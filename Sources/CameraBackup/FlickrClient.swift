import AppKit
import CryptoKit
import Darwin
import Foundation
import Security

private struct FlickrCredentials: Codable, Sendable { let key: String; let secret: String }
private struct FlickrAccess: Codable, Sendable { let token: String; let secret: String; let username: String?; let userID: String? }

actor FlickrClient {
    private let keychain = FlickrKeychain()
    private var credentials: FlickrCredentials?
    private var access: FlickrAccess?

    init() { }
    var isAuthorized: Bool { (credentials != nil && access != nil) || UserDefaults.standard.bool(forKey: "authorized.flickr") }

    func uploadPrivate(file: URL, filename: String) async throws -> FlickrUploadResult {
        loadStoredStateIfNeeded()
        guard let credentials, let access else { throw FlickrError.notAuthorized }
        let endpoint = URL(string: "https://up.flickr.com/services/upload/")!
        var parameters = oauthParameters(key: credentials.key, token: access.token)
        parameters["title"] = file.deletingPathExtension().lastPathComponent
        parameters["is_public"] = "0"
        parameters["is_friend"] = "0"
        parameters["is_family"] = "0"
        parameters["hidden"] = "2"
        parameters["safety_level"] = "1"
        parameters["dedup_check"] = "1"
        parameters["oauth_signature"] = signature(method: "POST", url: endpoint.absoluteString, parameters: parameters, consumerSecret: credentials.secret, tokenSecret: access.secret)

        let boundary = "CameraZapper-\(UUID().uuidString)"
        let bodyURL = FileManager.default.temporaryDirectory.appending(path: "flickr-upload-\(UUID().uuidString)")
        FileManager.default.createFile(atPath: bodyURL.path, contents: nil)
        defer { try? FileManager.default.removeItem(at: bodyURL) }
        let output = try FileHandle(forWritingTo: bodyURL)
        defer { try? output.close() }
        for (name, value) in parameters.sorted(by: { $0.key < $1.key }) {
            try output.write(contentsOf: Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(name)\"\r\n\r\n\(value)\r\n".utf8))
        }
        let safeFilename = filename.replacingOccurrences(of: "\"", with: "_")
        try output.write(contentsOf: Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"photo\"; filename=\"\(safeFilename)\"\r\nContent-Type: \(mimeType(for: file))\r\n\r\n".utf8))
        let input = try FileHandle(forReadingFrom: file)
        while let chunk = try input.read(upToCount: 1_048_576), !chunk.isEmpty { try output.write(contentsOf: chunk) }
        try input.close()
        try output.write(contentsOf: Data("\r\n--\(boundary)--\r\n".utf8))
        try output.synchronize()

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        let (data, response) = try await URLSession.shared.upload(for: request, fromFile: bodyURL)
        let text = String(decoding: data, as: UTF8.self)
        guard let http = response as? HTTPURLResponse else { throw FlickrError.api(text) }
        if http.statusCode == 413 { throw FlickrError.entityTooLarge }
        guard (200..<300).contains(http.statusCode) else { throw FlickrError.api(text) }
        if let photoID = xmlValue("photoid", in: text) { return .uploaded("https://www.flickr.com/photos/\(access.userID ?? "me")/\(photoID)") }
        if text.contains("code=\"9\"") {
            let duplicateURL = xmlAttribute("duplicate_photo_id", in: text).map { "https://www.flickr.com/photos/\(access.userID ?? "me")/\($0)" }
            return .alreadyPresent(duplicateURL)
        }
        throw FlickrError.api(xmlAttribute("msg", in: text) ?? text)
    }

    func configureAndAuthorize(key: String, secret: String) async throws {
        let trimmedKey = key.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedSecret = secret.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty, !trimmedSecret.isEmpty else { throw FlickrError.invalidCredentials }
        let credentials = FlickrCredentials(key: trimmedKey, secret: trimmedSecret)
        try keychain.save(JSONEncoder().encode(credentials), account: "flickr.credentials")
        self.credentials = credentials

        let callback = try FlickrOAuthCallback.start()
        let requestURL = URL(string: "https://www.flickr.com/services/oauth/request_token")!
        let requestParameters = oauthParameters(key: trimmedKey, token: nil).merging(["oauth_callback": callback.redirectURI]) { _, new in new }
        let requestResponse = try await signedGET(requestURL, parameters: requestParameters, consumerSecret: trimmedSecret, tokenSecret: nil)
        let requestValues = formValues(requestResponse)
        guard let requestToken = requestValues["oauth_token"], let requestSecret = requestValues["oauth_token_secret"] else { throw FlickrError.api(requestResponse) }
        var authorize = URLComponents(string: "https://www.flickr.com/services/oauth/authorize")!
        authorize.queryItems = [.init(name: "oauth_token", value: requestToken), .init(name: "perms", value: "write")]
        _ = await MainActor.run { NSWorkspace.shared.open(authorize.url!) }
        let verifier = try await callback.waitForVerifier(expectedToken: requestToken)

        let accessURL = URL(string: "https://www.flickr.com/services/oauth/access_token")!
        let accessParameters = oauthParameters(key: trimmedKey, token: requestToken).merging(["oauth_verifier": verifier]) { _, new in new }
        let accessResponse = try await signedGET(accessURL, parameters: accessParameters, consumerSecret: trimmedSecret, tokenSecret: requestSecret)
        let values = formValues(accessResponse)
        guard let token = values["oauth_token"], let tokenSecret = values["oauth_token_secret"] else { throw FlickrError.api(accessResponse) }
        let access = FlickrAccess(token: token, secret: tokenSecret, username: values["username"], userID: values["user_nsid"])
        try keychain.save(JSONEncoder().encode(access), account: "flickr.access")
        self.access = access
    }

    private func signedGET(_ url: URL, parameters: [String: String], consumerSecret: String, tokenSecret: String?) async throws -> String {
        var signed = parameters
        signed["oauth_signature"] = signature(method: "GET", url: url.absoluteString, parameters: parameters, consumerSecret: consumerSecret, tokenSecret: tokenSecret)
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        components.queryItems = signed.sorted { $0.key < $1.key }.map { .init(name: $0.key, value: $0.value) }
        let (data, response) = try await URLSession.shared.data(from: components.url!)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { throw FlickrError.api(String(decoding: data, as: UTF8.self)) }
        return String(decoding: data, as: UTF8.self)
    }
    private func oauthParameters(key: String, token: String?) -> [String: String] {
        var result = ["oauth_consumer_key": key, "oauth_nonce": UUID().uuidString.replacingOccurrences(of: "-", with: ""), "oauth_signature_method": "HMAC-SHA1", "oauth_timestamp": String(Int(Date().timeIntervalSince1970)), "oauth_version": "1.0"]
        if let token { result["oauth_token"] = token }; return result
    }
    private func signature(method: String, url: String, parameters: [String: String], consumerSecret: String, tokenSecret: String?) -> String {
        let encoded: [(String, String)] = parameters.map { pair in (oauthEncode(pair.key), oauthEncode(pair.value)) }
        let sorted = encoded.sorted { left, right in left.0 == right.0 ? left.1 < right.1 : left.0 < right.0 }
        let normalized = sorted.map { pair in pair.0 + "=" + pair.1 }.joined(separator: "&")
        let base = "\(method)&\(oauthEncode(url))&\(oauthEncode(normalized))"
        let signingKey = SymmetricKey(data: Data("\(oauthEncode(consumerSecret))&\(oauthEncode(tokenSecret ?? ""))".utf8))
        return Data(HMAC<Insecure.SHA1>.authenticationCode(for: Data(base.utf8), using: signingKey)).base64EncodedString()
    }
    private func oauthEncode(_ value: String) -> String { value.addingPercentEncoding(withAllowedCharacters: CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~")) ?? value }
    private func formValues(_ text: String) -> [String: String] { Dictionary(uniqueKeysWithValues: text.split(separator: "&").compactMap { pair in let bits = pair.split(separator: "=", maxSplits: 1).map(String.init); return bits.count == 2 ? (bits[0].removingPercentEncoding ?? bits[0], bits[1].removingPercentEncoding ?? bits[1]) : nil }) }
    private func loadStoredStateIfNeeded() {
        if credentials == nil { credentials = keychain.load("flickr.credentials").flatMap { try? JSONDecoder().decode(FlickrCredentials.self, from: $0) } }
        if access == nil { access = keychain.load("flickr.access").flatMap { try? JSONDecoder().decode(FlickrAccess.self, from: $0) } }
    }
    private func mimeType(for url: URL) -> String { switch url.pathExtension.lowercased() { case "jpg", "jpeg": "image/jpeg"; case "png": "image/png"; case "gif": "image/gif"; case "tif", "tiff": "image/tiff"; case "heic": "image/heic"; case "mov": "video/quicktime"; case "m4v": "video/x-m4v"; default: "video/mp4" } }
    private func xmlValue(_ element: String, in text: String) -> String? { guard let start = text.range(of: "<\(element)>"), let end = text.range(of: "</\(element)>", range: start.upperBound..<text.endIndex) else { return nil }; return String(text[start.upperBound..<end.lowerBound]) }
    private func xmlAttribute(_ attribute: String, in text: String) -> String? { let marker = "\(attribute)=\""; guard let start = text.range(of: marker), let end = text[start.upperBound...].firstIndex(of: "\"") else { return nil }; return String(text[start.upperBound..<end]) }
}

enum FlickrUploadResult: Sendable {
    case uploaded(String)
    case alreadyPresent(String?)
}

private final class FlickrOAuthCallback: @unchecked Sendable {
    let fd: Int32; let redirectURI: String
    private init(fd: Int32, port: UInt16) { self.fd = fd; redirectURI = "http://127.0.0.1:\(port)/flickr/callback" }
    deinit { Darwin.close(fd) }
    static func start() throws -> FlickrOAuthCallback {
        let fd = socket(AF_INET, SOCK_STREAM, 0); guard fd >= 0 else { throw FlickrError.callback }
        var reuse: Int32 = 1; setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &reuse, socklen_t(MemoryLayout.size(ofValue: reuse)))
        var address = sockaddr_in(sin_len: UInt8(MemoryLayout<sockaddr_in>.size), sin_family: sa_family_t(AF_INET), sin_port: 0, sin_addr: in_addr(s_addr: inet_addr("127.0.0.1")), sin_zero: (0,0,0,0,0,0,0,0))
        let bound = withUnsafePointer(to: &address) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) } }
        guard bound == 0, listen(fd, 1) == 0 else { Darwin.close(fd); throw FlickrError.callback }
        var actual = sockaddr_in(); var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        let named = withUnsafeMutablePointer(to: &actual) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(fd, $0, &length) } }
        guard named == 0 else { Darwin.close(fd); throw FlickrError.callback }
        return .init(fd: fd, port: UInt16(bigEndian: actual.sin_port))
    }
    func waitForVerifier(expectedToken: String) async throws -> String {
        let listener = fd
        return try await Task.detached {
            let client = accept(listener, nil, nil); guard client >= 0 else { throw FlickrError.callback }; defer { Darwin.close(client) }
            var buffer = [UInt8](repeating: 0, count: 16_384); let count = recv(client, &buffer, buffer.count, 0); guard count > 0 else { throw FlickrError.callback }
            let line = String(decoding: buffer.prefix(count), as: UTF8.self).components(separatedBy: "\r\n").first ?? ""
            let target = line.split(separator: " ").dropFirst().first.map(String.init) ?? ""
            let items = URLComponents(string: "http://localhost" + target)?.queryItems ?? []
            let token = items.first(where: { $0.name == "oauth_token" })?.value; let verifier = items.first(where: { $0.name == "oauth_verifier" })?.value
            let response = "HTTP/1.1 200 OK\r\nContent-Type: text/html; charset=utf-8\r\nConnection: close\r\n\r\n<h2>Camera Zapper is authorized for Flickr.</h2><p>You may close this window.</p>"
            _ = response.withCString { send(client, $0, strlen($0), 0) }
            guard token == expectedToken, let verifier else { throw FlickrError.callback }; return verifier
        }.value
    }
}

private struct FlickrKeychain: Sendable {
    func save(_ data: Data, account: String) throws {
        do { try CameraZapperCredentialVault.shared.save(data, account: account) }
        catch { throw FlickrError.keychain }
    }
    func load(_ account: String) -> Data? { CameraZapperCredentialVault.shared.load(account) }
}

enum FlickrError: LocalizedError { case invalidCredentials, callback, keychain, notAuthorized, entityTooLarge, api(String)
    var errorDescription: String? { switch self { case .invalidCredentials: "Enter both the Flickr API key and secret."; case .callback: "Flickr's local authorization callback failed."; case .keychain: "Flickr credentials could not be stored in Keychain."; case .notAuthorized: "Flickr is not authorized."; case .entityTooLarge: "Flickr rejected the upload because the request was too large."; case .api(let value): "Flickr: \(value)" } }
}
