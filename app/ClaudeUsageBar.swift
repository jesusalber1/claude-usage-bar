import SwiftUI
import AppKit

// MARK: - Entry Point

@main
struct Main {
    static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }
}

// MARK: - App Delegate

class FloatingPanel: NSPanel {
    override var canBecomeKey: Bool { true }

    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        level = .statusBar
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isMovableByWindowBackground = false
        isReleasedWhenClosed = false
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem!
    var panel: FloatingPanel!
    let usageManager = UsageManager()
    var eventMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem.button {
            updateStatusIcon()
            button.action = #selector(togglePanel)
            button.target = self
        }

        let hostingView = NSHostingView(
            rootView: UsageView(manager: usageManager, onUpdate: { [weak self] in
                self?.updateStatusIcon()
            })
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(.regularMaterial)
                    .shadow(color: .black.opacity(0.15), radius: 8, y: 4)
            )
            .clipShape(RoundedRectangle(cornerRadius: 12))
        )

        panel = FloatingPanel(contentRect: NSRect(x: 0, y: 0, width: 340, height: 400))
        panel.contentView = hostingView

        usageManager.fetchUsage()
        scheduleBackgroundRefresh()
    }

    func scheduleBackgroundRefresh() {
        let interval = 900 + Double.random(in: 0...300) // 15 min + rand 0-5 min
        Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { [weak self] _ in
            self?.usageManager.fetchUsage()
            self?.updateStatusIcon()
            self?.scheduleBackgroundRefresh()
        }
    }

    func updateStatusIcon() {
        guard let button = statusItem.button else { return }
        let pct = Int(usageManager.sessionPercent)
        let color: NSColor
        if pct >= 90 { color = .systemRed }
        else if pct >= 70 { color = .systemOrange }
        else { color = .systemGreen }

        let text = "C \(pct)%"
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium),
            .foregroundColor: color
        ]
        button.attributedTitle = NSAttributedString(string: text, attributes: attributes)
        button.image = nil
    }

    @objc func togglePanel() {
        if panel.isVisible {
            hidePanel()
        } else {
            showPanel()
        }
    }

    func showPanel() {
        guard let button = statusItem.button,
              let buttonWindow = button.window else { return }

        usageManager.fetchUsage()
        updateStatusIcon()

        let buttonRect = button.convert(button.bounds, to: nil)
        let screenRect = buttonWindow.convertToScreen(buttonRect)

        // Fit content
        if let hostingView = panel.contentView as? NSHostingView<AnyView> {
            let fitting = hostingView.fittingSize
            panel.setContentSize(NSSize(width: 340, height: fitting.height))
        }

        let panelWidth: CGFloat = 340
        let panelHeight = panel.frame.height
        let x = screenRect.midX - panelWidth / 2
        let y = screenRect.minY - panelHeight - 4

        panel.setFrame(NSRect(x: x, y: y, width: panelWidth, height: panelHeight), display: true)
        panel.orderFrontRegardless()
        panel.makeKey()

        // Close when clicking outside
        eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.hidePanel()
        }
    }

    func hidePanel() {
        panel.orderOut(nil)
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
    }
}

// MARK: - Usage Manager

class UsageManager: ObservableObject {
    @Published var sessionPercent: Double = 0
    @Published var sessionResetsAt: String = ""
    @Published var weeklyPercent: Double = 0
    @Published var weeklyResetsAt: String = ""
    @Published var sonnetPercent: Double = 0
    @Published var sonnetResetsAt: String = ""
    @Published var hasSonnet: Bool = false
    @Published var lastUpdated: String = ""
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?

    @Published var cookie: String {
        didSet { UserDefaults.standard.set(cookie, forKey: "claude_session_cookie") }
    }
    @Published var openAtLogin: Bool {
        didSet { UserDefaults.standard.set(openAtLogin, forKey: "open_at_login") }
    }
    @Published var notificationsEnabled: Bool {
        didSet { UserDefaults.standard.set(notificationsEnabled, forKey: "notifications_enabled") }
    }

    private var firedThresholds: Set<Int> = []

    init() {
        self.cookie = UserDefaults.standard.string(forKey: "claude_session_cookie") ?? ""
        self.openAtLogin = UserDefaults.standard.bool(forKey: "open_at_login")
        self.notificationsEnabled = UserDefaults.standard.bool(forKey: "notifications_enabled")
    }

    func fetchUsage() {
        guard !cookie.isEmpty else {
            errorMessage = "Set your session cookie to get started"
            return
        }
        isLoading = true
        errorMessage = nil

        let orgId = extractOrgId()

        if let orgId = orgId {
            fetchUsageData(orgId: orgId)
        } else {
            fetchOrgIdFromBootstrap { [weak self] fetchedId in
                guard let self = self else { return }
                if let id = fetchedId {
                    self.fetchUsageData(orgId: id)
                } else {
                    DispatchQueue.main.async {
                        self.isLoading = false
                        self.errorMessage = "Could not determine org ID. Check your cookie."
                    }
                }
            }
        }
    }

    private func extractOrgId() -> String? {
        let parts = cookie.components(separatedBy: "lastActiveOrg=")
        guard parts.count > 1 else { return nil }
        return parts[1].components(separatedBy: ";").first?.trimmingCharacters(in: .whitespaces)
    }

    private func fetchOrgIdFromBootstrap(completion: @escaping (String?) -> Void) {
        guard let url = URL(string: "https://claude.ai/api/bootstrap") else {
            completion(nil)
            return
        }
        var request = URLRequest(url: url)
        request.setValue(cookie, forHTTPHeaderField: "Cookie")
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36", forHTTPHeaderField: "User-Agent")

        URLSession.shared.dataTask(with: request) { data, _, _ in
            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let account = json["account"] as? [String: Any],
                  let orgId = account["lastActiveOrgId"] as? String else {
                completion(nil)
                return
            }
            completion(orgId)
        }.resume()
    }

    private func fetchUsageData(orgId: String) {
        guard let url = URL(string: "https://claude.ai/api/organizations/\(orgId)/usage") else {
            DispatchQueue.main.async { self.isLoading = false }
            return
        }
        var request = URLRequest(url: url)
        request.setValue(cookie, forHTTPHeaderField: "Cookie")
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36", forHTTPHeaderField: "User-Agent")
        request.setValue("https://claude.ai", forHTTPHeaderField: "Origin")
        request.setValue("https://claude.ai/", forHTTPHeaderField: "Referer")

        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.isLoading = false

                if let error = error {
                    self.errorMessage = error.localizedDescription
                    return
                }

                guard let data = data,
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    self.errorMessage = "Invalid response from API"
                    return
                }

                self.parseUsage(json)
                self.updateTimestamp()
            }
        }.resume()
    }

    private func parseUsage(_ json: [String: Any]) {
        if let session = json["five_hour"] as? [String: Any] {
            sessionPercent = (session["utilization"] as? Double) ?? 0
            sessionResetsAt = formatResetTime(session["resets_at"] as? String)
        }
        if let weekly = json["seven_day"] as? [String: Any] {
            weeklyPercent = (weekly["utilization"] as? Double) ?? 0
            weeklyResetsAt = formatResetDate(weekly["resets_at"] as? String)
        }
        if let sonnet = json["seven_day_sonnet"] as? [String: Any] {
            sonnetPercent = (sonnet["utilization"] as? Double) ?? 0
            sonnetResetsAt = formatResetDate(sonnet["resets_at"] as? String)
            hasSonnet = true
        } else {
            hasSonnet = false
        }

        checkNotifications()
    }

    private func formatResetTime(_ iso: String?) -> String {
        guard let iso = iso else { return "" }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let date = formatter.date(from: iso) else {
            formatter.formatOptions = [.withInternetDateTime]
            guard let date = formatter.date(from: iso) else { return iso }
            return formatTime(date)
        }
        return formatTime(date)
    }

    private func formatTime(_ date: Date) -> String {
        let df = DateFormatter()
        df.dateFormat = "HH:mm"
        return "Resets at \(df.string(from: date))"
    }

    private func formatResetDate(_ iso: String?) -> String {
        guard let iso = iso else { return "" }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let date = formatter.date(from: iso) else {
            formatter.formatOptions = [.withInternetDateTime]
            guard let date = formatter.date(from: iso) else { return iso }
            return formatDate(date)
        }
        return formatDate(date)
    }

    private func formatDate(_ date: Date) -> String {
        let df = DateFormatter()
        df.dateFormat = "d MMM yyyy 'at' h:mm a"
        return "Resets on \(df.string(from: date))"
    }

    private func updateTimestamp() {
        let df = DateFormatter()
        df.dateFormat = "HH:mm"
        lastUpdated = df.string(from: Date())
    }

    private func checkNotifications() {
        guard notificationsEnabled else { return }
        for threshold in [25, 50, 75, 90] {
            if Int(sessionPercent) >= threshold && !firedThresholds.contains(threshold) {
                firedThresholds.insert(threshold)
                sendNotification(title: "Claude Usage Alert", body: "Session usage at \(threshold)%")
            }
        }
    }

    func sendNotification(title: String, body: String) {
        let notification = NSUserNotification()
        notification.title = title
        notification.informativeText = body
        notification.soundName = NSUserNotificationDefaultSoundName
        NSUserNotificationCenter.default.deliver(notification)
    }
}

// MARK: - Usage View

struct UsageView: View {
    @ObservedObject var manager: UsageManager
    var onUpdate: () -> Void
    @State private var showSettings = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Claude Usage")
                .font(.headline)
                .padding(.bottom, 4)

            if let error = manager.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .onAppear { showSettings = true }
            }

            if !manager.lastUpdated.isEmpty {
                usageBar(label: "Session (5 hour)", percent: manager.sessionPercent, resetInfo: manager.sessionResetsAt)
                usageBar(label: "Weekly (7 day)", percent: manager.weeklyPercent, resetInfo: manager.weeklyResetsAt)

                if manager.hasSonnet {
                    usageBar(label: "Weekly Sonnet (7 day)", percent: manager.sonnetPercent, resetInfo: manager.sonnetResetsAt)
                }

                Divider()

                HStack {
                    Text("Last updated: \(manager.lastUpdated)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                    Button("Refresh") {
                        manager.fetchUsage()
                        onUpdate()
                    }
                    .buttonStyle(.plain)
                    .font(.caption)
                    .foregroundColor(.primary)
                }
            }

            // Collapsible settings
            Button(action: { withAnimation { showSettings.toggle() } }) {
                HStack {
                    Image(systemName: showSettings ? "chevron.down" : "chevron.right")
                        .font(.caption2)
                    Text("Settings")
                        .font(.caption)
                    Spacer()
                }
                .foregroundColor(.secondary)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if showSettings {
                VStack(alignment: .leading, spacing: 10) {
                    // Cookie input
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Session Cookie")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        HStack {
                            SecureField("Paste cookie here...", text: $manager.cookie)
                                .textFieldStyle(.roundedBorder)
                                .font(.caption)
                            Button("Save") {
                                manager.fetchUsage()
                                onUpdate()
                            }
                            .font(.caption)
                        }
                    }

                    Divider()

                    Toggle(isOn: $manager.openAtLogin) {
                        VStack(alignment: .leading) {
                            Text("Open at Login")
                                .font(.caption)
                            Text("Launch app automatically when you log in")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                    .toggleStyle(.checkbox)

                    Toggle(isOn: $manager.notificationsEnabled) {
                        VStack(alignment: .leading) {
                            Text("Enable Notifications")
                                .font(.caption)
                            Text("Get alerts at 25%, 50%, 75%, and 90% session usage")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                    .toggleStyle(.checkbox)

                    if manager.notificationsEnabled {
                        Button("Test Notification") {
                            manager.sendNotification(title: "Claude Usage", body: "This is a test notification")
                        }
                        .font(.caption)
                    }

                    Divider()

                    Button("Quit") {
                        NSApplication.shared.terminate(nil)
                    }
                    .font(.caption)
                    .foregroundColor(.red)
                }
                .padding(.top, 6)
            }
        }
        .padding(16)
        .frame(width: 340)
    }

    func usageBar(label: String, percent: Double, resetInfo: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label)
                    .font(.system(size: 12, weight: .medium))
                Spacer()
                Text(resetInfo)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.gray.opacity(0.2))
                        .frame(height: 8)
                    RoundedRectangle(cornerRadius: 3)
                        .fill(barColor(percent))
                        .frame(width: max(0, geo.size.width * CGFloat(min(percent, 100)) / 100), height: 8)
                }
            }
            .frame(height: 8)
            Text("\(Int(percent))% used")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .padding(.bottom, 4)
    }

    func barColor(_ percent: Double) -> Color {
        if percent >= 90 { return .red }
        if percent >= 70 { return .orange }
        return .primary.opacity(0.7)
    }
}
