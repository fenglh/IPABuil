//
//  X509Certificate+Extension.swift
//  IPABuild
//
//  Created by fenglh on 2022/11/24.
//

import Foundation
import ASN1Decoder
import CommonCrypto

enum IssuerOrganizationName {
    static let appleInc = "Apple Inc."
    static let veriSignInc = "VeriSign, Inc."
}

enum Keychain {
    case `default`
    case login
    
    var dbPath: String {
        switch self {
        case .`default`:
            return ""
        case .login:
            return "~/Library/Keychains/login.keychain-db"
        }
    }
}

struct X509CertificateModel {
    var sha1: String
    var certificate: X509Certificate
}

extension X509Certificate {
    
    //MARK: - 主题信息
    /// 主题用户ID
    var subjectUserIds: [String]? {
        return subject(oid: .userId)
    }
    
    /// 主题常用名称
    var subjectCommonNames: [String]? {
        return subject(oid: .commonName)
    }
    
    /// 主题组织单位名称
    var subjectOrganizationalUnitNames: [String]? {
        return subject(oid: .organizationalUnitName)
    }
    
    /// 主题组织名称
    var subjectOrganizationNames: [String]? {
        return subject(oid: .organizationName)
    }
    
    /// 主题国家或地区
    var subjectCountryNames: [String]? {
        return subject(oid: .countryName)
    }
    
    //MARK: - 签发者信息
 
    /// 签发者常用名称
    var issuerCommonName: String? {
        return issuer(oid: .commonName)
    }
    
    /// 签发者组织单位
    var issuerOrganizationalUnitName: String? {
        return issuer(oid: .organizationalUnitName)
    }
    
    /// 签发者组织
    var issuerOrganizationName: String? {
        return issuer(oid: .organizationName)
    }
    
    /// 签发者国家或地区
    var issuerCountryName: String? {
        return issuer(oid: .countryName)
    }
    //MARK: - 序列号
    /// 序列号
    var serialNumberHex: String? {
        guard let serialNumber = serialNumber else {return nil}
        return serialNumber.hexDescription.uppercased()
    }
    
    /// 剩余有效天数
    var daysUntilExpiry: (days: Int, hours: Int) {
        guard let notAfter else { return (0, 0) }
        let now = Date()
        return timeBetweenDates(startDate: now, endDate: notAfter)
    }

 
}

private extension X509Certificate {
    func timeBetweenDates(startDate: Date, endDate: Date) -> (days: Int, hours: Int) {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.day, .hour], from: startDate, to: endDate)
        return (components.day ?? 0, components.hour ?? 0)
    }
}

extension X509Certificate {
    /// 查找登录钥匙串中所有包含私钥的证书，不关心具体用途。
    /// - Returns: 包含私钥的证书序列号数组
    static func findCertificateNamesWithPrivateKey(in keychain: Keychain) -> [String] {
        let cmd = "security find-identity -p basic \(keychain.dbPath)"
        
        guard let outputString = try? shellOut(to: cmd) else {
            return []
        }
        
        // 使用正则表达式匹配证书名称
        let pattern = "\"([^\"]+)\""
        let regex = try? NSRegularExpression(pattern: pattern, options: [])
        let matches = regex?.matches(in: outputString, options: [], range: NSRange(location: 0, length: outputString.count))
        
        let certificateNames: [String] = matches?.compactMap { match in
            guard match.numberOfRanges > 1,
                  let range = Range(match.range(at: 1), in: outputString) else {
                return nil
            }
            return String(outputString[range])
        } ?? []
        
        return Array(Set(certificateNames)) // 去重并返回
    }
    
    static func findCertificates(in keychain: Keychain) -> [X509Certificate]? {
        
        guard let pemsString = try? shellOut(to: "security find-certificate -p -a \(keychain.dbPath)") else {
            return nil
        }
        let endPemBlock   = "-----END CERTIFICATE-----"
        let pems = pemsString.components(separatedBy: endPemBlock).filter {
            $0 != ""
        }.compactMap{
            "\($0)\(endPemBlock)"
        }
        var certificates = [X509Certificate]()
        for pem in pems {
            guard let pemData = pem.data(using: .ascii),
                  let certificate = try? X509Certificate(pem: pemData) else {
                continue
            }
            certificates.append(certificate)
        }
        return certificates
    }
}

extension Data {
    
    func sha1() -> String {
        var digest = [UInt8](repeating: 0, count:Int(CC_SHA1_DIGEST_LENGTH))
        let newData = NSData.init(data: self)
        CC_SHA1(newData.bytes, CC_LONG(self.count), &digest)
        let output = NSMutableString(capacity: Int(CC_SHA1_DIGEST_LENGTH))
        for byte in digest {
            output.appendFormat("%02x", byte)
        }
        return output as String
    }
}


