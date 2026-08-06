import SwiftUI

struct SettingsView: View {
    var body: some View {
        Text("設定")
            .font(DS.Typo.body)
            .foregroundStyle(DS.Palette.text)
            .navigationTitle("設定")
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(DS.Palette.bg)
    }
}
