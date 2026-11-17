# ForeverFishing

Advanced fishing assistant for WoW Forever: live Auction House prices for
fish, "where to fish right now" recommendations, and a session coach.

## Works on every PC

Windows, macOS and Linux — the WoW client runs on all three and this addon is
pure Lua with no OS-specific code, no network access, and no external files.
All UI art is built into the game client itself (icon and border textures),
so nothing needs to be downloaded or installed alongside the addon.

It is built to never hard-break: every client API call is feature-detected and
nil-guarded, and each module initialises inside its own error guard, so one
unsupported API degrades to a missing feature instead of a Lua error.

## Install

1. Download this repo as a ZIP (Code > Download ZIP) and extract it.
2. Drop the `ForeverFishing` folder into the client's `Interface/AddOns/`.
3. `/reload` (or relog).
4. If the addon shows as disabled/out-of-date in the addon list, open
   `ForeverFishing.toc` and set `## Interface:` to your own
   `/dump GetBuildInfo()` value (see `COMPAT.md`). The shipped value (16001)
   matches the WoW Forever client.

## Commands

- `/ff panel` — open the panel (tabs: Where to Fish, Prices, Session, Options)
- `/ff scan start` — full AH scan (must be at an Auction House)
- `/ff best` — print top-3 zones to chat
- `/ff session` — session summary
- `/ff reset` — reset the session

## How prices work (and their limits)

Addons cannot access the internet. "Live prices" means prices scanned from the
in-game Auction House, stored in `SavedVariables` (`ForeverFishingDB`), and
shown with their age ("scanned 12 min ago"). Prices older than 24 h are greyed
and flagged "stale". If you never scan, the recommender falls back to clearly
labelled static value tiers ("unpriced mode").

## No automation

The addon never casts, loots, or recasts for you. It only watches and reports.
