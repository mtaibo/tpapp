import Foundation

/// What the floating Albums/Gallery/Shared switcher currently shows inside the Photos tab.
public enum PhotosSection: String, CaseIterable, Sendable {
    case albums, gallery, shared

    var title: String {
        switch self {
        case .albums: return "Albums"
        case .gallery: return "Gallery"
        case .shared: return "Shared"
        }
    }
}

/// Shared between `RootView` (which owns the real bottom `TabView`) and `PhotoGalleryView`
/// (which drives it from its own scroll position): whether the system tab bar should be
/// swapped for the floating "…" + section-switcher pair, and which section is showing.
@MainActor
public final class PhotosTabBarState: ObservableObject {
    @Published public var isCollapsed = false
    @Published public var section: PhotosSection = .gallery

    public init() {}
}
