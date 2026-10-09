# v1 → v2 port log

Changes that bring v1 lessons (`docs/v1-study/`) and product decisions
(`docs/product/PRODUCT_DECISIONS_2026-10-09.md`) into v2 code.

**Status: written without a compiler.** These changes have not been built or tested; there is no
Swift toolchain on the machine where they were written. Before building on any of this, run
`swift build && swift test` and fix whatever fails.

| Commit | Change | Lesson / decision | Tests added |
| --- | --- | --- | --- |
| `5d11c8e` | `.gitignore` for SwiftPM/Xcode artifacts (`Package.resolved` stays committed) | PD-7, review L2 | — |
| `5d90da4` | Readable text decodes the complete HTML 4.01 named entity table (`HTMLNamedEntities.swift`) instead of 18 entries | IN-6 (v1 fixed this twice) | `PublishedTextNormalizationTests.testH5bCompleteHTML4NamedEntities` |
| `796fddf` | Future `authoredAt`/`modifiedAt` clamped to `observedAt`; version identity keeps the claimed value | IN-4, review M12 | `SyndicationTranslatorTests.test26` |
| `292fea0` | https → http redirect refused (`invalidRedirectTarget`, already an operational failure) | IN-2, review M13 | `SyndicationHTTPTests.test07b` |
| `8cfc531` | Card-visual admission rules (`SyndicationMediaLocator.swift`) and more image sources. See "Media admission" below. | MD, IN quirks 4–8 | `SyndicationTranslatorTests.test27`–`test31`; `test22`/`test23` dimensions raised above the 150 px logo rule |
| `5a0149d` | Link-derived item identity normalized (`SyndicationItemIdentity.swift`): host case, `www.`, scheme, default port, trailing slash, fragment, tracking/session params. guid/id values and the opening link are unchanged. | IN-3, PD-1 rule 1 | `SyndicationTranslatorTests.test02`, `test02b` |
| `9ae4b72` | `MediaPolicy`, `MediaResolver` and `MediaRetention` as pure values. See "Media policy and retention" below. | PD-6, MD lessons 4–8 | `MediaPolicyResolverTests` (10) |
| `ee99228` | PD-4 source alternation via a new sequencing behavior. See "PD-4 source alternation" below. | PD-4, FP-11, CE-5 | `SelectionEngineTests.testPD4*` (5) |

## Details

**Media admission (`8cfc531`).**
- Relative, protocol-relative and `&amp;`-escaped locators resolve against the item link.
- Not admitted: tracking pixels, spacers, avatars, emoji, share buttons, favicons, sized variants ≤150 px, SVG, audio/video/PDF/HTML, and malformed nested schemes.
- New image sources: `media:content`, `media:group`, image enclosures (RSS and Atom), JSON image attachments, and the first content image in item HTML (aware of lazy `data-*` attributes and `srcset`, preferring ≥960 w).
- Duplicate locators collapse to one candidate.

**Media policy and retention (`9ae4b72`).**
- Pixel targets come from slot width × screen scale.
- Economy mode turns on under Low Power Mode, serious or critical thermal state, or a constrained or expensive network path.
- Byte budget = measured throughput × the runway's wait budget, capped by safety ceilings.
- The resolver picks the smallest candidate that fills the slot. If there is none, the card is a designed text-only card.
- Disk budget is derived from free space. Eviction order: far-future unseen, seen long ago, seen recently, near-future. Bookmarked media is never evicted.

**PD-4 source alternation (`ee99228`).**
- New sequencing behavior `.recencyAlternatingSources`.
- Candidates now carry their source memberships.
- The Edition tail counts as the previous card, so alternation holds across segments.
- A card that cannot be placed is held, and the supply cursor rewinds so it is considered again later.
- Single-source contexts are exempt.
- The app uses sequencing policy v2 for new Editions.

## Not done yet (next candidates)

- **PD-1:** amend the 3R5 one-occurrence-per-origin rule. Turn a material edit under an unchanged
  Atom/JSON version into a new revision instead of rejecting it (3R1).
- **PD-3:** a preparation-evidence surface (sources contacted, headlines admitted, cards prepared)
  for an entertaining first launch.
- **PD-5 / PD-6 wiring:** call `MediaResolver` from the composition `prepare` closure. Add one
  Runtime download owner with a streaming byte ceiling, a media handle on `PresentationCard`, and
  re-preparation of unseen cards while the app is not visible.
- **PD-2:** v1 catalog import with a stable v1-key → UUID mapping.
- **Review H2 residuals:** per-target backoff and bounded parallelism.
