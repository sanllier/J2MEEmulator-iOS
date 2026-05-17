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
    /// Slightly above the iOS superellipse approximation (62 * 0.232 ≈ 14.4)
    /// for a marginally softer corner. Combined with cornerCurve = .continuous
    /// this reads as a true squircle close to the system Home Screen look.
    static let iconCornerRadius: CGFloat = 15.5
    /// Gap between the icon's bottom and the label's top.
    static let iconToLabelGap: CGFloat = 8
    /// Reserved label height — ~2 lines at 12.5pt with 1.18 line height.
    static let labelHeight: CGFloat = 32

    // Two-layer icon: an outer shadow-carrier (can't clip — clipping kills the
    // shadow) and an inner clipping image view that gets the iOS-style
    // continuous corner mask. Single-view setups force a trade-off between
    // shadow and rounded clip; splitting them keeps both correct.
    let iconShadow = UIView()
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
        para.lineHeightMultiple = 1.0
        para.lineBreakMode = .byTruncatingTail
        return [
            .font: UIFont.systemFont(ofSize: 12.5, weight: .medium),
            .foregroundColor: UIColor.white.withAlphaComponent(0.92),
            .kern: -0.12,                       // letter-spacing: -0.01em
            .shadow: shadow,
            .paragraphStyle: para,
        ]
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)

        contentView.clipsToBounds = false

        // Shadow wrapper — no mask, just carries the drop shadow.
        iconShadow.translatesAutoresizingMaskIntoConstraints = false
        iconShadow.backgroundColor = .clear
        iconShadow.layer.shadowColor = UIColor.black.cgColor
        iconShadow.layer.shadowOpacity = 0.4
        iconShadow.layer.shadowOffset = CGSize(width: 0, height: 4)
        iconShadow.layer.shadowRadius = 9
        iconShadow.layer.masksToBounds = false
        contentView.addSubview(iconShadow)

        // Inner image view — continuous (squircle) corners + thin border
        // applied via CALayer so they automatically follow the squircle
        // shape (CALayer.borderColor is rendered along cornerCurve).
        iconView.contentMode = .scaleAspectFill
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.layer.cornerRadius = Self.iconCornerRadius
        iconView.layer.cornerCurve = .continuous
        iconView.layer.masksToBounds = true
        iconView.layer.borderWidth = 1
        iconView.layer.borderColor = UIColor.white.withAlphaComponent(0.12).cgColor
        iconShadow.addSubview(iconView)

        nameLabel.textAlignment = .center
        nameLabel.numberOfLines = 2
        nameLabel.lineBreakMode = .byTruncatingTail
        nameLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(nameLabel)

        NSLayoutConstraint.activate([
            iconShadow.topAnchor.constraint(equalTo: contentView.topAnchor),
            iconShadow.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            iconShadow.widthAnchor.constraint(equalToConstant: Self.iconSize),
            iconShadow.heightAnchor.constraint(equalToConstant: Self.iconSize),

            iconView.topAnchor.constraint(equalTo: iconShadow.topAnchor),
            iconView.leadingAnchor.constraint(equalTo: iconShadow.leadingAnchor),
            iconView.trailingAnchor.constraint(equalTo: iconShadow.trailingAnchor),
            iconView.bottomAnchor.constraint(equalTo: iconShadow.bottomAnchor),

            nameLabel.topAnchor.constraint(equalTo: iconShadow.bottomAnchor,
                                            constant: Self.iconToLabelGap),
            nameLabel.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            nameLabel.widthAnchor.constraint(lessThanOrEqualTo: contentView.widthAnchor),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        // shadowPath uses circular-arc roundedRect — UIBezierPath has no
        // squircle variant. Visually indistinguishable because the shadow
        // blur is large (9pt), but mathematically a hair off from the
        // continuous icon outline.
        iconShadow.layer.shadowPath = UIBezierPath(
            roundedRect: iconShadow.bounds,
            cornerRadius: Self.iconCornerRadius
        ).cgPath
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        iconView.image = nil
        nameLabel.attributedText = nil
    }

    // Press animation — mimics iOS home screen: only the *icon* reacts, the title stays
    // in place. Transform is applied to the shadow wrapper so the shadow shrinks
    // along with the icon (otherwise the shadow stays full-size while the icon
    // shrinks, which looks broken).
    override var isHighlighted: Bool {
        didSet {
            UIView.animate(withDuration: 0.18,
                           delay: 0,
                           options: [.allowUserInteraction, .beginFromCurrentState,
                                     .curveEaseOut]) {
                let pressed = self.isHighlighted
                self.iconShadow.transform = pressed
                    ? CGAffineTransform(scaleX: 0.92, y: 0.92)
                    : .identity
                self.iconShadow.alpha = pressed ? 0.85 : 1.0
            }
        }
    }

    func configure(name: String, icon: UIImage) {
        iconView.image = icon
        nameLabel.attributedText = NSAttributedString(string: name,
                                                      attributes: Self.labelAttributes)
    }
}
