//
//  Neumorphic.swift
//  J2MEEmulator
//
//  Visual primitives for the in-game UI — Soft 3D / Neumorphic treatment.
//  Mirrors design/variants.jsx → NeumoVariant.
//

import UIKit

// MARK: - Palette

enum NeumoPalette {
    // Surface (button face) — linear-gradient(145deg, #30363f, #232830)
    static let surfaceTop      = UIColor(red: 0x30/255, green: 0x36/255, blue: 0x3f/255, alpha: 1)
    static let surfaceBottom   = UIColor(red: 0x23/255, green: 0x28/255, blue: 0x30/255, alpha: 1)

    // Shadows
    static let shadowDark      = UIColor.black.withAlphaComponent(0.55)
    static let shadowLight     = UIColor.white.withAlphaComponent(0.045)
    static let topHighlight    = UIColor.white.withAlphaComponent(0.05)

    // Text
    static let label           = UIColor(red: 231/255, green: 236/255, blue: 244/255, alpha: 0.66)
    static let labelStrong     = UIColor.white
    static let labelDim        = UIColor(red: 231/255, green: 236/255, blue: 244/255, alpha: 0.34)
    static let hintRest        = UIColor(red: 231/255, green: 236/255, blue: 244/255, alpha: 0.22)

    // Accent — teal #5EEAD4
    static let accent          = UIColor(red: 0x5E/255, green: 0xEA/255, blue: 0xD4/255, alpha: 1)

    // Background (page)
    static let bgBase1         = UIColor(red: 0x1f/255, green: 0x24/255, blue: 0x2b/255, alpha: 1)
    static let bgBase2         = UIColor(red: 0x16/255, green: 0x1a/255, blue: 0x20/255, alpha: 1)
    static let bgRadialLight   = UIColor(red: 0x2c/255, green: 0x33/255, blue: 0x3d/255, alpha: 1)
    static let bgRadialDark    = UIColor(red: 0x1c/255, green: 0x20/255, blue: 0x27/255, alpha: 1)

    // Screen bezel
    static let screenBezelTop    = UIColor(red: 0x11/255, green: 0x16/255, blue: 0x1d/255, alpha: 1)
    static let screenBezelBottom = UIColor(red: 0x0a/255, green: 0x0d/255, blue: 0x12/255, alpha: 1)

    // D-pad well
    static let wellInner       = UIColor(red: 0x1a/255, green: 0x1e/255, blue: 0x25/255, alpha: 1)
    static let wellOuter       = UIColor(red: 0x14/255, green: 0x17/255, blue: 0x1c/255, alpha: 1)

    // D-pad stick — radial #3d444f → #272d36 → #181c22
    static let stick1          = UIColor(red: 0x3d/255, green: 0x44/255, blue: 0x4f/255, alpha: 1)
    static let stick2          = UIColor(red: 0x27/255, green: 0x2d/255, blue: 0x36/255, alpha: 1)
    static let stick3          = UIColor(red: 0x18/255, green: 0x1c/255, blue: 0x22/255, alpha: 1)
    // Dimple — #1a1e25 → #2c333d → #3a414c
    static let dimple1         = UIColor(red: 0x1a/255, green: 0x1e/255, blue: 0x25/255, alpha: 1)
    static let dimple2         = UIColor(red: 0x2c/255, green: 0x33/255, blue: 0x3d/255, alpha: 1)
    static let dimple3         = UIColor(red: 0x3a/255, green: 0x41/255, blue: 0x4c/255, alpha: 1)
}

// MARK: - Procedural noise tile (replaces SVG feTurbulence overlays)

/// Tiny LCG so the noise pattern is deterministic across launches.
/// SystemRandomNumberGenerator would regenerate the texture differently every build,
/// which makes the background look subtly different each time.
private struct NeumoLCG: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed | 1 }
    mutating func next() -> UInt64 {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return state
    }
}

enum NeumoNoise {
    /// Dense fine grain for the background — many low-alpha pixels read as a soft, uniform film.
    static let backgroundTile: UIImage = makeNoise(size: 200, dotCount: 36000, maxAlpha: 0.28, seed: 0xBADCAFE)

    /// Slightly punchier noise for the D-pad stick top surface.
    static let stickTile: UIImage = makeNoise(size: 160, dotCount: 13000, maxAlpha: 0.22, seed: 0xC0FFEE)

    private static func makeNoise(size: CGFloat, dotCount: Int, maxAlpha: CGFloat, seed: UInt64) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: size, height: size))
        var rng = NeumoLCG(seed: seed)
        let sizeUInt = UInt64(Int(size))
        return renderer.image { ctx in
            UIColor.clear.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: size, height: size))
            for _ in 0..<dotCount {
                let x = CGFloat(rng.next() % sizeUInt)
                let y = CGFloat(rng.next() % sizeUInt)
                let a = CGFloat(rng.next() % 1000) / 1000.0 * maxAlpha
                UIColor(white: 1, alpha: a).setFill()
                ctx.fill(CGRect(x: x, y: y, width: 1, height: 1))
            }
        }
    }
}

// MARK: - Inner shadow helper

/// Builds a CAShapeLayer that renders an inner shadow inside `bounds` with `cornerRadius`.
/// The shadow direction/strength matches CSS `box-shadow: inset` semantics.
final class NeumoInnerShadowLayer: CAShapeLayer {
    /// Inner shadow params.
    var inset: CGSize = .zero
    var blur: CGFloat = 0
    var color: UIColor = .black
    var strength: Float = 0

    func apply(to rect: CGRect, cornerRadius: CGFloat) {
        frame = rect
        // Path & mask must be in the layer's LOCAL coord system (bounds-relative),
        // not in the caller's coord system — otherwise non-zero rect.origin offsets
        // the shadow geometry inside the layer and the mask stops aligning with the
        // visible area, leaking shadow past where it should be clipped.
        let local = CGRect(origin: .zero, size: rect.size)
        // Outer rim must be much larger than the visible rect so the shadow projects all the way inward.
        let outerInset: CGFloat = max(blur, 20) * 2
        // Push the ring's INNER edge a couple of points OUTSIDE the masked region,
        // otherwise the mask's antialiased rim samples a sliver of fill colour and
        // a 1px hairline (white for `innerLight`) shows up along the rounded edge.
        // Shadow geometry is unaffected — it's still wide enough to wrap inward.
        let bleedGuard: CGFloat = 2
        let outer = UIBezierPath(roundedRect: local.insetBy(dx: -outerInset, dy: -outerInset),
                                 cornerRadius: cornerRadius + outerInset)
        let inner = UIBezierPath(roundedRect: local.insetBy(dx: -bleedGuard, dy: -bleedGuard),
                                 cornerRadius: cornerRadius + bleedGuard).reversing()
        outer.append(inner)
        path = outer.cgPath
        fillRule = .evenOdd
        fillColor = color.cgColor
        shadowColor = color.cgColor
        shadowOffset = inset
        shadowRadius = blur
        shadowOpacity = strength

        // Mask the rim away — only the shadow leaks through (clipped to the visible rounded rect).
        let mask = CAShapeLayer()
        mask.path = UIBezierPath(roundedRect: local, cornerRadius: cornerRadius).cgPath
        self.mask = mask
    }
}

// MARK: - Neumorphic button (close / L / R / numpad keys)

class NeumoButton: UIControl {

    // Visual layers
    private let darkOuter   = CALayer()
    private let lightOuter  = CALayer()
    private let surface     = CAGradientLayer()
    private let topGloss    = CALayer()
    private let innerDark   = NeumoInnerShadowLayer()
    private let innerLight  = NeumoInnerShadowLayer()

    // Content
    let glyphLabel = UILabel()
    let subLabel   = UILabel()
    private let stack = UIStackView()
    /// Optional SF Symbol / image content (used by the close button).
    let iconView  = UIImageView()

    /// Corner radius — 16 for close, 20 for keypad/soft.
    var cornerRadius: CGFloat = 20 { didSet { setNeedsLayout() } }

    /// Press-state visual shift (px). 1pt in CSS reference.
    var pressShift: CGFloat = 1

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear

        // Outer shadows ─ two soft drops, dark bottom-right + faint white top-left.
        darkOuter.shadowColor   = UIColor.black.cgColor
        darkOuter.shadowOffset  = CGSize(width: 6, height: 6)
        darkOuter.shadowRadius  = 14 / 2  // CALayer.shadowRadius corresponds to CSS blur/2
        darkOuter.shadowOpacity = 0.55
        layer.addSublayer(darkOuter)

        lightOuter.shadowColor   = UIColor.white.cgColor
        lightOuter.shadowOffset  = CGSize(width: -3, height: -3)
        lightOuter.shadowRadius  = 10 / 2
        lightOuter.shadowOpacity = 0.045
        layer.addSublayer(lightOuter)

        // Surface gradient — linear 145°. CAGradientLayer needs unit-square start/end.
        // CSS 145° ≈ angled from upper-left toward lower-right, slightly past the diagonal.
        surface.colors = [NeumoPalette.surfaceTop.cgColor, NeumoPalette.surfaceBottom.cgColor]
        surface.startPoint = CGPoint(x: 0.213, y: 0.09)
        surface.endPoint   = CGPoint(x: 0.787, y: 0.91)
        surface.masksToBounds = true
        // 1px hairline border — mirrors CSS `border: 1px solid rgba(255,255,255,.03)`.
        surface.borderWidth = 1
        surface.borderColor = UIColor.white.withAlphaComponent(0.03).cgColor
        layer.addSublayer(surface)

        // 1px top gloss — inset 0 1px 0 rgba(255,255,255,.05).
        topGloss.backgroundColor = NeumoPalette.topHighlight.cgColor
        layer.addSublayer(topGloss)

        // Inner shadows used in pressed state.
        innerDark.inset    = CGSize(width: 4, height: 4)
        innerDark.blur     = 8
        innerDark.color    = .black
        innerDark.strength = 0.55
        innerDark.isHidden = true
        layer.addSublayer(innerDark)

        innerLight.inset    = CGSize(width: -2, height: -2)
        innerLight.blur     = 6
        innerLight.color    = .white
        innerLight.strength = 0.045
        innerLight.isHidden = true
        layer.addSublayer(innerLight)

        // Content
        glyphLabel.textColor = NeumoPalette.label
        glyphLabel.textAlignment = .center
        subLabel.textColor = NeumoPalette.labelDim
        subLabel.textAlignment = .center

        iconView.contentMode = .center
        iconView.tintColor = NeumoPalette.label
        iconView.isHidden = true

        stack.axis = .vertical
        stack.alignment = .center
        stack.distribution = .fill
        stack.spacing = 2
        stack.isUserInteractionEnabled = false
        stack.addArrangedSubview(glyphLabel)
        stack.addArrangedSubview(subLabel)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        iconView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(iconView)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconView.centerXAnchor.constraint(equalTo: centerXAnchor),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    /// Configure as a glyph + T9 sub-letters (numpad key).
    func configureAsKey(glyph: String, sub: String, glyphFontSize: CGFloat, subFontSize: CGFloat) {
        glyphLabel.font = .systemFont(ofSize: glyphFontSize, weight: .medium)
        glyphLabel.text = glyph
        // Sub-label with kerning + uppercase to mirror `letter-spacing: .16em; text-transform: uppercase`.
        let upper = sub.uppercased()
        let attr = NSAttributedString(string: upper, attributes: [
            .font: UIFont.systemFont(ofSize: subFontSize, weight: .medium),
            .kern: subFontSize * 0.16,
            .foregroundColor: NeumoPalette.labelDim,
        ])
        subLabel.attributedText = attr
        subLabel.isHidden = sub.isEmpty
        iconView.isHidden = true
        stack.isHidden = false
    }

    /// Configure as a single glyph (soft keys L/R) — no sub-label.
    func configureAsSoft(glyph: String, fontSize: CGFloat) {
        glyphLabel.font = .systemFont(ofSize: fontSize, weight: .medium)
        glyphLabel.text = glyph
        subLabel.isHidden = true
        iconView.isHidden = true
        stack.isHidden = false
    }

    /// Configure with an icon (close button).
    func configureAsIcon(image: UIImage?) {
        iconView.image = image
        iconView.isHidden = false
        stack.isHidden = true
    }

    // MARK: Layout

    override func layoutSubviews() {
        super.layoutSubviews()
        let r = cornerRadius
        for l in [darkOuter, lightOuter, surface] {
            l.frame = bounds
            l.cornerRadius = r
        }
        let path = UIBezierPath(roundedRect: bounds, cornerRadius: r).cgPath
        darkOuter.shadowPath  = path
        lightOuter.shadowPath = path

        // Top gloss: 1pt line inset by corner radius left/right.
        topGloss.frame = CGRect(x: r, y: 0, width: max(0, bounds.width - 2 * r), height: 1)

        innerDark.apply(to: bounds, cornerRadius: r)
        innerLight.apply(to: bounds, cornerRadius: r)
    }

    // MARK: Pressed state

    override var isHighlighted: Bool { didSet { updatePressedState() } }

    // UIControl, unlike UIButton, does not auto-toggle isHighlighted during tracking.
    // Mirror UIButton's behavior — highlighted while finger is inside the bounds.

    override func beginTracking(_ touch: UITouch, with event: UIEvent?) -> Bool {
        let result = super.beginTracking(touch, with: event)
        isHighlighted = true
        return result
    }

    override func continueTracking(_ touch: UITouch, with event: UIEvent?) -> Bool {
        let result = super.continueTracking(touch, with: event)
        isHighlighted = isTouchInside
        return result
    }

    override func endTracking(_ touch: UITouch?, with event: UIEvent?) {
        super.endTracking(touch, with: event)
        isHighlighted = false
    }

    override func cancelTracking(with event: UIEvent?) {
        super.cancelTracking(with: event)
        isHighlighted = false
    }

    private func updatePressedState() {
        let pressed = isHighlighted
        // Toggle outer ↔ inner shadows and shift surface down 1pt.
        CATransaction.begin()
        CATransaction.setAnimationDuration(0.12)
        darkOuter.opacity  = pressed ? 0 : 1
        lightOuter.opacity = pressed ? 0 : 1
        innerDark.isHidden  = !pressed
        innerLight.isHidden = !pressed
        surface.transform = pressed
            ? CATransform3DMakeTranslation(0, pressShift, 0)
            : CATransform3DIdentity
        topGloss.opacity = pressed ? 0 : 1
        CATransaction.commit()

        // Move the label/icon along with the surface so the text doesn't appear to "float"
        // above a sinking button — without this the press effect is broken.
        let contentTransform: CGAffineTransform = pressed
            ? CGAffineTransform(translationX: 0, y: pressShift)
            : .identity
        UIView.animate(withDuration: 0.12, delay: 0,
                       options: [.beginFromCurrentState, .curveEaseOut]) {
            self.stack.transform = contentTransform
            self.iconView.transform = contentTransform
        }

        UIView.transition(with: glyphLabel, duration: 0.15, options: .transitionCrossDissolve) {
            self.glyphLabel.textColor = pressed ? NeumoPalette.accent : NeumoPalette.label
        }
        if !subLabel.isHidden {
            UIView.transition(with: subLabel, duration: 0.15, options: .transitionCrossDissolve) {
                let color: UIColor = pressed ? NeumoPalette.accent.withAlphaComponent(0.6) : NeumoPalette.labelDim
                if let attr = self.subLabel.attributedText {
                    let mut = NSMutableAttributedString(attributedString: attr)
                    mut.addAttribute(.foregroundColor, value: color,
                                     range: NSRange(location: 0, length: mut.length))
                    self.subLabel.attributedText = mut
                }
            }
        }
        iconView.tintColor = pressed ? NeumoPalette.accent : NeumoPalette.label
    }
}

// MARK: - Background view (radial gradients + noise overlay)

final class NeumoBackgroundView: UIView {

    private let baseLinear = CAGradientLayer()
    private let radialTopLeft = CAGradientLayer()
    private let radialBottomRight = CAGradientLayer()
    private let accentGlow = CAGradientLayer()
    private let noiseView = UIView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false

        // Base: linear-gradient(180deg, #1f242b 0%, #161a20 100%)
        baseLinear.colors = [NeumoPalette.bgBase1.cgColor, NeumoPalette.bgBase2.cgColor]
        baseLinear.startPoint = CGPoint(x: 0.5, y: 0)
        baseLinear.endPoint   = CGPoint(x: 0.5, y: 1)
        layer.addSublayer(baseLinear)

        // Top-left lift: radial-gradient(120% 80% at 18% 14%, #2c333d 0%, transparent 55%)
        radialTopLeft.type = .radial
        radialTopLeft.colors = [
            NeumoPalette.bgRadialLight.cgColor,
            NeumoPalette.bgRadialLight.withAlphaComponent(0).cgColor,
        ]
        radialTopLeft.locations = [0.0, 0.55]
        layer.addSublayer(radialTopLeft)

        // Bottom-right shade: radial 120% 80% at 86% 90%, #1c2027 0%, transparent 60%
        radialBottomRight.type = .radial
        radialBottomRight.colors = [
            NeumoPalette.bgRadialDark.cgColor,
            NeumoPalette.bgRadialDark.withAlphaComponent(0).cgColor,
        ]
        radialBottomRight.locations = [0.0, 0.60]
        layer.addSublayer(radialBottomRight)

        // Subtle accent glow near bottom (the CSS ::before)
        accentGlow.type = .radial
        let accent = NeumoPalette.accent.withAlphaComponent(0.035)
        accentGlow.colors = [accent.cgColor, NeumoPalette.accent.withAlphaComponent(0).cgColor]
        accentGlow.locations = [0.0, 0.60]
        layer.addSublayer(accentGlow)

        // Noise overlay — 7% opacity tiled pattern.
        noiseView.backgroundColor = UIColor(patternImage: NeumoNoise.backgroundTile)
        noiseView.alpha = 0.12
        noiseView.isUserInteractionEnabled = false
        addSubview(noiseView)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        baseLinear.frame = bounds

        // Reproduce CSS `radial-gradient(120% 80% at X Y, ...)`:
        // the gradient ellipse is sized 120% × 80% of the container, centered at (X, Y).
        let w = bounds.width
        let h = bounds.height

        func radialFrame(at p: CGPoint, sizeRatio: CGSize) -> CGRect {
            let gw = w * sizeRatio.width
            let gh = h * sizeRatio.height
            return CGRect(x: p.x - gw / 2, y: p.y - gh / 2, width: gw, height: gh)
        }
        // 18%/14%, 120%/80% (×2 because CAGradientLayer measures radii not diameters? — no,
        //   CAGradientLayer.type=.radial draws an ellipse fit to the layer bounds, so we
        //   just size the layer to the gradient ellipse size and position it).
        radialTopLeft.frame = radialFrame(
            at: CGPoint(x: w * 0.18, y: h * 0.14),
            sizeRatio: CGSize(width: 1.2, height: 0.8))
        // Radial CAGradientLayer goes from startPoint→endPoint within layer bounds.
        // For a centered radial: start = (0.5, 0.5), end = (1, 0.5) defines radius = half-width.
        for l in [radialTopLeft, radialBottomRight, accentGlow] {
            l.startPoint = CGPoint(x: 0.5, y: 0.5)
            l.endPoint   = CGPoint(x: 1.0, y: 1.0)
        }

        radialBottomRight.frame = radialFrame(
            at: CGPoint(x: w * 0.86, y: h * 0.90),
            sizeRatio: CGSize(width: 1.2, height: 0.8))

        // Accent glow: 60%×40% at 50% 100%.
        accentGlow.frame = radialFrame(
            at: CGPoint(x: w * 0.5, y: h * 1.0),
            sizeRatio: CGSize(width: 0.6, height: 0.4))

        noiseView.frame = bounds
    }
}

// MARK: - Screen bezel (frame around the J2ME canvas)

/// Decorative bezel that wraps the emulator canvas: outer rounded rect with a dark linear gradient
/// and a deep inner well. Mirrors `.neumo-screen` from the design reference.
final class NeumoScreenFrame: UIView {

    private let outerGradient = CAGradientLayer()
    private let innerWellShadow = NeumoInnerShadowLayer()
    /// Padding around the canvas inside the bezel (designUnit * 14).
    var canvasPadding: CGFloat = 14 { didSet { setNeedsLayout() } }
    /// Corner radius of the bezel itself.
    var bezelCornerRadius: CGFloat = 18 { didSet { setNeedsLayout() } }
    /// Corner radius of the inner canvas well.
    var wellCornerRadius: CGFloat = 6 { didSet { setNeedsLayout() } }

    /// Convenience anchor describing the inside of the bezel — clients pin the canvas here.
    let canvasLayoutGuide = UILayoutGuide()

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear

        // Bezel — linear 180° #11161d → #0a0d12, with the same hairline border the
        // CSS reference puts on it (`0 0 0 1px rgba(255,255,255,.05)`).
        outerGradient.colors = [NeumoPalette.screenBezelTop.cgColor, NeumoPalette.screenBezelBottom.cgColor]
        outerGradient.startPoint = CGPoint(x: 0.5, y: 0)
        outerGradient.endPoint   = CGPoint(x: 0.5, y: 1)
        // Uniform hairline tracing the whole rounded perimeter — CSS reference uses
        // 0.05 alpha but on a dark gradient that washes out; bumped to .14 so the
        // border actually reads.
        outerGradient.borderWidth = 1
        outerGradient.borderColor = UIColor.white.withAlphaComponent(0.14).cgColor
        layer.addSublayer(outerGradient)

        // Inner well — deep inset shadow on top of the gradient.
        layer.addSublayer(innerWellShadow)

        // Soft drop shadow under the bezel — CSS reference is `0 28px 60px rgba(0,0,0,.65)`;
        // toned down to .35 so it reads as gentle lift rather than a hard black rectangle.
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOffset = CGSize(width: 0, height: 12)
        layer.shadowRadius = 24
        layer.shadowOpacity = 0.35
        // masksToBounds MUST stay false for the drop shadow to render. The inner well
        // shadow layer below has its own mask so it doesn't leak past the bezel.
        layer.masksToBounds = false

        addLayoutGuide(canvasLayoutGuide)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        outerGradient.frame = bounds
        outerGradient.cornerRadius = bezelCornerRadius
        layer.cornerRadius = bezelCornerRadius
        // Explicit shadowPath so Core Animation doesn't have to sample the layer's
        // alpha each frame to figure out the shadow shape.
        layer.shadowPath = UIBezierPath(roundedRect: bounds, cornerRadius: bezelCornerRadius).cgPath

        // Inner well rect — bounds inset by padding, with own corner radius.
        let well = bounds.insetBy(dx: canvasPadding, dy: canvasPadding)
        innerWellShadow.inset    = CGSize(width: 0, height: 0)
        innerWellShadow.blur     = 22
        innerWellShadow.color    = .black
        innerWellShadow.strength = 0.75
        innerWellShadow.apply(to: well, cornerRadius: wellCornerRadius)
    }

    /// Returns the corner radius the embedded canvas should round its corners to.
    var canvasCornerRadius: CGFloat { wellCornerRadius }
}
