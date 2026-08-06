import SwiftUI

struct OnboardingView: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var selection: EmploymentType?
    @State private var isSaving = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Spacer(minLength: 24)

            VStack(alignment: .leading, spacing: 8) {
                Text("働き方を教えてください")
                    .font(DS.Typo.title)
                    .foregroundStyle(DS.Palette.text)

                Text("経費入力と税金目安の表示に使います。")
                    .font(DS.Typo.caption)
                    .foregroundStyle(DS.Palette.textSub)
            }

            VStack(spacing: 10) {
                ForEach(EmploymentType.allCases) { type in
                    Button {
                        selection = type
                    } label: {
                        HStack {
                            Text(type.localizedName)
                                .font(DS.Typo.body)
                            Spacer()
                            if selection == type {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(DS.Palette.teal)
                            }
                        }
                        .foregroundStyle(DS.Palette.text)
                        .padding(16)
                        .frame(minHeight: 56)
                        .background(DS.Palette.bg)
                        .overlay {
                            RoundedRectangle(cornerRadius: DS.Radius.tile, style: .continuous)
                                .stroke(selection == type ? DS.Palette.ink : DS.Palette.line, lineWidth: 1)
                        }
                    }
                    .accessibilityIdentifier("workstyle-\(type.rawValue)")
                }
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(DS.Typo.caption)
                    .foregroundStyle(DS.Palette.red)
            }

            Spacer()

            Button {
                Task { await save() }
            } label: {
                if isSaving {
                    ProgressView()
                        .tint(.white)
                } else {
                    Text("はじめる")
                        .font(DS.Typo.body.weight(.semibold))
                }
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(selection == nil ? DS.Palette.textSub : DS.Palette.ink, in: Capsule())
            .disabled(selection == nil || isSaving)
        }
        .padding(DS.Spacing.screenMargin)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DS.Palette.bg)
    }

    private func save() async {
        guard let selection else { return }
        isSaving = true
        defer { isSaving = false }
        do {
            _ = try await environment.api.putSettings(SettingsDto(employmentType: selection, savingsGoal: nil))
            await environment.auth.refreshMe()
        } catch APIError.unauthorized {
            environment.auth.handleUnauthorized()
        } catch {
            errorMessage = "保存できませんでした。"
        }
    }
}
