//
//  NumpadView.swift
//  J2MEEmulator
//
//  Reusable numpad control: 0-9, *, # + soft keys + command buttons.
//

import UIKit

class NumpadView: UIView {

    static let KEY_SOFT_LEFT: Int32  = -6
    static let KEY_SOFT_RIGHT: Int32 = -7

    private var repeatTimer: Timer?
    private var repeatKeyCode: Int32 = 0
    private var commandButtons: [UIButton] = []
    private let haptic = UIImpactFeedbackGenerator(style: .light)

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func setup() {
        let numpad: [(String, Int32)] = [
            ("1", 49), ("2", 50), ("3", 51),
            ("4", 52), ("5", 53), ("6", 54),
            ("7", 55), ("8", 56), ("9", 57),
            ("*", 42), ("0", 48), ("#", 35),
        ]
        for (title, code) in numpad {
            let btn = UIButton(type: .system)
            btn.setTitle(title, for: .normal)
            btn.titleLabel?.font = .systemFont(ofSize: 18, weight: .bold)
            btn.setTitleColor(.white, for: .normal)
            btn.backgroundColor = UIColor(white: 0.12, alpha: 1)
            btn.layer.cornerRadius = 10
            btn.layer.borderColor = UIColor(white: 1, alpha: 0.12).cgColor
            btn.layer.borderWidth = 1
            btn.tag = Int(code)
            btn.addTarget(self, action: #selector(down(_:)), for: .touchDown)
            btn.addTarget(self, action: #selector(up(_:)),
                          for: [.touchUpInside, .touchUpOutside, .touchCancel])
            addSubview(btn)
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let w = bounds.width
        let h = bounds.height

        let cols: CGFloat = 3
        let numRows: CGFloat = 4
        let gap: CGFloat = 3

        let btnW = (w - gap * (cols - 1)) / cols
        let btnH = (h - gap * (numRows - 1)) / numRows

        for sub in subviews {
            guard let btn = sub as? UIButton else { continue }
            let code = Int32(btn.tag)

            let (col, row): (Int, Int)
            switch code {
            case 49: (col, row) = (0, 0)
            case 50: (col, row) = (1, 0)
            case 51: (col, row) = (2, 0)
            case 52: (col, row) = (0, 1)
            case 53: (col, row) = (1, 1)
            case 54: (col, row) = (2, 1)
            case 55: (col, row) = (0, 2)
            case 56: (col, row) = (1, 2)
            case 57: (col, row) = (2, 2)
            case 42: (col, row) = (0, 3) // *
            case 48: (col, row) = (1, 3) // 0
            case 35: (col, row) = (2, 3) // #
            default: continue
            }
            btn.frame = CGRect(
                x: CGFloat(col) * (btnW + gap),
                y: CGFloat(row) * (btnH + gap),
                width: btnW, height: btnH)
        }

        layoutCommands()
    }

    // MARK: - Key events with repeat

    @objc private func down(_ sender: UIButton) {
        let code = Int32(sender.tag)
        haptic.impactOccurred(intensity: 0.6)
        j2me_input_post_key(Int32(J2ME_INPUT_KEY_PRESSED), code)
        sender.backgroundColor = UIColor(white: 0.30, alpha: 1)
        repeatKeyCode = code
        repeatTimer?.invalidate()
        repeatTimer = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: false) { [weak self] _ in
            self?.repeatTimer = Timer.scheduledTimer(withTimeInterval: 0.08, repeats: true) { [weak self] _ in
                guard let self, self.repeatKeyCode == code else { return }
                j2me_input_post_key(Int32(J2ME_INPUT_KEY_REPEATED), code)
            }
        }
    }

    @objc private func up(_ sender: UIButton) {
        j2me_input_post_key(Int32(J2ME_INPUT_KEY_RELEASED), Int32(sender.tag))
        sender.backgroundColor = UIColor(white: 0.12, alpha: 1)
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

            let btn = UIButton(type: .system)
            btn.setTitle(label, for: .normal)
            btn.titleLabel?.font = .boldSystemFont(ofSize: 12)
            btn.setTitleColor(.white, for: .normal)
            btn.backgroundColor = .systemBlue
            btn.layer.cornerRadius = 10
            btn.tag = 1000 + Int(cmdId)
            btn.addTarget(self, action: #selector(commandTapped(_:)), for: .touchUpInside)
            addSubview(btn)
            commandButtons.append(btn)
        }
        setNeedsLayout()
    }

    private func layoutCommands() {
        guard !commandButtons.isEmpty else { return }
        let w = bounds.width
        // Place command buttons below the soft keys, stacked vertically on the right
        // We'll use a column on the right side
        let btnW = w * 0.45
        let btnH: CGFloat = 26
        let gap: CGFloat = 3
        // Start from the bottom of the view
        for (i, btn) in commandButtons.reversed().enumerated() {
            let y = bounds.height - CGFloat(i + 1) * (btnH + gap)
            btn.frame = CGRect(x: w - btnW, y: y, width: btnW, height: btnH)
        }
    }

    @objc private func commandTapped(_ sender: UIButton) {
        j2me_input_post_key(Int32(J2ME_UI_COMMAND_ACTION), Int32(sender.tag - 1000))
    }
}
