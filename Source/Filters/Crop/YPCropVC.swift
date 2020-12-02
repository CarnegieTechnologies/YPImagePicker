//
//  YPCropVC.swift
//  YPImagePicker
//
//  Created by Sacha DSO on 12/02/2018.
//  Copyright © 2018 Yummypets. All rights reserved.
//

import UIKit

public enum YPCropType {
    case none
    case rectangle(ratios: [Ratio])
}

public enum Ratio: String {
    case oneToOne = "1:1"
    case fourToThree = "4:3"
    case threeToFour = "3:4"
    case sixteenToNine = "16:9"

    var value: Double {
        switch self {
        case .oneToOne: return 1.0
        case .fourToThree: return 4.0 / 3.0
        case .threeToFour: return 3.0 / 4.0
        case .sixteenToNine: return 16.0 / 9.0
        }
    }
}

public class RatioButtonItem: UIBarButtonItem {

    var ratio: Ratio!

    init(ratio: Ratio, target: AnyObject, action: Selector) {
        super.init()
        self.title = ratio.rawValue
        self.target = target
        self.action = action
        self.tintColor = .ypLabel
        self.ratio = ratio
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }
}

class YPCropVC: UIViewController {

    public var didFinishCropping: ((UIImage) -> Void)?
    
    override var prefersStatusBarHidden: Bool { return YPConfig.hidesStatusBar }
    
    private let originalImage: UIImage
    private let pinchGR = UIPinchGestureRecognizer()
    private let panGR = UIPanGestureRecognizer()

    private var v: YPCropView
    private var ratios: [Ratio]

    private var currentRatio: Ratio {
        didSet {
            guard oldValue != currentRatio else { return }
            v = YPCropView(image: originalImage, ratio: currentRatio.value)
            view = v
            setupToolbar()
            setupGestureRecognizers()
        }
    }
    
    override func loadView() { view = v }
    
    required init(image: UIImage, ratios: [Ratio]) {
        self.originalImage = image
        self.ratios = ratios
        self.currentRatio = ratios.first ?? Ratio.oneToOne
        v = YPCropView(image: image, ratio: currentRatio.value)
        super.init(nibName: nil, bundle: nil)
        self.title = YPConfig.wordings.crop
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupToolbar()
        setupGestureRecognizers()
        setUpNavigationBar()
    }
    
    func setupToolbar() {
        let cancelButton = UIBarButtonItem(title: YPConfig.wordings.cancel,
                                           style: .plain,
                                           target: self,
                                           action: #selector(cancel))
        cancelButton.setFont(font: YPConfig.fonts.leftBarButtonFont, forState: .normal)
        cancelButton.tintColor = .ypLabel
        let flexibleSpace = UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil)
        var toolbarItems = [cancelButton, flexibleSpace]
        for ratio in ratios {
            let ratioItem = RatioButtonItem(ratio: ratio, target: self, action: #selector(setRatio(ratioButtonItem:)))
            toolbarItems.append(contentsOf: [ratioItem, flexibleSpace])
        }
        cancelButton.setFont(font: YPConfig.fonts.leftBarButtonFont, forState: .normal)
        
        let saveButton = UIBarButtonItem(title: YPConfig.wordings.save,
                                         style: .done,
                                         target: self,
                                         action: #selector(done))
        saveButton.setFont(font: YPConfig.fonts.rightBarButtonFont, forState: .normal)
        saveButton.tintColor = .ypLabel
        toolbarItems.append(saveButton)
        v.toolbar.items = toolbarItems
    }
    
    func setupGestureRecognizers() {
        // Pinch Gesture
        pinchGR.addTarget(self, action: #selector(pinch(_:)))
        pinchGR.delegate = self
        v.imageView.addGestureRecognizer(pinchGR)
        
        // Pan Gesture
        panGR.addTarget(self, action: #selector(pan(_:)))
        panGR.delegate = self
        v.imageView.addGestureRecognizer(panGR)
    }
    
    private func setUpNavigationBar() {
        let rotateButton = UIBarButtonItem(barButtonSystemItem: UIBarButtonItem.SystemItem.refresh,
                                           target: self, action: #selector(rotate))
        navigationItem.rightBarButtonItem = rotateButton
    }
    
    @objc
    func cancel() {
        navigationController?.popViewController(animated: true)
    }
    
    @objc
    func setRatio(ratioButtonItem: RatioButtonItem) {
        currentRatio = ratioButtonItem.ratio
    }

    @objc
    func done() {
        guard let image = v.imageView.image else {
            return
        }
        
        let xCrop = v.cropArea.frame.minX - v.imageView.frame.minX
        let yCrop = v.cropArea.frame.minY - v.imageView.frame.minY
        let widthCrop = v.cropArea.frame.width
        let heightCrop = v.cropArea.frame.height
        let scaleRatio = image.size.width / v.imageView.frame.width
        let scaledCropRect = CGRect(x: xCrop * scaleRatio,
                                    y: yCrop * scaleRatio,
                                    width: widthCrop * scaleRatio,
                                    height: heightCrop * scaleRatio)
        if let cgImage = image.toCIImage()?.toCGImage(),
            let imageRef = cgImage.cropping(to: scaledCropRect) {
            let croppedImage = UIImage(cgImage: imageRef)
            didFinishCropping?(croppedImage)
        }
    }
    
    @objc
    func rotate() {
        v.imageView.transform = v.imageView.transform.rotated(by: .pi / 2)
    }
    
}

extension YPCropVC: UIGestureRecognizerDelegate {
    
    // MARK: - Pinch Gesture
    
    @objc
    func pinch(_ sender: UIPinchGestureRecognizer) {
        // TODO: Zoom where the fingers are (more user friendly)
        switch sender.state {
        case .began, .changed:
            // Apply zoom level.
            v.imageView.transform = v.imageView.transform.scaledBy(x: sender.scale, y: sender.scale)
        case .ended:
            pinchGestureEnded()
        case .cancelled, .failed, .possible:
            ()
        @unknown default:
            fatalError()
        }
        // Reset the pinch scale.
        sender.scale = 1.0
    }
    
    private func pinchGestureEnded() {
        var transform = v.imageView.transform
        let kMinZoomLevel: CGFloat = 1.0
        let kMaxZoomLevel: CGFloat = 3.0
        var wentOutOfAllowedBounds = false
        
        // Prevent zooming out too much
        if transform.a.magnitude < kMinZoomLevel && transform.b.magnitude < kMinZoomLevel &&
            transform.c.magnitude < kMinZoomLevel && transform.d.magnitude < kMinZoomLevel {
            transform = .identity
            wentOutOfAllowedBounds = true
        }
        
        // Prevent zooming in too much
        if transform.a.magnitude > kMaxZoomLevel && transform.d.magnitude > kMaxZoomLevel {
            transform.a = transform.a > 0 ? kMaxZoomLevel : -kMaxZoomLevel
            transform.d = transform.d > 0 ? kMaxZoomLevel : -kMaxZoomLevel
            wentOutOfAllowedBounds = true
        } else if transform.b.magnitude > kMaxZoomLevel && transform.c.magnitude > kMaxZoomLevel {
            transform.b = transform.b > 0 ? kMaxZoomLevel : -kMaxZoomLevel
            transform.c = transform.c > 0 ? kMaxZoomLevel : -kMaxZoomLevel
            wentOutOfAllowedBounds = true
        }
        
        // Animate coming back to the allowed bounds with a haptic feedback.
        if wentOutOfAllowedBounds {
            generateHapticFeedback()
            UIView.animate(withDuration: 0.3, animations: {
                self.v.imageView.transform = transform
            })
        }
    }
    
    func generateHapticFeedback() {
        if #available(iOS 10.0, *) {
            let generator = UIImpactFeedbackGenerator(style: .light)
            generator.impactOccurred()
        }
    }
    
    // MARK: - Pan Gesture
    
    @objc
    func pan(_ sender: UIPanGestureRecognizer) {
        let translation = sender.translation(in: view)
        let imageView = v.imageView
        
        // Apply the pan translation to the image.
        imageView.center = CGPoint(x: imageView.center.x + translation.x, y: imageView.center.y + translation.y)
        
        // Reset the pan translation.
        sender.setTranslation(CGPoint.zero, in: view)
        
        if sender.state == .ended {
            keepImageIntoCropArea()
        }
    }
    
    private func keepImageIntoCropArea() {
        let imageRect = v.imageView.frame
        let cropRect = v.cropArea.frame
        var correctedFrame = imageRect
        
        // Cap Top.
        if imageRect.minY > cropRect.minY {
            correctedFrame.origin.y = cropRect.minY
        }
        
        // Cap Bottom.
        if imageRect.maxY < cropRect.maxY {
            correctedFrame.origin.y = cropRect.maxY - imageRect.height
        }
        
        // Cap Left.
        if imageRect.minX > cropRect.minX {
            correctedFrame.origin.x = cropRect.minX
        }
        
        // Cap Right.
        if imageRect.maxX < cropRect.maxX {
            correctedFrame.origin.x = cropRect.maxX - imageRect.width
        }
        
        // Animate back to allowed bounds
        if imageRect != correctedFrame {
            UIView.animate(withDuration: 0.3, animations: {
                self.v.imageView.frame = correctedFrame
            })
        }
    }
    
    /// Allow both Pinching and Panning at the same time.
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        return true
    }
}
