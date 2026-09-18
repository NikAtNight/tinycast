import Foundation

/// The `kleio://` triggers Tinycast can send. Kleio registers the scheme; nothing here is synthesized.
enum KleioCommandURL: Equatable, Sendable {
    enum RecordingMode: String, Sendable {
        case meeting
        case system
        case mic
    }

    case startRecording(RecordingMode)
    case stopRecording
    case toggleRecording(RecordingMode)
    case toggleDictation

    static let scheme = "kleio"

    var url: URL {
        var components = URLComponents()
        components.scheme = Self.scheme
        switch self {
        case .startRecording(let mode):
            components.host = "record"
            components.path = "/start"
            components.queryItems = [URLQueryItem(name: "mode", value: mode.rawValue)]
        case .stopRecording:
            components.host = "record"
            components.path = "/stop"
        case .toggleRecording(let mode):
            components.host = "record"
            components.path = "/toggle"
            components.queryItems = [URLQueryItem(name: "mode", value: mode.rawValue)]
        case .toggleDictation:
            components.host = "dictation"
            components.path = "/toggle"
        }
        return components.url!
    }

    var successMessage: String {
        switch self {
        case .startRecording(.meeting): return "Kleio: starting meeting recording"
        case .startRecording(.system): return "Kleio: starting system audio recording"
        case .startRecording(.mic): return "Kleio: starting voice memo"
        case .stopRecording: return "Kleio: stopping recording"
        case .toggleRecording(.meeting): return "Kleio: toggling meeting recording"
        case .toggleRecording(.system): return "Kleio: toggling system audio recording"
        case .toggleRecording(.mic): return "Kleio: toggling voice memo"
        case .toggleDictation: return "Kleio: toggling dictation"
        }
    }
}
