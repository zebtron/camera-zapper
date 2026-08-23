import AppKit
import CryptoKit
import Darwin
import Foundation
import Security

struct GoogleOAuthCredentials: Codable, Sendable {
    struct Installed: Codable, Sendable {
        let client_id: String
        let client_secret: String?
        let auth_uri: String
        let token_uri: String
    }
    let installed: Installed
}

private struct GoogleToken: Codable, Sendable {
    var accessToken: String
    var refreshToken: String?
    var expiresAt: Date
}

actor GooglePhotosClient {
    private let keychain = CameraZapperKeychain()
    private var credentials: GoogleOAuthCredentials?
    private var token: GoogleToken?
    private var youtubeToken: GoogleToken?
    private var lastPhotosRequestAt = Date.distantPast

    init() { }

    var isConfigured: Bool { credentials != nil || UserDefaults.standard.bool(forKey: "authorized.googlePhotos") }
    var isAuthorized: Bool { token?.refreshToken != nil || (token?.expiresAt ?? .distantPast) > .now || UserDefaults.standard.bool(forKey: "authorized.googlePhotos") }
    var isYouTubeAuthorized: Bool { youtubeToken?.refreshToken != nil || (youtubeToken?.expiresAt ?? .distantPast) > .now || UserDefaults.standard.bool(forKey: "authorized.youtube") }

    func importAndAuthorize(data: Data) async throws {
        let parsed = try JSONDecoder().decode(GoogleOAuthCredentials.self, from: data)
        guard parsed.installed.client_id.hasSuffix(".apps.googleusercontent.com") else { throw GooglePhotosError.invalidCredentials }
        credentials = parsed
        try keychain.save(data, account: "google.oauth.credentials")
        token = try await authorize(parsed.installed, scope: "https://www.googleapis.com/auth/photoslibrary.appendonly")
        try saveToken()
    }

    func authorizeYouTube() async throws {
        loadStoredStateIfNeeded()
        guard let credentials else { throw GooglePhotosError.api("Configure Google Photos OAuth once first; Camera Zapper will reuse that Google desktop client for YouTube.") }
        youtubeToken = try await authorize(credentials.installed, scope: "https://www.googleapis.com/auth/youtube.upload")
        try keychain.save(JSONEncoder().encode(youtubeToken), account: "youtube.oauth.token")
    }

    func uploadToYouTube(file: URL, title: String) async throws -> String {
        let access = try await validYouTubeAccessToken()
        var components = URLComponents(string: "https://www.googleapis.com/upload/youtube/v3/videos")!
        components.queryItems = [.init(name: "uploadType", value: "resumable"), .init(name: "part", value: "snippet,status"), .init(name: "notifySubscribers", value: "false")]
        var start = URLRequest(url: components.url!); start.httpMethod = "POST"
        start.setValue("Bearer \(access)", forHTTPHeaderField: "Authorization")
        start.setValue("application/json", forHTTPHeaderField: "Content-Type")
        start.setValue(mimeType(file), forHTTPHeaderField: "X-Upload-Content-Type")
        start.httpBody = try JSONSerialization.data(withJSONObject: ["snippet": ["title": String(title.prefix(100)), "description": "Uploaded by Zebtron Camera Zapper", "categoryId": "22"], "status": ["privacyStatus": "private", "selfDeclaredMadeForKids": false]])
        let (startData, startResponse) = try await URLSession.shared.data(for: start)
        try validate(startResponse, data: startData)
        guard let location = (startResponse as? HTTPURLResponse)?.value(forHTTPHeaderField: "Location"), let uploadURL = URL(string: location) else { throw GooglePhotosError.api("YouTube did not provide a resumable upload URL") }
        var upload = URLRequest(url: uploadURL); upload.httpMethod = "PUT"; upload.setValue(mimeType(file), forHTTPHeaderField: "Content-Type")
        let (data, response) = try await URLSession.shared.upload(for: upload, fromFile: file)
        try validate(response, data: data)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let id = json?["id"] as? String else { throw GooglePhotosError.api("YouTube upload returned no video ID") }
        return "https://youtu.be/\(id)"
    }

    func createAlbum(title: String) async throws -> String {
        let accessToken = try await validAccessToken()
        var request = URLRequest(url: URL(string: "https://photoslibrary.googleapis.com/v1/albums")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["album": ["title": title]])
        let (data, response) = try await photosData(for: request)
        try validate(response, data: data)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let id = json?["id"] as? String else { throw GooglePhotosError.api("Album creation returned no ID") }
        return id
    }

    func upload(file: URL, filename: String, albumID: String) async throws -> String {
        let accessToken = try await validAccessToken()
        var upload = URLRequest(url: URL(string: "https://photoslibrary.googleapis.com/v1/uploads")!)
        upload.httpMethod = "POST"
        upload.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        upload.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        upload.setValue(mimeType(file), forHTTPHeaderField: "X-Goog-Upload-Content-Type")
        upload.setValue("raw", forHTTPHeaderField: "X-Goog-Upload-Protocol")
        let (uploadData, uploadResponse) = try await photosUpload(for: upload, file: file)
        try validate(uploadResponse, data: uploadData)
        let uploadToken = String(decoding: uploadData, as: UTF8.self)

        var create = URLRequest(url: URL(string: "https://photoslibrary.googleapis.com/v1/mediaItems:batchCreate")!)
        create.httpMethod = "POST"
        create.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        create.setValue("application/json", forHTTPHeaderField: "Content-Type")
        create.httpBody = try JSONSerialization.data(withJSONObject: ["albumId": albumID, "newMediaItems": [["simpleMediaItem": ["fileName": filename, "uploadToken": uploadToken]]]])
        let (resultData, resultResponse) = try await photosData(for: create)
        try validate(resultResponse, data: resultData)
        let json = try JSONSerialization.jsonObject(with: resultData) as? [String: Any]
        let first = (json?["newMediaItemResults"] as? [[String: Any]])?.first
        if let status = first?["status"] as? [String: Any], let code = status["code"] as? Int, code != 0 {
            throw GooglePhotosError.api(status["message"] as? String ?? "Google Photos rejected the item")
        }
        let media = first?["mediaItem"] as? [String: Any]
        return media?["productUrl"] as? String ?? "googlephotos://\(media?["id"] as? String ?? filename)"
    }

    private func authorize(_ client: GoogleOAuthCredentials.Installed, scope: String) async throws -> GoogleToken {
        let callback = try LoopbackOAuthCallback.start()
        let verifier = randomURLSafe(count: 64)
        let challenge = Data(SHA256.hash(data: Data(verifier.utf8))).base64URLEncodedString()
        let state = randomURLSafe(count: 32)
        var components = URLComponents(string: client.auth_uri)!
        components.queryItems = [
            .init(name: "client_id", value: client.client_id), .init(name: "redirect_uri", value: callback.redirectURI),
            .init(name: "response_type", value: "code"), .init(name: "scope", value: scope),
            .init(name: "access_type", value: "offline"), .init(name: "prompt", value: "consent"), .init(name: "state", value: state),
            .init(name: "code_challenge", value: challenge), .init(name: "code_challenge_method", value: "S256")
        ]
        _ = await MainActor.run { NSWorkspace.shared.open(components.url!) }
        let result = try await callback.waitForCode()
        guard result.state == state else { throw GooglePhotosError.invalidState }
        return try await exchange(code: result.code, redirectURI: callback.redirectURI, verifier: verifier, client: client)
    }

    private func exchange(code: String, redirectURI: String, verifier: String, client: GoogleOAuthCredentials.Installed) async throws -> GoogleToken {
        var items = [URLQueryItem(name: "code", value: code), .init(name: "client_id", value: client.client_id), .init(name: "redirect_uri", value: redirectURI), .init(name: "grant_type", value: "authorization_code"), .init(name: "code_verifier", value: verifier)]
        if let secret = client.client_secret { items.append(.init(name: "client_secret", value: secret)) }
        return try await tokenRequest(items, endpoint: client.token_uri, priorRefresh: nil)
    }

    private func validAccessToken() async throws -> String {
        loadStoredStateIfNeeded()
        if let token, token.expiresAt > Date().addingTimeInterval(60) { return token.accessToken }
        guard let credentials, let refresh = token?.refreshToken else { throw GooglePhotosError.notAuthorized }
        var items = [URLQueryItem(name: "client_id", value: credentials.installed.client_id), .init(name: "refresh_token", value: refresh), .init(name: "grant_type", value: "refresh_token")]
        if let secret = credentials.installed.client_secret { items.append(.init(name: "client_secret", value: secret)) }
        token = try await tokenRequest(items, endpoint: credentials.installed.token_uri, priorRefresh: refresh)
        try saveToken()
        return token!.accessToken
    }

    private func validYouTubeAccessToken() async throws -> String {
        loadStoredStateIfNeeded()
        if let youtubeToken, youtubeToken.expiresAt > Date().addingTimeInterval(60) { return youtubeToken.accessToken }
        guard let credentials, let refresh = youtubeToken?.refreshToken else { throw GooglePhotosError.notAuthorized }
        var items = [URLQueryItem(name: "client_id", value: credentials.installed.client_id), .init(name: "refresh_token", value: refresh), .init(name: "grant_type", value: "refresh_token")]
        if let secret = credentials.installed.client_secret { items.append(.init(name: "client_secret", value: secret)) }
        youtubeToken = try await tokenRequest(items, endpoint: credentials.installed.token_uri, priorRefresh: refresh)
        try keychain.save(JSONEncoder().encode(youtubeToken), account: "youtube.oauth.token")
        return youtubeToken!.accessToken
    }

    private func loadStoredStateIfNeeded() {
        if credentials == nil { credentials = keychain.load("google.oauth.credentials").flatMap { try? JSONDecoder().decode(GoogleOAuthCredentials.self, from: $0) } }
        if token == nil { token = keychain.load("google.oauth.token").flatMap { try? JSONDecoder().decode(GoogleToken.self, from: $0) } }
        if youtubeToken == nil { youtubeToken = keychain.load("youtube.oauth.token").flatMap { try? JSONDecoder().decode(GoogleToken.self, from: $0) } }
    }

    private func tokenRequest(_ items: [URLQueryItem], endpoint: String, priorRefresh: String?) async throws -> GoogleToken {
        var request = URLRequest(url: URL(string: endpoint)!)
        request.httpMethod = "POST"; request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var body = URLComponents(); body.queryItems = items; request.httpBody = body.percentEncodedQuery?.data(using: .utf8)
        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response, data: data)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let access = json?["access_token"] as? String else { throw GooglePhotosError.api("No access token returned") }
        return .init(accessToken: access, refreshToken: json?["refresh_token"] as? String ?? priorRefresh, expiresAt: Date().addingTimeInterval(json?["expires_in"] as? Double ?? 3600))
    }

    private func saveToken() throws { if let token { try keychain.save(JSONEncoder().encode(token), account: "google.oauth.token") } }
    private func waitForPhotosQuotaSlot() async throws {
        // Google currently grants 30 write requests/minute/user. Keep a little
        // headroom so clock drift and retries do not trigger a 429 response.
        let delay = 2.15 - Date().timeIntervalSince(lastPhotosRequestAt)
        if delay > 0 { try await Task.sleep(for: .seconds(delay)) }
        lastPhotosRequestAt = .now
    }
    private func photosData(for request: URLRequest) async throws -> (Data, URLResponse) {
        var attempt = 0
        while true {
            try await waitForPhotosQuotaSlot()
            let result = try await URLSession.shared.data(for: request)
            if let http = result.1 as? HTTPURLResponse, http.statusCode == 429 {
                attempt += 1
                guard attempt <= 6 else { throw GooglePhotosError.rateLimited }
                let serverDelay = http.value(forHTTPHeaderField: "Retry-After").flatMap(Double.init) ?? 65
                try await Task.sleep(for: .seconds(max(serverDelay, min(300, pow(2, Double(attempt)) * 5))))
                continue
            }
            return result
        }
    }
    private func photosUpload(for request: URLRequest, file: URL) async throws -> (Data, URLResponse) {
        var attempt = 0
        while true {
            try await waitForPhotosQuotaSlot()
            let result = try await URLSession.shared.upload(for: request, fromFile: file)
            if let http = result.1 as? HTTPURLResponse, http.statusCode == 429 {
                attempt += 1
                guard attempt <= 6 else { throw GooglePhotosError.rateLimited }
                let serverDelay = http.value(forHTTPHeaderField: "Retry-After").flatMap(Double.init) ?? 65
                try await Task.sleep(for: .seconds(max(serverDelay, min(300, pow(2, Double(attempt)) * 5))))
                continue
            }
            return result
        }
    }
    private func validate(_ response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            if let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let error = root["error"] as? [String: Any] {
                let message = error["message"] as? String ?? "Request failed"
                let details = error["details"] as? [[String: Any]] ?? []
                let activation = details.compactMap { ($0["metadata"] as? [String: Any])?["activationUrl"] as? String }.first
                if let activation, let url = URL(string: activation) { throw GooglePhotosError.serviceDisabled(message, url) }
                throw GooglePhotosError.api(message)
            }
            throw GooglePhotosError.api(String(decoding: data, as: UTF8.self))
        }
    }
    private func randomURLSafe(count: Int) -> String { String((0..<count).map { _ in "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~".randomElement()! }) }
    private func mimeType(_ url: URL) -> String { switch url.pathExtension.lowercased() { case "jpg", "jpeg": "image/jpeg"; case "heic": "image/heic"; case "png": "image/png"; case "mov": "video/quicktime"; case "mp4", "m4v": "video/mp4"; default: "application/octet-stream" } }
}

private final class LoopbackOAuthCallback: @unchecked Sendable {
    let socketFD: Int32
    let redirectURI: String
    private init(socketFD: Int32, port: UInt16) { self.socketFD = socketFD; redirectURI = "http://127.0.0.1:\(port)/oauth/callback" }
    deinit { Darwin.close(socketFD) }
    static func start() throws -> LoopbackOAuthCallback {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { throw GooglePhotosError.callback }
        var reuse: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &reuse, socklen_t(MemoryLayout.size(ofValue: reuse)))
        var address = sockaddr_in(sin_len: UInt8(MemoryLayout<sockaddr_in>.size), sin_family: sa_family_t(AF_INET), sin_port: 0, sin_addr: in_addr(s_addr: inet_addr("127.0.0.1")), sin_zero: (0,0,0,0,0,0,0,0))
        let bound = withUnsafePointer(to: &address) { pointer in pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) } }
        guard bound == 0, listen(fd, 1) == 0 else { Darwin.close(fd); throw GooglePhotosError.callback }
        var actual = sockaddr_in(); var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        let named = withUnsafeMutablePointer(to: &actual) { pointer in pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(fd, $0, &length) } }
        guard named == 0 else { Darwin.close(fd); throw GooglePhotosError.callback }
        return .init(socketFD: fd, port: UInt16(bigEndian: actual.sin_port))
    }
    func waitForCode() async throws -> (code: String, state: String) {
        let fd = socketFD
        return try await Task.detached {
            let client = accept(fd, nil, nil)
            guard client >= 0 else { throw GooglePhotosError.callback }
            defer { Darwin.close(client) }
            var buffer = [UInt8](repeating: 0, count: 16_384)
            let count = recv(client, &buffer, buffer.count, 0)
            guard count > 0 else { throw GooglePhotosError.callback }
            let line = String(decoding: buffer.prefix(count), as: UTF8.self).components(separatedBy: "\r\n").first ?? ""
            let target = line.split(separator: " ").dropFirst().first.map(String.init) ?? ""
            let components = URLComponents(string: "http://localhost" + target)
            let code = components?.queryItems?.first(where: { $0.name == "code" })?.value
            let state = components?.queryItems?.first(where: { $0.name == "state" })?.value
            let response = "HTTP/1.1 200 OK\r\nContent-Type: text/html; charset=utf-8\r\nConnection: close\r\n\r\n<html><body><h2>Camera Zapper is authorized.</h2><p>You may close this window.</p></body></html>"
            _ = response.withCString { send(client, $0, strlen($0), 0) }
            guard let code, let state else { throw GooglePhotosError.callback }
            return (code, state)
        }.value
    }
}

private struct CameraZapperKeychain: Sendable {
    func save(_ data: Data, account: String) throws {
        do { try CameraZapperCredentialVault.shared.save(data, account: account) }
        catch { throw GooglePhotosError.keychain }
    }
    func load(_ account: String) -> Data? { CameraZapperCredentialVault.shared.load(account) }
}

enum GooglePhotosError: LocalizedError { case invalidCredentials, invalidState, callback, notAuthorized, keychain, rateLimited, serviceDisabled(String, URL), api(String)
    var activationURL: URL? { if case .serviceDisabled(_, let url) = self { url } else { nil } }
    var errorDescription: String? { switch self { case .invalidCredentials: "The selected JSON is not a Google desktop OAuth client file."; case .invalidState: "Google OAuth state validation failed."; case .callback: "The local OAuth callback failed."; case .notAuthorized: "Google Photos is not authorized."; case .keychain: "The OAuth credential could not be stored in Keychain."; case .rateLimited: "Google Photos kept rate-limiting requests after automatic retries. Wait several minutes and resume Catch Up."; case .serviceDisabled: "Google Photos Library API is disabled for this OAuth project. Enable it, wait a few minutes, then retry Catch Up."; case .api(let text): "Google Photos: \(text)" } }
}

private extension Data { func base64URLEncodedString() -> String { base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "") } }
