import UIKit

enum Theme {
    static let background = UIColor(red: 0.047, green: 0.043, blue: 0.063, alpha: 1)
    static let card = UIColor(red: 0.106, green: 0.098, blue: 0.129, alpha: 1)
    static let raised = UIColor(red: 0.157, green: 0.145, blue: 0.184, alpha: 1)
    static let purple = UIColor(red: 0.630, green: 0.343, blue: 0.979, alpha: 1)
    static let lightPurple = UIColor(red: 0.789, green: 0.642, blue: 1, alpha: 1)
    static let muted = UIColor(red: 0.686, green: 0.666, blue: 0.737, alpha: 1)
    static let warning = UIColor(red: 1, green: 0.365, blue: 0.500, alpha: 1)
    static let green = UIColor(red: 0.341, green: 0.871, blue: 0.612, alpha: 1)
    static let outline = UIColor(red: 0.235, green: 0.211, blue: 0.274, alpha: 1)

    static func label(_ text: String, size: CGFloat, weight: UIFont.Weight = .regular, color: UIColor = .white, lines: Int = 0) -> UILabel {
        let label = UILabel()
        label.text = text
        label.font = .systemFont(ofSize: size, weight: weight)
        label.textColor = color
        label.numberOfLines = lines
        return label
    }

    static func symbol(_ name: String, size: CGFloat = 24, color: UIColor = .white) -> UIImageView {
        let view = UIImageView(image: UIImage(systemName: name, withConfiguration: UIImage.SymbolConfiguration(pointSize: size, weight: .medium)))
        view.tintColor = color
        view.contentMode = .scaleAspectFit
        view.setContentHuggingPriority(.required, for: .horizontal)
        return view
    }

    static func rounded(_ view: UIView, radius: CGFloat = 20, stroke: UIColor? = nil) {
        view.layer.cornerRadius = radius
        view.layer.cornerCurve = .continuous
        if let stroke {
            view.layer.borderWidth = 1
            view.layer.borderColor = stroke.cgColor
        }
    }
}

extension UIStackView {
    convenience init(axis: NSLayoutConstraint.Axis, spacing: CGFloat = 0, alignment: UIStackView.Alignment = .fill) {
        self.init()
        self.axis = axis
        self.spacing = spacing
        self.alignment = alignment
        self.translatesAutoresizingMaskIntoConstraints = false
    }
}

extension UIView {
    func pin(_ child: UIView, inset: CGFloat = 0) {
        child.translatesAutoresizingMaskIntoConstraints = false
        addSubview(child)
        NSLayoutConstraint.activate([
            child.topAnchor.constraint(equalTo: topAnchor, constant: inset),
            child.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -inset),
            child.leadingAnchor.constraint(equalTo: leadingAnchor, constant: inset),
            child.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -inset)
        ])
    }
}
