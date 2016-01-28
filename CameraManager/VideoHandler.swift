//
//  Video.swift
//  camera
//
//  Created by Tom Clark on 2015-11-30.
//  Copyright © 2015 FluidDynamics. All rights reserved.
//

import AVFoundation

class VideoHandler: NSObject {
    /// Property to check video recording duration when in progress
    var recordedDuration : CMTime { return movieOutput?.recordedDuration ?? kCMTimeZero }

    /// Property to check video recording file size when in progress
    var recordedFileSize : Int64 { return movieOutput?.recordedFileSize ?? 0 }

    var completionHandler: ((videoURL: NSURL?, error: NSError?) -> Void)?

    private var albumTitle: String?
    private weak var library: PhotoLibrary?
    private var movieOutput: AVCaptureMovieFileOutput?

    init(library: PhotoLibrary, albumTitle: String?) {
        self.albumTitle = albumTitle
        self.library = library
    }

    func getMovieOutput(captureSession: AVCaptureSession?) -> AVCaptureMovieFileOutput {
        var shouldReinitializeMovieOutput = movieOutput == nil
        if !shouldReinitializeMovieOutput {
            if let connection = movieOutput!.connectionWithMediaType(AVMediaTypeVideo) {
                shouldReinitializeMovieOutput = shouldReinitializeMovieOutput || !connection.active
            }
        }

        if shouldReinitializeMovieOutput {
            movieOutput = AVCaptureMovieFileOutput()
            movieOutput!.movieFragmentInterval = kCMTimeInvalid

            captureSession?.beginConfiguration()
            captureSession?.addOutput(movieOutput)
            captureSession?.commitConfiguration()
        }
        return movieOutput!
    }
}

// MARK: - AVCaptureFileOutputRecordingDelegate
extension VideoHandler: AVCaptureFileOutputRecordingDelegate {
    func captureOutput(captureOutput: AVCaptureFileOutput!, didFinishRecordingToOutputFileAtURL outputFileURL: NSURL!, fromConnections connections: [AnyObject]!, error: NSError!) {
        guard error == nil
            else {
                self.completionHandler!(videoURL: nil, error: error)
//                _show(NSLocalizedString("Unable to save video to the iPhone", comment:""), message: error.localizedDescription)
                return
            }

        if let albumTitle = albumTitle {
            library!.saveVideo(outputFileURL, toAlbum: albumTitle, withCompletionHandler: { assetURL, error in

                if (error != nil) {
                    //self._show(NSLocalizedString("Unable to save video to the iPhone.", comment:""), message: error!.localizedDescription)
                    self.completionHandler!(videoURL: nil, error: error)
                } else {
                    if let validAssetURL = assetURL as? AVURLAsset {
                        self.completionHandler!(videoURL: validAssetURL.URL, error: error)
                    }
                }
            })
        } else {
            completionHandler!(videoURL: outputFileURL, error: error)
        }
    }
}
