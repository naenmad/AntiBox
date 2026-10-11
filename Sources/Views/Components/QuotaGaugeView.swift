import SwiftUI

/// Custom linear gauge showing remaining quota percentage
public struct QuotaGaugeView: View {
    public let percentage: Double
    public let status: QuotaStatus

    public init(percentage: Double, status: QuotaStatus) {
        self.percentage = percentage
        self.status = status
    }

    public var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                // Background Track
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(Color.primary.opacity(0.08))

                // Filled Bar
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(status.color.gradient)
                    .frame(width: max(0, min(geometry.size.width * CGFloat(percentage / 100.0), geometry.size.width)))
                    .animation(.easeInOut(duration: 0.3), value: percentage)
            }
        }
        .frame(height: 6)
    }
}
