import Foundation

public enum ExtractionError: Error, Equatable {
    /// The bundled busyness.js could not be found. A packaging problem, not
    /// a scraping one.
    case scriptMissing
    /// The script returned something that was not the expected JSON object.
    case malformedPayload
}

/// The search page for a query, or `nil` for a blank one.
///
/// `hl=en` pins the interface language, because the extractor reads the
/// words "Live:" off the page and Google would otherwise localise them.
public func googleSearchURL(query: String) -> URL? {
    let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return nil }
    var components = URLComponents()
    components.scheme = "https"
    components.host = "www.google.com"
    components.path = "/search"
    components.queryItems = [
        URLQueryItem(name: "q", value: trimmed),
        URLQueryItem(name: "hl", value: "en"),
    ]
    return components.url
}

/// What `busyness.js` reports about a page, before it is judged.
///
/// `found` and `hasConsentForm` are kept apart from the reading so the
/// source can turn them into the right `BusyError` rather than the
/// extractor having to know what an error is.
public struct ExtractedPage: Equatable {
    public var found: Bool
    public var hasConsentForm: Bool
    public var reading: BusyReading
}

private struct RawPage: Decodable {
    struct RawHour: Decodable {
        let hour: Int
        let percent: Int
    }

    let found: Bool
    let hasConsentForm: Bool
    let name: String?
    let statusText: String?
    let isLive: Bool
    let livePercent: Int?
    let usualPercent: Int?
    let currentHour: Int?
    let day: Int?
    let hours: [RawHour]
}

/// The JavaScript that runs inside the webview.
///
/// A bundled resource rather than a Swift string literal so a selector fix —
/// the maintenance this design signs up for — is a one-file change that does
/// not touch compiled code.
public func extractScriptSource() throws -> String {
    guard let url = Bundle.module.url(forResource: "busyness", withExtension: "js"),
          let source = try? String(contentsOf: url, encoding: .utf8)
    else { throw ExtractionError.scriptMissing }
    return source
}

public func decodeExtractedPage(_ json: String) throws -> ExtractedPage {
    guard let data = json.data(using: .utf8),
          let raw = try? JSONDecoder().decode(RawPage.self, from: data)
    else { throw ExtractionError.malformedPayload }

    return ExtractedPage(
        found: raw.found,
        hasConsentForm: raw.hasConsentForm,
        reading: BusyReading(
            name: raw.name,
            statusText: raw.statusText,
            isLive: raw.isLive,
            livePercent: raw.livePercent,
            usualPercent: raw.usualPercent,
            currentHour: raw.currentHour,
            day: raw.day,
            hours: raw.hours.map { HourBusyness(hour: $0.hour, percent: $0.percent) }
        )
    )
}
