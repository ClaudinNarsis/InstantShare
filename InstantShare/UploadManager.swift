//
//  UploadManager.swift
//  InstantShareIntent
//
//  Created by Claudin Narsis on 05/12/24.
//

import Foundation
import Photos
import UniformTypeIdentifiers
import os.log
import UserNotifications

class UploadManager:NSObject, URLSessionDelegate, URLSessionTaskDelegate {
    let APP_GROUP_ID = "group.com.smoose.InstantShareIntent"
    static let shared = UploadManager()
    private var backgroundSession: URLSession!
    override init() {
            super.init()
            os_log("MANUAL LOG: Initializing UploadManager")
            let config = URLSessionConfiguration.background(withIdentifier: "com.smoose.InstantShareIntent.upload")
            config.isDiscretionary = false
            config.sessionSendsLaunchEvents = true
            config.shouldUseExtendedBackgroundIdleMode = true
            config.sharedContainerIdentifier = APP_GROUP_ID
            backgroundSession = URLSession(configuration: config, delegate: self, delegateQueue: nil)
            os_log("MANUAL LOG: Background session configured")
        }
        

        
        private func fetchImageData(for asset: PHAsset, options: PHImageRequestOptions) async throws -> (data: Data, uti: String?) {
            try await withCheckedThrowingContinuation { continuation in
                PHImageManager.default().requestImageDataAndOrientation(for: asset, options: options) { data, uti, _, _ in
                    if let data = data {
                        continuation.resume(returning: (data, uti))
                    } else {
                        continuation.resume(throwing: NSError(domain: "FetchImageDataError", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to fetch image data"]))
                    }
                }
            }
        }
    
    
    func getCurrentUserUid() -> String? {
        // Get shared UserDefaults
        if let sharedDefaults = UserDefaults(suiteName: APP_GROUP_ID) {
            return sharedDefaults.string(forKey: "currentUserUid")
        }
        return nil
    }
    
    func isUserAuthenticated() -> Bool {
        return getCurrentUserUid() != nil
    }
    
    func uploadAssetDirectly(_ asset: PHAsset) async throws -> String {
        let endpoint="https://us-central1-bringer-cam-dev.cloudfunctions.net/uploadImage"
//        let endpoint = "https://eo32kqfieb8ahl9.m.pipedream.net"
        let options = PHImageRequestOptions()
        options.isNetworkAccessAllowed = true
        options.deliveryMode = .highQualityFormat
        options.isSynchronous = true
        os_log("MANUAL LOG: options set")
        let imageData = try await fetchImageData(for: asset, options: options)
        
        // Create URL request
        guard let url = URL(string: endpoint) else {
            throw URLError(.badURL)
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 18// Increase the timeout interval to 18 seconds
        
        // Create multipart form data
        let boundary = UUID().uuidString
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        let userId = getCurrentUserUid() ?? ""
        let timestamp = asset.creationDate?.timeIntervalSince1970 ?? Date().timeIntervalSince1970
        let assetResources = PHAssetResource.assetResources(for: asset)
        let originalFilename = assetResources.first?.originalFilename ?? ""
        let fileExtension = (originalFilename as NSString).pathExtension.lowercased()

        var body = Data()

        // Add timestamp field
        body.append("--\(boundary)\r\n")
        body.append("Content-Disposition: form-data; name=\"timestamp\"\r\n\r\n")
        body.append("\(timestamp)\r\n")

        // Add userId field
        body.append("--\(boundary)\r\n")
        body.append("Content-Disposition: form-data; name=\"userId\"\r\n\r\n")
        body.append(userId + "\r\n")

        // Add imageType field
        body.append("--\(boundary)\r\n")
        body.append("Content-Disposition: form-data; name=\"imageType\"\r\n\r\n")
        body.append(fileExtension + "\r\n")

        // Add image file
        body.append("--\(boundary)\r\n")
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"image.\(fileExtension)\"\r\n")
        body.append("Content-Type: image/\(fileExtension)\r\n\r\n")
        body.append(imageData.data)
        body.append("\r\n--\(boundary)--\r\n")
        request.httpBody = body
        os_log("MANUAL LOG: performing request")
        // Perform upload
        
        let (data, response) = try await URLSession.shared.data(for: request)
        os_log("MANUAL LOG: got response")
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            os_log("MANUAL LOG: bad response %{public}@", data as CVarArg)
            URLSession.shared.finishTasksAndInvalidate()
            throw URLError(.badServerResponse)
        }
        os_log("MANUAL LOG: got data %{public}@", data as CVarArg)
        
        // Clean up any temporary data or resources
        URLSession.shared.finishTasksAndInvalidate()
        
        return String(data: data, encoding: .utf8) ?? ""
    }
}

extension Data {
    mutating func append(_ string: String) {
        if let data = string.data(using: .utf8) {
            append(data)
        }
    }
}
