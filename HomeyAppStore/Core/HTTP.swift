import Foundation

struct APIError: LocalizedError, Sendable {
    let status: Int
    let message: String
    let url: String

    /// Underlying network error code (offline, timeout, …) when the request never got an answer.
    var urlErrorCode: URLError.Code? = nil

    init(status: Int, message: String, url: String, urlErrorCode: URLError.Code? = nil) {
        self.status = status
        self.message = message
        self.url = url
        self.urlErrorCode = urlErrorCode
    }

    var errorDescription: String? {
        status == 0 ? message : "HTTP \(status): \(message)"
    }
    var isUnauthorized: Bool { status == 401 }
    var isCancelled: Bool { urlErrorCode == .cancelled }
    var isOffline: Bool {
        guard let urlErrorCode else { return false }
        return [.notConnectedToInternet, .networkConnectionLost, .dataNotAllowed, .internationalRoamingOff].contains(urlErrorCode)
    }
}

/// Plain Dutch text for any error; `nil` for cancelled requests (those are silent).
enum ErrorText {
    static func message(_ error: Error) -> String? {
        if error is CancellationError { return nil }
        if let e = error as? APIError {
            if e.isCancelled { return nil }
            if let code = e.urlErrorCode { return network(code) }
            switch e.status {
            case 401: return L("Je sessie is verlopen. Log opnieuw in.")
            case 403: return L("Je hebt hier geen toestemming voor.")
            case 404: return L("Niet gevonden.")
            case 429: return L("Te veel verzoeken. Probeer het zo opnieuw.")
            case 500...599: return L("De server van Homey heeft een probleem. Probeer het later opnieuw.")
            default: return e.message.isEmpty ? L("Er ging iets mis.") : e.message
            }
        }
        if let u = error as? URLError {
            if u.code == .cancelled { return nil }
            return network(u.code)
        }
        return error.localizedDescription
    }

    private static func network(_ code: URLError.Code) -> String {
        switch code {
        case .notConnectedToInternet, .dataNotAllowed, .internationalRoamingOff: return L("Je bent offline. Controleer je internetverbinding.")
        case .networkConnectionLost: return L("De verbinding werd verbroken. Probeer het opnieuw.")
        case .timedOut: return L("Het duurde te lang voordat er antwoord kwam. Probeer het opnieuw.")
        case .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed: return L("Kan de server niet bereiken.")
        case .secureConnectionFailed, .serverCertificateUntrusted: return L("Kon geen veilige verbinding maken.")
        default: return L("Netwerkfout. Probeer het opnieuw.")
        }
    }
}

enum HTTP {
    static let session: URLSession = {
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = 20
        cfg.timeoutIntervalForResource = 600
        cfg.waitsForConnectivity = false
        return URLSession(configuration: cfg)
    }()

    /// For calls that may legitimately take minutes (installing a big app with `waitForInstall`).
    static let longSession: URLSession = {
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = 300
        cfg.timeoutIntervalForResource = 600
        cfg.waitsForConnectivity = false
        return URLSession(configuration: cfg)
    }()

    struct Response: Sendable {
        let status: Int
        let data: Data
        let headers: [String: String]
        var json: JSON { JSON.parse(data) }
    }

    @discardableResult
    static func send(
        _ url: URL,
        method: String = "GET",
        headers: [String: String] = [:],
        body: Data? = nil,
        timeout: TimeInterval? = nil
    ) async throws -> Response {
        var req = URLRequest(url: url)
        if let timeout { req.timeoutInterval = timeout }
        req.httpMethod = method
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue("HomeyStore-iOS/\(Config.appVersion) (\(Config.appBuild))", forHTTPHeaderField: "User-Agent")
        for (k, v) in headers { req.setValue(v, forHTTPHeaderField: k) }
        if let body {
            req.httpBody = body
            if req.value(forHTTPHeaderField: "Content-Type") == nil {
                req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            }
        }
        let (data, resp): (Data, URLResponse)
        do {
            let s = (timeout ?? 0) > 20 ? longSession : session
            (data, resp) = try await s.data(for: req)
        } catch {
            let code = (error as? URLError)?.code ?? (error is CancellationError ? .cancelled : nil)
            throw APIError(status: 0, message: ErrorText.message(URLError(code ?? .unknown)) ?? error.localizedDescription,
                           url: url.absoluteString, urlErrorCode: code)
        }
        let http = resp as? HTTPURLResponse
        let status = http?.statusCode ?? 0
        var hdrs: [String: String] = [:]
        http?.allHeaderFields.forEach { if let k = $0.key as? String { hdrs[k] = "\($0.value)" } }
        guard (200..<300).contains(status) else {
            let j = JSON.parse(data)
            var msg = j.firstString("message", "error_description", "error")
            if msg.isEmpty { msg = String(data: data.prefix(300), encoding: .utf8) ?? L("Onbekende fout") }
            throw APIError(status: status, message: msg, url: url.absoluteString)
        }
        return Response(status: status, data: data, headers: hdrs)
    }

    static func formBody(_ params: [String: String]) -> Data {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        let s = params.map { k, v in
            "\(k.addingPercentEncoding(withAllowedCharacters: allowed) ?? k)=\(v.addingPercentEncoding(withAllowedCharacters: allowed) ?? v)"
        }.joined(separator: "&")
        return Data(s.utf8)
    }
}

enum JWT {
    /// Expiry (minus a 60s safety margin) of a JWT, or nil when it can't be read.
    static func expiry(_ token: String) -> Date? {
        let parts = token.split(separator: ".")
        guard parts.count >= 2 else { return nil }
        var b64 = String(parts[1]).replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while b64.count % 4 != 0 { b64 += "=" }
        guard let data = Data(base64Encoded: b64), let exp = JSON.parse(data)["exp"].double else { return nil }
        return Date(timeIntervalSince1970: exp - 60)
    }
}
