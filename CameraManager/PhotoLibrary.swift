//
//  PhotoLibrary.swift
//  camera
//
//  Created by Tom Clark on 2015-11-25.
//  Copyright © 2015 FluidDynamics. All rights reserved.
//

import Photos

class PhotoLibrary {
    func saveImage(image: UIImage, toAlbum albumName: String, withCompletionHandler handler: (Bool,NSError?) -> Void) {
        let assetCollection = getAssetCollectionByName(albumName)

        if let assetCollection = assetCollection {
            self.addAsset(image, toCollection: assetCollection, withCompletionHandler: handler)
        } else {
            var placeholderCollection: PHObjectPlaceholder!
            PHPhotoLibrary.sharedPhotoLibrary().performChanges({ () -> Void in
                placeholderCollection = self.createAlbum(albumName)
                }, completionHandler: { (success: Bool, error: NSError?) -> Void in
                    if success {
                        let assetCollection = PHAssetCollection.fetchAssetCollectionsWithLocalIdentifiers([placeholderCollection.localIdentifier], options: nil)
                        self.addAsset(image, toCollection: assetCollection.firstObject as! PHAssetCollection, withCompletionHandler: handler)
                    }
            })
        }
    }
    func saveVideo() {
        PHPhotoLibrary.sharedPhotoLibrary().performChanges({ () -> Void in

        }) { success, error in

        }
    }
    private func getAssetCollectionByName(albumName: String) -> PHAssetCollection? {
        let assetCollection: PHFetchResult = PHAssetCollection.fetchAssetCollectionsWithType(.Album, subtype: .AlbumRegular, options: nil)
        var outCollection: PHAssetCollection?
        assetCollection.enumerateObjectsUsingBlock {
            (collection: AnyObject!, idx: Int, stop: UnsafeMutablePointer<ObjCBool>) -> Void in
            let assetCollection: PHAssetCollection = collection as! PHAssetCollection
            if collection.localizedTitle == albumName {
                outCollection = assetCollection
                stop.memory = true
            }
        }
        return outCollection
    }

    private func createAlbum(albumName: String) -> PHObjectPlaceholder {
        let newAssetCollection = PHAssetCollectionChangeRequest.creationRequestForAssetCollectionWithTitle(albumName)
        return newAssetCollection.placeholderForCreatedAssetCollection
    }

    private func addVideo(videoURL: NSURL) {
        PHAssetChangeRequest.creationRequestForAssetFromVideoAtFileURL(videoURL)
    }

    private func addAsset(image: UIImage, toCollection collection: PHAssetCollection, withCompletionHandler handler: (Bool,NSError?) -> Void) {
        PHPhotoLibrary.sharedPhotoLibrary().performChanges({ () -> Void in
            let assetRequest = PHAssetChangeRequest.creationRequestForAssetFromImage(image)
            let assetCollectionRequest = PHAssetCollectionChangeRequest(forAssetCollection: collection)
            assetCollectionRequest!.addAssets([assetRequest.placeholderForCreatedAsset!])
        }, completionHandler: handler)
    }
}
