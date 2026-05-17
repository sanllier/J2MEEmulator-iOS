//
//  NumpadView.swift
//  J2MEEmulator
//
//  Reusable 3×4 numpad with T9 sub-letters + dynamic command buttons.
//  Visual treatment matches `.neumo-key` from design/variants.jsx.
//

import UIKit

class NumpadView: UIView {

    static let KEY_SOFT_LEFT: Int32  = -6
    static let KEY_SOFT_RIGHT: Int32 = -7

    private var repeatTimer: Timer?
    private var repeatKeyCode: Int32 = 0
    private var commandButtons: [NeumoButton] = []
    private let haptic = UIImpactFeedbackGenerator(style: .light)

    private var keys: [NeumoButton] = []

    /// Glyph + T9-style sub-letters per the reference. `·` for 1, U+2423 (open box) for 0,
    /// U+21B5 (carriage-return) for #.
    private static let keyDefs: [(glyph: String, sub: String, code: Int32)] = [
        ("1", "\u{00B7}", 49), ("2", "abc",     50), ("3", "def",     51),
        ("4", "ghi",     52), ("5", "jkl",     53), ("6", "mno",     54),
        ("7", "pqrs",    55), ("8", "tuv",     56), ("9", "wxyz",    57),
        ("*", "+",       42), ("0", "\u{2423}", 48), ("#", "\u{21B5}", 35),
    ]

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        setup()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func setup() {
        for def in Self.keyDefs {
            let btn = NeumoButton()
            btn.tag = Int(def.code)
            // Sizes get configured in layoutSubviews based on actual key dimensions.
            btn.configureAsKey(glyph: def.glyph, sub: def.sub, glyphFontSize: 22, subFontSize: 8)
            btn.addTarget(self, action: #selector(down(_:)), for: .touchDown)
            btn.addTarget(self, action: #selector(up(_:)),
                          for: [.touchUpInside, .touchUpOutside, .touchCancel])
            addSubview(btn)
            keys.append(btn)
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let cols: CGFloat = 3
        let rows: CGFloat = 4
        // Gap is 12pt at 92pt key — ratio 12/92 ≈ 0.13.
        let gapRatio: CGFloat = 12.0 / 92.0
        // Solve for key size: w = cols*key + (cols-1)*gap, gap = key*ratio
        let key = bounds.width / (cols + (cols - 1) * gapRatio)
        let gap = key * gapRatio

        let glyphSize = key * (28.0 / 92.0)
        let subSize   = key * (15.0 / 92.0)
        let corner    = key * (20.0 / 92.0)

        for (i, btn) in keys.enumerated() {
            let col = i % 3
            let row = i / 3
            btn.frame = CGRect(
                x: CGFloat(col) * (key + gap),
                y: CGFloat(row) * (key + gap),
                width: key, height: key)
            btn.cornerRadius = corner
            btn.configureAsKey(glyph: Self.keyDefs[i].glyph,
                               sub: Self.keyDefs[i].sub,
                               glyphFontSize: glyphSize,
                               subFontSize: subSize)
        }

        layoutCommands(below: rows * key + (rows - 1) * gap, gap: gap, corner: corner)
    }

    // MARK: - Key events with repeat

    @objc private func down(_ sender: NeumoButton) {
        let code = Int32(sender.tag)
        haptic.impactOccurred(intensity: 0.6)
        j2me_input_post_key(Int32(J2ME_INPUT_KEY_PRESSED), code)
        repeatKeyCode = code
        repeatTimer?.invalidate()
        repeatTimer = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: false) { [weak self] _ in
            self?.repeatTimer = Timer.scheduledTimer(withTimeInterval: 0.08, repeats: true) { [weak self] _ in
                guard let self, self.repeatKeyCode == code else { return }
                j2me_input_post_key(Int32(J2ME_INPUT_KEY_REPEATED), code)
            }
        }
    }

    @objc private func up(_ sender: NeumoButton) {
        j2me_input_post_key(Int32(J2ME_INPUT_KEY_RELEASED), Int32(sender.tag))
        repeatTimer?.invalidate()
        repeatTimer = nil
    }

    // MARK: - Canvas command buttons

    func updateCommands() {
        commandButtons.forEach { $0.removeFromSuperview() }
        commandButtons.removeAll()

        let cmdCount = j2me_ui_get_command_count()
        guard cmdCount > 0 else { return }

        for i in 0..<cmdCount {
            let label = String(cString: j2me_ui_get_command_label(Int32(i)))
            let cmdId = j2me_ui_get_command_id(Int32(i))

            let btn = NeumoButton()
            btn.configureAsSoft(glyph: label, fontSize: 13)
            btn.cornerRadius = 14
            btn.tag = 1000 + Int(cmdId)
            btn.addTarget(self, action: #selector(commandTapped(_:)), for: .touchUpInside)
            addSubview(btn)
            commandButtons.append(btn)
        }
        setNeedsLayout()
    }

    private func layoutCommands(below keypadHeight: CGFloat, gap: CGFloat, corner: CGFloat) {
        guard !commandButtons.isEmpty else { return }
        let w = bounds.width
        // Stack command buttons on the right edge below the keypad.
        let btnW = w * 0.5
        let btnH: CGFloat = 32
        let startY = keypadHeight + gap
        for (i, btn) in commandButtons.enumerated() {
            btn.cornerRadius = corner * 0.7
            btn.frame = CGRect(x: w - btnW,
                               y: startY + CGFloat(i) * (btnH + gap),
                               width: btnW, height: btnH)
        }
    }

    @objc private func commandTapped(_ sender: NeumoButton) {
        j2me_input_post_key(Int32(J2ME_UI_COMMAND_ACTION), Int32(sender.tag - 1000))
    }

    // Command buttons are positioned below the 4×3 key grid — outside our own
    // bounds (NumpadView.frame is sized for the grid only). They render fine
    // (clipsToBounds is false), but UIView's default hitTest returns nil for
    // any point outside bounds, so taps on them never reach the button. Extend
    // hit-testing to cover those out-of-bounds command buttons explicitly.
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        if let hit = super.hitTest(point, with: event) { return hit }
        guard isUserInteractionEnabled, !isHidden, alpha > 0.01 else { return nil }
        for btn in commandButtons where !btn.isHidden && btn.isUserInteractionEnabled && btn.alpha > 0.01 {
            let local = convert(point, to: btn)
            if btn.bounds.contains(local) { return btn }
        }
        return nil
    }
}
