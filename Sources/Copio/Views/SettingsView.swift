import SwiftUI
import AppKit
import Sparkle

struct SettingsView: View {
    let model: AppModel
    let updater: SPUUpdater
    let initialTab: Int
    let updateHotkey: () -> Void
    let previewSearch: () -> Void
    let resize: (CGFloat) -> Void
    @State private var tab = 0
    @State private var clearConfirmation = false
    @State private var resetConfirmation = false
    @State private var newCollectionName = ""
    @State private var editingCollectionID: UUID?
    @State private var renameName = ""
    @State private var collectionToDelete: ClipCollection?
    @State private var secretToDelete: SecureItem?
    @State private var revealedSecrets: [UUID: String] = [:]
    @State private var checkingUpdates = false
    @State private var updateStatusMessage: String?
    private let sections: [(String, String)] = [
        ("General", "gearshape"), ("Clipboard", "doc.on.clipboard"), ("Collections", "folder"),
        ("Shortcuts", "keyboard"), ("Security", "lock.shield"), ("Appearance", "paintbrush"),
        ("Advanced", "wrench.and.screwdriver")
    ]
    private let sectionHeights: [CGFloat] = [390, 405, 300, 350, 495, 245, 385]

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 2) {
                ForEach(sections.indices, id: \.self) { index in
                    Button { tab = index } label: {
                        VStack(spacing: 3) {
                            Image(systemName: sections[index].1).font(.system(size: 13, weight: .medium))
                            Text(sections[index].0).font(.system(size: 10, weight: tab == index ? .semibold : .medium))
                        }
                        .foregroundStyle(tab == index ? Color.accentColor : Color.secondary)
                        .frame(maxWidth: .infinity).frame(height: 43)
                        .background(tab == index ? Color.accentColor.opacity(0.12) : Color.clear, in: RoundedRectangle(cornerRadius: 7))
                    }.buttonStyle(.plain)
                }
            }.padding(.horizontal, 10).padding(.vertical, 8)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 9) {
                    HStack(spacing: 6) {
                        Image(systemName: sections[tab].1).foregroundStyle(.tint)
                        Text(sections[tab].0).font(.system(size: 13, weight: .semibold))
                    }
                    selectedForm
                        .toggleStyle(SettingsTrailingSwitchStyle())
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                        .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 9))
                }
                .padding(.horizontal, 16).padding(.vertical, 12)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        }
        .frame(width: 640, height: sectionHeights[tab])
        .onAppear { tab = initialTab; resize(sectionHeights[initialTab]) }
        .onChange(of: tab) { _, value in resize(sectionHeights[value]) }
        .onDisappear { revealedSecrets.removeAll() }
        .controlSize(.small)
        .preferredColorScheme(model.settings.colorScheme)
        .alert("Clear all clipboard history?", isPresented: $clearConfirmation) {
            Button("Clear History", role: .destructive) { model.clearHistory() }
            Button("Cancel", role: .cancel) {}
        } message: { Text("This removes regular clipboard items. Saved secrets remain.") }
        .alert("Reset Copio?", isPresented: $resetConfirmation) {
            Button("Reset Application", role: .destructive) { model.resetApplication(); updateHotkey() }
            Button("Cancel", role: .cancel) {}
        } message: { Text("This permanently removes history, collections, saved secrets, and settings.") }
        .alert("Copio", isPresented: Binding(get: { model.alertMessage != nil }, set: { if !$0 { model.alertMessage = nil } })) {
            Button("OK") { model.alertMessage = nil }
        } message: { Text(model.alertMessage ?? "") }
        .confirmationDialog("Delete collection?", isPresented: Binding(get: { collectionToDelete != nil }, set: { if !$0 { collectionToDelete = nil } })) {
            Button("Delete Collection", role: .destructive) {
                if let collectionToDelete { model.deleteCollection(collectionToDelete) }
                collectionToDelete = nil
            }
            Button("Cancel", role: .cancel) { collectionToDelete = nil }
        } message: { Text("Items in this collection will remain in clipboard history.") }
        .confirmationDialog("Delete saved password?", isPresented: Binding(get: { secretToDelete != nil }, set: { if !$0 { secretToDelete = nil } })) {
            Button("Delete Password", role: .destructive) {
                if let secretToDelete { model.deleteSecret(secretToDelete) }
                secretToDelete = nil
            }
            Button("Cancel", role: .cancel) { secretToDelete = nil }
        } message: { Text("This removes the saved value from Keychain.") }
    }

    @ViewBuilder private var selectedForm: some View {
        switch tab {
        case 0:
            VStack(alignment: .leading, spacing: 12) {
                Toggle("Launch at Login", isOn: Bindable(model.settings).launchAtLogin)
                    .onChange(of: model.settings.launchAtLogin) { _, _ in model.syncLaunchAtLogin() }
                Toggle("Show Menu Bar icon", isOn: Bindable(model.settings).showMenuBarIcon)
                    .disabled(!model.shortcutAvailable && model.settings.showMenuBarIcon)
                Toggle("Show notifications", isOn: Bindable(model.settings).showNotifications)
                    .onChange(of: model.settings.showNotifications) { _, enabled in
                        if enabled {
                            Task {
                                if !(await NotificationService.requestPermission()) {
                                    model.settings.showNotifications = false
                                    model.alertMessage = "Notifications were not enabled in System Settings."
                                }
                            }
                        }
                    }
                Text("Copio lives in your Menu Bar. Your clipboard stays on this Mac.").foregroundStyle(.secondary)
                Divider()
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Copio \(versionLabel)").font(.system(size: 12, weight: .semibold))
                        Text("by Bes-js · Updates from GitHub").font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button(checkingUpdates ? "Checking…" : "Check for Updates…") {
                        Task { await checkForUpdates() }
                    }
                    .disabled(checkingUpdates)
                }
                if let updateStatusMessage {
                    Text(updateStatusMessage).font(.system(size: 11)).foregroundStyle(.secondary)
                }
                Toggle("Check for updates automatically", isOn: Binding(
                    get: { updater.automaticallyChecksForUpdates },
                    set: { updater.automaticallyChecksForUpdates = $0 }
                ))
                Toggle("Download and install updates automatically", isOn: Binding(
                    get: { updater.automaticallyDownloadsUpdates },
                    set: { updater.automaticallyDownloadsUpdates = $0 }
                ))
                .disabled(!updater.automaticallyChecksForUpdates)
            }
        case 1:
            VStack(alignment: .leading, spacing: 12) {
                Toggle("Enable clipboard monitoring", isOn: Bindable(model.settings).monitorEnabled)
                    .onChange(of: model.settings.monitorEnabled) { _, _ in model.syncMonitoring() }
                Toggle("Capture images", isOn: Bindable(model.settings).captureImages)
                Toggle("Capture files", isOn: Bindable(model.settings).captureFiles)
                Toggle("Ignore consecutive duplicates", isOn: Bindable(model.settings).ignoreDuplicates)
                HStack {
                    Text("Maximum clipboard history")
                    Spacer()
                    Picker("", selection: Bindable(model.settings).historyLimit) {
                        ForEach(HistoryLimit.allCases) { limit in Text(limit.label).tag(limit.rawValue) }
                    }
                    .labelsHidden().pickerStyle(.menu).frame(width: 145)
                    .onChange(of: model.settings.historyLimit) { _, _ in model.cleanup() }
                }
                HStack {
                    Text("Automatically remove items after")
                    Spacer()
                    Picker("", selection: Bindable(model.settings).cleanupDays) {
                        Text("Never").tag(0); Text("1 day").tag(1); Text("7 days").tag(7); Text("30 days").tag(30); Text("90 days").tag(90)
                    }
                    .labelsHidden().pickerStyle(.menu).frame(width: 145)
                    .onChange(of: model.settings.cleanupDays) { _, _ in model.cleanup() }
                }
                Toggle("Keep favorites forever", isOn: Bindable(model.settings).keepFavorites)
                Toggle("Keep collection items", isOn: Bindable(model.settings).keepCollections)
            }
        case 2:
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    TextField("New collection name", text: $newCollectionName)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit(addCollection)
                    Button("Add Collection", action: addCollection)
                        .disabled(newCollectionName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                if model.collections.isEmpty {
                    Label("No collections yet", systemImage: "folder")
                        .foregroundStyle(.secondary).padding(.vertical, 12)
                }
                ForEach(model.collections) { collection in
                    collectionRow(collection)
                    if collection.id != model.collections.last?.id { Divider() }
                }
                Text("Use the folder button in search to add an item to a collection.")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }
        case 3:
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Open Clipboard")
                    Spacer()
                    ShortcutRecorder(keyCode: Bindable(model.settings).shortcutKeyCode,
                                     modifiers: Bindable(model.settings).shortcutModifiers,
                                     keyLabel: Bindable(model.settings).shortcutKeyLabel,
                                     onChange: updateHotkey)
                }
                Text("Click the shortcut, then press a key with ⌘, ⌥, or ⌃. Esc cancels.").font(.system(size: 11)).foregroundStyle(.secondary)
                Button("Preview Quick Search") { previewSearch() }
                if !model.shortcutAvailable { Text("This shortcut is unavailable. Choose another combination.").foregroundStyle(.red) }
                Toggle("Paste selected item on Return", isOn: Bindable(model.settings).pasteOnReturn)
                Text("Automatic paste requires Accessibility access. Copy remains available without it.").foregroundStyle(.secondary)
                Button("Open Accessibility Settings") { NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!) }
            }
        case 4:
            VStack(alignment: .leading, spacing: 12) {
                Toggle("Detect sensitive clipboard content", isOn: Bindable(model.settings).detectSensitive)
                Toggle("Require Mac authentication to access secrets", isOn: Bindable(model.settings).requireAuthentication)
                HStack {
                    Text("Clear sensitive clipboard after")
                    Spacer()
                    Picker("", selection: Bindable(model.settings).secretClearSeconds) {
                        Text("10 seconds").tag(10); Text("30 seconds").tag(30); Text("60 seconds").tag(60); Text("5 minutes").tag(300); Text("Never").tag(0)
                    }
                    .labelsHidden().pickerStyle(.menu).frame(width: 145)
                }
                Text("Never capture from these applications (bundle IDs, one per line)")
                TextEditor(text: Bindable(model.settings).excludedBundleIDs)
                    .font(.system(size: 11, design: .monospaced)).frame(height: 72)
                    .scrollContentBackground(.hidden)
                    .padding(5).background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 6))
                Text("Exclusions use the apps active during clipboard detection. Background copies cannot always be attributed to an app.").font(.caption).foregroundStyle(.secondary)
                Text("Detected secrets are held in memory until you choose Store Securely, Keep Temporarily, or Ignore. Saved values use Keychain.").foregroundStyle(.secondary)
                Divider()
                Text("Saved passwords (\(model.secrets.count))").font(.system(size: 12, weight: .semibold))
                if model.secrets.isEmpty {
                    Text("No saved passwords yet.").foregroundStyle(.secondary)
                }
                ForEach(model.secrets, id: \.id) { secret in
                    secretRow(secret)
                    Divider()
                }
            }
        case 5:
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Appearance")
                    Spacer()
                    Picker("", selection: Bindable(model.settings).appearance) {
                        Text("Follow System").tag("system"); Text("Light").tag("light"); Text("Dark").tag("dark")
                    }
                    .labelsHidden().pickerStyle(.menu).frame(width: 145)
                }
            }
        default:
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Database").fontWeight(.medium)
                    Text(model.database.directory.appendingPathComponent("history.sqlite3").path)
                        .font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary)
                        .lineLimit(2).textSelection(.enabled)
                }
                Button("Reveal Data Folder") { NSWorkspace.shared.open(model.database.directory) }
                HStack {
                    Button("Export History…") {
                        let panel = NSSavePanel()
                        panel.nameFieldStringValue = "Copio Export.clipcollections"
                        if panel.runModal() == .OK, let url = panel.url { model.exportHistory(to: url) }
                    }
                    Button("Import History…") {
                        let panel = NSOpenPanel()
                        panel.canChooseDirectories = true
                        panel.canChooseFiles = false
                        if panel.runModal() == .OK, let url = panel.url { model.importHistory(from: url) }
                    }
                }
                Divider()
                HStack {
                    Button("Clear History", role: .destructive) { clearConfirmation = true }
                    Button("Reset Application…", role: .destructive) { resetConfirmation = true }
                }
                Text("Saved secrets remain in Keychain when history is cleared.").foregroundStyle(.secondary)
            }
        }
    }

    private var versionLabel: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
        return "\(version) (\(build))"
    }

    private func checkForUpdates() async {
        checkingUpdates = true
        updateStatusMessage = nil
        defer { checkingUpdates = false }
        do {
            switch try await GitHubReleaseService.latestStatus() {
            case .available:
                updateStatusMessage = nil
                updater.checkForUpdates()
            case .noRelease:
                updateStatusMessage = "No public Copio release is available on Bes-js/Copio yet."
            case .missingAppcast:
                updateStatusMessage = "The latest GitHub release does not include an appcast.xml update feed."
            }
        } catch {
            updateStatusMessage = "Could not reach GitHub to check for updates. Try again later."
        }
    }

    private func addCollection() {
        let name = newCollectionName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        model.addCollection(name: name)
        newCollectionName = ""
    }

    private func collectionRow(_ collection: ClipCollection) -> some View {
        HStack(spacing: 10) {
            Image(systemName: collection.symbol).foregroundStyle(collection.tint).frame(width: 20)
            if editingCollectionID == collection.id {
                TextField("Collection name", text: $renameName)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { saveCollectionName(collection) }
                Button("Save") { saveCollectionName(collection) }
                Button("Cancel") { editingCollectionID = nil }
            } else {
                Text(collection.name)
                Spacer()
                Menu {
                    Button("Rename…") { renameName = collection.name; editingCollectionID = collection.id }
                    Menu("Icon") {
                        ForEach(["folder", "briefcase", "person", "hammer", "chevron.left.forwardslash.chevron.right", "link", "star", "paintbrush"], id: \.self) { symbol in
                            Button { var updated = collection; updated.symbol = symbol; model.saveCollection(updated) } label: {
                                Label(symbol, systemImage: symbol)
                            }
                        }
                    }
                    Menu("Color") {
                        ForEach(["blue", "green", "orange", "purple", "pink", "gray"], id: \.self) { color in
                            Button(color.capitalized) { var updated = collection; updated.color = color; model.saveCollection(updated) }
                        }
                    }
                    Button("Move Up") { model.moveCollection(collection, by: -1) }
                    Button("Move Down") { model.moveCollection(collection, by: 1) }
                    Divider()
                    Button("Delete", role: .destructive) { collectionToDelete = collection }
                } label: { Image(systemName: "ellipsis") }.menuStyle(.borderlessButton).frame(width: 28)
            }
        }
        .font(.system(size: 12))
        .frame(height: 28)
    }

    private func saveCollectionName(_ collection: ClipCollection) {
        let name = renameName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        var updated = collection
        updated.name = name
        model.saveCollection(updated)
        editingCollectionID = nil
    }

    private func secretRow(_ secret: SecureItem) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "lock.fill").foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 3) {
                Text(secret.title).fontWeight(.medium)
                Text(revealedSecrets[secret.id] ?? "••••••••••••")
                    .font(.system(size: 11, design: .monospaced))
                    .textSelection(.enabled)
                HStack(spacing: 4) {
                    if let source = secret.sourceApp {
                        SourceAppIcon(name: source, bundleID: secret.sourceBundleID, size: 11)
                        Text("Copied from \(source)")
                    } else {
                        Text("Source unknown")
                    }
                }.font(.system(size: 10)).foregroundStyle(.secondary)
            }
            Spacer()
            Button(revealedSecrets[secret.id] == nil ? "Reveal" : "Hide") {
                if revealedSecrets[secret.id] != nil { revealedSecrets[secret.id] = nil }
                else {
                    Task {
                        revealedSecrets[secret.id] = await model.revealSecret(secret)
                        try? await Task.sleep(for: .seconds(30))
                        revealedSecrets[secret.id] = nil
                    }
                }
            }
            Button("Copy") { Task { await model.copySecret(secret) } }
            Button { secretToDelete = secret } label: { Image(systemName: "trash") }
                .help("Delete password")
        }.padding(.vertical, 5)
    }
}

private struct SettingsTrailingSwitchStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack {
            configuration.label
            Spacer()
            Toggle(isOn: configuration.$isOn) { EmptyView() }
                .labelsHidden()
                .toggleStyle(.switch)
        }
    }
}

struct ShortcutRecorder: NSViewRepresentable {
    @Binding var keyCode: Int
    @Binding var modifiers: Int
    @Binding var keyLabel: String
    let onChange: () -> Void

    func makeNSView(context: Context) -> ShortcutCaptureButton {
        ShortcutCaptureButton(frame: .zero)
    }

    func updateNSView(_ button: ShortcutCaptureButton, context: Context) {
        button.shortcutTitle = display
        button.onCapture = { key, flags, label in
            keyCode = key
            modifiers = flags
            keyLabel = label
            onChange()
        }
        if !button.isRecording { button.title = display }
    }

    static func dismantleNSView(_ button: ShortcutCaptureButton, coordinator: ()) {
        button.stopRecording()
    }

    private var display: String {
        var parts = ""
        if modifiers & 256 != 0 { parts += "⌘" }
        if modifiers & 512 != 0 { parts += "⇧" }
        if modifiers & 2048 != 0 { parts += "⌥" }
        if modifiers & 4096 != 0 { parts += "⌃" }
        return parts + keyLabel
    }
}

@MainActor final class ShortcutCaptureButton: NSButton {
    var shortcutTitle = ""
    var onCapture: ((Int, Int, String) -> Void)?
    private(set) var isRecording = false
    private var keyMonitor: Any?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        bezelStyle = .rounded
        font = .systemFont(ofSize: 12, weight: .semibold)
        target = self
        action = #selector(toggleRecording)
    }

    required init?(coder: NSCoder) {
        fatalError("ShortcutCaptureButton does not use Interface Builder")
    }

    override var acceptsFirstResponder: Bool { true }

    @objc private func toggleRecording() {
        if isRecording {
            stopRecording()
            return
        }
        isRecording = true
        title = "Press keys…"
        window?.makeFirstResponder(self)
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.isRecording else { return event }
            guard event.window === self.window, self.window?.isKeyWindow == true else {
                self.stopRecording()
                return event
            }
            self.capture(event)
            return nil
        }
    }

    func stopRecording() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
        isRecording = false
        title = shortcutTitle
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow == nil { stopRecording() }
        super.viewWillMove(toWindow: newWindow)
    }

    override func keyDown(with event: NSEvent) {
        if isRecording { capture(event) }
        else { super.keyDown(with: event) }
    }

    private func capture(_ event: NSEvent) {
        if event.keyCode == 53 {
            stopRecording()
            return
        }
        let flags = event.modifierFlags
        var carbon = 0
        if flags.contains(.command) { carbon |= 256 }
        if flags.contains(.shift) { carbon |= 512 }
        if flags.contains(.option) { carbon |= 2048 }
        if flags.contains(.control) { carbon |= 4096 }
        guard carbon & (256 | 2048 | 4096) != 0 else {
            title = "Use ⌘, ⌥, or ⌃"
            NSSound.beep()
            return
        }
        let special: [UInt16: String] = [36: "↩", 49: "Space", 51: "⌫", 53: "Esc", 123: "←", 124: "→", 125: "↓", 126: "↑",
                                         122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6", 98: "F7", 100: "F8", 101: "F9",
                                         109: "F10", 103: "F11", 111: "F12", 105: "F13", 107: "F14", 113: "F15", 106: "F16", 64: "F17", 79: "F18", 80: "F19"]
        let label = special[event.keyCode] ?? event.charactersIgnoringModifiers?.uppercased() ?? "Key \(event.keyCode)"
        stopRecording()
        onCapture?(Int(event.keyCode), carbon, label)
    }
}
