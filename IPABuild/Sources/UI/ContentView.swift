//
//  ContentView.swift
//  IPABuild
//
//  Created by fenglh on 2025/10/29.
//

import Foundation
import SwiftUI
import ASN1Decoder
import AppKit

// 主视图
struct ContentView: View {
    @State private var certificates: [X509Certificate] = []
    @State private var privateKeyNames: Set<String> = []
    @State private var selectedIndex: Int? = nil
    @State private var showUntrustedWarning = true
    @State private var untrustedX509CertificateName = "Apple Push Services: com.dev.talk"

    // 过滤与排序
    @State private var searchText: String = ""
    @State private var onlyValid = true
    @State private var onlyAppleIssuer = false
    @State private var onlyWithPrivateKey = false
    @State private var onlyStarred = false
    @State private var sortOption: SortOption = .default
    // 列宽（可拖拽调整，持久化）
    @AppStorage("ColFavW") private var colFavWStore: Double = 26
    @AppStorage("ColNameW") private var colNameWStore: Double = 360
    @AppStorage("ColExpiryW") private var colExpiryWStore: Double = 180
    private var colFavW: CGFloat { get { CGFloat(colFavWStore) } set { colFavWStore = Double(max(20, newValue)) } }
    private var colNameW: CGFloat { get { CGFloat(colNameWStore) } set { colNameWStore = Double(max(120, newValue)) } }
    private var colExpiryW: CGFloat { get { CGFloat(colExpiryWStore) } set { colExpiryWStore = Double(max(140, newValue)) } }
    private var bindFavW: Binding<CGFloat> { Binding(get: { CGFloat(colFavWStore) }, set: { colFavWStore = Double(max(20, $0)) }) }
    private var bindNameW: Binding<CGFloat> { Binding(get: { CGFloat(colNameWStore) }, set: { colNameWStore = Double(max(120, $0)) }) }
    private var bindExpiryW: Binding<CGFloat> { Binding(get: { CGFloat(colExpiryWStore) }, set: { colExpiryWStore = Double(max(140, $0)) }) }
    
    // 默认使用登录钥匙串

    // 用户标记的可信证书ID（持久化）
    @AppStorage("UserTrustedCertIDs") private var userTrustedIDsStore: String = ""
    private func getUserTrustedIDs() -> Set<String> {
        Set(userTrustedIDsStore.split(separator: ",").map(String.init))
    }
    private func setUserTrustedIDs(_ ids: Set<String>) {
        userTrustedIDsStore = ids.joined(separator: ",")
    }

    // 用户“关注”标记集合（持久化）
    @AppStorage("UserStarredCertIDs") private var userStarredIDsStore: String = ""
    private func getUserStarredIDs() -> Set<String> {
        Set(userStarredIDsStore.split(separator: ",").map(String.init))
    }
    private func setUserStarredIDs(_ ids: Set<String>) {
        userStarredIDsStore = ids.joined(separator: ",")
    }

    // 计算属性：过滤 + 排序后的证书
    private var displayedCertificates: [X509Certificate] {
        var list = certificates
        if onlyValid { list = list.filter { !$0.isExpired } }
        if onlyAppleIssuer { list = list.filter { ($0.issuerOrganizationName ?? "").contains(IssuerOrganizationName.appleInc) } }
        if onlyWithPrivateKey { list = list.filter { nameFor($0).map { privateKeyNames.contains($0) } ?? false } }
        if onlyStarred {
            let starred = getUserStarredIDs()
            list = list.filter { starred.contains(certificateID($0)) }
        }
        if !searchText.isEmpty {
            let q = searchText.lowercased()
            list = list.filter {
                let name = $0.subjectCommonNames?.first?.lowercased() ?? ""
                let issuer = $0.issuerOrganizationName?.lowercased() ?? ""
                let serial = $0.serialNumberHex?.lowercased() ?? ""
                return name.contains(q) || issuer.contains(q) || serial.contains(q)
            }
        }
        switch sortOption {
        case .nameAsc:
            list.sort { (nameFor($0) ?? "") < (nameFor($1) ?? "") }
        case .nameDesc:
            list.sort { (nameFor($0) ?? "") > (nameFor($1) ?? "") }
        case .expiryAsc:
            list.sort { ($0.daysUntilExpiry.days, $0.daysUntilExpiry.hours) < ($1.daysUntilExpiry.days, $1.daysUntilExpiry.hours) }
        case .expiryDesc:
            list.sort { ($0.daysUntilExpiry.days, $0.daysUntilExpiry.hours) > ($1.daysUntilExpiry.days, $1.daysUntilExpiry.hours) }
        default:
            break
        }
        return list
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // 顶部工具栏
            HStack(spacing: 12) {
                // 筛选
                Text("筛选：").foregroundColor(.secondary)
                Toggle("有效", isOn: $onlyValid)
                    .toggleStyle(.switch)
                    .help("仅显示在有效期内的证书")
                Toggle("Apple签发", isOn: $onlyAppleIssuer)
                    .toggleStyle(.switch)
                    .help("仅显示由 Apple 机构签发的证书")
                Toggle("含私钥", isOn: $onlyWithPrivateKey)
                    .toggleStyle(.switch)
                    .help("仅显示钥匙串中带有私钥的证书")
                Toggle("关注", isOn: $onlyStarred)
                    .toggleStyle(.switch)
                    .help("仅显示已标记为关注的证书")

                Button("重置") {
                    onlyValid = true
                    onlyAppleIssuer = false
                    onlyWithPrivateKey = false
                    onlyStarred = false
                    searchText = ""
                    sortOption = .default
                }
                .buttonStyle(.bordered)
                .help("重置所有筛选项")

                Divider().frame(height: 20)

                // 搜索框
                TextField("搜索名称/签发者", text: $searchText)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .frame(maxWidth: 260)

                // 排序（与表头点击联动）
                Picker("排序", selection: $sortOption) {
                    Text("默认").tag(SortOption.default)
                    Text("名称↑").tag(SortOption.nameAsc)
                    Text("名称↓").tag(SortOption.nameDesc)
                    Text("到期↑").tag(SortOption.expiryAsc) // 近到远
                    Text("到期↓").tag(SortOption.expiryDesc) // 远到近
                }
                .frame(width: 160)
                Spacer()
                Button(action: refreshX509Certificates) {
                    Image(systemName: "arrow.clockwise")
                }
                .help("刷新证书列表")
            }
            .padding(12)

            Divider()

            // 内容
            VStack(spacing: 0) {
                if showUntrustedWarning { warningBanner }

                // 列表和详情
                HStack(spacing: 0) {
                    // 证书列表
                    ScrollView(.horizontal) {
                        let totalWidth = colFavW + colNameW + colExpiryW + 32
                        VStack(spacing: 0) {
                            // 表头（含拖拽分割线）
                            HStack(spacing: 0) {
                                headerFavoritesTriStateView()
                                    .frame(width: colFavW, alignment: .leading)
                                columnResizer(left: bindFavW, right: bindNameW)
                                headerSortableLabel(title: "名称", isActive: sortOption.isName, ascending: sortOption.isAscendingForName) { toggleSort(for: .name) }
                                    .frame(width: colNameW, alignment: .leading)
                                columnResizer(left: bindNameW, right: bindExpiryW)
                                headerSortableLabel(title: "过期时间", isActive: sortOption.isExpiry, ascending: sortOption.isAscendingForExpiry) { toggleSort(for: .expiry) }
                                    .frame(width: colExpiryW, alignment: .leading)
                            }
                            .font(.headline)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(Color.gray.opacity(0.1))
                            .frame(minWidth: totalWidth, alignment: .leading)

                            // 列表
                            List(selection: $selectedIndex) {
                                ForEach(Array(displayedCertificates.enumerated()), id: \.offset) { idx, cert in
                                    X509CertificateRow(
                                        certificate: cert,
                                        isUserTrusted: getUserTrustedIDs().contains(certificateID(cert)),
                                        isFavorite: favoriteBinding(for: cert),
                                        hasPrivateKey: nameFor(cert).map { privateKeyNames.contains($0) } ?? false,
                                        favWidth: colFavW, nameWidth: colNameW, expiryWidth: colExpiryW
                                    )
                                    .contextMenu { certificateContextMenu(cert) }
                                    .contentShape(Rectangle())
                                    .onTapGesture { selectedIndex = idx }
                                }
                            }
                            .listStyle(PlainListStyle())
                            .frame(minWidth: totalWidth, alignment: .leading)
                        }
                    }
                    .frame(minWidth: 520)

                    Divider()

                    // 详情
                    if let idx = selectedIndex, displayedCertificates.indices.contains(idx) {
                        X509CertificateDetailView(certificate: displayedCertificates[idx])
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .padding(16)
                    } else {
                        VStack(spacing: 12) {
                            Image(systemName: "certificate")
                                .font(.system(size: 48))
                                .foregroundColor(.gray)
                            Text("选择证书以查看详情")
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
            }
        }
        .frame(minWidth: 900, minHeight: 650)
        .onAppear {
            loadData()
        }
    }
    
    // 警告横幅
    private var warningBanner: some View {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.red)
            
            VStack(alignment: .leading, spacing: 2) {
                Text("\"\(untrustedX509CertificateName)\"证书不受信任")
                    .font(.system(size: 13, weight: .medium))
                Text("此证书标记为不受信任。")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Button("修复") {
                fixUntrustedX509Certificate()
            }
            .buttonStyle(BorderlessButtonStyle())
            .font(.system(size: 12))
            
            Button(action: { showUntrustedWarning = false }) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.gray)
            }
            .buttonStyle(PlainButtonStyle())
        }
        .padding(12)
        .background(Color.red.opacity(0.1))
        .overlay(
            Rectangle()
                .frame(height: 1)
                .foregroundColor(.red.opacity(0.3)),
            alignment: .bottom
        )
    }
    
    // 保留占位（如需表头样式可在此扩展）
    
    // 加载数据（默认登录钥匙串）
    private func loadData() {
        certificates = X509Certificate.findCertificates(in: .login) ?? []
        privateKeyNames = Set(X509Certificate.findCertificateNamesWithPrivateKey(in: .login))
        selectedIndex = nil
    }
    
    // 操作方法
    private func refreshX509Certificates() {
        // 模拟刷新操作
        print("刷新证书列表")
    }
    
    private func fixUntrustedX509Certificate() {
        showUntrustedWarning = false
        // 在实际应用中，这里会调用security命令修复证书信任
        print("修复不受信任的证书")
    }
    
    private func showX509CertificateInfo(_ certificate: X509Certificate) {
        print("显示证书信息: \(certificate.subjectCommonNames?.first ?? "-")")
    }
    
    private func exportX509Certificate(_ certificate: X509Certificate) {
        guard let name = certificate.subjectCommonNames?.first else { return }
        // 从 security 导出 PEM
        let cmd: String
        let kc = Keychain.login
        cmd = "security find-certificate -p -c \"\(name)\" \(kc.dbPath)"
        guard let pem = try? shellOut(to: cmd), pem.isEmpty == false else { return }
        let panel = NSSavePanel()
        panel.allowedFileTypes = ["cer", "pem"]
        panel.nameFieldStringValue = sanitizeFilename(name) + ".cer"
        if panel.runModal() == .OK, let url = panel.url {
            do { try pem.data(using: .utf8)?.write(to: url) } catch { print("写入失败: \(error)") }
        }
    }
    
    private func deleteX509Certificate(_ certificate: X509Certificate) {
        // 出于安全考虑，不提供实际删除；保留菜单项供扩展
        print("删除证书(未执行): \(certificate.subjectCommonNames?.first ?? "-")")
    }

    // 右键菜单
    @ViewBuilder
    private func certificateContextMenu(_ cert: X509Certificate) -> some View {
        Button("显示简介") { showX509CertificateInfo(cert) }
        Button("导出…") { exportX509Certificate(cert) }
        Divider()
        let id = certificateID(cert)
        if getUserTrustedIDs().contains(id) {
            Button("取消标记为可信") { toggleUserTrusted(cert) }
        } else {
            Button("标记为可信") { toggleUserTrusted(cert) }
        }
        let favId = certificateID(cert)
        if getUserStarredIDs().contains(favId) {
            Button("取消关注") { toggleFavorite(cert) }
        } else {
            Button("标记为关注") { toggleFavorite(cert) }
        }
        Divider()
        Button("复制名称") { copyToPasteboard(cert.subjectCommonNames?.first ?? "") }
        Button("复制序列号") { copyToPasteboard(cert.serialNumberHex ?? "") }
        Button("复制SHA1") { copyToPasteboard(fetchSHA1(cert) ?? "") }
    }

    private func toggleUserTrusted(_ cert: X509Certificate) {
        var ids = getUserTrustedIDs()
        let id = certificateID(cert)
        if ids.contains(id) { ids.remove(id) } else { ids.insert(id) }
        setUserTrustedIDs(ids)
    }

    private func toggleFavorite(_ cert: X509Certificate) {
        var ids = getUserStarredIDs()
        let id = certificateID(cert)
        if ids.contains(id) { ids.remove(id) } else { ids.insert(id) }
        setUserStarredIDs(ids)
    }

    private func certificateID(_ cert: X509Certificate) -> String {
        // 优先使用序列号，保证唯一性；
        // 若缺失，则退化到(主题CN + 颁发者 + 到期时间戳)的组合键，避免不同证书冲突。
        if let sn = cert.serialNumberHex, !sn.isEmpty {
            return sn
        }
        let name = cert.subjectCommonNames?.first ?? "-"
        let issuer = cert.issuerOrganizationName ?? "-"
        let end = Int(cert.notAfter?.timeIntervalSince1970 ?? 0)
        return "\(name)|\(issuer)|\(end)"
    }

    private func copyToPasteboard(_ text: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
    }

    // 列宽拖拽分隔条
    @ViewBuilder
    private func columnResizer(left: Binding<CGFloat>, right: Binding<CGFloat>, minLeft: CGFloat = 20, minRight: CGFloat = 60) -> some View {
        Rectangle()
            .fill(Color.gray.opacity(0.001)) // 扩大可点区域
            .frame(width: 6, height: 18)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let dx = value.translation.width
                        let newLeft = max(minLeft, left.wrappedValue + dx)
                        let delta = newLeft - left.wrappedValue
                        let newRight = max(minRight, right.wrappedValue - delta)
                        if newRight != right.wrappedValue { right.wrappedValue = newRight }
                        left.wrappedValue = newLeft
                    }
            )
            .padding(.horizontal, 2)
    }

    private func favoriteBinding(for cert: X509Certificate) -> Binding<Bool> {
        let id = certificateID(cert)
        return Binding<Bool>(
            get: { getUserStarredIDs().contains(id) },
            set: { newValue in
                var ids = getUserStarredIDs()
                if newValue { ids.insert(id) } else { ids.remove(id) }
                setUserStarredIDs(ids)
            }
        )
    }

    private func selectAllFavorites() {
        var ids = getUserStarredIDs()
        for cert in displayedCertificates { ids.insert(certificateID(cert)) }
        setUserStarredIDs(ids)
    }

    private func invertFavorites() {
        var ids = getUserStarredIDs()
        let displayIDs = displayedCertificates.map { certificateID($0) }
        for id in displayIDs {
            if ids.contains(id) { ids.remove(id) } else { ids.insert(id) }
        }
        setUserStarredIDs(ids)
    }

    private func fetchSHA1(_ cert: X509Certificate) -> String? {
        guard let name = cert.subjectCommonNames?.first else { return nil }
        let cmd: String
        let kc = Keychain.login
        cmd = "security find-certificate -Z -c \"\(name)\" \(kc.dbPath)"
        guard let output = try? shellOut(to: cmd) else { return nil }
        // 解析形如：SHA-1 hash: 0123456789ABCDEF...
        for line in output.split(separator: "\n") {
            if let range = line.range(of: "SHA-1 hash:") {
                return line[range.upperBound...].trimmingCharacters(in: .whitespaces)
            }
        }
        return nil
    }

    private func sanitizeFilename(_ s: String) -> String {
        let invalid = CharacterSet(charactersIn: "/\\?%*|\"<>:")
        return s.components(separatedBy: invalid).joined(separator: "_")
    }

    private func nameFor(_ cert: X509Certificate) -> String? { cert.subjectCommonNames?.first }

    // 表头：当前页全选三态
    private enum TriState { case all, none, partial }
    private func headerFavoritesState() -> TriState {
        let ids = getUserStarredIDs()
        let displayIDs = displayedCertificates.map { certificateID($0) }
        guard !displayIDs.isEmpty else { return .none }
        let count = displayIDs.filter { ids.contains($0) }.count
        if count == 0 { return .none }
        if count == displayIDs.count { return .all }
        return .partial
    }

    @ViewBuilder
    private func headerFavoritesTriStateView() -> some View {
        let state = headerFavoritesState()
        Button(action: headerFavoritesToggleAll) {
            Image(systemName: {
                switch state {
                case .all: return "checkmark.square"
                case .none: return "square"
                case .partial: return "minus.square"
                }
            }())
        }
        .buttonStyle(PlainButtonStyle())
        .help("当前页全选/全不选")
    }

    private func headerFavoritesToggleAll() {
        var ids = getUserStarredIDs()
        let displayIDs = displayedCertificates.map { certificateID($0) }
        switch headerFavoritesState() {
        case .all:
            for id in displayIDs { ids.remove(id) }
        default:
            for id in displayIDs { ids.insert(id) }
        }
        setUserStarredIDs(ids)
    }

    // 表头：可点击排序标签
    @ViewBuilder
    private func headerSortableLabel(title: String, isActive: Bool, ascending: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Text(title)
                if isActive {
                    Image(systemName: ascending ? "arrow.up" : "arrow.down")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
            }
        }
        .buttonStyle(PlainButtonStyle())
    }

    private enum SortKey { case name, expiry }
    private func toggleSort(for key: SortKey) {
        switch key {
        case .name:
            sortOption = (sortOption == .nameAsc) ? .nameDesc : .nameAsc
        case .expiry:
            sortOption = (sortOption == .expiryAsc) ? .expiryDesc : .expiryAsc
        }
    }
}

// 排序选项
enum SortOption: String, CaseIterable, Identifiable {
    case `default`
    case nameAsc
    case nameDesc
    case expiryAsc
    case expiryDesc
    var id: String { rawValue }

    var isName: Bool { self == .nameAsc || self == .nameDesc }
    var isExpiry: Bool { self == .expiryAsc || self == .expiryDesc }
    var isAscendingForName: Bool { self == .nameAsc }
    var isAscendingForExpiry: Bool { self == .expiryAsc }
}

// 证书行视图
struct X509CertificateRow: View {
    let certificate: X509Certificate
    let isUserTrusted: Bool
    @Binding var isFavorite: Bool
    let hasPrivateKey: Bool
    let favWidth: CGFloat
    let nameWidth: CGFloat
    let expiryWidth: CGFloat

    var body: some View {
        let showExpiryWarning = certificate.isExpired || certificate.isExpiringSoon
        return HStack(spacing: 8) {
            // 关注复选框
            Toggle("", isOn: $isFavorite)
                .toggleStyle(.checkbox)
                .labelsHidden()
                .frame(width: favWidth, alignment: .leading)

            // 名称 + 徽章
            HStack(spacing: 8) {
                Image(systemName: certificate.isTrusted ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                    .foregroundColor(certificate.isTrusted ? .green : .orange)
                    .font(.system(size: 12))
                if isUserTrusted {
                    Image(systemName: "shield.fill").foregroundColor(.green).font(.system(size: 10))
                }
                if hasPrivateKey {
                    Image(systemName: "key.fill").foregroundColor(.blue).font(.system(size: 10))
                }
                Text(certificate.subjectCommonNames?.first ?? "-")
                    .font(.system(size: 13))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
            }
            .frame(width: nameWidth, alignment: .leading)

            // 过期时间列
            HStack {
                Text(certificate.formattedExpiry)
                    .font(.system(size: 13))
                    .foregroundColor(showExpiryWarning ? .red : .primary)
                if showExpiryWarning {
                    Image(systemName: "exclamationmark.circle.fill").foregroundColor(.red).font(.system(size: 10))
                }
            }
            .frame(width: expiryWidth, alignment: .leading)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color.clear)
        .contentShape(Rectangle())
    }
}


// 证书详情视图
struct X509CertificateDetailView: View {
    let certificate: X509Certificate
    
    private var validityProgress: Double {
        guard let start = certificate.notBefore, let end = certificate.notAfter else { return 0 }
        let total = end.timeIntervalSince1970 - start.timeIntervalSince1970
        guard total > 0 else { return 0 }
        let now = Date().timeIntervalSince1970
        let passed = max(0, min(total, now - start.timeIntervalSince1970))
        return passed / total
    }

    private var keyUsageList: [String] {
        // 位序定义见 Pods/ASN1Decoder 注释
        let names = [
            "digitalSignature",
            "nonRepudiation",
            "keyEncipherment",
            "dataEncipherment",
            "keyAgreement",
            "keyCertSign",
            "cRLSign",
            "encipherOnly"
        ]
        return zip(names, certificate.keyUsage).compactMap { name, flag in flag ? name : nil }
    }

    private var extKeyUsageList: [String] {
        certificate.extendedKeyUsage.map { oid in
            mapExtendedKeyUsage(of: oid)
        }
    }

    private func mapExtendedKeyUsage(of oid: String) -> String {
        // 常见 EKU OID 映射
        switch oid {
        case "1.3.6.1.5.5.7.3.1": return "serverAuth"
        case "1.3.6.1.5.5.7.3.2": return "clientAuth"
        case "1.3.6.1.5.5.7.3.3": return "codeSigning"
        case "1.3.6.1.5.5.7.3.4": return "emailProtection"
        case "1.3.6.1.5.5.7.3.8": return "timeStamping"
        case "1.3.6.1.5.5.7.3.9": return "OCSPSigning"
        default: return oid
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // 标题 + 主题名称
            Text(certificate.subjectCommonNames?.first ?? "-")
                .font(.title3).bold()
                .textSelection(.enabled)

            // 颁发者 / 序列号
            HStack(spacing: 16) {
                Label("颁发者: \(certificate.issuerOrganizationName ?? "-")", systemImage: "building.2")
                Label("序列号: \(certificate.serialNumberHex ?? "-")", systemImage: "number")
            }
            .font(.system(size: 12))
            .foregroundColor(.secondary)
            .textSelection(.enabled)

            // 有效期区间 + 进度条
            VStack(alignment: .leading, spacing: 6) {
                let start = certificate.notBefore?.formattedString ?? "-"
                let end = certificate.notAfter?.formattedString ?? "-"
                Text("有效期: \(start) — \(end)").font(.system(size: 12)).foregroundColor(.secondary)
                Group {
                    if #available(macOS 12.0, *) {
                        ProgressView(value: validityProgress)
                            .tint(certificate.isExpired ? .red : (certificate.isExpiringSoon ? .orange : .green))
                    } else {
                        ProgressView(value: validityProgress)
                            .accentColor(certificate.isExpired ? .red : (certificate.isExpiringSoon ? .orange : .green))
                    }
                }
                Text("剩余: \(certificate.daysUntilExpiry.days) 天 \(certificate.daysUntilExpiry.hours) 小时")
                    .font(.system(size: 12))
                    .foregroundColor(certificate.isExpiringSoon ? .red : .secondary)
            }

            // 用途 OID
            VStack(alignment: .leading, spacing: 8) {
                Text("用途").font(.system(size: 12, weight: .semibold)).foregroundColor(.secondary)
                if !keyUsageList.isEmpty {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "hammer")
                        Text(keyUsageList.joined(separator: ", "))
                    }.font(.system(size: 12))
                }
                if !extKeyUsageList.isEmpty {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "text.badge.checkmark")
                        Text(extKeyUsageList.joined(separator: ", "))
                    }.font(.system(size: 12))
                }
            }

            // 主题/颁发者备用名称
            if !certificate.subjectAlternativeNames.isEmpty || !certificate.issuerAlternativeNames.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("备用名称").font(.system(size: 12, weight: .semibold)).foregroundColor(.secondary)
                    if !certificate.subjectAlternativeNames.isEmpty {
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "person.crop.circle")
                            Text(certificate.subjectAlternativeNames.joined(separator: ", "))
                        }.font(.system(size: 12))
                    }
                    if !certificate.issuerAlternativeNames.isEmpty {
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "building.2")
                            Text(certificate.issuerAlternativeNames.joined(separator: ", "))
                        }.font(.system(size: 12))
                    }
                }
            }

            // 密钥/签名/CA 信息
            VStack(alignment: .leading, spacing: 8) {
                Text("加密信息").font(.system(size: 12, weight: .semibold)).foregroundColor(.secondary)
                HStack(spacing: 16) {
                    let alg = certificate.publicKey?.algName ?? certificate.publicKey?.algOid ?? "-"
                    let keyBits = estimateKeyBits(pub: certificate.publicKey)
                    Label("公钥: \(alg) \(keyBits)", systemImage: "key")
                    let sig = certificate.sigAlgName ?? certificate.sigAlgOID ?? "-"
                    Label("签名: \(sig)", systemImage: "seal")
                    let isCA = (certificate.extensionObject(oid: .basicConstraints) as? X509Certificate.BasicConstraintExtension)?.isCA ?? false
                    Label(isCA ? "CA 证书" : "End-Entity", systemImage: isCA ? "shield.checkerboard" : "person.crop.square")
                }
                .font(.system(size: 12))
                .foregroundColor(.secondary)
            }

            Spacer()
        }
        .padding(8)
    }
}

private func estimateKeyBits(pub: X509PublicKey?) -> String {
    guard let pub = pub else { return "" }
    if let oid = pub.algOid, oid == OID.rsaEncryption.rawValue {
        let bytes = pub.key?.count ?? 0
        if bytes > 0 { return "\(bytes*8)bit" }
    }
    if let curve = pub.algParams {
        switch curve {
        case OID.prime256v1.rawValue: return "256bit"
        default: break
        }
    }
    return ""
}
