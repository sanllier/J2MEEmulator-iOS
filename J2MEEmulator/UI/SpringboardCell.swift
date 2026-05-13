//
//  SpringboardCell.swift
//  J2MEEmulator
//
//  Library tile — icon (62×62, iOS-app-icon-like) + 2-line label.
//  Matches design/library.jsx GameTile.
//

import UIKit

class SpringboardCell: UICollectionViewCell {

    static let reuseID = "SpringboardCell"
    /// 62pt — same as in design/library.jsx (GameIcon default size).
    static let iconSize: CGFloat = 62
    /// 62 * 0.232 ≈ 14.4 — iOS superellipse approximation from the reference.
    static let iconCornerRadius: CGFloat = 14.4
    /// Gap between the icon's bottom and the label's top.
    static let iconToLabelGap: CGFloat = 8
    /// Reserved label height — ~2 lines at 12.5pt with 1.18 line height.
    static let labelHeight: CGFloat = 32

    let iconView = UIImageView()
    let nameLabel = UILabel()

    // Label attributes mirroring the reference (12.5pt regular, white .92, 1.18 line height,
    // shadow black .6 / blur 2 / offset 1 — softer than the previous spec).
    private static let labelAttributes: [NSAttributedString.Key: Any] = {
        let shadow = NSShadow()
        shadow.shadowColor = UIColor.black.withAlphaComponent(0.6)
        shadow.shadowOffset = CGSize(width: 0, height: 1)
        shadow.shadowBlurRadius = 2
        let para = NSMutableParagraphStyle()
        para.alignment = .center
        para.lineHeightMultiple = 1.18
        para.lineBreakMode = .byTruncatingTail
        return [
            .font: UIFont.systemFont(ofSize: 12.5, weight: .regular),
            .foregroundColor: UIColor.white.withAlphaComponent(0.92),
            .kern: -0.12,                       // letter-spacing: -0.01em
            .shadow: shadow,
            .paragraphStyle: para,
        ]
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)

        contentView.clipsToBounds = false

        iconView.contentMode = .scaleAspectFill
        iconView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(iconView)

        nameLabel.textAlignment = .center
        nameLabel.numberOfLines = 2
        nameLabel.lineBreakMode = .byTruncatingTail
        nameLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(nameLabel)

        NSLayoutConstraint.activate([
            iconView.topAnchor.constraint(equalTo: contentView.topAnchor),
            iconView.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            iconView.widthAnchor.constraint(equalToConstant: Self.iconSize),
            iconView.heightAnchor.constraint(equalToConstant: Self.iconSize),

            nameLabel.topAnchor.constraint(equalTo: iconView.bottomAnchor,
                                            constant: Self.iconToLabelGap),
            nameLabel.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            nameLabel.widthAnchor.constraint(lessThanOrEqualTo: contentView.widthAnchor),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        iconView.image = nil
        nameLabel.attributedText = nil
    }

    // Press animation — mimics iOS home screen: only the *icon* reacts, the title stays
    // in place. A whole-cell transform would cause the label to visually grow back to 1.0
    // when the system context menu starts (UIKit cancels the highlight), so this scopes
    // the effect to iconView only.
    override var isHighlighted: Bool {
        didSet {
            UIView.animate(withDuration: 0.18,
                           delay: 0,
                           options: [.allowUserInteraction, .beginFromCurrentState,
                                     .curveEaseOut]) {
                let pressed = self.isHighlighted
                self.iconView.transform = pressed
                    ? CGAffineTransform(scaleX: 0.92, y: 0.92)
                    : .identity
                self.iconView.alpha = pressed ? 0.85 : 1.0
            }
        }
    }

    func configure(name: String, icon: UIImage) {
        iconView.image = icon
        nameLabel.attributedText = NSAttributedString(string: name,
                                                      attributes: Self.labelAttributes)
    }
}
