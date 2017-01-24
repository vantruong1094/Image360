//
//  Image360Controller.swift
//  Image360
//
//  Copyright © 2017 Andrew Simvolokov. All rights reserved.
//
//  Permission is hereby granted, free of charge, to any person obtaining a copy
//  of this software and associated documentation files (the "Software"), to deal
//  in the Software without restriction, including without limitation the rights
//  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
//  copies of the Software, and to permit persons to whom the Software is
//  furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in
//  all copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
//  THE SOFTWARE.

import UIKit
import GLKit

private let blackFileURL = Bundle(for: Image360Controller.self).url(forResource: "black", withExtension: "jpg")!

public class Image360Controller: GLKViewController {

    private var imageView: Image360View

    // MARK: Inertia
    let inertiaInterval: TimeInterval = 0.020
    /// Amount of movement parameter for inertia (weak)
    let weakIntertiaRatio: Float = 1.0
    /// Amount of movement parameter for inertia (strong)
    let strongIntertiaRatio: Float = 10.0

    private var inertiaRatio: Float?

    public var inertia: Inertia = .short {
        willSet {
            inertiaTimer?.invalidate()
            inertiaTimer = nil
            inertiaTimerCount = 0
        }
    }

    fileprivate var inertiaTimerCount: UInt = 0
    fileprivate var inertiaTimer: Timer?

    public var image: UIImage? {
        get {
            return imageView.image
        }
        set {
            imageView.image = newValue
        }
    }

    public required init?(coder aDecoder: NSCoder) {
        imageView = Image360View(frame: CGRect(x: 0, y: 0, width: 512, height: 512))
        super.init(coder: aDecoder)
        registerGestureRecognizers()
        imageView.touchesHandler = self

        setBlackBackground()
    }

    public override func loadView() {
        self.view = imageView
    }

    public override func glkView(_ view: GLKView, drawIn rect: CGRect) {
        imageView.draw()
    }

    // MARK: Appear/Disappear
    private var isAppear = false

    public override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        if let presentedImage = imageView.image {
            imageView.image = presentedImage
        }
    }

    public override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        isAppear = true
    }

    public override func viewDidDisappear(_ animated: Bool) {
        imageView.unloadTextures()

        super.viewDidDisappear(animated)
        isAppear = false
    }

    // MARK: Helpers
    private func setBlackBackground() {
        let data = (try? Data(contentsOf: blackFileURL))!
        let image = UIImage(data: data)!
        imageView.image = image
    }

    // MARK: Gestures
    private var panGestureRecognizer: UIPanGestureRecognizer!
    private var pinchGestureRecognizer: UIPinchGestureRecognizer!

    fileprivate var isPanning = false
    private var panPrev: CGPoint?
    private var panLastDiffX: CGFloat?
    private var panLastDiffY: CGFloat?

    /// Gesture registration method
    private func registerGestureRecognizers() {
        panGestureRecognizer = UIPanGestureRecognizer(target: self, action: #selector(panGestureHandler(recognizer:)))
        panGestureRecognizer.maximumNumberOfTouches = 1
        panGestureRecognizer.delegate = self
        imageView.addGestureRecognizer(panGestureRecognizer)

        pinchGestureRecognizer = UIPinchGestureRecognizer(target: self, action: #selector(pinchGestureHandler(recognizer:)))
        pinchGestureRecognizer.delegate = self
        imageView.addGestureRecognizer(pinchGestureRecognizer)
    }


    /// Pinch operation compatibility handler
    /// - parameter recognizer: Recognizer object for gesture operations
    func pinchGestureHandler(recognizer: UIPinchGestureRecognizer) {
        switch recognizer.state {
        case .began:
            prevScale = 1.0
        default:
            ()
        }
        scale(ratio: recognizer.scale)
    }

    /// Pan operation compatibility handler
    /// - parameter recognizer: Recognizer object for gesture operations
    func panGestureHandler(recognizer: UIPanGestureRecognizer) {
        let cur = recognizer.translation(in: imageView)

        switch recognizer.state {
        case .ended:
            inertiaTimer?.invalidate()
            inertiaTimerCount = 0

            if inertia != .none {
                inertiaTimer = Timer.scheduledTimer(timeInterval: inertiaInterval,
                                                    target: self,
                                                    selector: #selector(inertiaTimerHandler(timer:)),
                                                    userInfo: nil,
                                                    repeats: true)
            }
        default:
            if isPanning {
                panLastDiffX = cur.x - panPrev!.x
                panLastDiffY = cur.y - panPrev!.y

                panPrev = cur
                rotate(diffx: -Float(panLastDiffX!), diffy: Float(panLastDiffY!))
            } else {
                isPanning = true
                panPrev = cur
            }
        }
    }

    /// Timer setting method
    /// - parameter timer: Setting target timer
    func inertiaTimerHandler(timer: Timer) {
        var diffX: Float = 0
        var diffY: Float = 0

        if inertiaTimerCount == 0 {
            inertiaRatio = 1.0
            switch inertia {
            case .short:
                inertiaRatio = weakIntertiaRatio
            case .long:
                inertiaRatio = strongIntertiaRatio
            case .none:
                ()
            }
        } else if inertiaTimerCount > 150 {
            inertiaTimer?.invalidate()
            inertiaTimer = nil
            inertiaTimerCount = 0
        } else {
            diffX = Float(panLastDiffX!) * (1.0 / Float(inertiaTimerCount)) * inertiaRatio!
            diffY = Float(panLastDiffY!) * (1.0 / Float(inertiaTimerCount)) * inertiaRatio!

            rotate(diffx: -diffX, diffy: diffY)
        }

        inertiaTimerCount += 1
    }

    // MARK: Scaling & rotation
    private var prevScale: CGFloat = 1.0
    /// Parameter for maximum width control
    private let scaleRatioTickExpansion: Float = 1.05
    /// Parameter for minimum width control
    private let scaleRatioTickReduction: Float = 0.95

    /// Zoom in/Zoom out method
    /// - parameter ratio: Zoom in/zoom out ratio
    private func scale(ratio: CGFloat) {
        if ratio < prevScale {
            imageView.setCameraFovDegree(newValue: imageView.cameraFovDegree * scaleRatioTickExpansion)
        } else {
            imageView.setCameraFovDegree(newValue: imageView.cameraFovDegree * scaleRatioTickReduction)
        }
        prevScale = ratio
    }

    /// Parameter for amount of rotation control (X axis)
    private let divideRotateX: Float = 500.0
    /// Parameter for amount of rotation control (Y axis)
    private let divideRotateY: Float = 500.0

    /// Rotation method
    /// - parameter diffx: Rotation amount (y axis)
    /// - parameter diffy: Rotation amount (xy plane)
    func rotate(diffx: Float, diffy: Float) {
        let xz = diffx / divideRotateX
        let y = diffy / divideRotateY

        imageView.setRotationAngleXZ(newValue: imageView.rotationAngleXZ + xz)
        imageView.setRotationAngleY(newValue: imageView.rotationAngleY + y)
    }
}

// MARK: - UIGestureRecognizerDelegate
extension Image360Controller: UIGestureRecognizerDelegate {
    // UIGestureRecognizerDelegate.gestureRecognizer(_:shouldRecognizeSimultaneouslyWith:) handler.
    public func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        return false
    }
}

// MARK: - Image360ViewTouchesHandler
extension Image360Controller: Image360ViewTouchesHandler {
    func image360View(_ view: Image360View, touchesBegan touches: Set<UITouch>, with event: UIEvent?) {
        inertiaTimer?.invalidate()
        inertiaTimer = nil
        inertiaTimerCount = 0

        isPanning = false
    }

    func image360View(_ view: Image360View, touchesMoved touches: Set<UITouch>, with event: UIEvent?) {
    }

    func image360View(_ view: Image360View, touchesEnded touches: Set<UITouch>, with event: UIEvent?) {
    }
}
