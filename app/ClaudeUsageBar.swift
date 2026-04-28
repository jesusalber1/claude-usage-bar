import SwiftUI
import AppKit
import UserNotifications
import ServiceManagement

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
    var refreshTimer: Timer?
    var iconTickTimer: Timer?
    private var appearanceObservation: NSKeyValueObservation?

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem.button {
            updateStatusIcon()
            button.action = #selector(togglePanel)
            button.target = self
            appearanceObservation = button.observe(\.effectiveAppearance, options: [.new]) { [weak self] _, _ in
                DispatchQueue.main.async { self?.updateStatusIcon() }
            }
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

        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, error in
            if let error = error {
                NSLog("Notification auth error: \(error.localizedDescription)")
            } else {
                NSLog("Notification auth granted: \(granted)")
            }
        }

        usageManager.onDataUpdated = { [weak self] in
            self?.updateStatusIcon()
        }
        usageManager.fetchUsage()
        scheduleBackgroundRefresh()
        scheduleIconTick()

        DistributedNotificationCenter.default.addObserver(
            self,
            selector: #selector(appearanceChanged),
            name: NSNotification.Name("AppleInterfaceThemeChangedNotification"),
            object: nil
        )

        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(systemDidWake),
            name: NSWorkspace.didWakeNotification,
            object: nil
        )
    }

    @objc func systemDidWake() {
        usageManager.fetchUsage()
        updateStatusIcon()
        refreshTimer?.invalidate()
        scheduleBackgroundRefresh()
        scheduleIconTick()
    }

    @objc func appearanceChanged() {
        DispatchQueue.main.async { [weak self] in
            self?.updateStatusIcon()
        }
    }

    func scheduleBackgroundRefresh() {
        let interval = 900 + Double.random(in: 0...300) // 15 min + rand 0-5 min
        let timer = Timer(timeInterval: interval, repeats: false) { [weak self] _ in
            self?.usageManager.fetchUsage()
            self?.updateStatusIcon()
            self?.scheduleBackgroundRefresh()
        }
        RunLoop.main.add(timer, forMode: .common)
        refreshTimer = timer
    }

    func scheduleIconTick() {
        iconTickTimer?.invalidate()
        let timer = Timer(timeInterval: 60, repeats: true) { [weak self] _ in
            self?.updateStatusIcon()
        }
        RunLoop.main.add(timer, forMode: .common)
        iconTickTimer = timer
    }

    func updateStatusIcon() {
        guard let button = statusItem.button else { return }
        let pct = Int(usageManager.sessionPercent)
        let color: NSColor
        if pct >= 90 { color = .systemRed }
        else if pct >= 70 { color = .systemOrange }
        else { color = .systemGreen }

        let appearance = button.window != nil ? button.effectiveAppearance : NSApp.effectiveAppearance
        let matchedName = appearance.bestMatch(from: [
            .aqua, .darkAqua,
            .vibrantLight, .vibrantDark,
            .accessibilityHighContrastAqua, .accessibilityHighContrastDarkAqua,
            .accessibilityHighContrastVibrantLight, .accessibilityHighContrastVibrantDark
        ])
        let isDark = matchedName == .darkAqua
            || matchedName == .vibrantDark
            || matchedName == .accessibilityHighContrastDarkAqua
            || matchedName == .accessibilityHighContrastVibrantDark
        let foreground: NSColor = isDark ? .white : .black

        let pctText = "\(pct)%"
        let timeText = formatTimeLeft(usageManager.sessionResetDate)
        let textFont = NSFont.monospacedDigitSystemFont(ofSize: 9, weight: .medium)

        let pctSize = (pctText as NSString).size(withAttributes: [.font: textFont])
        let timeSize = (timeText as NSString).size(withAttributes: [.font: textFont])
        let textWidth = max(pctSize.width, timeSize.width)

        let symbolConfig = NSImage.SymbolConfiguration(pointSize: 8, weight: .semibold)
            .applying(.init(paletteColors: [foreground]))
        let stopwatchImage = NSImage(systemSymbolName: "stopwatch", accessibilityDescription: nil)?
            .withSymbolConfiguration(symbolConfig)
        let usageImage = NSImage(systemSymbolName: "bolt.fill", accessibilityDescription: nil)?
            .withSymbolConfiguration(symbolConfig)

        let iconColumnWidth: CGFloat = 11
        let barHeight: CGFloat = 3
        let rowHeight: CGFloat = max(11, pctSize.height, timeSize.height)
        let rowGap: CGFloat = 1
        let gap: CGFloat = 3
        let barWidth: CGFloat = 28

        let width = iconColumnWidth + gap + barWidth + gap + textWidth
        let height = rowHeight * 2 + rowGap

        let image = NSImage(size: NSSize(width: width, height: height))
        image.lockFocus()

        let drawRow: (CGFloat, NSImage?, Double, NSColor, String, NSSize) -> Void = { yOffset, icon, fraction, fillColor, text, textSize in
            if let icon = icon {
                let iconY = yOffset + (rowHeight - icon.size.height) / 2
                let iconX = max(0, (iconColumnWidth - icon.size.width) / 2)
                icon.draw(
                    at: NSPoint(x: iconX, y: iconY),
                    from: .zero,
                    operation: .sourceOver,
                    fraction: 1.0
                )
            }

            let barX = iconColumnWidth + gap
            let barY = yOffset + (rowHeight - barHeight) / 2
            let trackRect = NSRect(x: barX, y: barY, width: barWidth, height: barHeight)
            let track = NSBezierPath(roundedRect: trackRect, xRadius: barHeight / 2, yRadius: barHeight / 2)
            foreground.withAlphaComponent(0.18).setFill()
            track.fill()

            let fillW = barWidth * CGFloat(min(max(fraction, 0), 1))
            if fillW > 0 {
                NSGraphicsContext.saveGraphicsState()
                track.addClip()
                fillColor.setFill()
                NSBezierPath(rect: NSRect(x: barX, y: barY, width: fillW, height: barHeight)).fill()
                NSGraphicsContext.restoreGraphicsState()
            }

            let textX = barX + barWidth + gap
            let textY = yOffset + (rowHeight - textSize.height) / 2
            (text as NSString).draw(
                at: NSPoint(x: textX, y: textY),
                withAttributes: [.font: textFont, .foregroundColor: foreground]
            )
        }

        let timeFraction = computeTimeFraction(usageManager.sessionResetDate)
        drawRow(rowHeight + rowGap, stopwatchImage, timeFraction, foreground.withAlphaComponent(0.55), timeText, timeSize)
        drawRow(0, usageImage, Double(pct) / 100.0, color, pctText, pctSize)

        image.unlockFocus()
        image.isTemplate = false

        button.image = image
        button.attributedTitle = NSAttributedString(string: "")
        button.imagePosition = .imageOnly
    }

    private func computeTimeFraction(_ date: Date?) -> Double {
        guard let date = date else { return 0 }
        let total: TimeInterval = 5 * 3600
        let remaining = date.timeIntervalSinceNow
        let elapsed = total - remaining
        return max(0, min(1, elapsed / total))
    }

    private func formatTimeLeft(_ date: Date?) -> String {
        guard let date = date else { return "—" }
        let interval = date.timeIntervalSinceNow
        if interval <= 0 { return "0m" }
        let totalMinutes = Int(interval / 60)
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        if hours > 0 { return "\(hours)h \(minutes)m" }
        if totalMinutes > 0 { return "\(totalMinutes)m" }
        return "<1m"
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
    @Published var sessionResetDate: Date?
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
        didSet {
            UserDefaults.standard.set(openAtLogin, forKey: "open_at_login")
            applyOpenAtLogin(openAtLogin)
        }
    }

    private func applyOpenAtLogin(_ enabled: Bool) {
        let service = SMAppService.mainApp
        do {
            if enabled {
                if service.status != .enabled {
                    try service.register()
                }
            } else {
                if service.status == .enabled {
                    try service.unregister()
                }
            }
        } catch {
            NSLog("Open-at-login update failed: \(error.localizedDescription)")
        }
    }
    @Published var notificationsEnabled: Bool {
        didSet { UserDefaults.standard.set(notificationsEnabled, forKey: "notifications_enabled") }
    }

    private var firedThresholds: Set<Int> = []
    var onDataUpdated: (() -> Void)?

    init() {
        self.cookie = UserDefaults.standard.string(forKey: "claude_session_cookie") ?? ""
        let savedOpenAtLogin = UserDefaults.standard.bool(forKey: "open_at_login")
        let systemEnabled = SMAppService.mainApp.status == .enabled
        self.openAtLogin = savedOpenAtLogin || systemEnabled
        self.notificationsEnabled = UserDefaults.standard.bool(forKey: "notifications_enabled")
        if savedOpenAtLogin && !systemEnabled {
            applyOpenAtLogin(true)
        }
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
                self.onDataUpdated?()
            }
        }.resume()
    }

    private func parseUsage(_ json: [String: Any]) {
        if let session = json["five_hour"] as? [String: Any] {
            sessionPercent = (session["utilization"] as? Double) ?? 0
            sessionResetsAt = formatResetTime(session["resets_at"] as? String)
            sessionResetDate = parseISODate(session["resets_at"] as? String)
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

    private func parseISODate(_ iso: String?) -> Date? {
        guard let iso = iso else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = formatter.date(from: iso) { return d }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: iso)
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
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { settings in
            if settings.authorizationStatus == .notDetermined {
                center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
                    if granted { center.add(request) }
                }
            } else if settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional {
                center.add(request) { error in
                    if let error = error {
                        NSLog("Notification deliver error: \(error.localizedDescription)")
                    }
                }
            } else {
                NSLog("Notifications not authorized: \(settings.authorizationStatus.rawValue)")
            }
        }
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
