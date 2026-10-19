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
    /// P07/R16: one page over the real local authorities, computed **off** the MainActor. The result states
    /// whether a source page or the article window was truncated and which authorities failed; truncation or a
    /// failure is never presented as an empty, complete universe.
    func unifiedSearch(_ term: String, scope: ReaderSearchScope, token: UInt64,
        sourcePage: Int = 0, articleAfter: ReaderSearchCursor? = nil) async -> ReaderSearchResults? {
        guard let expression = SearchExpression(query: term), expression.canSearch else { return nil }
        let authorities = searchAuthorities()
        guard let database = authorities.database else { return nil }
        return await ReaderLocalSearch.run(expression: expression, scope: scope, token: token,
            database: database, catalogueURL: authorities.catalogue, feeds: authorities.feeds,
            sourcePage: sourcePage, articleAfter: articleAfter)
    }
}

/// P07: the local search itself, independent of the composition root so a test can prove the failure and paging
/// contracts against real authorities. It never opens a network connection and never touches the MainActor.
enum ReaderLocalSearch {
    static func run(expression: SearchExpression, scope: ReaderSearchScope, token: UInt64,
        database: RuntimeDatabase, catalogueURL: URL?, feeds: [TrustedFeed],
        sourcePage: Int = 0, articleAfter: ReaderSearchCursor? = nil) async -> ReaderSearchResults {
        let pageSize = 40
        let articleWindow = 400
        let page = max(0, sourcePage)
        return await Task.detached(priority: .userInitiated) {
            var sources: [ReaderSearchResult] = []
            var sourceTruncated = false
            var failed: Set<ReaderSearchAuthority> = []
            if scope.includesSources {
                if let catalogueURL {
                    do {
                        let search = try LegacyCatalogReader(catalogURL: catalogueURL)
                            .matchingSources(expression: expression, limit: pageSize, offset: page * pageSize)
                        sourceTruncated = search.truncated
                        sources = search.records.map { record in
                            let known = feeds.first { $0.principal == record.key }
                            return ReaderSearchResult(id: "source:" + record.key, kind: .source,
                                title: record.title, subtitle: record.siteURL,
                                destination: .source(principal: record.key, sourceID: known?.sourceID))
                        }
                    } catch { failed.insert(.catalogue) }
                } else {
                    failed.insert(.catalogue)
                }
            }
            var saved: [ReaderSearchResult] = []
            // A saved occurrence is content: `.sources` alone does not search it.
            if scope.includesContents {
                do {
                    let store = PublicationStore(database: database)
                    let ids = try store.bookmarkedCardIDs()
                    let records = try store.cards(ids: Array(ids))
                    saved = ids.sorted { $0.rawValue.uuidString < $1.rawValue.uuidString }.compactMap { id in
                        guard let card = records[id],
                            expression.matches(fields: [card.title ?? "", card.primaryText ?? ""]) else { return nil }
                        return ReaderSearchResult(id: "saved:" + id.rawValue.uuidString, kind: .saved,
                            title: card.title ?? "", subtitle: card.sourceDisplayName, destination: .savedCard(id))
                    }
                } catch { failed.insert(.saved) }
            }
            var articles: [ReaderSearchResult] = []
            var continuation: ReaderSearchCursor?
            if scope.includesContents {
                do {
                    let content = ContentStore(database: database)
                    let cursor = articleAfter.map {
                        ContentStore.CandidateCursor(sortDate: $0.sortDate, originRecordID: $0.originRecordID)
                    }
                    let window = try content.candidateWindow(sourceID: nil, after: cursor,
                        examinedCapacity: articleWindow)
                    let publications = PublicationStore(database: database)
                    let cardIDs = try publications.cardIDs(originRecordIDs: window.records.map(\.originRecordID))
                    articles = window.records.compactMap { record in
                        guard expression.matches(fields: [record.headline ?? "", record.summary ?? "",
                            record.declaredBody ?? ""]) else { return nil }
                        return ReaderSearchResult(id: "article:" + record.originRecordID.rawValue.uuidString,
                            kind: .article, title: record.headline ?? "", subtitle: record.summary,
                            destination: .article(cardID: cardIDs[record.originRecordID],
                                originRecordID: record.originRecordID))
                    }
                    continuation = window.nextCursor.map {
                        ReaderSearchCursor(sortDate: $0.sortDate, originRecordID: $0.originRecordID)
                    }
                } catch { failed.insert(.content) }
            }
            return ReaderSearchResults(query: expression.query, scope: scope, token: token,
                sources: sources, saved: saved, articles: articles,
                sourceTruncated: sourceTruncated, articleContinuation: continuation,
                failedAuthorities: failed)
        }.value
    }
}
