import SwiftUI

// MARK: - Appearance Mode

enum AppearanceMode: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var label: String {
        switch self {
        case .system: return "System"
        case .light:  return "Light"
        case .dark:   return "Dark"
        }
    }

    var iconName: String {
        switch self {
        case .system: return "circle.lefthalf.filled"
        case .light:  return "sun.max.fill"
        case .dark:   return "moon.fill"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light:  return .light
        case .dark:   return .dark
        }
    }

    static func from(rawValue: String) -> AppearanceMode {
        AppearanceMode(rawValue: rawValue) ?? .system
    }
}

// MARK: - App Theme

enum AppTheme: String, CaseIterable, Identifiable {
    case teal
    case midnight
    case forest
    case sunset
    case ocean

    var id: String { rawValue }

    var label: String {
        switch self {
        case .teal:     return "Teal"
        case .midnight: return "Midnight"
        case .forest:   return "Forest"
        case .sunset:   return "Sunset"
        case .ocean:    return "Ocean"
        }
    }

    var iconName: String {
        switch self {
        case .teal:     return "circle.lefthalf.filled"
        case .midnight: return "moon.stars.fill"
        case .forest:   return "leaf.fill"
        case .sunset:   return "sun.horizon.fill"
        case .ocean:    return "water.waves"
        }
    }

    var accentColor: Color {
        switch self {
        case .teal:     return .teal
        case .midnight: return .indigo
        case .forest:   return Color(red: 0.13, green: 0.62, blue: 0.30)
        case .sunset:   return Color(red: 0.95, green: 0.45, blue: 0.08)
        case .ocean:    return Color(red: 0.15, green: 0.42, blue: 0.88)
        }
    }

    static func from(rawValue: String) -> AppTheme {
        AppTheme(rawValue: rawValue) ?? .teal
    }
}

// MARK: - Environment Key

private struct AppAccentColorKey: EnvironmentKey {
    static let defaultValue: Color = .teal
}

extension EnvironmentValues {
    var appAccentColor: Color {
        get { self[AppAccentColorKey.self] }
        set { self[AppAccentColorKey.self] = newValue }
    }
}
