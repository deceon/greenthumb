# Greenthumb — SotA crop tracker (v0.1 MVP spec)

Author: **Kronic** (gaming identity; commits as Kronic). Repo: `E:\dev\sota\addons\greenthumb`, linked into
`%APPDATA%\Catnip Games\Shroud of the Avatar(DEV)\Lua\greenthumb\`.
Data credit: SotA Lore Farming Planner (https://www.sotalore.com/farming) — credit in README.

## Goal of 0.1
Track planters by hand and never miss a watering window. The player taps **Planted / Watered / Harvested**;
Greenthumb does the timing math, shows countdowns, and alerts in chat + on screen.

## Farming rules
- Base growth: Quick 24 h, Medium 48 h, Slow 72 h (outside).
- Location multiplier: Outside x1, Greenhouse x0.5, Inside x10.
- T = base x multiplier. Four waterings for full yield: water 1 at planting (Planted counts as water 1),
  then window k (k = 1..3) runs from (k-1)*T/3 to k*T/3. Harvest at T.
- A window that closes with no water -> `missed += 1`.

## Seed table (built in: name, speed, avg yield, price gold)
Quick: Garlic Plant Seed 16/8, Pumpkin Plant Seed 4/6, Carrot Plant Seed 8/8, Lettuce Plant Seed 8/8,
Pepper Plant Seed 8/8, Potato Plant Seed 8/8, Tomato Plant Seed 8/8, Blue/Orange/Pink/Red/Yellow Rose Bush Seed 7/10.
Medium: Mandrake Plant Seed 32/16, Nightshade Plant Seed 32/16, Banana Tree Seed 16/16, Barley Plant Seed 16/16,
Corn Plant Seed 16/16, Cotton Bush Seed 9/16, Hops Plant Seed 16/16, Lemon Tree Seed 16/16, Onion Plant Seed 16/16,
Red Grape Plant Seed 16/16, Wheat Plant Seed 16/16, White Grape Plant Seed 16/16.
Slow: Coconut Plant Seed 18/30, Small Apple Tree Seed 28/30, Tea Leave Seed 18/30.

## Features (0.1)
1. **Plant**: at a planter, open Plant dialog -> searchable seed picker + location toggle (Outside/Greenhouse/Inside)
   + optional name ("Back garden 3"). Save zone (ShroudGetCurrentSceneName), position (ShroudPlayerX/Y/Z; Y is height),
   seed, location, plantedAt (os.time()).
2. **Timers**: each planter shows "Water in 2h 10m" / "Water now (closes in 3h)" / "Missed a watering" / "Ready to harvest".
   **Watered** records the water for the current window.
3. **Alerts**: chat line + on-screen notice when a window opens, 1 h before it closes, and when ready. Each type toggleable.
   Alert once per planter per window.
4. **Overview window**: scrolling list (zone, name, crop, next action, time left), sorted soonest first, zone filter.
   **Harvested** clears or one-click replants the same seed.
5. **Catch-up on login**: timers use real time, so on load show anything due/overdue.

Commands: `/greenthumb` (open), `/gt plant <seed>`, `/gt water`, `/gt list`, `/gt due`.

## Saved data (character scope: ShroudGetSavedVar / ShroudSetSavedVar)
- `greenthumb_planters`: records `id|zone|name|x|y|z|seed|location|plantedAt|waters|missed`, joined by "~".
- `greenthumb_prefs`: alert toggles, sort, last zone filter.
- Also write `greenthumb-planters.tsv` in the Lua folder (ShroudLuaPath + io.open) for the website sync later
  (columns: id, zone, name, x, y, z, seed, location, plantedAt, waters, missed).

## Lessons from Lodestone (follow these)
- Probe Shroud.UI fields inside pcall (unknown fields raise errors).
- Build UI rows a few per frame (Lodestone: 3 rows/frame) to avoid "elements are being created too fast".
- Never store custom fields on UI userdata; keep text in Lua locals/tables.
- No default keybind (Shroud.Keybind with a default key is rejected).
- Later (0.2) map pins: ShroudSetMapMarker / ShroudRemoveMapMarker for the current zone only (~50 max), retry on
  "rate"/"too_soon"; compass with ShroudSetBeacon / ShroudClearBeacon. Clean up in ShroudOnDisableScript.

## Files
`greenthumb.lua`, `manifest.json` (author Kronic, version 0.1.0), `README.md`, `RELEASE-NOTES.md`, `icon.png`.

## Test plan
In the DEV client: plant one Garlic (Quick, Outside), confirm windows at 0/8/16 h and harvest at 24 h (use a debug
`/gt speed 60` that scales hours to minutes for fast testing), log out/in mid-window, confirm catch-up + alerts.

## Later (not 0.1)
0.2 map pins + compass; website Farm page + email alerts (Resend, from alerts@mail.truechaos.com to
greenthumb@truechaos.com, via the Lodestone Sync program and a Cloudflare cron Worker); 0.3 reagent planner +
seed shopping list; 0.4 harvest log.
