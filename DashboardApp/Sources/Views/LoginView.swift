import SwiftUI

struct LoginView: View {
    @EnvironmentObject var state: AppState
    @EnvironmentObject var l10n: L10n
    @State private var user = "admin"
    @State private var pass = ""
    @State private var server = ""
    @State private var showServer = false
    @State private var busy = false
    @State private var err: String?
    @FocusState private var focus: Int?

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                Spacer(minLength: 60)
                ZStack {
                    RoundedRectangle(cornerRadius: 26, style: .continuous).fill(Theme.primary).frame(width: 92, height: 92)
                    Image(systemName: "building.2.crop.circle").font(.system(size: 46)).foregroundColor(.white)
                }
                VStack(spacing: 6) {
                    Text(L("login.title")).font(.system(size: 26, weight: .bold, design: .serif)).foregroundColor(Theme.text)
                    Text(L("login.sub")).font(.subheadline).foregroundColor(Theme.muted)
                }
                VStack(spacing: 12) {
                    field(L("login.user"), text: $user, secure: false, tag: 0)
                    field(L("login.pass"), text: $pass, secure: true, tag: 1)
                    if showServer {
                        field(L("login.server"), text: $server, secure: false, tag: 2)
                            .textInputAutocapitalization(.never).keyboardType(.URL)
                    }
                    if let err {
                        Text(err).font(.footnote).foregroundColor(Theme.danger).frame(maxWidth: .infinity, alignment: .leading)
                    }
                    Button(busy ? L("login.busy") : L("login.go")) { submit() }
                        .buttonStyle(PrimaryButtonStyle()).disabled(busy || pass.isEmpty)
                    Button { withAnimation { showServer.toggle() } } label: {
                        Label(server.isEmpty ? DEFAULT_BASE : server, systemImage: "server.rack")
                            .font(.caption).foregroundColor(Theme.muted).lineLimit(1)
                    }
                }
                .card(pad: 18)
                .padding(.horizontal, 16)
                HStack(spacing: 14) {
                    Button("繁中") { l10n.lang = "zh" }.foregroundColor(l10n.lang == "zh" ? Theme.primary : Theme.muted)
                    Button("EN") { l10n.lang = "en" }.foregroundColor(l10n.lang == "en" ? Theme.primary : Theme.muted)
                }.font(.footnote.weight(.semibold))
                Spacer(minLength: 40)
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .screenBackground()
        .onAppear { server = state.baseString }
    }

    @ViewBuilder
    private func field(_ title: String, text: Binding<String>, secure: Bool, tag: Int) -> some View {
        Group {
            if secure { SecureField(title, text: text) } else { TextField(title, text: text) }
        }
        .textInputAutocapitalization(.never).autocorrectionDisabled()
        .focused($focus, equals: tag)
        .submitLabel(tag == 1 ? .go : .next)
        .onSubmit { if tag == 1 { submit() } else { focus = tag + 1 } }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .background(Theme.surface2)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .foregroundColor(Theme.text)
    }

    private func submit() {
        guard !busy else { return }
        busy = true; err = nil
        Task {
            do { try await state.login(user: user, pass: pass, server: server.isEmpty ? DEFAULT_BASE : server) }
            catch { err = error.localizedDescription; Haptic.error() }
            busy = false
        }
    }
}
