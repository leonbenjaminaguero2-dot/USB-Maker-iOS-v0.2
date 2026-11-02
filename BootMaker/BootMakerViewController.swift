import UIKit
import UniformTypeIdentifiers

final class BootMakerViewController: UIViewController, UIDocumentPickerDelegate {
    private enum Stage: Int { case usb = 0, iso = 1, create = 2 }
    private enum PickerPurpose { case usb, iso }
    private var pickerPurpose: PickerPurpose = .usb
    private enum CreateState { case ready, writing, success, failure(String) }
    private enum ISOState { case none, checking, ready(ISOImage), unsupported(String) }
    private enum USBState { case none, checking, ready(String), invalid(String) }

    private var stage: Stage = .usb
    private var selectedFolder: URL?
    private var selectedISO: URL?
    private var createState: CreateState = .ready
    private var isoState: ISOState = .none
    private var usbState: USBState = .none
    private let creator = UEFICreationService()
    private var latestSnapshot: CreationProgress?

    private let scroll = UIScrollView()
    private let content = UIStackView(axis: .vertical, spacing: 25)
    private let bottom = UIStackView(axis: .horizontal, spacing: 12)
    private let pageTitle = Theme.label("", size: 30, weight: .bold)

    override var preferredStatusBarStyle: UIStatusBarStyle { .lightContent }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Theme.background
        setupLayout()
        render()
    }

    private func setupLayout() {
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.alwaysBounceVertical = true
        scroll.showsVerticalScrollIndicator = false
        view.addSubview(scroll)
        scroll.addSubview(content)
        content.alignment = .fill
        bottom.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(bottom)
        NSLayoutConstraint.activate([
            bottom.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 20),
            bottom.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -20),
            bottom.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -20),
            bottom.heightAnchor.constraint(equalToConstant: 60),
            scroll.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
            scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: bottom.topAnchor, constant: -15),
            content.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor, constant: 8),
            content.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor, constant: 20),
            content.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor, constant: -20),
            content.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor, constant: -22),
            content.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor, constant: -40)
        ])
    }

    private func clear(_ stack: UIStackView) {
        stack.arrangedSubviews.forEach { view in
            stack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
    }

    private func render() {
        clear(content)
        clear(bottom)
        content.addArrangedSubview(makeHeader())
        content.addArrangedSubview(makeStages())
        switch stage {
        case .usb: content.addArrangedSubview(makeUSBPanel())
        case .iso: content.addArrangedSubview(makeISOPanel())
        case .create: content.addArrangedSubview(makeCreatePanel())
        }
        makeFooter()
    }

    private func makeHeader() -> UIView {
        let header = UIStackView(axis: .horizontal, spacing: 13, alignment: .center)
        let icon = UIImageView(image: UIImage(systemName: "externaldrive.fill", withConfiguration: UIImage.SymbolConfiguration(pointSize: 27, weight: .medium)))
        icon.tintColor = .white
        icon.contentMode = .center
        icon.backgroundColor = Theme.purple
        Theme.rounded(icon, radius: 18)
        icon.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([icon.widthAnchor.constraint(equalToConstant: 62), icon.heightAnchor.constraint(equalToConstant: 62)])

        let titles = UIStackView(axis: .vertical, spacing: 4)
        titles.addArrangedSubview(Theme.label("BootMaker", size: 29, weight: .heavy))
        titles.addArrangedSubview(Theme.label("Crea un USB de arranque desde tu iPhone", size: 12, color: Theme.muted, lines: 2))
        header.addArrangedSubview(icon)
        header.addArrangedSubview(titles)
        let info = UIButton(type: .system)
        info.setImage(UIImage(systemName: "info.circle", withConfiguration: UIImage.SymbolConfiguration(pointSize: 24)), for: .normal)
        info.tintColor = Theme.lightPurple
        info.addTarget(self, action: #selector(infoTapped), for: .touchUpInside)
        info.accessibilityLabel = "Información y limitaciones"
        header.addArrangedSubview(info)
        info.widthAnchor.constraint(equalToConstant: 36).isActive = true
        return header
    }

    private func makeStages() -> UIView {
        let row = UIStackView(axis: .horizontal, spacing: 0, alignment: .center)
        let stages = ["USB", "ISO", "Crear"]
        for index in 0..<3 {
            let column = UIStackView(axis: .vertical, spacing: 7, alignment: .center)
            let active = index <= stage.rawValue
            let circle = UIView()
            circle.backgroundColor = active ? Theme.purple : Theme.raised
            Theme.rounded(circle, radius: 22, stroke: active ? Theme.lightPurple : Theme.outline)
            circle.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([circle.widthAnchor.constraint(equalToConstant: 44), circle.heightAnchor.constraint(equalToConstant: 44)])
            let numberText = index < stage.rawValue ? "✓" : "\(index + 1)"
            let number = Theme.label(numberText, size: 18, weight: .bold, color: active ? .white : Theme.muted)
            number.textAlignment = .center
            circle.pin(number)
            column.addArrangedSubview(circle)
            let caption = Theme.label(stages[index], size: 12, weight: active ? .bold : .medium,
                                      color: active ? Theme.lightPurple : Theme.muted)
            column.addArrangedSubview(caption)
            row.addArrangedSubview(column)
            column.widthAnchor.constraint(equalToConstant: 65).isActive = true
            if index < 2 {
                let separator = UIView()
                separator.backgroundColor = index < stage.rawValue ? Theme.purple : Theme.outline
                separator.translatesAutoresizingMaskIntoConstraints = false
                separator.heightAnchor.constraint(equalToConstant: 2).isActive = true
                row.addArrangedSubview(separator)
            }
        }
        return row
    }

    private func card(title: String, subtitle: String, symbol: String) -> UIStackView {
        let outer = UIStackView(axis: .vertical, spacing: 18)
        outer.isLayoutMarginsRelativeArrangement = true
        outer.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 23, leading: 18, bottom: 24, trailing: 18)
        outer.backgroundColor = Theme.card
        Theme.rounded(outer, radius: 25, stroke: Theme.outline)
        let line = UIStackView(axis: .horizontal, spacing: 14, alignment: .center)
        let picture = Theme.symbol(symbol, size: 29, color: Theme.lightPurple)
        let block = UIStackView(axis: .vertical, spacing: 8)
        block.addArrangedSubview(Theme.label(title, size: 24, weight: .bold, lines: 2))
        block.addArrangedSubview(Theme.label(subtitle, size: 14, color: Theme.muted, lines: 0))
        line.addArrangedSubview(picture)
        picture.widthAnchor.constraint(equalToConstant: 39).isActive = true
        line.addArrangedSubview(block)
        outer.addArrangedSubview(line)
        return outer
    }

    private func insetRow(symbol: String, title: String, detail: String, color: UIColor = Theme.purple) -> UIView {
        let line = UIStackView(axis: .horizontal, spacing: 14, alignment: .center)
        line.isLayoutMarginsRelativeArrangement = true
        line.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 17, leading: 15, bottom: 17, trailing: 15)
        line.backgroundColor = Theme.raised
        Theme.rounded(line, radius: 16, stroke: color.withAlphaComponent(0.45))
        line.addArrangedSubview(Theme.symbol(symbol, size: 25, color: Theme.lightPurple))
        let textStack = UIStackView(axis: .vertical, spacing: 5)
        textStack.addArrangedSubview(Theme.label(title, size: 16, weight: .semibold, lines: 2))
        textStack.addArrangedSubview(Theme.label(detail, size: 12, color: Theme.muted, lines: 0))
        line.addArrangedSubview(textStack)
        return line
    }

    private func miniButton(_ title: String, icon: String, selector: Selector) -> UIButton {
        let button = UIButton(type: .system)
        var style = UIButton.Configuration.filled()
        style.title = title
        style.image = UIImage(systemName: icon)
        style.imagePadding = 9
        style.baseBackgroundColor = Theme.purple
        style.baseForegroundColor = .white
        style.cornerStyle = .large
        style.contentInsets = NSDirectionalEdgeInsets(top: 13, leading: 14, bottom: 13, trailing: 14)
        button.configuration = style
        button.titleLabel?.font = .systemFont(ofSize: 14, weight: .bold)
        button.addTarget(self, action: selector, for: .touchUpInside)
        return button
    }

    private func makeUSBPanel() -> UIView {
        let panel = card(title: "Conectar USB", subtitle: "Conectá el pendrive y elegí su carpeta raíz en Archivos. Debe estar vacío y en formato FAT32.", symbol: "cable.connector")
        let illustration = makeIllustration()
        panel.addArrangedSubview(illustration)
        if let folder = selectedFolder {
            switch usbState {
            case .ready(let format):
                panel.addArrangedSubview(insetRow(symbol: "checkmark.circle.fill", title: folder.lastPathComponent,
                    detail: "Destino FAT accesible y vacío · \(format) · ubicación física sin confirmar", color: Theme.green))
            case .checking:
                panel.addArrangedSubview(insetRow(symbol: "hourglass", title: "Comprobando destino…",
                    detail: "Verificando formato, espacio, permisos y contenido."))
            case .invalid(let message):
                panel.addArrangedSubview(insetRow(symbol: "xmark.octagon", title: "Destino no válido",
                    detail: message, color: Theme.warning))
            case .none: break
            }
        } else {
            panel.addArrangedSubview(insetRow(symbol: "externaldrive", title: "No seleccionaste el USB",
                                            detail: "Seleccioná la carpeta raíz del pendrive en Archivos."))
        }
        panel.addArrangedSubview(miniButton("Elegir carpeta del USB", icon: "folder.badge.plus", selector: #selector(chooseUSB)))
        let hint = hintBox("En Archivos, buscá tu memoria en ‘Ubicaciones’. Si no aparece, comprobá el adaptador y la alimentación USB. En iPhone con Lightning, BootMaker no puede reformatearlo.")
        panel.addArrangedSubview(hint)
        return panel
    }

    private func makeIllustration() -> UIView {
        let holder = UIView()
        holder.translatesAutoresizingMaskIntoConstraints = false
        holder.heightAnchor.constraint(equalToConstant: 156).isActive = true
        let group = UIStackView(axis: .horizontal, spacing: 18, alignment: .center)
        group.translatesAutoresizingMaskIntoConstraints = false
        holder.addSubview(group)
        NSLayoutConstraint.activate([group.centerXAnchor.constraint(equalTo: holder.centerXAnchor),
                                     group.centerYAnchor.constraint(equalTo: holder.centerYAnchor)])
        group.addArrangedSubview(Theme.symbol("iphone.gen3", size: 67, color: Theme.lightPurple))
        group.addArrangedSubview(Theme.symbol("arrow.right", size: 23, color: Theme.purple))
        group.addArrangedSubview(Theme.symbol("externaldrive.fill", size: 67, color: Theme.lightPurple))
        return holder
    }

    private func makeISOPanel() -> UIView {
        let panel = card(title: "Seleccionar ISO", subtitle: "Elegí una imagen ISO que incluya archivos de arranque UEFI (x64 o ARM64).", symbol: "doc.zipper")
        if let file = selectedISO {
            let size: Int64
            if case .ready(let image) = isoState {
                size = image.fileLength
            } else {
                size = (try? FileManager.default.attributesOfItem(atPath: file.path)[.size] as? NSNumber)?.int64Value ?? 0
            }
            panel.addArrangedSubview(insetRow(symbol: "doc.fill", title: file.lastPathComponent,
                                            detail: "\(ByteCountFormatter.string(fromByteCount: size, countStyle: .file)) · archivo seleccionado"))
        } else {
            panel.addArrangedSubview(insetRow(symbol: "doc.badge.plus", title: "No seleccionaste una ISO",
                                            detail: "Elegí una ISO real; no hay archivos precargados."))
        }
        panel.addArrangedSubview(miniButton("Elegir ISO desde Archivos", icon: "doc.badge.plus", selector: #selector(chooseISO)))
        switch isoState {
        case .checking:
            panel.addArrangedSubview(hintBox("Analizando la estructura de la ISO y buscando el cargador de arranque UEFI…"))
        case .ready(let image):
            panel.addArrangedSubview(insetRow(symbol: "checkmark.shield.fill", title: "ISO UEFI reconocida", detail: "\(image.fileCount) archivos · Cargador: \(image.bootloader)", color: Theme.green))
        case .unsupported(let message):
            panel.addArrangedSubview(insetRow(symbol: "exclamationmark.triangle.fill", title: "ISO no compatible", detail: message, color: Theme.warning))
        case .none: break
        }
        panel.addArrangedSubview(warningBox())
        return panel
    }

    private func warningBox() -> UIView {
        let box = UIStackView(axis: .vertical, spacing: 10)
        box.isLayoutMarginsRelativeArrangement = true
        box.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 16, leading: 16, bottom: 16, trailing: 16)
        box.backgroundColor = Theme.warning.withAlphaComponent(0.10)
        Theme.rounded(box, radius: 16, stroke: Theme.warning)
        let title = UIStackView(axis: .horizontal, spacing: 10, alignment: .center)
        title.addArrangedSubview(Theme.symbol("exclamationmark.triangle.fill", size: 20, color: Theme.warning))
        title.addArrangedSubview(Theme.label("Advertencias", size: 19, weight: .bold, color: Theme.warning))
        box.addArrangedSubview(title)
        for item in [
            "• Si reformateás el USB, se eliminarán todos sus datos.",
            "• El proceso puede tardar varios minutos.",
            "• No desconectes el USB durante la creación."
        ] {
            box.addArrangedSubview(Theme.label(item, size: 13, color: .white, lines: 0))
        }
        return box
    }

    private func makeCreatePanel() -> UIView {
        let panel = card(title: "Crear USB UEFI", subtitle: "Extrae los archivos de arranque de la ISO y los escribe en tu pendrive FAT32.", symbol: "externaldrive.badge.checkmark")
        if let file = selectedISO {
            panel.addArrangedSubview(insetRow(symbol: "doc.fill", title: file.lastPathComponent, detail: "Imagen de origen"))
        }
        if let folder = selectedFolder {
            panel.addArrangedSubview(insetRow(symbol: "externaldrive.fill", title: folder.lastPathComponent, detail: "Destino seleccionado en Archivos"))
        }
        if case .ready(let image) = isoState {
            panel.addArrangedSubview(hintBox("\(image.fileCount) archivos · \(bytes(image.bytesToCopy)) · UEFI (no Legacy/BIOS). Requiere un destino FAT vacío. No se formatea ni particiona el USB."))
        }
        switch createState {
        case .ready:
            panel.addArrangedSubview(Theme.label("El porcentaje y el tiempo restante se calcularán con la transferencia real, una vez que comience.", size: 13, color: Theme.muted, lines: 0))
        case .writing:
            let snapshot = latestSnapshot
            let progress = UIProgressView(progressViewStyle: .default)
            progress.progressTintColor = Theme.purple
            progress.trackTintColor = Theme.raised
            progress.progress = Float(snapshot?.fraction ?? 0)
            progress.transform = CGAffineTransform(scaleX: 1, y: 2.5)
            panel.addArrangedSubview(progress)
            let percent = Int((snapshot?.fraction ?? 0) * 100)
            let activity = snapshot?.phase == .verifying ? "Verificando USB" : "Creando USB"
            panel.addArrangedSubview(Theme.label("\(activity)… \(percent)%", size: 19, weight: .bold))
            if let s = snapshot {
                let speed = ByteCountFormatter.string(fromByteCount: Int64(s.bytesPerSecond), countStyle: .file)
                let eta = s.remainingSeconds.map { formatTime($0) } ?? "calculando…"
                let detail = s.phase == .verifying ? "Comprobando datos escritos" : "Extrayendo archivos de la ISO"
                panel.addArrangedSubview(Theme.label("\(detail) · \(speed)/s\nTiempo restante estimado: \(eta)", size: 13, color: Theme.muted, lines: 0))
            } else {
                panel.addArrangedSubview(Theme.label("Analizando espacio y preparando carpetas…", size: 13, color: Theme.muted))
            }
        case .success:
            panel.addArrangedSubview(insetRow(symbol: "checkmark.circle.fill", title: "Archivos UEFI escritos y verificados", detail: "Los archivos coinciden con la ISO y el cargador está presente. El arranque real debe comprobarse en una PC.", color: Theme.green))
        case .failure(let message):
            panel.addArrangedSubview(insetRow(symbol: "xmark.octagon.fill", title: "No se completó la creación", detail: message, color: Theme.warning))
        }
        return panel
    }

    private func hintBox(_ message: String) -> UIView {
        let box = UIStackView(axis: .horizontal, spacing: 10, alignment: .top)
        box.isLayoutMarginsRelativeArrangement = true
        box.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 13, leading: 13, bottom: 13, trailing: 13)
        box.backgroundColor = Theme.purple.withAlphaComponent(0.09)
        Theme.rounded(box, radius: 14, stroke: Theme.purple.withAlphaComponent(0.5))
        box.addArrangedSubview(Theme.symbol("info.circle", size: 18, color: Theme.lightPurple))
        box.addArrangedSubview(Theme.label(message, size: 13, color: Theme.lightPurple, lines: 0))
        return box
    }

    private func makeFooter() {
        if stage != .usb {
            let back = UIButton(type: .system)
            var style = UIButton.Configuration.bordered()
            style.title = "Atrás"
            style.baseForegroundColor = .white
            style.baseBackgroundColor = Theme.raised
            style.cornerStyle = .large
            back.configuration = style
            back.addTarget(self, action: #selector(previous), for: .touchUpInside)
            if case .writing = createState { back.isEnabled = false }
            bottom.addArrangedSubview(back)
            back.widthAnchor.constraint(equalTo: bottom.widthAnchor, multiplier: 0.29).isActive = true
        }
        let main = UIButton(type: .system)
        var style = UIButton.Configuration.filled()
        switch stage {
        case .usb:
            switch usbState {
            case .ready: style.title = "Siguiente  →"
            case .checking: style.title = "Comprobando USB…"
            case .none, .invalid: style.title = "Elegir USB"
            }
        case .iso:
            switch isoState {
            case .ready: style.title = "Siguiente  →"
            case .checking: style.title = "Analizando ISO…"
            case .none, .unsupported: style.title = "Elegir otra ISO"
            }
        case .create:
            switch createState {
            case .ready, .failure: style.title = "Crear USB  →"
            case .writing: style.title = "Cancelar"
            case .success: style.title = "Finalizar  ✓"
            }
        }
        style.baseBackgroundColor = Theme.purple
        style.baseForegroundColor = .white
        style.cornerStyle = .capsule
        main.configuration = style
        main.titleLabel?.font = .systemFont(ofSize: 18, weight: .bold)
        main.addTarget(self, action: #selector(nextTapped), for: .touchUpInside)
        if stage == .iso, case .checking = isoState { main.isEnabled = false }
        if stage == .usb, case .checking = usbState { main.isEnabled = false }
        bottom.addArrangedSubview(main)
    }

    private func bytes(_ count: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: count, countStyle: .file)
    }

    private func formatTime(_ seconds: TimeInterval) -> String {
        let count = max(0, Int(seconds))
        if count > 3600 { return "\(count / 3600) h \((count % 3600) / 60) min" }
        if count > 60 { return "\(count / 60) min \(count % 60) s" }
        return "\(count) s"
    }

    @objc private func previous() {
        guard stage.rawValue > 0 else { return }
        if case .writing = createState { return }
        stage = Stage(rawValue: stage.rawValue - 1) ?? .usb
        render()
    }

    @objc private func nextTapped() {
        switch stage {
        case .usb:
            guard case .ready = usbState else { chooseUSB(); return }
            stage = .iso
        case .iso:
            if case .ready = isoState { stage = .create }
            else { chooseISO(); return }
        case .create:
            switch createState {
            case .ready, .failure: confirmCreate()
            case .writing: creator.cancel()
            case .success:
                stage = .usb
                createState = .ready
                isoState = .none
                selectedISO = nil
                selectedFolder = nil
                usbState = .none
                latestSnapshot = nil
            }
        }
        render()
    }

    @objc private func chooseUSB() {
        if case .writing = createState { return }
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.folder], asCopy: false)
        picker.delegate = self
        picker.allowsMultipleSelection = false
        pickerPurpose = .usb
        present(picker, animated: true)
    }

    @objc private func chooseISO() {
        if case .writing = createState { return }
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.item], asCopy: false)
        picker.delegate = self
        picker.allowsMultipleSelection = false
        pickerPurpose = .iso
        present(picker, animated: true)
    }

    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        guard let url = urls.first else { return }
        if pickerPurpose == .usb {
            selectedFolder = url
            usbState = .checking
            createState = .ready
            stage = .usb
            creator.inspectDestination(folder: url) { [weak self] result in
                guard let self, self.selectedFolder == url else { return }
                switch result {
                case .success(let format): self.usbState = .ready(format)
                case .failure(let error): self.usbState = .invalid(error.localizedDescription)
                }
                self.render()
            }
        } else {
            let ext = url.pathExtension.lowercased()
            guard ext == "iso" else {
                showMessage("Archivo no compatible", "Seleccioná un archivo con extensión .iso. Los archivos .img de disco completo necesitan acceso a bloques que iOS no concede.")
                return
            }
            selectedISO = url
            isoState = .checking
            createState = .ready
            stage = .iso
            creator.inspect(source: url) { [weak self] result in
                guard let self, self.selectedISO == url else { return }
                switch result {
                case .success(let image): self.isoState = .ready(image)
                case .failure(let error): self.isoState = .unsupported(error.localizedDescription)
                }
                self.render()
            }
        }
        render()
    }

    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) { }

    private func confirmCreate() {
        guard let source = selectedISO, let folder = selectedFolder else { return }
        guard case .ready = isoState else { return }
        let alert = UIAlertController(
            title: "Crear USB UEFI",
            message: "BootMaker extraerá los archivos de ‘\(source.lastPathComponent)’ a la carpeta elegida. Debés haber seleccionado la RAÍZ de un pendrive FAT vacío. No se puede crear particiones ni formatear desde esta app, y algunas ISO no arrancarán aunque tengan cargador EFI. ¿Continuar?",
            preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Cancelar", style: .cancel))
        alert.addAction(UIAlertAction(title: "Crear USB", style: .default) { [weak self] _ in
            self?.beginCreation(source: source, folder: folder)
        })
        present(alert, animated: true)
    }

    private func beginCreation(source: URL, folder: URL) {
        createState = .writing
        latestSnapshot = nil
        render()
        creator.create(source: source, destinationFolder: folder, onProgress: { [weak self] snapshot in
            guard let self else { return }
            if case .writing = self.createState {
                self.latestSnapshot = snapshot
                self.render()
            }
        }, completion: { [weak self] result in
            guard let self else { return }
            switch result {
            case .success: self.createState = .success
            case .failure(let error): self.createState = .failure(error.localizedDescription)
            }
            self.render()
        })
    }

    @objc private func infoTapped() {
        showMessage("Qué hace BootMaker", "Esta versión intenta crear realmente la estructura de arranque UEFI extrayendo una ISO 9660/Joliet compatible a la raíz de un pendrive FAT32 vacío. No se limita a copiar el archivo .iso. iOS no permite a una IPA convencional modificar particiones o grabar bloques crudos. No es compatible con imágenes UDF, WIM de más de 4 GiB, algunas Linux ISO híbridas ni arranque Legacy/BIOS. El arranque final debe comprobarse en la PC.")
    }

    private func showMessage(_ title: String, _ message: String) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Entendido", style: .default))
        present(alert, animated: true)
    }
}
