import SwiftUI

struct PairingSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var model: SyncModel
    @State private var pairingText: String

    private var parsedLink: PairingLink? { try? PairingLink(pairingText) }
    private var isEmpty: Bool { pairingText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    init(model: SyncModel, initialText: String) {
        self.model = model
        _pairingText = State(initialValue: initialText)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Mac 配对链接") {
                    SecureField("粘贴 watchbridge:// 开头的链接", text: $pairingText)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .accessibilityLabel("Mac 配对链接，包含一次性配对码")
                        .accessibilityIdentifier("pairing.link")
                    PasteButton(payloadType: String.self, onPaste: paste)
                        .accessibilityLabel("粘贴配对链接")
                    if let link = parsedLink {
                        LabeledContent("将连接", value: link.endpoint.host ?? "Mac")
                        Text("证书指纹：\(link.fingerprint.prefix(12))…\(link.fingerprint.suffix(12))")
                            .font(BridgeTheme.utility).textSelection(.enabled)
                    } else {
                        Text(isEmpty
                             ? "尚未收到配对链接。请扫描 Mac 的配对二维码，或粘贴完整链接后继续。"
                             : "配对链接不完整或格式不正确。请重新生成并粘贴完整的 watchbridge://pair 链接。")
                            .font(.footnote)
                            .foregroundStyle(isEmpty ? Color.secondary : Color.red)
                            .accessibilityIdentifier("pairing.validation")
                    }
                }
                Section {
                    Button(action: confirmPairing) {
                        HStack {
                            Text("确认配对")
                            Spacer()
                            if model.isPairing { ProgressView() }
                        }.frame(minHeight: 32)
                    }
                    .accessibilityIdentifier("pairing.confirm")
                    .disabled(model.isPairing || parsedLink == nil)
                    if model.isError { Text(model.message).foregroundStyle(.red) }
                } footer: {
                    Text("只使用你自己 Mac 生成的链接。配对码 5 分钟内有效，只能使用一次。确认后，所选健康数据会发送到这台 Mac。")
                }
            }
            .navigationTitle("配对 Mac").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) {
                Button("取消", action: { dismiss() }).disabled(model.isPairing)
            } }
            .interactiveDismissDisabled(model.isPairing)
        }
        .tint(BridgeTheme.accent)
    }

    private func paste(_ strings: [String]) {
        pairingText = strings.first ?? ""
    }

    private func confirmPairing() {
        Task {
            await model.pair(pairingText)
            if !model.isError { dismiss() }
        }
    }
}
