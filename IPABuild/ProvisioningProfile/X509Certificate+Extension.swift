//
//  X509Certificate+Extension.swift
//  IPABuild
//
//  Created by fenglh on 2022/11/24.
//

import Foundation
import ASN1Decoder
import CommonCrypto


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
    


    
    //MARK: - Private
    /// 没有私钥的证书也会被找到
    func findValidLocalCertificates(withSubjectCommonName subjectCommonName: String) -> [X509Certificate]? {
        guard let pemsString = try? shellOut(to: "security find-certificate -a -c \"\(subjectCommonName)\" -p") else {
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
                  let certificate = try? X509Certificate(pem: pemData),
                    certificate.checkValidity() else {
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


