import SwiftUI

struct RootView: View {
    @Environment(AppEnvironment.self) private var environment

    var body: some View {
        Group {
            switch environment.auth.state {
            case .unknown:
                ProgressView()
            case .signedOut:
                SignInView()
            case .signedIn:
                if environment.auth.me?.onboarded == false {
                    OnboardingView()
                } else {
                    MainTabView()
                }
            }
        }
        .task {
            await environment.auth.bootstrap()
        }
        .tint(DS.Palette.ink)
    }
}

private struct MainTabView: View {
    var body: some View {
        TabView {
            NavigationStack {
                HomeView()
            }
            .tabItem {
                Label("ホーム", systemImage: "house")
            }
            .accessibilityIdentifier("tab-home")

            NavigationStack {
                RecordsView()
            }
            .tabItem {
                Label("記録", systemImage: "list.bullet")
            }
            .accessibilityIdentifier("tab-records")

            NavigationStack {
                SettingsView()
            }
            .tabItem {
                Label("設定", systemImage: "person")
            }
            .accessibilityIdentifier("tab-settings")
        }
    }
}
