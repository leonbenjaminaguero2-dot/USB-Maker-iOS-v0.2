import Foundation

/// Minimal read-only ISO 9660 / Joliet directory reader. Does not support UDF,
/// Rock Ridge-specific links, compressed images, IMG disk images or multi-extent files.
/// Zero third-party dependencies. Runs equally on iOS and macOS/Linux for tests.
struct ISOFile: Equatable {
    let relativePath: String
    let offset: Int64
    let length: Int64
    let isDirectory: Bool
}

struct ISOImage {
    let entries: [ISOFile]
    let volumeLabel: String
    let fileLength: Int64
    let bootloader: String

    var bytesToCopy: Int64 { entries.filter { !$0.isDirectory }.reduce(0) { $0 + $1.length } }
    var fileCount: Int { entries.filter { !$0.isDirectory }.count }
}

enum ISOIssue: LocalizedError {
    case unsupported, damaged, unsafeName, tooManyFiles, missingBootloader, largeFile(String), invalidBootloader
    var errorDescription: String? {
        switch self {
        case .unsupported: return "Esta imagen no tiene un sistema ISO 9660/Joliet compatible. Las ISO UDF y las IMG de disco completo todavía no están admitidas."
        case .damaged: return "La estructura de esta ISO es inválida o está incompleta."
        case .unsafeName: return "La ISO contiene nombres o rutas de archivo no seguros."
        case .tooManyFiles: return "La ISO contiene demasiados archivos o directorios para procesarla con seguridad."
        case .missingBootloader: return "La ISO no contiene EFI/BOOT/BOOTX64.EFI ni EFI/BOOT/BOOTAA64.EFI. No se creará un USB que no tenga cargador UEFI."
        case .largeFile(let name): return "El archivo ‘\(name)’ supera 4 GiB. FAT32 no admite ese tamaño. La app no divide archivos WIM automáticamente."
        case .invalidBootloader: return "El cargador EFI no es una aplicación PE/COFF UEFI válida para x64 o ARM64."
        }
    }
}

final class ISO9660Reader {
    private let sector: Int64 = 2048
    private let handle: FileHandle
    private let fileSize: Int64
    private var joliet = false
    private var visited = Set<String>()
    private var entries = [ISOFile]()

    init(url: URL) throws {
        handle = try FileHandle(forReadingFrom: url)
        fileSize = Int64((try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.int64Value ?? 0)
    }

    deinit { try? handle.close() }

    private func bytes(at offset: Int64, count: Int) throws -> Data {
        guard count >= 0, offset >= 0, Int64(count) <= fileSize - offset else { throw ISOIssue.damaged }
        try handle.seek(toOffset: UInt64(offset))
        let result = try handle.read(upToCount: count) ?? Data()
        guard result.count == count else { throw ISOIssue.damaged }
        return result
    }

    private func u32(_ d: Data, _ at: Int) throws -> UInt32 {
        guard at >= 0, d.count >= at + 4 else { throw ISOIssue.damaged }
        return d[at..<(at + 4)].enumerated().reduce(UInt32(0)) {
            $0 | (UInt32($1.element) << UInt32($1.offset * 8))
        }
    }

    private struct Record {
        let name: String
        let start: Int64
        let size: Int64
        let isDirectory: Bool
        let multiExtent: Bool
    }

    private func record(_ bytes: Data, at position: Int) throws -> Record? {
        guard position < bytes.count else { throw ISOIssue.damaged }
        let length = Int(bytes[position])
        guard length >= 34, position + length <= bytes.count else { throw ISOIssue.damaged }
        let idLength = Int(bytes[position + 32])
        guard idLength > 0, 33 + idLength <= length else { throw ISOIssue.damaged }
        let rawName = Data(bytes[(position + 33)..<(position + 33 + idLength)])
        if rawName == Data([0]) || rawName == Data([1]) { return nil }
        var name: String
        if joliet {
            guard idLength.isMultiple(of: 2) else { throw ISOIssue.damaged }
            let units = stride(from: 0, to: rawName.count, by: 2).map {
                (UInt16(rawName[$0]) << 8) | UInt16(rawName[$0 + 1])
            }
            name = String(decoding: units, as: UTF16.self)
        } else {
            name = String(data: rawName, encoding: .ascii) ?? ""
        }
        if let semicolon = name.lastIndex(of: ";") { name = String(name[..<semicolon]) }
        if name.hasSuffix(".") { name.removeLast() }
        // FAT filenames must be portable and cannot alias reserved DOS device names.
        let forbidden = CharacterSet(charactersIn: "\\/:*?\"<>|")
        let reserved = Set(["CON", "PRN", "AUX", "NUL"] +
                           (1...9).map { "COM\($0)" } + (1...9).map { "LPT\($0)" })
        let stem = String(name.split(separator: ".", omittingEmptySubsequences: false).first ?? "").uppercased()
        guard !name.isEmpty, name != ".", name != "..", !name.hasPrefix("."),
              !name.hasSuffix(" "), !name.hasSuffix("."),
              name.rangeOfCharacter(from: forbidden.union(.controlCharacters)) == nil,
              !reserved.contains(stem), name.utf8.count <= 220 else { throw ISOIssue.unsafeName }
        let start = Int64(try u32(bytes, position + 2)) * sector
        let length64 = Int64(try u32(bytes, position + 10))
        guard start >= 0, length64 >= 0, start <= fileSize, length64 <= fileSize - start else { throw ISOIssue.damaged }
        let flags = bytes[position + 25]
        return Record(name: name, start: start, size: length64,
                      isDirectory: (flags & 0x02) != 0, multiExtent: (flags & 0x80) != 0)
    }

    private func walk(directoryStart: Int64, directorySize: Int64, path: String, depth: Int) throws {
        guard depth <= 24, directorySize <= 32 * 1024 * 1024 else { throw ISOIssue.tooManyFiles }
        let key = "\(directoryStart):\(directorySize)"
        guard visited.insert(key).inserted else { return }
        let contents = try bytes(at: directoryStart, count: Int(directorySize))
        var cursor = 0
        while cursor < contents.count {
            let recordLength = Int(contents[cursor])
            if recordLength == 0 {
                cursor = ((cursor / Int(sector)) + 1) * Int(sector)
                continue
            }
            let rec = try record(contents, at: cursor)
            cursor += recordLength
            guard let rec else { continue }
            guard !rec.multiExtent else { throw ISOIssue.unsupported }
            let relative = path.isEmpty ? rec.name : path + "/" + rec.name
            entries.append(ISOFile(relativePath: relative, offset: rec.start,
                                   length: rec.size, isDirectory: rec.isDirectory))
            guard entries.count <= 25000 else { throw ISOIssue.tooManyFiles }
            if rec.isDirectory {
                try walk(directoryStart: rec.start, directorySize: rec.size, path: relative, depth: depth + 1)
            }
        }
    }

    func inspect() throws -> ISOImage {
        guard fileSize >= 18 * sector else { throw ISOIssue.unsupported }
        var primary: Data?
        var supplementary: Data?
        for index in 16..<80 {
            guard Int64(index + 1) * sector <= fileSize else { break }
            let d = try bytes(at: Int64(index) * sector, count: Int(sector))
            guard d.subdata(in: 1..<6) == Data("CD001".utf8), d[6] == 1 else { throw ISOIssue.unsupported }
            if d[0] == 1 && primary == nil { primary = d }
            if d[0] == 2 && supplementary == nil {
                let esc = Array(d[88..<91])
                if esc == [0x25, 0x2F, 0x40] || esc == [0x25, 0x2F, 0x43] || esc == [0x25, 0x2F, 0x45] {
                    supplementary = d
                }
            }
            if d[0] == 255 { break }
        }
        guard let volume = supplementary ?? primary else { throw ISOIssue.unsupported }
        joliet = supplementary != nil
        guard volume[128] == 0 && volume[129] == 8 else { throw ISOIssue.unsupported }
        guard let root = try recordRoot(volume) else { throw ISOIssue.damaged }
        let label = String(data: volume[40..<72], encoding: .ascii)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "ISO"
        try walk(directoryStart: root.start, directorySize: root.size, path: "", depth: 0)
        var names = Set<String>()
        for entry in entries {
            let normal = entry.relativePath.lowercased()
            guard names.insert(normal).inserted else { throw ISOIssue.unsafeName }
            if !entry.isDirectory && entry.length > 4_294_967_295 {
                throw ISOIssue.largeFile(entry.relativePath)
            }
        }
        let loaders = ["efi/boot/bootx64.efi", "efi/boot/bootaa64.efi"]
        guard let boot = entries.first(where: { !($0.isDirectory) && loaders.contains($0.relativePath.lowercased()) }) else {
            throw ISOIssue.missingBootloader
        }
        // Check actual EFI PE/COFF machine and subsystem, not just MZ/PE magic.
        // MZ+PE can be an ordinary Windows EXE, which is NOT a UEFI bootloader.
        guard boot.length >= 256 else { throw ISOIssue.invalidBootloader }
        let header = try bytes(at: boot.offset, count: Int(min(boot.length, 4096)))
        guard header.prefix(2) == Data([0x4d, 0x5a]), header.count >= 64 else { throw ISOIssue.invalidBootloader }
        let peOffset = Int(try u32(header, 0x3c))
        guard peOffset >= 0x40, peOffset <= header.count - 96,
              Data(header[peOffset..<(peOffset + 4)]) == Data([0x50, 0x45, 0, 0]) else {
            throw ISOIssue.invalidBootloader
        }
        let machine = UInt16(header[peOffset + 4]) | (UInt16(header[peOffset + 5]) << 8)
        let isX64Path = boot.relativePath.lowercased().hasSuffix("bootx64.efi")
        guard machine == (isX64Path ? 0x8664 : 0xAA64) else { throw ISOIssue.invalidBootloader }
        let optionalSize = Int(header[peOffset + 20]) | (Int(header[peOffset + 21]) << 8)
        let optionalStart = peOffset + 24
        guard optionalSize >= 70, optionalStart + optionalSize <= header.count,
              optionalStart + optionalSize <= Int(boot.length) else { throw ISOIssue.invalidBootloader }
        let magic = UInt16(header[optionalStart]) | (UInt16(header[optionalStart + 1]) << 8)
        guard magic == 0x20b || magic == 0x10b else { throw ISOIssue.invalidBootloader }
        let subsystem = UInt16(header[optionalStart + 68]) | (UInt16(header[optionalStart + 69]) << 8)
        guard subsystem == 10 else { throw ISOIssue.invalidBootloader } // IMAGE_SUBSYSTEM_EFI_APPLICATION
        return ISOImage(entries: entries, volumeLabel: label, fileLength: fileSize, bootloader: boot.relativePath)
    }

    private func recordRoot(_ volume: Data) throws -> (start: Int64, size: Int64)? {
        let start = Int64(try u32(volume, 158)) * sector // 156 is the embedded record; extent at +2
        let count = Int64(try u32(volume, 166))
        guard count > 0, start >= 0, start <= fileSize, count <= fileSize - start else { return nil }
        return (start, count)
    }
}
