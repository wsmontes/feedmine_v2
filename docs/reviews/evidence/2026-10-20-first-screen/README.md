# First presented screen — 2026-10-20

Source run (simulator `FeedMine Fresh`, 92CDD7F7-724B-42D2-A1AA-3B7051E2DD65):

```
xcodebuild -project FeedMineApp/FeedMineApp.xcodeproj -scheme FeedMine -configuration Debug \
  -destination 'platform=iOS Simulator,id=92CDD7F7-724B-42D2-A1AA-3B7051E2DD65' \
  -derivedDataPath /private/tmp/fm-firstscreen-derived -parallel-testing-enabled NO \
  -resultBundlePath /private/tmp/fm-firstscreen-20261020-103552.xcresult \
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
wait_passes=4 kind=launch-progress first_wait_ms=724 last_wait_ms=1020 cards=1 first_cards_ms=1304 content_bottom=141 viewport_height=730
```

`first-presented-screen.json` is the new criterion's complete `VISIBLE_FIRST_SCREEN_JSON` line, verbatim.
`first-screen-2026-10-20-100754.json` is the earlier run the architect quoted (`cards=1 first_cards_ms=1716`,
viewport 402×752, tallest card 141.83 pt), preserved unchanged for the audit trail; its `covered_fraction` field
was the criterion that has now been removed. Screenshot,
accessibility tree and the same JSON are attached to the test in the result bundle under
`first-presented-screen-*`.

Reading: the first card-carrying presentation laid out one card (141 pt) in a 730 pt viewport; the content
therefore stopped 589 pt before the viewport bottom. The product fix (hold the presentation until the screen is
covered) is the architect's; this evidence is the red side of that criterion.
