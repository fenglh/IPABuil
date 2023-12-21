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

enum ConfigurationType: String {
    case debug
    case release
}

public enum Platform: String {
    case iOS
    case macOS
    case tvOS
    case watchOS
}
