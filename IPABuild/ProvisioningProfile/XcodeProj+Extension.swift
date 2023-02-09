//
//  XcodeProj+Extension.swift
//  IPABuild
//
//  Created by fenglh on 2022/11/25.
//

import Foundation
import XcodeProj

extension XcodeProj {
    
    func setCodeSignStyle(_ style: CodeSignStyle) {
        let key = "CODE_SIGN_STYLE"
        for conf in pbxproj.buildConfigurations where conf.buildSettings[key] != nil {
            conf.buildSettings[key] = style.rawValue
        }
    }

    func defaultTarget() -> PBXNativeTarget? {
        pbxproj.nativeTargets.first
    }
}
