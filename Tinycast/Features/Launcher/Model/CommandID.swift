import Foundation

/// Built-in launcher actions, surfaced alongside the user-authored ones.
enum CommandID: String, CaseIterable, Sendable {
    /// The palette's chat keeps the id it shipped with, so its hotkeys and fallback still reach it.
    case quickAI = "command:ai-chat"
    case aiChat = "command:ai-chat-window"
    case fixGrammar = "command:fix-grammar"
    case rewrite = "command:rewrite"
    case translate = "command:translate"
    case summarize = "command:summarize"
    case calculatorHistory = "command:calculator-history"
    case clipboardHistory = "command:clipboard-history"
    case searchEmoji = "command:search-emoji"
    case searchFiles = "command:search-files"
    case searchMenuItems = "command:search-menu-items"
    case switchWindows = "command:switch-windows"
    case openCamera = "command:open-camera"
    case openInBrowser = "command:open-in-browser"
    case runShellCommand = "command:run-shell-command"
    case define = "command:define"
    case joinNextMeeting = "command:join-next-meeting"
    case mySchedule = "command:my-schedule"
    case createEvent = "command:create-event"
    case copyMeetingLink = "command:copy-meeting-link"
    case openInCalendar = "command:open-in-calendar"
    case showNotes = "command:show-notes"
    case createNote = "command:create-note"
    case searchNotes = "command:search-notes"
    case createWindowLayout = "command:create-window-layout"
    case captureWindowLayout = "command:capture-window-layout"
    case switchRoom = "command:switch-room"
    case createRoom = "command:create-room"
    case createQuicklink = "command:create-quicklink"
    case searchQuicklinks = "command:search-quicklinks"
    case importQuicklinks = "command:import-quicklinks"
    case exportQuicklinks = "command:export-quicklinks"
    case searchSnippets = "command:search-snippets"
    case createSnippet = "command:create-snippet"
    case snippetsForThisApp = "command:snippets-for-this-app"
    case exportSettings = "command:export-settings"
    case importSettings = "command:import-settings"
    case importFromRaycast = "command:import-from-raycast"
    case checkForUpdates = "command:check-for-updates"
    case settings = "command:settings"
    case about = "command:about"
    case support = "command:support"
    case quit = "command:quit"
    case ports = "command:ports"
    case repos = "command:repos"
    case talixStartTimer = "command:talix-start-timer"
    case talixStopTimer = "command:talix-stop-timer"
    case talixLogTime = "command:talix-log-time"
    case talixToday = "command:talix-today"
    case inbox = "command:inbox"
    case clipShareLatest = "command:clipshare-latest"
    case clipShareClipboard = "command:clipshare-clipboard"
    case clipShareRecent = "command:clipshare-recent"

    case kleioRecordings = "command:kleio-recordings"
    case kleioStartMeeting = "command:kleio-start-meeting"
    case kleioStartMemo = "command:kleio-start-memo"
    case kleioStopRecording = "command:kleio-stop-recording"
    case kleioToggleRecording = "command:kleio-toggle-recording"
    case kleioToggleDictation = "command:kleio-toggle-dictation"
    case spotifySearch = "command:spotify-search"

    var name: String {
        switch self {
        case .quickAI: return "Quick AI"
        case .aiChat: return "AI Chat"
        case .fixGrammar: return BuiltInQuickAction.fixGrammar.title
        case .rewrite: return BuiltInQuickAction.rewrite.title
        case .translate: return BuiltInQuickAction.translate.title
        case .summarize: return BuiltInQuickAction.summarize.title
        case .calculatorHistory: return "Calculator History"
        case .clipboardHistory: return "Clipboard History"
        case .searchEmoji: return "Search Emoji & Symbols"
        case .searchFiles: return "Search Files"
        case .searchMenuItems: return "Search Menu Bar Items"
        case .switchWindows: return "Switch Windows"
        case .openCamera: return "Open Camera"
        case .openInBrowser: return "Open in Browser"
        case .runShellCommand: return "Run Shell Command"
        case .define: return "Define Word"
        case .joinNextMeeting: return "Join Next Meeting"
        case .mySchedule: return "My Schedule"
        case .createEvent: return "Create Event"
        case .copyMeetingLink: return "Copy Meeting Link"
        case .openInCalendar: return "Open in Calendar"
        case .showNotes: return "Show Notes"
        case .createNote: return "Create Note"
        case .searchNotes: return "Search Notes"
        case .createWindowLayout: return "Create Window Layout"
        case .captureWindowLayout: return "Create Layout from Current Windows"
        case .switchRoom: return "Switch Room"
        case .createRoom: return "Create Room"
        case .createQuicklink: return "Create Quicklink"
        case .searchQuicklinks: return "Search Quicklinks"
        case .importQuicklinks: return "Import Quicklinks"
        case .exportQuicklinks: return "Export Quicklinks"
        case .searchSnippets: return "Search Snippets"
        case .createSnippet: return "Create Snippet"
        case .snippetsForThisApp: return "Snippets for This App"
        case .exportSettings: return "Export Backup"
        case .importSettings: return "Import Backup"
        case .importFromRaycast: return "Import from Raycast"
        case .checkForUpdates: return "Check for Updates"
        case .settings: return "Tinycast Settings"
        case .about: return "About Tinycast"
        case .support: return "Support Tinycast"
        case .quit: return "Quit Tinycast"
        case .ports: return "Listening Ports"
        case .repos: return "Repositories"
        case .talixStartTimer: return "Talix Start Timer"
        case .talixStopTimer: return "Talix Stop Timer"
        case .talixLogTime: return "Talix Log Time"
        case .talixToday: return "Talix Today"
        case .inbox: return "Inbox"
        case .clipShareLatest: return "Share Latest Recording"
        case .clipShareClipboard: return "Share File on Clipboard"
        case .clipShareRecent: return "Recent ClipShare Uploads"
        case .kleioRecordings: return "Kleio Recordings"
        case .kleioStartMeeting: return "Start Kleio Meeting Recording"
        case .kleioStartMemo: return "Start Kleio Voice Memo"
        case .kleioStopRecording: return "Stop Kleio Recording"
        case .kleioToggleRecording: return "Toggle Kleio Recording"
        case .kleioToggleDictation: return "Toggle Kleio Dictation"
        case .spotifySearch: return "Search Spotify"
        }
    }

    var sfSymbol: String {
        switch self {
        case .quickAI: return "sparkles"
        case .aiChat: return "bubble.left.and.bubble.right"
        case .fixGrammar: return BuiltInQuickAction.fixGrammar.symbol
        case .rewrite: return BuiltInQuickAction.rewrite.symbol
        case .translate: return BuiltInQuickAction.translate.symbol
        case .summarize: return BuiltInQuickAction.summarize.symbol
        case .calculatorHistory: return "plus.forwardslash.minus"
        case .clipboardHistory: return "doc.on.clipboard"
        case .searchEmoji: return "face.smiling"
        case .searchFiles: return "doc.text.magnifyingglass"
        case .searchMenuItems: return "menubar.rectangle"
        case .switchWindows: return "macwindow.on.rectangle"
        case .openCamera: return "camera"
        case .openInBrowser: return "globe"
        case .runShellCommand: return "terminal"
        case .define: return "book.closed"
        case .joinNextMeeting: return "video.fill"
        case .mySchedule: return "calendar"
        case .createEvent: return "calendar.badge.plus"
        case .copyMeetingLink: return "link"
        case .openInCalendar: return "calendar.badge.clock"
        case .showNotes: return "text.page"
        case .createNote: return "note.text.badge.plus"
        case .searchNotes: return "text.magnifyingglass"
        case .createWindowLayout: return "plus.rectangle.on.rectangle"
        case .captureWindowLayout: return "macwindow.badge.plus"
        case .switchRoom: return "door.left.hand.open"
        case .createRoom: return "rectangle.stack.badge.plus"
        case .createQuicklink: return "link.badge.plus"
        case .searchQuicklinks: return Quicklink.sfSymbol
        case .importQuicklinks: return "square.and.arrow.down"
        case .exportQuicklinks: return "square.and.arrow.up"
        case .searchSnippets: return "curlybraces"
        case .createSnippet: return "plus.rectangle.on.rectangle"
        case .snippetsForThisApp: return "curlybraces.square"
        case .exportSettings: return "square.and.arrow.up"
        case .importSettings: return "square.and.arrow.down"
        case .importFromRaycast: return "arrow.down.doc"
        case .checkForUpdates: return "arrow.down.circle"
        case .settings: return "gearshape"
        case .about: return "info.circle"
        case .support: return "heart"
        case .quit: return "power"
        case .ports: return "network"
        case .repos: return "folder.badge.gearshape"
        case .talixStartTimer: return "timer"
        case .talixStopTimer: return "stop.circle"
        case .talixLogTime: return "clock.badge.plus"
        case .talixToday: return "clock"
        case .inbox: return "tray"
        case .clipShareLatest, .clipShareClipboard: return "square.and.arrow.up"
        case .clipShareRecent: return "video"
        case .kleioRecordings: return "waveform"
        case .kleioStartMeeting: return "record.circle"
        case .kleioStartMemo: return "mic.circle"
        case .kleioStopRecording: return "stop.circle"
        case .kleioToggleRecording: return "record.circle.fill"
        case .kleioToggleDictation: return "waveform.circle"
        case .spotifySearch: return "music.note.list"
        }
    }

    /// Exhaustive, so a fifth shipped action cannot reach the launcher without a row here.
    init(_ action: BuiltInQuickAction) {
        switch action {
        case .fixGrammar: self = .fixGrammar
        case .rewrite: self = .rewrite
        case .translate: self = .translate
        case .summarize: self = .summarize
        }
    }

    var builtInQuickAction: BuiltInQuickAction? {
        switch self {
        case .fixGrammar: return .fixGrammar
        case .rewrite: return .rewrite
        case .translate: return .translate
        case .summarize: return .summarize
        default: return nil
        }
    }

    /// Queries this command wins until the user opens a rival more.
    var boostedTerms: Set<String> {
        switch self {
        case .quickAI: ["ai"]
        case .aiChat: ["chat"]
        default: []
        }
    }

    /// Suggested, highest first, until the user's own habits fill the section.
    var suggestionPriority: Int? {
        switch self {
        case .clipboardHistory: 80
        case .searchFiles: 70
        case .mySchedule: 60
        case .searchEmoji: 50
        case .createQuicklink, .createSnippet: 30
        default: nil
        }
    }

    /// Query-driven: the typed text is their input, so they are built where offered, never listed.
    var isQueryDriven: Bool {
        self == .openInBrowser || self == .runShellCommand
    }

    /// A chord carries no query, and none should be able to terminate the app outright.
    var hotKeyAction: HotKeyAction? {
        isQueryDriven || self == .quit ? nil : .command(self)
    }
}

extension CommandID {
    /// The app a command drives, so its row wears that app's icon whenever the app is installed.
    var applicationBundleID: String? {
        switch self {
        case .kleioRecordings, .kleioStartMeeting, .kleioStartMemo, .kleioStopRecording,
            .kleioToggleRecording, .kleioToggleDictation:
            return "app.talix.scribe"
        case .clipShareLatest, .clipShareClipboard, .clipShareRecent:
            return "app.talix.clipshare"
        case .talixStartTimer, .talixStopTimer, .talixLogTime, .talixToday:
            return "app.talix.time"
        case .spotifySearch:
            return "com.spotify.client"
        default:
            return nil
        }
    }
}
