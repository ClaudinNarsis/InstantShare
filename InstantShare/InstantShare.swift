//
//  InstantShare.swift
//  InstantShare
//
//  Created by Claudin Narsis on 05/12/24.
//

import AppIntents
import OSLog
import Photos
import UIKit
struct InstantShare: AppIntent {
    
    private let APP_GROUP_ID = "group.com.smoose.InstantShareIntent"
    static var title: LocalizedStringResource = "InstantShare"
    static var description = IntentDescription("The photos in gallery app will be uploaded to Social Gallery")
    static var openAppWhenRun: Bool = false
    
        func perform() async throws -> some IntentResult & ReturnsValue<String> {
            let userDefaults = UserDefaults(suiteName: APP_GROUP_ID)
            let uploadedTillTimestamp = userDefaults?.string(forKey: "uploaded_till_timestamp")
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "d MMM yyyy 'at' h:mm:ss a"
            dateFormatter.locale = Locale(identifier: "en_US_POSIX")
            let dateToUse: Date
            if let timestamp = uploadedTillTimestamp, let date = dateFormatter.date(from: timestamp) {
                dateToUse = date
            } else {
                dateToUse = Date().addingTimeInterval(-5 * 60)
            }
            let formattedDateToUse = dateFormatter.string(from: dateToUse)
            
            
            let status = PHPhotoLibrary.authorizationStatus()
            if status != .authorized {
                let newStatus = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
                guard newStatus == .authorized else {
                    print("Photo library access not authorized")
                    os_log("MANUAL LOG Photo library access not authorized")
                    return .result(value: formattedDateToUse)
                }
            }

            
            let readdateFormatter = DateFormatter()
            readdateFormatter.dateFormat = "d MMM yyyy 'at' h:mm:ss a"
            readdateFormatter.locale = Locale(identifier: "en_US_POSIX")

            guard let formatedDate = readdateFormatter.date(from: formattedDateToUse) else {
                os_log("MANUAL LOG: readdateFormatter failed")
                return .result(value:formattedDateToUse)
            }
            
            
            let fetchOptions = PHFetchOptions()
            fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: true)]
            fetchOptions.predicate = NSPredicate(format: "creationDate > %@", formatedDate as NSDate)
            fetchOptions.fetchLimit = 3

            let fetchResult = PHAsset.fetchAssets(with: .image, options: fetchOptions)
            os_log("MANUAL LOG: UPLOADING %{public}d images", fetchResult.count)
            
            if (fetchResult.count != 0){
                let asset = fetchResult.object(at: 0)
                do {
                    try await UploadManager.shared.uploadAssetDirectly(asset)
                    os_log("MANUAL LOG: RETURNING TRUE")
                    let resultdateFormatter = DateFormatter()
                    resultdateFormatter.dateFormat = "d MMM yyyy 'at' h:mm:ss a"
                    let returnformattedDate = resultdateFormatter.string(from: (asset.creationDate ?? Date()).addingTimeInterval(1))
                    
                    if fetchResult.count > 1 {
                        updateUploadedTillTimestamp(with: returnformattedDate)
                        return .result(value: "Continue-\(returnformattedDate)")
                    }
                    
                    
                    updateUploadedTillTimestamp(with: returnformattedDate)
                    return .result(value: "Success-\(returnformattedDate)")
                } catch {
                    os_log("MANUAL LOG: RETURNING FALSE %{public}@", error as CVarArg)
                    showFailueNotification()
                    updateUploadedTillTimestamp(with: formattedDateToUse)
                    return .result(value: "Error-\(formattedDateToUse)")
                }
            }
            updateUploadedTillTimestamp(with: formattedDateToUse)
            return .result(value: "Error-\(formattedDateToUse)")
        }
    
        func updateUploadedTillTimestamp(with timestamp: String) {
            let userDefaults = UserDefaults(suiteName: APP_GROUP_ID)
            userDefaults?.set(timestamp, forKey: "uploaded_till_timestamp")
            os_log("MANUAL LOG: Updated uploaded_till_timestamp to %{public}@", timestamp)
        }
        
         
        
        func showFailueNotification(){
            let content = UNMutableNotificationContent()
            content.title = "Instant Share is slow :("
            content.body = "Open the App to share photos faster"
            
            let request = UNNotificationRequest(
                identifier: "InstnatShareFailure",
                content: content,
                trigger: nil
            )
            
            UNUserNotificationCenter.current().add(request)
        }
    
}
