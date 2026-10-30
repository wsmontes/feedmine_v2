# F13 R4 — global words and reader continuity

Status: implementation contract in progress. The known native R4 add/off/on/remove oracle passed ordinary assertions on 2026-10-30; full F13 recovery/UI/relaunch acceptance remains open. See docs/reviews/2026-10-30-f13-native-history-binding.md.
Baseline: `6dcf9cf4`. The preceding checkpoint made progress by recording the real host failure and a strict regression; it did not fix production.

## Intent and constraints

Adding/removing global words, selecting templates, or toggling the global master affects future publication. It must preserve the presented Edition, admitted prefix, anchor, saves and checkpoint. Explicit changes to contextual criteria still select a distinct reading history; A→B→A restores each position. Context-owned words survive global master-off, including overlapping words. Published cards and revisions remain immutable. Source alternation PD-4 remains mandatory.

Implementation stays in the existing Swift modules, SQLite/GRDB transactions and native iOS composition. These are executor decisions under the user's autonomous-work instruction. No new scheduler, global policy registry, schema-version shortcut, historical keyword subtraction or deletion of old histories.

## Separate three facts

1. Logical context: the full raw key stored by ReaderPreferencesStore, including its own words and explicit criteria. Global settings never enter this key for new contexts.
2. Historical publication: an Edition keeps its original context and revision, even if an older app folded global words into them.
3. Current publication opportunity: captures effective contextual plus global exclusions, resolved using one immutable template catalogue/language selection for that composition. The existing opportunity owner transports this value through selection and transaction commit.

FeedAssociation must expose the logical key separately from the frozen publication key. Restoration/editorial operations use the latter; context selection and UI intent use the former. Audit every association.contextKey caller before changing its meaning. The editorial revision UUID currently derives from encoded context, selection version, scoring and sequencing versions; preserve it for restored Editions. Do not change these versions merely to fix settings application.

## Durable history ownership

Introduce additive reader-history bindings: stable binding ID, unique logical key and stable runtime namespace, with Edition membership uniquely owned by a binding. Membership stores the original publication key and references the Edition; one binding may own multiple revisions. An optional active Edition pointer must reference its own membership. New first publication attaches membership and pointer in the publication transaction. Existing Edition rows are never rewritten.

Restore production history by the binding's active owned Edition, retaining PublicationHistory's existing neighbour and compatibility resolution. Do not pick the latest Edition merely by a possibly colliding publication key. Keep the existing context-key restoration API for legacy callers. Store checkpoints by binding, preserving the old context_checkpoints rows; existing save/initial-checkpoint transactions update the owning binding from Edition membership. Activation and stale callbacks obey existing reader ownership fences. A stale callback must never activate or overwrite another binding's position.

Reuse the preexisting runtime namespace when claiming an old history. For new contexts use the normal existing namespace if unowned; if it collides with a claimed legacy namespace, allocate a stable binding discriminator. This preserves old runway/high-water state without allowing two explicit contexts to share it. The exact representation is builder discretion; namespaces must be persisted, unique and covered by collision tests.

## Legacy adoption and ambiguity

Adoption is transactional and idempotent. Prefer the active checkpoint's compatible Edition when its key exactly matches either the raw logical key or the current legacy union computed from known raw preferences and settings. Otherwise use compatible exact-key historical candidates; ambiguous multiple candidates do not get merged. Claim only unowned Editions. Record the raw input key and the policy used to resolve an exact legacy-union match as adoption provenance. This records known inputs; it does not infer which historical words came from where.

If an Edition is already owned by another logical key, the new context starts its own history and namespace. Two distinct logical contexts whose legacy union is identical never borrow one another's Edition/checkpoint. Old unowned histories remain reachable.

When current intent cannot establish an unambiguous binding, show the existing history unchanged and pause future publication. Offer a recoverable choice in the existing More menu (and directly on an empty reader): “Continue with previous criteria” explicitly adopts the complete frozen criteria as contextual; “Open current criteria” explicitly selects the current raw criteria. Provide access to retained previous readings through that recovery surface. Neither choice silently deletes/merges history. No database identifiers appear in UI. pt/en copy explains that new exclusions affect future items. This ambiguity flow is an executor product decision, not an assertion about old keyword origin.

## Effective policy and race protection

Resolve explicit words and enabled templates with existing normalization/matching. Use strict settings decoding. Effective semantic equality ignores rule order and display labels; disabled global rules contribute nothing and remain stored. Context words always contribute independently.

A publication expectation includes the effective policy and immutable catalogue/language descriptor. The writer re-resolves current settings under that descriptor inside the same transaction as first/append publication and rejects stale expectations before any CardRecords, segments, checkpoint or cursor changes. Cover cold bootstrap, ordinary append, head/reoffer and media preparation; use existing source-policy transport/guard conventions. The policy guard must not change editorial revision compatibility.

Enabled unresolved template IDs or duplicate catalogue definitions pause new publication rather than silently admit unrestricted content. Master-off masks unresolved global templates; explicit context rules still apply. The editor keeps unresolved IDs visible/removable. Catalogue resolution may retry while unavailable; once available it is immutable for that composition. Editor counts and publication use the same resolver.

A semantic policy change invalidates stale prepared work and reconsiders local supply through the existing generation owner, preserving Edition and high-water. Equivalent policy changes do not reset work. Do not filter published cards. The last-notified token is only deduplication, never authority.

## Recovery and acceptance

Generalize the fixed-size More-menu recovery affordance to word/mixed filters and unresolved policies, preserving the proven zero tail displacement. Retain source-only AX identifiers where applicable. Context-owned criteria recovery opens its own editor. Never imply that global master-off disables contextual criteria.

Required proof: existing raw R4 add/off/on/remove oracle becomes normal assertions with no expected failures; future X/Y publication and reversal; context overlap; templates; stale first/append rejection with atomic no-op; relaunch; legacy adoption/collision/ambiguity; explicit A→B→A; actual pt/en large-text UI route and stable tail. Package and actual iOS host tests are separate evidence. Existing source gates and B02/B04/B05 remain open until individually verified; B03 FAIL and B06 NOT_RUN remain unchanged.

## Delivery order

First implement strict, deterministic policy resolution with unit coverage; then transactional snapshot/guard; then binding/migration/restoration tests; only then wire native composition, recovery UI and remove R4 expectations. Intermediate commits must state which contracts remain unwired. No claim of R4 success from policy-only tests.

## Builder check

A fresh independent software-engineering builder check returned “nothing important left” on 2026-10-28. The user has explicitly requested autonomous continuation, so no additional approval round is introduced. Implementation is split into independently verifiable slices; the first policy-only slice intentionally leaves the existing host failure visible.
