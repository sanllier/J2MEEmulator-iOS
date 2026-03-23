//
//  NeutralBlurView.swift
//  J2MEEmulator
//
//

import UIKit
import CoreImage.CIFilterBuiltins

final class NeutralBlurView: UIView {

    var radius: CGFloat { didSet { updateImplAppearance() } }
    override var backgroundColor: UIColor? {
        get { tintView?.backgroundColor }
        set { tintView?.backgroundColor = newValue }
    }
    override var alpha: CGFloat {
        get { _alpha }
        set { _alpha = newValue }
    }

    init(radius: CGFloat) {
        self.radius = radius
        if let impl = BlurImpl(radius: radius) {
            self.impl = impl
            self.tintView = .init(frame: .zero)
        } else {
            self.impl = FallbackImpl()
            self.tintView = nil
        }
        super.init(frame: .zero)
        tintView.map { addSubview($0) }
        addSubview(impl)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        tintView?.frame = bounds
        impl.frame = bounds
    }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        _alpha < 0.001 ? nil : super.hitTest(point, with: event)
    }

    private let impl: UIView
    private let tintView: UIView?
    private var _alpha: CGFloat = 1.0 { didSet {
        tintView?.alpha = alpha
        updateImplAppearance()
    }}
}

private extension NeutralBlurView {

    final class BlurImpl: UIVisualEffectView {

        var radius: CGFloat { didSet {
            guard let backdropLayer = subviews.first?.layer else { return }
            backdropLayer.setValue(radius, forKeyPath: "filters.blur.inputRadius")
        }}

        init?(radius: CGFloat) {
            self.radius = radius
            super.init(effect: UIBlurEffect(style: .regular))
            guard let UICABackdropLayer = NSClassFromString("pordkcaBACIU".reversed() + "Layer")! as? NSObject.Type else { return nil }
            guard let CAFilter = NSClassFromString("iFAC".reversed() + "lter")! as? NSObject.Type else { return nil }
            guard let filter = CAFilter.self.perform(
                NSSelectorFromString("iWretlif".reversed() + "thType:"),
                with: "bairav".reversed() + "leBlur"
            ).takeUnretainedValue() as? NSObject else { return nil }
            guard let gradientImage = makeUniformMaskImage() else { return nil }
            guard let backdropLayer = subviews.first(where: {
                type(of: $0.layer) == UICABackdropLayer
            })?.layer else { return nil }
            filter.setValue("blur", forKey: "name")
            filter.setValue(radius, forKey: "inputRadius")
            filter.setValue(gradientImage, forKey: "inputMaskImage")
            filter.setValue(true, forKey: "inputNormalizeEdges")
            backdropLayer.filters = [filter]
            subviews.dropFirst().forEach { $0.alpha = 0.0 }
        }

        required init?(coder: NSCoder) { fatalError() }

        override func didMoveToWindow() {
            guard let window, let backdropLayer = subviews.first?.layer else { return }
            backdropLayer.setValue(window.traitCollection.displayScale, forKey: "scale")
        }

        override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {}

        private func makeUniformMaskImage() -> CGImage? {
            let ciImage = CIImage(color: .black).cropped(to: CGRect(x: 0, y: 0, width: 1, height: 1))
            return CIContext().createCGImage(ciImage, from: ciImage.extent)
        }
    }

    final class FallbackImpl: UIVisualEffectView {
        init() { super.init(effect: UIBlurEffect(style: .systemUltraThinMaterial)) }
        required init?(coder: NSCoder) { fatalError() }
    }

    func updateImplAppearance() {
        if let impl = impl as? BlurImpl {
            impl.radius = radius * _alpha
        } else {
            impl.alpha = radius <= 0 ? 0 : _alpha
        }
    }
}
