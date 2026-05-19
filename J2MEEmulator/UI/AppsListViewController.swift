//
//  AppsListViewController.swift
//  J2MEEmulator
//
//  Game library — A1 · Minimal layout from design/library.jsx.
//  Same neumorphic background as the in-game screen, 4-column icon grid,
//  round neumo "+" button in the top-right corner.
//

import UIKit
import UniformTypeIdentifiers

extension Notification.Name {
    /// Posted by SceneDelegate after one or more JARs are imported via
    /// "Open in JarBox" / share sheet — AppsListViewController listens and
    /// triggers a library refresh.
    static let jarsImported = Notification.Name("jarsImported")
}

class AppsListViewController: UIViewController,
                      UICollectionViewDataSource,
                      UICollectionViewDelegate,
                      UIDocumentPickerDelegate {

    private let backgroundView = NeumoBackgroundView()
    private var springboardCollectionView: UICollectionView!
    private let emptyStateLabel = UILabel()
    private let addButton = NeumoButton()
    private var lastLayoutWidth: CGFloat = 0

    // Design reference (design/library.jsx, A1 · Minimal) — positions measured from
    // the artboard's top edge (which already includes the status-bar area):
    //   plus button top: 68, right: 18, size 48 (round)
    //   grid top: 144      ⇒ 28pt gap below the plus button
    //   grid bottom: 50
    // iPhone safe.top in portrait ≈ 47pt, so subtract that to anchor against safe.top.
    private enum Layout {
        static let columns: CGFloat = 4
        static let sidePadding: CGFloat = 24
        static let columnGap: CGFloat = 18
        static let rowGap: CGFloat = 22
        static let plusSize: CGFloat = 48
        static let plusRightInset: CGFloat = 18
        // Reference distances measured from the artboard top.
        static let plusTopFromArtboardTop: CGFloat = 68
        static let gridTopFromArtboardTop: CGFloat = 144
        static let gridBottomFromArtboardBottom: CGFloat = 50
    }

    /// Directory where imported JARs are stored
    private static var gamesDirectory: String {
        documentsDirectory + "/games"
    }

    override var preferredStatusBarStyle: UIStatusBarStyle { .lightContent }
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask { .portrait }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = NeumoPalette.bgBase2

        // Neumo background — layered gradients + grain (same as in-game screen).
        backgroundView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(backgroundView)
        NSLayoutConstraint.activate([
            backgroundView.topAnchor.constraint(equalTo: view.topAnchor),
            backgroundView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            backgroundView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            backgroundView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

        let layout = UICollectionViewFlowLayout()
        layout.scrollDirection = .vertical
        layout.minimumInteritemSpacing = Layout.columnGap
        layout.minimumLineSpacing = Layout.rowGap

        springboardCollectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        springboardCollectionView.dataSource = self
        springboardCollectionView.delegate = self
        springboardCollectionView.backgroundColor = .clear
        springboardCollectionView.alwaysBounceVertical = true
        springboardCollectionView.showsVerticalScrollIndicator = false
        springboardCollectionView.register(SpringboardCell.self,
                                           forCellWithReuseIdentifier: SpringboardCell.reuseID)
        // Manage insets manually so the grid lines up with the reference (status-bar-relative).
        springboardCollectionView.contentInsetAdjustmentBehavior = .never
        springboardCollectionView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(springboardCollectionView)

        NSLayoutConstraint.activate([
            springboardCollectionView.topAnchor.constraint(equalTo: view.topAnchor),
            springboardCollectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            springboardCollectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            springboardCollectionView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

        // Round neumo "+" button — top-right corner under the status bar.
        addButton.cornerRadius = Layout.plusSize / 2
        let cfg = UIImage.SymbolConfiguration(pointSize: 22, weight: .semibold)
        addButton.configureAsIcon(image: UIImage(systemName: "plus", withConfiguration: cfg))
        addButton.addTarget(self, action: #selector(addAppTapped), for: .touchUpInside)
        addButton.translatesAutoresizingMaskIntoConstraints = true
        view.addSubview(addButton)

        // Empty state
        emptyStateLabel.text = "No Games Yet\nTap + to add a .jar file"
        emptyStateLabel.textColor = NeumoPalette.label
        emptyStateLabel.font = .systemFont(ofSize: 17)
        emptyStateLabel.textAlignment = .center
        emptyStateLabel.numberOfLines = 0
        emptyStateLabel.isHidden = true
        emptyStateLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(emptyStateLabel)
        NSLayoutConstraint.activate([
            emptyStateLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            emptyStateLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor, constant: -40),
            emptyStateLabel.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 40),
        ])

        // Ensure games directory exists
        try? FileManager.default.createDirectory(atPath: Self.gamesDirectory,
                                                  withIntermediateDirectories: true)
        scanApps()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        // Library screen owns its own "+" button — hide the system nav bar.
        navigationController?.setNavigationBarHidden(true, animated: animated)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        NotificationCenter.default.addObserver(self, selector: #selector(appDidBecomeActive),
                                               name: UIApplication.didBecomeActiveNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(jarImported),
                                               name: .jarsImported, object: nil)
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        NotificationCenter.default.removeObserver(self, name: UIApplication.didBecomeActiveNotification, object: nil)
        NotificationCenter.default.removeObserver(self, name: .jarsImported, object: nil)
    }

    @objc private func appDidBecomeActive() {
        scanApps()
    }

    @objc private func jarImported() {
        scanApps()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let width = view.bounds.width
        let height = view.bounds.height

        // Reference distances are measured from the artboard's *physical* top/bottom,
        // not from the safe area — `top: 68` already sits below the status bar in the design.
        let plusY = max(Layout.plusTopFromArtboardTop, view.safeAreaInsets.top + 4)
        let gridTop = max(Layout.gridTopFromArtboardTop, plusY + Layout.plusSize + 28)
        let gridBottomInset = max(Layout.gridBottomFromArtboardBottom, view.safeAreaInsets.bottom + 16)

        // "+" button — pinned right, design Y from the top of the screen.
        addButton.frame = CGRect(
            x: width - Layout.plusRightInset - Layout.plusSize,
            y: plusY,
            width: Layout.plusSize, height: Layout.plusSize)

        guard width > 0, width != lastLayoutWidth else { return }
        lastLayoutWidth = width

        let columns = Layout.columns
        let sidePad = Layout.sidePadding
        let gap = Layout.columnGap
        let cellWidth = floor((width - 2 * sidePad - (columns - 1) * gap) / columns)
        let cellHeight = SpringboardCell.iconSize + SpringboardCell.iconToLabelGap + SpringboardCell.labelHeight

        guard let layout = springboardCollectionView.collectionViewLayout as? UICollectionViewFlowLayout else { return }
        layout.itemSize = CGSize(width: cellWidth, height: cellHeight)
        layout.sectionInset = UIEdgeInsets(
            top: gridTop,
            left: sidePad,
            bottom: gridBottomInset,
            right: sidePad)

        _ = height // (kept for future use if we need to anchor against physical bottom)
    }

    // ============================================================
    // MARK: - Import JAR from Files
    // ============================================================

    @objc private func addAppTapped() {
        let jarType = UTType(filenameExtension: "jar") ?? .data
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [jarType])
        picker.delegate = self
        picker.allowsMultipleSelection = true
        present(picker, animated: true)
    }

    func documentPicker(_ controller: UIDocumentPickerViewController,
                        didPickDocumentsAt urls: [URL]) {
        let imported = Self.importJars(from: urls)
        if imported > 0 {
            scanApps()
        }
    }

    /// Copy one or more `.jar` URLs into Documents/games/ — used by both the
    /// in-app document picker and the Scene URL handler (Files long-press
    /// "Open in JarBox" or sharing a JAR from another app). Returns the
    /// number of files actually copied.
    @discardableResult
    static func importJars(from urls: [URL]) -> Int {
        let fm = FileManager.default
        try? fm.createDirectory(atPath: gamesDirectory, withIntermediateDirectories: true)
        var imported = 0

        for url in urls {
            guard url.pathExtension.lowercased() == "jar" else { continue }
            let accessing = url.startAccessingSecurityScopedResource()
            defer { if accessing { url.stopAccessingSecurityScopedResource() } }

            let destURL = URL(fileURLWithPath: gamesDirectory)
                .appendingPathComponent(url.lastPathComponent)

            // Tap-to-open from Files on a JAR that is already in our games/
            // folder hands us back the same path we'd copy to. Without this
            // guard we'd removeItem(dest) — wiping the source — and then fail
            // on copyItem, losing the file. Compare canonical paths so symlinks
            // and ./.. don't fool us.
            let srcPath = url.resolvingSymlinksInPath().standardizedFileURL.path
            let dstPath = destURL.resolvingSymlinksInPath().standardizedFileURL.path
            if srcPath == dstPath { continue }

            // Different file with the same name — treat as an update, overwrite.
            try? fm.removeItem(at: destURL)

            do {
                try fm.copyItem(at: url, to: destURL)
                imported += 1
            } catch {
                print("[Swift] Failed to import \(url.lastPathComponent): \(error)")
            }
        }
        return imported
    }

    // ============================================================
    // MARK: - App scanning (Documents/games/)
    // ============================================================

    struct AppInfo {
        let name: String
        let path: String
        let fileName: String
        let version: String?
        let vendor: String?
        let icon: UIImage
    }
    private var apps: [AppInfo] = []

    private func scanApps() {
        let gamesDir = Self.gamesDirectory

        DispatchQueue.global(qos: .userInitiated).async {
            var jarPaths: [(name: String, path: String)] = []

            if let files = try? FileManager.default.contentsOfDirectory(atPath: gamesDir) {
                for file in files where file.hasSuffix(".jar") {
                    jarPaths.append((name: String(file.dropLast(4)), path: gamesDir + "/" + file))
                }
            }

            var unsorted = jarPaths.map { jar -> (String, String, String, String?, String?, UIImage?) in
                let meta = JARMetadata.read(from: jar.path)
                let jarIcon = meta?.readIcon(from: jar.path)
                let fileName = URL(fileURLWithPath: jar.path).lastPathComponent
                let appName = meta?.midletName ?? jar.name
                return (appName, jar.path, fileName, meta?.version, meta?.vendor, jarIcon)
            }
            unsorted.sort { $0.0.localizedCaseInsensitiveCompare($1.0) == .orderedAscending }

            let scannedApps = unsorted.enumerated().map { (index, t) in
                AppInfo(name: t.0, path: t.1, fileName: t.2,
                        version: t.3, vendor: t.4,
                        icon: Self.springboardIcon(t.5, name: t.0, index: index))
            }

            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.apps = scannedApps
                self.springboardCollectionView.reloadData()
                self.emptyStateLabel.isHidden = !scannedApps.isEmpty
                print("[Swift] Found \(scannedApps.count) MIDlet JARs in \(gamesDir)")
            }
        }
    }

    // ============================================================
    // MARK: - Icon generation
    // ============================================================

    private static let iconSize: CGFloat = SpringboardCell.iconSize

    private static let placeholderGradients: [(UIColor, UIColor)] = [
        (UIColor(red: 0.20, green: 0.40, blue: 0.90, alpha: 1),
         UIColor(red: 0.35, green: 0.60, blue: 1.00, alpha: 1)),
        (UIColor(red: 0.00, green: 0.68, blue: 0.63, alpha: 1),
         UIColor(red: 0.20, green: 0.85, blue: 0.60, alpha: 1)),
        (UIColor(red: 0.95, green: 0.55, blue: 0.15, alpha: 1),
         UIColor(red: 1.00, green: 0.75, blue: 0.28, alpha: 1)),
        (UIColor(red: 0.88, green: 0.22, blue: 0.28, alpha: 1),
         UIColor(red: 1.00, green: 0.42, blue: 0.48, alpha: 1)),
        (UIColor(red: 0.58, green: 0.28, blue: 0.85, alpha: 1),
         UIColor(red: 0.72, green: 0.48, blue: 1.00, alpha: 1)),
        (UIColor(red: 0.22, green: 0.30, blue: 0.80, alpha: 1),
         UIColor(red: 0.38, green: 0.48, blue: 0.95, alpha: 1)),
        (UIColor(red: 0.90, green: 0.28, blue: 0.52, alpha: 1),
         UIColor(red: 1.00, green: 0.48, blue: 0.68, alpha: 1)),
        (UIColor(red: 0.15, green: 0.65, blue: 0.42, alpha: 1),
         UIColor(red: 0.28, green: 0.82, blue: 0.55, alpha: 1)),
    ]

    private static func springboardIcon(_ jarIcon: UIImage?, name: String, index: Int) -> UIImage {
        let size = CGSize(width: iconSize, height: iconSize)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { ctx in
            let rect = CGRect(origin: .zero, size: size)

            // Render as a flat square — the cell applies a continuous-corner
            // mask (cornerCurve = .continuous) and a CALayer border, which
            // together give iOS-Springboard squircle corners. Pre-clipping
            // here with UIBezierPath(roundedRect:cornerRadius:) would bake in
            // a circular-arc rounded rect that doesn't match the squircle and
            // would poke out at the corner extremes.

            if let img = jarIcon {
                UIColor(white: 0.22, alpha: 1).setFill()
                UIBezierPath(rect: rect).fill()
                img.draw(in: rect)
            } else {
                let pair = placeholderGradients[index % placeholderGradients.count]
                let cgCtx = ctx.cgContext
                let colorSpace = CGColorSpaceCreateDeviceRGB()
                if let gradient = CGGradient(colorsSpace: colorSpace,
                                              colors: [pair.0.cgColor, pair.1.cgColor] as CFArray,
                                              locations: [0, 1]) {
                    cgCtx.drawLinearGradient(gradient, start: .zero,
                                             end: CGPoint(x: iconSize, y: iconSize), options: [])
                }
                let letter = String(name.prefix(1)).uppercased()
                let attrs: [NSAttributedString.Key: Any] = [
                    .foregroundColor: UIColor.white.withAlphaComponent(0.9),
                    .font: UIFont.systemFont(ofSize: iconSize * 0.5, weight: .bold)
                ]
                let strSize = (letter as NSString).size(withAttributes: attrs)
                (letter as NSString).draw(
                    at: CGPoint(x: (iconSize - strSize.width) / 2,
                                y: (iconSize - strSize.height) / 2),
                    withAttributes: attrs)
            }
        }
    }

    // ============================================================
    // MARK: - UICollectionView
    // ============================================================

    func collectionView(_ collectionView: UICollectionView,
                        numberOfItemsInSection section: Int) -> Int {
        apps.count
    }

    func collectionView(_ collectionView: UICollectionView,
                        cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(
            withReuseIdentifier: SpringboardCell.reuseID, for: indexPath) as! SpringboardCell
        let app = apps[indexPath.item]
        cell.configure(name: app.name, icon: app.icon)
        return cell
    }

    func collectionView(_ collectionView: UICollectionView,
                        contextMenuConfigurationForItemsAt indexPaths: [IndexPath],
                        point: CGPoint) -> UIContextMenuConfiguration? {
        guard let indexPath = indexPaths.first else { return nil }
        let app = apps[indexPath.item]
        return UIContextMenuConfiguration(identifier: indexPath as NSIndexPath,
                                          previewProvider: nil,
                                          actionProvider: { [weak self] _ in
            let ssEnabled = Self.is3DSupersampling(for: app)
            let toggle3D = UIAction(title: ssEnabled ? "Disable 3D Enhancement" : "Enable 3D Enhancement",
                                    subtitle: ssEnabled ? "Lower quality, but closer to original" : "Smoother 3D, but not original-accurate",
                                    image: UIImage(systemName: "cube"),
                                    state: ssEnabled ? .on : .off) { _ in
                Self.set3DSupersampling(!ssEnabled, for: app)
            }
            let clearData = UIAction(title: "Clear Game Data",
                                     image: UIImage(systemName: "eraser")) { _ in
                self?.confirmClearGameData(for: app)
            }
            let delete = UIAction(title: "Delete", image: UIImage(systemName: "trash"),
                                  attributes: .destructive) { _ in
                self?.confirmDeleteApp(at: indexPath)
            }
            let currentRes = Self.resolution(for: app)
            let resActions = Self.resolutionOptions.map { opt in
                UIAction(title: opt.label,
                         state: (opt.w == currentRes.w && opt.h == currentRes.h) ? .on : .off) { _ in
                    Self.setResolution(w: opt.w, h: opt.h, for: app)
                }
            }
            let resMenu = UIMenu(title: "Screen Resolution",
                                  image: UIImage(systemName: "aspectratio"),
                                  children: resActions)

            let currentFps = Self.fpsLimit(for: app)
            let fpsActions = Self.fpsLimitOptions.map { opt in
                UIAction(title: opt.label,
                         state: opt.value == currentFps ? .on : .off) { _ in
                    Self.setFpsLimit(opt.value, for: app)
                }
            }
            let fpsMenu = UIMenu(title: "FPS Limit",
                                  subtitle: "High FPS may break some games",
                                  image: UIImage(systemName: "gauge.with.needle"),
                                  children: fpsActions)

            let settings = UIMenu(options: .displayInline, children: [toggle3D, resMenu, fpsMenu])
            let actions = UIMenu(options: .displayInline, children: [clearData, delete])
            return UIMenu(children: [settings, actions])
        })
    }

    // Context-menu preview — target only the icon (rounded). The cell's title stays
    // exactly where it is; UIKit smoothly scales the icon up into the preview state,
    // matching the iOS home-screen long-press feel.
    func collectionView(_ collectionView: UICollectionView,
                        contextMenuConfiguration configuration: UIContextMenuConfiguration,
                        highlightPreviewForItemAt indexPath: IndexPath) -> UITargetedPreview? {
        return makeIconTargetPreview(at: indexPath, in: collectionView)
    }

    func collectionView(_ collectionView: UICollectionView,
                        contextMenuConfiguration configuration: UIContextMenuConfiguration,
                        dismissalPreviewForItemAt indexPath: IndexPath) -> UITargetedPreview? {
        return makeIconTargetPreview(at: indexPath, in: collectionView)
    }

    private func makeIconTargetPreview(at indexPath: IndexPath,
                                       in collectionView: UICollectionView) -> UITargetedPreview? {
        guard let cell = collectionView.cellForItem(at: indexPath) as? SpringboardCell else {
            return nil
        }
        let params = UIPreviewParameters()
        params.backgroundColor = .clear
        params.visiblePath = UIBezierPath(
            roundedRect: cell.iconView.bounds,
            cornerRadius: SpringboardCell.iconCornerRadius)
        return UITargetedPreview(view: cell.iconView, parameters: params)
    }

    // MARK: - Per-game settings

    private static func gameId(for app: AppInfo) -> String {
        let jarName = URL(fileURLWithPath: app.path).deletingPathExtension().lastPathComponent
        return jarName.replacingOccurrences(of: "[^a-zA-Z0-9._-]", with: "_", options: .regularExpression)
    }

    static func is3DSupersampling(for app: AppInfo) -> Bool {
        UserDefaults.standard.object(forKey: "ss3d_\(gameId(for: app))") as? Bool ?? true
    }

    static func set3DSupersampling(_ enabled: Bool, for app: AppInfo) {
        UserDefaults.standard.set(enabled, forKey: "ss3d_\(gameId(for: app))")
    }

    private static let resolutionOptions: [(label: String, w: Int, h: Int)] = [
        // Common J2ME resolutions (portrait / square only)
        ("101×80",   101,  80),
        ("128×128",  128, 128),
        ("128×160",  128, 160),
        ("132×176",  132, 176),
        ("160×128",  160, 128),
        ("176×208",  176, 208),
        ("176×220",  176, 220),
        ("208×208",  208, 208),
        ("220×220",  220, 220),
        ("240×266",  240, 266),
        ("240×320",  240, 320),
        ("240×400",  240, 400),
        ("320×480",  320, 480),
        ("352×416",  352, 416),
        ("360×640",  360, 640),
        ("480×800",  480, 800),
    ]

    static func resolution(for app: AppInfo) -> (w: Int, h: Int) {
        let gid = gameId(for: app)
        let w = UserDefaults.standard.object(forKey: "resW_\(gid)") as? Int ?? 240
        let h = UserDefaults.standard.object(forKey: "resH_\(gid)") as? Int ?? 320
        return (w, h)
    }

    private static func setResolution(w: Int, h: Int, for app: AppInfo) {
        let gid = gameId(for: app)
        UserDefaults.standard.set(w, forKey: "resW_\(gid)")
        UserDefaults.standard.set(h, forKey: "resH_\(gid)")
    }

    private static let fpsLimitOptions: [(label: String, value: Int)] = [
        ("Unlimited", 0),
        ("15 FPS",   15),
        ("20 FPS",   20),
        ("30 FPS",   30),
        ("60 FPS",   60),
    ]

    static func fpsLimit(for app: AppInfo) -> Int {
        UserDefaults.standard.object(forKey: "fpsLimit_\(gameId(for: app))") as? Int ?? 60
    }

    private static func setFpsLimit(_ fps: Int, for app: AppInfo) {
        UserDefaults.standard.set(fps, forKey: "fpsLimit_\(gameId(for: app))")
    }

    private static var documentsDirectory: String {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!.path
    }

    private func confirmClearGameData(for app: AppInfo) {
        let alert = UIAlertController(title: "Clear Game Data",
                                       message: "Delete all save data for \(app.name)?",
                                       preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Clear", style: .destructive) { _ in
            let gid = Self.gameId(for: app)
            try? FileManager.default.removeItem(atPath: Self.documentsDirectory + "/Games Data/" + gid)
        })
        present(alert, animated: true)
    }

    private func confirmDeleteApp(at indexPath: IndexPath) {
        let app = apps[indexPath.item]
        let alert = UIAlertController(title: "Delete Game",
                                       message: "Delete \(app.name) and all its save data?",
                                       preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Delete", style: .destructive) { [weak self] _ in
            guard let self else { return }
            let gid = Self.gameId(for: app)
            try? FileManager.default.removeItem(atPath: Self.documentsDirectory + "/Games Data/" + gid)
            try? FileManager.default.removeItem(atPath: app.path)
            self.springboardCollectionView.performBatchUpdates {
                self.apps.remove(at: indexPath.item)
                self.springboardCollectionView.deleteItems(at: [indexPath])
            }
            self.emptyStateLabel.isHidden = !self.apps.isEmpty
        })
        present(alert, animated: true)
    }

    func collectionView(_ collectionView: UICollectionView,
                        didSelectItemAt indexPath: IndexPath) {
        let app = apps[indexPath.item]

        let render3dScale = Self.is3DSupersampling(for: app) ? 3 : 1
        let res = Self.resolution(for: app)
        let fps = Self.fpsLimit(for: app)
        let gameVC = GameViewController(jarPath: app.path, appName: app.name, appIcon: app.icon,
                                         canvasWidth: res.w, canvasHeight: res.h,
                                         render3dScale: render3dScale, fpsLimit: fps)
        gameVC.modalPresentationStyle = .fullScreen
        present(gameVC, animated: true)
    }
}
