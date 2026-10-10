// U1-A: the single visual-token authority for FeedMineUI.
//
// Roles, not a catalogue of aesthetic values: spacing, radius, typography roles and semantic
// colors. Deliberately NOT ported from V1: the CircadianEngine (clock-driven typography, spacing,
// radius and palette mutation), its singleton, a parallel DesignTokens/Circadian pair, or a
// darkening overlay standing in for dark mode. V1's palettes may inform individual values later;
// its time drift never does. Every value here is adaptive through the system appearance and scales
// through Dynamic Type, so the feed cannot be invalidated by a clock.
import SwiftUI

public enum FeedDesignTokens {
    /// Semantic spacing roles shared by every FeedMineUI surface.
    public enum Spacing {
        public static let tight: CGFloat = 6
        public static let compact: CGFloat = 8
        public static let normal: CGFloat = 12
        public static let card: CGFloat = 16
        public static let section: CGFloat = 16
        public static let page: CGFloat = 24
        public static let deck: CGFloat = 28
    }

    /// Corner radii by role.
    public enum Radius {
        public static let media: CGFloat = 8
        public static let card: CGFloat = 12
        public static let overlay: CGFloat = 14
    }

    /// Semantic text roles. All are Dynamic Type styles: no fixed point sizes, no time-driven
    /// weight or tracking changes.
    public enum Typography {
        public static let pageTitle: Font = .title2.weight(.semibold)
        public static let cardTitleFeatured: Font = .title2
        public static let cardTitle: Font = .headline
        public static let body: Font = .body
        public static let label: Font = .subheadline
        public static let badge: Font = .caption.weight(.medium)
        public static let metadata: Font = .caption
    }

    /// Adaptive semantic colors. They follow the system appearance; there is no appearance
    /// overlay and no appearance-driven feed invalidation.
    public enum Palette {
        public static let cardSurface: Color = .primary.opacity(0.06)
        public static let mediaPlaceholder: Color = .primary.opacity(0.08)
        public static let secondaryText: Color = .secondary
        public static let accent: Color = .accentColor
        public static let statusPositive: Color = .green
        public static let statusCaution: Color = .orange
        public static let shadow: Color = .black
    }

    /// Dimensions that must stay constant across layouts. Reader-scaled ones are resolved with
    /// `@ScaledMetric` at the view, never with a clock.
    public enum Measurement {
        /// Compact-row thumbnail reference side; the view scales it with the reader's text size.
        public static let compactThumbnailBase: CGFloat = 88
        /// Maximum readable content width; wider displays keep editorial text readable instead of
        /// stretching a single column across the window.
        public static let readableContentWidth: CGFloat = 700
        public static let headlineDeckWidth: CGFloat = 420
        public static let sourceCloudWidth: CGFloat = 520
        public static let deckSymbolWidth: CGFloat = 28
        public static let wordmarkWidth: CGFloat = 180
    }

    /// Exact catalog names of the reviewed V1 branding imagesets. Named constants, never a name
    /// built from a palette suffix: V1 constructed `Placeholder-Article-<palette>` names that do
    /// not exist in its own catalog, and U1 must not reproduce that.
    public enum AssetName {
        public static let wordmarkLight = "Wordmark-Light"
        public static let wordmarkDark = "Wordmark-Dark"
        public static let symbolGradient = "Symbol-Gradient"

        /// The legible wordmark for the current appearance. Both names exist in the catalog.
        public static func wordmark(for scheme: ColorScheme) -> String {
            scheme == .dark ? wordmarkDark : wordmarkLight
        }
    }
}
