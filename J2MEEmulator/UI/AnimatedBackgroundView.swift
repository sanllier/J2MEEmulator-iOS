//
//  AnimatedBackgroundView.swift
//  J2MEEmulator
//
//  Animated colored blobs covered by a blur — creates a soft lava-lamp background.
//

import UIKit

final class AnimatedBackgroundView: UIView {

    private let circlesContainer = UIView()
    private let blurView = NeutralBlurView(radius: 40)
    private var circleViews: [UIView] = []
    private var animating = false

    private static let colors: [UIColor] = [
        UIColor(red: 0.15, green: 0.22, blue: 0.55, alpha: 0.38),  // Blue
        UIColor(red: 0.42, green: 0.12, blue: 0.33, alpha: 0.33),  // Magenta
        UIColor(red: 0.06, green: 0.33, blue: 0.36, alpha: 0.33),  // Teal
        UIColor(red: 0.33, green: 0.15, blue: 0.45, alpha: 0.33),  // Purple
        UIColor(red: 0.10, green: 0.30, blue: 0.22, alpha: 0.28),  // Green
        UIColor(red: 0.48, green: 0.22, blue: 0.15, alpha: 0.28),  // Orange
    ]

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func setup() {
        backgroundColor = .black
        clipsToBounds = true

        circlesContainer.clipsToBounds = true
        addSubview(circlesContainer)

        for color in Self.colors {
            let circle = UIView()
            circle.backgroundColor = color
            circlesContainer.addSubview(circle)
            circleViews.append(circle)
        }

        blurView.backgroundColor = UIColor(white: 0, alpha: 0.3)
        addSubview(blurView)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        circlesContainer.frame = bounds
        blurView.frame = bounds

        if !animating {
            // Initial random positions
            for circle in circleViews {
                let size = randomSize()
                circle.frame = CGRect(
                    x: CGFloat.random(in: -size/2 ... bounds.width - size/2),
                    y: CGFloat.random(in: -size/2 ... bounds.height - size/2),
                    width: size, height: size)
                circle.layer.cornerRadius = size / 2
            }
            animating = true
            startAnimations()
        }
    }

    private func startAnimations() {
        for (i, circle) in circleViews.enumerated() {
            let delay = Double(i) * 1.5
            animateCircle(circle, delay: delay)
        }
    }

    private func animateCircle(_ circle: UIView, delay: TimeInterval) {
        let duration = Double.random(in: 10...16)
        let newSize = randomSize()

        UIView.animate(
            withDuration: duration,
            delay: delay,
            options: [.curveEaseInOut, .allowUserInteraction],
            animations: { [weak self] in
                guard let self else { return }
                let x = CGFloat.random(in: -newSize/2 ... self.bounds.width - newSize/2)
                let y = CGFloat.random(in: -newSize/2 ... self.bounds.height - newSize/2)
                circle.frame = CGRect(x: x, y: y, width: newSize, height: newSize)
                circle.layer.cornerRadius = newSize / 2
            },
            completion: { [weak self] _ in
                self?.animateCircle(circle, delay: 0)
            }
        )
    }

    private func randomSize() -> CGFloat {
        let base = min(bounds.width, bounds.height)
        return CGFloat.random(in: base * 0.3 ... base * 0.7)
    }
}
