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
        imageOutput.captureStillImageAsynchronouslyFromConnection(imageOutput.connectionWithMediaType(AVMediaTypeVideo)) { (sample: CMSampleBuffer!, error: NSError!) -> Void in
            guard error == nil
                else {
                    imageCompletion(nil, error)
                    return
                }
            let imageData = AVCaptureStillImageOutput.jpegStillImageNSDataRepresentation(sample)
            imageCompletion(UIImage(data: imageData), error)
        }
    }
}
