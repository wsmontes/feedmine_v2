# First presented screen — 2026-10-20

Source run (simulator `FeedMine Fresh`, 92CDD7F7-724B-42D2-A1AA-3B7051E2DD65):

```
xcodebuild -project FeedMineApp/FeedMineApp.xcodeproj -scheme FeedMine -configuration Debug \
  -destination 'platform=iOS Simulator,id=92CDD7F7-724B-42D2-A1AA-3B7051E2DD65' \
  -derivedDataPath /private/tmp/fm-firstscreen-derived -parallel-testing-enabled NO \
  -resultBundlePath /private/tmp/fm-firstscreen-20261020-110324.xcresult \
  -testLanguage pt-BR -testRegion BR \
  -only-testing:FeedMineUITests/FeedVisibleExperienceUITests test
```

`Executed 3 tests, with 1 failure`: the first-presented-screen test is RED by design; the retry-recovery and
failure-behind-content tests pass. The failing assertion:

```
a primeira apresentação do feed não alcança o fim do viewport: the first presented content stops at 141.0 pt
of a 730.0 pt viewport: a 589.0 pt gap below the last laid-out card (epsilon 1.0 pt)
```

The app's own witness (`feed-launch-record`), copied verbatim in `witness.txt`:

```
wait_passes=4 kind=launch-progress first_wait_ms=653 last_wait_ms=929 cards=1 first_cards_ms=1144 content_bottom=141 viewport_height=730 render_ready_cards=1
```

`first-presented-screen.json` is the new criterion's complete `VISIBLE_FIRST_SCREEN_JSON` line, verbatim.
`first-screen-2026-10-20-100754.json` is the earlier run the architect quoted (`cards=1 first_cards_ms=1716`,
viewport 402×752, tallest card 141.83 pt), preserved unchanged for the audit trail; its `covered_fraction` field
was the criterion that has now been removed. Screenshot,
accessibility tree and the same JSON are attached to the test in the result bundle under
`first-presented-screen-*`.

## Criterion (D4), stated once

The first presented state passes when, on the first card-carrying record:

`content_bottom >= viewport_height - 1 pt` — the last laid-out card reaches (or passes) the viewport bottom.

`render_ready_cards` (distinct publication ids in that same layout) is recorded as information, **never** as a
threshold: the PM's corrected D4 states no universal two-card floor. The criterion is a valid editorial prefix
sufficient to fill the real viewport, judged by this geometry, not by a count.

Reading of this run: the first card-carrying presentation laid out 1 distinct card (141 pt) in a 730 pt viewport;
the content stopped 589 pt before the viewport bottom. The product fix (hold the presentation until the visible
area is filled) is the architect's; this evidence is the red side of that criterion.

## Product fix — the transition is held by the measured layout

The red run above is answered in the product, not in the criterion:

- `FeedFirstScreenGate` (`Sources/FeedMineUI/FeedFirstScreenGate.swift`) decides the surface from the **measured**
  layout — distinct laid-out cards, the lowest card bottom in viewport coordinates, and the measured viewport
  height — with the same 1 pt tolerance the criterion states. Card count is an output, never the rule.
- `FeedScreen` keeps the preparation surface over the laid-out cards while the gate says `preparation`. The cards
  are laid out (that is what makes the measurement possible); publication, admission and the cards themselves are
  unchanged, and they keep growing underneath. The view remains a renderer: the lifecycle that states the facts
  (a prepared window, the exposure, the bound) is the host's, and the cards behind the cover are hidden from the
  accessibility tree for the same reason they are invisible on screen.
- Exits are stated once and all reach a surface: offer exhausted (`endOfContent`) and transport failure
  (`unreachable`/`failed`) show what exists at once; the bounded maximum wait is the run's **measured** tolerance
  for one operation (`FeedAssociation.preparationWaitSeconds`, the number the media window and byte budget already
  read); no cards draws the existing loading/failure surface, whose copy is its work state.
- A durable restore (the window already there on the first pass) was never prepared on this screen, so it is shown
  at once — the reopen criterion is untouched.
- The launch record now states the **first exposure**, not the first layout pass (`FeedLaunchWitness
  .noteFirstExposure`, called when the reading surface is first shown), so a layout measured under the cover can
  never be reported as a first screen.

Unit evidence: `Tests/FeedMineCompositionTests/FirstScreenPresentationTests.swift` (the recorded one-card case is
held; the 729/730 boundary; one tall card passes and twelve short ones do not; exhausted/offline/bounded exits;
restore and no-card surfaces). The UI journey above remains the device-level judge; it is not re-run here.

