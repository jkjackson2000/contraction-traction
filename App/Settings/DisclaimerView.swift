import SwiftUI

enum Disclaimer {
    static let text = "Timing tool, not medical advice. Follow your provider's instructions. In an emergency, call 911 or your local emergency number."
}

struct DisclaimerView: View {
    let onAccept: () -> Void

    var body: some View {
        // Scrolls when it doesn't fit (large text), so the emergency line is
        // always reachable.
        ViewThatFits(in: .vertical) {
            content
            ScrollView { content }
        }
        .safeAreaInset(edge: .bottom) {
            Button(action: onAccept) {
                Text("Got it")
                    .font(.title3.weight(.bold))
                    .frame(maxWidth: .infinity, minHeight: 56)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.capsule)
            .padding(.horizontal, 28)
            .padding(.vertical, 12)
            .background(Theme.background)
        }
        .background(Theme.background.ignoresSafeArea())
    }

    private var content: some View {
        VStack(spacing: 28) {
            Spacer()
            Image(systemName: "heart.text.square.fill")
                .font(.system(size: 64))
                .foregroundStyle(Theme.resting)
                .accessibilityHidden(true)
            VStack(spacing: 14) {
                Text("Before you start")
                    .font(.system(.largeTitle, design: .rounded).weight(.bold))
                Text("Timing tool, not medical advice.")
                    .font(.title3.weight(.semibold))
                Text("Follow your provider's instructions.\nIn an emergency, call 911 or your local emergency number.")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            .multilineTextAlignment(.center)
            Spacer()
            Text("Nothing leaves your phone unless you share it.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(28)
        .frame(maxWidth: .infinity)
    }
}
