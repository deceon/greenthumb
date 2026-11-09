# Greenthumb 0.2.2

Easier seed picking.

- The seed list is now a dropdown (like All beds), sorted by name. The search box above it narrows the dropdown.
- No more Quick / Medium / Slow: each seed shows its real time in the area you're planting, e.g. "Garlic – 12h, 16 crops, 8g" in a greenhouse, "Garlic – 24h ..." outside, "Mandrake – 24h, 32 crops, 16g" in a greenhouse. A synced timing for that seed and growth type is included. Switching area updates the times.
- After picking, the line reads "Garlic: ready in 12h, water every 4h". Change seed brings the dropdown back.
- Plantings are named by where they are: "Garlic – bed 3", "Garlic – beds 1-8", or "Garlic x4" where beds aren't numbered. No more running numbers (Garlic 1, Garlic 2). After Split each part reads "Garlic – bed N". Saved ids don't change. /gth water and /gth sync find a planting by that name (e.g. /gth sync garlic bed 3 > 41m).
- Area lines say "you're here" only for the area you're standing in (within about 15 m); the others show their distance.
- Only one panel is open at a time: opening Edit, New farm, the walk, Plant or Sync closes whichever was open. Making a new area from the plant panel goes back to planting in it.

# Greenthumb 0.2.1

Set up a whole farm in one walk.

- Optional: farm-layout.tsv in the add-on folder lists farms and their areas (farm, area, type, order). It comes with Kronic's Farm: GH1 to GH8, Center Field, Walkway Bed and Gazebo Bed.
- /gth setup reads it and adds any farm or area that doesn't exist yet. It never makes duplicates, and never deletes or changes what you have (it only fills in the layout order for areas that already exist).
- Walk the farm: a panel that goes one step at a time with progress (3 / 12). First the farm entrance (saves the farm's zone and spot), then a spot inside each area in layout order. Save here, Skip, Back and Finish.
- Each area can take an optional planter count during the walk ("How many planters here?"). Areas show "3 of 8 planters", and the plant dialog starts at the number of empty planters.
- Areas are listed in layout order in the plant dialog, and as a tie-break in the overview.
- Without farm-layout.tsv, /gth setup walks the nearest farm's areas as they are.
- Fixed slash commands: they're now registered the way the game expects (Shroud.Command{ name, help, run }, as Crafters Ledger does). Before, the game rejected them silently, so /greenthumb setup ended up as a message to a character called "setup". If registration fails, chat now says so.
- New farms need no file or setup: after Create farm, an Add areas panel opens. Walk into each area, name it, pick its type (and planter count if you like) and press Save area here; Done when finished. + Area on a farm opens the same panel later.
- Edit > Walk this farm steps through a farm's entrance and areas to re-save their spots.
- Reorder areas: the Areas: soonest first / my order button switches the overview; in my order each area has ^ and v to move it. The plant dialog and the walk follow the same order, and new areas are added at the end.
- Planting beds: everything now says bed / planting bed. Bed types: Large, Medium and Small Planting Bed, Planting Barrel, Planting Pot, plus your own (+ Add type). An area's beds are set up once (Edit, or during the walk): how many, numbered or just a count, and a type for all beds or for each bed.
- New plant dialog: the area is picked for you and shown on one line (Change to pick another). Click a seed and the list closes; then Plant all empty beds (one line for the area), pick bed numbers (taken beds show their seed, the panel stays open for the next seed), or give a count. No Name box. Plantings remember their bed numbers, and Split names each part after its bed. Saved plantings gain a beds field, areas their bed setup, and greenthumb-planters.tsv a beds column.
- Fixed: "~" showed as a box in the game font; seed lines and counts now use plain characters ("Garlic x8").
- Plantings: planting one seed in several planters makes one line ("Garlic 1 ×8") that you water and harvest as one. Split breaks it into single planters that keep their timing. Area lines show what's growing ("Garlic ×4, Carrot ×3, 1 empty"), the plant dialog starts at the area's empty planters, and counts everywhere are real planters. Saved planters gain a count field (1 for older ones) and greenthumb-planters.tsv a count column.
- New look: a header with the app icon, summary tiles (Water now, Ready, Missed, Planters), farms as rounded cards with a barn icon and their name underlined, areas with a greenhouse / sun / house icon for their type, and planters with a status icon (water drop, clock, sprout, ready check) and a growth bar that fills as the crop grows (blue when it needs water, gold when ready). Dialogs are shaded panels with icon headings and green main buttons, and the on-screen alert has a bell icon. Icons come from icons.png; if the game can't show a picture or style, that bit is simply left out.
- Chat lines are coloured (green for done/ready, gold for needs you, red for warnings and missed waterings), with commands in gold.
- The short command is now /gth (for example /gth setup, /gth speed 60). /gt belongs to the game (it expects a character name), so Greenthumb never received it. /greenthumb works for everything too.

# Greenthumb 0.2.0

Farms and areas.

- Everything is now grouped as Farm -> Area -> Planter. A farm has a name, its zone, a spot (saved with New farm where you stand) and notes. An area belongs to a farm and has a growth type: Outside (1x growth), Greenhouse (2x) or Inside (0.1x). Planters take their growth rate from their area, so the Outside / Greenhouse / Inside choice when planting is gone.
- Plant dialog: pick Farm, then Area, then the seed, then a count, and plant that many planters at once. New farm and New area buttons right in the dialog.
- Water all due on each area records a watering for every planter in it whose window is open.
- Area spots: a new area is placed where you're standing (when you're in its farm's zone), and Edit > Set area spot here moves it. Within about 15 m of an area's spot, Greenthumb picks that area for you when planting (Plant here, /gt plant) and watering (/gt water, /gt water all), and the top of the window says "You're in GH3 - Left" with Plant and Water all due buttons.
- The overview is grouped by farm and then area, with whatever needs you soonest at the top. Farms can be collapsed with - / +, and show their zone, distance, planter count and notes.
- Go to farm points the game's compass at the farm and pins it on the map while you're in its zone (like Lodestone). Stop, clearing the compass, or /gt go ends it.
- Edit farms (rename, notes, Move here, Delete when empty) and areas (rename, change type, Delete when empty).
- New commands: /gt farm <name>, /gt area <name> [type], /gt go [farm], /gt water all. /gt plant now takes a count: /gt plant garlic 8.
- Upgrading: planters from 0.1 move into a farm named after their zone, with one area per location type. Saved as greenthumb_farms, greenthumb_areas (with each area's spot) and greenthumb_planters (which gains an area id). greenthumb-planters.tsv gains farm and area columns.
- Sync corrections are kept per seed and growth type, as before.

# Greenthumb 0.1.2

Match the game's own timers.

- Sync from tooltip: each planter has a Sync button. Hover the planter in game, type its "Next watering in" time (41m, 2h 5m, 1d 3h or 2:05) and press Set. Greenthumb moves that planter's next watering window to open after exactly that time. Or type /gt sync 41m (the nearest planter in this zone) or /gt sync Garlic 1 > 2h 5m.
- The correction is remembered for that seed and location, so new plantings and replants of the same seed in the same place start with the game's timing. Test-speed planters (/gt speed) can be synced too, but their correction isn't saved for new plantings.
- Locations show their growth rate the way the planter tooltip does: Outside (Growth Rate x1.0), Greenhouse (Growth Rate x2.0), Inside (Growth Rate x0.1). /gt plant also accepts the rate, e.g. /gt plant garlic x2.0.
- A "window opens" alert now also comes for the first window when a synced planter's first window opens after planting.
- Plant icon on screen to show or hide the window, and an icon in the Add-Ons window.
- Fixed the window and the on-screen notice opening in the top-left corner when the game reported their position as 0, 0.
- Saved planters gain an offset field (also a new last column in greenthumb-planters.tsv). Planters saved by 0.1.0 load with no offset.

# Greenthumb 0.1.0

First test build: track your planters by hand and never miss a watering window.

- Plant dialog: search the 27 built-in seeds, choose Outside, Greenhouse or Inside, and add a name if you like. Greenthumb saves the zone, position, seed and planting time.
- Timers: each planter shows "Water in ...", "Water now (closes in ...)", "Harvest in ..." or "Ready to harvest", plus "Missed a watering" when a window closed without water. Planting counts as the first of four waterings.
- Watered records the watering for the current window. Harvested offers Replant (same seed) or Clear.
- Alerts in chat and as an on-screen notice when a window opens, 1 h before it closes, and when a crop is ready. Each kind can be turned off, and each alert comes once per planter per window.
- Overview: a scrolling list sorted soonest first (or by zone or name), with a zone filter.
- Catch-up on login: timers run on real time, so you see anything due or overdue and any windows missed while you were away.
- Commands: /greenthumb, /gt plant, /gt water, /gt list, /gt due, and /gt speed for testing.
- Writes greenthumb-planters.tsv in the Lua folder for a future website sync.

Seed data and growth rules: SotA Lore Farming Planner (sotalore.com/farming).
