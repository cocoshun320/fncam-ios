import Foundation
import Photos
import UIKit
import AVFoundation

enum PhotoStore {
    static func ensureAuthorized(_ completion: @escaping (Bool) -> Void) {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        switch status {
        case .authorized, .limited:
            completion(true)
        case .notDetermined:
            PHPhotoLibrary.requestAuthorization(for: .readWrite) { s in
                DispatchQueue.main.async { completion(s == .authorized || s == .limited) }
            }
        default:
            completion(false)
        }
    }

    static func ensureAlbum(_ name: String, completion: @escaping (PHAssetCollection?) -> Void) {
        let fetch = PHAssetCollection.fetchAssetCollections(with: .album, subtype: .albumRegular, options: nil)
        var found: PHAssetCollection?
        fetch.enumerateObjects { col, _, stop in
            if col.localizedTitle == name {
                found = col
                stop.pointee = true
            }
        }
        if let f = found {
            completion(f)
            return
        }
        var placeholder: PHObjectPlaceholder?
        PHPhotoLibrary.shared().performChanges({
            let req = PHAssetCollectionChangeRequest.creationRequestForAssetCollection(withTitle: name)
            placeholder = req.placeholderForCreatedAssetCollection
        }) { ok, _ in
            if ok, let id = placeholder?.localIdentifier {
                let r = PHAssetCollection.fetchAssetCollections(withLocalIdentifiers: [id], options: nil)
                completion(r.firstObject)
            } else {
                completion(nil)
            }
        }
    }

    static func saveImage(data: Data, completion: @escaping (String?) -> Void) {
        ensureAuthorized { granted in
            guard granted, let image = UIImage(data: data) else { completion(nil); return }
            ensureAlbum(Settings.shared.album) { col in
                var placeholder: PHObjectPlaceholder?
                PHPhotoLibrary.shared().performChanges({
                    let req = PHAssetChangeRequest.creationRequestForAsset(from: image)
                    placeholder = req.placeholderForCreatedAsset
                    if let col = col, let ph = placeholder,
                       let albumReq = PHAssetCollectionChangeRequest(for: col) {
                        albumReq.addAssets([ph] as NSArray)
                    }
                }) { ok, _ in
                    DispatchQueue.main.async { completion(ok ? placeholder?.localIdentifier : nil) }
                }
            }
        }
    }

    static func saveVideo(url: URL, completion: @escaping (String?) -> Void) {
        ensureAuthorized { granted in
            guard granted else { completion(nil); return }
            ensureAlbum(Settings.shared.album) { col in
                var placeholder: PHObjectPlaceholder?
                PHPhotoLibrary.shared().performChanges({
                    let req = PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url)
                    placeholder = req?.placeholderForCreatedAsset
                    if let col = col, let ph = placeholder,
                       let albumReq = PHAssetCollectionChangeRequest(for: col) {
                        albumReq.addAssets([ph] as NSArray)
                    }
                }) { ok, _ in
                    DispatchQueue.main.async { completion(ok ? placeholder?.localIdentifier : nil) }
                }
            }
        }
    }

    static func asset(_ localIdentifier: String) -> PHAsset? {
        return PHAsset.fetchAssets(withLocalIdentifiers: [localIdentifier], options: nil).firstObject
    }

    /// 导出相册资源到临时文件，供 FTP 读取（在后台线程同步调用）
    static func exportAsset(_ localIdentifier: String, kind: String) -> URL? {
        guard let asset = asset(localIdentifier) else { return nil }
        let tmp = FileManager.default.temporaryDirectory
        let sem = DispatchSemaphore(value: 0)
        var result: URL?

        if kind == "video" {
            let opts = PHVideoRequestOptions()
            opts.version = .current
            opts.deliveryMode = .highQualityFormat
            opts.isNetworkAccessAllowed = true
            PHImageManager.default().requestAVAsset(forVideo: asset, options: opts) { av, _, _ in
                if let urlAsset = av as? AVURLAsset {
                    let dst = tmp.appendingPathComponent(UUID().uuidString + ".mp4")
                    do {
                        try FileManager.default.copyItem(at: urlAsset.url, to: dst)
                        result = dst
                    } catch {
                        result = nil
                    }
                }
                sem.signal()
            }
        } else {
            let opts = PHImageRequestOptions()
            opts.version = .current
            opts.deliveryMode = .highQualityFormat
            opts.isNetworkAccessAllowed = true
            opts.isSynchronous = false
            PHImageManager.default().requestImageDataAndOrientation(for: asset, options: opts) { data, _, _, _ in
                if let data = data {
                    let dst = tmp.appendingPathComponent(UUID().uuidString + ".jpg")
                    do {
                        try data.write(to: dst)
                        result = dst
                    } catch {
                        result = nil
                    }
                }
                sem.signal()
            }
        }
        _ = sem.wait(timeout: .now() + 120)
        return result
    }

    static func thumbnail(_ localIdentifier: String, size: CGSize, completion: @escaping (UIImage?) -> Void) {
        guard let asset = asset(localIdentifier) else { completion(nil); return }
        let opts = PHImageRequestOptions()
        opts.deliveryMode = .opportunistic
        opts.isNetworkAccessAllowed = true
        PHImageManager.default().requestImage(for: asset, targetSize: size,
                                              contentMode: .aspectFill, options: opts) { img, _ in
            DispatchQueue.main.async { completion(img) }
        }
    }

    /// 删除相册资源。注意：iOS 会弹系统确认框，这是苹果强制的。
    static func deleteAsset(_ localIdentifier: String) {
        guard let asset = asset(localIdentifier) else { return }
        PHPhotoLibrary.shared().performChanges({
            PHAssetChangeRequest.deleteAssets([asset] as NSArray)
        }) { _, _ in }
    }
}

import AVFoundation