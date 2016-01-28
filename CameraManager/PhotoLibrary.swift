//
//  PhotoLibrary.swift
//  camera
//
//  Created by Tom Clark on 2015-11-25.
//  Copyright © 2015 FluidDynamics. All rights reserved.
//

import Photos

typealias CompletionHandler = (Bool,NSError?) -> Void

class PhotoLibrary {
    func saveImage(image: UIImage?, toAlbum albumName: String, withCompletionHandler handler: (AnyObject, NSError?) -> Void) {
      guard let img = image
        else { return }

      PHPhotoLibrary.requestAuthorization { status in
        switch status {
        case .Authorized:
          self.saveItem(img, toAlbum: albumName, withCompletionHandler: handler)
          break
        case .Denied:
          print("denied")
          break
        case .Restricted:
          print("restricted")
          break
        case .NotDetermined:
          print("not determined")
          break
        }
      }
    }

    func saveVideo(videoURL: NSURL?, toAlbum albumName: String, withCompletionHandler handler: (AnyObject, NSError?) -> Void) {
        guard let url = videoURL
            else { return }
        saveItem(url, toAlbum: albumName) { (asset, error) -> Void in
            PHImageManager.defaultManager().requestAVAssetForVideo(asset as! PHAsset, options: nil, resultHandler: { (videoAsset, mix, info) -> Void in
                handler(videoAsset!, nil)
            })
        }
    }

    private func saveItem(object: AnyObject, toAlbum albumName: String, withCompletionHandler handler: (AnyObject, NSError?) -> Void) {
        if let assetCollection = getAssetCollectionByName(albumName) {
            self.addAsset(object, toCollection: assetCollection, withCompletionHandler: handler)
        } else {
            createAlbum(albumName, completion: { (fetchResult, error) -> Void in
                if let fetchResult = fetchResult {
                    self.addAsset(object, toCollection: fetchResult.firstObject as! PHAssetCollection, withCompletionHandler: handler)
                }
            })
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

    private func createAlbum(albumName: String, completion: (PHFetchResult?, NSError?) -> Void) {
        var collectionPlaceHolder: PHObjectPlaceholder?
        PHPhotoLibrary.sharedPhotoLibrary().performChanges({ () -> Void in
            let newAssetCollection = PHAssetCollectionChangeRequest.creationRequestForAssetCollectionWithTitle(albumName)
            collectionPlaceHolder = newAssetCollection.placeholderForCreatedAssetCollection
        }) { success, error in
            let assetCollection = PHAssetCollection.fetchAssetCollectionsWithLocalIdentifiers([collectionPlaceHolder!.localIdentifier], options: nil)
            completion(assetCollection, error)
        }
    }

    private func assetType(asset: AnyObject) -> PHAssetChangeRequest? {
        if let image = asset as? UIImage {
            return PHAssetChangeRequest.creationRequestForAssetFromImage(image)
        } else if let videoURL = asset as? NSURL {
            return PHAssetChangeRequest.creationRequestForAssetFromVideoAtFileURL(videoURL)
        }
        return nil
    }

    private func addAsset(asset: AnyObject, toCollection collection: PHAssetCollection, withCompletionHandler handler: (PHAsset, NSError?) -> Void) {
        var assetRequest: PHObjectPlaceholder!
        PHPhotoLibrary.sharedPhotoLibrary().performChanges({ () -> Void in
            assetRequest = self.assetType(asset)!.placeholderForCreatedAsset
            let assetCollectionRequest = PHAssetCollectionChangeRequest(forAssetCollection: collection)
            assetCollectionRequest!.addAssets([assetRequest])
        }) { success, error -> Void in
            if success {
                let fetchResult = PHAsset.fetchAssetsWithLocalIdentifiers([assetRequest.localIdentifier], options: nil)
                handler(fetchResult.firstObject as! PHAsset, nil)
            }
        }
    }
}
