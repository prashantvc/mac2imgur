/* This file is part of mac2imgur.
*
* mac2imgur is free software: you can redistribute it and/or modify
* it under the terms of the GNU General Public License as published by
* the Free Software Foundation, either version 3 of the License, or
* (at your option) any later version.

* mac2imgur is distributed in the hope that it will be useful,
* but WITHOUT ANY WARRANTY; without even the implied warranty of
* MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
* GNU General Public License for more details.

* You should have received a copy of the GNU General Public License
* along with mac2imgur.  If not, see <http://www.gnu.org/licenses/>.
*/

import Foundation

public class ImgurClient {
    
    /// All file types accepted by the Imgur API
    public let allowedFileTypes = ["jpg", "jpeg", "gif", "png", "apng", "tiff", "bmp", "pdf", "xcf"]
    
    let kRefreshToken = "RefreshToken"
    let kUsername = "ImgurUsername"
    let boundary: String = "---------------------\(arc4random())\(arc4random())" // Random boundary
    let apiURL = "https://api.imgur.com/"
    
    let clientId: String
    let clientSecret: String
    
    var uploadQueue = [ImgurUpload]()
    var authenticationInProgress = false
    var tokenExpiryDate: NSDate?
    
    public init(clientId: String, clientSecret: String) {
        self.clientId = clientId
        self.clientSecret = clientSecret
    }
    
    /// The username of the currently authenticated user, if any
    public var username: String? {
        get {
            return NSUserDefaults.standardUserDefaults().stringForKey(kUsername)
        }
        set {
            NSUserDefaults.standardUserDefaults().setObject(newValue, forKey: kUsername)
        }
    }
    
    var refreshToken: String? {
        get {
            return NSUserDefaults.standardUserDefaults().stringForKey(kRefreshToken)
        }
        set {
            NSUserDefaults.standardUserDefaults().setObject(newValue, forKey: kRefreshToken)
        }
    }
    
    var accessToken: String? {
        didSet {
            // Update token expiry date (imgur access tokens are valid for 1 hour)
            tokenExpiryDate = NSDate(timeIntervalSinceNow: 1 * 60 * 60)
        }
    }
    
    public var isAuthenticated: Bool {
        return username != nil && refreshToken != nil
    }
    
    var accessTokenIsValid: Bool {
        if accessToken != nil {
            return tokenExpiryDate!.timeIntervalSinceReferenceDate > NSDate().timeIntervalSinceReferenceDate
        }
        return false
    }
    
    /**
    Authenticate with the Imgur API
    
    :param: code The authorization code obtained from the Imgur API
    
    :callback: The code to be executed upon a successful authentication attempt
    */
    public func authenticate(code: String, callback: () -> ()) {
        let parameters = [
            "client_id": clientId,
            "client_secret": clientSecret,
            "grant_type": "authorization_code",
            "code": code
        ]
        request(.POST, "\(apiURL)oauth2/token", parameters: parameters, encoding: .JSON)
            .validate()
            .validate(contentType: ["application/json"])
            .responseJSON { (request, response, JSON, error) -> () in
                if let refreshToken = JSON?["refresh_token"] as? String {
                    self.accessToken = JSON?["access_token"] as? String
                    self.username = JSON?["account_username"] as? String
                    self.refreshToken = refreshToken
                    callback()
                } else {
                    NSLog("An error occurred while attempting to obtain tokens from a pin: \(error)\nRequest: \(request)\nResponse: \(response)\nJSON: \(JSON)")
                }
        }
    }
    
    func requestAccessToken(callback: () -> ()) {
        let parameters = [
            "client_id": clientId,
            "client_secret": clientSecret,
            "grant_type": "refresh_token",
            "refresh_token": self.refreshToken!
        ]
        request(.POST, "\(apiURL)oauth2/token", parameters: parameters, encoding: .JSON)
            .validate()
            .validate(contentType: ["application/json"])
            .responseJSON { (request, response, JSON, error) -> () in
            if let access = JSON?["access_token"] as? String {
                self.accessToken = access
                callback()
            } else {
                NSLog("An error occurred while requesting a new access token: \(error)\nRequest: \(request)\nResponse: \(response)\nJSON: \(JSON)")
            }
        }
    }
    
    /// Delete Imgur authentication credentials from NSUserDefaults
    public func deleteCredentials() {
        NSUserDefaults.standardUserDefaults().removeObjectForKey(kUsername)
        NSUserDefaults.standardUserDefaults().removeObjectForKey(kRefreshToken)
    }
    
    public func addToQueue(upload: ImgurUpload) {
        uploadQueue.append(upload)
        
        // If necessary, request a new access token
        if isAuthenticated && !accessTokenIsValid {
            if !authenticationInProgress {
                authenticationInProgress = true
                requestAccessToken({ () -> () in
                    self.authenticationInProgress = false
                    self.processQueue()
                })
            }
        } else {
            processQueue()
        }
    }
    
    func processQueue() {
        // Upload all images in queue
        for upload in uploadQueue {
            attemptUpload(upload)
        }
        // Clear queue
        uploadQueue.removeAll(keepCapacity: false)
    }
    
    func attemptUpload(uploadRequest: ImgurUpload) {
        let request = NSMutableURLRequest()
        request.URL = NSURL(string: "\(apiURL)3/upload")
        request.HTTPMethod = Method.POST.rawValue
        
        let requestBody = NSMutableData()
        let contentType = "multipart/form-data; boundary=\(boundary)"
        request.addValue(contentType, forHTTPHeaderField: "Content-Type")
        
        // Add authorization
        request.addValue(isAuthenticated ? "Client-Bearer \(accessToken!)" : "Client-ID \(clientId)", forHTTPHeaderField: "Authorization")
        
        // Add image data
        requestBody.appendData("--\(boundary)\r\n".dataUsingEncoding(NSUTF8StringEncoding)!)
        requestBody.appendData("Content-Disposition: attachment; name=\"image\"; filename=\".\(uploadRequest.imagePath.pathExtension)\"\r\n".dataUsingEncoding(NSUTF8StringEncoding)!)
        requestBody.appendData("Content-Type: application/octet-stream\r\n\r\n".dataUsingEncoding(NSUTF8StringEncoding)!)
        requestBody.appendData(uploadRequest.imageData)
        requestBody.appendData("\r\n".dataUsingEncoding(NSUTF8StringEncoding)!)
        
        // Add title
        requestBody.appendData("--\(boundary)\r\n".dataUsingEncoding(NSUTF8StringEncoding)!)
        requestBody.appendData("Content-Disposition: form-data; name=\"title\"\r\n\r\n".dataUsingEncoding(NSUTF8StringEncoding)!)
        requestBody.appendData(uploadRequest.imagePath.lastPathComponent.stringByDeletingPathExtension.dataUsingEncoding(NSUTF8StringEncoding)!)
        requestBody.appendData("\r\n".dataUsingEncoding(NSUTF8StringEncoding)!)
        
        // Add description
        let description = uploadRequest.description.isEmpty ? "Uploaded by mac2imgur! (https://mileswd.com/mac2imgur)" : uploadRequest.description
        requestBody.appendData("--\(boundary)\r\n".dataUsingEncoding(NSUTF8StringEncoding)!)
        requestBody.appendData("Content-Disposition: form-data; name=\"description\"\r\n\r\n".dataUsingEncoding(NSUTF8StringEncoding)!)
        requestBody.appendData(description.dataUsingEncoding(NSUTF8StringEncoding)!)
        requestBody.appendData("\r\n".dataUsingEncoding(NSUTF8StringEncoding)!)
        
        requestBody.appendData("--\(boundary)--\r\n".dataUsingEncoding(NSUTF8StringEncoding)!)
        
        // Send request
        upload(request, requestBody)
            .validate()
            .validate(contentType: ["application/json"])
            .responseJSON { (request, response, JSON, error) -> Void in
                if var link = JSON?.objectForKey("data")?.objectForKey("link") as? String {
                    // Update link provided by API to HTTPS if necessary
                    if link.substringToIndex(advance(link.startIndex, 5)) == "http:" {
                        link = "https" + link.substringFromIndex(advance(link.startIndex, 4))
                    }
                    uploadRequest.link = link
                } else {
                    if let error = JSON?.objectForKey("data")?.objectForKey("error") as? String {
                        uploadRequest.error = "Imgur responded with the following error: \"\(error)\""
                    } else {
                        uploadRequest.error = error?.localizedDescription
                    }
                    NSLog("An error occurred while attempting to upload an image: \(error)\nRequest: \(request)\nResponse: \(response)\nJSON: \(JSON)")
                }
                uploadRequest.callback(upload: uploadRequest)
        }
    }
}