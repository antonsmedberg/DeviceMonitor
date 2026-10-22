import SwiftUI

/// One device in a list, 56 pt: a flat kind well (a badge only when offline or unstable), the name with its
/// favourite star and "New" badge, the address │ vendor subtitle (whole segments drop out when it does not
/// fit, by `DeviceRowFacts.subtitleFallbacks`), and a right-aligned column of latency over jitter. Latency
/// takes its state colour against the device's own usual range; an offline device shows "Offline" over when
/// it was last seen. A newcomer row has no trailing column, because its Trust button sits there.
struct DeviceRowView: View {
    let device: DeviceSnapshot
    /// The last hour's latency values, oldest first: jitter and the usual-range check.
    let samples: [Double]
    let now: Date
    /// A row in "New on your network": "Joined …" as the last subtitle segment and no trailing column.
    let isNewcomer: Bool

    /// The List row insets that make a 56 pt row around the 40 pt content.
    static let listRowInsets = EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16)

    init(device: DeviceSnapshot, samples: [Double] = [], now: Date = Date(), isNewcomer: Bool = false) {
        self.device = device
        self.samples = samples
        self.now = now
        self.isNewcomer = isNewcomer
    }

    private var badges: [DSBadge.Kind] {
        var badges: [DSBadge.Kind] = []
        if device.isFavorite { badges.append(.favorite) }
        if device.isNewcomer(now: now) { badges.append(.new) }
        return badges
    }

    var body: some View {
        let facts = DeviceRowFacts.make(device: device, samples: samples, now: now, isNewcomer: isNewcomer)
        DSListRow(
            thumbnail: DeviceThumbnail(kind: device.kind, state: device.state),
            title: device.displayName,
            badges: badges,
            subtitle: facts.subtitle,
            subtitleFallbacks: facts.subtitleFallbacks,
            primary: facts.primary,
            primaryTone: facts.primaryTone,
            secondary: facts.secondary,
            accessibilityLabel: facts.accessibilityLabel,
            accessibilityValue: facts.accessibilityValue
        )
        .contentShape(Rectangle())
    }
}
