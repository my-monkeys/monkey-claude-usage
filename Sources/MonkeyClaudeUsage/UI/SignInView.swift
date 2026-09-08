import MonkeyClaudeUsageCore
import SwiftUI

/// The OAuth callback shows a `code#state` string the user pastes back — there is no
/// loopback listener, which is also what lets several accounts be added one by one.
struct SignInView: View {
    @ObservedObject var state: AppState
    let isFirstAccount: Bool

    @State private var code = ""
    @FocusState private var codeFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if state.pendingAuthorization == nil {
                Text(isFirstAccount ? L("no_account_title") : L("add_account"))
                    .font(.system(size: 13, weight: .semibold))

                Text(isFirstAccount ? L("no_account_body") : L("second_account_hint"))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if state.canImportClaudeCodeSession {
                    Button(L("import_cli")) {
                        Task { await state.importClaudeCodeSession() }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .frame(maxWidth: .infinity)

                    Text(L("or"))
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity)
                }

                // Importing is the shortcut; the browser flow stays available and is the
                // only way in for a second account.
                let browserFlow = Button(L("sign_in")) {
                    NSWorkspace.shared.open(state.beginSignIn())
                }
                .controlSize(.large)
                .frame(maxWidth: .infinity)

                if state.canImportClaudeCodeSession {
                    browserFlow.buttonStyle(.bordered)
                } else {
                    browserFlow.buttonStyle(.borderedProminent)
                }
            } else {
                Text(L("sign_in_hint"))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                TextField(L("paste_code"), text: $code)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12, design: .monospaced))
                    .focused($codeFocused)
                    .onSubmit(submit)

                HStack {
                    Button(L("cancel")) {
                        code = ""
                        state.cancelSignIn()
                    }
                    .controlSize(.small)

                    Spacer()

                    Button(L("validate"), action: submit)
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .disabled(code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                  || state.isExchangingCode)
                }
            }

            if let error = state.authorizationError {
                Text(error)
                    .font(.system(size: 10))
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .onAppear { codeFocused = state.pendingAuthorization != nil }
    }

    private func submit() {
        let pasted = code
        code = ""
        Task { await state.completeSignIn(code: pasted) }
    }
}
