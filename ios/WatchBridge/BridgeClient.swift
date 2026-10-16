import Foundation
import CryptoKit
import Security

final class CertificatePin: NSObject, URLSessionDelegate, URLSessionTaskDelegate, @unchecked Sendable {
    let expected: String
    let host: String
    init(expected: String, host: String) { self.expected = expected; self.host = host }

    func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge,
                    completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              challenge.protectionSpace.host == host,
              let trust = challenge.protectionSpace.serverTrust,
              let certificates = SecTrustCopyCertificateChain(trust) as? [SecCertificate],
              let certificate = certificates.first else {
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }
        let data = SecCertificateCopyData(certificate) as Data
        let fingerprint = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        guard fingerprint == expected else {
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }
        completionHandler(.useCredential, URLCredential(trust: trust))
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil) // Credentials are never forwarded to a redirected host.
    }
}

enum BridgeClient {
    static func request<Body: Encodable, Reply: Decodable>(_ path: String, endpoint: URL, pin: String,
        token: String? = nil, body: Body, reply: Reply.Type) async throws -> Reply {
        guard let host = endpoint.host, endpoint.scheme == "https" else {
            throw BridgeError.message("仅支持 HTTPS 同步地址。")
        }
        let delegate = CertificatePin(expected: pin, host: host)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 20
        configuration.timeoutIntervalForResource = 30
        configuration.httpShouldSetCookies = false
        configuration.urlCache = nil
        let session = URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        var request = URLRequest(url: endpoint.appendingPathComponent(path))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        request.httpBody = try JSONEncoder().encode(body)
        do {
            let (data, response) = try await session.data(for: request)
            guard let response = response as? HTTPURLResponse else { throw BridgeError.message("Mac 未返回有效响应。") }
            guard response.statusCode == 200 else {
                switch response.statusCode {
                case 401: throw BridgeError.connection("配对已失效，请在 Mac 上生成新链接并重新配对。")
                case 409: throw BridgeError.message("同步批次冲突。请重试，原有数据已保留。")
                case 413: throw BridgeError.message("本次数据过多，请缩短补录范围后重试。")
                default: throw BridgeError.message("Mac 同步服务返回错误（\(response.statusCode)）。请确认服务正在运行。")
                }
            }
            return try JSONDecoder().decode(Reply.self, from: data)
        } catch let error as URLError {
            if [.serverCertificateUntrusted, .secureConnectionFailed, .cancelled].contains(error.code) {
                throw BridgeError.connection("无法验证 Mac 的证书。请检查配对链接；更换证书后需要重新配对。")
            }
            throw BridgeError.connection("连接不到 Mac。请确认同一 Wi‑Fi、本地网络权限和 Mac 服务状态，再点一次同步。")
        }
    }

    static func pair(_ link: PairingLink, deviceID: String, name: String) async throws -> Connection {
        struct Body: Encodable { let code: String; let device_id: String; let name: String }
        struct Reply: Decodable { let device_id: String; let token: String }
        let result = try await request("v1/pair", endpoint: link.endpoint, pin: link.fingerprint,
            body: Body(code: link.code, device_id: deviceID, name: name), reply: Reply.self)
        guard result.device_id.lowercased() == deviceID.lowercased(), result.token.count >= 20 else {
            throw BridgeError.message("Mac 返回的配对信息不完整。")
        }
        return Connection(endpoint: link.endpoint, fingerprint: link.fingerprint, token: result.token, deviceID: deviceID)
    }
}
