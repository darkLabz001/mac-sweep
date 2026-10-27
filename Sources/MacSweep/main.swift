import SwiftUI
import Foundation
import AppKit
import CryptoKit

struct SweepItem: Identifiable, Hashable, Sendable {
    let id = UUID()
    let url: URL
    let category: SweepCategory
    let bytes: Int64
    let modified: Date

    var name: String { url.lastPathComponent }
}

struct ProtectionCheck: Identifiable, Sendable {
    enum State: Sendable {
        case secure, attention, unavailable
    }

    let id: String
    let title: String
    let icon: String
    let state: State
    let detail: String
}

struct InstalledApp: Identifiable, Sendable {
    let id = UUID()
    let url: URL
    let name: String
    let version: String
    let size: Int64
}

enum SweepCategory: String, CaseIterable, Identifiable, Sendable {
    case smartScan = "Smart Scan"
    case systemJunk = "System Junk"
    case mailAttachments = "Mail Attachments"
    case trash = "Trash Bins"
    case largeFiles = "Large & Old Files"
    case applications = "Applications"
    case startupItems = "Login Items"
    case duplicates = "Duplicates"
    case performance = "Performance"
    case maintenance = "Maintenance"
    case protection = "Protection"
    case spaceLens = "Space Lens"
    case myClutter = "My Clutter"
    case updater = "Updater"
    case downloads = "Downloads"

    var id: String { rawValue }
    var icon: String {
        switch self {
        case .smartScan: "sparkles"
        case .systemJunk: "gearshape.2"
        case .mailAttachments: "envelope"
        case .trash: "trash"
        case .largeFiles: "externaldrive"
        case .applications: "square.stack.3d.up"
        case .startupItems: "power"
        case .duplicates: "square.on.square"
        case .performance: "gauge.with.dots.needle.67percent"
        case .maintenance: "wrench.and.screwdriver"
        case .protection: "shield.lefthalf.filled"
        case .spaceLens: "chart.bar.xaxis"
        case .myClutter: "rectangle.3.group"
        case .updater: "square.and.arrow.down"
        case .downloads: "arrow.down.circle"
        }
    }
    var detail: String {
        switch self {
        case .smartScan: "A complete overview of your Mac"
        case .systemJunk: "Caches, logs, and temporary files"
        case .mailAttachments: "Large files saved by Mail"
        case .trash: "Items already in your Trash"
        case .largeFiles: "Big files and forgotten downloads"
        case .applications: "Installed apps and their footprints"
        case .startupItems: "Apps that launch when you log in"
        case .duplicates: "Identical files taking up space twice"
        case .performance: "Review startup load and available headroom"
        case .maintenance: "Read-only maintenance recommendations"
        case .protection: "Local safety checks for your Mac"
        case .spaceLens: "See what is consuming your available space"
        case .myClutter: "Large, old, and duplicate files"
        case .updater: "Installed application versions"
        case .downloads: "Old files in your Downloads folder"
        }
    }
}

enum Neon {
    static let violet = Color(red: 0.55, green: 0.18, blue: 1.0)
    static let magenta = Color(red: 1.0, green: 0.12, blue: 0.58)
    static let cyan = Color(red: 0.05, green: 0.86, blue: 1.0)
    static let acid = Color(red: 0.72, green: 1.0, blue: 0.16)
    static let midnight = Color(red: 0.025, green: 0.018, blue: 0.075)
    static let panel = Color(red: 0.08, green: 0.055, blue: 0.15)
}

extension View {
    @ViewBuilder
    func sweepGlass(tint: Color = Neon.violet, radius: CGFloat = 16) -> some View {
        if #available(macOS 26.0, *) {
            self.glassEffect(.regular.tint(tint.opacity(0.22)).interactive(), in: .rect(cornerRadius: radius))
        } else {
            self.background(Neon.panel.opacity(0.88), in: RoundedRectangle(cornerRadius: radius))
                .overlay(RoundedRectangle(cornerRadius: radius).stroke(tint.opacity(0.28), lineWidth: 1))
        }
    }
}

@MainActor
final class SweepModel: ObservableObject {
    @Published var selectedCategory: SweepCategory = .smartScan
    @Published var items: [SweepItem] = []
    @Published var selectedIDs = Set<UUID>()
    @Published var isScanning = false
    @Published var isCleaning = false
    @Published var lastScan: Date?
    @Published var message = "Ready when you are"
    @Published var protectionChecks: [ProtectionCheck] = []
    @Published var isCheckingProtection = false
    @Published var installedApps: [InstalledApp] = []

    var selectedItems: [SweepItem] { items.filter { selectedIDs.contains($0.id) } }
    var selectedBytes: Int64 { selectedItems.reduce(0) { $0 + $1.bytes } }
    var totalBytes: Int64 { items.reduce(0) { $0 + $1.bytes } }
    var storage: (used: Int64, free: Int64, total: Int64) {
        let values = try? FileManager.default.homeDirectoryForCurrentUser.resourceValues(forKeys: [.volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey])
        let total = Int64(values?.volumeTotalCapacity ?? 0)
        let free = Int64(values?.volumeAvailableCapacityForImportantUsage ?? 0)
        return (max(0, total - free), free, total)
    }
    var displayedItems: [SweepItem] {
        guard selectedCategory != .smartScan else {
            return items.filter { Self.isSmartScanCandidate($0.category) }
        }
        return items.filter { $0.category == selectedCategory }
    }

    private static func isSmartScanCandidate(_ category: SweepCategory) -> Bool {
        switch category {
        case .systemJunk, .mailAttachments, .downloads, .largeFiles, .duplicates:
            return true
        case .smartScan, .trash, .applications, .startupItems, .performance, .maintenance, .protection, .spaceLens, .myClutter, .updater:
            return false
        }
    }

    private static func isAutoSelected(_ category: SweepCategory) -> Bool {
        category == .systemJunk || category == .mailAttachments
    }

    private nonisolated static func isSafeToTrash(_ item: SweepItem) -> Bool {
        switch item.category {
        case .systemJunk, .mailAttachments, .downloads, .largeFiles, .duplicates:
            break
        case .smartScan, .trash, .applications, .startupItems, .performance, .maintenance, .protection, .spaceLens, .myClutter, .updater:
            return false
        }
        let home = FileManager.default.homeDirectoryForCurrentUser.resolvingSymlinksInPath()
        let resolved = item.url.resolvingSymlinksInPath()
        guard resolved.path.hasPrefix(home.path + "/"), resolved != home else { return false }
        guard let values = try? resolved.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey]) else { return false }
        return values.isDirectory != true && values.isSymbolicLink != true && FileManager.default.isReadableFile(atPath: resolved.path)
    }

    func scan() {
        guard !isScanning else { return }
        isScanning = true
        message = "Checking your Mac..."
        if ProcessInfo.processInfo.environment["MAC_SWEEP_DEMO"] == "1" {
            let found = Self.demoItems()
            items = found
            installedApps = Self.demoApps()
            selectedIDs = Set(found.filter { Self.isAutoSelected($0.category) }.map(\.id))
            lastScan = Date()
            isScanning = false
            message = "Demo scan complete — fabricated data only"
            return
        }
        let home = FileManager.default.homeDirectoryForCurrentUser
        Task.detached(priority: .userInitiated) {
            let found = Self.findItems(home: home)
            let apps = Self.findApplications(home: home)
            await MainActor.run {
                self.items = found
                self.installedApps = apps
                self.selectedIDs = Set(found.filter { Self.isAutoSelected($0.category) }.map(\.id))
                self.lastScan = Date()
                self.isScanning = false
                self.message = found.isEmpty ? "Your Mac is looking tidy" : "Review the items below"
            }
        }
    }

    func runProtectionChecks() {
        guard !isCheckingProtection else { return }
        isCheckingProtection = true
        if ProcessInfo.processInfo.environment["MAC_SWEEP_DEMO"] == "1" {
            protectionChecks = [
                ProtectionCheck(id: "filevault", title: "FileVault encryption", icon: "lock.shield", state: .secure, detail: "Encryption is enabled (demo result)"),
                ProtectionCheck(id: "firewall", title: "Application firewall", icon: "firewall", state: .secure, detail: "Firewall is enabled (demo result)"),
                ProtectionCheck(id: "gatekeeper", title: "Gatekeeper", icon: "checkmark.seal", state: .secure, detail: "Assessments enabled (demo result)"),
                ProtectionCheck(id: "sip", title: "System Integrity Protection", icon: "shield.lefthalf.filled", state: .secure, detail: "Enabled (demo result)"),
                ProtectionCheck(id: "updates", title: "Automatic updates", icon: "arrow.down.circle", state: .secure, detail: "Automatic checking enabled (demo result)")
            ]
            isCheckingProtection = false
            return
        }
        Task.detached(priority: .userInitiated) {
            let checks = Self.performProtectionChecks()
            await MainActor.run {
                self.protectionChecks = checks
                self.isCheckingProtection = false
            }
        }
    }

    func runDemoSequence() {
        guard ProcessInfo.processInfo.environment["MAC_SWEEP_DEMO"] == "1" else { return }
        Task { @MainActor in
            for category in [SweepCategory.smartScan, .myClutter, .updater, .protection, .smartScan] {
                try? await Task.sleep(for: .seconds(2))
                selectedCategory = category
            }
        }
    }

    func cleanSelected() {
        guard !selectedItems.isEmpty, !isCleaning else { return }
        isCleaning = true
        let candidates = selectedItems.filter { Self.isSafeToTrash($0) }
        guard !candidates.isEmpty else {
            isCleaning = false
            message = "Nothing selected is eligible for automatic cleanup"
            return
        }
        Task.detached(priority: .userInitiated) {
            var removed = Set<UUID>()
            for item in candidates {
                do {
                    guard Self.isSafeToTrash(item) else { continue }
                    var result: NSURL?
                    try FileManager.default.trashItem(at: item.url, resultingItemURL: &result)
                    removed.insert(item.id)
                } catch {
                    // Files in use or removed by another process remain visible for review.
                }
            }
            await MainActor.run {
                self.items.removeAll { removed.contains($0.id) }
                self.selectedIDs.subtract(removed)
                self.isCleaning = false
                self.message = removed.isEmpty ? "Nothing was moved" : "Moved \(removed.count) item\(removed.count == 1 ? "" : "s") to Trash"
            }
        }
    }

    func toggleAll() {
        let visible = displayedItems
        let visibleIDs = Set(visible.map(\.id))
        if visibleIDs.isSubset(of: selectedIDs) {
            selectedIDs.subtract(visibleIDs)
        } else {
            selectedIDs.formUnion(visibleIDs)
        }
    }

    private nonisolated static func findItems(home: URL) -> [SweepItem] {
        let fm = FileManager.default
        let roots: [(SweepCategory, URL)] = [
            (.systemJunk, home.appending(path: "Library/Caches")),
            (.systemJunk, home.appending(path: "Library/Logs")),
            (.downloads, home.appending(path: "Downloads")),
            (.largeFiles, home.appending(path: "Downloads")),
            (.largeFiles, home.appending(path: "Documents")),
            (.largeFiles, home.appending(path: "Desktop")),
            (.mailAttachments, home.appending(path: "Library/Containers/com.apple.mail/Data/Library/Mail Downloads")),
            (.startupItems, home.appending(path: "Library/LaunchAgents")),
            (.duplicates, home.appending(path: "Downloads")),
            (.duplicates, home.appending(path: "Documents")),
            (.duplicates, home.appending(path: "Desktop"))
        ]
        let cutoff = Date().addingTimeInterval(-30 * 86400)
        let largeCutoff = Date().addingTimeInterval(-90 * 86400)
        var found: [SweepItem] = []
        for (category, root) in roots where fm.fileExists(atPath: root.path) {
            guard let enumerator = fm.enumerator(at: root, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey, .fileSizeKey, .contentModificationDateKey], options: [.skipsHiddenFiles]) else { continue }
            for case let url as URL in enumerator {
                do {
                    let values = try url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey, .fileSizeKey, .contentModificationDateKey])
                    guard values.isDirectory != true, values.isSymbolicLink != true,
                          let modified = values.contentModificationDate, modified < cutoff else { continue }
                    if category == .largeFiles && (values.fileSize ?? 0) < 500_000_000 && modified >= largeCutoff { continue }
                    if category == .duplicates { continue }
                    found.append(SweepItem(url: url, category: category, bytes: Int64(values.fileSize ?? 0), modified: modified))
                } catch { continue }
            }
        }
        let applications = [
            URL(fileURLWithPath: "/Applications", isDirectory: true),
            home.appending(path: "Applications")
        ]
        for root in applications where fm.fileExists(atPath: root.path) {
            guard let entries = try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey], options: [.skipsHiddenFiles]) else { continue }
            for url in entries where url.pathExtension == "app" {
                let bytes = directorySize(url, fileManager: fm)
                let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date()
                found.append(SweepItem(url: url, category: .applications, bytes: bytes, modified: modified))
            }
        }
        let trash = home.appending(path: ".Trash")
        if let entries = try? fm.contentsOfDirectory(at: trash, includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey], options: [.skipsHiddenFiles]) {
            for url in entries {
                let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey])
                let bytes = values?.isDirectory == true ? directorySize(url, fileManager: fm) : Int64(values?.fileSize ?? 0)
                found.append(SweepItem(url: url, category: .trash, bytes: bytes, modified: values?.contentModificationDate ?? Date()))
            }
        }
        found.append(contentsOf: duplicateItems(home: home, fileManager: fm))
        return found.sorted { $0.bytes > $1.bytes }
    }

    private nonisolated static func findApplications(home: URL) -> [InstalledApp] {
        let fileManager = FileManager.default
        let roots = [URL(fileURLWithPath: "/Applications", isDirectory: true), home.appending(path: "Applications")]
        var apps: [InstalledApp] = []
        for root in roots where fileManager.fileExists(atPath: root.path) {
            guard let entries = try? fileManager.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) else { continue }
            for url in entries where url.pathExtension == "app" {
                let bundle = Bundle(url: url)
                let name = bundle?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ?? url.deletingPathExtension().lastPathComponent
                let version = bundle?.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Unknown"
                apps.append(InstalledApp(url: url, name: name, version: version, size: directorySize(url, fileManager: fileManager)))
            }
        }
        return apps.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private nonisolated static func performProtectionChecks() -> [ProtectionCheck] {
        let fileVault = command("/usr/bin/fdesetup", arguments: ["status"])
        let firewall = command("/usr/libexec/ApplicationFirewall/socketfilterfw", arguments: ["--getglobalstate"])
        let gatekeeper = command("/usr/sbin/spctl", arguments: ["--status"])
        let sip = command("/usr/bin/csrutil", arguments: ["status"])
        let updates = command("/usr/sbin/softwareupdate", arguments: ["--schedule"])

        return [
            ProtectionCheck(id: "filevault", title: "FileVault encryption", icon: "lock.shield", state: fileVault.output.localizedCaseInsensitiveContains("is on") ? .secure : .attention, detail: fileVault.output.isEmpty ? "Status unavailable" : fileVault.output.trimmingCharacters(in: .whitespacesAndNewlines)),
            ProtectionCheck(id: "firewall", title: "Application firewall", icon: "firewall", state: firewall.output.localizedCaseInsensitiveContains("enabled") ? .secure : .attention, detail: firewall.output.isEmpty ? "Status unavailable" : firewall.output.trimmingCharacters(in: .whitespacesAndNewlines)),
            ProtectionCheck(id: "gatekeeper", title: "Gatekeeper", icon: "checkmark.seal", state: gatekeeper.output.localizedCaseInsensitiveContains("assessments enabled") ? .secure : .attention, detail: gatekeeper.output.isEmpty ? "Status unavailable" : gatekeeper.output.trimmingCharacters(in: .whitespacesAndNewlines)),
            ProtectionCheck(id: "sip", title: "System Integrity Protection", icon: "shield.lefthalf.filled", state: sip.output.localizedCaseInsensitiveContains("enabled") ? .secure : .attention, detail: sip.output.isEmpty ? "Status unavailable" : sip.output.trimmingCharacters(in: .whitespacesAndNewlines)),
            ProtectionCheck(id: "updates", title: "Automatic updates", icon: "arrow.down.circle", state: updates.output.localizedCaseInsensitiveContains("on") ? .secure : .attention, detail: updates.output.isEmpty ? "Status unavailable" : updates.output.trimmingCharacters(in: .whitespacesAndNewlines))
        ]
    }

    private nonisolated static func demoItems() -> [SweepItem] {
        let root = URL(fileURLWithPath: "/Users/demo")
        let entries: [(String, SweepCategory, Int64)] = [
            ("Library/Caches/Studio/cache.bundle", .systemJunk, 4_200_000_000),
            ("Library/Logs/agent/session.log", .systemJunk, 820_000_000),
            ("Library/Mail Downloads/Design-assets.zip", .mailAttachments, 1_600_000_000),
            ("Downloads/archive-2024.zip", .largeFiles, 2_800_000_000),
            ("Documents/duplicate-presentation.key", .duplicates, 760_000_000),
            ("Downloads/duplicate-presentation-copy.key", .duplicates, 760_000_000)
        ]
        return entries.map { path, category, bytes in
            SweepItem(url: root.appending(path: path), category: category, bytes: bytes, modified: Date().addingTimeInterval(-45 * 86400))
        }
    }

    private nonisolated static func demoApps() -> [InstalledApp] {
        [
            InstalledApp(url: URL(fileURLWithPath: "/Applications/Orbit.app"), name: "Orbit", version: "4.2.1", size: 1_200_000_000),
            InstalledApp(url: URL(fileURLWithPath: "/Applications/Signal Forge.app"), name: "Signal Forge", version: "2.8.0", size: 640_000_000),
            InstalledApp(url: URL(fileURLWithPath: "/Applications/Pixel Lab.app"), name: "Pixel Lab", version: "7.1.3", size: 2_100_000_000)
        ]
    }

    private nonisolated static func command(_ executable: String, arguments: [String]) -> (output: String, status: Int32) {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = pipe
        process.standardError = pipe
        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return (String(data: data, encoding: .utf8) ?? "", process.terminationStatus)
        } catch {
            return ("", -1)
        }
    }

    private nonisolated static func directorySize(_ url: URL, fileManager: FileManager) -> Int64 {
        guard let enumerator = fileManager.enumerator(at: url, includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey], options: [.skipsHiddenFiles]) else { return 0 }
        var total: Int64 = 0
        for case let child as URL in enumerator {
            let values = try? child.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey])
            if values?.isDirectory != true { total += Int64(values?.fileSize ?? 0) }
        }
        return total
    }

    private nonisolated static func duplicateItems(home: URL, fileManager: FileManager) -> [SweepItem] {
        let roots = [home.appending(path: "Downloads"), home.appending(path: "Documents"), home.appending(path: "Desktop")]
        var bySize: [Int64: [URL]] = [:]
        for root in roots where fileManager.fileExists(atPath: root.path) {
            guard let enumerator = fileManager.enumerator(at: root, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey, .fileSizeKey], options: [.skipsHiddenFiles]) else { continue }
            for case let url as URL in enumerator {
                let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey, .fileSizeKey])
                guard values?.isDirectory != true, values?.isSymbolicLink != true, let size = values?.fileSize, size > 0 else { continue }
                bySize[Int64(size), default: []].append(url)
            }
        }
        var byHash: [String: [URL]] = [:]
        for (size, urls) in bySize where urls.count > 1 && size < 250_000_000 {
            for url in urls {
                if let hash = fileHash(url, fileManager: fileManager) { byHash[hash, default: []].append(url) }
            }
        }
        return byHash.values.filter { $0.count > 1 }.flatMap { urls in
            urls.dropFirst().compactMap { url in
                guard let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey]), let size = values.fileSize else { return nil }
                return SweepItem(url: url, category: .duplicates, bytes: Int64(size), modified: values.contentModificationDate ?? Date())
            }
        }
    }

    private nonisolated static func fileHash(_ url: URL, fileManager: FileManager) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        var hasher = SHA256()
        defer { try? handle.close() }
        while true {
            guard let data = try? handle.read(upToCount: 1_048_576), !data.isEmpty else { break }
            hasher.update(data: data)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}

@main
struct MacSweepApp: App {
    var body: some Scene {
        Window("Mac Sweep", id: "main") { ContentView() }
            .windowStyle(.hiddenTitleBar)
            .defaultSize(width: 1120, height: 720)
    }
}

struct ContentView: View {
    @StateObject private var model = SweepModel()
    @State private var showAll = false
    @State private var search = ""
    @State private var showCleanupConfirmation = false

    private var visibleItems: [SweepItem] {
        let items = model.displayedItems
        guard !search.isEmpty else { return showAll ? items : Array(items.prefix(120)) }
        return items.filter { $0.name.localizedCaseInsensitiveContains(search) || $0.url.path.localizedCaseInsensitiveContains(search) }
    }

    var body: some View {
        HStack(spacing: 0) {
            Sidebar(model: model)
            VStack(spacing: 0) {
                Header(model: model, search: $search)
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        SummaryCard(model: model)
                        StorageStrip(model: model)
                        if model.selectedCategory == .smartScan {
                            SmartCareRoutines(model: model)
                        } else if model.selectedCategory == .performance {
                            PerformancePanel(model: model)
                        } else if model.selectedCategory == .maintenance {
                            MaintenancePanel(model: model)
                        } else if model.selectedCategory == .protection {
                            ProtectionPanel(model: model)
                        } else if model.selectedCategory == .spaceLens {
                            SpaceLensPanel(model: model)
                        } else if model.selectedCategory == .updater {
                            UpdaterPanel(model: model)
                        } else if model.selectedCategory == .myClutter {
                            MyClutterPanel(model: model)
                        } else if model.items.isEmpty && !model.isScanning {
                            EmptyState(model: model)
                        } else {
                            if model.selectedCategory == .applications {
                                UninstallerNotice()
                            }
                            ResultsHeader(model: model, showAll: $showAll)
                            ResultsList(model: model, items: visibleItems)
                        }
                    }
                    .padding(32)
                }
                Footer(model: model, showConfirmation: $showCleanupConfirmation)
            }
        }
        .frame(minWidth: 980, minHeight: 650)
        .preferredColorScheme(.dark)
        .background {
            ZStack {
                Neon.midnight
                Circle().fill(Neon.magenta.opacity(0.12)).frame(width: 420).blur(radius: 100).offset(x: 360, y: -280)
                Circle().fill(Neon.cyan.opacity(0.08)).frame(width: 360).blur(radius: 110).offset(x: -280, y: 280)
            }.ignoresSafeArea()
        }
        .task {
            model.scan()
            model.runProtectionChecks()
            model.runDemoSequence()
        }
        .alert("Move selected files to Trash?", isPresented: $showCleanupConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Move to Trash", role: .destructive) { model.cleanSelected() }
        } message: {
            Text("Only verified user-owned cleanup files will be moved. Apps, login items, and Trash contents are blocked from this action.")
        }
    }
}

struct Sidebar: View {
    @ObservedObject var model: SweepModel
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10).fill(LinearGradient(colors: [Neon.magenta, Neon.violet], startPoint: .topLeading, endPoint: .bottomTrailing))
                    Image(systemName: "sparkles").foregroundStyle(.white).font(.title3.bold())
                }.frame(width: 34, height: 34)
                VStack(alignment: .leading, spacing: 1) {
                    Text("MAC SWEEP").font(.title3.weight(.black)).tracking(1.4)
                    Text("NIGHTSHIFT EDITION").font(.system(size: 8, weight: .bold, design: .monospaced)).tracking(1.1).foregroundStyle(Neon.cyan)
                }
            }.padding(.bottom, 24)
            sidebarSection("CLEANUP // PROTOCOLS", [.smartScan, .systemJunk, .mailAttachments, .trash])
            sidebarSection("SPEED // PERFORMANCE", [.performance, .maintenance, .startupItems])
            sidebarSection("DEFENSE // PROTECTION", [.protection])
            sidebarSection("FILES // STORAGE", [.myClutter, .applications, .largeFiles, .duplicates, .downloads, .spaceLens])
            sidebarSection("APPS // UPDATES", [.updater])
            Spacer()
            VStack(alignment: .leading, spacing: 8) {
                Label("SAFE MODE // ACTIVE", systemImage: "checkmark.shield")
                    .font(.system(size: 10, weight: .bold, design: .monospaced)).foregroundStyle(Neon.acid)
                Text("Selected files go to Trash. Nothing is permanently deleted.")
                    .font(.caption2).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }.padding(12).sweepGlass(tint: Neon.acid, radius: 10)
        }
        .padding(20).frame(width: 240).background(Neon.midnight.opacity(0.82))
    }

    @ViewBuilder
    private func sidebarSection(_ title: String, _ categories: [SweepCategory]) -> some View {
        Text(title).font(.system(size: 10, weight: .bold, design: .monospaced)).tracking(1.1).foregroundStyle(Neon.cyan).padding(.leading, 10).padding(.top, 5)
        ForEach(categories) { category in
            Button { model.selectedCategory = category } label: {
                Label { Text(category.rawValue).font(.callout.weight(.medium)) } icon: { Image(systemName: category.icon).font(.callout) }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 7).padding(.horizontal, 10)
                    .background(model.selectedCategory == category ? Neon.magenta.opacity(0.15) : .clear, in: RoundedRectangle(cornerRadius: 8))
                    .overlay(alignment: .leading) { if model.selectedCategory == category { Capsule().fill(Neon.magenta).frame(width: 3).padding(.vertical, 5) } }
                    .foregroundStyle(model.selectedCategory == category ? Neon.magenta : .primary)
            }.buttonStyle(.plain)
        }
    }
}

struct Header: View {
    @ObservedObject var model: SweepModel
    @Binding var search: String
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(model.selectedCategory.rawValue.uppercased()).font(.system(size: 20, weight: .black, design: .rounded)).tracking(1.1)
                Text(model.selectedCategory.detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            HStack(spacing: 8) { Image(systemName: "magnifyingglass"); TextField("Search", text: $search).textFieldStyle(.plain) }
                .padding(9).frame(width: 200).sweepGlass(tint: Neon.cyan, radius: 10).foregroundStyle(.secondary)
            Button { model.scan() } label: { Label("SCAN", systemImage: "arrow.clockwise") }.buttonStyle(.borderedProminent).tint(Neon.magenta)
        }.padding(.horizontal, 32).padding(.vertical, 18)
    }
}

struct SummaryCard: View {
    @ObservedObject var model: SweepModel
    var body: some View {
        HStack(spacing: 28) {
            ZStack {
                Circle().stroke(.white.opacity(0.18), lineWidth: 12)
                Circle().trim(from: 0, to: model.totalBytes > 0 ? 0.78 : 0.02).stroke(AngularGradient(colors: [Neon.cyan, Neon.magenta, Neon.violet, Neon.cyan], center: .center), style: StrokeStyle(lineWidth: 12, lineCap: .round)).rotationEffect(.degrees(-90))
                VStack(spacing: 2) { Text(formatBytes(model.totalBytes)).font(.system(size: 27, weight: .bold, design: .rounded)); Text("to review").font(.caption).opacity(0.8) }
            }.frame(width: 124, height: 124)
            VStack(alignment: .leading, spacing: 8) {
                Text(model.isScanning ? "Scanning your Mac" : model.items.isEmpty ? "Your Mac is looking tidy" : "Your Mac has room to reclaim")
                    .font(.title2.weight(.bold))
                Text(model.message).foregroundStyle(.white.opacity(0.78))
                if let date = model.lastScan { Text("Last checked \(date.formatted(date: .omitted, time: .shortened))").font(.caption).foregroundStyle(.white.opacity(0.58)) }
            }
            Spacer()
            Image(systemName: "macbook.gen2").font(.system(size: 64)).opacity(0.28)
        }.padding(28).foregroundStyle(.white).background {
            ZStack {
                LinearGradient(colors: [Color(red: 0.17, green: 0.04, blue: 0.28), Color(red: 0.04, green: 0.18, blue: 0.3)], startPoint: .topLeading, endPoint: .bottomTrailing)
                Image(systemName: "hexagon.grid.3x3.fill").font(.system(size: 280)).foregroundStyle(.white.opacity(0.035)).rotationEffect(.degrees(12)).offset(x: 300, y: 20)
                Rectangle().fill(LinearGradient(colors: [.clear, Neon.magenta.opacity(0.65), .clear], startPoint: .leading, endPoint: .trailing)).frame(height: 1).offset(y: 48)
            }.clipShape(RoundedRectangle(cornerRadius: 18))
        }.sweepGlass(tint: Neon.magenta, radius: 18)
    }
}

struct StorageStrip: View {
    @ObservedObject var model: SweepModel
    var body: some View {
        let storage = model.storage
        let usedRatio = storage.total > 0 ? Double(storage.used) / Double(storage.total) : 0
        HStack(spacing: 18) {
            Image(systemName: "internaldrive.fill").font(.title3).foregroundStyle(Neon.cyan)
            VStack(alignment: .leading, spacing: 7) {
                HStack {
                    Text("STORAGE STATUS").font(.system(size: 11, weight: .bold, design: .monospaced)).tracking(1)
                    Spacer()
                    Text("\(formatBytes(storage.free)) free").font(.caption.monospacedDigit()).foregroundStyle(Neon.acid)
                }
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(.white.opacity(0.08))
                        Capsule().fill(LinearGradient(colors: [Neon.cyan, Neon.violet, Neon.magenta], startPoint: .leading, endPoint: .trailing)).frame(width: max(8, proxy.size.width * min(1, usedRatio)))
                    }
                }.frame(height: 7)
            }
            Text("\(formatBytes(storage.used)) / \(formatBytes(storage.total))").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
        }.padding(.horizontal, 16).padding(.vertical, 12).sweepGlass(tint: Neon.cyan, radius: 12)
    }
}

struct SmartCareRoutines: View {
    @ObservedObject var model: SweepModel
    private var secureChecks: Int { model.protectionChecks.filter { if case .secure = $0.state { return true }; return false }.count }
    private var duplicateCount: Int { model.items.filter { $0.category == .duplicates }.count }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("SMART CARE // FIVE ROUTINES").font(.system(size: 15, weight: .black, design: .rounded)).tracking(1)
                    Text("One overview for cleanup, protection, performance, updates, and clutter.").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Text("LOCAL ONLY").font(.system(size: 10, weight: .bold, design: .monospaced)).foregroundStyle(Neon.acid)
            }
            HStack(spacing: 12) {
                RoutineCard(icon: "sparkles", title: "CLEANUP", value: formatBytes(model.totalBytes), detail: "reviewable", tint: Neon.magenta)
                RoutineCard(icon: "shield.checkered", title: "PROTECTION", value: "\(secureChecks)/5", detail: "checks secure", tint: Neon.acid)
                RoutineCard(icon: "gauge.with.dots.needle.67percent", title: "PERFORMANCE", value: "\(model.items.filter { $0.category == .startupItems }.count)", detail: "login items", tint: Neon.cyan)
                RoutineCard(icon: "arrow.down.circle", title: "UPDATES", value: "MANUAL", detail: "system-owned", tint: Neon.violet)
                RoutineCard(icon: "square.on.square", title: "CLUTTER", value: "\(duplicateCount)", detail: "duplicates", tint: Neon.magenta)
            }
        }
    }
}

struct RoutineCard: View {
    let icon: String
    let title: String
    let value: String
    let detail: String
    let tint: Color
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: icon).foregroundStyle(tint)
            Text(title).font(.system(size: 9, weight: .bold, design: .monospaced)).foregroundStyle(.secondary)
            Text(value).font(.headline.weight(.bold)).lineLimit(1).minimumScaleFactor(0.7)
            Text(detail).font(.caption2).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity, alignment: .leading).padding(13).sweepGlass(tint: tint, radius: 12)
    }
}

struct PerformancePanel: View {
    @ObservedObject var model: SweepModel
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("PERFORMANCE // SYSTEM PULSE").font(.system(size: 16, weight: .black, design: .rounded)).tracking(1)
            HStack(spacing: 14) {
                StatusTile(icon: "power", title: "LOGIN ITEMS", value: "\(model.items.filter { $0.category == .startupItems }.count)", detail: "reviewable startup agents", tint: Neon.magenta)
                StatusTile(icon: "memorychip", title: "MEMORY", value: formatBytes(Int64(ProcessInfo.processInfo.physicalMemory)), detail: "installed capacity", tint: Neon.cyan)
                StatusTile(icon: "bolt.fill", title: "MAINTENANCE", value: "READY", detail: "safe local checks available", tint: Neon.acid)
            }
            Text("Performance tools are review-first. Nothing is disabled or changed without an explicit selection.").font(.caption).foregroundStyle(.secondary)
        }
    }
}

struct ProtectionPanel: View {
    @ObservedObject var model: SweepModel
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("PROTECTION // LOCAL CHECKS").font(.system(size: 16, weight: .black, design: .rounded)).tracking(1)
                    Text("A transparent safety dashboard, not a fake malware promise.").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button { model.runProtectionChecks() } label: {
                    Label(model.isCheckingProtection ? "CHECKING..." : "RUN CHECKS", systemImage: "arrow.clockwise")
                }.buttonStyle(.borderedProminent).tint(Neon.cyan).disabled(model.isCheckingProtection)
            }
            if model.protectionChecks.isEmpty && !model.isCheckingProtection {
                ProtectionRow(icon: "shield.checkered", title: "No check results yet", detail: "Run the local checks to inspect your current security posture.", tint: Neon.cyan)
                    .padding(14).sweepGlass(tint: Neon.cyan, radius: 14)
            } else {
                VStack(spacing: 0) {
                    ForEach(model.protectionChecks) { check in
                        ProtectionCheckRow(check: check)
                        if check.id != model.protectionChecks.last?.id { Divider() }
                    }
                }.sweepGlass(tint: Neon.cyan, radius: 14)
            }
        }
    }
}

struct ProtectionCheckRow: View {
    let check: ProtectionCheck
    private var tint: Color {
        switch check.state { case .secure: Neon.acid; case .attention: Neon.magenta; case .unavailable: .secondary }
    }
    private var status: String {
        switch check.state { case .secure: "SECURE"; case .attention: "REVIEW"; case .unavailable: "UNKNOWN" }
    }
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: check.icon).foregroundStyle(tint).frame(width: 24)
            VStack(alignment: .leading, spacing: 3) { Text(check.title).font(.callout.weight(.semibold)); Text(check.detail).font(.caption).foregroundStyle(.secondary).lineLimit(2) }
            Spacer()
            Text(status).font(.system(size: 10, weight: .bold, design: .monospaced)).foregroundStyle(tint)
        }.padding(14)
    }
}

struct StatusTile: View {
    let icon: String
    let title: String
    let value: String
    let detail: String
    let tint: Color
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: icon).foregroundStyle(tint)
            Text(title).font(.system(size: 10, weight: .bold, design: .monospaced)).foregroundStyle(.secondary)
            Text(value).font(.title3.weight(.bold).monospacedDigit())
            Text(detail).font(.caption2).foregroundStyle(.secondary).lineLimit(2)
        }.frame(maxWidth: .infinity, alignment: .leading).padding(16).sweepGlass(tint: tint, radius: 14)
    }
}

struct ProtectionRow: View {
    let icon: String
    let title: String
    let detail: String
    let tint: Color
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon).foregroundStyle(tint).frame(width: 24)
            VStack(alignment: .leading, spacing: 3) { Text(title).font(.callout.weight(.semibold)); Text(detail).font(.caption).foregroundStyle(.secondary) }
            Spacer()
        }.padding(14)
    }
}

struct SpaceLensPanel: View {
    @ObservedObject var model: SweepModel
    private var groups: [(String, Int64, Color)] {
        let totals = Dictionary(grouping: model.items, by: { $0.category }).map { ($0.key.rawValue, $0.value.reduce(0) { $0 + $1.bytes }) }
        return totals.sorted { $0.1 > $1.1 }.map { item in
            let tint: Color = item.0 == SweepCategory.applications.rawValue ? Neon.magenta : item.0 == SweepCategory.systemJunk.rawValue ? Neon.cyan : Neon.violet
            return (item.0, item.1, tint)
        }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("SPACE LENS // IMPACT MAP").font(.system(size: 16, weight: .black, design: .rounded)).tracking(1)
                    Text("Ranked from the files Mac Sweep has already inspected.").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "scope").font(.system(size: 32)).foregroundStyle(Neon.cyan)
            }
            if groups.isEmpty {
                Text("Run Smart Scan to map your storage.").foregroundStyle(.secondary).padding(24)
            } else {
                ForEach(groups, id: \.0) { group in
                    HStack(spacing: 12) {
                        Image(systemName: "circle.fill").font(.caption2).foregroundStyle(group.2)
                        Text(group.0).font(.callout.weight(.semibold))
                        Spacer()
                        Text(formatBytes(group.1)).font(.callout.monospacedDigit()).foregroundStyle(group.2)
                    }.padding(.vertical, 6)
                }
            }
        }.padding(20).sweepGlass(tint: Neon.cyan, radius: 16)
    }
}

struct MyClutterPanel: View {
    @ObservedObject var model: SweepModel
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("MY CLUTTER // REVIEW QUEUE").font(.system(size: 16, weight: .black, design: .rounded)).tracking(1)
            Text("A focused view of large, old, and duplicate files. Nothing here is selected without your review.").font(.caption).foregroundStyle(.secondary)
            HStack(spacing: 12) {
                RoutineCard(icon: "externaldrive", title: "LARGE / OLD", value: formatBytes(model.items.filter { $0.category == .largeFiles }.reduce(0) { $0 + $1.bytes }), detail: "reviewable", tint: Neon.violet)
                RoutineCard(icon: "square.on.square", title: "DUPLICATES", value: formatBytes(model.items.filter { $0.category == .duplicates }.reduce(0) { $0 + $1.bytes }), detail: "safe candidates", tint: Neon.magenta)
            }
        }
    }
}

struct MaintenancePanel: View {
    @ObservedObject var model: SweepModel
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("MAINTENANCE // READ-ONLY RECOMMENDATIONS").font(.system(size: 16, weight: .black, design: .rounded)).tracking(1)
            Text("These checks do not change your Mac. Maintenance actions will only be added after they can be verified and reversed.").font(.caption).foregroundStyle(.secondary)
            VStack(spacing: 0) {
                ProtectionRow(icon: "checkmark.circle", title: "Review login items", detail: "Open the Login Items module to inspect user launch agents.", tint: Neon.cyan)
                Divider()
                ProtectionRow(icon: "arrow.clockwise", title: "Rescan stale inventory", detail: "Refresh the local file and application inventory before acting.", tint: Neon.acid)
                Divider()
                ProtectionRow(icon: "doc.text.magnifyingglass", title: "Inspect before cleanup", detail: "Every candidate remains visible with its full path and size.", tint: Neon.magenta)
            }.sweepGlass(tint: Neon.cyan, radius: 14)
        }
    }
}

struct UpdaterPanel: View {
    @ObservedObject var model: SweepModel
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("UPDATER // INSTALLED APPS").font(.system(size: 16, weight: .black, design: .rounded)).tracking(1)
                    Text("Versions are read locally. No app is downloaded or changed.").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Text("\(model.installedApps.count) APPS").font(.system(size: 10, weight: .bold, design: .monospaced)).foregroundStyle(Neon.cyan)
            }
            VStack(spacing: 0) {
                ForEach(model.installedApps) { app in
                    HStack(spacing: 12) {
                        Image(nsImage: NSWorkspace.shared.icon(forFile: app.url.path)).resizable().frame(width: 30, height: 30)
                        VStack(alignment: .leading, spacing: 2) { Text(app.name).font(.callout.weight(.semibold)); Text(app.url.path).font(.caption2).foregroundStyle(.secondary).lineLimit(1) }
                        Spacer()
                        Text("v\(app.version)").font(.caption.monospacedDigit()).foregroundStyle(Neon.cyan)
                    }.padding(12)
                    if app.id != model.installedApps.last?.id { Divider() }
                }
            }.sweepGlass(tint: Neon.cyan, radius: 14)
        }
    }
}

struct UninstallerNotice: View {
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Neon.magenta)
            VStack(alignment: .leading, spacing: 3) {
                Text("UNINSTALLER MODE").font(.system(size: 11, weight: .bold, design: .monospaced)).foregroundStyle(Neon.magenta)
                Text("Apps are never selected automatically. Choose an app, review it, then move it to Trash.").font(.caption).foregroundStyle(.secondary)
            }
        }.padding(14).sweepGlass(tint: Neon.magenta, radius: 12)
    }
}

struct ResultsHeader: View {
    @ObservedObject var model: SweepModel
    @Binding var showAll: Bool
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) { Text("REVIEW ITEMS").font(.system(size: 16, weight: .black, design: .rounded)).tracking(1); Text("Choose what you want to move to Trash").font(.subheadline).foregroundStyle(.secondary) }
            Spacer()
            Button(showAll ? "Show less" : "Show all") { showAll.toggle() }.buttonStyle(.plain).foregroundStyle(Color.accentColor)
            Button("SELECT ALL") { model.toggleAll() }.buttonStyle(.bordered).tint(Neon.cyan)
        }
    }
}

struct ResultsList: View {
    @ObservedObject var model: SweepModel
    let items: [SweepItem]
    var body: some View {
        VStack(spacing: 0) {
            ForEach(items) { item in
                HStack(spacing: 12) {
                    Toggle("", isOn: Binding(get: { model.selectedIDs.contains(item.id) }, set: { selected in if selected { model.selectedIDs.insert(item.id) } else { model.selectedIDs.remove(item.id) } })).labelsHidden().toggleStyle(.checkbox)
                    Image(nsImage: NSWorkspace.shared.icon(forFile: item.url.path)).resizable().frame(width: 28, height: 28)
                    VStack(alignment: .leading, spacing: 2) { Text(item.name).lineLimit(1); Text(item.url.deletingLastPathComponent().path).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
                    Spacer()
                    Text(formatBytes(item.bytes)).font(.callout.monospacedDigit()).foregroundStyle(.secondary)
                }.padding(.vertical, 10).padding(.horizontal, 14)
                Divider().padding(.leading, 82)
            }
        }.sweepGlass(tint: Neon.violet, radius: 12)
    }
}

struct EmptyState: View {
    @ObservedObject var model: SweepModel
    var body: some View { VStack(spacing: 12) { Image(systemName: "checkmark.circle").font(.system(size: 44)).foregroundStyle(Neon.acid); Text("NOTHING TO CLEAN").font(.system(size: 18, weight: .black, design: .rounded)); Text("Run another scan whenever you want to check again.").foregroundStyle(.secondary); Button("SCAN AGAIN") { model.scan() }.buttonStyle(.borderedProminent).tint(Neon.magenta) }.frame(maxWidth: .infinity).padding(70).sweepGlass(tint: Neon.acid, radius: 16) }
}

struct Footer: View {
    @ObservedObject var model: SweepModel
    @Binding var showConfirmation: Bool
    var body: some View { HStack { HStack(spacing: 8) { Circle().fill(Neon.acid).frame(width: 7, height: 7); Text("\(model.selectedItems.count) SELECTED // \(formatBytes(model.selectedBytes))").font(.system(size: 11, weight: .bold, design: .monospaced)).foregroundStyle(.secondary) }; Spacer(); Button { showConfirmation = true } label: { Label(model.isCleaning ? "CLEANING..." : "REVIEW AND CLEAN", systemImage: "bolt.fill") }.buttonStyle(.borderedProminent).tint(Neon.magenta).disabled(model.selectedItems.isEmpty || model.isCleaning) }.padding(.horizontal, 32).padding(.vertical, 16).background(Neon.midnight.opacity(0.9)) }
}

func formatBytes(_ bytes: Int64) -> String {
    ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
}
