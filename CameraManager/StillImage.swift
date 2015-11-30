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

    func _getStillImageOutput(captureSession: AVCaptureSession?) -> AVCaptureStillImageOutput {
        if (stillImageOutput == nil) {
            stillImageOutput = AVCaptureStillImageOutput()
        }

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
}
