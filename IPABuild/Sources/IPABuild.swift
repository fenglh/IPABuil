//
//  XcodeProjMgr.swift
//  IPABuild
//
//  Created by fenglh on 2022/11/11.
//

import ASN1Decoder
import Foundation
import PathKit
import XcodeProj

enum BuildError: Error, CustomStringConvertible {
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

struct BuildParams {
    var bundleId: String
    var scheme: String
    var method: ExportOptions.Method
    var teamId: String
    var type: ConfigurationType
    var mobileProvisionUUID: String
    var certificateName: String
    var platform: Platform = .iOS
    var projectVersion: String?
    var marketingVersion: String?
}

class IPABuild {
    var projectPath: Path
    var xcodeproj: XcodeProj
    
    public init(path: Path) throws {
        projectPath = path
        xcodeproj = try XcodeProj(path: path)
    }
    
    public func run(scheme: String, method: ExportOptions.Method) throws {
        
        try buildPath.delete()
        
        if !buildPath.exists {
            try buildPath.mkdir()
        }
        
        let result = try makeBuildParams(scheme: scheme, method: method)
        switch result {
        case let .failure(err):
            print("❌❌❌构建失败：\(err.description)")
        case let .success(params):
            var name = params.scheme
            if let marketingVersion = params.marketingVersion {
                name += "-\(marketingVersion)"
                if let projectVersion = params.projectVersion {
                    name += "[\(projectVersion)]"
                }
            }
            let time = Date().timeIntervalSince1970.toInt64 ?? 0
            name += "-\(time)"

            
            let archviePath = buildPath + "\(name).xcarchive"
            let buildCMD = makeBuildCMD(with: params, archivePath: archviePath.string)
            guard let buildCMD else {
                print("❌❌❌ buildCMD 生成失败！")
                return
            }
            // 开始构建
            var ret = false
            try shellOut(to: ShellOutCommand(string: buildCMD)) {
                print($0)
                if $0.contains("** ARCHIVE SUCCEEDED **") {
                    ret = true
                } else if $0.contains("** ARCHIVE FAILED **") {
                    ret = true
                }
            }
            
            guard ret, archviePath.exists else {
                print("❌❌❌ Archive 失败：\(archviePath)")
                return
            }
            
            print("✅✅✅ Archive 成功：\(archviePath)")
            
            let exportPlistPath = buildPath + "exportOptions.plist"
            
            try makeExportPlist(bundleId: params.bundleId, teamId: params.teamId, mobileProvisionUUID: params.mobileProvisionUUID, method: params.method, outputPath: exportPlistPath)
            guard exportPlistPath.exists else {
                print("❌❌❌ exportPlist 生成失败！")
                return
            }
            print("✅✅✅ exportPlist 生成成功！")
            
            
            let exportIPACmd = makeExportIPACMD(archivePath: archviePath, plistPath: exportPlistPath, outputPath: buildPath)
            
            guard let exportIPACmd else {
                print("❌❌❌ exportIPACmd 生成失败！")
                return
            }
            
            
            try shellOut(to: ShellOutCommand(string: exportIPACmd)) {
                print($0)
                if $0.contains("** EXPORT SUCCEEDED **") {
                    ret = true
                } else if $0.contains("** EXPORT FAILED **") {
                    ret = true
                }
            }
            
        
            print("✅✅✅ export IPA 结束")

        }
    }
    
    
    func clean() throws {
        try FileManager.default.removeItem(atPath: buildPath.string)
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
    
    var xcworkspacePath: Path? {
        return rootPath.glob("*.xcworkspace").first
    }
    
    private func findValidMobileProvision(withBundleId bundleId: String,
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
    
    private func makeBuildParams(scheme name: String,
                                 method: ExportOptions.Method,
                                 type: ConfigurationType = .release,
                                 platform: Platform = .iOS) throws -> Result<BuildParams, BuildError>
    {
        guard let schemes = xcodeproj.sharedData?.schemes,
              let scheme = schemes.first(where: {
                  $0.name == name
              })
        else {
            return .failure(.schemeNotFound(name: name, schemes: xcodeproj.sharedData?.schemes))
        }
        
        guard let entry = scheme.buildAction?.buildActionEntries.first(where: { $0.buildFor.contains(.archiving) && xcodeproj.pbxproj.nativeTargets.compactMap { $0.name
        }.contains($0.buildableReference.blueprintName)
        }) else {
            return .failure(.schemeNotBuildForArchiving(scheme: scheme))
        }
        
        let targetName = entry.buildableReference.blueprintName

        guard let target = xcodeproj.pbxproj.nativeTargets.first(where: { $0.name == targetName }) else {
            return .failure(.targetNotFound(name: targetName, scheme: scheme))
        }
        
        guard let bundleId = target.buildConfiguration(with: type)?.bundleId else {
            return .failure(.bundleIdNotFound(name: targetName))
        }
        
        guard let mobileProvision = findValidMobileProvision(withBundleId: bundleId, method: method, platform: platform) else {
            return .failure(.mobileProvisionNotFound(bundleId: bundleId, target: target))
        }
        
        guard let teamId = mobileProvision.teamIdentifier.first else {
            return .failure(.teamIDNotFound(mobileProvision: mobileProvision))
        }
        
        guard let certificate = mobileProvision.validDeveloperX509Certificates.first,
              let certificateName = certificate.subjectCommonNames?.first
        else {
            return .failure(.certificateNotFound(mobileProvision: mobileProvision))
        }
        
        var result = BuildParams(bundleId: bundleId, scheme: name, method: method, teamId: teamId, type: type, mobileProvisionUUID: mobileProvision.uuid, certificateName: certificateName)
        result.marketingVersion = target.buildConfiguration(with: type)?.marketingVersion
        result.projectVersion = target.buildConfiguration(with: type)?.currentProjectVersion
        return .success(result)
    }
    
    private func makeBuildCMD(with params: BuildParams,
                              archivePath: String) -> String?
    {
        var args = [String]()
        args.append("xcodebuild archive")
        let destination = Destination.generic(platform: .iOS)
        args.append("-destination '\(destination.argument)'")
        if let xcworkspacePath = xcworkspacePath, xcworkspacePath.exists {
            args.append("-workspace \(xcworkspacePath.string)")
        }
        args.append("-scheme \(params.scheme)")
        args.append("-archivePath \(archivePath)")
        args.append("-configuration \(params.type.rawValue)")
        args.append("CODE_SIGN_STYLE=\(CodeSignStyle.Manual.rawValue)")
        args.append("PROVISIONING_PROFILE='\(params.mobileProvisionUUID)'")
        args.append("PROVISIONING_PROFILE_SPECIFIER='\(params.mobileProvisionUUID)'")
        args.append("DEVELOPMENT_TEAM=\(params.teamId)")
        args.append("CODE_SIGN_IDENTITY='\(params.certificateName)'")
        // Adding CODE_SIGNING_REQUIRED=Yes and CODE_SIGNING_ALLOWED=No because of this answer:
        // https://forums.swift.org/t/xcode-14-beta-code-signing-issues-when-spm-targets-include-resources/59685/17
        // https://blog.codemagic.io/code-signing-issues-in-xcode-14-and-how-to-fix-them/
        args.append("CODE_SIGNING_REQUIRED=YES")
        args.append("CODE_SIGNING_ALLOWED=NO")
        args.append("clean")
        args.append("build")
        return args.joined(separator: " ")
    }
    
    private func makeExportPlist(bundleId: String,
                                 teamId: String,
                                 mobileProvisionUUID: String,
                                 method: ExportOptions.Method,
                                 exportConfig: ExportOptions.Export = .nonAppStore(), outputPath: Path) throws
    {
        // TODO: provisioningProfiles 添加Extension的bundleId和uuid
        let options = ExportOptions(method: method,
                                    export: exportConfig,
                                    signing: .manual(provisioningProfiles: [bundleId: mobileProvisionUUID]),
                                    teamID: teamId)
        try options.writeToPath(path: outputPath.url)
    }
    
    private func makeExportIPACMD(archivePath: Path, plistPath: Path, outputPath: Path) -> String? {
        var args = [String]()
        args.append("xcodebuild -exportArchive")
        args.append("-archivePath \(archivePath.string)")
        args.append("-exportPath \(outputPath.string)")
        args.append("-exportOptionsPlist \(plistPath.string)")
        return args.joined(separator: " ")
    }
    
}
