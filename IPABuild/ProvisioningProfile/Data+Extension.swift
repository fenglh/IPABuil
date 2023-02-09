//
//  Data+Extension.swift
//  IPABuild
//
//  Created by fenglh on 2022/11/14.
//

import Foundation

extension Data {
    var hexDescription: String {
        return reduce("") {$0 + String(format:"%02x", $1)}
    }
}
