import Foundation
import Security

/// A throwaway RSA key, in the PKCS#8 armour Google uses.
///
/// Generated rather than checked in: a real private key in a repository is a
/// real private key in a repository, even a worthless one. 2048 bits takes
/// long enough that it is made once and shared across the suite.
enum RSATestKey {
    enum Failure: Error {
        case generationFailed
        case exportFailed
    }

    /// The PKCS#1 `RSAPrivateKey` DER — what `SecKeyCreateWithData` accepts,
    /// and what unwrapping the PKCS#8 below should produce.
    static func pkcs1DER() throws -> Data {
        try shared.get().pkcs1
    }

    static func pkcs8PEM() throws -> String {
        pem(try shared.get().pkcs8, label: "PRIVATE KEY")
    }

    static func pkcs1PEM() throws -> String {
        pem(try shared.get().pkcs1, label: "RSA PRIVATE KEY")
    }

    // MARK: - Generation

    private struct Material {
        let pkcs1: Data
        let pkcs8: Data
    }

    private static let shared: Result<Material, Error> = generate()

    private static func generate() -> Result<Material, Error> {
        let attributes: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
            kSecAttrKeySizeInBits as String: 2048,
            // Never lands in a keychain: this is scratch material for a test
            // process, and persisting it would outlive the run.
            kSecAttrIsPermanent as String: false,
        ]
        guard let key = SecKeyCreateRandomKey(attributes as CFDictionary, nil) else {
            return .failure(Failure.generationFailed)
        }
        guard let pkcs1 = SecKeyCopyExternalRepresentation(key, nil) as Data? else {
            return .failure(Failure.exportFailed)
        }
        return .success(Material(pkcs1: pkcs1, pkcs8: wrapInPKCS8(pkcs1)))
    }

    /// ```
    /// SEQUENCE {
    ///   INTEGER 0
    ///   SEQUENCE { OID rsaEncryption, NULL }
    ///   OCTET STRING { RSAPrivateKey }
    /// }
    /// ```
    private static func wrapInPKCS8(_ pkcs1: Data) -> Data {
        let rsaOID = Data([0x2A, 0x86, 0x48, 0x86, 0xF7, 0x0D, 0x01, 0x01, 0x01])
        let algorithm = tlv(0x30, tlv(0x06, rsaOID) + tlv(0x05, Data()))
        let body = tlv(0x02, Data([0x00])) + algorithm + tlv(0x04, pkcs1)
        return tlv(0x30, body)
    }

    private static func tlv(_ tag: UInt8, _ value: Data) -> Data {
        Data([tag]) + length(value.count) + value
    }

    private static func length(_ count: Int) -> Data {
        if count < 0x80 { return Data([UInt8(count)]) }
        var bytes: [UInt8] = []
        var remaining = count
        while remaining > 0 {
            bytes.insert(UInt8(remaining & 0xFF), at: 0)
            remaining >>= 8
        }
        return Data([0x80 | UInt8(bytes.count)] + bytes)
    }

    private static func pem(_ der: Data, label: String) -> String {
        let base64 = der.base64EncodedString()
        let lines = stride(from: 0, to: base64.count, by: 64).map { start -> String in
            let from = base64.index(base64.startIndex, offsetBy: start)
            let to = base64.index(from, offsetBy: min(64, base64.count - start))
            return String(base64[from..<to])
        }
        return (["-----BEGIN \(label)-----"] + lines + ["-----END \(label)-----"]).joined(separator: "\n")
    }
}

private extension Result {
    func get() throws -> Success {
        switch self {
        case .success(let value): return value
        case .failure(let error): throw error
        }
    }
}
