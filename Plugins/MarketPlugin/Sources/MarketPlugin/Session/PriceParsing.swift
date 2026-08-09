import Foundation

/// The numeric value behind a displayed price, in whole units of currency.
///
/// The display string is what Facebook rendered — "$180", "Free", "$1,200".
/// A client cannot sort or threshold on that, so this pulls out the number
/// when there is one and returns `nil` when there is not.
///
/// Cents are truncated rather than rounded: a cap of $200 should not be
/// satisfied by $200.99.
public func parsePriceValue(_ display: String) -> Int? {
    var digits = ""
    var sawSeparator = false
    for character in display {
        if character.isNumber {
            if sawSeparator { break }  // stop at the cents
            digits.append(character)
        } else if character == "." && !digits.isEmpty {
            sawSeparator = true
        } else if character == "," {
            continue  // thousands separator
        } else if !digits.isEmpty {
            break  // the number ended; ignore any trailing text
        }
    }
    guard !digits.isEmpty else { return nil }
    // `Int(digits)` returns nil rather than trapping when it overflows, which
    // is what we want for absurd input.
    return Int(digits)
}
