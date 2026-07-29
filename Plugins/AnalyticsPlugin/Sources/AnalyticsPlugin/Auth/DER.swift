import Foundation

/// Just enough DER to get at an RSA private key.
///
/// Google issues service-account keys as PKCS#8 (`BEGIN PRIVATE KEY`), and
/// `SecKeyCreateWithData` wants a bare PKCS#1 `RSAPrivateKey`. Unwrapping one
/// to the other is a three-element walk, which is a great deal less than
/// taking on a dependency to do it.
enum DER {
    struct Element {
        let tag: UInt8
        let value: Data
        /// Offset just past this element in the buffer it was read from.
        let end: Int
    }

    enum Tag {
        static let integer: UInt8 = 0x02
        static let octetString: UInt8 = 0x04
        static let objectIdentifier: UInt8 = 0x06
        static let sequence: UInt8 = 0x30
    }

    /// `1.2.840.113549.1.1.1`, the only algorithm this plugin can sign with.
    static let rsaEncryptionOID = Data([0x2A, 0x86, 0x48, 0x86, 0xF7, 0x0D, 0x01, 0x01, 0x01])

    /// Reads one tag-length-value triple starting at `offset`.
    static func element(in data: Data, at offset: Int) throws -> Element {
        let bytes = [UInt8](data)
        guard offset + 1 < bytes.count else { throw AnalyticsError.unusableKey }
        let tag = bytes[offset]

        var cursor = offset + 1
        let first = bytes[cursor]
        cursor += 1

        var length = Int(first)
        if first & 0x80 != 0 {
            // Long form: the low seven bits count the bytes of the real length.
            let byteCount = Int(first & 0x7F)
            guard byteCount > 0, byteCount <= 4, cursor + byteCount <= bytes.count else {
                throw AnalyticsError.unusableKey
            }
            length = bytes[cursor..<(cursor + byteCount)].reduce(0) { ($0 << 8) | Int($1) }
            cursor += byteCount
        }

        guard cursor + length <= bytes.count else { throw AnalyticsError.unusableKey }
        return Element(tag: tag, value: data.subdata(in: cursor..<(cursor + length)), end: cursor + length)
    }

    /// Returns the PKCS#1 `RSAPrivateKey` inside a PKCS#8 `PrivateKeyInfo`,
    /// or the input unchanged when it already is PKCS#1.
    static func pkcs1PrivateKey(fromDER data: Data) throws -> Data {
        let outer = try element(in: data, at: 0)
        guard outer.tag == Tag.sequence else { throw AnalyticsError.unusableKey }

        let version = try element(in: outer.value, at: 0)
        guard version.tag == Tag.integer else { throw AnalyticsError.unusableKey }

        // PKCS#1 also opens SEQUENCE-INTEGER, so the discriminator is what
        // comes next: an AlgorithmIdentifier means PKCS#8, another INTEGER
        // (the modulus) means this is already the key we want.
        let second = try element(in: outer.value, at: version.end)
        guard second.tag == Tag.sequence else { return data }

        let algorithm = try element(in: second.value, at: 0)
        guard algorithm.tag == Tag.objectIdentifier, algorithm.value == rsaEncryptionOID else {
            throw AnalyticsError.unusableKey
        }

        let wrapped = try element(in: outer.value, at: second.end)
        guard wrapped.tag == Tag.octetString else { throw AnalyticsError.unusableKey }
        return wrapped.value
    }

    /// Strips PEM armour and base64-decodes the body.
    static func der(fromPEM pem: String) throws -> Data {
        let body = pem
            .split(separator: "\n", omittingEmptySubsequences: true)
            .filter { !$0.hasPrefix("-----") }
            .joined()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = Data(base64Encoded: body, options: .ignoreUnknownCharacters), !data.isEmpty else {
            throw AnalyticsError.unusableKey
        }
        return data
    }
}
