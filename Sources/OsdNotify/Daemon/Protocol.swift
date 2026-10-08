import Foundation

struct DaemonRequest: Codable {
    enum Kind: String, Codable {
        case show
        case clear
        case ping
    }

    let kind: Kind
    let showOptions: Options?
    let clearOptions: ClearOptions?

    static func show(_ options: Options) -> DaemonRequest {
        DaemonRequest(kind: .show, showOptions: options, clearOptions: nil)
    }

    static func clear(_ options: ClearOptions) -> DaemonRequest {
        DaemonRequest(kind: .clear, showOptions: nil, clearOptions: options)
    }

    static func ping() -> DaemonRequest {
        DaemonRequest(kind: .ping, showOptions: nil, clearOptions: nil)
    }
}

struct DaemonResponse: Codable {
    let ok: Bool
    let message: String
}
