import SwiftUI

struct MenuBarLabel: View {
    @ObservedObject var viewModel: UsageViewModel

    var body: some View {
        Text(BarLabel.text(state: viewModel.state, now: viewModel.lastUpdatedAt ?? Date()))
    }
}
