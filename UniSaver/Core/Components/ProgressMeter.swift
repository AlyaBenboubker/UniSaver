import SwiftUI

struct ProgressMeter: View {
    let value: Double
    var label: String = "Structural progress"

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(label)
                Spacer()
                Text(value, format: .percent.precision(.fractionLength(0)))
                    .monospacedDigit()
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            ProgressView(value: value)
                .tint(.accentColor)
                .accessibilityLabel(label)
                .accessibilityValue(Text(value.formatted(.percent.precision(.fractionLength(0)))))
        }
    }
}
