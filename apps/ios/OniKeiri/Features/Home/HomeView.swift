import SwiftUI

struct HomeView: View {
    var body: some View {
        Text("ホーム")
            .font(DS.Typo.body)
            .foregroundStyle(DS.Palette.text)
            .navigationTitle("ホーム")
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(DS.Palette.bg)
    }
}
