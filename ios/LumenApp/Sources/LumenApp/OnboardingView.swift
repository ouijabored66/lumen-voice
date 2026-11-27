import SwiftUI

/// First launch: API key, or the desktop server. The key is never shown again after it is saved.
struct OnboardingView: View {
    @EnvironmentObject var model: LumenModel
    var onDone: () -> Void

    @State private var choice: Choice?
    @State private var providerDraft = ""
    @State private var urls: [ServerID: String] = [:]
    @State private var drafts: [ServerID: String] = [:]
    @State private var busy = false
    @State private var pairNote = ""

    private enum Choice { case provider, server, custom }

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        Text("How should Lumen think?")
                            .font(.title2.weight(.semibold))
                            .foregroundStyle(.white)
                        Text("Speech stays on this iPhone. One key is enough, or you can run the small server on your computer.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        skipRow
                        choiceButton("Use your API key", "Grok, Claude, Gemini, Groq, or OpenRouter. The key stays in the iPhone Keychain.", .provider)
                        choiceButton("Run your own server", "Start the desktop server, then scan its QR. The provider key stays on that computer.", .server)
                        choiceButton("Cloud / custom provider", "A local or cloud chat address. Auto tries the local URL first.", .custom)
                        ServerOSIndicators(os: model.litServerOS)
                        if choice == .provider { providerForm }
                        if choice == .server { serverChecklist }
                        if choice == .custom { customForm }
                    }
                    .padding(22)
                }
            }
            .navigationTitle("Lumen Voice")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Skip") { onDone() }
                }
            }
        }
        .tint(Theme.accent)
        .onAppear {
            for s in ServerID.allCases { urls[s] = model.url(s) }
        }
    }

    private var skipRow: some View {
        HStack(spacing: 12) {
            Button("Skip for now") { onDone() }
                .font(.footnote.weight(.semibold))
            Button("Try Demo Mode") {
                Task {
                    await model.setDemoMode(true)
                    onDone()
                }
            }
            .font(.footnote.weight(.semibold))
        }
    }

    private func choiceButton(_ title: String, _ detail: String, _ value: Choice) -> some View {
        Button {
            choice = value
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline).foregroundStyle(choice == value ? .black : .white)
                Text(detail).font(.footnote).foregroundStyle(choice == value ? .black.opacity(0.75) : .secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(choice == value ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(Theme.card),
                        in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Theme.stroke))
        }
        .buttonStyle(.plain)
    }

    private var providerForm: some View {
        VStack(alignment: .leading, spacing: 12) {
            SecretEntry(title: "API Key", saved: model.providerKeySaved, suffix: model.providerKeySuffix,
                        draft: $providerDraft) { model.clearProviderKey() }
            statusBlock
            Button {
                let typed = providerDraft
                busy = true
                Task {
                    model.setLinkMode(provider: true)
                    await model.saveProviderKey(typed)
                    if model.providerStatus != .unrecognized { providerDraft = "" }
                    busy = false
                    if case .connected = model.providerStatus { onDone() }
                }
            } label: {
                HStack { Text("Save and connect"); Spacer(); if busy { ProgressView() } }
            }
            .disabled(busy)
        }
    }

    private var serverChecklist: some View {
        VStack(alignment: .leading, spacing: 16) {
            checklistRow(1, done: serverConnected, title: "Start the desktop server") {
                Text("On your computer, in the Lumen Voice folder, run:")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Text("python3 desktop/server.py")
                    .font(.system(.footnote, design: .monospaced))
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                Text("It prints a pair page such as http://192.168.x.x:8787/pair. Open that page on the computer so you can see the QR code. About five to ten minutes the first time.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            checklistRow(2, done: serverConnected, title: "Pair by QR (or type it)") {
                PairScanButton { outcome in
                    urls[.home] = model.serverURL
                    pairNote = LumenModel.pairingNote(outcome)
                }
                Text("Or type the URL and token from that page:")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                serverForm
            }
            checklistRow(3, done: serverConnected, title: "Connection test") {
                if !pairNote.isEmpty {
                    Text(pairNote)
                        .font(.footnote)
                        .foregroundStyle(serverConnected ? Theme.accent : .red)
                }
                ForEach(ServerID.allCases) { s in
                    serverStatus(s)
                }
            }
            checklistRow(4, done: serverConnected, title: "Done — try a command") {
                if serverConnected {
                    Text("You're paired. Hold the microphone or type a question. Tasks that change the computer wait for your Approve tap.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Button("Continue") { onDone() }
                        .font(.headline)
                } else {
                    Text("Pair first. Then come back here, or skip and try Demo Mode from Settings.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var serverConnected: Bool {
        ServerID.allCases.contains { if case .some(.connected) = model.serverLink[$0.rawValue] { return true }; return false }
    }

    private func checklistRow<Content: View>(_ number: Int, done: Bool, title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: done ? "checkmark.circle.fill" : "\(number).circle")
                    .foregroundStyle(done ? Theme.accent : .secondary)
                Text(title).font(.headline)
            }
            content()
                .padding(.leading, 28)
        }
    }

    private var serverForm: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(ServerID.allCases) { s in
                Text(s.label).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                TextField("https://…", text: urlBinding(s))
                    .textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
                    .padding(10)
                    .background(Theme.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                SecretEntry(title: "Server token", saved: model.serverSaved[s.rawValue] == true,
                            suffix: model.serverSuffix[s.rawValue] ?? "", draft: draftBinding(s)) {
                    model.clearServerToken(s)
                }
            }
            Button {
                busy = true
                Task {
                    model.setLinkMode(provider: false)
                    for s in ServerID.allCases {
                        let u = (urls[s] ?? "").trimmingCharacters(in: .whitespaces)
                        model.serverURL = u
                        let typed = (drafts[s] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                        if !typed.isEmpty {
                            model.setServerToken(typed, for: s)
                            drafts[s] = ""
                        }
                        if model.serverSaved[s.rawValue] == true && !u.isEmpty {
                            await model.verifyServer(s)
                        }
                    }
                    busy = false
                    if serverConnected {
                        pairNote = LumenModel.pairingNote(.connected(model.assistantTitle))
                    } else if ServerID.allCases.contains(where: { if case .some(.rejected) = model.serverLink[$0.rawValue] { return true }; return false }) {
                        pairNote = LumenModel.pairingNote(.rejected)
                    } else {
                        pairNote = LumenModel.pairingNote(.unreachable)
                    }
                }
            } label: {
                HStack { Text("Save and connect"); Spacer(); if busy { ProgressView() } }
            }
            .disabled(busy)
        }
    }

    private var customForm: some View {
        VStack(alignment: .leading, spacing: 12) {
            CustomProviderSettings()
            if model.customConnectedName != nil {
                Button("Continue") {
                    model.setConnectionMode("custom")
                    onDone()
                }
            }
        }
        .onAppear { model.setConnectionMode("custom") }
    }

    @ViewBuilder private var statusBlock: some View {
        switch model.providerStatus {
        case .idle: EmptyView()
        case .checking: ProgressView()
        case .connected(let name): ConnectedLine(name: name)
        case .rejected: Text("That API key was rejected.").font(.footnote).foregroundStyle(.red)
        case .unrecognized:
            UseCustomKeyOffer(draft: providerDraft) {
                providerDraft = ""
                choice = .custom
            }
        case .unreachable: Text("Can't reach the provider. Check your connection and try again.").font(.footnote).foregroundStyle(.red)
        }
    }

    @ViewBuilder private func serverStatus(_ s: ServerID) -> some View {
        switch model.serverLink[s.rawValue] ?? .idle {
        case .idle: EmptyView()
        case .checking: ProgressView()
        case .connected(let name): ConnectedLine(name: name)
        case .rejected: Text("That token was rejected.").font(.footnote).foregroundStyle(.red)
        case .unreachable: Text("Can't reach \(s.label). Check the URL and that the computer is on.").font(.footnote).foregroundStyle(.red)
        }
    }

    private func urlBinding(_ s: ServerID) -> Binding<String> {
        Binding(get: { urls[s] ?? "" }, set: { urls[s] = $0 })
    }

    private func draftBinding(_ s: ServerID) -> Binding<String> {
        Binding(get: { drafts[s] ?? "" }, set: { drafts[s] = $0 })
    }
}

struct UseCustomKeyOffer: View {
    @EnvironmentObject var model: LumenModel
    let draft: String
    var onUsed: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("This key doesn't match Grok, Claude, Gemini, Groq, or OpenRouter.")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Button("Use as custom provider") {
                model.useKeyAsCustom(draft)
                onUsed()
            }
            .font(.footnote)
        }
    }
}

struct SecretEntry: View {
    let title: String
    let saved: Bool
    let suffix: String
    @Binding var draft: String
    var onClear: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SecureField(title, text: $draft)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .textContentType(nil)
                .privacySensitive()
                .padding(10)
                .background(Theme.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            if saved {
                HStack {
                    Text(suffix.isEmpty ? "Saved" : "Saved · ••••\(suffix)")
                        .font(.footnote).foregroundStyle(.secondary)
                        .privacySensitive()
                    Spacer()
                    Button("Clear", role: .destructive, action: onClear).font(.footnote)
                }
            }
        }
    }
}

struct ConnectedLine: View {
    let name: String
    var body: some View {
        Label("Connected to \(name)", systemImage: "checkmark.circle.fill")
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Theme.accent)
            .accessibilityLabel("Connected to \(name)")
    }
}
