# Greenthumb

Crop tracker for Shroud of the Avatar, by Kronic. Version 0.2.2 (test build).

Never miss a watering window. Set up your farms once, tell Greenthumb what
you planted, and press **Watered** when you water. Greenthumb does the timing
math, shows a countdown on every bed, and tells you in chat and on screen
when it's time to water or harvest.

## Farms, areas and beds

Greenthumb groups everything as **Farm → Area → Bed**.

- A **farm** is a place: a name, its zone, the spot you stood on when you
  made it, and notes ("lot 4, row house; key in the chest").
- An **area** is a group of beds in a farm with one growth type:
  **Outside (1x growth)**, **Greenhouse (2x growth)** or **Inside (0.1x
  growth)**. Every bed in it grows at that rate.
- A **planting bed** (bed for short) is what you plant in: a **Large**,
  **Medium** or **Small Planting Bed**, a **Planting Barrel**, a **Planting
  Pot**, or a type you add yourself.

To get started (no files or setup needed):
1. Stand at your farm's entrance, press **New farm**, give it a name and
   notes, and press **Create farm**.
2. The **Add areas** panel opens. Walk into a greenhouse (or field, or
   house), type its name ("GH3 - Left", "Back field"), pick its type, how
   many planting beds it has and their bed type. Press **Save area here**.
   Its spot is where you're standing. Walk to the next one and do the same.
   Press **Done** when you've added them all.
3. Press **Plant here**. Standing in an area picks it for you (**Change**
   picks another). Pick a seed from the dropdown (type in the search box to
   narrow it). Each line shows how long it takes in that area, for example
   "Garlic – 12h, 16 crops, 8g" in a greenhouse. Then the line reads
   "Garlic: ready in 12h, water every 4h" and you choose where:
   - **Plant all empty beds**: one line for the whole area, like
     "Garlic – beds 1-8", watered and harvested together.
   - **Pick beds**: click the bed numbers you want (planted beds are shown
     with their seed), then **Plant selected beds**. The panel stays open so
     you can pick the next seed for other beds.
   - Areas set to **Just count** ask "How many beds?" instead of numbers.

**Split** on a planting of several beds breaks it into single beds (named
after their bed number), each with its own buttons.

## Setting up beds

**Edit** on an area sets its beds once, so you don't have to pick them each
time you plant:
- **Planting beds**: how many it has.
- **Numbered beds** (pick beds by number when planting) or **Just count**.
- **All beds**: a dropdown with the bed type for every bed.
- **Each bed**: click a bed to change just its type, for a mixed greenhouse.
- **+ Add type**: a new bed type of your own. It appears in every dropdown.

The walk panels (Add areas, Walk this farm) also ask for the bed count and
type, so new areas are set up as you walk them.

Later, **+ Area** on a farm opens the same Add areas panel. **Edit** >
**Walk this farm** steps through its entrance and areas again to re-save
their spots, and **Edit** on an area changes just that one.

When you're within about 15 m of an area's spot, the top of the window says
**You're in GH3 - Left**, with its farm, type and how many beds are due,
plus **Plant** and **Water all due** buttons for that area.

## Optional: a farm layout file (/gth setup)

You don't need this for new farms. It's a shortcut if you'd rather type a
farm's areas into a file than name them in game. List them in
`farm-layout.tsv` in the add-on folder (tab-separated: farm, area, type,
order) and walk the farm once:

```
farm	area	type	order
Kronic's Farm	GH1 – Front Left	Greenhouse	1
Kronic's Farm	Center Field	Outside	9
```

1. Go to your farm and type `/gth setup`. Greenthumb adds any farm or area
   from the file that doesn't exist yet. It never makes duplicates, and it
   never deletes or changes what you already have.
2. The **Walk the farm** panel shows one step at a time, with progress
   (3 / 12). First: stand at the farm entrance and press **Save here**.
3. Then for each area in order: stand inside it, type **How many beds
   here?** if you like, and press **Save here**.
4. **Skip** leaves a step as it is, **Back** goes to the previous one, and
   **Finish** closes the panel.

After that, standing in an area picks it for planting and watering. With a
bed count, the plant dialog starts at the number of empty beds
there, and the area shows "3 of 8 beds".

Renaming a farm or area in the file and running `/gth setup` again adds a new
one with that name. To rename, use **Edit** in the window instead. Without
the file, `/gth setup` walks the nearest farm's areas as they are.

## How the timing works

- Each seed is Quick (24 h), Medium (48 h) or Slow (72 h) at 1x growth.
  A Greenhouse (2x) takes half that; Inside (0.1x) takes ten times as long.
- A full harvest takes four waterings. Planting counts as the first. The
  growing time is then split into three windows, and each one needs one
  watering. For Garlic outside the windows are 0-8 h, 8-16 h and 16-24 h,
  and it's ready at 24 h.
- A window that closes without water counts as **missed**.
- If the game's timer doesn't match, use **Sync** (below). Greenthumb
  shifts that bed's schedule to match the game, and remembers the
  correction for that seed and growth type.
- Timers use real time, so they keep running while you're logged out. When
  you log in, Greenthumb lists anything due or overdue and any windows you
  missed while you were away.

## The window

- **New farm** and **Plant here** at the top, under the Greenthumb title.
- Four tiles show at a glance how many beds need **water now**, are
  **ready**, have **missed** a watering, and how many **beds** you have.
- Each bed has a status icon (water drop = water now, clock = waiting,
  sprout = growing, check = ready) and a growth bar that fills up as it grows.
- The list is grouped by farm, then area, with whatever needs you soonest
  at the top. Click **-** / **+** to hide or show a farm.
- Each **farm** shows its zone, how far away it is (when you're in that
  zone), how many beds it has and how many need you. Its notes show
  underneath.
  - **Go to farm**: the game's compass points at it and a pin shows on the
    map while you're in its zone. In another zone it tells you where to
    travel. **Stop** (or clearing the compass) ends it.
  - **+ Area** adds an area; **Edit** renames it, changes notes, **Move
    here** (saves where you're standing as its spot) or **Delete** (only when
    nothing is planted in it).
- Each **area** shows its growth type, bed count, and how far away it is
  (or "no spot set").
  - **Water all due**: records a watering for every bed in it whose
    window is open.
  - **Plant** opens the plant dialog for that area; **Edit** renames it,
    changes its type, sets its spot (**Set area spot here**, while standing
    inside it), or deletes it (when empty).
- Each area line shows what's growing in it: "Greenhouse (2x growth):
  Garlic x4, Carrot x3, 1 empty".
- Each **planting** (one seed in one or more beds, like "Garlic – beds 1-8")
  shows what to do next: "Water in 2h 10m",
  "Water now (closes in 3h)", "Harvest in 5h" or "Ready to harvest", plus
  "Missed a watering" if one was missed.
  - **Watered** records the watering for the current window (for all its
    beds).
  - **Harvested** then offers **Replant** (same seed, starts over) or
    **Clear**.
  - **Split** (on x2 or more) breaks it into single beds that keep their
    timing, so you can water, harvest or replant each one separately.
  - **Sync** (sync from tooltip): hover the bed in game, type the time it
    shows after "Next watering in" (`41m`, `2h 5m`, `1d 3h` or `2:05`) and
    press **Set**. New plantings of that seed in areas of the same type start
    with the corrected timing (not for `/gth speed` test beds).
- **< >** and **This zone** show farms in one zone or all of them.
- **Areas: soonest first / my order** switches how areas are listed inside
  each farm. In **my order**, each area has **^** and **v** to move it up or
  down. That order is also used by the plant dialog and Walk this farm, and
  new areas go to the end.
- **Alerts**: turn each kind on or off: a window opens, 1 h left in a window,
  and ready to harvest. Each alert comes once per bed per window, as a
  chat line and an on-screen notice (click the notice to open Greenthumb;
  drag it where you like).

## Commands

- `/greenthumb`: show or hide the window
- `/gth setup`: add what's missing from `farm-layout.tsv`, then Walk the farm
- `/gth farm <name>`: make a farm where you're standing (`/gth farm` alone
  opens the New farm box)
- `/gth area <name> [outside|greenhouse|inside]`: add an area to the nearest
  farm in this zone. `2x`, `1x` and `0.1x` work as the type too.
- `/gth plant <seed> [count] [> name]`: plant into the area you're standing
  in (or the one picked last in the plant dialog), e.g. `/gth plant garlic 8`.
  Part of the seed name is enough. `/gth plant` alone opens the plant dialog.
- `/gth water [name]`: water a bed that needs it: in the area you're
  standing in first, otherwise the nearest in this zone, or the one with that
  name
- `/gth water all`: Water all due in the area you're standing in
- `/gth sync [name >] <time>`: sync from tooltip without the window, e.g.
  `/gth sync 41m` (the nearest bed in this zone) or
  `/gth sync garlic bed 3 > 2h 5m`
- `/gth go <farm>`: Go to farm. `/gth go` alone stops.
- `/gth list`: every bed and its status, to chat
- `/gth due`: only the beds that need you now
- `/gth speed <n>`: for testing. Beds you plant from now on grow n times
  faster (`/gth speed 60` turns hours into minutes). Existing beds keep
  their speed. `/gth speed 1` turns it off.

## Show / hide

- Click the **plant icon** on screen (drag it where you like).
- Set a key for it in the game's **Add-Ons** window (there's no default key).
- Type **/greenthumb**.

## Notes

- Farms, areas and beds are saved per character.
- Upgrading from 0.1: your beds move into a farm named after their
  zone, with one area per type (Outside, Greenhouse, Inside). Rename them
  with **Edit**, use **Move here** to set the farm's spot, and **Set area
  spot here** inside each area.
- Greenthumb also writes `greenthumb-planters.tsv` in your Lua folder (with
  farm and area columns) for a future website sync. The game itself never
  goes online.
- Greenthumb only knows what you tell it. The game doesn't let add-ons read
  beds, so press the buttons when you plant, water and harvest.

## Credits

Seed list, yields, prices and growth rules come from the
[SotA Lore Farming Planner](https://www.sotalore.com/farming). Thank you to
SotA Lore for collecting them.
