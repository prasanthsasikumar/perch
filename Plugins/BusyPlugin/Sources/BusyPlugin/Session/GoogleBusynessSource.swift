import Foundation

/// The real `BusynessSource`: a Google search, through the session's webview.
///
/// Judges what the page was — results, consent wall, or nothing — and turns
/// that into a `BusyError`. The extractor only reports; this decides.
@MainActor
public struct GoogleBusynessSource: BusynessSource {
    private let session: GoogleSession

    public init(session: GoogleSession) {
        self.session = session
    }

    public func fetch(query: String) async throws -> BusyReading {
        guard let url = googleSearchURL(query: query) else {
            throw BusyError.failed("this place has no search text")
        }
        let page = try await session.load(url: url)
        return try judge(page)
    }

    /// Pure, so the classification is pinned by tests rather than discovered
    /// against live Google.
    func judge(_ page: LoadedPage) throws -> BusyReading {
        let extracted = try decodeExtractedPage(page.payload)
        if extracted.hasConsentForm || (page.finalURL?.host ?? "").contains("consent.google") {
            throw BusyError.consentWall
        }
        guard extracted.found else { throw BusyError.notFound }
        return extracted.reading
    }
}
