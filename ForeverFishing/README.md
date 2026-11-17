# ForeverFishing

Advanced fishing assistant for WoW Forever: live Auction House prices for
fish, "where to fish right now" recommendations, and a session coach.

## Install

Drop the `ForeverFishing` folder into `Interface/AddOns/`, then `/reload`.
Replace the placeholder `## Interface:` in `ForeverFishing.toc` with the value
from `/dump GetBuildInfo()` (see COMPAT.md).

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
