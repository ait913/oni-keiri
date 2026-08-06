import AuthenticationServices
import SwiftUI

struct SignInView: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 28) {
            Spacer()

            VStack(spacing: 12) {
                Text("鬼")
                    .font(.system(size: 44, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 72, height: 72)
                    .background(DS.Palette.red, in: Circle())

                Text("鬼個人経理")
                    .font(DS.Typo.title)
                    .foregroundStyle(DS.Palette.text)
            }

            VStack(spacing: 10) {
                SignInWithAppleButton(.signIn) { request in
                    AppleSignIn.makeRequest(request)
                } onCompletion: { result in
                    Task { await handleAppleCompletion(result) }
                }
                .signInWithAppleButtonStyle(.black)
                .frame(height: 50)
                .clipShape(Capsule())
                .accessibilityLabel("Appleでサインイン")

                Text("Appleでサインイン")
                    .font(DS.Typo.caption)
                    .foregroundStyle(DS.Palette.textSub)
            }
            .padding(.horizontal, 32)

            if let errorMessage {
                Text(errorMessage)
                    .font(DS.Typo.caption)
                    .foregroundStyle(DS.Palette.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DS.Palette.bg)
    }

    private func handleAppleCompletion(_ result: Result<ASAuthorization, Error>) async {
        do {
            let idToken = try AppleSignIn.identityToken(from: try result.get())
            try await environment.auth.signInWithApple(idToken: idToken)
        } catch {
            errorMessage = "サインインできませんでした。時間をおいてもう一度お試しください。"
        }
    }
}
