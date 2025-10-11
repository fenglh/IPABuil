//
//  TimeInterval+Extension.swift
//  IPABuild
//
//  Created by fenglh on 2023/12/21.
//

import Foundation


extension TimeInterval {
    var toInt64: Int64? {
        guard self <= TimeInterval(Int64.max) else { return nil }
        guard self >= TimeInterval(Int64.min) else { return nil }
        return Int64(self)
    }
}
