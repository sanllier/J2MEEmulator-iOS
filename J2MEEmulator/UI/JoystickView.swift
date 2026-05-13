//
//  JoystickView.swift
//  J2MEEmulator
//
//  Virtual analog joystick that emits 8-way numpad key presses (1-4, 6-9).
//  Visual treatment mirrors `.neumo-dpad` from design/variants.jsx — circular dark well
//  with thin guide ring, etched cardinal cross, four chevron hints, and a 3D stick.
//

import UIKit

class JoystickView: UIView {

    // MARK: Visual layers
    private let wellGradient    = CAGradientLayer()    // radial #1a1e25 → #14171c
    private let wellInsetShadow = NeumoInnerShadowLayer()  // CSS: inset 0 3px 10px black .75 (dark at top rim)
    private let guideRing       = CAShapeLayer()       // thin 1pt border at inset 7%
    private let etchedCross     = CAShapeLayer()       // faint cardinal cross
    private let stickView       = UIView()
    private let stickGradient   = CAGradientLayer()    // radial offset gradient
    private let stickNoise      = CALayer()
    private let stickTopRim     = CAShapeLayer()       // stroked outline — masked to top arc only
    private let stickTopRimMask = CAGradientLayer()    // vertical fade mask for stickTopRim
    private let stickBottomShadow = NeumoInnerShadowLayer()  // CSS: inset 0 -5px 12px black .6 — soft bottom shading
    private let dimpleView      = UIView()
    private let dimpleGradient  = CAGradientLayer()
    private let dimpleInset     = NeumoInnerShadowLayer()

    private let hintUp    = UIImageView()
    private let hintDown  = UIImageView()
    private let hintLeft  = UIImageView()
    private let hintRight = UIImageView()
    private var hintImage: UIImage?

    // MARK: State
    private var activeCode: Int32 = 0
    private var repeatTimer: Timer?
    private var stickAtRestCenter: CGPoint = .zero

    /// Dead zone as fraction of well radius (no key press within this range)
    private let deadZoneRatio: CGFloat = 0.25

    /// 8-way direction codes mapped to numpad keys, clockwise from right.
    /// J2ME maps: 2=UP, 8=DOWN, 4=LEFT, 6=RIGHT (top-of-keypad = up).
    /// Sectors follow iOS atan2: 0=right, π/2=down, π=left, -π/2=up.
    ///   Right=6  DownRight=9  Down=8  DownLeft=7  Left=4  UpLeft=1  Up=2  UpRight=3
    private static let sectorCodes: [Int32] = [54, 57, 56, 55, 52, 49, 50, 51]

    override init(frame: CGRect) {
        super.init(frame: frame)
        isMultipleTouchEnabled = false
        backgroundColor = .clear

        // ── Well ──
        // Radial gradient inside the well — wider light spot fades to almost black at 92%.
        wellGradient.type = .radial
        wellGradient.colors = [NeumoPalette.wellInner.cgColor, NeumoPalette.wellOuter.cgColor]
        wellGradient.locations = [0.0, 0.92]
        wellGradient.startPoint = CGPoint(x: 0.5, y: 0.5)
        wellGradient.endPoint   = CGPoint(x: 1.0, y: 1.0)
        // 1.5px hairline border, white .045 alpha.
        wellGradient.borderWidth = 1.5
        wellGradient.borderColor = UIColor.white.withAlphaComponent(0.045).cgColor
        layer.addSublayer(wellGradient)

        // Deep inner shadow at top — CSS: inset 0 3px 10px black .75
        layer.addSublayer(wellInsetShadow)

        // Thin guide ring at 7% inset.
        guideRing.fillColor = UIColor.clear.cgColor
        guideRing.strokeColor = UIColor.white.withAlphaComponent(0.04).cgColor
        guideRing.lineWidth = 1
        layer.addSublayer(guideRing)

        // Etched cardinal cross — four short ticks between stick and guide ring.
        etchedCross.fillColor = UIColor.clear.cgColor
        etchedCross.strokeColor = UIColor.white.withAlphaComponent(0.15).cgColor
        etchedCross.lineWidth = 1
        layer.addSublayer(etchedCross)

        // ── Chevron hints (always shown, faintly tinted) ──
        for hint in [hintUp, hintDown, hintLeft, hintRight] {
            hint.contentMode = .center
            hint.isUserInteractionEnabled = false
            addSubview(hint)
        }
        hintDown.transform  = CGAffineTransform(rotationAngle: .pi)
        hintLeft.transform  = CGAffineTransform(rotationAngle: -.pi / 2)
        hintRight.transform = CGAffineTransform(rotationAngle: .pi / 2)
        applyHintTint(.rest)

        // ── Stick ──
        stickView.isUserInteractionEnabled = false
        stickView.layer.masksToBounds = false
        // Outer drop shadow: 0 10px 22px black .55 — bedded by CALayer.shadow*.
        stickView.layer.shadowColor = UIColor.black.cgColor
        stickView.layer.shadowOpacity = 0.55
        stickView.layer.shadowOffset = CGSize(width: 0, height: 10)
        stickView.layer.shadowRadius = 11
        addSubview(stickView)

        // Radial gradient on the stick, offset toward upper-left (CSS: at 35% 26%).
        // CAGradientLayer.radial places the gradient circle in layer coords by
        // start (center) → end (radius). We center at (0.35, 0.26) and extend to a corner.
        stickGradient.type = .radial
        stickGradient.colors = [
            NeumoPalette.stick1.cgColor,
            NeumoPalette.stick2.cgColor,
            NeumoPalette.stick3.cgColor,
        ]
        stickGradient.locations = [0.0, 0.5, 1.0]
        stickGradient.startPoint = CGPoint(x: 0.35, y: 0.26)
        stickGradient.endPoint   = CGPoint(x: 1.20, y: 1.10)
        // 1pt dark hairline around the puck — CSS: `0 0 0 1px rgba(0,0,0,.55)`
        stickGradient.borderWidth = 1
        stickGradient.borderColor = UIColor.black.withAlphaComponent(0.55).cgColor
        stickView.layer.addSublayer(stickGradient)

        // Noise overlay on the stick top — subtle texture (`feTurbulence` in the design).
        stickNoise.contents = NeumoNoise.stickTile.cgImage
        stickNoise.contentsGravity = .resizeAspectFill
        stickNoise.opacity = 0.6
        stickNoise.compositingFilter = "overlayBlendMode"
        stickView.layer.addSublayer(stickNoise)

        // Convex puck rim shading — dark bottom under the noise so it reads as ambient,
        // then a stroked top rim with a vertical fade mask so the highlight is contained
        // to the upper arc and doesn't read as a continuous ring around the whole puck.
        stickView.layer.addSublayer(stickBottomShadow)

        stickTopRim.fillColor = UIColor.clear.cgColor
        stickTopRim.strokeColor = UIColor.white.withAlphaComponent(0.35).cgColor
        stickTopRim.lineWidth = 1
        // Mask: opaque at the very top, fully clear well before the equator.
        stickTopRimMask.colors = [UIColor.white.cgColor, UIColor.clear.cgColor]
        stickTopRimMask.locations = [0.0, 1.0]
        stickTopRimMask.startPoint = CGPoint(x: 0.5, y: 0.0)
        stickTopRimMask.endPoint   = CGPoint(x: 0.5, y: 0.28)
        stickTopRim.mask = stickTopRimMask
        stickView.layer.addSublayer(stickTopRim)

        // ── Dimple on top of the stick ──
        dimpleView.isUserInteractionEnabled = false
        dimpleGradient.type = .radial
        dimpleGradient.colors = [
            NeumoPalette.dimple1.cgColor,
            NeumoPalette.dimple2.cgColor,
            NeumoPalette.dimple3.cgColor,
        ]
        dimpleGradient.locations = [0.0, 0.70, 1.0]
        dimpleGradient.startPoint = CGPoint(x: 0.35, y: 0.28)
        dimpleGradient.endPoint   = CGPoint(x: 1.20, y: 1.10)
        dimpleView.layer.addSublayer(dimpleGradient)
        dimpleView.layer.addSublayer(dimpleInset)
        stickView.addSubview(dimpleView)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        let size = min(bounds.width, bounds.height)
        let wellRect = CGRect(x: (bounds.width - size) / 2,
                              y: (bounds.height - size) / 2,
                              width: size, height: size)
        let radius = size / 2
        let center = CGPoint(x: wellRect.midX, y: wellRect.midY)

        // Well gradient layer
        wellGradient.frame = wellRect
        wellGradient.cornerRadius = radius

        // Inner shadow on the well — inset top 3px, blur 10, black .75 (CSS reference)
        wellInsetShadow.inset    = CGSize(width: 0, height: 3)
        wellInsetShadow.blur     = 10
        wellInsetShadow.color    = .black
        wellInsetShadow.strength = 0.75
        wellInsetShadow.apply(to: wellRect, cornerRadius: radius)

        // Guide ring at 7% inset
        let ringInset = size * 0.07
        let ringRect = wellRect.insetBy(dx: ringInset, dy: ringInset)
        guideRing.frame = bounds
        guideRing.path = UIBezierPath(ovalIn: ringRect).cgPath

        // Cardinal tick marks — sit in the corridor between the stick (~54% radius)
        // and the guide ring (~93% radius), so they're visible *around* the puck rather
        // than hidden under it. Each tick is a short radial segment.
        let crossPath = UIBezierPath()
        let innerRadius = size * 0.30       // just outside the stick edge (stick = 0.54 * size)
        let outerRadius = size * 0.38       // ends well inside the guide ring
        // Horizontal segments (left / right ticks)
        crossPath.move(to: CGPoint(x: center.x - outerRadius, y: center.y))
        crossPath.addLine(to: CGPoint(x: center.x - innerRadius, y: center.y))
        crossPath.move(to: CGPoint(x: center.x + innerRadius, y: center.y))
        crossPath.addLine(to: CGPoint(x: center.x + outerRadius, y: center.y))
        // Vertical segments (top / bottom ticks)
        crossPath.move(to: CGPoint(x: center.x, y: center.y - outerRadius))
        crossPath.addLine(to: CGPoint(x: center.x, y: center.y - innerRadius))
        crossPath.move(to: CGPoint(x: center.x, y: center.y + innerRadius))
        crossPath.addLine(to: CGPoint(x: center.x, y: center.y + outerRadius))
        etchedCross.frame = bounds
        etchedCross.path = crossPath.cgPath

        // Hints — small light-weight chevrons pinned to the outer rim of the well,
        // right on the guide ring (≈4% inset from the well edge).
        let hintInset: CGFloat = size * 0.04
        let hintGlyphSize: CGFloat = max(8, size * 0.045)
        if hintImage?.size.height != hintGlyphSize {
            let cfg = UIImage.SymbolConfiguration(pointSize: hintGlyphSize, weight: .light)
            hintImage = UIImage(systemName: "chevron.up", withConfiguration: cfg)
            for hint in [hintUp, hintDown, hintLeft, hintRight] {
                hint.image = hintImage
            }
            applyHintTint(.rest)
        }
        let hintBox = CGSize(width: hintGlyphSize * 1.8, height: hintGlyphSize * 1.8)
        func placeHint(_ hint: UIImageView, x: CGFloat, y: CGFloat) {
            hint.bounds = CGRect(origin: .zero, size: hintBox)
            hint.center = CGPoint(x: x, y: y)
        }
        placeHint(hintUp,    x: center.x,                 y: wellRect.minY + hintInset)
        placeHint(hintDown,  x: center.x,                 y: wellRect.maxY - hintInset)
        placeHint(hintLeft,  x: wellRect.minX + hintInset, y: center.y)
        placeHint(hintRight, x: wellRect.maxX - hintInset, y: center.y)

        // Stick — 54% of well diameter.
        let stickSize = size * 0.54
        let stickRect = CGRect(x: 0, y: 0, width: stickSize, height: stickSize)
        stickView.bounds = stickRect
        stickView.center = center
        stickAtRestCenter = center
        stickView.layer.cornerRadius = stickSize / 2
        stickView.layer.shadowPath = UIBezierPath(ovalIn: stickRect).cgPath

        stickGradient.frame = stickRect
        stickGradient.cornerRadius = stickSize / 2
        stickGradient.masksToBounds = true

        stickNoise.frame = stickRect
        stickNoise.cornerRadius = stickSize / 2
        stickNoise.masksToBounds = true

        // CSS reference for the puck bottom: `inset 0 -5px 12px rgba(0,0,0,.6)` — soft pillow.
        stickBottomShadow.inset    = CGSize(width: 0, height: -5)
        stickBottomShadow.blur     = 12
        stickBottomShadow.color    = .black
        stickBottomShadow.strength = 0.6
        stickBottomShadow.apply(to: stickRect, cornerRadius: stickSize / 2)

        // Top rim — stroke a circle inset by half lineWidth so the stroke sits inside the puck.
        stickTopRim.frame = stickRect
        stickTopRim.path = UIBezierPath(ovalIn: stickRect.insetBy(dx: 0.5, dy: 0.5)).cgPath
        stickTopRimMask.frame = stickRect

        // Dimple — 36% of stick.
        let dimpleSize = stickSize * 0.36
        let dimpleRect = CGRect(x: 0, y: 0, width: dimpleSize, height: dimpleSize)
        dimpleView.bounds = dimpleRect
        dimpleView.center = CGPoint(x: stickSize / 2, y: stickSize / 2)
        dimpleView.layer.cornerRadius = dimpleSize / 2
        dimpleView.layer.masksToBounds = true

        dimpleGradient.frame = dimpleRect
        dimpleGradient.cornerRadius = dimpleSize / 2

        // Concave inner shadow on the dimple — inset 0 2px 6px black .55
        dimpleInset.inset    = CGSize(width: 0, height: 2)
        dimpleInset.blur     = 6
        dimpleInset.color    = .black
        dimpleInset.strength = 0.55
        dimpleInset.apply(to: dimpleRect, cornerRadius: dimpleSize / 2)
    }

    // MARK: - Hint tinting

    private enum HintState { case rest, active }

    private func applyHintTint(_ state: HintState) {
        let color: UIColor
        switch state {
        case .rest:   color = NeumoPalette.hintRest
        case .active: color = NeumoPalette.accent
        }
        for hint in [hintUp, hintDown, hintLeft, hintRight] {
            hint.tintColor = color
            // SF Symbols ignore tintColor when rendered as `automatic`; force template.
            if let img = hint.image, img.renderingMode != .alwaysTemplate {
                hint.image = img.withRenderingMode(.alwaysTemplate)
            }
        }
    }

    // MARK: - Touch handling

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let pt = touches.first?.location(in: self) else { return }
        update(at: pt)
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let pt = touches.first?.location(in: self) else { return }
        update(at: pt)
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        reset()
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        reset()
    }

    // MARK: - Joystick logic

    private func update(at point: CGPoint) {
        let cx = stickAtRestCenter.x
        let cy = stickAtRestCenter.y
        let radius = wellGradient.bounds.width / 2

        let dx = point.x - cx
        let dy = point.y - cy
        let dist = hypot(dx, dy)
        let angle = atan2(dy, dx)

        // Clamp stick travel — let the puck reach all the way to the well rim.
        // Stick radius = size * 0.27 = radius * 0.54, so its center can travel up to
        // radius * (1 - 0.54) = radius * 0.46 before the puck edge meets the well rim.
        let clamped = min(dist, radius * 0.46)
        let newCenter = CGPoint(x: cx + cos(angle) * clamped, y: cy + sin(angle) * clamped)
        UIView.animate(withDuration: 0.06, delay: 0, options: [.beginFromCurrentState, .curveLinear]) {
            self.stickView.center = newCenter
        }

        // Dead zone check
        if dist < radius * deadZoneRatio {
            if activeCode != 0 { releaseKey(activeCode) }
            return
        }

        // 8-way sector: each 45° wide, sector 0 centered on 0° (right)
        var a = angle
        if a < 0 { a += 2 * .pi }
        let sector = Int((a + .pi / 8) / (.pi / 4)) % 8
        let code = Self.sectorCodes[sector]

        if code != activeCode {
            if activeCode != 0 { releaseKey(activeCode) }
            pressKey(code)
        }
    }

    private func reset() {
        if activeCode != 0 { releaseKey(activeCode) }
        UIView.animate(withDuration: 0.32,
                       delay: 0,
                       usingSpringWithDamping: 0.7,
                       initialSpringVelocity: 0.3,
                       options: [.beginFromCurrentState]) {
            self.stickView.center = self.stickAtRestCenter
        }
    }

    private func pressKey(_ code: Int32) {
        activeCode = code
        j2me_input_post_key(Int32(J2ME_INPUT_KEY_PRESSED), code)

        repeatTimer?.invalidate()
        repeatTimer = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: false) { [weak self] _ in
            self?.repeatTimer = Timer.scheduledTimer(withTimeInterval: 0.08, repeats: true) { [weak self] _ in
                guard let self, self.activeCode == code else { return }
                j2me_input_post_key(Int32(J2ME_INPUT_KEY_REPEATED), code)
            }
        }
    }

    private func releaseKey(_ code: Int32) {
        j2me_input_post_key(Int32(J2ME_INPUT_KEY_RELEASED), code)
        activeCode = 0
        repeatTimer?.invalidate()
        repeatTimer = nil
    }
}
