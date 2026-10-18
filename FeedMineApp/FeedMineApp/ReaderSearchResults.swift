// File: ReaderSearchResults.swift
// Module: FeedMineApp (host)
//
// Responsibility:
// R16: one search, three real authorities. A query is interpreted once (R14's expression) and each scope asks the
// authority that actually owns those results: the catalogue for sources, the library's bookmarks for saved
// occurrences, the canonical content for local articles. Results are typed, never copied into a second index.
//
// Does not own: acquisition, publication, selection or reading surfaces. A result names the real destination; the
// host navigates through the existing owners.
import Foundation
import FeedMineDomain
import FeedMinePersistence
import FeedMinePublication
import FeedMineComposition

import FeedMineAcquisition

extension AppComposition {
    /// R16: run one unified search against the real authorities. `sources` reads the shipped catalogue, `saved`
    /// the reader's own bookmarks, `articles` canonical local content. No network is consulted, so a saved search
    /// reopens offline with the same expression and scope.
    func unifiedSearch(_ term: String, scope: ReaderSearchScope, token: UInt64) -> ReaderSearchResults? {
        guard let expression = SearchExpression(query: term), expression.canSearch else { return nil }
        let authorities = searchAuthorities()
        guard let database = authorities.database else { return nil }
        var sources: [ReaderSearchResult] = []
        if scope.includesSources, let url = authorities.catalogue,
            let records = try? LegacyCatalogReader(catalogURL: url).matchingSources(query: term, limit: 40) {
            sources = records.compactMap { record in
                guard expression.matches(fields: [record.title, (record.tags ?? []).joined(separator: " "), record.key]) else {
                    return nil
                }
                let known = authorities.feeds.first { $0.principal == record.key }
                return ReaderSearchResult(id: "source:" + record.key, kind: .source,
                    title: record.title, subtitle: record.siteURL,
                    destination: .source(principal: record.key, sourceID: known?.sourceID))
            }
        }
        var saved: [ReaderSearchResult] = []
        // A saved occurrence is content: `.sources` alone does not search it.
        if scope.includesContents, let ids = try? PublicationStore(database: database).bookmarkedCardIDs() {
            let store = PublicationStore(database: database)
            saved = ids.sorted { $0.rawValue.uuidString < $1.rawValue.uuidString }.compactMap { id in
                guard let card = try? store.card(id: id),
                    expression.matches(fields: [card.title ?? "", card.primaryText ?? ""]) else { return nil }
                return ReaderSearchResult(id: "saved:" + id.rawValue.uuidString, kind: .saved,
                    title: card.title ?? "", subtitle: card.sourceDisplayName, destination: .savedCard(id))
            }
        }
        var articles: [ReaderSearchResult] = []
        if scope.includesContents {
            let content = ContentStore(database: database)
            if let window = try? content.candidateWindow(sourceID: nil, after: nil, examinedCapacity: 400) {
                let publications = PublicationStore(database: database)
                let cardIDs = (try? publications.cardIDs(originRecordIDs: window.records.map(\.originRecordID))) ?? [:]
                articles = window.records.compactMap { record in
                    guard expression.matches(fields: [record.headline ?? "", record.summary ?? "",
                        record.declaredBody ?? ""]) else { return nil }
                    let card = cardIDs[record.originRecordID]
                    return ReaderSearchResult(id: "article:" + record.originRecordID.rawValue.uuidString,
                        kind: .article, title: record.headline ?? "", subtitle: record.summary,
                        destination: .article(cardID: card, originRecordID: record.originRecordID))
                }
            }
        }
        return ReaderSearchResults(query: term, scope: scope, token: token,
            sources: sources, saved: saved, articles: articles)
    }
}
