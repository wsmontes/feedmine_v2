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
public struct Source: Hashable, Codable, Sendable {
    public let id: SourceID
    public let displayName: String
    public let providerID: ProviderID?
    public let isEnabled: Bool

    public init(
        id: SourceID,
        displayName: String,
        providerID: ProviderID?,
        isEnabled: Bool
    ) {
        self.id = id
        self.displayName = displayName
        self.providerID = providerID
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
public struct SourceBinding: Hashable, Codable, Sendable {
    public let id: SourceBindingID
    public let sourceID: SourceID
    public let connectorKind: ConnectorKind
    public let externalPrincipal: ExternalIdentity
    public let aliases: [ExternalIdentity]
    public let generation: UInt64
    public let state: SourceBindingState

    public init(
        id: SourceBindingID,
        sourceID: SourceID,
        connectorKind: ConnectorKind,
        externalPrincipal: ExternalIdentity,
        aliases: [ExternalIdentity],
        generation: UInt64,
        state: SourceBindingState
    ) {
        self.id = id
        self.sourceID = sourceID
        self.connectorKind = connectorKind
        self.externalPrincipal = externalPrincipal
        self.aliases = aliases
        self.generation = generation
        self.state = state
    }
}
