//
//  YPImagePicker.swift
//  YPImgePicker
//
//  Created by Sacha Durand Saint Omer on 27/10/16.
//  Copyright © 2016 Yummypets. All rights reserved.
//

import UIKit
import AVFoundation
import Photos
import Mantis

public protocol YPImagePickerDelegate: AnyObject {
    func noPhotos()
    func shouldAddToSelection(indexPath: IndexPath, numSelections: Int) -> Bool
}

open class YPImagePicker: UINavigationController {
      
    open override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        return .portrait
    }
    
    private var _didFinishPicking: (([YPMediaItem], Bool) -> Void)?
    public func didFinishPicking(completion: @escaping (_ items: [YPMediaItem], _ cancelled: Bool) -> Void) {
        _didFinishPicking = completion
    }
    public weak var imagePickerDelegate: YPImagePickerDelegate?
    
    open override var preferredStatusBarStyle: UIStatusBarStyle {
        return YPImagePickerConfiguration.shared.preferredStatusBarStyle
    }
    
    open override var childForStatusBarHidden: UIViewController? {
        if let topController = children.last as? YPPickerVC {
            return topController.controllers[topController.currentPage]
        } else if children.last is CropViewController {
            return children.first
        } else {
            return children.last
        }
    }
    
    // This nifty little trick enables us to call the single version of the callbacks.
    // This keeps the backwards compatibility keeps the api as simple as possible.
    // Multiple selection becomes available as an opt-in.
    private func didSelect(items: [YPMediaItem]) {
        _didFinishPicking?(items, false)
    }
    
    let loadingView = YPLoadingView()
    private let picker: YPPickerVC!
    var currentlyModifiedPhoto: YPMediaPhoto?
    
    /// Get a YPImagePicker instance with the default configuration.
    public convenience init() {
        self.init(configuration: YPImagePickerConfiguration.shared)
    }
    
    /// Get a YPImagePicker with the specified configuration.
    public required init(configuration: YPImagePickerConfiguration) {
        YPImagePickerConfiguration.shared = configuration
        picker = YPPickerVC()
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .overCurrentContext
        picker.imagePickerDelegate = self
        navigationBar.tintColor = configuration.colors.tintColor
        navigationBar.barTintColor = configuration.colors.barTintColor
        navigationBar.titleTextAttributes = [.foregroundColor: YPConfig.colors.tintColor]
        navigationBar.barStyle = YPConfig.preferredStatusBarStyle == .lightContent ? .black : .default
    }
    
    public required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
override open func viewDidLoad() {
        super.viewDidLoad()
        picker.didClose = { [weak self] in
            self?._didFinishPicking?([], true)
        }
        viewControllers = [picker]
        setupLoadingView()
        navigationBar.isTranslucent = false
        setNeedsStatusBarAppearanceUpdate()

        picker.didSelectItems = { [weak self] items in
            guard let self = self else { return }
            // Use Fade transition instead of default push animation
            let transition = CATransition()
            transition.duration = 0.3
            transition.timingFunction = CAMediaTimingFunction(name: CAMediaTimingFunctionName.easeInEaseOut)
            transition.type = CATransitionType.fade
            self.view.layer.add(transition, forKey: nil)
            
            // Multiple items flow
            if items.count > 1 {
                if YPConfig.library.skipSelectionsGallery {
                    self.didSelect(items: items)
                    return
                } else {
                    let selectionsGalleryVC = YPSelectionsGalleryVC(items: items) { _, items in
                        self.didSelect(items: items)
                    }
                    self.pushViewController(selectionsGalleryVC, animated: true)
                    return
                }
            }
            
            // One item flow
            let item = items.first!
            switch item {
            case .photo(let photo):
                self.currentlyModifiedPhoto = photo
                func showCropVC(photo: YPMediaPhoto) {
                    if case let YPCropType.rectangle(ratios) = YPConfig.showsCrop {
                        let cropVC = self.cropViewController(for: photo.image, with: ratios)
                        self.pushViewController(cropVC, animated: true)
                    } else {
                        self.save(photo: photo)
                    }
                }
                
                if YPConfig.showsPhotoFilters {
                    var isLastStep = false
                    if case YPCropType.none = YPConfig.showsCrop {
                        isLastStep = true
                    }
                    let filterVC = YPPhotoFiltersVC(inputPhoto: photo,
                                                    isFromSelectionVC: false,
                                                    isLastStep: isLastStep)
                    // Show filters and then crop
                    filterVC.didSave = { outputMedia in
                        if case let YPMediaItem.photo(outputPhoto) = outputMedia {
                            showCropVC(photo: outputPhoto)
                        }
                    }
                    self.pushViewController(filterVC, animated: false)
                } else {
                    showCropVC(photo: photo)
                }
            case .video(let video):
                if YPConfig.showsVideoTrimmer {
                    let videoFiltersVC = YPVideoFiltersVC.initWith(video: video,
                                                                   isFromSelectionVC: false,
                                                                   isLastStep: true)
                    videoFiltersVC.didSave = { [weak self] outputMedia in
                        self?.didSelect(items: [outputMedia])
                    }
                    self.pushViewController(videoFiltersVC, animated: true)
                } else {
                    self.didSelect(items: [YPMediaItem.video(v: video)])
                }
            }
        }
    }
    
    deinit {
        print("Picker deinited 👍")
    }
    
    private func setupLoadingView() {
        view.sv(
            loadingView
        )
        loadingView.fillContainer()
        loadingView.alpha = 0
    }
    
    private func cropViewController(for image: UIImage, with ratios: [MantisRatio]) -> CropViewController {
        var config = Mantis.Config()
        config.ratioOptions = [.custom]
        config.cropToolbarConfig.fixRatiosShowType = .vetical
        config.cropToolbarConfig.ratioCandidatesShowType = .alwaysShowRatioList
        ratios.forEach { (ratio) in
            config.addCustomRatio(byVerticalWidth: ratio.width, andVerticalHeight: ratio.height)
        }
        if ratios.first(where: {$0.height == 1 && $0.width == 1}) != nil {
            config.presetFixedRatioType = .canUseMultiplePresetFixedRatio(defaultRatio: 1)
        } else {
            let ratio = ratios.first
            let width = Double(ratio?.width ?? 1)
            let height = Double(ratio?.height ?? 1)
            config.presetFixedRatioType = .canUseMultiplePresetFixedRatio(defaultRatio: width / height)
        }
        if YPConfig.enableCropRotation {
            config.cropToolbarConfig.toolbarButtonOptions = [.clockwiseRotate, .counterclockwiseRotate]
        } else {
            config.cropToolbarConfig.toolbarButtonOptions = []
            config.showRotationDial = false
        }
        config.cropToolbarConfig.optionButtonFontSize = 16
        config.cropToolbarConfig.cropToolbarHeightForVertialOrientation = 56
        let cropViewController = Mantis.cropViewController(image: image, config: config)
        cropViewController.delegate = self
        cropViewController.title = YPConfig.wordings.crop
        return cropViewController
    }
    
    private func save(photo: YPMediaPhoto) {
        let mediaItem = YPMediaItem.photo(p: photo)
        // Save new image or existing but modified, to the photo album.
        if YPConfig.shouldSaveNewPicturesToAlbum {
            let isModified = photo.modifiedImage != nil
            if photo.fromCamera || (!photo.fromCamera && isModified) {
                YPPhotoSaver.trySaveImage(photo.image, inAlbumNamed: YPConfig.albumName)
            }
        }
        didSelect(items: [mediaItem])
    }
}

extension YPImagePicker: ImagePickerDelegate {
    
    func noPhotos() {
        self.imagePickerDelegate?.noPhotos()
    }
    
    func shouldAddToSelection(indexPath: IndexPath, numSelections: Int) -> Bool {
        return self.imagePickerDelegate?.shouldAddToSelection(indexPath: indexPath, numSelections: numSelections)
			?? true
    }
}

extension YPImagePicker: CropViewControllerDelegate {
    public func cropViewControllerDidCrop(_ cropViewController: CropViewController,
                                          cropped: UIImage, transformation: Transformation) {
        guard let modifiedPhoto = currentlyModifiedPhoto else { return }
        modifiedPhoto.modifiedImage = cropped
        save(photo: modifiedPhoto)
    }
    
    public func cropViewControllerDidCancel(_ cropViewController: CropViewController,
                                            original: UIImage) {
        self.popViewController(animated: false)
    }
}
