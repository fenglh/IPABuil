//
//  ProvisioningProfile.swift
//
//
//  Created by Chris Mash on 05/11/2020.
//  Modified by fenglh on 2022/11/11.
//

import Foundation
import PathKit

/// Representation of a provisioning profile
public struct ProvisioningProfile {
    /// Custom `DateFormatter` for generating `formattedExpiryDate`, defaults to `nil`.
    /// If required, ensure you set this property before accessing `profile()`.
    public static var dateFormatter: DateFormatter?

    
//    public let name: String?
//    /// The expiry date of the provisioning profile as a `Date`, if successfully parsed.
//    public let expiryDate: Date?
//    /// The expiry date of the provisioning profile as a formatted `String`, if successfully parsed.
//    /// The default formatting is `short` for both date and time. Provide your own `DateFormatter`
//    /// to `dateForamtter` to override this.
//    public let formattedExpiryDate: String?
    
    
    var appIDName: String?
    var creationDate: Date?
    var platform: [String]?
    var isXcodeManaged: Bool?
    var developerCertificates: [Data]?
    var DEREncodedProfile: Data?
    var entitlements:Entitlements?
    var expirationDate: Date?
    var name: String?
    var provisionedDevices: [String]?
    var teamIdentifier: String?
    var teamName: String?
    var timeToLive: Int?
    var UUID: String?
    var version: Int?
    
    
    
 
//    internal init(name: String?, expiryDate: Date?) {
//        self.name = name
//        self.expiryDate = expiryDate
//        
//        if let expiry = expiryDate {
//            // Format the date into a presentable form
//            formattedExpiryDate = ProvisioningProfile.format(date: expiry)
//        }
//        else {
//            formattedExpiryDate = nil
//        }
//    }

    
    static func loadProfile(_ path: Path) -> ProvisioningProfile? {
        guard path.exists else { return nil }
        do {
            let data = try Data(contentsOf: path.url)
            guard let content = String(data: data, encoding: .ascii) else {
                return nil
            }

            return ProvisioningProfileParser.parse(string: content)
        }
        catch {
            return nil
        }
    }
    
    private static func format(date: Date) -> String {
        if let formatter = ProvisioningProfile.dateFormatter {
            // externally supplied formatter
            return formatter.string(from: date)
        }
        else {
            // default formatter
            let formatter = DateFormatter()
            formatter.dateStyle = .short
            formatter.timeStyle = .short
            formatter.timeZone = .current
            formatter.locale = .current
            return formatter.string(from: date)
        }
    }
    
}
