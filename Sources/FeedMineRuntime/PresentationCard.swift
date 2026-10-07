// File: PresentationCard.swift
// Module: FeedMineRuntime
// Owns: disposable immutable UI-facing projection of published card values.
// Does not own: publication authority, storage, provenance, media or action execution.

import Foundation
import FeedMineDomain
import FeedMinePublication

public enum PresentationCardLayout: String, Hashable, Sendable {
    case hero
    case thumbnail
    case textOnly
}

public enum PresentationTimestampKind: String, Hashable, Sendable {
    case authored
    case modified
    case observed
}

public struct PresentationTimestamp: Hashable, Sendable {
    public let value: Date
    public let kind: PresentationTimestampKind
}

public enum PresentationPrimaryActionKind: String, Hashable, Sendable {
    case externalURL
    case mediaPlayback
    case localContentDetail
}

/// Presentation is reconstructible; frozen publication remains the authority.
/// Action targets and backend provenance deliberately do not cross this surface.
public struct PresentationCard: Identifiable, Hashable, Sendable {
    public let id: PublicationCardID
    public let title: String?
    public let primaryText: String?
    public let timestamp: PresentationTimestamp?
    public let sourceDisplayName: String?
    public let providerDisplayName: String?
    public let layout: PresentationCardLayout
    public let mediaAspectRatio: Double?
    public let primaryActionKind: PresentationPrimaryActionKind?

    init(publishedCard: PublishedCard) {
        id = publishedCard.id
        title = publishedCard.text.title
        primaryText = publishedCard.text.primaryText
        sourceDisplayName = publishedCard.origin.sourceDisplayName
        providerDisplayName = publishedCard.origin.providerDisplayName
        timestamp = publishedCard.timestamp.map { timestamp in
            let kind: PresentationTimestampKind
            switch timestamp.kind {
            case .authored: kind = .authored
            case .modified: kind = .modified
            case .observed: kind = .observed
            }
            return PresentationTimestamp(value: timestamp.value, kind: kind)
        }
        switch publishedCard.renderContract.layout {
        case .hero: layout = .hero
        case .thumbnail: layout = .thumbnail
        case .textOnly: layout = .textOnly
        }
        mediaAspectRatio = publishedCard.renderContract.mediaAspectRatio
        switch publishedCard.primaryAction {
        case nil: primaryActionKind = nil
        case .externalURL: primaryActionKind = .externalURL
        case .mediaPlayback: primaryActionKind = .mediaPlayback
        case .localContentDetail: primaryActionKind = .localContentDetail
        }
    }
}
