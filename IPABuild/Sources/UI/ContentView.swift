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
import AppKit

private enum DingTalkReminderReason {
    case auto
    case manualAll
    case manualSingle
    
    var isSingleCertificate: Bool {
        if case .manualSingle = self { return true }
        return false
    }
    
    var header: String {
            return "证书有效期提醒:"
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

final class DingTalkReminderManager {
    static let shared = DingTalkReminderManager()
    private var timer: DispatchSourceTimer?
    private let queue = DispatchQueue(label: "com.ipabuild.dingtalk.scheduler", qos: .background)
    private var isSending = false
    
    private init() {}
    
    func start() {
        guard timer == nil else { return }
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + 5, repeating: .seconds(60), leeway: .seconds(10))
        timer.setEventHandler { [weak self] in
            self?.performAutoReminder()
        }
        timer.resume()
        self.timer = timer
        queue.async { [weak self] in
            self?.performAutoReminder()
        }
    }
    
    private func performAutoReminder() {
        let defaults = UserDefaults.standard
        guard let webhook = defaults.string(forKey: "DingTalkWebhookURL")?.trimmingCharacters(in: .whitespacesAndNewlines),
              !webhook.isEmpty else { return }
        let frequency = defaults.integer(forKey: "DingTalkFrequencyDays")
        guard frequency > 0 else { return }
        let sendHour = defaults.integer(forKey: "DingTalkSendHour")
        let lastTimestamp = defaults.double(forKey: "DingTalkLastAutoSentTimestamp")
        let now = Date()
        guard shouldSend(now: now, frequencyDays: frequency, targetHour: sendHour, lastTimestamp: lastTimestamp) else {
            return
        }
        
        let starredIDs = Set(defaults.string(forKey: "UserStarredCertIDs")?
            .split(separator: ",")
            .map { String($0) } ?? [])
        guard !starredIDs.isEmpty else { return }
        
        guard let certificates = X509Certificate.findCertificates(in: .login) else { return }
        let starredCertificates = certificates.filter { starredIDs.contains(certificateID($0)) }
        guard !starredCertificates.isEmpty else { return }
        
        let secret = defaults.string(forKey: "DingTalkSecret") ?? ""
        let keyword = defaults.string(forKey: "DingTalkKeyword") ?? ""
        let atMobilesString = defaults.string(forKey: "DingTalkAtMobiles") ?? ""
        let atMobiles = atMobilesString.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        
        sendDingTalkReminder(
            webhook: webhook,
            secret: secret,
            keyword: keyword,
            atMobiles: atMobiles,
            certificates: starredCertificates,
            reason: .auto
        ) { success in
            if success {
                defaults.set(Date().timeIntervalSince1970, forKey: "DingTalkLastAutoSentTimestamp")
            }
        }
    }
    
    private func shouldSend(now: Date, frequencyDays: Int, targetHour: Int, lastTimestamp: Double) -> Bool {
        let hour = min(23, max(0, targetHour))
        let calendar = Calendar.current
        if lastTimestamp <= 0 {
            let currentHour = calendar.component(.hour, from: now)
            return currentHour >= hour
        }
        guard let nextBase = calendar.date(byAdding: .day, value: frequencyDays, to: Date(timeIntervalSince1970: lastTimestamp)) else {
            return true
        }
        var components = calendar.dateComponents([.year, .month, .day], from: nextBase)
        components.hour = hour
        components.minute = 0
        components.second = 0
        guard let targetDate = calendar.date(from: components) else { return true }
        return now >= targetDate
    }
    
    private func sendDingTalkReminder(
        webhook: String,
        secret: String,
        keyword: String,
        atMobiles: [String],
        certificates: [X509Certificate],
        reason: DingTalkReminderReason,
        completion: @escaping (Bool) -> Void
    ) {
        guard !isSending else {
            completion(false)
            return
        }
        guard let url = makeRequestURL(from: webhook, secret: secret) else {
            completion(false)
            return
        }
        let message = buildMessage(for: certificates, reason: reason, keyword: keyword, atMobiles: atMobiles)
        let payload = DingTalkTextPayload(content: message, atMobiles: atMobiles)
        guard let body = try? JSONEncoder().encode(payload) else {
            completion(false)
            return
        }
        isSending = true
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            self.isSending = false
            if let error = error {
                NSLog("DingTalk auto reminder failed: \(error.localizedDescription)")
                completion(false)
                return
            }
            guard
                let http = response as? HTTPURLResponse,
                http.statusCode == 200,
                let data = data,
                let result = try? JSONDecoder().decode(DingTalkRobotResponse.self, from: data),
                result.errcode == 0
            else {
                NSLog("DingTalk auto reminder failed: invalid response")
                completion(false)
                return
            }
            completion(true)
        }.resume()
    }
    
    private func makeRequestURL(from webhook: String, secret: String) -> URL? {
        guard var components = URLComponents(string: webhook) else { return nil }
        guard !secret.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return components.url
        }
        let timestamp = Int(Date().timeIntervalSince1970 * 1000)
        let stringToSign = "\(timestamp)\n\(secret)"
        guard let secretData = secret.data(using: .utf8) else { return components.url }
        let key = SymmetricKey(data: secretData)
        let signature = HMAC<SHA256>.authenticationCode(for: Data(stringToSign.utf8), using: key)
        let signData = Data(signature).base64EncodedString()
        let encodedSign = signData.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? signData
        var items = components.queryItems ?? []
        items.append(URLQueryItem(name: "timestamp", value: "\(timestamp)"))
        items.append(URLQueryItem(name: "sign", value: encodedSign))
        components.queryItems = items
        return components.url
    }
    
    private func buildMessage(
        for certificates: [X509Certificate],
        reason: DingTalkReminderReason,
        keyword: String,
        atMobiles: [String]
    ) -> String {
        let header: String = reason.header
        var lines: [String] = []
        if !keyword.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            lines.append(keyword)
        }
        lines.append(header)
        for cert in certificates {
            let name = cert.subjectCommonNames?.first ?? "-"
            let issuer = cert.issuerOrganizationName ?? "-"
            let expiry = cert.formattedExpiry
            let days = cert.daysUntilExpiry.days
            let status: String
            if cert.isExpired {
                status = "⚠️ 已过期"
            } else if days >= 0 {
                status = "剩余\(days)天"
            } else {
                status = "即将过期"
            }
            lines.append("• \(name) (\(issuer))")
            lines.append("到期: \(expiry) | \(status)")
        }
        if !atMobiles.isEmpty {
            lines.append(atMobiles.map { "@\($0)" }.joined(separator: " "))
        }
        return lines.joined(separator: "\n")
    }
    
    private func certificateID(_ cert: X509Certificate) -> String {
        if let sn = cert.serialNumberHex, !sn.isEmpty {
            return sn
        }
        let subject = cert.subjectCommonNames?.first ?? "-"
        let issuer = cert.issuerOrganizationName ?? "-"
        let expiry = cert.notAfter?.timeIntervalSince1970 ?? 0
        return "\(subject)|\(issuer)|\(expiry)"
    }
}
import CryptoKit

// 主视图
struct ContentView: View {
    @State private var certificates: [X509Certificate] = []
    @State private var privateKeyNames: Set<String> = []
    @State private var selectedIndex: Int? = nil
    @State private var showUntrustedWarning = true
    @State private var untrustedX509CertificateName = "Apple Push Services: com.dev.talk"

    // 过滤
    @State private var searchText: String = ""
    @State private var filterOption: CertificateFilterOption = .all
    @AppStorage("CertificateFilterOption") private var storedFilterOptionRaw: String = CertificateFilterOption.all.rawValue
    // 列宽（可拖拽调整，持久化）
    @AppStorage("ColFavW") private var colFavWStore: Double = 110
    @AppStorage("ColNameW") private var colNameWStore: Double = 360
    @AppStorage("ColExpiryW") private var colExpiryWStore: Double = 180
    private var colFavW: CGFloat { get { CGFloat(colFavWStore) } set { colFavWStore = Double(max(60, newValue)) } }
    private var colNameW: CGFloat { get { CGFloat(colNameWStore) } set { colNameWStore = Double(max(120, newValue)) } }
    private var colExpiryW: CGFloat { get { CGFloat(colExpiryWStore) } set { colExpiryWStore = Double(max(140, newValue)) } }
    private let operationColumnWidth: CGFloat = 80
    private var bindFavW: Binding<CGFloat> { Binding(get: { CGFloat(colFavWStore) }, set: { colFavWStore = Double(max(60, $0)) }) }
    private var bindNameW: Binding<CGFloat> { Binding(get: { CGFloat(colNameWStore) }, set: { colNameWStore = Double(max(120, $0)) }) }
    private var bindExpiryW: Binding<CGFloat> { Binding(get: { CGFloat(colExpiryWStore) }, set: { colExpiryWStore = Double(max(140, $0)) }) }
    
    // 钉钉自动提醒配置
    @AppStorage("DingTalkWebhookURL") private var dingTalkWebhookURL: String = ""
    @AppStorage("DingTalkSecret") private var dingTalkSecretStore: String = ""
    @AppStorage("DingTalkKeyword") private var dingTalkKeywordStore: String = ""
    @AppStorage("DingTalkAtMobiles") private var dingTalkAtMobilesStore: String = ""
    @AppStorage("DingTalkFrequencyDays") private var dingTalkFrequencyDays: Int = 1
    @AppStorage("DingTalkSendHour") private var dingTalkSendHour: Int = 9
    @AppStorage("LaunchAtLoginEnabled") private var launchAtLoginEnabled = false
    @AppStorage("LaunchAtLoginAutoEnabled") private var launchAtLoginAutoEnabled = false
    @AppStorage("DingTalkLastAutoSentTimestamp") private var dingTalkLastAutoSentTimestamp: Double = 0
    @State private var showDingTalkConfig = false
    @State private var isSendingDingTalk = false
    @State private var showDingTalkAlert = false
    @State private var dingTalkAlertMessage: String? = nil
    @State private var suppressLaunchStateUpdate = false
    @State private var currentManualSendingID: String? = nil
    @State private var isGlobalReminderInProgress = false
    
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
        switch filterOption {
        case .all:
            break
        case .validOnly:
            list = list.filter { !$0.isExpired }
        case .starredOnly:
            let starred = getUserStarredIDs()
            list = list.filter { starred.contains(certificateID($0)) }
        case .withPrivateKey:
            list = list.filter { nameFor($0).map { privateKeyNames.contains($0) } ?? false }
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
                Picker(selection: $filterOption, label: Image(systemName: "line.3.horizontal.decrease.circle")) {
                    ForEach(CertificateFilterOption.allCases) { option in
                        Text(option.displayName).tag(option)
                    }
                }
                .pickerStyle(MenuPickerStyle())
                .frame(width: 220, alignment: .leading)
                .help("点击选择要过滤的证书范围")

                // 搜索框
                TextField("搜索名称/签发者", text: $searchText)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .frame(maxWidth: 260)

                Spacer()

                Toggle("开机启动", isOn: $launchAtLoginEnabled)
                    .toggleStyle(SwitchToggleStyle())
                    .frame(maxWidth: 140)
                    .help("启动 macOS 时自动打开证书管理")

                Button(action: refreshX509Certificates) {
                    Image(systemName: "arrow.clockwise")
                }
                .help("刷新证书列表")
                
                Divider().frame(height: 20)
                
                Button("配置") {
                    showDingTalkConfig = true
                }
                
                Button("立即提醒") {
                    triggerManualAllReminder()
                }
                .disabled(starredCertificatesList.isEmpty || !hasValidDingTalkWebhook || isSendingDingTalk || isGlobalReminderInProgress || currentManualSendingID != nil)
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
                        .frame(minWidth: 160)
                }
            }
        }
        .frame(minWidth: 900, minHeight: 650)
        .onAppear {
            loadData()
            filterOption = CertificateFilterOption(rawValue: storedFilterOptionRaw) ?? .all
            refreshLaunchAtLoginState()
            ensureDefaultLaunchAtLoginEnabled()
        }
        .onChange(of: filterOption) { newValue in
            storedFilterOptionRaw = newValue.rawValue
        }
        .onChange(of: launchAtLoginEnabled) { newValue in
            if suppressLaunchStateUpdate {
                suppressLaunchStateUpdate = false
            } else {
                applyLaunchAtLoginState(enabled: newValue, showAlertOnUnsupported: true)
            }
        }
        .sheet(isPresented: $showDingTalkConfig) {
            DingTalkConfigView(
                webhookURL: $dingTalkWebhookURL,
                secret: $dingTalkSecretStore,
                keyword: $dingTalkKeywordStore,
                atMobiles: $dingTalkAtMobilesStore,
                sendHour: Binding(
                    get: { dingTalkSendHour },
                    set: { dingTalkSendHour = min(23, max(0, $0)) }
                ),
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
                                        dingTalkEnabled: isRowReminderEnabled(for: cert),
                                        manualReminderAction: {
                                            sendManualReminder(for: cert)
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
                        Text("订阅自动提醒")
                            .font(.system(size: 12, weight: .semibold))
                            .frame(width: colFavW, alignment: .center)
                        columnResizer(left: bindFavW, right: bindNameW)
                        Text("名称")
                            .font(.system(size: 12, weight: .semibold))
                            .frame(width: nameWidth, alignment: .leading)
            columnResizer(left: bindNameW, right: bindExpiryW)
            Text("过期时间")
                .font(.system(size: 12, weight: .semibold))
                .frame(width: colExpiryW, alignment: .leading)
            Text("操作")
                .frame(width: operationColumnWidth, alignment: .center)
                .foregroundColor(.secondary)
            Spacer(minLength: 0)
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
                    Image(systemName: "signature")
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

    private func isRowReminderEnabled(for certificate: X509Certificate) -> Bool {
        guard hasValidDingTalkWebhook else { return false }
        if isGlobalReminderInProgress { return false }
        if let sendingID = currentManualSendingID {
            return certificateID(certificate) != sendingID
        }
        return !isSendingDingTalk
    }

    private func sendManualReminder(for certificate: X509Certificate) {
        let id = certificateID(certificate)
        currentManualSendingID = id
        sendDingTalkReminder(for: [certificate], reason: .manualSingle) {
            currentManualSendingID = nil
        }
    }

    private func triggerManualAllReminder() {
        guard !starredCertificatesList.isEmpty else { return }
        isGlobalReminderInProgress = true
        sendDingTalkReminder(for: starredCertificatesList, reason: .manualAll) {
            isGlobalReminderInProgress = false
        }
    }
    
    private func sendDingTalkReminder(for certificates: [X509Certificate], reason: DingTalkReminderReason, completion: (() -> Void)? = nil) {
        guard !isSendingDingTalk else {
            completion?()
            return
        }
        guard hasValidDingTalkWebhook else {
            presentDingTalkAlert("请先在“钉钉配置”中填写有效的Webhook地址。")
            completion?()
            return
        }
        guard !certificates.isEmpty else {
            presentDingTalkAlert("没有可提醒的证书。")
            completion?()
            return
        }
        guard let url = dingTalkRequestURL() else {
            presentDingTalkAlert("Webhook地址无效。")
            completion?()
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
            defer {
                isSendingDingTalk = false
                completion?()
            }
            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                try await handleDingTalkResponse(data: data, response: response, reason: reason)
            } catch {
                presentDingTalkAlert("发送失败：\(error.localizedDescription)")
            }
        }
    }
    
    private func buildDingTalkMessage(for certificates: [X509Certificate], reason: DingTalkReminderReason) -> String {
        let header: String = reason.header
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
                status = "⚠️ 已过期"
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
    
    private func presentGeneralAlert(_ title: String, message: String) {
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = title
            alert.informativeText = message
            alert.alertStyle = .warning
            alert.addButton(withTitle: "好的")
            let targetWindow = NSApp.keyWindow?.attachedSheet ?? NSApp.keyWindow
            if let window = targetWindow {
                alert.beginSheetModal(for: window, completionHandler: nil)
            } else {
                alert.runModal()
            }
        }
    }
    
    private func refreshLaunchAtLoginState() {
        guard let bundleID = Bundle.main.bundleIdentifier else { return }
        let actual = LaunchAtLoginManager.shared.isEnabled(bundleIdentifier: bundleID)
        suppressLaunchStateUpdate = true
        launchAtLoginEnabled = actual
    }
    
    private func ensureDefaultLaunchAtLoginEnabled() {
        if launchAtLoginAutoEnabled { return }
        guard let bundleID = Bundle.main.bundleIdentifier else { return }
        let appPath = Bundle.main.bundlePath
        if appPath.contains("DerivedData") { return }
        guard let executablePath = Bundle.main.executableURL?.path else { return }
        do {
            try LaunchAtLoginManager.shared.setEnabled(true, bundleIdentifier: bundleID, executablePath: executablePath)
            launchAtLoginAutoEnabled = true
            suppressLaunchStateUpdate = true
            launchAtLoginEnabled = true
        } catch {
            // 自动开机启动失败不会打断流程，用户可在配置中手动设置。
        }
    }

    private func applyLaunchAtLoginState(enabled: Bool, showAlertOnUnsupported: Bool) {
        guard let bundleID = Bundle.main.bundleIdentifier else {
            if showAlertOnUnsupported {
                presentGeneralAlert("无法配置", message: "未能获取应用标识。")
            }
            suppressLaunchStateUpdate = true
            launchAtLoginEnabled = false
            return
        }
        let appPath = Bundle.main.bundlePath
        if enabled && appPath.contains("DerivedData") {
            if showAlertOnUnsupported {
                presentGeneralAlert("无法配置", message: "请先将应用拖到 /Applications 或其它永久路径后再启用开机启动。")
            }
            suppressLaunchStateUpdate = true
            launchAtLoginEnabled = false
            return
        }
        guard let executablePath = Bundle.main.executableURL?.path else {
            if showAlertOnUnsupported {
                presentGeneralAlert("无法配置", message: "未找到可执行文件路径。")
            }
            suppressLaunchStateUpdate = true
            launchAtLoginEnabled = false
            return
        }
        do {
            try LaunchAtLoginManager.shared.setEnabled(enabled, bundleIdentifier: bundleID, executablePath: executablePath)
            if enabled {
                launchAtLoginAutoEnabled = true
            }
        } catch {
            if showAlertOnUnsupported {
                let description = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                presentGeneralAlert("配置失败", message: "无法更新开机启动：\(description)")
            }
            suppressLaunchStateUpdate = true
            launchAtLoginEnabled = !enabled
        }
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
}

enum CertificateFilterOption: String, CaseIterable, Identifiable {
    case all
    case validOnly
    case starredOnly
    case withPrivateKey

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .all: return "所有证书"
        case .validOnly: return "有效的证书"
        case .starredOnly: return "已订阅的证书"
        case .withPrivateKey: return "包含私钥的证书"
        }
    }
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
        return HStack(spacing: 8) {
            // 关注复选框
            Toggle("", isOn: $isFavorite)
                .toggleStyle(.switch)
                .labelsHidden()
                .controlSize(.small)
                .frame(width: favWidth, alignment: .center)

            // 名称 + 徽章
            HStack(spacing: 8) {
                Image(systemName: "certificate")
                    .font(.system(size: 13))
                    .foregroundColor(.accentColor)
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
            Text(expirySummaryText(for: certificate))
                .font(.system(size: 13))
                .foregroundColor(expiryColor(for: certificate))
            .frame(width: expiryWidth, alignment: .leading)

            Button("立即提醒", action: manualReminderAction)
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            .disabled(!dingTalkEnabled)
            .foregroundColor(dingTalkEnabled ? .accentColor : .secondary)
            .help(dingTalkEnabled ? "立即发送该证书的钉钉提醒" : "请先配置钉钉Webhook")
            .frame(width: operationWidth, alignment: .center)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 0)
        .padding(.vertical, 8)
        .background(Color.clear)
        .contentShape(Rectangle())
    }
}

private func expirySummaryText(for certificate: X509Certificate) -> String {
    let base = certificate.formattedExpiry
    if certificate.isExpired {
        return "\(base) · 已过期"
    }
    let remainingDays = max(0, certificate.daysUntilExpiry.days)
    let remainingHours = max(0, certificate.daysUntilExpiry.hours)
    return "\(base) · 剩余\(remainingDays)天\(remainingHours)小时"
}

private func expiryColor(for certificate: X509Certificate) -> Color {
    (certificate.isExpired || certificate.isExpiringSoon) ? .red : .primary
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
                let prefix = certificate.isExpired ? "已过期: " : "剩余: "
                let remainingDays = abs(certificate.daysUntilExpiry.days)
                let remainingHours = abs(certificate.daysUntilExpiry.hours)
                let remainingText =
                    Text(prefix)
                        .font(.system(size: 12))
                + Text("\(remainingDays)")
                        .font(.system(size: 20, weight: .bold))
                + Text(" 天 ")
                        .font(.system(size: 12))
                + Text("\(remainingHours)")
                        .font(.system(size: 20, weight: .bold))
                + Text(" 小时")
                        .font(.system(size: 12))
                remainingText
                    .foregroundColor(expiryColor(for: certificate))
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

struct DingTalkConfigView: View {
    @Binding var webhookURL: String
    @Binding var secret: String
    @Binding var keyword: String
    @Binding var atMobiles: String
    @Binding var sendHour: Int
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
    
    private var nextReminderDescription: String {
        guard frequencyDays > 0 else { return "未配置自动发送频率" }
        let calendar = Calendar.current
        let targetHour = min(23, max(0, sendHour))
        let baseDate: Date
        if lastAutoTimestamp > 0 {
            baseDate = Date(timeIntervalSince1970: lastAutoTimestamp)
        } else {
            baseDate = Date()
        }
        guard let nextBase = calendar.date(byAdding: .day, value: frequencyDays, to: baseDate) else {
            return "无法计算"
        }
        var components = calendar.dateComponents([.year, .month, .day], from: nextBase)
        components.hour = targetHour
        components.minute = 0
        components.second = 0
        guard let nextScheduled = calendar.date(from: components) else {
            return "无法计算"
        }
        let now = Date()
        if nextScheduled <= now {
            return "即将发送"
        }
        let remaining = nextScheduled.timeIntervalSince(now)
        let days = Int(remaining) / 86_400
        let hours = (Int(remaining) % 86_400) / 3_600
        let minutes = (Int(remaining) % 3_600) / 60
        let seconds = Int(remaining) % 60
        return "剩余 \(days) 天 \(String(format: "%02d:%02d:%02d", hours, minutes, seconds))"
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("配置")
                .font(.title2)
                .bold()
            
            GroupBox(label: Text("钉钉配置").font(.headline)) {
                VStack(alignment: .leading, spacing: 12) {
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
                    
                    Stepper(value: $sendHour, in: 0...23) {
                        Text("发送时间：每天 \(sendHour) 点")
                    }
                    
                    Text("上次自动发送：\(lastAutoDescription)")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                    
                    Text("距离下一次提醒：\(nextReminderDescription)")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }
            }
            
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
        .frame(minWidth: 460, minHeight: 360)
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
