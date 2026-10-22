# Campaign mock tests

These are the exact self-contained Lua test harnesses used for the English edition, with the current mission script embedded. They stub DCS APIs and test all nine exercises with one player and four players in the retained two-flight layout. Tests cover menus, spawns, range bounds, completion, score deduplication, the incomplete-spawn guard and free training. They are snapshots of v1.1 EN; regenerate them when changing the mission engine.

Run with a compatible Lua 5.1 interpreter, for example:

```sh
lua5.1 tests/mock_campaign_1_players.lua
lua5.1 tests/mock_campaign_4_players.lua
```

A successful script exits without an assertion error. The original checks used the Lua runtime from the local DCS installation. These mocks do not establish in-simulator or in-flight compatibility.
