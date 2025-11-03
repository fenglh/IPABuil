//
//  main.swift
//  IPABuild
//
//  Created by fenglh on 2022/11/11.
//
// https://www.testdevlab.com/blog/xcode-provisioning-profile-automation-for-ci

import ASN1Decoder
import Foundation
import PathKit
import XcodeProj

/// 证书的生成和使用过程：
/// 1. 本地生成：【公钥L】、【私钥L】
/// 2. 将公钥+个人信息封装到：
/// 3. 将【.certSigningRequest】上传到苹果MC
/// 4. MC从【.certSigningRequest】取出【个人信息】、【公钥L】，并加上【苹果的签名】，生成了x【509证书C】
/// 5. 开发者另外生成的【mobileprovision】文件中developerCertificates证书列表包含该【x509证书C】
/// 6. App在签名的时使用的【私钥L】进行签名
/// 7. App打包的时候会把【mobileprovision】文件打包到ipa
/// 8. IPA 安装的时候，会取出【mobileprovision】文件，通过设备内置的【公钥X】对签名进行校验，确认【mobileprovision】文件是否合法。
/// 9. 确认【mobileprovision】文件合法后，从中取出【公钥L】去验证App的签名。
/// 10. 签名通过即可安装

/// 自动签名原理：
/// 即使没有勾选“Automatically manage signing”，
/// 但"Build Settings - Code Signing Identity" 中选择iOS Developer 或者 Apple Developer
/// 也会根据配置的Provisioning Profile 匹配到正确的证书。

/// 检查IPA的签名：
/// codesign --verify Example.app

struct CertificateFilter {
    // 有私钥
    let withPrivateKey: Bool = true
    // 有签发者名字
    let withIssuerOrgNames: [String] = [IssuerOrganizationName.appleInc]
}

// 将原先命令行入口的输出改为可复用的调试函数，避免与 SwiftUI @main 冲突。
func debugListCertificates() {
    let keychain: Keychain = .login
    let certificates = X509Certificate.findCertificates(in: keychain)
    let certificateNamesWithPrivateKey = X509Certificate.findCertificateNamesWithPrivateKey(in: keychain)
    let filter = CertificateFilter()

    var index = 1
    certificates?.forEach { cer in
        let daysUntilExpiry = cer.daysUntilExpiry
        guard let subjectCommonName = cer.subjectCommonNames?.first else { return }

        if filter.withPrivateKey {
            guard certificateNamesWithPrivateKey.contains(subjectCommonName) else { return }
        }
        if filter.withIssuerOrgNames.isEmpty == false {
            guard let issuerOrgName = cer.issuerOrganizationName else { return }
            guard filter.withIssuerOrgNames.contains(issuerOrgName) else { return }
        }

        let expiryText: String = (daysUntilExpiry.days < 0 || daysUntilExpiry.hours < 0)
            ? "⚠️已过期"
            : "\(daysUntilExpiry.days)天\(daysUntilExpiry.hours)小时"

        print("\(index)【\(subjectCommonName)】\(expiryText)")
        index += 1
    }
}
