//
//  CameraManager.swift
//  camera
//
//  Created by Natalia Terlecka on 10/10/14.
//  Copyright (c) 2014 imaginaryCloud. All rights reserved.
//

import UIKit
import AVFoundation

public enum CameraState {
    case Ready, AccessDenied, NoDeviceFound, NotDetermined
}

public enum CameraDevice {
    case Front, Back
}

public enum CameraFlashMode: Int {
    case Off, On, Auto
}

public enum CameraOutputMode {
    case StillImage, VideoWithMic, VideoOnly
}

public enum CameraOutputQuality: Int {
    case Low, Medium, High
}

/// Class for handling iDevices custom camera usage
public class CameraManager: NSObject {

    // MARK: - Public properties
    
    /// Capture session to customize camera settings.
    public var captureSession: AVCaptureSession?
    
    /// Property to determine if the manager should show the error for the user. If you want to show the errors yourself set this to false. If you want to add custom error UI set showErrorBlock property. Default value is false.
    public var showErrorsToUsers = false
    
    /// Property to determine if the manager should show the camera permission popup immediatly when it's needed or you want to show it manually. Default value is true. Be carful cause using the camera requires permission, if you set this value to false and don't ask manually you won't be able to use the camera.
    public var showAccessPermissionPopupAutomatically = true
    
    /// A closure creating UI to present error message to the user. This can be customised to be presented on the Window root view controller, or to pass in the viewController which will present the UIAlertController, for example.
    public var showErrorBlock: ((erTitle: String, erMessage: String) -> Void)?

    /// Property to determine if manager should write the resources to the phone library. Default value is true.
    public var writeFilesToPhoneLibrary = true
    
    /// Property to determine if manager should follow device orientation. Default value is true.
    public var shouldRespondToOrientationChanges = true {
        didSet {
            if shouldRespondToOrientationChanges {
                _startFollowingDeviceOrientation()
            } else {
                _stopFollowingDeviceOrientation()
            }
        }
    }

    /// Property for album title
    public var albumTitle: String = "All Images"

    /// The Bool property to determine if current device has front camera.
    public var hasFrontCamera: Bool = {
        let devices = AVCaptureDevice.devicesWithMediaType(AVMediaTypeVideo)
        for  device in devices  {
            let captureDevice = device as! AVCaptureDevice
            if (captureDevice.position == .Front) {
                return true
            }
        }
        return false
    }()
    
    /// The Bool property to determine if current device has flash.
    public var hasFlash: Bool = {
        let devices = AVCaptureDevice.devicesWithMediaType(AVMediaTypeVideo)
        for  device in devices  {
            let captureDevice = device as! AVCaptureDevice
            if (captureDevice.position == .Back) {
                return captureDevice.hasFlash
            }
        }
        return false
    }()
    
    /// Property to change camera device between front and back.
    public var cameraDevice = CameraDevice.Back {
        didSet {
            if cameraDevice != oldValue {
                _updateCameraDevice(cameraDevice)
            }
        }
    }

    /// Property to change camera flash mode.
    public var flashMode = CameraFlashMode.Off {
        didSet {
            if flashMode != oldValue {
                _updateFlasMode(flashMode)
            }
        }
    }

    /// Property to change camera output quality.
    public var cameraOutputQuality = CameraOutputQuality.High {
        didSet {
            if cameraOutputQuality != oldValue {
                _updateCameraQualityMode(cameraOutputQuality)
            }
        }
    }

    /// Property to change camera output.
    public var cameraOutputMode = CameraOutputMode.StillImage {
        didSet {
            if cameraOutputMode != oldValue {
                _setupOutputMode(cameraOutputMode, oldCameraOutputMode: oldValue)
            }
        }
    }
    
    /// Property to check video recording duration when in progress
    public var recordedDuration : CMTime { return videoHandler?.recordedDuration ?? kCMTimeZero }
    
    /// Property to check video recording file size when in progress
    public var recordedFileSize : Int64 { return videoHandler?.recordedFileSize ?? 0 }

    
    // MARK: - Private properties

    private weak var embeddingView: UIView?
    private var videoCompletion: ((videoURL: NSURL?, error: NSError?) -> Void)?
    private var withZoom = false

    private var sessionQueue = dispatch_queue_create("CameraSessionQueue", DISPATCH_QUEUE_SERIAL)

    private lazy var frontCameraDevice: AVCaptureDevice? = {
        let devices = AVCaptureDevice.devicesWithMediaType(AVMediaTypeVideo) as! [AVCaptureDevice]
        return devices.filter{$0.position == .Front}.first
    }()
    
    private lazy var backCameraDevice: AVCaptureDevice? = {
        let devices = AVCaptureDevice.devicesWithMediaType(AVMediaTypeVideo) as! [AVCaptureDevice]
        return devices.filter{$0.position == .Back}.first
    }()
    
    private lazy var mic: AVCaptureDevice? = {
        return AVCaptureDevice.defaultDeviceWithMediaType(AVMediaTypeAudio)
    }()

    private var previewLayer: AVCaptureVideoPreviewLayer?
    private let library = PhotoLibrary()
    private var videoHandler: VideoHandler?
    private var stillImageHandler: StillImage?
    private var zoomScale = CGFloat(1.0)

    private var cameraIsSetup = false
    private var cameraIsObservingDeviceOrientation = false

    private var tempFilePath: NSURL = {
        let tempPath = NSURL(fileURLWithPath: NSTemporaryDirectory()).URLByAppendingPathComponent("tempMovie").URLByAppendingPathExtension("mp4").absoluteString
        if NSFileManager.defaultManager().fileExistsAtPath(tempPath) {
            do {
                try NSFileManager.defaultManager().removeItemAtPath(tempPath)
            } catch { }
        }
        return NSURL(string: tempPath)!
    }()

    private var canLoadCamera: Bool {
        let currentCameraState = _checkIfCameraIsAvailable()
        return currentCameraState == .Ready || (currentCameraState == .NotDetermined && showAccessPermissionPopupAutomatically)
    }

    // MARK: - CameraManager

    /**
    Inits a capture session and adds a preview layer to the given view. Preview layer bounds will automaticaly be set to match given view. Default session is initialized with still image output.

    :param: view The view you want to add the preview layer to
    :param: cameraOutputMode The mode you want capturesession to run image / video / video and microphone
    
    :returns: Current state of the camera: Ready / AccessDenied / NoDeviceFound / NotDetermined.
    */
    public init (cameraOutputMode: CameraOutputMode) {
        self.cameraOutputMode = cameraOutputMode
    }
    public func addPreviewLayerToView(view: UIView, withZoom zoom: Bool = false) -> CameraState {
        withZoom = zoom
        return addPreviewLayerToView(view, newCameraOutputMode: cameraOutputMode)
    }
    private func addPreviewLayerToView(view: UIView, newCameraOutputMode: CameraOutputMode) -> CameraState {
        if canLoadCamera {
            if let _ = embeddingView {
                if let validPreviewLayer = previewLayer {
                    validPreviewLayer.removeFromSuperlayer()
                }
            }
            if cameraIsSetup {
                _addPreviewLayerToView(view)
                cameraOutputMode = newCameraOutputMode
            } else {
                _setupCamera({ Void -> Void in
                    self._addPreviewLayerToView(view)
                    self.cameraOutputMode = newCameraOutputMode
                })
            }
        }
        return _checkIfCameraIsAvailable()
    }

    /**
    Asks the user for camera permissions. Only works if the permissions are not yet determined. Note that it'll also automaticaly ask about the microphone permissions if you selected VideoWithMic output.
    
    :param: completion Completion block with the result of permission request
    */
    public func askUserForCameraPermissions(completion: Bool -> Void) {
        AVCaptureDevice.requestAccessForMediaType(AVMediaTypeVideo, completionHandler: { (alowedAccess) -> Void in
            if self.cameraOutputMode == .VideoWithMic {
                AVCaptureDevice.requestAccessForMediaType(AVMediaTypeAudio, completionHandler: { (alowedAccess) -> Void in
                    dispatch_sync(dispatch_get_main_queue(), { () -> Void in
                        completion(alowedAccess)
                    })
                })
            } else {
                dispatch_sync(dispatch_get_main_queue(), { () -> Void in
                    completion(alowedAccess)
                })

            }
        })

    }

    /**
    Stops running capture session but all setup devices, inputs and outputs stay for further reuse.
    */
    public func stopCaptureSession() {
        captureSession?.stopRunning()
        _stopFollowingDeviceOrientation()
    }

    /**
    Resumes capture session.
    */
    public func resumeCaptureSession() {
        if let validCaptureSession = captureSession {
            if !validCaptureSession.running && cameraIsSetup {
                validCaptureSession.startRunning()
                _startFollowingDeviceOrientation()
            }
        } else {
            if canLoadCamera {
                if cameraIsSetup {
                    stopAndRemoveCaptureSession()
                }
                _setupCamera({Void -> Void in
                    if let validEmbeddingView = self.embeddingView {
                        self._addPreviewLayerToView(validEmbeddingView)
                    }
                    self._startFollowingDeviceOrientation()
                })
            }
        }
    }

    /**
    Stops running capture session and removes all setup devices, inputs and outputs.
    */
    public func stopAndRemoveCaptureSession() {
        stopCaptureSession()
        cameraDevice = .Back
        cameraIsSetup = false
        previewLayer = nil
        captureSession = nil
        frontCameraDevice = nil
        backCameraDevice = nil
        mic = nil
        stillImageHandler = nil
        videoHandler = nil
    }

    /**
    Captures still image from currently running capture session.

    :param: imageCompletion Completion block containing the captured UIImage
    */
    public func capturePictureWithCompletion(imageCompletion: (UIImage?, NSError?) -> Void) {
        guard cameraIsSetup
            else {
                _show(NSLocalizedString("No capture session setup", comment:""), message: NSLocalizedString("I can't take any picture", comment:""))
                return
            }
        guard cameraOutputMode == .StillImage
            else {
                _show(NSLocalizedString("Capture session output mode video", comment:""), message: NSLocalizedString("I can't take any picture", comment:""))
                return
            }

        dispatch_async(sessionQueue, {
            self.stillImageHandler?.captureImageFromCaptureSession(self.captureSession!, imageCompletion: { [weak self] (image, error) -> Void in
                guard let error = error
                    else {
                        dispatch_async(dispatch_get_main_queue(), {
                            imageCompletion(image, nil)
                        })
                        return
                    }
                dispatch_async(dispatch_get_main_queue(), {
                    if let weakSelf = self {
                        weakSelf._show(NSLocalizedString("Error", comment:""), message: error.localizedDescription)
                    }
                })
            })
        })
    }

    /**
    Starts recording a video with or without voice as in the session preset.
    */
    public func startRecordingVideo() {
        if cameraOutputMode != .StillImage {
            captureSession?.beginConfiguration()
            if flashMode != .Off {
                _updateTorch(flashMode)
            }
            captureSession?.commitConfiguration()
            videoHandler!.getMovieOutput(captureSession).startRecordingToOutputFileURL(tempFilePath, recordingDelegate: videoHandler!)
        } else {
            _show(NSLocalizedString("Capture session output still image", comment:""), message: NSLocalizedString("I can only take pictures", comment:""))
        }
    }

    /**
    Stop recording a video. Save it to the cameraRoll and give back the url.
    */
    public func stopRecordingVideo(completion:(videoURL: NSURL?, error: NSError?) -> Void) {
        _updateTorch(.Off)
        if let runningMovieOutput = videoHandler?.getMovieOutput(captureSession) {
            if runningMovieOutput.recording {
                videoHandler?.completionHandler = completion
                videoCompletion = completion
                runningMovieOutput.stopRecording()
            }
        }
    }

    /**
    Current camera status.
    
    :returns: Current state of the camera: Ready / AccessDenied / NoDeviceFound / NotDetermined
    */
    public func currentCameraStatus() -> CameraState {
        return _checkIfCameraIsAvailable()
    }
    
    /**
    Change current flash mode to next value from available ones.
    
    :returns: Current flash mode: Off / On / Auto
    */
    public func changeFlashMode() -> CameraFlashMode {
        flashMode = CameraFlashMode(rawValue: (flashMode.rawValue+1)%3)!
        return flashMode
    }
    
    /**
    Change current output quality mode to next value from available ones.
    
    :returns: Current quality mode: Low / Medium / High
    */
    public func changeQualityMode() -> CameraOutputQuality {
        cameraOutputQuality = CameraOutputQuality(rawValue: (cameraOutputQuality.rawValue+1)%3)!
        return cameraOutputQuality
    }

    // MARK: - CameraManager()

    private func _updateTorch(flashMode: CameraFlashMode) {
        captureSession?.beginConfiguration()
        let devices = AVCaptureDevice.devicesWithMediaType(AVMediaTypeVideo)
        for device in devices  {
            let captureDevice = device as! AVCaptureDevice
            if (captureDevice.position == AVCaptureDevicePosition.Back) {
                let avTorchMode = AVCaptureTorchMode(rawValue: flashMode.rawValue)
                if (captureDevice.isTorchModeSupported(avTorchMode!)) {
                    do {
                        try captureDevice.lockForConfiguration()
                    } catch {
                        return
                    }
                    captureDevice.torchMode = avTorchMode!
                    captureDevice.unlockForConfiguration()
                }
            }
        }
        captureSession?.commitConfiguration()
    }
    
    private func _executeVideoCompletionWithURL(url: NSURL?, error: NSError?) {
        if let validCompletion = videoCompletion {
            validCompletion(videoURL: url, error: error)
            videoCompletion = nil
        }
    }

    private func attachZoom(view: UIView) {
        let pinch = UIPinchGestureRecognizer(target: self, action: "_zoom:")
        view.addGestureRecognizer(pinch)
    }

    @objc private func _zoom(recognizer: UIPinchGestureRecognizer) {
        guard let view = embeddingView,
          previewLayer = previewLayer
          else { return }

        var allTouchesOnPreviewLayer = true
        let numTouch = recognizer.numberOfTouches()
      
        for var i = 0; i < numTouch; i++ {
            let location = recognizer.locationOfTouch(i, inView: view)
            let convertedTouch = previewLayer.convertPoint(location, fromLayer: previewLayer.superlayer)
            if !previewLayer.containsPoint(convertedTouch) {
              allTouchesOnPreviewLayer = false
              break
            }
        }
        if allTouchesOnPreviewLayer {
            do {
                let captureDevice = AVCaptureDevice.devices().first as? AVCaptureDevice
                try captureDevice?.lockForConfiguration()
                if recognizer.scale >= 1.0 {
                  captureDevice?.videoZoomFactor = recognizer.scale
                  zoomScale = recognizer.scale
                }
              captureDevice?.unlockForConfiguration()
            } catch {
                print("Error locking configuration")
            }
        }
    }
    
    @objc private func _orientationChanged() {
        var currentConnection: AVCaptureConnection?;
        switch cameraOutputMode {
        case .StillImage:
            currentConnection = stillImageHandler?.getStillImageOutput(captureSession).connectionWithMediaType(AVMediaTypeVideo)
        case .VideoOnly, .VideoWithMic:
            currentConnection = videoHandler!.getMovieOutput(captureSession).connectionWithMediaType(AVMediaTypeVideo)
        }
        if let validPreviewLayer = previewLayer {
            if let validPreviewLayerConnection = validPreviewLayer.connection {
                if validPreviewLayerConnection.supportsVideoOrientation {
                    validPreviewLayerConnection.videoOrientation = _currentVideoOrientation()
                }
            }
            if let validOutputLayerConnection = currentConnection {
                if validOutputLayerConnection.supportsVideoOrientation {
                    validOutputLayerConnection.videoOrientation = _currentVideoOrientation()
                }
            }
            dispatch_async(dispatch_get_main_queue(), { () -> Void in
                if let validEmbedingView = self.embeddingView {
                    validPreviewLayer.frame = validEmbedingView.bounds
                }
            })
        }
    }

    private func _currentVideoOrientation() -> AVCaptureVideoOrientation {
        switch UIDevice.currentDevice().orientation {
        case .LandscapeLeft:
            return .LandscapeRight
        case .LandscapeRight:
            return .LandscapeLeft
        default:
            return .Portrait
        }
    }

    private func _setupCamera(completion: Void -> Void) {
        captureSession = AVCaptureSession()
        
        dispatch_async(sessionQueue, {
            if let validCaptureSession = self.captureSession {
                validCaptureSession.beginConfiguration()
                validCaptureSession.sessionPreset = AVCaptureSessionPresetHigh
                self._updateCameraDevice(self.cameraDevice)
                self._setupOutputMode(self.cameraOutputMode, oldCameraOutputMode: nil)
                self._setupPreviewLayer()
                validCaptureSession.commitConfiguration()
                self._updateFlasMode(self.flashMode)
                self._updateCameraQualityMode(self.cameraOutputQuality)
                validCaptureSession.startRunning()
                self._startFollowingDeviceOrientation()
                self.cameraIsSetup = true
                self._orientationChanged()
                
                completion()
            }
        })
    }

    private func _startFollowingDeviceOrientation() {
        if shouldRespondToOrientationChanges && !cameraIsObservingDeviceOrientation {
            NSNotificationCenter.defaultCenter().addObserver(self, selector: "_orientationChanged", name: UIDeviceOrientationDidChangeNotification, object: nil)
            cameraIsObservingDeviceOrientation = true
        }
    }

    private func _stopFollowingDeviceOrientation() {
        if cameraIsObservingDeviceOrientation {
            NSNotificationCenter.defaultCenter().removeObserver(self, name: UIDeviceOrientationDidChangeNotification, object: nil)
            cameraIsObservingDeviceOrientation = false
        }
    }

    private func _addPreviewLayerToView(view: UIView) {
        embeddingView = view
        if withZoom {
            attachZoom(view)
        }
        dispatch_async(dispatch_get_main_queue(), { () -> Void in
            guard let pl = self.previewLayer else {
                return
            }
            pl.frame = view.layer.bounds
            view.clipsToBounds = true
            view.layer.insertSublayer(pl, atIndex: 0)
        })
    }

    private func _checkIfCameraIsAvailable() -> CameraState {
        let deviceHasCamera = UIImagePickerController.isCameraDeviceAvailable(UIImagePickerControllerCameraDevice.Rear) || UIImagePickerController.isCameraDeviceAvailable(UIImagePickerControllerCameraDevice.Front)
        if deviceHasCamera {
            let authorizationStatus = AVCaptureDevice.authorizationStatusForMediaType(AVMediaTypeVideo)
            let userAgreedToUseIt = authorizationStatus == .Authorized
            if userAgreedToUseIt {
                return .Ready
            } else if authorizationStatus == AVAuthorizationStatus.NotDetermined {
                return .NotDetermined
            } else {
                _show(NSLocalizedString("Camera access denied", comment:""), message:NSLocalizedString("You need to go to settings app and grant acces to the camera device to use it.", comment:""))
                return .AccessDenied
            }
        } else {
            _show(NSLocalizedString("Camera unavailable", comment:""), message:NSLocalizedString("The device does not have a camera.", comment:""))
            return .NoDeviceFound
        }
    }
    
    private func _setupOutputMode(newCameraOutputMode: CameraOutputMode, oldCameraOutputMode: CameraOutputMode?) {
        captureSession?.beginConfiguration()
        
        if let cameraOutputToRemove = oldCameraOutputMode {
            // remove current setting
            switch cameraOutputToRemove {
            case .StillImage:
                if let validStillImageOutput = stillImageHandler {
                    captureSession?.removeOutput(validStillImageOutput.getStillImageOutput(captureSession!))
                }
            case .VideoOnly, .VideoWithMic:
                if let validMovieOutput = videoHandler?.getMovieOutput(captureSession!) {
                    captureSession?.removeOutput(validMovieOutput)
                }
                if cameraOutputToRemove == .VideoWithMic {
                    _removeMicInput()
                }
            }
        }
        
        // configure new devices
        switch newCameraOutputMode {
        case .StillImage:
            if (stillImageHandler == nil) {
                stillImageHandler = StillImage(library: library, albumTitle: albumTitle)
            }
            if let validStillImageOutput = stillImageHandler {
                validStillImageOutput.getStillImageOutput(captureSession!)
            }
        case .VideoOnly, .VideoWithMic:
            if videoHandler == nil {
                videoHandler = VideoHandler(library: library, albumTitle: albumTitle)
            }
            videoHandler?.getMovieOutput(captureSession)
            
            if newCameraOutputMode == .VideoWithMic {
                if let validMic = _deviceInputFromDevice(mic) {
                    captureSession?.addInput(validMic)
                }
            }
        }
        captureSession?.commitConfiguration()
        _updateCameraQualityMode(cameraOutputQuality)
        _orientationChanged()
    }

    private func _setupPreviewLayer() {
        if let validCaptureSession = captureSession {
            previewLayer = AVCaptureVideoPreviewLayer(session: validCaptureSession)
            previewLayer?.videoGravity = AVLayerVideoGravityResizeAspectFill
        }
    }
    
    private func _updateCameraDevice(deviceType: CameraDevice) {
        if let validCaptureSession = captureSession {
            validCaptureSession.beginConfiguration()
            let inputs = validCaptureSession.inputs as! [AVCaptureInput]
            
            for input in inputs {
                if let deviceInput = input as? AVCaptureDeviceInput {
                    if deviceInput.device == backCameraDevice && cameraDevice == .Front {
                        validCaptureSession.removeInput(deviceInput)
                        break;
                    } else if deviceInput.device == frontCameraDevice && cameraDevice == .Back {
                        validCaptureSession.removeInput(deviceInput)
                        break;
                    }
                }
            }
            switch cameraDevice {
            case .Front:
                if hasFrontCamera {
                    if let validFrontDevice = _deviceInputFromDevice(frontCameraDevice) {
                        if !inputs.contains(validFrontDevice) {
                            validCaptureSession.addInput(validFrontDevice)
                        }
                    }
                }
            case .Back:
                if let validBackDevice = _deviceInputFromDevice(backCameraDevice) {
                    if !inputs.contains(validBackDevice) {
                        validCaptureSession.addInput(validBackDevice)
                    }
                }
            }
            validCaptureSession.commitConfiguration()
        }
    }
    
    private func _updateFlasMode(flashMode: CameraFlashMode) {
        captureSession?.beginConfiguration()
        let devices = AVCaptureDevice.devicesWithMediaType(AVMediaTypeVideo)
        for  device in devices  {
            let captureDevice = device as! AVCaptureDevice
            if (captureDevice.position == AVCaptureDevicePosition.Back) {
                let avFlashMode = AVCaptureFlashMode(rawValue: flashMode.rawValue)
                if (captureDevice.isFlashModeSupported(avFlashMode!)) {
                    do {
                        try captureDevice.lockForConfiguration()
                    } catch {
                        return
                    }
                    captureDevice.flashMode = avFlashMode!
                    captureDevice.unlockForConfiguration()
                }
            }
        }
        captureSession?.commitConfiguration()
    }
    
    private func _updateCameraQualityMode(newCameraOutputQuality: CameraOutputQuality) {
        if let validCaptureSession = captureSession {
            var sessionPreset = AVCaptureSessionPresetLow
            switch (newCameraOutputQuality) {
            case .Low:
                sessionPreset = AVCaptureSessionPresetLow
            case .Medium:
                sessionPreset = AVCaptureSessionPresetMedium
            case .High:
                if cameraOutputMode == .StillImage {
                    sessionPreset = AVCaptureSessionPresetPhoto
                } else {
                    sessionPreset = AVCaptureSessionPresetHigh
                }
            }
            if validCaptureSession.canSetSessionPreset(sessionPreset) {
                validCaptureSession.beginConfiguration()
                validCaptureSession.sessionPreset = sessionPreset
                validCaptureSession.commitConfiguration()
            } else {
                _show(NSLocalizedString("Preset not supported", comment:""), message: NSLocalizedString("Camera preset not supported. Please try another one.", comment:""))
            }
        } else {
            _show(NSLocalizedString("Camera error", comment:""), message: NSLocalizedString("No valid capture session found, I can't take any pictures or videos.", comment:""))
        }
    }

    private func _removeMicInput() {
        guard let inputs = captureSession?.inputs as? [AVCaptureInput]
            else { return }
        
        for input in inputs {
            if let deviceInput = input as? AVCaptureDeviceInput {
                if deviceInput.device == mic {
                    captureSession?.removeInput(deviceInput)
                    break;
                }
            }
        }
    }
    
    private func _show(title: String, message: String) {
        if let errorBlock = showErrorBlock where showErrorsToUsers {
            dispatch_async(dispatch_get_main_queue(), { () -> Void in
                errorBlock(erTitle: title, erMessage: message)
            })
        }
    }
    
    private func _deviceInputFromDevice(device: AVCaptureDevice?) -> AVCaptureDeviceInput? {
        guard let validDevice = device else { return nil }
        do {
            return try AVCaptureDeviceInput(device: validDevice)
        } catch let outError {
            _show(NSLocalizedString("Device setup error occured", comment:""), message: "\(outError)")
            return nil
        }
    }

    deinit {
        stopAndRemoveCaptureSession()
        _stopFollowingDeviceOrientation()
    }
}
