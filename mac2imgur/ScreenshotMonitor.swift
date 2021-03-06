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

class ScreenshotMonitor {
    
    let callback: (screenshotPath: String) -> ()
    var query: NSMetadataQuery
    var blacklist: [String]
    
    init(callback: (screenshotPath: String) -> ()) {
        self.callback = callback
        self.blacklist = []
        
        query = NSMetadataQuery()
        
        // Only accept screenshots
        query.predicate = NSPredicate(format: "kMDItemIsScreenCapture = 1")
        
        // Limit scope to local mounted volumes
        query.searchScopes = [NSMetadataQueryLocalComputerScope]
    }
    
    func startMonitoring() {
        NSNotificationCenter.defaultCenter().addObserverForName(NSMetadataQueryDidFinishGatheringNotification, object: query, queue: NSOperationQueue.mainQueue(), usingBlock: initialPhaseComplete)
        NSNotificationCenter.defaultCenter().addObserverForName(NSMetadataQueryDidUpdateNotification, object: query, queue: NSOperationQueue.mainQueue(), usingBlock: liveUpdatePhaseEvent)
        query.startQuery()
    }
    
    func stopMonitoring() {
        NSNotificationCenter.defaultCenter().removeObserver(self, name: NSMetadataQueryDidFinishGatheringNotification, object: query)
        NSNotificationCenter.defaultCenter().removeObserver(self, name: NSMetadataQueryDidUpdateNotification, object: query)
        query.stopQuery()
    }
    
    func initialPhaseComplete(notification: NSNotification!) {
        // Blacklist all screenshots that already exist
        if let itemsAdded = notification.object?.results as? [NSMetadataItem] {
            for item in itemsAdded {
                // Get the path to the screenshot
                if let screenshotPath = item.valueForAttribute(NSMetadataItemPathKey) as? String {
                    let screenshotName = screenshotPath.lastPathComponent.stringByDeletingPathExtension
                    
                    // Blacklist the screenshot if it hasn't already been blacklisted
                    if !contains(blacklist, screenshotName) {
                        blacklist.append(screenshotName)
                    }
                }
            }
        }
    }
    
    func liveUpdatePhaseEvent(notification: NSNotification!) {
        if let itemsAdded = notification.userInfo?["kMDQueryUpdateAddedItems"] as? [NSMetadataItem] {
            for item in itemsAdded {
                // Get the path to the screenshot
                if let screenshotPath = item.valueForAttribute(NSMetadataItemPathKey) as? String {
                    let screenshotName = screenshotPath.lastPathComponent.stringByDeletingPathExtension
                    
                    // Ensure that the screenshot detected is from the right folder and isn't blacklisted
                    if screenshotPath.stringByDeletingLastPathComponent.stringByStandardizingPath == screenshotLocationPath.stringByStandardizingPath && !contains(blacklist, screenshotName) {
                        callback(screenshotPath: screenshotPath)
                        blacklist.append(screenshotName)
                    }
                }
            }
        }
    }
    
    var screenshotLocationPath: String {
        // Check for custom screenshot location chosen by user
        if let customLocation = NSUserDefaults.standardUserDefaults().persistentDomainForName("com.apple.screencapture")?["location"] as? String {
            // Check that the chosen directory exists, otherwise screencapture will not use it
            var isDir = ObjCBool(false)
            if NSFileManager.defaultManager().fileExistsAtPath(customLocation, isDirectory: &isDir) && isDir {
                return customLocation
            }
        }
        // If a custom location is not defined (or invalid) return the default screenshot location (~/Desktop)
        return NSSearchPathForDirectoriesInDomains(.DesktopDirectory, .UserDomainMask, true)[0] as! String
    }
}