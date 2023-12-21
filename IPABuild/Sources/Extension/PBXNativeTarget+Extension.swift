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
    
    func buildConfiguration(with type: ConfigurationType) -> XCBuildConfiguration? {
        for conf in buildConfigurationList!.buildConfigurations where conf.name.lowercased() == type.rawValue.lowercased() {
            return conf
        }
        return nil
    }
    
}
