// File: ReaderScaledFont.swift
// Module: FeedMineUI
// Owns: the one place card text turns a V1 point size into a Dynamic Type-aware `Font` (F-UI-4).
// Does not own: what the reader's type scale is (`ReaderTypeScale`) or the palette.
//
// Why `@ScaledMetric` and not a text style: V1's ruler gives three sizes per role (small/medium/large)
// and the ruler is frozen. A text style would discard those sizes; `.system(size:)` is fixed by
// definition. `@ScaledMetric` multiplies the ruler's size by the reader's text-size setting, which is the
// same mechanism `FeedItemCardView.overlayBadgeSide` already uses for the bookmark badge.

import SwiftUI

/// Applies a reader font at the size the reader's Dynamic Type setting resolves to.
public struct ReaderScaledFont: ViewModifier {
    private let style: ReaderFontStyle
    private let weight: Font.Weight
    @ScaledMetric private var size: CGFloat

    /// A role's V1 size, scaled.
    public init(appearance: ReaderAppearance, role: ReaderFontRole) {
        self.style = appearance.fontStyle
        self.weight = role.defaultWeight
        _size = ScaledMetric(
            wrappedValue: appearance.typeScale.size(for: role),
            relativeTo: role.textStyle)
    }

    /// An explicit V1 size for text that has no role yet, scaled against `textStyle`.
    public init(appearance: ReaderAppearance, size: CGFloat, textStyle: Font.TextStyle,
        weight: Font.Weight = .regular) {
        self.style = appearance.fontStyle
        self.weight = weight
        _size = ScaledMetric(wrappedValue: size, relativeTo: textStyle)
    }

    public func body(content: Content) -> some View {
        content.font(ReaderAppearance.font(style: style, size: size, weight: weight))
    }
}

public extension View {
    /// Card text: the role's frozen V1 size, resolved through the reader's Dynamic Type setting.
    func readerFont(_ role: ReaderFontRole, in appearance: ReaderAppearance) -> some View {
        modifier(ReaderScaledFont(appearance: appearance, role: role))
    }

    /// Text without a role: an explicit frozen V1 size, still resolved through Dynamic Type.
    func readerFont(size: CGFloat, relativeTo textStyle: Font.TextStyle,
                    in appearance: ReaderAppearance, weight: Font.Weight = .regular) -> some View {
        modifier(ReaderScaledFont(appearance: appearance, size: size, textStyle: textStyle, weight: weight))
    }
}
