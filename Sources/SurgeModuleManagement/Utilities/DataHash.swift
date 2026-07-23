import CryptoKit
import Foundation

extension Data {
    var sha256String: String {
        SHA256.hash(data: self).map { String(format: "%02x", $0) }.joined()
    }

    var gitBlobSHA1: String {
        var material = Data("blob \(count)\u{0}".utf8)
        material.append(self)
        return Insecure.SHA1.hash(data: material).map { String(format: "%02x", $0) }.joined()
    }
}
