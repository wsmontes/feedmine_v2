//
// File: FeedReadingWording.swift
// Module: FeedMineUI
// Owns: the one sentence the local reader shows about the text it holds — what the app knows, and nothing else.
// Does not own: whether the text is complete, whether the site exists, or whether it can be reached. None of those
//       are established when the surface renders, so none of them is stated.
//
// Why this exists (review, 2026-10-17): the surface used to say "Conteúdo parcial: o artigo completo está no site",
// which asserts two things the app has not established — that the text is truncated, and that the whole article is
// available on the site. Not being able to confirm completeness is not proof of a truncated text nor of an
// accessible article. The note therefore says only that the source supplied this text and that completeness was
// not confirmed, and names the site only when the card carries an address the app can open — as a possibility,
// never a guarantee of access or of more content.
import Foundation

/// The reader's honesty note, as values so a test can state them without rendering and so the app catalogue can be
/// checked against the exact keys the surface asks for (the `FeedEndOfContentView.message` precedent).
public enum FeedReadingWording {
    /// The note when the card carries a usable address: the site is named as a possibility, not as a destination
    /// the app can promise.
    public static let textWithSite = String(localized: """
        Texto fornecido pela fonte. Não foi possível confirmar que este texto está completo. A versão no site pode \
        conter mais conteúdo.
        """)
    /// The note when it does not: the stored text is all the app has, and it says so without promising more.
    public static let textWithoutSite = String(localized: """
        Texto fornecido pela fonte. Não foi possível confirmar que este texto está completo.
        """)

    /// The sentence the surface shows, chosen by whether it can actually offer the site.
    public static func note(offersSite: Bool) -> String {
        offersSite ? textWithSite : textWithoutSite
    }
}
