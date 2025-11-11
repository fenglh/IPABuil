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
import CryptoKit

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
    private let operationColumnWidth: CGFloat = 80
    private var bindFavW: Binding<CGFloat> { Binding(get: { CGFloat(colFavWStore) }, set: { colFavWStore = Double(max(20, $0)) }) }
    private var bindNameW: Binding<CGFloat> { Binding(get: { CGFloat(colNameWStore) }, set: { colNameWStore = Double(max(120, $0)) }) }
    private var bindExpiryW: Binding<CGFloat> { Binding(get: { CGFloat(colExpiryWStore) }, set: { colExpiryWStore = Double(max(140, $0)) }) }
    
    // 钉钉自动提醒配置
    @AppStorage("DingTalkWebhookURL") private var dingTalkWebhookURL: String = ""
    @AppStorage("DingTalkSecret") private var dingTalkSecretStore: String = ""
    @AppStorage("DingTalkKeyword") private var dingTalkKeywordStore: String = ""
    @AppStorage("DingTalkAtMobiles") private var dingTalkAtMobilesStore: String = ""
    @AppStorage("DingTalkFrequencyDays") private var dingTalkFrequencyDays: Int = 1
    @AppStorage("DingTalkLastAutoSentTimestamp") private var dingTalkLastAutoSentTimestamp: Double = 0
    @State private var showDingTalkConfig = false
    @State private var isSendingDingTalk = false
    @State private var showDingTalkAlert = false
    @State private var dingTalkAlertMessage: String? = nil
    @State private var dingTalkTimer: Timer?
    
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
    
    private var starredCertificatesList: [X509Certificate] {
        let starred = getUserStarredIDs()
        guard !starred.isEmpty else { return [] }
        return certificates.filter { starred.contains(certificateID($0)) }
    }
    
    private var sanitizedDingTalkWebhook: String {
        dingTalkWebhookURL.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    private var sanitizedDingTalkSecret: String {
        dingTalkSecretStore.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    private var sanitizedDingTalkKeyword: String {
        dingTalkKeywordStore.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    private var dingTalkAtMobiles: [String] {
        dingTalkAtMobilesStore
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
    
    private var hasValidDingTalkWebhook: Bool {
        guard let url = URL(string: sanitizedDingTalkWebhook) else { return false }
        return !sanitizedDingTalkWebhook.isEmpty && (url.scheme == "http" || url.scheme == "https")
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
                
                Divider().frame(height: 20)
                
                Button("钉钉配置") {
                    showDingTalkConfig = true
                }
                
                Button("钉钉提醒关注") {
                    sendDingTalkReminder(for: starredCertificatesList, reason: .manualAll)
                }
                .disabled(starredCertificatesList.isEmpty || !hasValidDingTalkWebhook || isSendingDingTalk)
                .help("立即把全部关注证书通过钉钉机器人提醒")
            }
            .padding(12)

            Divider()

            // 内容
            VStack(spacing: 0) {
                if showUntrustedWarning { warningBanner }

                // 列表和详情
                HSplitView {
                    certificateListPane
                        .frame(minWidth: 360)
                    certificateDetailPane
                        .frame(minWidth: 320)
                }
            }
        }
        .frame(minWidth: 900, minHeight: 650)
        .onAppear {
            loadData()
            scheduleDingTalkTimer()
        }
        .onDisappear {
            dingTalkTimer?.invalidate()
        }
        .sheet(isPresented: $showDingTalkConfig) {
            DingTalkConfigView(
                webhookURL: $dingTalkWebhookURL,
                secret: $dingTalkSecretStore,
                keyword: $dingTalkKeywordStore,
                atMobiles: $dingTalkAtMobilesStore,
                frequencyDays: Binding(
                    get: { max(1, dingTalkFrequencyDays) },
                    set: { dingTalkFrequencyDays = max(1, $0) }
                ),
                lastAutoTimestamp: $dingTalkLastAutoSentTimestamp
            )
        }
        .alert("钉钉提醒", isPresented: $showDingTalkAlert) {
            Button("好的", role: .cancel) { }
        } message: {
            Text(dingTalkAlertMessage ?? "")
        }
    }
    
    private var certificateListPane: some View {
        GeometryReader { geo in
            let baseNameWidth = CGFloat(colNameWStore)
            let staticColumnsWidth = colFavW + colExpiryW + operationColumnWidth
            let baseWidth = staticColumnsWidth + baseNameWidth
            let delta = geo.size.width - baseWidth
            let maxNameWidth = min(580, baseNameWidth + delta)
            let effectiveNameWidth = min(maxNameWidth, max(120, baseNameWidth + delta))
            let totalWidth = max(staticColumnsWidth + effectiveNameWidth, geo.size.width)
            ScrollView([.vertical, .horizontal]) {
                VStack(spacing: 0) {
                    headerRow(width: totalWidth, nameWidth: effectiveNameWidth)
                    Divider()
                        .frame(width: totalWidth)
                    ForEach(Array(displayedCertificates.enumerated()), id: \.offset) { idx, cert in
                        let isSelected = selectedIndex == idx
                        X509CertificateRow(
                            certificate: cert,
                            isUserTrusted: getUserTrustedIDs().contains(certificateID(cert)),
                            isFavorite: favoriteBinding(for: cert),
                            hasPrivateKey: nameFor(cert).map { privateKeyNames.contains($0) } ?? false,
                            favWidth: colFavW,
                            nameWidth: effectiveNameWidth,
                            expiryWidth: colExpiryW,
                            dingTalkEnabled: hasValidDingTalkWebhook && !isSendingDingTalk,
                            manualReminderAction: {
                                sendDingTalkReminder(for: [cert], reason: .manualSingle(nameFor(cert) ?? "未命名证书"))
                            },
                            operationWidth: operationColumnWidth
                        )
                        .background(isSelected ? Color.accentColor.opacity(0.15) : Color.clear)
                        .contentShape(Rectangle())
                        .onTapGesture { selectedIndex = idx }
                        .contextMenu { certificateContextMenu(cert) }
                        Divider()
                            .frame(width: totalWidth)
                    }
                }
                .frame(width: totalWidth, alignment: .leading)
                .frame(minHeight: geo.size.height, alignment: .topLeading)
            }
            .scrollIndicators(.visible)
        }
        .background(Color(NSColor.windowBackgroundColor))
    }
    
    @ViewBuilder
    private func headerRow(width: CGFloat, nameWidth: CGFloat) -> some View {
        HStack(spacing: 0) {
            headerFavoritesTriStateView()
                .frame(width: colFavW, alignment: .center)
            columnResizer(left: bindFavW, right: bindNameW)
            headerSortableLabel(title: "名称", isActive: sortOption.isName, ascending: sortOption.isAscendingForName) { toggleSort(for: .name) }
                .frame(width: nameWidth, alignment: .leading)
            columnResizer(left: bindNameW, right: bindExpiryW)
            headerSortableLabel(title: "过期时间", isActive: sortOption.isExpiry, ascending: sortOption.isAscendingForExpiry) { toggleSort(for: .expiry) }
                .frame(width: colExpiryW, alignment: .leading)
            Text("操作")
                .frame(width: operationColumnWidth, alignment: .center)
                .foregroundColor(.secondary)
        }
        .font(.headline)
        .padding(.horizontal, 0)
        .padding(.vertical, 8)
        .background(Color.gray.opacity(0.1))
        .frame(width: width, alignment: .leading)
    }
    
    private var certificateDetailPane: some View {
        Group {
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
    
    // 钉钉提醒相关
    private func scheduleDingTalkTimer() {
        dingTalkTimer?.invalidate()
        dingTalkTimer = Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { _ in
            maybeSendAutoDingTalk()
        }
        if let timer = dingTalkTimer {
            RunLoop.main.add(timer, forMode: .common)
        }
        maybeSendAutoDingTalk()
    }
    
    private func maybeSendAutoDingTalk() {
        guard hasValidDingTalkWebhook else { return }
        guard dingTalkFrequencyDays > 0 else { return }
        if isSendingDingTalk { return }
        let lastSendDate = dingTalkLastAutoSentTimestamp > 0 ? Date(timeIntervalSince1970: dingTalkLastAutoSentTimestamp) : nil
        if let lastSendDate,
           let next = Calendar.current.date(byAdding: .day, value: dingTalkFrequencyDays, to: lastSendDate),
           Date() < next {
            return
        }
        let starred = starredCertificatesList
        guard !starred.isEmpty else { return }
        sendDingTalkReminder(for: starred, reason: .auto)
    }
    
    private func sendDingTalkReminder(for certificates: [X509Certificate], reason: DingTalkReminderReason) {
        guard hasValidDingTalkWebhook else {
            presentDingTalkAlert("请先在“钉钉配置”中填写有效的Webhook地址。")
            return
        }
        guard !certificates.isEmpty else {
            presentDingTalkAlert("没有可提醒的证书。")
            return
        }
        guard let url = dingTalkRequestURL() else {
            presentDingTalkAlert("Webhook地址无效。")
            return
        }
        
        let payload = DingTalkTextPayload(
            content: buildDingTalkMessage(for: certificates, reason: reason),
            atMobiles: dingTalkAtMobiles
        )
        guard let body = try? JSONEncoder().encode(payload) else {
            presentDingTalkAlert("无法编码钉钉请求。")
            return
        }
        
        isSendingDingTalk = true
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        
        Task {
            defer { isSendingDingTalk = false }
            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                try await handleDingTalkResponse(data: data, response: response, reason: reason)
            } catch {
                presentDingTalkAlert("发送失败：\(error.localizedDescription)")
            }
        }
    }
    
    private func buildDingTalkMessage(for certificates: [X509Certificate], reason: DingTalkReminderReason) -> String {
        let header: String
        switch reason {
        case .auto:
            header = "自动关注证书提醒"
        case .manualAll:
            header = "关注证书手动提醒"
        case .manualSingle(let name):
            header = "证书提醒：\(name)"
        }
        
        var lines: [String] = []
        if !sanitizedDingTalkKeyword.isEmpty {
            lines.append(sanitizedDingTalkKeyword)
        }
        lines.append(header)
        let shouldUseBullets = !(certificates.count == 1 && reason.isSingleCertificate)
        for cert in certificates {
            let name = cert.subjectCommonNames?.first ?? "-"
            let issuer = cert.issuerOrganizationName ?? "-"
            let expiry = cert.formattedExpiry
            let days = cert.daysUntilExpiry.days
            let status: String
            if cert.isExpired {
                status = "已过期"
            } else if days >= 0 {
                status = "剩余\(days)天"
            } else {
                status = "即将过期"
            }
            let prefix = shouldUseBullets ? "• " : ""
            lines.append("\(prefix)\(name) (\(issuer))")
            lines.append("到期: \(expiry) | \(status)")
        }
        if !dingTalkAtMobiles.isEmpty {
            let mentionLine = dingTalkAtMobiles.map { "@\($0)" }.joined(separator: " ")
            lines.append(mentionLine)
        }
        return lines.joined(separator: "\n")
    }
    
    private func presentDingTalkAlert(_ message: String) {
        dingTalkAlertMessage = message
        showDingTalkAlert = true
    }
    
    private func dingTalkRequestURL() -> URL? {
        guard var components = URLComponents(string: sanitizedDingTalkWebhook) else { return nil }
        var queryItems = components.queryItems ?? []
        let secret = sanitizedDingTalkSecret
        if !secret.isEmpty {
            let timestamp = Int(Date().timeIntervalSince1970 * 1000)
            let stringToSign = "\(timestamp)\n\(secret)"
            let key = SymmetricKey(data: Data(secret.utf8))
            let signature = HMAC<SHA256>.authenticationCode(for: Data(stringToSign.utf8), using: key)
            let signData = Data(signature)
            let base64 = signData.base64EncodedString()
            let encodedSign = base64.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? base64
            queryItems.append(URLQueryItem(name: "timestamp", value: "\(timestamp)"))
            queryItems.append(URLQueryItem(name: "sign", value: encodedSign))
        }
        if !queryItems.isEmpty {
            components.percentEncodedQueryItems = queryItems
        }
        return components.url
    }

    private func handleDingTalkResponse(data: Data, response: URLResponse, reason: DingTalkReminderReason) async throws {
        guard let http = response as? HTTPURLResponse else {
            presentDingTalkAlert("钉钉返回异常：无效响应。")
            return
        }
        guard http.statusCode == 200 else {
            presentDingTalkAlert("钉钉返回异常，状态码：\(http.statusCode)。")
            return
        }
        if let result = try? JSONDecoder().decode(DingTalkRobotResponse.self, from: data) {
            if result.errcode == 0 {
                if case .auto = reason {
                    dingTalkLastAutoSentTimestamp = Date().timeIntervalSince1970
                }
                presentDingTalkAlert("钉钉提醒发送成功。")
            } else {
                let errMsg = result.errmsg ?? "未知错误"
                presentDingTalkAlert("钉钉返回错误：\(errMsg)")
            }
        } else {
            let raw = String(data: data, encoding: .utf8) ?? "未知内容"
            presentDingTalkAlert("钉钉返回无法解析：\(raw)")
        }
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
    let dingTalkEnabled: Bool
    let manualReminderAction: () -> Void
    let operationWidth: CGFloat

    var body: some View {
        let showExpiryWarning = certificate.isExpired || certificate.isExpiringSoon
        return HStack(spacing: 8) {
            // 关注复选框
            Toggle("", isOn: $isFavorite)
                .toggleStyle(.checkbox)
                .labelsHidden()
                .frame(width: favWidth, alignment: .center)

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

            Button(action: manualReminderAction) {
                Image(systemName: "bell.badge")
            }
            .buttonStyle(BorderlessButtonStyle())
            .disabled(!dingTalkEnabled)
            .foregroundColor(dingTalkEnabled ? .accentColor : .secondary)
            .help(dingTalkEnabled ? "发送该证书的钉钉提醒" : "请先配置钉钉Webhook")
            .frame(width: operationWidth, alignment: .center)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 0)
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

private enum DingTalkReminderReason {
    case auto
    case manualAll
    case manualSingle(String)
    
    var isSingleCertificate: Bool {
        if case .manualSingle = self { return true }
        return false
    }
}

private struct DingTalkTextPayload: Encodable {
    let msgtype = "text"
    let text: TextBody
    let at: AtBody?
    
    struct TextBody: Encodable {
        let content: String
    }
    
    struct AtBody: Encodable {
        let atMobiles: [String]
        let isAtAll: Bool
    }
    
    init(content: String, atMobiles: [String]) {
        self.text = TextBody(content: content)
        if atMobiles.isEmpty {
            self.at = nil
        } else {
            self.at = AtBody(atMobiles: atMobiles, isAtAll: false)
        }
    }
}

private struct DingTalkRobotResponse: Decodable {
    let errcode: Int
    let errmsg: String?
}

struct DingTalkConfigView: View {
    @Binding var webhookURL: String
    @Binding var secret: String
    @Binding var keyword: String
    @Binding var atMobiles: String
    @Binding var frequencyDays: Int
    @Binding var lastAutoTimestamp: Double
    @Environment(\.dismiss) private var dismiss
    
    private var lastAutoDescription: String {
        guard lastAutoTimestamp > 0 else { return "尚未自动发送" }
        let date = Date(timeIntervalSince1970: lastAutoTimestamp)
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("钉钉提醒配置")
                .font(.title2)
                .bold()
            
            TextField("Webhook 地址", text: $webhookURL)
                .textFieldStyle(RoundedBorderTextFieldStyle())
            
            SecureField("加签 Secret（若未开启加签可留空）", text: $secret)
                .textFieldStyle(RoundedBorderTextFieldStyle())
            
            TextField("关键词（若配置了关键词，请填写以确保消息包含）", text: $keyword)
                .textFieldStyle(RoundedBorderTextFieldStyle())
            
            TextField("提醒指定手机号（多个用逗号分隔）", text: $atMobiles)
                .textFieldStyle(RoundedBorderTextFieldStyle())

            Stepper(value: $frequencyDays, in: 1...30) {
                Text("自动发送频率：每 \(frequencyDays) 天")
            }
            
            Text("上次自动发送：\(lastAutoDescription)")
                .font(.footnote)
                .foregroundColor(.secondary)
            
            Spacer()
            
            HStack {
                Spacer()
                Button("完成") {
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
        .frame(minWidth: 420, minHeight: 260)
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
