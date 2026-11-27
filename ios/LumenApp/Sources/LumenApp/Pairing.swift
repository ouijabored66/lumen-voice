import Foundation

/// Result of storing a scanned (or typed) pairing payload and testing `/health`.
enum PairingOutcome: Equatable {
    case connected(String)
    case rejected
    case unreachable
    case invalid
}

/// JSON (or lumenvoice:// URL) encoded in the desktop `/pair` QR.
struct PairingPayload: Equatable {
    var urls: [String]
    var token: String

    static func parse(_ raw: String) -> PairingPayload? {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        if text.hasPrefix("lumenvoice:") || text.hasPrefix("lumen:") {
            return parseURL(text)
        }
        guard let data = text.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return parseJSON(obj)
    }

    private static func parseJSON(_ obj: [String: Any]) -> PairingPayload? {
        if let lumen = obj["lumen"] {
            let n = (lumen as? Int) ?? (lumen as? NSNumber)?.intValue
            if n != 1 { return nil }
        }
        var urls: [String] = []
        if let list = obj["urls"] as? [Any] {
            urls = list.compactMap { $0 as? String }.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        }
        if urls.isEmpty, let one = obj["url"] as? String {
            let trimmed = one.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { urls = [trimmed] }
        }
        let token = ((obj["token"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !urls.isEmpty, !token.isEmpty else { return nil }
        return PairingPayload(urls: urls, token: token)
    }

    private static func parseURL(_ raw: String) -> PairingPayload? {
        guard let comps = URLComponents(string: raw) else { return nil }
        guard comps.scheme == "lumenvoice" || comps.scheme == "lumen" else { return nil }
        let host = (comps.host ?? "").lowercased()
        let path = comps.path.trimmingCharacters(in: CharacterSet(charactersIn: "/")).lowercased()
        guard host == "pair" || path == "pair" else { return nil }
        let items = comps.queryItems ?? []
        let urls = items.filter { $0.name == "url" }.compactMap(\.value)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let token = (items.first(where: { $0.name == "token" })?.value ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !urls.isEmpty, !token.isEmpty else { return nil }
        return PairingPayload(urls: urls, token: token)
    }
}
