//
//  enum.swift
//  IPABuild
//
//  Created by fenglh on 2022/11/25.
//

import Foundation

enum CodeSignStyle: String {
    case Manual
    case Automatic
}

//enum DistributionType: String {
//    case unknow
//    case development
//    case appstore
//    case enterprise
//    case adhoc
//}

enum ConfigurationType: String {
    case Debug
    case Release
}

public enum Platform: String {
    case iOS
    case macOS
    case tvOS
    case watchOS
}
