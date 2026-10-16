import Foundation

// Compiles the exact iOS transport/model sources against macOS Foundation for live TLS contract testing.
@main
struct TransportTests {
    static func main() async throws {
        guard let text = readLine() else { fatalError("Expected a local pairing link on stdin") }
        let link = try PairingLink(text)
        do {
            _ = try PairingLink("watchbridge://pair?endpoint=http://example.com&pin=bad&code=x")
            fatalError("Insecure pairing link was accepted")
        } catch { }
        let connection = try await BridgeClient.pair(link, deviceID: UUID().uuidString.lowercased(), name: "Synthetic transport test")
        let batchID = UUID().uuidString.lowercased()
        let record = HealthRecord(id: UUID().uuidString.lowercased(), start: "2026-10-16T00:30:00+08:00",
            end: "2026-10-16T00:31:00+08:00", value: 42, unit: "count", source_name: "Synthetic Watch",
            source_bundle: "local.watchbridge.test", device_model: "Synthetic", metadata: SampleMetadata())
        let payload = SyncPayload(batch_id: batchID, type: "steps", cursor: "synthetic", samples: [record], deleted: [])
        do {
            let _: SyncAcknowledgement = try await BridgeClient.request("v1/sync", endpoint: connection.endpoint,
                pin: String(repeating: "0", count: 64), token: connection.token, body: payload, reply: SyncAcknowledgement.self)
            fatalError("Wrong certificate pin was accepted")
        } catch { }
        let ack = try await BridgeClient.request("v1/sync", endpoint: connection.endpoint, pin: connection.fingerprint,
            token: connection.token, body: payload, reply: SyncAcknowledgement.self)
        precondition(ack.ok && ack.batch_id == batchID && ack.accepted == 1)
        print("Swift TLS pairing, certificate mismatch rejection, authenticated upload, and acknowledgement checks passed.")
    }
}
