import Foundation

public enum ExtractionError: Error, Equatable {
    /// The bundled extract.js could not be found. A packaging problem, not a
    /// scraping one.
    case scriptMissing
    /// The script returned something that was not the expected JSON array.
    case malformedPayload
}

/// One row as `extract.js` emits it.
private struct RawListing: Decodable {
    let id: String
    let title: String
    let price: String
    let location: String
    let url: String
    let imageURL: String?
}

/// The JavaScript source that runs inside the webview.
///
/// Kept as a bundled resource rather than a Swift string literal so a selector
/// fix — which is the maintenance this design signs up for — is a one-file
/// change that does not touch compiled code.
public func extractScriptSource() throws -> String {
    guard let url = Bundle.module.url(forResource: "extract", withExtension: "js"),
          let source = try? String(contentsOf: url, encoding: .utf8)
    else { throw ExtractionError.scriptMissing }
    return source
}

/// Turns the script's JSON into listings.
///
/// A row with an unusable URL is skipped rather than failing the batch: one
/// malformed entry should cost one listing, not a whole poll.
public func decodeExtractedListings(_ json: String) throws -> [ScrapedListing] {
    guard let data = json.data(using: .utf8),
          let rows = try? JSONDecoder().decode([RawListing].self, from: data)
    else { throw ExtractionError.malformedPayload }

    return rows.compactMap { row in
        guard let url = URL(string: row.url), url.scheme == "https" else { return nil }
        return ScrapedListing(
            id: row.id,
            title: row.title,
            price: row.price,
            location: row.location,
            url: url,
            imageURL: row.imageURL.flatMap(URL.init(string:)),
            priceValue: parsePriceValue(row.price)
        )
    }
}
