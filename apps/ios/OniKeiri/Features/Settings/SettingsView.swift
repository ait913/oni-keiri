import Observation
import SwiftUI

struct SettingsView: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var viewModel = SettingsViewModel()
    @State private var showWorkStyle = false
    @State private var showSavingsGoal = false
    @State private var showDeleteAccountConfirmation = false
    @State private var accountDeleteError: String?

    var body: some View {
        ScrollView {
            VStack(spacing: DS.Spacing.sectionGap) {
                ProfileCard(me: environment.auth.me)

                switch viewModel.state {
                case .loading:
                    LoadingPlaceholderCard(height: 126)
                case .error:
                    ContentUnavailableView {
                        Label("設定を読み込めません", systemImage: "exclamationmark.triangle")
                    } actions: {
                        Button("再試行") {
                            Task { await viewModel.load(api: environment.api, auth: environment.auth) }
                        }
                    }
                case .loaded(let settings):
                    SettingsSection {
                        SettingsRow(title: "働き方", value: settings.employmentType.localizedName) {
                            showWorkStyle = true
                        }
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("経費入力・税金目安")
                                    .font(DS.Typo.body.weight(.semibold))
                                    .foregroundStyle(DS.Palette.text)
                                Text("個人事業主のときだけ有効")
                                    .font(DS.Typo.caption)
                                    .foregroundStyle(DS.Palette.textSub)
                            }
                            Spacer()
                            Toggle("", isOn: .constant(settings.employmentType == .freelance))
                                .labelsHidden()
                                .tint(DS.Palette.teal)
                                .disabled(true)
                        }
                        .padding(.vertical, 12)
                    }

                    SettingsSection {
                        SettingsRow(
                            title: "貯金目標",
                            value: settings.savingsGoal.map { YenText.string(amount: $0) } ?? "未設定"
                        ) {
                            showSavingsGoal = true
                        }
                    }

                    Button("ログアウト") {
                        Task { await environment.auth.signOut() }
                    }
                    .font(DS.Typo.body.weight(.semibold))
                    .foregroundStyle(DS.Palette.text)
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .overlay(Capsule().stroke(DS.Palette.line))

                    Button("アカウント削除") {
                        showDeleteAccountConfirmation = true
                    }
                    .font(DS.Typo.body.weight(.semibold))
                    .foregroundStyle(DS.Palette.red)
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)

                    if let accountDeleteError {
                        Text(accountDeleteError)
                            .font(DS.Typo.caption)
                            .foregroundStyle(DS.Palette.red)
                    }
                }
            }
            .padding(DS.Spacing.screenMargin)
        }
        .navigationTitle("設定")
        .background(DS.Palette.bg)
        .task(id: environment.ticker.tick) {
            await viewModel.load(api: environment.api, auth: environment.auth)
        }
        .sheet(isPresented: $showWorkStyle) {
            if let settings = viewModel.settings {
                WorkStylePickerSheet(selection: settings.employmentType) { type in
                    await viewModel.update(
                        settings: SettingsDto(employmentType: type, savingsGoal: settings.savingsGoal),
                        api: environment.api,
                        auth: environment.auth,
                        ticker: environment.ticker
                    )
                }
            }
        }
        .sheet(isPresented: $showSavingsGoal) {
            if let settings = viewModel.settings {
                SavingsGoalSheet(current: settings.savingsGoal) { goal in
                    await viewModel.update(
                        settings: SettingsDto(employmentType: settings.employmentType, savingsGoal: goal),
                        api: environment.api,
                        auth: environment.auth,
                        ticker: environment.ticker
                    )
                }
            }
        }
        .confirmationDialog("アカウントを削除しますか", isPresented: $showDeleteAccountConfirmation, titleVisibility: .visible) {
            Button("アカウントを削除する", role: .destructive) {
                Task {
                    accountDeleteError = nil
                    do {
                        try await environment.api.deleteAccount()
                        await environment.auth.signOut()
                    } catch APIError.unauthorized {
                        environment.auth.handleUnauthorized()
                    } catch {
                        accountDeleteError = "アカウントを削除できませんでした。"
                    }
                }
            }
            Button("キャンセル", role: .cancel) {}
        } message: {
            Text("すべての記録と設定が削除されます。この操作は取り消せません。")
        }
    }
}

@MainActor
@Observable
final class SettingsViewModel {
    enum State: Equatable {
        case loading
        case loaded(SettingsDto)
        case error
    }

    private(set) var state: State = .loading
    private(set) var settings: SettingsDto?

    func load(api: APIClient, auth: AuthStore) async {
        state = .loading
        do {
            let loaded = try await api.settings()
            settings = loaded
            state = .loaded(loaded)
        } catch APIError.unauthorized {
            auth.handleUnauthorized()
        } catch {
            state = .error
        }
    }

    func update(settings next: SettingsDto, api: APIClient, auth: AuthStore, ticker: RefreshTicker) async {
        do {
            let updated = try await api.putSettings(next)
            settings = updated
            state = .loaded(updated)
            ticker.bump()
            await auth.refreshMe()
        } catch APIError.unauthorized {
            auth.handleUnauthorized()
        } catch {
            state = .error
        }
    }
}

private struct ProfileCard: View {
    let me: MeResponse?

    var body: some View {
        HStack(spacing: 12) {
            Text("鬼")
                .font(DS.Typo.body.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 46, height: 46)
                .background(DS.Palette.red, in: Circle())
            VStack(alignment: .leading, spacing: 3) {
                Text(me?.user.name ?? "鬼個人経理")
                    .font(DS.Typo.body.weight(.semibold))
                    .foregroundStyle(DS.Palette.text)
                Text(me?.user.email ?? "Apple ID でログイン中")
                    .font(DS.Typo.caption)
                    .foregroundStyle(DS.Palette.textSub)
                    .lineLimit(1)
            }
            Spacer()
        }
        .padding(DS.Spacing.cardPadding)
        .background(DS.Palette.bg)
        .overlay(RoundedRectangle(cornerRadius: DS.Radius.card).stroke(DS.Palette.line))
    }
}

private struct SettingsSection<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        VStack(spacing: 0) {
            content
        }
        .padding(.horizontal, DS.Spacing.cardPadding)
        .background(DS.Palette.bg)
        .overlay(RoundedRectangle(cornerRadius: DS.Radius.card).stroke(DS.Palette.line))
    }
}

private struct SettingsRow: View {
    let title: String
    let value: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Text(title)
                    .font(DS.Typo.body.weight(.semibold))
                    .foregroundStyle(DS.Palette.text)
                Spacer()
                Text(value)
                    .font(DS.Typo.caption)
                    .foregroundStyle(DS.Palette.textSub)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(DS.Palette.textSub)
            }
            .frame(height: 52)
        }
    }
}

struct WorkStylePickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var selection: EmploymentType
    let onSave: (EmploymentType) async -> Void

    init(selection: EmploymentType, onSave: @escaping (EmploymentType) async -> Void) {
        _selection = State(initialValue: selection)
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            List(EmploymentType.allCases) { type in
                Button {
                    selection = type
                } label: {
                    HStack {
                        Text(type.localizedName)
                        Spacer()
                        if selection == type {
                            Image(systemName: "checkmark")
                                .foregroundStyle(DS.Palette.teal)
                        }
                    }
                }
                .foregroundStyle(DS.Palette.text)
            }
            .navigationTitle("働き方")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        Task {
                            await onSave(selection)
                            dismiss()
                        }
                    }
                }
            }
        }
    }
}

struct SavingsGoalSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var amount: AmountInput
    let onSave: (Int?) async -> Void

    init(current: Int?, onSave: @escaping (Int?) async -> Void) {
        _amount = State(initialValue: AmountInput(amount: current ?? 0))
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Text(YenText.string(amount: amount.amount))
                    .font(DS.Typo.display)
                    .foregroundStyle(amount.amount == 0 ? DS.Palette.textSub : DS.Palette.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                SavingsGoalKeypad(amount: $amount)
                Button("保存") {
                    Task {
                        await onSave(amount.amount > 0 ? amount.amount : nil)
                        dismiss()
                    }
                }
                .font(DS.Typo.body.weight(.semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(DS.Palette.ink, in: Capsule())

                Button("目標を解除") {
                    Task {
                        await onSave(nil)
                        dismiss()
                    }
                }
                .font(DS.Typo.body.weight(.semibold))
                .foregroundStyle(DS.Palette.textSub)
            }
            .padding(DS.Spacing.screenMargin)
            .background(DS.Palette.bg)
            .navigationTitle("貯金目標")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

private struct SavingsGoalKeypad: View {
    @Binding var amount: AmountInput
    private let keys: [KeypadKey] = [.digit(1), .digit(2), .digit(3), .digit(4), .digit(5), .digit(6), .digit(7), .digit(8), .digit(9), .doubleZero, .digit(0), .backspace]
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 10), count: 3)

    var body: some View {
        LazyVGrid(columns: columns, spacing: 10) {
            ForEach(keys) { key in
                Button {
                    amount.tap(key)
                } label: {
                    Text(key.label)
                        .font(DS.Typo.title)
                        .foregroundStyle(DS.Palette.text)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(DS.Palette.bgSoft, in: RoundedRectangle(cornerRadius: DS.Radius.tile, style: .continuous))
                }
            }
        }
    }
}
