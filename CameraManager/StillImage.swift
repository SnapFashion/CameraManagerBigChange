//
//  StillImage.swift
//  camera
//
//  Created by Tom Clark on 2015-11-29.
//  Copyright © 2015 FluidDynamics. All rights reserved.
//

import AVFoundation

class StillImage {
    private var stillImageOutput: AVCaptureStillImageOutput?
    private var albumTitle: String?
    private weak var library: PhotoLibrary?

    init(library: PhotoLibrary, albumTitle: String) {
        self.albumTitle = albumTitle
        self.library = library
    }

    func getStillImageOutput(captureSession: AVCaptureSession?) -> AVCaptureStillImageOutput {
        var shouldReinitializeStillImageOutput = stillImageOutput == nil
        if !shouldReinitializeStillImageOutput {
            if let connection = stillImageOutput!.connectionWithMediaType(AVMediaTypeVideo) {
                shouldReinitializeStillImageOutput = shouldReinitializeStillImageOutput || !connection.active
            }
        }
        if shouldReinitializeStillImageOutput {
            stillImageOutput = AVCaptureStillImageOutput()

            captureSession?.beginConfiguration()
            captureSession?.addOutput(stillImageOutput)
            captureSession?.commitConfiguration()
        }
        return stillImageOutput!
    }

    func captureImageFromCaptureSession(captureSession: AVCaptureSession, imageCompletion: (UIImage?, NSError?) -> Void) {
        let imageOutput = getStillImageOutput(captureSession)
        imageOutput.captureStillImageAsynchronouslyFromConnection(imageOutput.connectionWithMediaType(AVMediaTypeVideo)) { [weak self] (sample: CMSampleBuffer!, error: NSError!) -> Void in
            guard error == nil
                else {
                    imageCompletion(nil, error)
                    return
                }
            let imageData = AVCaptureStillImageOutput.jpegStillImageNSDataRepresentation(sample)
            guard let weakSelf = self,
                validLibrary = weakSelf.library,
                albumTitle = weakSelf.albumTitle
                else {
                    imageCompletion(UIImage(data: imageData), error)
                    return
                }

            validLibrary.saveImage(UIImage(data: imageData)!, toAlbum: albumTitle) { (complete, error) -> Void in
                imageCompletion(UIImage(data: imageData), error)
            }
        }
    }
}
