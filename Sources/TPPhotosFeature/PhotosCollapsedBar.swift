import SwiftUI

/// The Albums/Gallery/Shared switcher: looks like a segmented control but isn't a `TabView` —
/// a capsule of plain buttons with a sliding white pill behind whichever one is selected.
private struct PhotosSectionSwitcher: View {
    @Binding var section: PhotosSection
    @Namespace private var namespace

    var body: some View {
        HStack(spacing: 2) {
            ForEach(PhotosSection.allCases, id: \.self) { candidate in
                segment(for: candidate)
            }
        }
        .padding(3)
        .glassEffect(.regular.interactive(), in: .capsule)
    }

    private func segment(for candidate: PhotosSection) -> some View {
        let isSelected = section == candidate
        return Button {
            withAnimation(.snappy(duration: 0.25)) { section = candidate }
        } label: {
            Text(candidate.title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(isSelected ? .black : .white)
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background {
                    if isSelected {
                        Capsule()
                            .fill(Color.white)
                            .matchedGeometryEffect(id: "selectedSection", in: namespace)
                    }
                }
        }
        .buttonStyle(.plain)
    }
}

/// The bottom tab bar's stand-in while scrolled into the Photos grid: a "…" pill on the left
/// that hands control back to the real `TabView` (restoring its normal "Photos" tab icon), and
/// the Albums/Gallery/Shared switcher in the middle — mirrors how Apple's own Photos app splits
/// its bottom bar into floating pieces once you scroll away from the top.
public struct PhotosCollapsedBar: View {
    @ObservedObject var state: PhotosTabBarState

    public init(state: PhotosTabBarState) {
        self.state = state
    }

    public var body: some View {
        HStack(spacing: 10) {
            Button {
                withAnimation(.snappy) { state.isCollapsed = false }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.white)
                    .frame(width: 34, height: 34)
            }
            .buttonStyle(.glass)
            .buttonBorderShape(.circle)

            PhotosSectionSwitcher(section: $state.section)
        }
    }
}
