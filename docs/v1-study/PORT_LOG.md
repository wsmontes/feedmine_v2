# v1 → v2 port log

Changes that bring v1 lessons (`docs/v1-study/`) and product decisions
(`docs/product/PRODUCT_DECISIONS_2026-10-09.md`) into v2 code.

**Historical status of rounds 1–3: written without a compiler.** These changes have not been built or tested; there is no
Swift toolchain on the machine where they were written. Local compilation/validation has now begun; see `docs/reviews/OMP_VALIDATION_2026-10-09.md`. Before building on any of this, run
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

## Round 2 — 2026-10-09 (all fronts, still uncompiled)

| Commit | Change | Lesson / decision | Tests added |
| --- | --- | --- | --- |
| `fdafa3a` | The translator's version identity is the claimed date plus a SHA-256 fingerprint of the material content. An edit under an unchanged `updated`/`date_modified` is a new version and is no longer rejected forever. | PD-1, H1 follow-up 1 | `SyndicationTranslatorTests.test32` |
| `4996497` | New exposure behavior `.excludePublishedMaterial`: an edited article (collapsed title or text differs) reappears as a new card. `PublicationStore` enforces this in the append transaction. 3R5 behavior is unchanged under `.excludePublishedRevisions`. The app uses exposure policy v2. | PD-1 (amends 3R5) | `EditedArticleRecurrenceTests` |
| `e7d94b6` | Per-target backoff: delay doubles from the request timeout and is capped; one success clears it; cooling targets are skipped during planning. `executeConcurrently` runs a sliding window that refills on each completion (cores-sized in the app, 1 by default). | H2 residuals 2–3, IN-8 | `AcquisitionBackoffConcurrencyTests` |
| `b9eaca2` | M6: `forwardBeyondProbe` records a lower-bound rate instead of wiping samples. M7: a failed local slice becomes retryable after a doubling delay, and the app schedules that opportunity. M2/M5 were already solved by the driver's single-owner causal execution. | M6, M7 | `RunwayControllerTests` (M6 assertion and a new retry test) |
| `d36d25e` | End-to-end card images. See "Card images" below. | PD-5, PD-6, M15, MD-1/2/5/6 | `MediaPrefetcherTests` |
| `71f3440` | First-launch preparation built from real evidence. See "First-launch preparation" below. | PD-3, M17, INV-06 | `PreparationProgressTests` |
| `55481ec` | Tidying while the app is not visible: `MediaHousekeeping` plus `MediaTidy`. It completes media for the next cards and evicts down to the free-space-derived budget, keeping the visible window last. Published cards are never rewritten. | PD-5, PD-6 rule 3 | `MediaHousekeepingTests` |
| `251e1da` | v1 catalog import. See "v1 catalog import" below. | PD-2, CE-1 | `LegacyCatalogReaderTests`, `LegacyCatalogImportTests` |

**Card images (`d36d25e`).**
- `MediaPrefetcher` is the single media owner. It resolves the supply head with `MediaResolver`, downloads with a byte ceiling, materializes, and picks hero or thumbnail from the measured pixels.
- `MediaReadiness` feeds the `prepare` closure, so every card is either a real image or designed text-only.
- `FeedSession` decodes local assets at slot size. `FeedCardView` keeps a fixed slot height using the frozen aspect ratio.
- `MediaHTTPFetcher` handles transport. The app supplies device-measured conditions.

**First-launch preparation (`71f3440`).**
- `PreparationProgress` holds the sources, admitted headlines and a measured time estimate; `ColdFeedBootstrap` emits the evidence.
- `FeedPreparationView` shows a headline deck and source chips, with Reduce Motion support.
- `FeedWorkBadge` shows pending or failed work while cards stay visible.

**v1 catalog import (`251e1da`).**
- `LegacyCatalogReader` reads `catalog.sqlite` read-only.
- `LegacyCatalogImport` derives deterministic v8 UUIDs from the v1 canonical key.
- The app follows the bundled catalog's defaults when the file is present.

A static audit of all round-2 commits found no compile or test-consistency defects. That audit is not a build.

### Known gaps (by design or pending)
- **PD-5, unseen published cards.** Already-published but unseen cards are not re-prepared with late media. That requires a Publication successor-tail mechanism; until then, late media improves only future cards.
- **PD-1 rule 2** (at most one unseen future occurrence per origin) is not enforced.
- **PD-2 catalog file.** The 118 MB `catalog.sqlite` is not in this repo. Bundle it (LFS) or download it, then add it to the app's Copy Bundle Resources.
- **PD-2 onboarding.** Source choice and onboarding are not built. The app registers at most 64 default catalog sources.

## Round 3 — 2026-10-09 (comparative review F01–F16, uncompiled)

Commits `5906b9a` through `f0fa2ef`; the per-finding status table is in `docs/reviews/CODE_REVIEW_COMPARATIVO_2026-10-09.md` (Resposta).

Additional device checks:
11. **Slow image.** Block one image URL so it never answers. The first screen still appears within about 5 s, and that card is text-only (F03).
12. **Flaky image host.** Images return after the network recovers; they are not stuck as text-only (F04).
13. **Stationary reader.** After launch, leave the app idle. Published cards ahead keep growing to the 16-card reserve (F01).
14. **One slow feed.** The first screen appears as soon as the fast feed answers (F06).
15. **All feeds failing, then recovering.** Content arrives with no gesture (F08, F16).
16. **Background during a scheduled retry.** No work runs while hidden (F09).
17. **Tap a card.** The article opens in Safari (F10).
## Device test checklist (needs a Mac and an iPhone)

Run `swift build && swift test` first. Then on device:

1. **Cold first launch.** The preparation screen shows real source names and headlines arriving and is not a progress bar. The first screen has no two adjacent cards from the same source (PD-4).
2. **Images.**
   - Cards are hero, thumbnail or designed text-only. None show an empty image.
   - Scroll for a while: card heights never jump.
   - Slow network: more text-only cards, no stalls.
3. **Late image.** Put the app in the background and reopen it. Visible cards are unchanged (PD-5) and later cards gain images.
4. **Edited article.** Edit an item in a test feed (same guid/date, new text) and refresh. The article appears again as a new card further down (PD-1).
5. **Broken feed.** Add an unreachable feed. Other feeds still arrive and the broken one stops being retried every cycle (H2 backoff).
6. **Fast scroll.** The runway keeps up (M6). Airplane mode mid-scroll, then back: work resumes without a new gesture (M7 retry).
7. **Low Power Mode, Low Data Mode, little free space.** Smaller images; media disk use shrinks after backgrounding (PD-6 tidy).
8. **Reduce Motion.** The preparation screen stops its drift. VoiceOver reads one summary.
9. **Catalog bundled.** Feeds come from the catalog defaults; relaunch keeps the same sources (stable UUIDs).
10. **Logs.** Check `tidy evicted=… reclaimed=… budget=…` on backgrounding.

## Next candidates

- Publication successor-tail mechanism, to re-prepare unseen published cards while the app is not visible (PD-5).
- PD-1 rule 2 (one unseen future occurrence per origin).
- Onboarding / source choice over the v1 catalog (PD-2), and taxonomy/search over catalog nodes.
- Diversity beyond source alternation (provider spacing, editorial quality from catalog `quality_score`).


## Fechamento Codex — 2026-10-09

Branch `codex/omp-plan-execution`, código `f8eb67e`: fontes/contextos/busca local persistidos, cauda não vista transacional e bookmarks/uso de mídia integrados. Pacote final: 827 testes, zero falhas. Release no simulador compilou; resultados iOS e limitações estão em [relatório OMP/Codex](../reviews/OMP_VALIDATION_2026-10-09.md). O catálogo real está em LFS, mas o upload remoto foi recusado por cota excedida: clone remoto ainda precisa receber esse objeto. iPhone 14 Plus/15 indisponíveis; checklist físico e energia/térmica permanecem pendentes.
