//
//  XcodeProjMgr.swift
//  IPABuild
//
//  Created by fenglh on 2022/11/11.
//

import Foundation
import PathKit
import XcodeProj

enum IPABuildError: Error, CustomStringConvertible {
    case notFound(path: Path)
    case pbxprojNotFound(path: Path)
    case xcworkspaceNotFound(path: Path)
    case schemeNotFound(name: String, schemes: [XCScheme]?)
    case invalidMethod(method: ExportOptions.Method)
    case targetNotFound(name: String, scheme: XCScheme)
    case bundleIdNotFound(name: String)
    case mobileProvisionNotFound(bundleId: String, target: PBXNativeTarget)
    case teamIDNotFound(mobileProvision: MobileProvision)
    case certificateNotFound(mobileProvision: MobileProvision)
    case xcodebuildFail(cmd: String)
    case createXCconfigFileFail(path: Path)
    case getBaseConfigurationFail(target: PBXNativeTarget)
    case schemeNotBuildForArchiving(scheme: XCScheme)
    var description: String {
        switch self {
        case let .notFound(path):
            return "The project cannot be found at path:\(path.string)"
        case let .pbxprojNotFound(path):
            return "The project doesn't contain a .pbxproj file at path:\(path.string)"
        case let .xcworkspaceNotFound(path):
            return "The project doesn't contain a .xcworkspace at path:\(path.string)"
        case let .schemeNotFound(name, schemes):
            var log = "The scheme cannot be found with name '\(name)'. Ensure the 'Shared' box is checked for the scheme '\(name)'"
            if let names = schemes?.compactMap({ $0.name }) {
                log += ", or you can choose one of the schemes:\(names)"
            }
            return log
        case let .invalidMethod(method):
            return "IPABuild not yet supported build with method:\(method.rawValue)"
        case let .bundleIdNotFound(name):
            return "The bundle identifier cannot be found in target:\(name)"
        case let .mobileProvisionNotFound(bundleId, target):
            return "The valid mobile provision cannot be found with bundle identifier '\(bundleId)' in target '\(target.name)'"
        case let .certificateNotFound(mobileProvision):
            return "The valid certificate cannot be found with a mobile provision:\(mobileProvision.name)"
        case let .teamIDNotFound(mobileProvision):
            return "The team identifier cannot be found with a mobile provision:\(mobileProvision.name)"
        case let .xcodebuildFail(cmd):
            return "Faild to execute command:\(cmd)"
        case let .createXCconfigFileFail(path):
            return "Faild to create .xcconfig file at path:\(path.string)"
        case let .getBaseConfigurationFail(target):
            return "Faild to get base configuration in target:\(target.name)"
        case let .schemeNotBuildForArchiving(scheme):
            let targetNames = scheme.buildAction?.buildActionEntries.compactMap { $0.buildableReference.blueprintName }
            return "Any one of the targets \(targetNames ?? []) in scheme '\(scheme.name)' cannot be build for archiving. Ensure the 'Archive' box is checked or target is effective"
        case let .targetNotFound(name, scheme):
            return "The target '\(name)' cannot be fount in scheme '\(scheme.name)' "
        }
    }
}

class IPABuild {
    var projectPath: Path
    var xcodeproj: XcodeProj
    
    public init(path: Path) throws {
        projectPath = path
        xcodeproj = try XcodeProj(path: path)
    }
    
    public func build(scheme name: String,
                      type: ConfigurationType = .release,
                      method: ExportOptions.Method = .development,
                      platform: Platform = .iOS) throws
    {
        guard supportedMethod(method: method) else {
            throw IPABuildError.invalidMethod(method: method)
        }
        
        guard let schemes = xcodeproj.sharedData?.schemes,
              let scheme = schemes.first(where: {
                  $0.name == name
              })
        else {
            throw IPABuildError.schemeNotFound(name: name, schemes: xcodeproj.sharedData?.schemes)
        }
        
        guard let entry = scheme.buildAction?.buildActionEntries.first(where: { $0.buildFor.contains(.archiving) && xcodeproj.pbxproj.nativeTargets.compactMap { $0.name
        }.contains($0.buildableReference.blueprintName)
        }) else {
            throw IPABuildError.schemeNotBuildForArchiving(scheme: scheme)
        }
        
        let targetName = entry.buildableReference.blueprintName

        guard let target = xcodeproj.pbxproj.nativeTargets.first(where: { $0.name == targetName }) else {
            throw IPABuildError.targetNotFound(name: targetName, scheme: scheme)
        }
        
        guard let bundleId = target.buildConfiguration(with: type)?.bundleId else {
            throw IPABuildError.bundleIdNotFound(name: targetName)
        }
        
        guard let mobileProvision = findValidMobileProvision(withBundleId: bundleId, method: method, platform: platform) else {
            throw IPABuildError.mobileProvisionNotFound(bundleId: bundleId, target: target)
        }
        
        guard let teamID = mobileProvision.teamIdentifier.first else {
            throw IPABuildError.teamIDNotFound(mobileProvision: mobileProvision)
        }
        
        guard let certificate = mobileProvision.validDeveloperX509Certificates.first,
              let certificateName = certificate.subjectCommonNames?.first
        else {
            throw IPABuildError.certificateNotFound(mobileProvision: mobileProvision)
        }
                
        let archivePath = archivePath(withName: name)
        var args = [String]()
        args.append("xcodebuild archive")
        let destination = Destination.generic(platform: .iOS)
        args.append("-destination '\(destination.argument)'")
        if let xcworkspacePath = xcworkspacePath, xcworkspacePath.exists {
            args.append("-workspace \(xcworkspacePath.string)")
        }
        args.append("-scheme \(name)")
        args.append("-archivePath \(archivePath.string)")
        args.append("-configuration \(type.rawValue)")
        args.append("CODE_SIGN_STYLE=\(CodeSignStyle.Manual.rawValue)")
        args.append("PROVISIONING_PROFILE='\(mobileProvision.uuid)'")
        args.append("PROVISIONING_PROFILE_SPECIFIER='\(mobileProvision.uuid)'")
        args.append("DEVELOPMENT_TEAM=\(teamID)")
        args.append("CODE_SIGN_IDENTITY='\(certificateName)'")
        // Adding CODE_SIGNING_REQUIRED=Yes and CODE_SIGNING_ALLOWED=No because of this answer:
        // https://forums.swift.org/t/xcode-14-beta-code-signing-issues-when-spm-targets-include-resources/59685/17
        // https://blog.codemagic.io/code-signing-issues-in-xcode-14-and-how-to-fix-them/
        args.append("CODE_SIGNING_REQUIRED=YES")
        args.append("CODE_SIGNING_ALLOWED=NO")
        args.append("clean")
        args.append("build")
        let cmdString = args.joined(separator: " ")
        let cmd = ShellOutCommand(string: cmdString)
        var archiveSucceed = false
        try shellOut(to: cmd) {
            print($0)
            
            if $0.contains("** ARCHIVE SUCCEEDED **") {
                archiveSucceed = true
            }
        }
        
        if archiveSucceed {
            print("** ARCHIVE SUCCEEDED **")
            // TODO: provisioningProfiles 添加Extension的bundleId和uuid
            // TODO: 根据描述文件动态配置method
            let options = ExportOptions(method: method,
                                        export: .nonAppStore(),
                                        signing: .manual(provisioningProfiles: [bundleId: mobileProvision.uuid]),
                                        teamID: mobileProvision.teamIdentifier.first)
            
            try options.writeToPath(path: exportOptionalsPath.url)
            try exportIPA(with: archivePath, optionsPath: exportOptionalsPath, exportPath: exportPath)
        }
    }
    
    func exportIPA(with archivePath: Path, optionsPath: Path, exportPath: Path) throws {
        guard archivePath.exists else { print("\(archivePath) 路径不存在"); return }
        guard optionsPath.exists else { print("\(optionsPath) 路径不存在"); return }
        guard exportPath.exists else { print("\(exportPath) 路径不存在"); return }
        
        var args = [String]()
        args.append("xcodebuild -exportArchive")
        args.append("-archivePath \(archivePath.string)")
        args.append("-exportPath \(exportPath.string)")
        args.append("-exportOptionsPlist \(optionsPath.string)")
        let cmdString = args.joined(separator: " ")
        print(cmdString)
        let cmd = ShellOutCommand(string: cmdString)
        try shellOut(to: cmd) {
            print($0)
        }
        print("** EXPORT FINISHED **")
    }
}

/// 代码签名
/// https://blog.codemagic.io/code-signing-issues-in-xcode-14-and-how-to-fix-them/

extension IPABuild {
    var rootPath: Path {
        return projectPath.parent()
    }
    
    var buildPath: Path {
        return rootPath + "ipabuild"
    }
    
    var exportOptionalsPath: Path {
        return buildPath + "exportOptionals.plist"
    }
    
    var exportPath: Path {
        return buildPath
    }
    
    var xcworkspacePath: Path? {
        return rootPath.glob("*.xcworkspace").first
    }
    
    func archivePath(withName name: String) -> Path {
        return buildPath + "\(name).xcarchive"
    }
    
    func findValidMobileProvision(withBundleId bundleId: String,
                                  method: ExportOptions.Method,
                                  platform: Platform) -> MobileProvision?
    {
        let mobileProvisions = MobileProvision.defaultMobileProvisions()
        var lastestMobileProvision: MobileProvision?
        for mobileProvision in mobileProvisions {
            guard mobileProvision.method == method,
                  mobileProvision.canSignBundleIdentifier(bundleId),
                  mobileProvision.platform.contains(platform.rawValue)
            else {
                continue
            }
            if let expirationDate = lastestMobileProvision?.expirationDate,
               expirationDate > mobileProvision.expirationDate
            {
                continue
            }
            lastestMobileProvision = mobileProvision
        }
        return lastestMobileProvision
    }
    
    func supportedMethod(method: ExportOptions.Method) -> Bool {
        method == .appStore
            || method == .development
            || method == .adHoc
            || method == .enterprise
    }
}
