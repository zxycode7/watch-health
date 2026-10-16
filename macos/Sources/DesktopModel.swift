import SwiftUI
import AppKit
import CryptoKit

struct MCPTool: Identifiable, Decodable { var id: String { name }; let name: String; let description: String }

@MainActor
final class DesktopModel: ObservableObject {
    let directory: URL
    let database: LocalDatabase
    @Published var snapshot: DatabaseSnapshot?
    @Published var page = RecordPage(rows: [], total: 0)
    @Published var recordRefreshVersion = 0
    @Published var loading = false
    @Published var loadingPage = false
    @Published var error: String?
    @Published var pageError: String?
    @Published var serviceOnline = false
    @Published var tools: [MCPTool] = []
    @Published var mcpResult = "尚未检测"
    @Published var mcpConfigured = false
    @Published var actionMessage: String?
    @Published var runningAction = false
    @Published var pairingLink: String?
    @Published var pairingExpiry: Date?
    private var requestVersion = 0
    var runtime: URL { directory.appendingPathComponent("runtime") }
    var python: String {
        let path = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/LaunchAgents/local.watchbridge.sync.plist")
        if let data = try? Data(contentsOf: path), let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any], let args = plist["ProgramArguments"] as? [String], let first = args.first { return first }
        return ["/opt/homebrew/bin/python3", "/usr/local/bin/python3", "/Library/Frameworks/Python.framework/Versions/3.12/bin/python3", "/usr/bin/python3"].first { FileManager.default.isExecutableFile(atPath: $0) } ?? "/usr/bin/python3"
    }
    init(directory: URL? = nil) {
        let path = directory ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/WatchBridge")
        self.directory = path
        self.database = LocalDatabase(directory: path)
    }
    func refresh() async {
        guard !loading else { return }
        loading = true
        defer { loading = false }
        do { snapshot = try await database.snapshot(); error = nil }
        catch { self.error = error.localizedDescription }
        await checkService()
    }
    func load(metric: HealthMetric, start: Date, end: Date, source: String, offset: Int) async {
        requestVersion += 1
        let version = requestVersion
        loadingPage = true
        page = RecordPage(rows: [], total: 0)
        pageError = nil
        do {
            let next = try await database.page(metric: metric, start: start, end: end, source: source, offset: offset)
            guard version == requestVersion else { return }
            page = next
        } catch {
            guard version == requestVersion else { return }
            pageError = error.localizedDescription
        }
        if version == requestVersion { loadingPage = false }
    }
    func checkService() async {
        do {
            let pem = try String(contentsOf: directory.appendingPathComponent("certificate.pem"), encoding: .utf8)
            let encoded = pem.components(separatedBy: .newlines).filter { !$0.hasPrefix("---") }.joined()
            guard let der = Data(base64Encoded: encoded) else { serviceOnline = false; return }
            let pin = SHA256.hash(data: der).map { String(format: "%02x", $0) }.joined()
            let delegate = CertificatePin(expected: pin, host: "127.0.0.1")
            let config = URLSessionConfiguration.ephemeral; config.timeoutIntervalForRequest = 3
            let session = URLSession(configuration: config, delegate: delegate, delegateQueue: nil)
            defer { session.invalidateAndCancel() }
            let (_, response) = try await session.data(from: URL(string: "https://127.0.0.1:8765/healthz")!)
            serviceOnline = (response as? HTTPURLResponse)?.statusCode == 200
        } catch { serviceOnline = false }
    }
    nonisolated static func run(_ executable: String, _ args: [String], input: Data? = nil) async throws -> Data {
        try await Task.detached {
            let process = Process(); process.executableURL = URL(fileURLWithPath: executable); process.arguments = args
            let output = Pipe(); let stdinPipe = Pipe(); process.standardOutput = output; process.standardError = FileHandle.nullDevice
            process.standardInput = stdinPipe
            var environment = ProcessInfo.processInfo.environment
            environment["PYTHONDONTWRITEBYTECODE"] = "1" // The signed application bundle must remain immutable.
            process.environment = environment
            try process.run()
            let watchdog = DispatchWorkItem { if process.isRunning { process.terminate() } }
            DispatchQueue.global().asyncAfter(deadline: .now() + 45, execute: watchdog)
            defer { watchdog.cancel() }
            if let input { stdinPipe.fileHandleForWriting.write(input) }
            try? stdinPipe.fileHandleForWriting.close()
            let data = output.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { throw BridgeError.message("本机命令未完成。请检查 Python 版本、本机服务安装状态后重试。") }
            return data
        }.value
    }
    func checkMCP() async {
        guard !runningAction else { return }
        runningAction = true; mcpResult = "正在检测…"
        defer { runningAction = false }
        do {
            let configCode = "import tomllib,pathlib,json,sys; p=pathlib.Path.home()/'.codex/config.toml'; d=tomllib.loads(p.read_text()) if p.exists() else {}; e=d.get('mcp_servers',{}).get('watchbridge',{}); print(json.dumps({'configured':e.get('enabled',True) and e.get('command')==sys.argv[3] and e.get('args')==[sys.argv[1],'mcp'] and e.get('env',{}).get('WATCHBRIDGE_HOME')==sys.argv[2]}))"
            let config = try await Self.run(python, ["-c", configCode, runtime.appendingPathComponent("scripts/run.py").path, directory.path, python])
            mcpConfigured = ((try? JSONSerialization.jsonObject(with: config) as? [String: Bool])?["configured"]) == true
            let messages: [[String: Any]] = [
                ["jsonrpc":"2.0", "id":1, "method":"initialize", "params":["protocolVersion":"2025-11-25"]],
                ["jsonrpc":"2.0", "id":2, "method":"tools/list"],
                ["jsonrpc":"2.0", "id":3, "method":"tools/call", "params":["name":"watchbridge_status", "arguments":[:]]]
            ]
            var input = Data()
            for message in messages { input.append(try JSONSerialization.data(withJSONObject: message)); input.append(10) }
            let output = try await Self.run(python, [runtime.appendingPathComponent("scripts/run.py").path,"mcp"], input: input)
            let replies = output.split(separator: 10).compactMap { try? JSONSerialization.jsonObject(with: Data($0)) as? [String: Any] }
            guard let list = replies.first(where: { ($0["id"] as? Int) == 2 })?["result"] as? [String: Any], let definitions = list["tools"],
                let last = replies.first(where: { ($0["id"] as? Int) == 3 })?["result"] as? [String: Any], last["isError"] as? Bool == false else { throw BridgeError.message("MCP 未返回完整响应，请检查本机服务版本。") }
            tools = try JSONDecoder().decode([MCPTool].self, from: JSONSerialization.data(withJSONObject: definitions))
            mcpResult = mcpConfigured ? "已注册 · 初始化、工具列表与数据状态查询通过" : "服务可用 · 尚未注册到 Codex"
        } catch { mcpResult = error.localizedDescription }
    }
    func pair() async {
        guard !runningAction else { return }
        runningAction = true; actionMessage = nil
        defer { runningAction = false }
        do {
            let data = try await Self.run(python, [runtime.appendingPathComponent("scripts/run.py").path,"pair"])
            guard let link = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines), (try? PairingLink(link)) != nil else { throw BridgeError.message("未收到有效配对信息，请检查本机服务。") }
            pairingLink = link; pairingExpiry = Date().addingTimeInterval(300)
        } catch { actionMessage = error.localizedDescription }
    }
    func installService() async {
        guard !runningAction, let resources = Bundle.main.resourceURL else { return }
        runningAction = true; actionMessage = "正在备份并更新本机服务…"
        defer { runningAction = false }
        do {
            _ = try await Self.run(python, [resources.appendingPathComponent("Service/scripts/install_mac.py").path,"--upgrade"])
            actionMessage = "本机服务已安装或更新，数据与配对已保留。"
            await refresh()
        } catch { actionMessage = error.localizedDescription }
    }
    func closePairing() { pairingLink = nil; pairingExpiry = nil }
    func service(start: Bool) async {
        guard !runningAction else { return }
        runningAction = true; actionMessage = nil
        defer { runningAction = false }
        do {
            let domain = "gui/\(getuid())"
            let plist = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/LaunchAgents/local.watchbridge.sync.plist").path
            _ = try await Self.run("/bin/launchctl", start ? ["bootstrap",domain,plist] : ["bootout",domain+"/local.watchbridge.sync"])
            actionMessage = start ? "已请求启动服务，点击刷新核对连接。" : "接收服务已停止，已有数据仍可查询。"
            await checkService()
        } catch { actionMessage = error.localizedDescription }
    }
}
