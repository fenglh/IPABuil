//
//  Date+Extension.swift
//  IPABuild
//
//  Created by fenglh on 2022/11/25.
//

import Foundation

extension Date {
    var expirationDays: Int {
       let left = timeIntervalSince1970 - Date().timeIntervalSince1970
       return (Int)(left/(24 * 3600.0))
    }
    
    var formattedString: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        formatter.timeZone = .current
        formatter.locale = .current
        return formatter.string(from: self)
    }
}
