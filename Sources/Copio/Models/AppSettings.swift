import Foundation
import SwiftUI

@MainActor @Observable final class AppSettings {
    private let defaults = UserDefaults.standard
    var monitorEnabled: Bool { didSet { defaults.set(monitorEnabled, forKey: "monitorEnabled") } }
    var showMenuBarIcon: Bool { didSet { defaults.set(showMenuBarIcon, forKey: "showMenuBarIcon"); onMenuBarIconChange?() } }
    var historyLimit: Int { didSet { defaults.set(historyLimit, forKey: "historyLimit") } }
    var cleanupDays: Int { didSet { defaults.set(cleanupDays, forKey: "cleanupDays") } }
    var keepFavorites: Bool { didSet { defaults.set(keepFavorites, forKey: "keepFavorites") } }
    var keepCollections: Bool { didSet { defaults.set(keepCollections, forKey: "keepCollections") } }
    var ignoreDuplicates: Bool { didSet { defaults.set(ignoreDuplicates, forKey: "ignoreDuplicates") } }
    var captureImages: Bool { didSet { defaults.set(captureImages, forKey: "captureImages") } }
    var captureFiles: Bool { didSet { defaults.set(captureFiles, forKey: "captureFiles") } }
    var detectSensitive: Bool { didSet { defaults.set(detectSensitive, forKey: "detectSensitive") } }
    var requireAuthentication: Bool { didSet { defaults.set(requireAuthentication, forKey: "requireAuthentication") } }
    var secretClearSeconds: Int { didSet { defaults.set(secretClearSeconds, forKey: "secretClearSeconds") } }
    var pasteOnReturn: Bool { didSet { defaults.set(pasteOnReturn, forKey: "pasteOnReturn") } }
    var excludedBundleIDs: String { didSet { defaults.set(excludedBundleIDs, forKey: "excludedBundleIDs") } }
    var appearance: String { didSet { defaults.set(appearance, forKey: "appearance") } }
    var showNotifications: Bool { didSet { defaults.set(showNotifications, forKey: "showNotifications") } }
    var launchAtLogin: Bool { didSet { defaults.set(launchAtLogin, forKey: "launchAtLogin") } }
    var shortcutKeyCode: Int { didSet { defaults.set(shortcutKeyCode, forKey: "shortcutKeyCode") } }
    var shortcutModifiers: Int { didSet { defaults.set(shortcutModifiers, forKey: "shortcutModifiers") } }
    var shortcutKeyLabel: String { didSet { defaults.set(shortcutKeyLabel, forKey: "shortcutKeyLabel") } }
    var hasCompletedOnboarding: Bool { didSet { defaults.set(hasCompletedOnboarding, forKey: "hasCompletedOnboarding") } }
    @ObservationIgnored var onMenuBarIconChange: (() -> Void)?

    init() {
        monitorEnabled = defaults.object(forKey: "monitorEnabled") as? Bool ?? true
        showMenuBarIcon = defaults.object(forKey: "showMenuBarIcon") as? Bool ?? true
        historyLimit = defaults.object(forKey: "historyLimit") as? Int ?? 250
        cleanupDays = defaults.object(forKey: "cleanupDays") as? Int ?? 0
        keepFavorites = defaults.object(forKey: "keepFavorites") as? Bool ?? true
        keepCollections = defaults.object(forKey: "keepCollections") as? Bool ?? true
        ignoreDuplicates = defaults.object(forKey: "ignoreDuplicates") as? Bool ?? true
        captureImages = defaults.object(forKey: "captureImages") as? Bool ?? true
        captureFiles = defaults.object(forKey: "captureFiles") as? Bool ?? true
        detectSensitive = defaults.object(forKey: "detectSensitive") as? Bool ?? true
        requireAuthentication = defaults.object(forKey: "requireAuthentication") as? Bool ?? true
        secretClearSeconds = defaults.object(forKey: "secretClearSeconds") as? Int ?? 30
        pasteOnReturn = defaults.object(forKey: "pasteOnReturn") as? Bool ?? false
        excludedBundleIDs = defaults.string(forKey: "excludedBundleIDs") ?? "com.agilebits.onepassword7\ncom.1password.1password\ncom.bitwarden.desktop"
        appearance = defaults.string(forKey: "appearance") ?? "system"
        showNotifications = defaults.object(forKey: "showNotifications") as? Bool ?? false
        launchAtLogin = defaults.object(forKey: "launchAtLogin") as? Bool ?? false
        shortcutKeyCode = defaults.object(forKey: "shortcutKeyCode") as? Int ?? 9 // V
        shortcutModifiers = defaults.object(forKey: "shortcutModifiers") as? Int ?? 768 // Command + Shift (Carbon)
        shortcutKeyLabel = defaults.string(forKey: "shortcutKeyLabel") ?? "V"
        hasCompletedOnboarding = defaults.object(forKey: "hasCompletedOnboarding") as? Bool ?? false
    }

    var colorScheme: ColorScheme? {
        switch appearance { case "light": .light; case "dark": .dark; default: nil }
    }

    var shortcutDisplay: String {
        var label = ""
        if shortcutModifiers & 256 != 0 { label += "⌘" }
        if shortcutModifiers & 512 != 0 { label += "⇧" }
        if shortcutModifiers & 2048 != 0 { label += "⌥" }
        if shortcutModifiers & 4096 != 0 { label += "⌃" }
        return label + shortcutKeyLabel
    }

    func resetToDefaults() {
        if let bundleID = Bundle.main.bundleIdentifier { defaults.removePersistentDomain(forName: bundleID) }
        monitorEnabled = true
        showMenuBarIcon = true
        historyLimit = 250
        cleanupDays = 0
        keepFavorites = true
        keepCollections = true
        ignoreDuplicates = true
        captureImages = true
        captureFiles = true
        detectSensitive = true
        requireAuthentication = true
        secretClearSeconds = 30
        pasteOnReturn = false
        excludedBundleIDs = "com.agilebits.onepassword7\ncom.1password.1password\ncom.bitwarden.desktop"
        appearance = "system"
        showNotifications = false
        launchAtLogin = false
        shortcutKeyCode = 9
        shortcutModifiers = 768
        shortcutKeyLabel = "V"
        hasCompletedOnboarding = false
    }
}
