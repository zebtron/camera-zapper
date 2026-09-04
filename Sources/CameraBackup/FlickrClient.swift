import AppKit
import CryptoKit
import Darwin
import Foundation
import Security
import UniformTypeIdentifiers

private struct FlickrCredentials: Codable, Sendable { let key: String; let secret: String }
private struct FlickrAccess: Codable, Sendable { let token: String; let secret: String; let username: String?; let userID: String? }
private struct FlickrStoredState: Codable, Sendable { let credentials: FlickrCredentials; let access: FlickrAccess }
struct FlickrAuthorizationStatus: Sendable { let username: String; let userID: String? }

actor FlickrClient {
    private let keychain = FlickrKeychain()
    private var credentials: FlickrCredentials?
    private var access: FlickrAccess?

    init() { }
    var isAuthorized: Bool { credentials != nil && access != nil }

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
        let message = xmlAttribute("msg", in: text) ?? text
        if ["96", "97", "98", "99", "100"].contains(xmlAttribute("code", in: text) ?? "") {
            throw FlickrError.authorizationExpired(message)
        }
        throw FlickrError.api(message)
    }

    func configureAndAuthorize(key: String, secret: String) async throws {
        let trimmedKey = key.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedSecret = secret.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty, !trimmedSecret.isEmpty else { throw FlickrError.invalidCredentials }
        let candidateCredentials = FlickrCredentials(key: trimmedKey, secret: trimmedSecret)

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
        let candidateAccess = FlickrAccess(token: token, secret: tokenSecret, username: values["username"], userID: values["user_nsid"])
        // Commit the consumer credentials and access token together only after
        // the complete OAuth exchange succeeds. A cancelled reauthorization
        // can therefore never pair a new API secret with an old access token.
        try keychain.save(JSONEncoder().encode(FlickrStoredState(credentials: candidateCredentials, access: candidateAccess)), account: "flickr.state.v2")
        credentials = candidateCredentials
        access = candidateAccess
    }

    func testAuthorization() async throws -> FlickrAuthorizationStatus {
        loadStoredStateIfNeeded()
        guard let credentials, let access else { throw FlickrError.notAuthorized }
        let endpoint = URL(string: "https://www.flickr.com/services/rest")!
        var parameters = oauthParameters(key: credentials.key, token: access.token)
        parameters["method"] = "flickr.test.login"
        parameters["format"] = "json"
        parameters["nojsoncallback"] = "1"
        let text = try await signedGET(endpoint, parameters: parameters, consumerSecret: credentials.secret, tokenSecret: access.secret)
        guard let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw FlickrError.api(text) }
        if json["stat"] as? String != "ok" {
            let problem = json["message"] as? String ?? text
            throw FlickrError.authorizationExpired(problem)
        }
        let user = json["user"] as? [String: Any]
        let username = ((user?["username"] as? [String: Any])?["_content"] as? String)
            ?? access.username ?? "Flickr account"
        return FlickrAuthorizationStatus(username: username, userID: user?["id"] as? String ?? access.userID)
    }

    func disconnect() throws {
        try keychain.remove(["flickr.state.v2", "flickr.credentials", "flickr.access"])
        credentials = nil
        access = nil
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
        if credentials == nil || access == nil,
           let data = keychain.load("flickr.state.v2"),
           let state = try? JSONDecoder().decode(FlickrStoredState.self, from: data) {
            credentials = state.credentials
            access = state.access
            return
        }
        if credentials == nil { credentials = keychain.load("flickr.credentials").flatMap { try? JSONDecoder().decode(FlickrCredentials.self, from: $0) } }
        if access == nil { access = keychain.load("flickr.access").flatMap { try? JSONDecoder().decode(FlickrAccess.self, from: $0) } }
        if let credentials, let access {
            try? keychain.save(JSONEncoder().encode(FlickrStoredState(credentials: credentials, access: access)), account: "flickr.state.v2")
        }
    }
    private func mimeType(for url: URL) -> String {
        UTType(filenameExtension: url.pathExtension)?.preferredMIMEType ?? "application/octet-stream"
    }
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
    func remove(_ accounts: [String]) throws {
        do { try CameraZapperCredentialVault.shared.remove(accounts) }
        catch { throw FlickrError.keychain }
    }
}

enum FlickrError: LocalizedError { case invalidCredentials, callback, keychain, notAuthorized, authorizationExpired(String), entityTooLarge, api(String)
    var errorDescription: String? { switch self { case .invalidCredentials: "Enter both the Flickr API key and secret."; case .callback: "Flickr's local authorization callback failed."; case .keychain: "Flickr credentials could not be stored in Keychain."; case .notAuthorized: "Flickr credentials are missing. Reconnect Flickr."; case .authorizationExpired(let value): "Flickr authorization is no longer valid: \(value). Reconnect Flickr."; case .entityTooLarge: "Flickr rejected the upload because the request was too large."; case .api(let value): "Flickr: \(value)" } }
}
