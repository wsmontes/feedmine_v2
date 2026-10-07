# Canonical domain model — Phase 1A

FeedMineDomain depends only on the Swift standard library and Foundation value types (`UUID`, `Date`, `URL`), never another FeedMine module. Only FeedIdentifiers.swift, Source.swift and Content.swift are implemented. All models are immutable value types conforming to Hashable, Codable and Sendable. IDs and ConnectorKind also provide string descriptions. No I/O or protocol interpretation occurs here.

## Identity

FeedMine internal identity != external identity.

SourceID, ProviderID, OriginRecordID, OriginRevisionID, SourceBindingID, ContentEntityID and ContentClusterID are separate nominal UUID wrappers. They accept an explicit UUID or generate an independent one; no ID derives from network location. SourceID cannot substitute for ProviderID even if their raw UUIDs match. FeedEditionID, FeedSegmentID, SessionID, AssetID, ActionID, PublicationCardID and AcquisitionTargetID remain documentation only.

## Sources and bindings

Source is a stable editorial entity: id, displayName, optional providerID and isEnabled. Provider is canonical producer/publisher/institutional author attribution: id and displayName. Display names are not validated in this phase. Future many-to-many source/provider relationships are not arrays embedded in these models.

Source != Provider.
Source != SourceBinding.
Source != AcquisitionTarget.
Source != endpoint.

ConnectorKind is an open string value, not a closed connector enum. Only the syndication constant is supplied. This names a connector without implementing one.

SourceBinding declaratively relates a source to an external system: id, sourceID, connectorKind, externalPrincipal, aliases, generation and state (enabled/revoked). It contains no endpoint, HTTP configuration, generic configuration blob, acquisition target or parser configuration.

generation identifies the semantic configuration revision of a SourceBinding. A semantic change to declarative acquisition authorization changes generation. The caller supplies this value; the model neither calculates nor increments it.

## Content identity and revision

ExternalIdentity is an opaque connectorKind/namespace/value/role tuple. Its exact roles are principal, object, version, alias and lookup. ExternalIdentity.value is opaque. Domain never parses protocol-specific identity, trims or lowercases it, converts URLs or derives hashes to canonicalize it.

OriginRecord represents the internal identity of a logical external object admitted to canonical supply: id, connectorKind, externalObjectIdentity, optional currentRevisionID, availability, firstObservedAt and lastObservedAt. It contains neither sourceID nor providerID, content text or raw protocol data. Availability is available, updated, removed, revoked or unknown. Removal/revocation does not imply deletion of published history.

OriginRecord != OriginRevision.

OriginRevision is an immutable accepted representation of an origin: id, originRecordID, optional externalVersionIdentity, headline, summary, bodyText, authoredAt, modifiedAt, language, primaryLink, searchProjection and providerID, plus required observedAt. Provider attribution belongs to the revision, not OriginRecord. Headline and public HTTP link may legitimately be absent.

authoredAt is external/editorial authorship time when known. modifiedAt is external/editorial modification time when known. observedAt is when FeedMine observed this accepted revision and is always FeedMine-controlled. Missing authoredAt stays missing; observedAt never substitutes for it. OriginRevision is immutable. OriginRecord.currentRevisionID is future-facing state, separate from already-published history.

## Membership and relations

SourceMembership relates an origin independently to each source with direct/derived kind and first/last observed timestamps. SourceMembership != acquisition provenance. Operational acquisition provenance will be added separately when AcquisitionTarget exists; there is no placeholder target ID.

ContentRelation is a directed origin-to-origin relationship with exactly replyTo, repostOf, quoteOf or references semantics. These are FeedMine concepts, not external protocol verbs.

## Equivalence and clusters

ContentEntity records strong equivalence between a nonempty set of origins. Its failable initializer rejects an empty set.

ContentCluster records a soft editorial relationship: id, nonempty originRecordIDs, confidence in 0...1, nonempty method and explicit version. Its failable initializer validates only these three conditions. A whitespace-only method is nonempty and is preserved. Nonfinite confidence is outside the accepted range. Codable decoding applies the same initializer invariants for entity and cluster; other values use ordinary value encoding/decoding.

ContentEntity/Cluster never destroys original evidence. Neither replaces OriginRecord, deletes OriginRevision, changes external identity nor becomes a global canonical record. No deduplication, fuzzy matching, clustering or canonical URL algorithm is implemented.

## Relationships

```text
Source
  │
  └── SourceBinding
          │
          └── external principal


external object
      │
      ▼
OriginRecord
      │
      ├── OriginRevision V1
      ├── OriginRevision V2
      └── OriginRevision V3
      │
      ├── SourceMembership ──→ Source
      └── Provider attribution ──→ Provider


OriginRecord A ──┐
OriginRecord B ──┼── ContentEntity / ContentCluster
OriginRecord C ──┘


OriginRecord A ── ContentRelation ──→ OriginRecord B
```

Provider attribution in this conceptual diagram is carried by each OriginRevision, never directly by OriginRecord. Revision labels denote successive values, not separate production types or compatibility runtimes.

## Scope

FeedContext, FeedIntent, FeedPlan, MediaCandidate and InteractionOffer remain scaffolds. Persistence, acquisition, connectors, networking, editorial selection, media preparation, publication, runtime and UI are not implemented in Phase 1A. The Publication/Persistence representation gate remains unresolved.
