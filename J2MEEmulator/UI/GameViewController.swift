//
//  GameViewController.swift
//  J2MEEmulator
//
//  Runs a single J2ME MIDlet. Presented modally with zoom transition.
//  Layout mode determines the arrangement of screen and controls.
//  Visual treatment — Soft 3D / Neumorphic (design/variants.jsx → NeumoVariant).
//

import UIKit

// MARK: - Layout mode (extensible for future layouts)

enum GameLayoutMode {
    case ngage      // Landscape: D-pad left, screen center, numpad right
    // Future: .classic   — Portrait: screen top, keyboard bottom
    // Future: .fullscreen — Landscape: screen fills, overlay controls
}

// MARK: - GameViewController

class GameViewController: UIViewController {

    let jarPath: String
    let appName: String
    let appIcon: UIImage
    let canvasWidth: Int
    let canvasHeight: Int
    let render3dScale: Int
    let fpsLimit: Int
    let layoutMode: GameLayoutMode

    private let backgroundView = NeumoBackgroundView()
    private let screenFrame = NeumoScreenFrame()
    private let emulatorView = EmulatorView()
    private lazy var formView = FormView()
    private lazy var listView = J2MEListView()
    private let closeButton = NeumoButton()
    private let lskButton = NeumoButton()
    private let rskButton = NeumoButton()
    private let softKeyHaptic = UIImpactFeedbackGenerator(style: .light)

    // Controls — created based on layoutMode
    private var joystickView: JoystickView?
    private var numpadView: NumpadView?

    // Layout cache
    private var canvasRatio: CGFloat = 1
    private var lastBounds: CGRect = .zero

    init(jarPath: String, appName: String, appIcon: UIImage,
         canvasWidth: Int = 240, canvasHeight: Int = 320,
         render3dScale: Int = 3, fpsLimit: Int = 0,
         layoutMode: GameLayoutMode = .ngage) {
        self.jarPath = jarPath
        self.appName = appName
        self.appIcon = appIcon
        self.canvasWidth = canvasWidth
        self.canvasHeight = canvasHeight
        self.render3dScale = render3dScale
        self.fpsLimit = fpsLimit
        self.layoutMode = layoutMode
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    deinit {
        setGlobalEmulatorView(nil)
        alertTimeoutWork?.cancel()
    }

    private var alertTimeoutWork: DispatchWorkItem?

    override var prefersStatusBarHidden: Bool { true }

    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        switch layoutMode {
        case .ngage: return .landscape
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        canvasRatio = CGFloat(canvasWidth) / CGFloat(canvasHeight)

        emulatorView.canvasWidth = canvasWidth
        emulatorView.canvasHeight = canvasHeight

        switch layoutMode {
        case .ngage: setupNGageLayout()
        }

        // Register native callbacks
        setGlobalEmulatorView(emulatorView)
        j2me_render_set_flush_callback(flushCallback)
        j2me_ui_set_callback(gameUICallback)
        activeGameViewController = self
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        startGame()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        guard view.bounds != lastBounds else { return }
        lastBounds = view.bounds
        layoutControls()
    }

    // ============================================================
    // MARK: - N-Gage layout (Neumorphic)
    // ============================================================
    //
    //  Landscape arrangement mirroring design/variants.jsx NeumoVariant.
    //  All sizes derive from `designUnit` so the layout scales across
    //  iPhone / iPad while preserving the proportions of the reference.

    private func setupNGageLayout() {
        // Background — full screen neumo gradient + noise.
        view.addSubview(backgroundView)
        backgroundView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            backgroundView.topAnchor.constraint(equalTo: view.topAnchor),
            backgroundView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            backgroundView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            backgroundView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

        // Joystick + Numpad
        let joystick = JoystickView()
        let numpad = NumpadView()
        self.joystickView = joystick
        self.numpadView = numpad

        // Soft keys (L/R) — neumo buttons sized like keypad keys.
        for (btn, title) in [(lskButton, "L"), (rskButton, "R")] {
            btn.configureAsSoft(glyph: title, fontSize: 22)
            btn.cornerRadius = 20
            btn.addTarget(self, action: #selector(softKeyDown(_:)), for: .touchDown)
            btn.addTarget(self, action: #selector(softKeyUp(_:)),
                          for: [.touchUpInside, .touchUpOutside, .touchCancel])
        }
        lskButton.tag = -6
        rskButton.tag = -7

        // Close — neumo button with SF Symbol xmark glyph.
        closeButton.cornerRadius = 16
        let cfg = UIImage.SymbolConfiguration(pointSize: 18, weight: .semibold)
        closeButton.configureAsIcon(image: UIImage(systemName: "xmark", withConfiguration: cfg))
        closeButton.addTarget(self, action: #selector(backTapped), for: .touchUpInside)

        // Add everything (order matters — back to front).
        view.addSubview(screenFrame)
        screenFrame.addSubview(emulatorView)
        view.addSubview(joystick)
        view.addSubview(numpad)
        view.addSubview(lskButton)
        view.addSubview(rskButton)
        view.addSubview(closeButton)
        view.addSubview(formView)
        view.addSubview(listView)

        // Frame-based controls — viewDidLayoutSubviews positions them via designUnit.
        for v: UIView in [screenFrame, emulatorView, joystick, numpad,
                          lskButton, rskButton, closeButton] {
            v.translatesAutoresizingMaskIntoConstraints = true
        }

        // Auto Layout for full-screen overlays.
        for v in [formView, listView] {
            v.translatesAutoresizingMaskIntoConstraints = false
        }
        NSLayoutConstraint.activate([
            formView.topAnchor.constraint(equalTo: view.topAnchor),
            formView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            formView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            formView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            listView.topAnchor.constraint(equalTo: view.topAnchor),
            listView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            listView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            listView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

        formView.isHidden = true
        listView.isHidden = true

        view.bringSubviewToFront(formView)
        view.bringSubviewToFront(listView)
        view.bringSubviewToFront(closeButton)
    }

    // MARK: - Frame-based layout (called whenever bounds change)

    private func layoutControls() {
        let safe = view.safeAreaLayoutGuide.layoutFrame
        guard safe.width > 0 && safe.height > 0 else { return }

        // The game screen ignores the bottom safe area — its bottom margin mirrors the
        // top one measured from the physical edge of the view. Soft keys (L/R) stay anchored
        // to the safe-area bottom so they don't slide down with the extended screen.
        let physicalBottom = view.bounds.maxY
        let extendedHeight = physicalBottom - safe.minY   // from safe top to physical bottom

        // Design reference artboard is 1556×720. Pick the smaller of height/width-constrained
        // units so the layout fits both phone and tablet aspect ratios.
        let canvasRatio = self.canvasRatio
        let unitFromHeight = extendedHeight / 720.0
        // screenW (canvas+pad) ≈ unit * (canvas.h * ratio + 2*pad) ≈ unit*(652*ratio + 28)
        // side panels: unit * (dpad 360 + gap + outer ≥ 10) ×2
        let sideGap: CGFloat = 40
        let widthRequired = 652 * canvasRatio + 28 + 2 * (360 + sideGap + 10)
        let unitFromWidth = safe.width / widthRequired
        let unit = min(unitFromHeight, unitFromWidth)

        // ── Screen bezel ──
        // Top inset from safe.minY mirrors the bottom inset from view's physical bottom.
        let topInset: CGFloat = unit * 20
        let bezelPad = unit * 14
        let bezelY   = safe.minY + topInset
        let bezelH   = (physicalBottom - topInset) - bezelY
        let canvasH  = bezelH - 2 * bezelPad
        let canvasW  = canvasH * canvasRatio
        let bezelW   = canvasW + 2 * bezelPad
        let bezelX   = safe.midX - bezelW / 2
        screenFrame.frame = CGRect(x: bezelX, y: bezelY, width: bezelW, height: bezelH)
        screenFrame.canvasPadding = bezelPad
        screenFrame.bezelCornerRadius = unit * 18
        screenFrame.wellCornerRadius  = unit * 6

        // Canvas sits inside the bezel padding.
        emulatorView.frame = CGRect(x: bezelPad, y: bezelPad, width: canvasW, height: canvasH)
        emulatorView.layer.cornerRadius = screenFrame.canvasCornerRadius
        emulatorView.clipsToBounds = true

        // Screen edges in view coords — used to anchor side controls.
        let screenLeft  = bezelX + bezelPad
        let screenRight = bezelX + bezelW - bezelPad

        // ── D-pad / joystick ──
        // CSS reference: width 360*unit, top 122. Side gap pulled out to `sideGap` (above).
        if let joystick = joystickView {
            let dpadSize = unit * 360
            let dpadX = screenLeft - unit * sideGap - dpadSize
            let dpadY = safe.minY + unit * 122
            joystick.frame = CGRect(x: dpadX, y: dpadY, width: dpadSize, height: dpadSize)
        }

        // ── Numpad ──
        // CSS reference: top 110, width = 3*92 + 2*12, height = 4*92 + 3*12.
        if let numpad = numpadView {
            let keypadW = unit * (3 * 92 + 2 * 12)
            let keypadH = unit * (4 * 92 + 3 * 12)
            let keypadX = screenRight + unit * sideGap
            let keypadY = safe.minY + unit * 110
            numpad.frame = CGRect(x: keypadX, y: keypadY, width: keypadW, height: keypadH)
        }

        // ── Soft keys L / R ──
        // L/R stay pinned to the old screen-bottom-in-safe-area position (so they don't
        // slide down with the now-extended canvas) and sit a bit further out horizontally.
        // Width is 1.5× the CSS reference (96 → 144) for a more comfortable thumb target.
        let softW = unit * 144
        let softH = unit * 82
        let softGap = unit * 22
        let softY = safe.maxY - topInset - softH
        lskButton.frame = CGRect(x: screenLeft - softGap - softW, y: softY, width: softW, height: softH)
        rskButton.frame = CGRect(x: screenRight + softGap,         y: softY, width: softW, height: softH)

        // ── Close ──
        // CSS: left 28, top 28, width/height 52.
        let closeSize = unit * 52
        let closePad  = unit * 28
        closeButton.frame = CGRect(
            x: safe.minX + closePad,
            y: safe.minY + closePad,
            width: closeSize, height: closeSize)
        closeButton.cornerRadius = unit * 16

        // Recompute key corners after layout.
        let keyCorner = unit * 20
        lskButton.cornerRadius = keyCorner
        rskButton.cornerRadius = keyCorner

        // L/R glyph — same point size as numpad digits (28pt at unit=1).
        let softGlyphPt = max(12, unit * 28)
        lskButton.configureAsSoft(glyph: "L", fontSize: softGlyphPt)
        rskButton.configureAsSoft(glyph: "R", fontSize: softGlyphPt)

        // Re-render close glyph at the right point size — design icon is 22pt at 52pt button.
        let closeGlyphPt = max(10, unit * 22)
        let cfg = UIImage.SymbolConfiguration(pointSize: closeGlyphPt, weight: .semibold)
        closeButton.configureAsIcon(image: UIImage(systemName: "xmark", withConfiguration: cfg))
    }

    // MARK: - Soft keys

    @objc private func softKeyDown(_ sender: NeumoButton) {
        softKeyHaptic.impactOccurred(intensity: 0.6)
        j2me_input_post_key(Int32(J2ME_INPUT_KEY_PRESSED), Int32(sender.tag))
    }

    @objc private func softKeyUp(_ sender: NeumoButton) {
        j2me_input_post_key(Int32(J2ME_INPUT_KEY_RELEASED), Int32(sender.tag))
    }

    // ============================================================
    // MARK: - Game lifecycle
    // ============================================================

    private func startGame() {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.runMIDlet()
            DispatchQueue.main.async {
                self?.dismiss(animated: true)
            }
        }
    }

    private func runMIDlet() {
        guard let resRoot = Bundle.main.resourcePath else { return }
        let docs = NSSearchPathForDirectoriesInDomains(
            .documentDirectory, .userDomainMask, true).first ?? NSTemporaryDirectory()

        // Per-game save directory: Documents/Games Data/{jarFilename}/
        let jarFileName = URL(fileURLWithPath: jarPath).deletingPathExtension().lastPathComponent
        let gameId = jarFileName.replacingOccurrences(of: "[^a-zA-Z0-9._-]",
                                                       with: "_", options: .regularExpression)
        let saveRoot = docs + "/Games Data/" + gameId
        try? FileManager.default.createDirectory(atPath: saveRoot, withIntermediateDirectories: true)

        let initResult = jvm_bridge_init(resRoot, saveRoot, jarPath,
                                         Int32(canvasWidth),
                                         Int32(canvasHeight),
                                         Int32(render3dScale),
                                         Int32(fpsLimit))
        guard initResult == 0 else {
            print("[Swift] ERROR: JVM init failed with code \(initResult)")
            return
        }

        let runResult = jvm_bridge_run_midlet(jarPath)
        print("[Swift] MIDlet run result: \(runResult)")
        jvm_bridge_destroy()
    }

    @objc private func backTapped() {
        closeButton.isEnabled = false
        jvm_bridge_request_stop()
    }

    // ============================================================
    // MARK: - View switching
    // ============================================================

    func showCanvasView() {
        emulatorView.isHidden = false
        joystickView?.isHidden = false
        numpadView?.isHidden = false
        formView.isHidden = true
        listView.isHidden = true
        numpadView?.updateCommands()
    }

    func showFormView() {
        formView.buildFromNativeData()
        formView.isHidden = false
        emulatorView.isHidden = true
        joystickView?.isHidden = true
        numpadView?.isHidden = true
        listView.isHidden = true
    }

    func showListView() {
        listView.buildFromNativeData()
        listView.isHidden = false
        emulatorView.isHidden = true
        joystickView?.isHidden = true
        numpadView?.isHidden = true
        formView.isHidden = true
    }

    func showAlert() {
        let title = String(cString: j2me_ui_get_form_title())
        let text = String(cString: j2me_ui_get_alert_text())

        let alert = UIAlertController(title: title, message: text, preferredStyle: .alert)

        alertTimeoutWork?.cancel()
        alertTimeoutWork = nil

        let cmdCount = j2me_ui_get_command_count()
        if cmdCount == 0 {
            alert.addAction(UIAlertAction(title: "OK", style: .default) { [weak self] _ in
                self?.alertTimeoutWork?.cancel()
                j2me_input_post_key(Int32(J2ME_UI_ALERT_DISMISSED), 0)
            })
        } else {
            for i in 0..<cmdCount {
                let label = String(cString: j2me_ui_get_command_label(Int32(i)))
                let cmdId = j2me_ui_get_command_id(Int32(i))
                alert.addAction(UIAlertAction(title: label, style: .default) { [weak self] _ in
                    self?.alertTimeoutWork?.cancel()
                    j2me_input_post_key(Int32(J2ME_UI_COMMAND_ACTION), cmdId)
                })
            }
        }

        present(alert, animated: true)

        let timeout = j2me_ui_get_alert_timeout()
        if timeout > 0 {
            let work = DispatchWorkItem { [weak alert] in
                alert?.dismiss(animated: true) {
                    j2me_input_post_key(Int32(J2ME_UI_ALERT_DISMISSED), 0)
                }
            }
            alertTimeoutWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(timeout) / 1000.0, execute: work)
        }
    }
}

// MARK: - Game UI callback (global)

private(set) weak var activeGameViewController: GameViewController?

let gameUICallback: @convention(c) (Int32, UnsafePointer<CChar>?) -> Void = { action, data in
    DispatchQueue.main.async {
        guard let vc = activeGameViewController else { return }
        switch action {
        case Int32(J2ME_UI_ACTION_SHOW_CANVAS):  vc.showCanvasView()
        case Int32(J2ME_UI_ACTION_SHOW_FORM):    vc.showFormView()
        case Int32(J2ME_UI_ACTION_SHOW_LIST):    vc.showListView()
        case Int32(J2ME_UI_ACTION_SHOW_ALERT):   vc.showAlert()
        default: break
        }
    }
}
