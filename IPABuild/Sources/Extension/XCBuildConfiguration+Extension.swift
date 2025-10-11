//
//  XCBuildConfiguration+Extension.swift
//  IPABuild
//
//  Created by fenglh on 2023/12/21.
//

import XcodeProj

extension XCBuildConfiguration {
    var bundleId: String? {
        buildSettings["PRODUCT_BUNDLE_IDENTIFIER"] as? String
    }
    
    var supportedPlatforms:Any? {
        buildSettings["SUPPORTED_PLATFORMS"]
    }
    
    var codeSignStyle: String? {
        buildSettings["CODE_SIGN_STYLE"] as? String
    }
    
    var marketingVersion: String? {
        buildSettings["MARKETING_VERSION"] as? String
    }
    
    var currentProjectVersion: String? {
        buildSettings["CURRENT_PROJECT_VERSION"] as? String
    }


}
