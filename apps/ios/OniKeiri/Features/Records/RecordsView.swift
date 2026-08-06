import SwiftUI

struct RecordsView: View {
    var body: some View {
        Text("記録")
            .font(DS.Typo.body)
            .foregroundStyle(DS.Palette.text)
            .navigationTitle("記録")
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(DS.Palette.bg)
    }
}
