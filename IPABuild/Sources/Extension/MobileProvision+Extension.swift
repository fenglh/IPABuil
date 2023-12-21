//
//  MobileProvision+Extension.swift
//  IPABuild
//
//  Created by fenglh on 2022/11/12.
//

import Foundation
import ASN1Decoder
import PathKit

extension MobileProvision {
    
    var method: ExportOptions.Method {
        var type = ExportOptions.Method.unknow
        switch entitlements.apsEnvironment {
        case .development:
            if let getTaskAllow = entitlements.getTaskAllow, getTaskAllow {
                type = .development
            }
        case .production:
            if let _ = provisionedDevices {
                type = .adHoc
            } else if let provisionsAllDevices = provisionsAllDevices, provisionsAllDevices {
                type = .enterprise
            } else {
                type = .appStore
            }
        default:
            type = .unknow
        }
        return type
    }
    var isWildcard: Bool {
        return applicationIdentifier?.contains("*") ?? false
    }
    var applicationIdentifier: String? {
        guard let applicationIdentifier = entitlements.applicationIdentifier else {
            return nil
        }
        var index = applicationIdentifier.index(applicationIdentifier.startIndex, offsetBy: 11)
        if var prefix = applicationIdentifierPrefix.first {
            prefix = "\(prefix)."
            if applicationIdentifier.hasPrefix(prefix) {
                index = applicationIdentifier.index(applicationIdentifier.startIndex, offsetBy: prefix.count)
            }
        }
        return String(applicationIdentifier[index...])
    }
    
    var developerX509Certificates: [X509Certificate] {
        var ret = [X509Certificate]()
        for data in developerCertificates {
            guard let x509 = try? X509Certificate(data: data) else {
                continue
            }
            ret.append(x509)
        }
        return ret
    }
    
    var validDeveloperX509Certificates: [X509Certificate] {
        var ret = [X509Certificate]()
        guard let content = try? shellOut(to: "security find-identity -p codesigning -v") else {
            return ret
        }
        for data in developerCertificates {
            if content.lowercased().contains(data.sha1().lowercased()) {
                guard let x509 = try? X509Certificate(data: data), x509.checkValidity() else {
                    continue
                }
                ret.append(x509)
            }
        }
        return ret.sorted { cer1, cer2 in
            guard let notAfter1 = cer1.notAfter, let notAfter2 = cer2.notAfter else {
                return false
            }
            return notAfter1 > notAfter2
        }
    }
    
    func canSignBundleIdentifier(_ bundleIdentifier: String) -> Bool {
        guard let applicationIdentifier = applicationIdentifier else {
            return false
        }
        if isWildcard {
            let predicate = NSPredicate(format: "SELF MATCH %@", applicationIdentifier)
            return predicate.evaluate(with: bundleIdentifier)
        } else {
            return applicationIdentifier == bundleIdentifier
        }
    }
    
    func containDeviceUUID(_ uuid: String) -> Bool {
        guard let provisionedDevices = provisionedDevices else { return false }
        return provisionedDevices.contains(uuid)
    }
    
    static func defaultMobileProvisions(_ path: String = "${HOME}/Library/MobileDevice/Provisioning Profiles" ) -> [MobileProvision] {
        var rets = [MobileProvision]()
        guard let absolutePath = try? shellOut(to: "echo \(path)") else { return rets }
        guard let enumerator = FileManager.default.enumerator(atPath: absolutePath) else { return rets }
        for obj in enumerator.allObjects {
            guard let file = obj as? String else {
                continue
            }
            let filePath = Path(absolutePath) + Path(file)
            if let mobileProvision = MobileProvision.read(from: filePath.string) {
                rets.append(mobileProvision)
            }
        }
        return rets
    }
    

    func description() -> String {
        var content = "👇🏻👇🏻👇🏻👇🏻👇🏻👇🏻👇🏻👇🏻👇🏻Provisioning Profile👇🏻👇🏻👇🏻👇🏻👇🏻👇🏻👇🏻👇🏻👇🏻\n"
        content.append("Name:\(name)\n")
        if let applicationIdentifier = applicationIdentifier {
            content.append("Application Identifier:\(applicationIdentifier)\n")
        }
        content.append("AppIDName:\(appIDName)\n")
        content.append("Method Type:\(method.rawValue)\n")
        content.append("Team Identifier:\(teamIdentifier)\n")
        content.append("Team Name:\(teamName)\n")
        content.append("Created:\(creationDate.formattedString)\n")
        content.append("Expire:\(expirationDate.formattedString) (Expires in \(expirationDate.expirationDays) days)\n")
        
        if let getTaskAllow = entitlements.getTaskAllow {
            content.append("Get Task Allow:\(getTaskAllow)\n")
        }
        if let developerPushToTalk = entitlements.developerPushToTalk {
            content.append("Developer Push To Talk:\(developerPushToTalk)\n")
        }
        content.append("UUID:\(uuid)\n")
        content.append("Application Identifier Prefix:\(applicationIdentifierPrefix)\n")

        content.append("Platform:\(platform)\n")
        if let isXcodeManaged = isXcodeManaged {
            content.append("is Xcode Managed:\(isXcodeManaged)\n")
        }
        if let provisionedDevices = provisionedDevices {
            content.append("Devices:\(provisionedDevices.count) Included\n")
        }
        
        if let provisionsAllDevices = provisionsAllDevices {
            content.append("Provisions All Devices:\(provisionsAllDevices)\n")
        }
        
        content.append("Time To Live:\(timeToLive)\n")
        content.append("Version:\(version)\n")
        
        var index = 1
        for certificate in validDeveloperX509Certificates {
            guard let serialNumberHex = certificate.serialNumberHex, let name = certificate.subjectCommonNames?.first else {
                continue
            }
            content.append("valid certificate \(index)\n")
            content.append("\tname:\(name)\n")
            content.append("\tsnbr:\(serialNumberHex)\n")
            if let notBefore = certificate.notBefore, let notAfter = certificate.notAfter {
                content.append("\tnotBefore:\(notBefore.formattedString)\n")
                content.append("\tnotAfter:\(notAfter.formattedString)(Expires in \(notAfter.expirationDays) days)\n")
            }
            index += 1
        }
        
        content.append("👆🏻👆🏻👆🏻👆🏻👆🏻👆🏻👆🏻👆🏻👆🏻Provisioning Profile👆🏻👆🏻👆🏻👆🏻👆🏻👆🏻👆🏻👆🏻👆🏻\n")
        return content
    }
}

