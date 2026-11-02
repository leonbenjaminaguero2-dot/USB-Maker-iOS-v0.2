import Foundation

enum CreationPhase { case copying, verifying }

struct CreationProgress {
    let copied: Int64       // work units completed: writing + verification
    let total: Int64        // 2x payload bytes (write + read back)
    let bytesPerSecond: Double
    let phase: CreationPhase
    var fraction: Double { total > 0 ? min(1, Double(copied) / Double(total)) : 0 }
    var remainingSeconds: TimeInterval? {
        bytesPerSecond > 1000 ? TimeInterval(max(0, total - copied)) / bytesPerSecond : nil
    }
}

enum CreationError: LocalizedError {
    case cancelled, notEmpty, formatUnknown, notFAT, insufficientSpace, sourceMissing, destinationMissing, changedSource, corruptedWrite, concurrent
    var errorDescription: String? {
        switch self {
        case .cancelled: return "Se canceló la creación. Se retirarán los archivos escritos por BootMaker."
        case .notEmpty: return "El destino no está vacío. Usá la raíz de un USB FAT32 vacío para no sobrescribir archivos."
        case .formatUnknown: return "No se pudo verificar que la unidad tenga formato FAT32. Abrila directamente desde Ubicaciones en Archivos; no se admite escribir en iCloud."
        case .notFAT: return "El destino no parece ser FAT/FAT32. Este método UEFI requiere ese sistema de archivos."
        case .insufficientSpace: return "No hay espacio libre suficiente para extraer esta ISO."
        case .sourceMissing: return "No se pudo abrir la ISO. Descargala completamente en Archivos antes de empezar."
        case .destinationMissing: return "No se pudo escribir en el destino. Comprobá el adaptador USB y los permisos de Archivos."
        case .changedSource: return "La ISO cambió desde que fue verificada. Volvé a seleccionarla."
        case .corruptedWrite: return "La verificación falló: los datos escritos no coinciden con los de la ISO. No se puede dar por terminado el USB."
        case .concurrent: return "Ya hay una creación de USB en curso."
        }
    }
}

/// Writes the actual extracted files in ISO 9660 images to an existing FAT USB volume.
/// This prepares *UEFI removable-media file layout*, not partitions or raw device blocks.
/// Does NOT support UDF, Windows WIM splitting, BIOS/Legacy or images needing an ISO block layout.
final class UEFICreationService {
    private let lock = NSLock()
    private var cancelRequested = false
    private var running = false
    private let queue = DispatchQueue(label: "bootmaker.uefi.writer", qos: .userInitiated)

    func cancel() { lock.lock(); cancelRequested = true; lock.unlock() }
    private func cancelled() -> Bool { lock.lock(); defer { lock.unlock() }; return cancelRequested }

    func create(source: URL, destinationFolder: URL,
                onProgress: @escaping (CreationProgress) -> Void,
                completion: @escaping (Result<ISOImage, Error>) -> Void) {
        lock.lock()
        if running {
            lock.unlock()
            DispatchQueue.main.async { completion(.failure(CreationError.concurrent)) }
            return
        }
        running = true
        cancelRequested = false
        lock.unlock()

        queue.async { [self] in
            let hasSource = source.startAccessingSecurityScopedResource()
            let hasFolder = destinationFolder.startAccessingSecurityScopedResource()
            defer {
                if hasSource { source.stopAccessingSecurityScopedResource() }
                if hasFolder { destinationFolder.stopAccessingSecurityScopedResource() }
                lock.lock(); running = false; lock.unlock()
            }
            var createdPaths = [URL]()
            do {
                guard FileManager.default.fileExists(atPath: source.path) else { throw CreationError.sourceMissing }
                guard FileManager.default.fileExists(atPath: destinationFolder.path) else { throw CreationError.destinationMissing }
                let sourceValues = try source.resourceValues(forKeys: [.fileSizeKey])
                let image = try ISO9660Reader(url: source).inspect()
                if let fileSize = sourceValues.fileSize {
                    guard Int64(fileSize) == image.fileLength else { throw CreationError.changedSource }
                }
                try verifyDestination(folder: destinationFolder, spaceNeeded: image.bytesToCopy)
                let reader = try FileHandle(forReadingFrom: source)
                defer { try? reader.close() }

                // No existing data is overwritten, and a failed run removes only its own files.
                let folders = image.entries.filter { $0.isDirectory }.sorted { $0.relativePath.count < $1.relativePath.count }
                for entry in folders {
                    if cancelled() { throw CreationError.cancelled }
                    let target = destinationFolder.appendingPathComponent(entry.relativePath, isDirectory: true)
                    try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
                    createdPaths.append(target)
                }
                let start = ProcessInfo.processInfo.systemUptime
                var lastReport = start
                var transferred: Int64 = 0
                let totalWork = image.bytesToCopy * 2
                for entry in image.entries where !entry.isDirectory {
                    if cancelled() { throw CreationError.cancelled }
                    let outputURL = destinationFolder.appendingPathComponent(entry.relativePath)
                    if FileManager.default.fileExists(atPath: outputURL.path) { throw CreationError.notEmpty }
                    let parent = outputURL.deletingLastPathComponent()
                    if !FileManager.default.fileExists(atPath: parent.path) {
                        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
                        createdPaths.append(parent)
                    }
                    guard FileManager.default.createFile(atPath: outputURL.path, contents: nil) else { throw CreationError.destinationMissing }
                    createdPaths.append(outputURL)
                    let output = try FileHandle(forWritingTo: outputURL)
                    do {
                        try reader.seek(toOffset: UInt64(entry.offset))
                        var remaining = entry.length
                        while remaining > 0 {
                            if cancelled() { throw CreationError.cancelled }
                            let chunk = Int(min(remaining, 1024 * 512))
                            let buffer = try reader.read(upToCount: chunk) ?? Data()
                            if buffer.count != chunk { throw CreationError.changedSource }
                            try output.write(contentsOf: buffer)
                            remaining -= Int64(chunk)
                            transferred += Int64(chunk)
                            let now = ProcessInfo.processInfo.systemUptime
                            if now - lastReport > 0.2 || transferred == image.bytesToCopy {
                                let elapsed = max(0.1, now - start)
                                let snapshot = CreationProgress(copied: transferred, total: totalWork,
                                                                bytesPerSecond: Double(transferred) / elapsed,
                                                                phase: .copying)
                                DispatchQueue.main.async { onProgress(snapshot) }
                                lastReport = now
                            }
                        }
                        try output.synchronize()
                        try output.close()
                    } catch {
                        try? output.close()
                        throw error
                    }
                    let actual = Int64((try FileManager.default.attributesOfItem(atPath: outputURL.path)[.size] as? NSNumber)?.int64Value ?? -1)
                    guard actual == entry.length else { throw CreationError.corruptedWrite }
                }
                // Read every written byte back. Correct size alone does not prove integrity.
                let verificationStart = ProcessInfo.processInfo.systemUptime
                var verificationReport = verificationStart
                var checked: Int64 = 0
                for entry in image.entries where !entry.isDirectory {
                    if cancelled() { throw CreationError.cancelled }
                    let outputURL = destinationFolder.appendingPathComponent(entry.relativePath)
                    let checkHandle = try FileHandle(forReadingFrom: outputURL)
                    do {
                        try reader.seek(toOffset: UInt64(entry.offset))
                        var remaining = entry.length
                        while remaining > 0 {
                            if cancelled() { throw CreationError.cancelled }
                            let chunk = Int(min(remaining, 1024 * 512))
                            let original = try reader.read(upToCount: chunk) ?? Data()
                            let written = try checkHandle.read(upToCount: chunk) ?? Data()
                            guard original.count == chunk, written == original else { throw CreationError.corruptedWrite }
                            remaining -= Int64(chunk)
                            checked += Int64(chunk)
                            let now = ProcessInfo.processInfo.systemUptime
                            if now - verificationReport > 0.2 || checked == image.bytesToCopy {
                                let elapsed = max(0.1, now - verificationStart)
                                let snapshot = CreationProgress(copied: image.bytesToCopy + checked,
                                                                total: totalWork,
                                                                bytesPerSecond: Double(checked) / elapsed,
                                                                phase: .verifying)
                                DispatchQueue.main.async { onProgress(snapshot) }
                                verificationReport = now
                            }
                        }
                        try checkHandle.close()
                    } catch {
                        try? checkHandle.close()
                        throw error
                    }
                }
                let bootURL = destinationFolder.appendingPathComponent(image.bootloader)
                guard FileManager.default.fileExists(atPath: bootURL.path) else { throw CreationError.corruptedWrite }
                DispatchQueue.main.async { completion(.success(image)) }
            } catch {
                // Delete only paths created by this run, deepest-first.
                for path in createdPaths.reversed() { try? FileManager.default.removeItem(at: path) }
                DispatchQueue.main.async { completion(.failure(error)) }
            }
        }
    }

    /// Validate the actual selected folder before enabling the next step.
    /// This does NOT discover USB devices or prove the folder is a physical USB root.
    func inspectDestination(folder: URL, completion: @escaping (Result<String, Error>) -> Void) {
        queue.async { [self] in
            let scoped = folder.startAccessingSecurityScopedResource()
            defer { if scoped { folder.stopAccessingSecurityScopedResource() } }
            do {
                try verifyDestination(folder: folder, spaceNeeded: 0)
                let values = try folder.resourceValues(forKeys: [.volumeLocalizedFormatDescriptionKey])
                let format = values.volumeLocalizedFormatDescription ?? "FAT"
                DispatchQueue.main.async { completion(.success(format)) }
            } catch {
                DispatchQueue.main.async { completion(.failure(error)) }
            }
        }
    }

    func inspect(source: URL, completion: @escaping (Result<ISOImage, Error>) -> Void) {
        queue.async {
            let scoped = source.startAccessingSecurityScopedResource()
            defer { if scoped { source.stopAccessingSecurityScopedResource() } }
            do { let image = try ISO9660Reader(url: source).inspect(); DispatchQueue.main.async { completion(.success(image)) } }
            catch { DispatchQueue.main.async { completion(.failure(error)) } }
        }
    }

    private func verifyDestination(folder: URL, spaceNeeded: Int64) throws {
        let values = try folder.resourceValues(forKeys: [.volumeLocalizedFormatDescriptionKey, .volumeAvailableCapacityKey, .isDirectoryKey])
        guard values.isDirectory == true else { throw CreationError.destinationMissing }
        // Foundation's format description is supplied by the mounted volume. Reject unknown formats.
        guard let format = values.volumeLocalizedFormatDescription?.lowercased() else { throw CreationError.formatUnknown }
        guard format.contains("fat32") || format.contains("fat 32") || format.contains("ms-dos") || format == "fat" else {
            throw CreationError.notFAT
        }
        if let capacity = values.volumeAvailableCapacity, Int64(capacity) < spaceNeeded + 32 * 1024 * 1024 {
            throw CreationError.insufficientSpace
        }
        let present = try FileManager.default.contentsOfDirectory(atPath: folder.path)
        guard present.isEmpty else { throw CreationError.notEmpty }
        // Verify write permission on this exact security-scoped directory.
        let probe = folder.appendingPathComponent(".bootmaker-write-test")
        let testBytes = Data("BootMaker write permission test".utf8)
        do { try testBytes.write(to: probe, options: .atomic); try FileManager.default.removeItem(at: probe) }
        catch { try? FileManager.default.removeItem(at: probe); throw CreationError.destinationMissing }
    }
}
