import AppKit
import Sparkle
import SwiftUI

@main @MainActor final class CopioApp: NSObject, NSApplicationDelegate, NSPopoverDelegate, NSWindowDelegate {
    private var model: AppModel!
    private var statusItem: NSStatusItem!
    private let popover = NSPopover()
    private var settingsWindow: NSWindow?
    private var onboardingWindow: NSWindow?
    private var quickPanel: QuickSearchPanel?
    private var hotkey: HotkeyService!
    private var updaterController: SPUStandardUpdaterController!

    static func main() {
        let application = NSApplication.shared
        let delegate = CopioApp()
        application.delegate = delegate
        application.run()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        do { model = try AppModel() }
        catch {
            NSAlert(error: error).runModal()
            NSApplication.shared.terminate(nil)
            return
        }
        NSApp.setActivationPolicy(.accessory)
        updaterController = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = NSImage(systemSymbolName: "square.on.square", accessibilityDescription: "Copio")
        statusItem.button?.action = #selector(togglePopover)
        statusItem.button?.target = self
        model.settings.onMenuBarIconChange = { [weak self] in self?.updateMenuBarIcon() }
        popover.behavior = .transient
        popover.delegate = self
        popover.contentSize = NSSize(width: 390, height: 220)
        popover.contentViewController = NSHostingController(rootView: PopoverView(model: model,
            manageCollections: { [weak self] in self?.openSettings(selectedTab: 2) },
            openSettings: { [weak self] in self?.openSettings() },
            close: { [weak self] in self?.popover.performClose(nil) },
            resize: { [weak self] height in self?.popover.contentSize = NSSize(width: 390, height: height) }))
        hotkey = HotkeyService()
        hotkey.onPress = { [weak self] in self?.toggleFromHotkey() }
        updateHotkey()
        updateMenuBarIcon()
        if !model.settings.hasCompletedOnboarding { openOnboarding() }
        else if !model.settings.launchAtLogin { showQuickSearch() }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    @objc private func togglePopover() {
        hideQuickSearch(restoreFocus: false)
        if popover.isShown { popover.performClose(nil) }
        else { showPopover() }
    }

    private func showPopover() {
        guard let button = statusItem.button else { return }
        model.previousApplication = NSWorkspace.shared.frontmostApplication
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
        NSApp.activate(ignoringOtherApps: true)
    }

    private func toggleFromHotkey() {
        if quickPanel?.isVisible == true { hideQuickSearch(restoreFocus: true) }
        else { showQuickSearch() }
    }

    private func showQuickSearch() {
        popover.performClose(nil)
        model.previousApplication = NSWorkspace.shared.frontmostApplication
        let panel: QuickSearchPanel
        if let quickPanel { panel = quickPanel }
        else {
            panel = QuickSearchPanel(contentRect: NSRect(origin: .zero, size: NSSize(width: 560, height: 430)),
                                     styleMask: [.borderless], backing: .buffered, defer: false)
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = true
            panel.isFloatingPanel = true
            panel.level = .floating
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
            panel.hidesOnDeactivate = true
            panel.isReleasedWhenClosed = false
            panel.delegate = self
            quickPanel = panel
        }
        panel.contentView = NSHostingView(rootView: QuickSearchView(
            model: model,
            choose: { [weak self] item, paste in self?.chooseQuickSearch(item, paste: paste) },
            close: { [weak self] in self?.hideQuickSearch(restoreFocus: true) },
            manageCollections: { [weak self] in self?.openSettings(selectedTab: 2) },
            openSettings: { [weak self] in self?.openSettings() },
            resize: { [weak self] height in self?.resizeQuickSearch(height: height) }
        ))
        let rowCount = min(7, model.items.count)
        let height = CGFloat(148 + (rowCount == 0 ? 96 : rowCount * 56) + (model.pendingSensitive == nil ? 0 : 94))
        let screen = NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) }) ?? NSScreen.main
        if let screen {
            let bounds = screen.visibleFrame
            panel.setFrame(NSRect(x: bounds.midX - 280, y: bounds.midY - height / 2,
                                  width: 560, height: height), display: true)
        }
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }

    private func resizeQuickSearch(height: CGFloat) {
        guard let panel = quickPanel else { return }
        let old = panel.frame
        panel.setFrame(NSRect(x: old.minX, y: old.maxY - height, width: 560, height: height), display: true)
    }

    private func chooseQuickSearch(_ item: ClipboardItem, paste: Bool) {
        hideQuickSearch(restoreFocus: !paste)
        model.copy(item, paste: paste)
    }

    private func hideQuickSearch(restoreFocus: Bool) {
        guard quickPanel?.isVisible == true else { return }
        quickPanel?.orderOut(nil)
        if restoreFocus, let previous = model.previousApplication,
           previous.bundleIdentifier != Bundle.main.bundleIdentifier {
            _ = previous.activate()
        }
    }

    func windowDidResignKey(_ notification: Notification) {
        if let window = notification.object as? NSWindow, window === quickPanel { quickPanel?.orderOut(nil) }
    }

    private func updateHotkey() {
        model.shortcutAvailable = hotkey.register(keyCode: model.settings.shortcutKeyCode, modifiers: model.settings.shortcutModifiers)
        updateMenuBarIcon()
    }

    private func updateMenuBarIcon() {
        guard statusItem != nil, model != nil else { return }
        if !model.shortcutAvailable && !model.settings.showMenuBarIcon { model.settings.showMenuBarIcon = true; return }
        statusItem.isVisible = model.settings.showMenuBarIcon
    }

    private func configure(_ window: NSWindow, title: String, size: NSSize) {
        window.title = title
        window.setContentSize(size)
        window.center()
        window.isReleasedWhenClosed = false
        window.tabbingMode = .disallowed
    }

    private func openSettings(selectedTab: Int = 0) {
        hideQuickSearch(restoreFocus: false)
        popover.performClose(nil)
        if settingsWindow == nil {
            let window = NSWindow(contentRect: NSRect(origin: .zero, size: NSSize(width: 640, height: 260)),
                                  styleMask: [.titled, .closable], backing: .buffered, defer: false)
            configure(window, title: "Copio Settings", size: NSSize(width: 640, height: 260))
            settingsWindow = window
        }
        settingsWindow?.contentView = NSHostingView(rootView: SettingsView(model: model,
            updater: updaterController.updater,
            initialTab: selectedTab,
            updateHotkey: { [weak self] in self?.updateHotkey() },
            previewSearch: { [weak self] in self?.showQuickSearch() },
            resize: { [weak self] height in self?.settingsWindow?.setContentSize(NSSize(width: 640, height: height)) }))
        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func openOnboarding() {
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: NSSize(width: 490, height: 390)),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        configure(window, title: "Welcome to Copio", size: NSSize(width: 490, height: 390))
        window.contentView = NSHostingView(rootView: OnboardingView(model: model, finish: { [weak self] in
            self?.model.settings.hasCompletedOnboarding = true
            self?.onboardingWindow?.close()
            self?.showQuickSearch()
        }))
        onboardingWindow = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

@MainActor private final class QuickSearchPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

struct OnboardingView: View {
    let model: AppModel
    let finish: () -> Void
    @State private var step = 0
    private let titles = ["Lives in your Menu Bar", "Private by design", "Open it instantly", "Choose your history size", "Protect sensitive content"]
    private let symbols = ["menubar.rectangle", "hand.raised", "keyboard", "clock.arrow.circlepath", "lock.shield"]
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: symbols[step]).font(.system(size: 44)).foregroundStyle(.tint)
            Text(titles[step]).font(.title2.weight(.semibold))
            Group {
                switch step {
                case 0: Text("Click the Copio icon to find and reuse recent clipboard items.")
                case 1: Text("Your clipboard stays on this Mac. No account, cloud service, or telemetry is used.")
                case 2: Text("Use ⌘⇧V to open your clipboard from any app. Change the shortcut in Settings.")
                case 3:
                    Picker("Maximum history", selection: Bindable(model.settings).historyLimit) {
                        ForEach(HistoryLimit.allCases) { limit in Text(limit.label).tag(limit.rawValue) }
                    }.frame(width: 240)
                default: Toggle("Detect sensitive clipboard content", isOn: Bindable(model.settings).detectSensitive)
                    .frame(width: 280)
                }
            }.multilineTextAlignment(.center).foregroundStyle(.secondary).frame(maxWidth: 350)
            Spacer()
            HStack {
                Text("\(step + 1) of 5").font(.caption).foregroundStyle(.secondary)
                Spacer()
                if step > 0 { Button("Back") { step -= 1 } }
                Button(step == 4 ? "Get Started" : "Continue") {
                    if step == 4 { finish() } else { step += 1 }
                }.buttonStyle(.borderedProminent)
            }
        }.padding(30)
    }
}
