//
//  PBXNativeTarget+Extension.swift
//  IPABuild
//
//  Created by fenglh on 2022/11/25.
//

import Foundation
import XcodeProj
import PathKit

extension PBXNativeTarget {
    
    func supportedPlatforms(withConfigurationType configurationType: ConfigurationType) -> Any? {
        return value(forKey: "SUPPORTED_PLATFORMS", withConfigurationType: configurationType)
    }
    
    func bundleId(withConfigurationType configurationType: ConfigurationType) -> String? {
        return value(forKey: "PRODUCT_BUNDLE_IDENTIFIER", withConfigurationType: configurationType) as? String
    }
    
    func baseConfiguration(withConfigurationType configurationType: ConfigurationType) -> PBXFileReference? {
        for conf in buildConfigurationList!.buildConfigurations where conf.name.lowercased() == configurationType.rawValue.lowercased() {
            return conf.baseConfiguration
        }
        return nil
    }
    
//    func baseXCConfig(withConfigurationType configurationType: ConfigurationType, projectPath: Path) throws -> XCConfig? {
//        guard let baseConfiguration = baseConfiguration(withConfigurationType: configurationType) else {
//            return nil
//        }
//        guard let fullPath = try baseConfiguration.fullPath(sourceRoot: rootPath) else {
//            return nil
//        }
//        return try XCConfig(path: fullPath, projectPath: projectPath)
//    }
    
//    func baseConfigurationFilePath(withConfigurationType configurationType: ConfigurationType) throws -> Path? {
//        guard let baseConfiguration = baseConfiguration(withConfigurationType: configurationType) else {
//            throw IPABuildError.getBaseConfigurationFail(target: self)
//        }
//
//        if let path = baseConfiguration.path {
//            return Path(path)
//        }
//        return nil
//    }
    
    func codeSignStyle(withConfigurationType configurationType: ConfigurationType) -> String? {
        return value(forKey: "CODE_SIGN_STYLE", withConfigurationType: configurationType) as? String
    }
    
    func value(forKey key: String, withConfigurationType configurationType: ConfigurationType) -> Any? {
        for conf in buildConfigurationList!.buildConfigurations where conf.name.lowercased() == configurationType.rawValue.lowercased() {
            return conf.buildSettings[key]
        }
        return nil
    }
    
}
