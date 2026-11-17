# COMPAT.md - probe findings, unconfirmed IDs, cut features

## Step 0 probe: NOT YET RUN (requires in-game access)

This addon was authored without a running WoW Forever client, so the mandatory
in-game probe has **not been executed**. Before first use, run this probe and
fill in the results below.

Probe addon (paste into a temp addon or a chat macro line by line):

```lua
/dump GetBuildInfo()
/dump C_AuctionHouse ~= nil
/dump QueryAuctionItems ~= nil, GetAuctionItemInfo ~= nil
/dump GetSkillLineInfo ~= nil, C_SkillLine ~= nil
/dump C_Map ~= nil
/dump GetGameTime ~= nil
/dump GetNumAuctionItems ~= nil
```

Also measure the AH query cooldown if any (time between accepted
`QueryAuctionItems` calls at a busy AH), and the Fishing spellID
(`/dump select(1, GetSpellInfo(7620))` and any replacement).

### Probe results (to fill in)

| Check | Result | Notes |
|---|---|---|
| Build (`GetBuildInfo()`) | UNMEASURED | must replace the placeholder `## Interface:` in the .toc |
| `C_AuctionHouse` present | UNMEASURED | newer API path |
| `QueryAuctionItems`/`GetAuctionItemInfo` present | UNMEASURED | Era API path |
| Skill API (`C_SkillLine` vs `GetSkillLineInfo`) | UNMEASURED | |
| `C_Map` present | UNMEASURED | |
| `GetGameTime` present | UNMEASURED | |
| AH query cooldown | UNMEASURED | tune `PriceDB.SCAN_PAGE_DELAY` |
| Fishing spellID | assumed 7620 | verify; used for cast counting |

The code never assumes: `API.lua` feature-detects every one of these at load
and nil-guards each call, so the addon loads on either API family.

## Unconfirmed itemIDs (ALL are Classic-era hypotheses - verify each against ForeverDB)

| Fish | itemID used | Status |
|---|---|---|
| Raw Brilliant Smallfish | 6289 | unconfirmed |
| Oily Blackmouth | 6361 | unconfirmed |
| Firefin Snapper | 6362 | unconfirmed |
| Raw Greater Sagefish | 8365 | unconfirmed |
| Deviate Fish | 6522 | unconfirmed |
| Raw Nightfin Snapper | 13756 | unconfirmed |
| Raw Sunscale Salmon | 13754 | unconfirmed |
| Raw Glowing Brightfish | 13759 | unconfirmed |
| Raw Mightfish | 13760 | unconfirmed |
| Winter Squid | 13755 | unconfirmed - possible collision with Raw Redgill in some DBs |
| Raw Summer Bass | 13758 | unconfirmed |
| Stonescale Eel | 13761 | unconfirmed |

Zone mapIDs (1411-1452 range values in `FishDB.ZONES`) are Classic mapID
hypotheses - verify via `C_Map.GetMapInfo` / `/dump GetCurrentMapAreaID()`.

## Cut features (anti-botting rule)

- No auto-recast, no auto-loot, no unattended fishing of any kind.
- The optional cast keybind was **cut** in this revision to stay clearly on the
  safe side of the spec ("if a feature smells like botting, cut it"). Cast
  counting is passive (spell-cast event) only. Re-add a one-press-one-cast
  override binding only if explicitly requested.
- No web API anywhere; the optional SavedVariables companion-sync stretch
  module was **not built** - the addon is fully standalone.
- No embedded libraries; no Ace3 (probe not run). Hand-rolled only.

## Known limitations

- Era AH path pages the full list and filters client-side; a full pass at a
  busy AH takes a while and is throttled (one query in flight, 0.35 s/page).
- Lure bonus detection parses buff names; exotic lures may need a
  `FF.LURE_BONUS_BY_NAME` entry.
- `GetServerTime` falls back to local time if `GetGameTime` is missing
  (flagged: wrong near server-midnight offsets).

## 2026-11-17 live fix (friend Windows client, build 1.60.1, interface 16001)
- /ff scan start failed with "bad argument #1" from
  C_AuctionHouse.SendSearchQuery: API.AHSearch passed an empty string
  where an ItemKey table is required. C_AuctionHouse confirmed present.
- Fix: modern scan rewritten as per-fish ItemKey searches
  (API.AHItemKey / AHSearchItem / AHResultsReady / AHCheapestPerUnit,
  PriceDB._ScanTickModern). Legacy paging kept as _ScanTickEra.
  The replicate read path (AHResultCount/AHReadItem) is now unused by
  the modern driver and remains unprobed. Rest of the probe still open.

## 2026-11-17 UI restyle (v0.2.0)
- Deep-water + gold theme: gradient panel interior, gold title with
  fish icon, tabs moved inside the panel with gold active marker,
  divider lines, styled session overlay and minimap ring.
- Real bug fixed on the way: Refresh() re-renders every 0.5s and the
  old cleanup only removed frames (GetChildren), so FontStrings and
  Textures leaked on every refresh. All render regions now go through
  a recycle pool in UI.lua.
