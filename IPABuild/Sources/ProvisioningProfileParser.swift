//
//  ProvisioningProfileParser.swift
//  
//
//  Created by Chris Mash on 28/11/2020.
//

import Foundation

internal class ProvisioningProfileParser {
    
    private enum Error: Swift.Error {
        case notFound
        case parsingError
    }
    
    internal static func parse(string: String) -> ProvisioningProfile{

        var profile = ProvisioningProfile()
        
        do {
           
            let appIDName = try extract(key: "AppIDName",
                                type: "string",
                                from: string)
        }
        catch {
            print("解释失败")
        }
        return profile

    }
    
//    internal static func parse(string: String) -> ProvisioningProfile {
//        // Extract the name from the provided string representation of a provisioning profile
//        let name: String?
//        do {
//            name = try extract(key: "Name",
//                               type: "string",
//                               from: string)
//        }
//        catch {
//            name = nil
//        }
//
//        // Extract the expiry date from the provided string representation of a provisioning profile
//        let expiryDate: Date?
//        do {
//            let expiryString = try extract(key: "ExpirationDate",
//                                           type: "date",
//                                           from: string)
//            // Parse the date as per https://developer.apple.com/library/archive/qa/qa1480/_index.html
//            let formatter = DateFormatter()
//            formatter.locale = Locale(identifier: "en_US_POSIX")
//            formatter.dateFormat = "yyyy'-'MM'-'dd'T'HH':'mm':'ss'Z'"
//            formatter.timeZone = TimeZone(abbreviation: "UTC")
//            let date = formatter.date(from: expiryString)
//
//            if date != nil {
//                expiryDate = date
//            }
//            else {
//                throw Error.parsingError
//            }
//        }
//        catch {
//            expiryDate = nil
//        }
//
//        return ProvisioningProfile(name: name,
//                                   expiryDate: expiryDate)
//    }
    

    
}


extension String {
    func extract(key: String, type: String) -> Any? {
        let scanner = Scanner(string: self)
        // Find the line with, e.g. <key>ExpirationDate</key>
        _ = scanner.scanUpTo("<key>\(key)</key>", into: nil)
        // Scan up to the next, e.g. <date> tag (should be the next line)
        _ = scanner.scanUpTo("<\(type)>", into: nil)
        // Scan over the, e.g. <date> tag to get to the start of the expiry date string
        scanner.scanString("<\(type)>", into: nil)
        // Scan up to the, e.g. </date> tag and return what laid between
        var extractedNS: NSString?
        scanner.scanUpTo("</\(type)>", into: &extractedNS)
        guard let extracted = extractedNS as String? else {
            throw Error.notFound
        }
        
        return extracted
    }
}
