//
//  SFTP.swift
//  IPABuild
//
//  Created by fenglh on 2023/12/20.
//

import NMSSH_riden
import PathKit

struct SFTP {
    static var host = "192.168.1.100"
    static var port = 22
    static var username = "sftpuser" // sftp用户名
    static var password = "Flat!@#12" // 密码

    static func uploadFile(filePath: Path) {
        guard filePath.exists, filePath.isFile else { print("文件不存在!\(filePath)"); return }
        let session = NMSSHSession(host: host, port: port, andUsername: username)
        session.connect()
        guard session.isConnected else { return }
        print("会话连接成功！！")
        session.authenticate(byPassword: password)
        guard session.isAuthorized else { return }
        print("认证成功!!")
        let sftp = NMSFTP(session: session)
        if sftp.connect() {
            print("SFTP连接成功")
            
//            sftp.writeFile(atPath: filePath.string, toFileAtPath: "", progress: <#T##((UInt) -> Bool)?##((UInt) -> Bool)?##(UInt) -> Bool#>)
        } else {
            print("SFTP连接失败")
        }
    }
}
