//
// File: Source.swift
// Module: FeedMineDomain
//
// Responsibility:
//   Define canonical editorial sources, provider attribution and declarative external bindings.
//
// Owns:
//   Source, Provider, ConnectorKind, SourceBinding and SourceBindingState.
//
// Does not own:
//   Endpoints, acquisition targets, connector execution or operational transport configuration.
//
// Allowed dependencies:
//   Swift standard library and Foundation value types (UUID, Date, URL).
//   No other FeedMine module dependencies.
//
// Architectural invariants:
//   INV-12, INV-13; Source != endpoint; Source != Provider; Source != SourceBinding; Source != AcquisitionTarget.
//
// Planned public surface:
//   The Phase 1A source value types; no operational acquisition API.
//
// Status:
//   Phase 1A canonical domain implementation.
//

import Foundation


/// A stable FeedMine editorial entity, not a URL, endpoint, external account or connector.
/// Source answers: through which editorial unit does content participate in FeedMine?
/// Provider answers: who is attributed as producer/editor/author for this content?
/// A Source may yield content from many Providers; a Provider may occur through many Sources.
/// Source has no ProviderID or structural Source-to-Provider relationship.
/// Current provider attribution belongs to OriginRevision.providerID.
public struct Source: Hashable, Codable, Sendable {
    public let id: SourceID
    public let displayName: String
    public let isEnabled: Bool

    public init(
        id: SourceID,
        displayName: String,
        isEnabled: Bool
    ) {
        self.id = id
        self.displayName = displayName
        self.isEnabled = isEnabled
    }
}

/// Producer, publisher or institutional author used for display and editorial diversity.
/// SourceID and ProviderID are distinct. Future many-to-many attribution is not stored as arrays here.
public struct Provider: Hashable, Codable, Sendable {
    public let id: ProviderID
    public let displayName: String

    public init(
        id: ProviderID,
        displayName: String
    ) {
        self.id = id
        self.displayName = displayName
    }
}

/// An opaque connector kind; new connectors do not require changing a central enum.
public struct ConnectorKind: Hashable, Codable, Sendable, RawRepresentable, CustomStringConvertible {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public static let syndication = ConnectorKind(rawValue: "syndication")

    public var description: String {
        rawValue
    }
}

/// Declarative authorization state of a binding; no execution behavior.
public enum SourceBindingState: String, Hashable, Codable, Sendable {
    case enabled
    case revoked
}

/// Declarative relationship between a FeedMine Source and an external system.
/// generation identifies the semantic configuration revision of a SourceBinding.
/// When declarative acquisition authorization changes semantically, generation changes.
/// The caller supplies generation explicitly; this value does not compute or increment it.
/// Operational acquisition configuration and provenance belong to a later phase.
/// ExternalIdentity owns the connector namespace; aliases share the principal connector kind.
/// This value validates only connector consistency, including during Codable decoding.
public struct SourceBinding: Hashable, Codable, Sendable {
    public let id: SourceBindingID
    public let sourceID: SourceID
    public let externalPrincipal: ExternalIdentity
    public let aliases: [ExternalIdentity]
    public let generation: UInt64
    public let state: SourceBindingState

    /// Derived from externalPrincipal; never duplicated as independent stored state.
    public var connectorKind: ConnectorKind {
        externalPrincipal.connectorKind
    }

    public init?(
        id: SourceBindingID,
        sourceID: SourceID,
        externalPrincipal: ExternalIdentity,
        aliases: [ExternalIdentity],
        generation: UInt64,
        state: SourceBindingState
    ) {
        guard aliases.allSatisfy({ $0.connectorKind == externalPrincipal.connectorKind }) else {
            return nil
        }
        self.id = id
        self.sourceID = sourceID
        self.externalPrincipal = externalPrincipal
        self.aliases = aliases
        self.generation = generation
        self.state = state
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let id = try container.decode(SourceBindingID.self, forKey: .id)
        let sourceID = try container.decode(SourceID.self, forKey: .sourceID)
        let principal = try container.decode(ExternalIdentity.self, forKey: .externalPrincipal)
        let aliases = try container.decode([ExternalIdentity].self, forKey: .aliases)
        let generation = try container.decode(UInt64.self, forKey: .generation)
        let state = try container.decode(SourceBindingState.self, forKey: .state)
        guard let binding = Self(id: id, sourceID: sourceID, externalPrincipal: principal, aliases: aliases, generation: generation, state: state) else {
            throw DecodingError.dataCorruptedError(forKey: .aliases, in: container, debugDescription: "SourceBinding aliases must share the principal connector kind.")
        }
        self = binding
    }

}
