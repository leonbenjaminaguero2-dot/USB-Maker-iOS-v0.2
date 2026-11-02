import Foundation

@main
struct ISOReaderTest {
    static func main() {
        guard CommandLine.arguments.count >= 2 else {
            fputs("Uso: ISOReaderTest archivo.iso [--expect-failure]\n", stderr)
            exit(2)
        }
        let expectFailure = CommandLine.arguments.contains("--expect-failure")
        do {
            let image = try ISO9660Reader(url: URL(fileURLWithPath: CommandLine.arguments[1])).inspect()
            if expectFailure {
                fputs("ERROR: se aceptó una ISO deliberadamente dañada\n", stderr)
                exit(1)
            }
            guard image.bootloader.lowercased() == "efi/boot/bootx64.efi",
                  image.fileCount == 2,
                  image.bytesToCopy == 2058,
                  image.entries.contains(where: { $0.relativePath == "EFI/BOOT/BOOTX64.EFI" }) else {
                fputs("ERROR: el lector devolvió contenido incorrecto\n", stderr)
                exit(1)
            }
            print("OK: ISO9660 validada: \(image.fileCount) archivos, loader \(image.bootloader)")
        } catch {
            guard expectFailure else {
                fputs("ERROR inesperado: \(error.localizedDescription)\n", stderr)
                exit(1)
            }
            print("OK: imagen rechazada: \(error.localizedDescription)")
        }
    }
}
