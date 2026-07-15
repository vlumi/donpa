import SwiftUI

/// The quiet secondary pace figure ("1.84/s") used beside best times in
/// comparisons. Renders nothing when no pace was ever logged.
struct PaceText: View {
    let pace: Double?

    static func display(_ pace: Double) -> String {
        pace.formatted(.number.precision(.fractionLength(2))) + "/s"
    }

    var body: some View {
        if let pace {
            Text(verbatim: Self.display(pace))
                .font(.caption2)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
    }
}
