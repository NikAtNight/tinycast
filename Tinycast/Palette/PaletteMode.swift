import AppKit

enum PaletteMode: String, CaseIterable, Identifiable {
    case launcher
    case clipboard
    case ai
    case aiHistory
    case calculatorHistory
    case emoji
    case fileSearch
    case menuSearch
    case switchWindows
    case schedule
    case uninstall
    case quicklinks
    case snippets
    case dictionary
    /// Collects a custom command's positional arguments, held on its own session.
    case customCommandArguments
    /// A Raycast extension command rendering into the palette.
    case extensionCommand
    /// A quicklink collecting its `{argument}` values, one per search-field entry.
    case quicklinkArguments
    case ports

    case repos
    case talix

    case inbox
    case clipShareRecent

    case kleioRecordings
    case spotify

    var id: String { rawValue }

    /// One value at a time into the search field, so ↵ still acts with no rows to select.
    var isArgumentForm: Bool { self == .customCommandArguments || self == .quicklinkArguments }
    var systemImage: String {
        switch self {
        case .launcher: return "magnifyingglass"
        case .clipboard: return "doc.on.doc"
        case .ai: return "sparkles"
        case .aiHistory: return "clock.arrow.circlepath"
        case .calculatorHistory: return "plus.forwardslash.minus"
        case .emoji: return "face.smiling"
        case .fileSearch: return "doc.text.magnifyingglass"
        case .menuSearch: return "menubar.rectangle"
        case .switchWindows: return "macwindow.on.rectangle"
        case .schedule: return "calendar"
        case .uninstall: return "trash"
        case .quicklinks: return Quicklink.sfSymbol
        case .customCommandArguments: return CustomCommand.sfSymbol
        case .quicklinkArguments: return Quicklink.sfSymbol
        case .snippets: return "curlybraces"
        case .dictionary: return "book.closed"
        case .extensionCommand: return "puzzlepiece.extension"
        case .ports: return "network"
        case .repos: return "folder.badge.gearshape"
        case .talix: return "timer"
        case .inbox: return "tray"
        case .clipShareRecent: return "video"
        case .kleioRecordings: return "waveform"
        case .spotify: return "music.note.list"
        }
    }
    var placeholder: String {
        switch self {
        case .launcher: return "Search for apps and commands…"
        case .clipboard: return "Type to filter entries…"
        case .ai: return "Ask anything…"
        case .aiHistory: return "Search chats…"
        case .calculatorHistory: return "Do math, convert units, or search your past calculations…"
        case .emoji: return "Search emoji and symbols…"
        case .fileSearch: return "Search files and folders…"
        case .menuSearch: return "Search menu bar items…"
        case .switchWindows: return "Search open windows…"
        case .schedule: return "Search your schedule…"
        case .uninstall: return "Filter files and folders by name…"
        case .quicklinks: return "Search quicklinks…"
        case .snippets: return "Search snippets…"
        case .dictionary: return "Look up a word…"
        // Replaced by the pending argument's name; only reached if the session vanished mid-render.
        case .customCommandArguments: return "Enter a value…"
        case .quicklinkArguments: return "Enter a value…"
        // Replaced by the command's own `searchBarPlaceholder` whenever it declares one.
        case .extensionCommand: return "Search…"
        case .ports: return "Search ports, processes, and projects…"
        case .repos: return "Search repositories, branches and organizations…"
        case .talix: return "Search Talix…"
        case .inbox: return "Search Inbox…"
        case .clipShareRecent: return "Search recent uploads…"
        case .kleioRecordings: return "Search Kleio recordings…"
        case .spotify: return "Search Spotify…"
        }
    }
}

/// The app a paste lands in, resolved once per show so nothing re-reads it per render.
struct PasteTarget: Equatable {
    let name: String
    /// Bundle path for `IconCache` — nil for a target with no on-disk bundle.
    let iconPath: String?

    init?(app: NSRunningApplication?) {
        guard let app, let name = app.localizedName else { return nil }
        self.name = name
        iconPath = app.bundleURL?.path
    }

    var pasteTitle: String { "Paste to \(name)" }
}
