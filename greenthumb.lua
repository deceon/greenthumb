--[[
  Greenthumb - crop tracker for Shroud of the Avatar
  by Kronic                                          Version 0.2.2 (test build)

  Track your farms and planters by hand and never miss a watering window.
  Farm -> Area -> Planter: a farm is a place (zone + spot), an area is a group
  of planters with one growth type (Outside 1x, Greenhouse 2x, Inside 0.1x).
  Press Planted / Watered / Harvested and Greenthumb does the timing:
  countdowns on every planter, and a chat line plus an on-screen notice when
  a window opens, an hour before it closes, and when the crop is ready.

  Open:     the plant icon, /greenthumb, or a key you set in Add-Ons
  Commands: /gth setup                        (farm-layout.tsv + Walk the farm)
            /gth farm <name>                  (new farm where you stand)
            /gth area <name> [outside|greenhouse|inside]  (new area in the nearest farm)
            /gth plant <seed> [count] [> name] (into the area picked in the plant dialog)
            /gth water [name|all]  (the area you're in first; all = Water all due there)
            /gth sync [name >] <time>  (the game tooltip's "Next watering in", e.g. 41m)
            /gth go [farm]     (compass + map pin to a farm; on its own: stop)
            /gth list          (every planter to chat)
            /gth due           (only the ones that need you now)
            /gth speed <n>     (debug: new plantings grow n times faster; 60 = hours become minutes)

  Seed data and growth rules: SotA Lore's Farming Planner (sotalore.com/farming).
  Files: greenthumb.lua, icons.png (icon sheet), icon.png, farm-layout.tsv, manifest.json, README.md, RELEASE-NOTES.md
]]

local VERSION = "0.2.2"

---------------------------------------------------------------- ui helper
-- Every element we make is remembered by its id (same pattern as Lodestone).
local made = {}
local UI = setmetatable({}, { __index = function(_, kind)
  return function(spec)
    local e = Shroud.UI[kind](spec)
    if spec.id and e then made[spec.id] = e end
    return e
  end
end })
-- Shroud.UI raises an error for a field it doesn't have, so ask inside pcall.
local function hasUI(kind)
  local ok, f = pcall(function() return Shroud.UI[kind] end)
  return ok and f ~= nil
end
local function showEl(e, on)
  if not e then return end
  if pcall(function() e:SetVisible(on) end) then return end
  pcall(function() if on then e:Show() else e:Hide() end end)
end
local function setText(e, t) if e then pcall(function() e:SetText(t) end) end end

-- DIM is a light warm grey so small text stays readable over the game world.
local GOLD, PARCH, DIM, GREEN, RED, BLUE = "#FFD24A", "#F2E8D0", "#CDBD9C", "#9EE07A", "#FF8A7A", "#8FD4F2"
-- Card look: dark see-through panels with a thin warm border and rounded corners.
local PANEL, PANEL_SOFT, EDGE, TRACK = "#120D09E6", "#2A1F16E0", "#6A5438", "#FFFFFF2A"
-- behind the whole window, so the world doesn't show through the text
local BODY = "#0B0806D9"
local PRIMARY = { backgroundColor = "#2E5A1EDD", color = "#FFFFFF" }
local BAR_W = 150 -- width of a planter's growth bar

-- Pictures: icons.png is a sheet of 14 icons (64 x 64 each, left to right); icon.png is the app icon.
local tex = { icons = -1, app = -1 }
local ICON_FRAMES = 14
local ICONS = { water = 1, clock = 2, sprout = 3, ready = 4, warn = 5, farm = 6, greenhouse = 7, outside = 8,
  inside = 9, pin = 10, plus = 11, edit = 12, sync = 13, bell = 14 }
local TYPE_ICON = { Outside = "outside", Greenhouse = "greenhouse", Inside = "inside" }
local canImage = nil

-- Make an element, or nil if the game doesn't accept it (so a fancy extra never breaks a window).
local function try(kind, spec)
  local ok, e = pcall(function() return UI[kind](spec) end)
  return ok and e or nil
end
-- Children lists that skip anything that came back nil.
local function pack(...)
  local out = {}
  for i = 1, select("#", ...) do
    local v = select(i, ...)
    if v then out[#out + 1] = v end
  end
  return out
end
-- The same for a table literal that may have holes (a nil in the middle would cut the list short).
local function compact(t)
  local keys, out = {}, {}
  for k in pairs(t) do if type(k) == "number" then keys[#keys + 1] = k end end
  table.sort(keys)
  for _, k in ipairs(keys) do out[#out + 1] = t[k] end
  return out
end
local function icon(name, size, tooltip)
  if tex.icons < 0 or not ICONS[name] then return nil end
  if canImage == nil then canImage = hasUI("Image") end
  if not canImage then return nil end
  local f = ICONS[name]
  size = size or 18
  return try("Image", { texture = tex.icons, uv = { (f - 1) / ICON_FRAMES, 0, 1 / ICON_FRAMES, 1 },
    width = size, height = size, tooltip = tooltip })
end
local function appImage(size)
  if tex.app < 0 then return nil end
  if canImage == nil then canImage = hasUI("Image") end
  if not canImage then return nil end
  return try("Image", { texture = tex.app, width = size, height = size })
end
-- An underline: a thin coloured bar under a heading.
local function rule(color, h, top, bottom)
  return try("Column", { style = { height = h or 2, backgroundColor = color or GOLD, marginTop = top or 2,
    marginBottom = bottom or 6, borderRadius = 1 }, children = {} })
end
local function sectionTitle(iconName, text, id, color)
  return UI.Row{ style = { alignItems = "center" }, children = pack(
    icon(iconName, 20),
    UI.Label{ id = id, text = text, style = { color = color or GOLD, fontSize = 16, fontStyle = "bold", marginLeft = 6, flexGrow = 1, whiteSpace = "wrap" } }) }
end

---------------------------------------------------------------- helpers
-- Chat lines are coloured with the game's [RRGGBB]text[-] tags (as Crafters Ledger does).
-- The game already starts each line with [Add-on: Greenthumb], so there's no prefix of our own.
local CHAT = { info = "9FD8F0", good = "8FD16A", alert = "FFD24A", warn = "FF7A6A", cmd = "FFD24A" }
local function chatKind(l)
  for _, w in ipairs({ "couldn't", "can't", "problem", "miss", "isn't", "not ready", "no bed", "no seed",
    "no farm", "you're not in", "usage:", "still has" }) do
    if string.find(l, w, 1, true) then return "warn" end
  end
  for _, w in ipairs({ "water now", "is open", "water in the next", "need you", "needs you" }) do
    if string.find(l, w, 1, true) then return "alert" end
  end
  for _, w in ipairs({ "ready", "planted", "replanted", "watered", "saved", "synced", "added", "new farm",
    "new area", "you reached", "walk finished", "guiding you" }) do
    if string.find(l, w, 1, true) then return "good" end
  end
  return "info"
end
-- Command names (/greenthumb, /gth ...) stand out in gold inside any line.
local function hiCommands(m)
  return (m:gsub("(/gth?%a*)", "[" .. CHAT.cmd .. "]%1[-]"):gsub("(/greenthumb)", "[" .. CHAT.cmd .. "]%1[-]"))
end
local function say(m, kind)
  m = tostring(m)
  kind = kind or chatKind(string.lower(m))
  if type(ShroudConsoleLog) == "function" then
    ShroudConsoleLog("[" .. (CHAT[kind] or CHAT.info) .. "]" .. hiCommands(m) .. "[-]")
  end
end
-- Frame clock, only for UI throttling.
local function now() return tonumber(ShroudTime) or 0 end
-- Real time (seconds since 1970), so timers keep running while you're logged out.
local realClock = true
local function clock()
  if type(os) == "table" and type(os.time) == "function" then
    local ok, v = pcall(os.time)
    if ok and type(v) == "number" then return v end
  end
  realClock = false
  return math.floor(now())
end

-- Saved per character.
local SCOPE = "character"
local function setVar(k, v)
  if type(ShroudSetSavedVar) == "function" then pcall(ShroudSetSavedVar, k, v, SCOPE) end
end
local function getVar(k)
  if type(ShroudGetSavedVar) ~= "function" then return nil end
  local ok, v = pcall(ShroudGetSavedVar, k, SCOPE)
  if ok and type(v) == "string" then return v end
  return nil
end

local function sceneName()
  for _, fn in ipairs({ "ShroudGetCurrentSceneName", "ShroudGetSceneName", "ShroudGetCurrentScene" }) do
    local f = _G[fn]
    if type(f) == "function" then
      local ok, v = pcall(f)
      if ok and type(v) == "string" and v ~= "" then return v end
    end
  end
  for _, var in ipairs({ "ShroudCurrentSceneName", "ShroudSceneName" }) do
    local v = _G[var]
    if type(v) == "string" and v ~= "" then return v end
  end
  return "Unknown zone"
end

-- X, height, Y (the order /loctrack shows).
local function position()
  local x, y, z = tonumber(ShroudPlayerX), tonumber(ShroudPlayerY), tonumber(ShroudPlayerZ)
  if not (x and y and z) then return nil end
  return x, y, z
end

local function key(s) return (string.lower(s or ""):gsub("[^%w]", "")) end
local function clean(s) return ((s or ""):gsub("[|~\t\r\n]", " "):gsub("^%s+", ""):gsub("%s+$", "")) end
local function fmt(n) return string.format("%.1f", n) end
local function b(v) return v and "1" or "0" end
local function plural(n, word) return n .. " " .. word .. (n == 1 and "" or "s") end

-- 2h 10m, 45m, 30s, 3d 4h
local function dur(s)
  s = math.max(0, math.floor(s + 0.5))
  if s < 60 then return s .. "s" end
  local m = math.floor(s / 60)
  if m < 60 then return m .. "m" end
  local h = math.floor(m / 60); m = m % 60
  if h < 24 then return m > 0 and (h .. "h " .. m .. "m") or (h .. "h") end
  local d = math.floor(h / 24); h = h % 24
  return h > 0 and (d .. "d " .. h .. "h") or (d .. "d")
end
-- +41m / -2h 5m
local function sdur(s) return (s < 0 and "-" or "+") .. dur(math.abs(s)) end

-- Compass direction to a spot (same correction as Lodestone: scenes are rotated differently).
local function atan2(y, x)
  if math.atan2 then return math.atan2(y, x) end
  return math.atan(y, x)
end
local DIRS = { "N", "NE", "E", "SE", "S", "SW", "W", "NW" }
local function heading(dx, dz)
  local plain = math.deg(atan2(dx, dz))
  local okH, h = pcall(function() return ShroudGetPlayerCompassHeading() end)
  local okY, yaw = pcall(function() return ShroudGetPlayerOrientation() end)
  local deg
  if okH and okY and type(h) == "number" and type(yaw) == "number" then
    deg = plain + (h - yaw)
  else
    local okS, off = pcall(function() return ShroudGetCurrentSceneOrientation() end)
    deg = plain + ((okS and type(off) == "number") and off or 0) + 90
  end
  deg = deg % 360
  return DIRS[math.floor((deg + 22.5) / 45) % 8 + 1]
end
-- "120 m NE" / "here", or nil when you're not in that zone
local function distanceText(zoneName, x, z)
  if key(zoneName) ~= key(sceneName()) then return nil end
  local px, _, pz = position()
  if not px then return nil end
  local dx, dz = x - px, z - pz
  local d = math.sqrt(dx * dx + dz * dz)
  if d < 5 then return "here" end
  return string.format("%d m %s", math.floor(d + 0.5), heading(dx, dz))
end

---------------------------------------------------------------- seeds and rules
-- From SotA Lore's Farming Planner: name, speed, average yield, price (gold).
local SEEDS = {}
local function seeds(speed, list)
  for _, s in ipairs(list) do SEEDS[#SEEDS + 1] = { name = s[1], speed = speed, yield = s[2], price = s[3] } end
end
seeds("Quick", {
  { "Garlic Plant Seed", 16, 8 }, { "Pumpkin Plant Seed", 4, 6 }, { "Carrot Plant Seed", 8, 8 },
  { "Lettuce Plant Seed", 8, 8 }, { "Pepper Plant Seed", 8, 8 }, { "Potato Plant Seed", 8, 8 },
  { "Tomato Plant Seed", 8, 8 }, { "Blue Rose Bush Seed", 7, 10 }, { "Orange Rose Bush Seed", 7, 10 },
  { "Pink Rose Bush Seed", 7, 10 }, { "Red Rose Bush Seed", 7, 10 }, { "Yellow Rose Bush Seed", 7, 10 },
})
seeds("Medium", {
  { "Mandrake Plant Seed", 32, 16 }, { "Nightshade Plant Seed", 32, 16 }, { "Banana Tree Seed", 16, 16 },
  { "Barley Plant Seed", 16, 16 }, { "Corn Plant Seed", 16, 16 }, { "Cotton Bush Seed", 9, 16 },
  { "Hops Plant Seed", 16, 16 }, { "Lemon Tree Seed", 16, 16 }, { "Onion Plant Seed", 16, 16 },
  { "Red Grape Plant Seed", 16, 16 }, { "Wheat Plant Seed", 16, 16 }, { "White Grape Plant Seed", 16, 16 },
})
seeds("Slow", {
  { "Coconut Plant Seed", 18, 30 }, { "Small Apple Tree Seed", 28, 30 }, { "Tea Leave Seed", 18, 30 },
})
local SEED_BY_KEY = {}
for _, s in ipairs(SEEDS) do SEED_BY_KEY[key(s.name)] = s end

local BASE_HOURS = { Quick = 24, Medium = 48, Slow = 72 }
-- Area types. Growth as the planter tooltip shows it: Greenhouse grows twice as fast, Inside a tenth as fast.
local LOCATIONS = { "Outside", "Greenhouse", "Inside" }
local MULT = { Outside = 1, Greenhouse = 0.5, Inside = 10 }
local GROWTH = { Outside = "1x", Greenhouse = "2x", Inside = "0.1x" }
local RATE_TO_LOC = { [1] = "Outside", [2] = "Greenhouse", [0.1] = "Inside" }
local function locLabel(l) return l .. " (" .. (GROWTH[l] or "1x") .. " growth)" end

local function shortName(seedName)
  local n = (seedName or ""):gsub(" Plant Seed$", ""):gsub(" Tree Seed$", " Tree"):gsub(" Bush Seed$", ""):gsub(" Seed$", "")
  return n
end
local function seedInfo(name)
  return SEED_BY_KEY[key(name)] or { name = name, speed = "Quick", yield = 0, price = 0, unknown = true }
end
local function locationName(s)
  local k = key(s)
  for _, l in ipairs(LOCATIONS) do if key(l) == k then return l end end
  if k == "gh" or k == "green" then return "Greenhouse" end
  if k == "in" or k == "indoors" or k == "house" then return "Inside" end
  if k == "out" or k == "outdoors" then return "Outside" end
  -- the growth rate: 2x, x2.0, 0.1 ...
  local r = tonumber(string.match(string.lower(s or ""), "^%s*x?(%d*%.?%d+)x?%s*$") or "")
  if r then
    for rate, l in pairs(RATE_TO_LOC) do if math.abs(r - rate) < 0.001 then return l end end
  end
  return nil
end

-- A planter made with /gth speed N keeps that speed for good: its id ends in xN.
local function speedOf(p) return tonumber(string.match(p.id or "", "x(%d+)$")) or 1 end
local function growFor(seedName, loc, speed)
  return BASE_HOURS[seedInfo(seedName).speed] * 3600 * (MULT[loc] or 1) / (speed or 1)
end
-- p.location always mirrors its area's type (see reindex).
local function growSecs(p) return growFor(p.seed, p.location, speedOf(p)) end
local function hourOf(p) return 3600 / speedOf(p) end

-- Planting is water 1. Window k (1..3) runs from off + (k-1)*T/3 to off + k*T/3; harvest at off + T.
-- off is the planter's sync offset (seconds, 0 = standard timing; set by "Sync from tooltip").
-- "Handled" windows = waters after planting + missed ones, always counted in order.
local function handled(p) return (p.waters - 1) + p.missed end
-- Time into the planter's (shifted) schedule. Negative = window 1 hasn't opened yet.
local function sched(p, t) return t - p.plantedAt - (p.off or 0) end

-- Count windows that closed without water. Returns true if anything changed.
local function applyMissed(p, t)
  local w = growSecs(p) / 3
  local closed = math.max(0, math.min(3, math.floor(sched(p, t) / w)))
  local h = handled(p)
  if h < closed then p.missed = p.missed + (closed - h); return true end
  return false
end

-- kind: "water" (window k open, not watered), "wait" (next window opens in left),
--       "grow" (all watered; harvest in left), "ready"
local function state(p, t)
  local T = growSecs(p)
  local w = T / 3
  local e = sched(p, t)
  if e >= T then return { kind = "ready", left = 0 } end
  local k = (e < 0) and 0 or math.min(3, math.floor(e / w) + 1)
  local h = handled(p)
  if k >= 1 and h < k then return { kind = "water", k = k, left = k * w - e } end
  if h < 3 then return { kind = "wait", k = k, left = h * w - e } end  -- window h+1 opens
  return { kind = "grow", k = k, left = T - e }
end

local function statusText(p, st)
  if st.kind == "ready" then return "Ready to harvest", GREEN end
  if st.kind == "water" then
    return "Water now (closes in " .. dur(st.left) .. ")", (st.left <= hourOf(p)) and RED or GOLD
  end
  if st.kind == "wait" then return "Water in " .. dur(st.left), PARCH end
  return "Harvest in " .. dur(st.left), PARCH
end
local function missedText(p)
  if p.missed <= 0 then return "" end
  if p.missed == 1 then return "Missed a watering" end
  return "Missed " .. p.missed .. " waterings"
end
local function needsYou(st) return st.kind == "water" or st.kind == "ready" end

-- Soonest first: ready, then water now, then the rest by time left.
local RANK = { ready = 0, water = 1, wait = 2, grow = 2 }
local function sooner(sa, sc)
  if RANK[sa.kind] ~= RANK[sc.kind] then return RANK[sa.kind] < RANK[sc.kind] end
  return sa.left < sc.left
end

---------------------------------------------------------------- state
-- farm:    { id, name, zone, x, y, z, notes, collapsed }
-- area:    { id, farmId, name, type, x, y, z, count, order }
--          (x/y/z = its spot, nil until set; count = how many planters it holds, optional;
--           order = its place in farm-layout.tsv, optional)
-- planter: { id, areaId, zone, name, x, y, z, seed, location, plantedAt, waters, missed, off }
--          (zone and location are copied from its farm and area)
local farms, areas, planters = {}, {}, {}
local farmById, areaById = {}, {}
local prefs = { open = true, aOpen = true, aClose = true, aReady = true, sort = "soonest", zoneFilter = "",
  x = 80, y = 200, w = 460, h = 520, loc = "Outside", speed = 1, nx = 520, ny = 120, lx = 20, ly = 340,
  areaId = "", farmId = "" }
local alerted = {}   -- [id] = { open = k, close = k, ready = true }: alert once per planter per window
local lastKind = {}  -- [id] = state key, to notice when the list needs rebuilding
local zone, zoneKey = nil, nil
local win, list = nil, nil
-- Sync offsets learned from the game's tooltip, per seed + area type, in real
-- (speed x1) seconds: [key(seed) .. "|" .. type] = seconds. New plantings start with it.
local learned = {}
local function learnKey(seed, loc) return key(seed) .. "|" .. loc end
local tick, posTick, searchTick = 0, 0, 0
local catchUp, catchUpAt = nil, 0
local migratedNote = nil

local function idTaken(id)
  return farmById[id] or areaById[id] or (function()
    for _, p in ipairs(planters) do if p.id == id then return true end end
    return false
  end)()
end
local function newId(prefix, speed)
  local id
  repeat
    id = string.format("%s%x%04x", prefix, clock(), math.random(0, 65535))
    if speed and speed > 1 then id = id .. "x" .. math.floor(speed) end
  until not idTaken(id)
  return id
end

-- Keep the lookups and each planter's copied zone / type up to date.
local function reindex()
  farmById, areaById = {}, {}
  for _, f in ipairs(farms) do farmById[f.id] = f end
  for _, a in ipairs(areas) do areaById[a.id] = a end
  for _, p in ipairs(planters) do
    local a = areaById[p.areaId]
    if a then
      p.location = a.type
      local f = farmById[a.farmId]
      if f then p.zone = f.zone end
    end
  end
end
local function areaOf(p) return areaById[p.areaId] end
local function farmOf(p) local a = areaOf(p); return a and farmById[a.farmId] end
local function areasOf(f)
  local out = {}
  for _, a in ipairs(areas) do if a.farmId == f.id then out[#out + 1] = a end end
  return out
end
local function plantersOf(a)
  local out = {}
  for _, p in ipairs(planters) do if p.areaId == a.id then out[#out + 1] = p end end
  return out
end
local function farmPlanters(f)
  local out = {}
  for _, p in ipairs(planters) do local a = areaById[p.areaId]; if a and a.farmId == f.id then out[#out + 1] = p end end
  return out
end
-- Planting beds. The game's are below; you can add your own types (saved as greenthumb_bedtypes).
local DEFAULT_BEDS = { "Large Planting Bed", "Medium Planting Bed", "Small Planting Bed", "Planting Barrel", "Planting Pot" }
local customBeds = {}
local function bedTypes()
  local out, seen = {}, {}
  for _, list in ipairs({ DEFAULT_BEDS, customBeds }) do
    for _, t in ipairs(list) do
      if not seen[key(t)] then seen[key(t)] = true; out[#out + 1] = t end
    end
  end
  return out
end
-- "Large", "Barrel", or a custom name, for tight spots
local function bedShort(t)
  if not t or t == "" then return "" end
  local s = t:gsub(" Planting Bed$", ""):gsub("^Planting ", "")
  return s
end
-- Bed numbers: "1,2,4" <-> { 1, 2, 4 }
local function bedsToText(b)
  if not b or #b == 0 then return "" end
  local out = {}
  for i, n in ipairs(b) do out[i] = tostring(n) end
  return table.concat(out, ",")
end
local function bedsFromText(s)
  local out = {}
  for n in string.gmatch(s or "", "%d+") do out[#out + 1] = tonumber(n) end
  table.sort(out)
  return (#out > 0) and out or nil
end
-- "beds 1-3, 5" for display
local function bedsLabel(b)
  if not b or #b == 0 then return "" end
  local parts, i = {}, 1
  while i <= #b do
    local j = i
    while j < #b and b[j + 1] == b[j] + 1 do j = j + 1 end
    parts[#parts + 1] = (j > i) and (b[i] .. "-" .. b[j]) or tostring(b[i])
    i = j + 1
  end
  return ((#b == 1) and "bed " or "beds ") .. table.concat(parts, ", ")
end

-- A planting can cover several beds with the same seed, planted together ("Garlic – beds 1-8").
local function nOf(p) return p.n or 1 end
-- A planting is named by where it is, not a running number:
--   "Garlic – bed 3", "Garlic – beds 1-8", or "Garlic x4" where beds aren't numbered.
-- (A count-only planting that was split keeps its "#2" part number.)
local function label(p)
  local seed = shortName(p.seed)
  if p.beds and #p.beds > 0 then return seed .. " – " .. bedsLabel(p.beds) end
  local part = string.match(p.name or "", "#%d+$")
  if part then return seed .. " " .. part end
  return seed .. (nOf(p) > 1 and (" x" .. nOf(p)) or "")
end
local function countOf(ps)
  local n = 0
  for _, p in ipairs(ps) do n = n + nOf(p) end
  return n
end
-- What's growing in an area: "Garlic x4, Carrot x3, 1 empty".
local function contents(a, ps)
  local bySeed, order = {}, {}
  for _, p in ipairs(ps) do
    local s = shortName(p.seed)
    if not bySeed[s] then bySeed[s] = 0; order[#order + 1] = s end
    bySeed[s] = bySeed[s] + nOf(p)
  end
  local parts = {}
  for _, s in ipairs(order) do parts[#parts + 1] = s .. " x" .. bySeed[s] end
  local empty = a.count and (a.count - countOf(ps)) or nil
  if empty and empty > 0 then parts[#parts + 1] = empty .. " empty" end
  if #parts == 0 then return "empty" end
  return table.concat(parts, ", ")
end
-- Which bed numbers are planted in an area: [bed number] = planting.
local function takenBeds(ps)
  local t = {}
  for _, p in ipairs(ps or {}) do for _, n in ipairs(p.beds or {}) do t[n] = p end end
  return t
end
-- The free bed numbers in an area (needs its bed count). Beds planted without
-- numbers ("just count") use up free numbers from the end.
local function freeBeds(a, ps)
  if not a.count then return {} end
  local t = takenBeds(ps)
  local unnumbered = 0
  for _, p in ipairs(ps) do if not p.beds then unnumbered = unnumbered + nOf(p) end end
  local free = {}
  for n = 1, a.count do if not t[n] then free[#free + 1] = n end end
  for _ = 1, math.min(unnumbered, #free) do table.remove(free) end
  return free
end
-- A bed's type in an area ("" when not set).
local function bedTypeOf(a, n) return (a.bedTypes and a.bedTypes[n]) or "" end
-- Saved as "Large Planting Bed;Large Planting Bed;;Small Planting Bed" (one per bed, empty = not set).
local function bedTypesText(a)
  local n = math.max(a.count or 0, 0)
  if n == 0 or not a.bedTypes then return "" end
  local out = {}
  for i = 1, n do out[i] = bedTypeOf(a, i) end
  return table.concat(out, ";")
end
local function bedTypesFromText(s)
  local out, i = {}, 0
  for part in string.gmatch((s or "") .. ";", "([^;]*);") do i = i + 1; out[i] = part end
  return (s and s ~= "") and out or nil
end
-- The bed types a planting uses: "Large Planting Bed" or "Large, Small".
local function plantingBedTypes(p, a)
  if not (a and p.beds) then return "" end
  local seen, out = {}, {}
  for _, n in ipairs(p.beds) do
    local t = bedTypeOf(a, n)
    if t ~= "" and not seen[t] then seen[t] = true; out[#out + 1] = t end
  end
  if #out == 1 then return out[1] end
  for i, t in ipairs(out) do out[i] = bedShort(t) end
  return table.concat(out, ", ")
end
local function where(p)
  local a, f = areaOf(p), farmOf(p)
  return (f and f.name or p.zone) .. (a and (" > " .. a.name) or "")
end

---------------------------------------------------------------- save / load
local lastTsv = nil
local function luaFile(name)
  if type(ShroudLuaPath) ~= "string" or type(io) ~= "table" or type(io.open) ~= "function" then return nil end
  return ShroudLuaPath .. "/" .. name
end

-- One planter's saved fields. 0.1.2 added offset, 0.2.0 added areaId (an empty
-- areaId means an older planter that still has to be moved into a farm), 0.2.1
-- added count (how many planters this planting covers; 1 when missing).
local function record(p)
  return { p.id, clean(p.zone), clean(p.name), fmt(p.x), fmt(p.y), fmt(p.z), clean(p.seed), p.location,
    string.format("%d", math.floor(p.plantedAt)), p.waters, p.missed, string.format("%d", math.floor((p.off or 0) + 0.5)),
    p.areaId or "", nOf(p), bedsToText(p.beds) }
end

-- greenthumb-planters.tsv in the Lua folder, for the website sync later.
local function writeTsv()
  local path = luaFile("greenthumb-planters.tsv"); if not path then return end
  local out = { "id\tfarm\tarea\tzone\tname\tx\ty\tz\tseed\tlocation\tplantedAt\twaters\tmissed\toffset\tcount\tbeds" }
  for _, p in ipairs(planters) do
    local a, f = areaOf(p), farmOf(p)
    out[#out + 1] = table.concat({ p.id, clean(f and f.name or ""), clean(a and a.name or ""), clean(p.zone), clean(label(p)),
      fmt(p.x), fmt(p.y), fmt(p.z), clean(p.seed), p.location, string.format("%d", math.floor(p.plantedAt)),
      p.waters, p.missed, string.format("%d", math.floor((p.off or 0) + 0.5)), nOf(p), bedsToText(p.beds) }, "\t")
  end
  local text = table.concat(out, "\n") .. "\n"
  if text == lastTsv then return end
  local ok = pcall(function()
    local f = assert(io.open(path, "w")); f:write(text); f:close()
  end)
  if ok then lastTsv = text end
end

local function save()
  local parts = {}
  for _, f in ipairs(farms) do
    parts[#parts + 1] = table.concat({ f.id, clean(f.name), clean(f.zone), fmt(f.x), fmt(f.y), fmt(f.z), clean(f.notes), b(f.collapsed) }, "|")
  end
  setVar("greenthumb_farms", table.concat(parts, "~"))
  parts = {}
  for _, a in ipairs(areas) do
    parts[#parts + 1] = table.concat({ a.id, a.farmId, clean(a.name), a.type,
      a.x and fmt(a.x) or "", a.y and fmt(a.y) or "", a.z and fmt(a.z) or "",
      a.count and tostring(a.count) or "", a.order and tostring(a.order) or "",
      bedTypesText(a), (a.numbered == false) and "0" or "1" }, "|")
  end
  setVar("greenthumb_areas", table.concat(parts, "~"))
  parts = {}
  for _, p in ipairs(planters) do parts[#parts + 1] = table.concat(record(p), "|") end
  setVar("greenthumb_planters", table.concat(parts, "~"))
  local offs = {}
  for k, v in pairs(learned) do offs[#offs + 1] = k .. "|" .. string.format("%d", math.floor(v + 0.5)) end
  table.sort(offs)
  setVar("greenthumb_offsets", table.concat(offs, "~"))
  setVar("greenthumb_bedtypes", table.concat(customBeds, "~"))
  setVar("greenthumb_prefs", table.concat({ b(prefs.open), b(prefs.aOpen), b(prefs.aClose), b(prefs.aReady),
    prefs.sort, math.floor(prefs.x), math.floor(prefs.y), math.floor(prefs.w), math.floor(prefs.h),
    prefs.loc, prefs.speed, math.floor(prefs.nx), math.floor(prefs.ny), clean(prefs.zoneFilter),
    math.floor(prefs.lx), math.floor(prefs.ly), prefs.areaId or "", prefs.farmId or "" }, "|"))
  if type(ShroudFlushSavedVars) == "function" then pcall(ShroudFlushSavedVars) end
  pcall(writeTsv)
end

local function split(s)
  local f = {}
  for part in string.gmatch(s .. "|", "([^|]*)|") do f[#f + 1] = part end
  return f
end
local function records(name)
  local out = {}
  local raw = getVar(name)
  if raw and raw ~= "" then
    for rec in string.gmatch(raw, "[^~]+") do out[#out + 1] = split(rec) end
  end
  return out
end

-- Older planters (no area yet): a farm named after their zone, one area per location type.
local function migrate(list)
  local moved, newFarms = 0, 0
  for _, p in ipairs(list) do
    local f
    for _, x in ipairs(farms) do if key(x.zone) == key(p.zone) and key(x.name) == key(p.zone) then f = x end end
    if not f then
      f = { id = newId("f"), name = p.zone ~= "" and p.zone or "My farm", zone = p.zone, x = p.x, y = p.y, z = p.z,
        notes = "Made from your 0.1 beds", collapsed = false }
      farms[#farms + 1] = f; farmById[f.id] = f; newFarms = newFarms + 1
    end
    local a
    for _, x in ipairs(areas) do if x.farmId == f.id and x.type == p.location and key(x.name) == key(p.location) then a = x end end
    if not a then
      a = { id = newId("a"), farmId = f.id, name = p.location, type = p.location }
      areas[#areas + 1] = a; areaById[a.id] = a
    end
    p.areaId = a.id
    moved = moved + 1
  end
  if moved > 0 then
    migratedNote = "moved " .. plural(moved, "bed") .. " into farms by zone" ..
      (newFarms > 0 and (" (" .. plural(newFarms, "new farm") .. ", one area per growth type)") or "") ..
      ". Rename them with Edit."
  end
  return moved > 0
end

local function load()
  farms, areas, planters = {}, {}, {}
  for _, f in ipairs(records("greenthumb_farms")) do
    local x, y, z = tonumber(f[4]), tonumber(f[5]), tonumber(f[6])
    if f[1] and f[1] ~= "" and x and y and z then
      farms[#farms + 1] = { id = f[1], name = (f[2] ~= "" and f[2]) or "Farm", zone = f[3] or "", x = x, y = y, z = z,
        notes = f[7] or "", collapsed = f[8] == "1" }
    end
  end
  reindex()
  for _, f in ipairs(records("greenthumb_areas")) do
    -- an area whose farm is gone is dropped; its planters get moved again below
    if f[1] and f[1] ~= "" and farmById[f[2] or ""] then
      local x, y, z = tonumber(f[5] or ""), tonumber(f[6] or ""), tonumber(f[7] or "")
      local a = { id = f[1], farmId = f[2], name = (f[3] ~= "" and f[3]) or "Area", type = locationName(f[4]) or "Outside" }
      if x and y and z then a.x, a.y, a.z = x, y, z end
      a.count, a.order = tonumber(f[8] or ""), tonumber(f[9] or "")
      a.bedTypes, a.numbered = bedTypesFromText(f[10]), f[11] ~= "0"
      areas[#areas + 1] = a
    end
  end
  reindex()
  local loose = {}
  for _, f in ipairs(records("greenthumb_planters")) do
    local x, y, z, at = tonumber(f[4]), tonumber(f[5]), tonumber(f[6]), tonumber(f[9])
    if f[1] and f[1] ~= "" and x and y and z and at then
      local p = { id = f[1], zone = f[2] or "", name = f[3] or "", x = x, y = y, z = z,
        seed = f[7] or "", location = locationName(f[8]) or "Outside", plantedAt = at,
        waters = math.max(1, math.min(4, tonumber(f[10]) or 1)), missed = math.max(0, tonumber(f[11]) or 0),
        off = tonumber(f[12]) or 0, areaId = f[13] or "", n = math.max(1, math.floor(tonumber(f[14] or "") or 1)),
        beds = bedsFromText(f[15]) }
      planters[#planters + 1] = p
      if not areaById[p.areaId] then loose[#loose + 1] = p end
    end
  end
  local changed = migrate(loose)
  reindex()
  customBeds = {}
  local bt = getVar("greenthumb_bedtypes")
  if bt and bt ~= "" then for t in string.gmatch(bt, "[^~]+") do customBeds[#customBeds + 1] = t end end
  learned = {}
  for _, f in ipairs(records("greenthumb_offsets")) do
    local loc, secs = locationName(f[2]), tonumber(f[3])
    if f[1] and f[1] ~= "" and loc and secs then learned[f[1] .. "|" .. loc] = secs end
  end
  local p = getVar("greenthumb_prefs")
  if p and p ~= "" then
    local v = split(p)
    prefs.open = v[1] ~= "0"
    prefs.aOpen = v[2] ~= "0"
    prefs.aClose = v[3] ~= "0"
    prefs.aReady = v[4] ~= "0"
    prefs.sort = (v[5] == "order") and "order" or "soonest"
    local px, py = tonumber(v[6]), tonumber(v[7])
    if px and py and (px ~= 0 or py ~= 0) then prefs.x, prefs.y = px, py end
    prefs.w = tonumber(v[8]) or prefs.w
    prefs.h = tonumber(v[9]) or prefs.h
    prefs.loc = locationName(v[10]) or prefs.loc
    prefs.speed = math.max(1, math.floor(tonumber(v[11]) or 1))
    local nx, ny = tonumber(v[12]), tonumber(v[13])
    if nx and ny and (nx ~= 0 or ny ~= 0) then prefs.nx, prefs.ny = nx, ny end
    prefs.zoneFilter = v[14] or ""
    local lx, ly = tonumber(v[15]), tonumber(v[16])
    if lx and ly and (lx ~= 0 or ly ~= 0) then prefs.lx, prefs.ly = lx, ly end
    prefs.areaId = v[17] or ""
    prefs.farmId = v[18] or ""
  end
  if changed then save() end
end

---------------------------------------------------------------- on-screen notice
local notice, noticeBtn, noticeUntil = nil, nil, 0
local setShown, rebuild -- defined below

local function hideNotice() noticeUntil = 0; showEl(notice, false) end
local function showNotice(text)
  if not notice then return end
  setText(noticeBtn, text)
  showEl(notice, true)
  noticeUntil = now() + 10
end
local function buildNotice()
  if not hasUI("HudFrame") then return end
  local ok, f = pcall(UI.HudFrame, { id = "gt_notice", x = prefs.nx, y = prefs.ny, width = 470, height = 48, children = {
    UI.Row{ style = { alignItems = "center", width = 470, height = 48, paddingLeft = 8, backgroundColor = "#120D09E6",
      borderRadius = 10, borderWidth = 1, borderColor = GOLD }, children = pack(
      icon("bell", 26),
      UI.Button{ id = "gt_notice_btn", text = "", tooltip = "Open Greenthumb",
        style = { flexGrow = 1, height = 44, color = GOLD, fontSize = 16, fontStyle = "bold", backgroundColor = "#00000000" },
        onClick = function() hideNotice(); setShown(true); rebuild() end }) },
  } })
  if not (ok and f) then -- the plain version, if the game didn't take the styled one
    ok, f = pcall(UI.HudFrame, { id = "gt_notice", x = prefs.nx, y = prefs.ny, width = 440, height = 44, children = {
      UI.Button{ id = "gt_notice_btn", text = "", tooltip = "Open Greenthumb",
        style = { width = 440, height = 44, color = GOLD, fontSize = 16 },
        onClick = function() hideNotice(); setShown(true); rebuild() end },
    } })
  end
  if ok and f then notice, noticeBtn = f, made.gt_notice_btn; showEl(notice, false)
  else say("couldn't make the on-screen notice (alerts go to chat only): " .. tostring(f)) end
end

---------------------------------------------------------------- planters
local function removeFrom(t, x)
  for i, y in ipairs(t) do if y == x then table.remove(t, i); return true end end
  return false
end


-- The learned sync offset for a seed + area type, scaled to a planter's test speed.
local function offsetFor(seedName, loc, speed)
  return (learned[learnKey(seedName, loc)] or 0) / (speed or 1)
end

-- Mark what's already true as alerted, so a fresh or re-timed planter doesn't alert for the past.
local function primeAlerts(p, t)
  local st = state(p, t)
  alerted[p.id] = {
    open = (st.kind == "water") and st.k or nil,
    close = (st.kind == "water" and st.left <= hourOf(p)) and st.k or nil,
    ready = st.kind == "ready" }
  lastKind[p.id] = st.kind .. (st.k or 0) .. ":" .. p.missed
  return st
end

-- Plant one seed in count beds of an area, as one planting ("Garlic – beds 1-8"):
-- one line, watered and harvested together. Split breaks it into single beds.
-- beds: the bed numbers used (optional; then count = #beds).
local function plant(a, seed, count, name, beds)
  if beds and #beds > 0 then count = #beds end
  local f = a and farmById[a.farmId]
  if not f then say("pick a farm and an area first (New farm, then New area)"); return end
  local px, py, pz = position()
  if not px then say("can't read your position, nothing saved"); return end
  count = math.max(1, math.min(500, math.floor(tonumber(count) or 1)))
  name = clean(name)
  local t = clock()
  -- the saved name is just the seed; what you see comes from label() (seed + beds)
  local first = { id = newId("g", prefs.speed), areaId = a.id, zone = f.zone, name = (name ~= "" and name) or shortName(seed.name),
    x = px, y = py, z = pz, seed = seed.name, location = a.type, plantedAt = t, waters = 1, missed = 0, n = count,
    beds = (beds and #beds > 0) and beds or nil }
  first.off = offsetFor(seed.name, a.type, speedOf(first))
  planters[#planters + 1] = first
  local st = primeAlerts(first, t)
  prefs.areaId, prefs.farmId = a.id, f.id
  save()
  if key(f.zone) ~= key(sceneName()) then say("note: you're not in " .. f.zone .. "; the beds are saved under " .. f.name .. " anyway") end
  say("planted " .. label(first) .. " (" .. shortName(seed.name) .. (first.beds and (", " .. bedsLabel(first.beds)) or "") .. ")" ..
    " in " .. f.name .. " > " .. a.name .. ", " .. locLabel(a.type) .. ". That's water 1. " .. (statusText(first, st)) ..
    "; harvest in " .. dur(growSecs(first) - sched(first, t)) ..
    (first.off ~= 0 and (" (synced timing " .. sdur(first.off) .. ")") or "") ..
    (speedOf(first) > 1 and (" (test speed x" .. speedOf(first) .. ")") or "") .. ".")
  rebuild()
end

local function water(p)
  local t = clock()
  if applyMissed(p, t) then save() end
  local st = state(p, t)
  if st.kind == "water" then
    p.waters = math.min(4, p.waters + 1)
    save()
    local nx = state(p, t)
    local after = (nx.kind == "wait") and ("next window opens in " .. dur(nx.left)) or ("harvest in " .. dur(nx.left))
    say("watered " .. label(p) .. " (window " .. st.k .. " of 3); " .. after)
    rebuild()
  elseif st.kind == "ready" then say(label(p) .. " is ready to harvest; no water needed")
  elseif st.kind == "wait" then say(label(p) .. " is watered for now; the next window opens in " .. dur(st.left))
  else say(label(p) .. " has all its water; harvest in " .. dur(st.left)) end
end

-- Water every planter in the area whose window is open.
local function waterAllDue(a)
  local t = clock()
  local n = 0
  for _, p in ipairs(plantersOf(a)) do
    applyMissed(p, t)
    if state(p, t).kind == "water" then p.waters = math.min(4, p.waters + 1); n = n + nOf(p) end
  end
  if n == 0 then say("nothing in " .. a.name .. " needs water right now"); return end
  save()
  say("watered " .. plural(n, "bed") .. " in " .. a.name)
  rebuild()
end

local function replant(p)
  local t = clock()
  p.plantedAt, p.waters, p.missed = t, 1, 0
  p.off = offsetFor(p.seed, p.location, speedOf(p))
  primeAlerts(p, t)
  save()
  say("replanted " .. label(p) .. " (" .. shortName(p.seed) .. "); harvest in " .. dur(growSecs(p) - sched(p, t)))
  rebuild()
end

-- "41m", "2h 5m", "1d 3h", "2:05", "Next watering in 41m". A bare number is minutes.
local function parseDuration(s)
  s = string.lower(s or "")
  local hh, mm = string.match(s, "(%d+):(%d%d)")
  if hh then return tonumber(hh) * 3600 + tonumber(mm) * 60 end
  local total, any = 0, false
  for num, unit in string.gmatch(s, "(%d+%.?%d*)%s*(%a*)") do
    local n, u = tonumber(num), string.sub(unit, 1, 1)
    if n then
      total = total + n * ((u == "d" and 86400) or (u == "h" and 3600) or (u == "s" and 1) or 60)
      any = true
    end
  end
  return any and total or nil
end

-- Sync from tooltip: the game says "Next watering in <secs>". Move this planter's
-- schedule so its next window opens then, and remember the shift for this seed + area type.
local function syncPlanter(p, secs)
  local t = clock()
  applyMissed(p, t)
  local n = handled(p) + 1
  if n > 3 then say(label(p) .. " has had all its waterings, so there's no next watering to sync"); return end
  local w = growSecs(p) / 3
  p.off = t + secs - p.plantedAt - (n - 1) * w
  primeAlerts(p, t)
  local note
  if speedOf(p) == 1 then
    learned[learnKey(p.seed, p.location)] = p.off
    note = "Saved for new " .. shortName(p.seed) .. " plantings in " .. locLabel(p.location) .. " areas."
  else
    note = "This is a test-speed bed, so the timing isn't saved for new plantings."
  end
  save()
  say("synced " .. label(p) .. ": watering window " .. n .. " of 3 opens in " .. dur(secs) ..
    " (" .. sdur(p.off) .. " from the standard timing). " .. note)
  rebuild()
end

-- Split "Garlic – beds 1-8" into 8 single beds that keep its timing. Each part
-- shows as "Garlic – bed N"; without bed numbers they're "Garlic #1", "Garlic #2" ...
local function splitPlanting(p)
  local n = nOf(p)
  if n <= 1 then return end
  local was, beds = label(p), p.beds
  local base = shortName(p.seed)
  local function nameFor(i) return beds and base or (base .. " #" .. i) end
  p.n, p.name = 1, nameFor(1)
  if beds then p.beds = { beds[1] } end
  for i = 2, n do
    local q = {}
    for k, v in pairs(p) do q[k] = v end
    q.id, q.name, q._st = newId("g", speedOf(p)), nameFor(i), nil
    if beds then q.beds = { beds[i] } end
    planters[#planters + 1] = q
    local a = alerted[p.id]
    if a then alerted[q.id] = { open = a.open, close = a.close, ready = a.ready } end
    lastKind[q.id] = lastKind[p.id]
  end
  save()
  say("split " .. was .. " into " .. n .. " single beds; water and harvest each one on its own")
  rebuild()
end

local function clearPlanter(p)
  removeFrom(planters, p)
  alerted[p.id], lastKind[p.id] = nil, nil
  save(); say("cleared " .. label(p)); rebuild()
end

---------------------------------------------------------------- farms and areas
local stopGuide -- defined below (Go to farm)

local function nearestFarm()
  local px, _, pz = position()
  local best, bestD
  for _, f in ipairs(farms) do
    if key(f.zone) == zoneKey then
      local d = px and ((f.x - px) ^ 2 + (f.z - pz) ^ 2) or 0
      if not bestD or d < bestD then best, bestD = f, d end
    end
  end
  return best
end

-- The area you're standing in: the nearest area spot in this zone within AREA_RANGE metres.
local AREA_RANGE = 15
local function nearestArea()
  local px, py, pz = position()
  if not px then return nil end
  local best, bestD
  for _, a in ipairs(areas) do
    local f = farmById[a.farmId]
    if a.x and f and key(f.zone) == zoneKey then
      local dx, dy, dz = a.x - px, a.y - py, a.z - pz
      local d = math.sqrt(dx * dx + dy * dy + dz * dz)
      if d <= AREA_RANGE and (not bestD or d < bestD) then best, bestD = a, d end
    end
  end
  return best
end

local function setAreaSpot(a, quiet)
  local f = farmById[a.farmId]
  local px, py, pz = position()
  if not px then say("can't read your position"); return false end
  if f and key(f.zone) ~= zoneKey then
    say(a.name .. " belongs to " .. f.name .. " in " .. f.zone .. "; go there to set its spot"); return false
  end
  a.x, a.y, a.z = px, py, pz
  save()
  if not quiet then say(a.name .. "'s spot is where you're standing. Within " .. AREA_RANGE .. " m of it, Greenthumb picks this area for you.") end
  rebuild()
  return true
end

local function newFarm(name, notes)
  local px, py, pz = position()
  if not px then say("can't read your position, no farm saved"); return nil end
  name = clean(name)
  if name == "" then name = (zone or sceneName()) .. " farm" end
  local f = { id = newId("f"), name = name, zone = zone or sceneName(), x = px, y = py, z = pz, notes = clean(notes), collapsed = false }
  farms[#farms + 1] = f
  reindex()
  prefs.farmId = f.id
  save()
  say("new farm " .. f.name .. " in " .. f.zone .. " at " .. fmt(px) .. ", " .. fmt(py) .. ", " .. fmt(pz) .. ". Add an area to it next.")
  rebuild()
  return f
end

local function moveFarmHere(f)
  local px, py, pz = position()
  if not px then say("can't read your position"); return end
  f.x, f.y, f.z, f.zone = px, py, pz, zone or sceneName()
  reindex(); save()
  say(f.name .. " now points to where you're standing in " .. f.zone)
  rebuild()
end

-- A farm can go once nothing is planted in it; its empty areas go with it.
local function deleteFarm(f)
  local n = #farmPlanters(f)
  if n > 0 then say(f.name .. " still has " .. plural(n, "bed") .. "; clear them first"); return false end
  for _, a in ipairs(areasOf(f)) do removeFrom(areas, a) end
  removeFrom(farms, f)
  if stopGuide then stopGuide(f) end
  reindex(); save(); say("deleted farm " .. f.name); rebuild()
  return true
end

-- A farm's areas in your order (layout order or as you moved them), then A to Z.
local function orderedAreas(f)
  local out = f and areasOf(f) or {}
  table.sort(out, function(a, c)
    if a.order and c.order and a.order ~= c.order then return a.order < c.order end
    if (a.order ~= nil) ~= (c.order ~= nil) then return a.order ~= nil end
    return string.lower(a.name) < string.lower(c.name)
  end)
  return out
end
-- Number a farm's areas 1, 2, 3 ... in their current order.
local function renumber(f)
  local list = orderedAreas(f)
  for i, a in ipairs(list) do a.order = i end
  return list
end
-- Move an area one place up (-1) or down (+1) within its farm.
local function moveArea(a, d)
  local f = farmById[a.farmId]; if not f then return end
  local list = renumber(f)
  local i = a.order
  local j = i + d
  if j < 1 or j > #list then return end
  list[i].order, list[j].order = j, i
  save(); rebuild()
end

local function uniqueAreaName(f, base)
  local used = {}
  for _, a in ipairs(areasOf(f)) do used[key(a.name)] = true end
  if not used[key(base)] then return base end
  local n = 2
  while used[key(base .. " " .. n)] do n = n + 1 end
  return base .. " " .. n
end

local function newArea(f, name, typ)
  typ = locationName(typ) or "Outside"
  name = clean(name)
  if name == "" then name = uniqueAreaName(f, typ) end
  local a = { id = newId("a"), farmId = f.id, name = name, type = typ, order = #renumber(f) + 1 }
  -- made while standing in the farm's zone: its spot is right here
  local px, py, pz = position()
  local here = px and key(f.zone) == zoneKey
  if here then a.x, a.y, a.z = px, py, pz end
  areas[#areas + 1] = a
  reindex()
  prefs.areaId, prefs.farmId, prefs.loc = a.id, f.id, typ
  save()
  say("new area " .. f.name .. " > " .. a.name .. ", " .. locLabel(typ) ..
    (here and ". Its spot is where you're standing (Edit > Set area spot here to change it)." or
      ". Stand in it and use Edit > Set area spot here so Greenthumb can pick it for you."))
  rebuild()
  return a
end

local function editArea(a, name, typ)
  name = clean(name)
  if name ~= "" then a.name = name end
  typ = locationName(typ)
  if typ and typ ~= a.type then
    a.type = typ
    local n = #plantersOf(a)
    reindex()
    if n > 0 then say(plural(n, "bed") .. " in " .. a.name .. " now grow at " .. locLabel(typ)) end
  end
  save(); rebuild()
end

local function deleteArea(a)
  local n = #plantersOf(a)
  if n > 0 then say(a.name .. " still has " .. plural(n, "bed") .. "; clear them first"); return false end
  removeFrom(areas, a)
  if prefs.areaId == a.id then prefs.areaId = "" end
  reindex(); save(); say("deleted area " .. a.name); rebuild()
  return true
end

---------------------------------------------------------------- go to farm (compass + map pin)
local goFarm = nil
local beaconOn, beaconFor = false, nil
local mapPlaced, mapDirty, mapRetryAt = false, false, 0
local MARKER = "gt_farm"
local function mapReady()
  return (tonumber(ShroudLuaApiVersion) or 0) >= 30 and type(ShroudSetMapMarker) == "function" and type(ShroudRemoveMapMarker) == "function"
end
local function mapLabel(t)
  t = tostring(t or ""):gsub("[%[%]<>]", ""):gsub("%c", " ")
  if #t > 40 then t = t:sub(1, 40) end
  return t ~= "" and t or "Farm"
end

-- Only the farm you're heading to gets a pin, and only while you're in its zone.
local function syncMap()
  if not mapReady() then return end
  if goFarm and key(goFarm.zone) == zoneKey then
    local ok, set, why = pcall(ShroudSetMapMarker, MARKER, goFarm.x, goFarm.y, goFarm.z, {
      label = mapLabel(goFarm.name), icon = "diamond", color = "#8fd16a", note = "Greenthumb farm" })
    if ok and set == true then mapPlaced = true
    elseif ok and (why == "rate" or why == "too_soon" or why == "no_scene") then mapDirty, mapRetryAt = true, now() + 12 end
  elseif mapPlaced then
    pcall(ShroudRemoveMapMarker, MARKER); mapPlaced = false
  end
end

-- The game's compass beacon points at the farm (only works in its zone).
local function updateBeacon()
  if type(ShroudSetBeacon) ~= "function" then return end
  local want = (goFarm and key(goFarm.zone) == zoneKey) and goFarm or nil
  if want == beaconFor then return end
  if want then
    local ok, set = pcall(ShroudSetBeacon, want.x, want.y, want.z, want.name)
    if ok and set ~= false then beaconOn, beaconFor = true, want end
  elseif beaconOn then
    pcall(ShroudClearBeacon); beaconOn, beaconFor = false, nil
  end
end

local refreshTrack -- defined below
local function guideTo(f)
  if not f or goFarm == f then
    if goFarm then say("stopped guiding to " .. goFarm.name) end
    goFarm = nil
  else
    goFarm = f
    if key(f.zone) == zoneKey then say("guiding you to " .. f.name .. " (compass and map)")
    else say(f.name .. " is in " .. f.zone .. ". Travel there and the compass will point to it.") end
  end
  mapDirty = true
  updateBeacon()
  if refreshTrack then refreshTrack() end
  rebuild()
end
stopGuide = function(f) if goFarm == f then guideTo(nil) end end

---------------------------------------------------------------- the list
-- The list is a flat run of items (farm headers, area headers, planters, notes),
-- built a few per frame. Element ids made for the list all start with "gtr_".
local rows = {}  -- refreshed every second: { kind, p / a / f, label, ... }
local ask, askAt, askRow = nil, 0, nil  -- Harvested pressed: that row offers Replant / Clear
local openSync, openFarmBox, openAreaBox, openPlant -- defined below
local startAddWalk, startWalkFarm -- defined below (Walk the farm)

local function zoneOk(f)
  return prefs.zoneFilter == "" or key(f.zone) == key(prefs.zoneFilter)
end

-- Soonest state of a set of planters (nil when empty).
local function bestOf(ps, t)
  local best
  for _, p in ipairs(ps) do
    local st = state(p, t)
    if not best or sooner(st, best) then best = st end
  end
  return best
end
local function bySoonest(list, t, statesOf)
  local keyed = {}
  for i, x in ipairs(list) do keyed[i] = { x = x, st = statesOf(x, t) } end
  table.sort(keyed, function(a, c)
    if a.st and c.st then
      if sooner(a.st, c.st) then return true end
      if sooner(c.st, a.st) then return false end
    elseif a.st or c.st then return a.st ~= nil end
    if a.x.order and c.x.order and a.x.order ~= c.x.order then return a.x.order < c.x.order end
    return string.lower(a.x.name) < string.lower(c.x.name)
  end)
  local out = {}
  for i, k in ipairs(keyed) do out[i] = k.x end
  return out
end

-- everything = true ignores the zone filter and collapsed farms (for /gth list).
local function items(everything)
  local t = clock()
  local out = {}
  local shownFarms = {}
  for _, f in ipairs(farms) do if everything or zoneOk(f) then shownFarms[#shownFarms + 1] = f end end
  for _, f in ipairs(bySoonest(shownFarms, t, function(f) return bestOf(farmPlanters(f), t) end)) do
    out[#out + 1] = { kind = "farm", f = f }
    if everything or not f.collapsed then
      local as = areasOf(f)
      if #as == 0 then out[#out + 1] = { kind = "note", text = "No areas yet. Press + Area to add one (Outside, Greenhouse or Inside)." } end
      local sorted = (prefs.sort == "order") and orderedAreas(f) or bySoonest(as, t, function(a) return bestOf(plantersOf(a), t) end)
      for _, a in ipairs(sorted) do
        out[#out + 1] = { kind = "area", a = a }
        local ps = bySoonest(plantersOf(a), t, function(p) return state(p, t) end)
        for _, p in ipairs(ps) do out[#out + 1] = { kind = "p", p = p } end
      end
    end
  end
  return out
end

local function resetAsk()
  if askRow then
    setText(made["gtr_w_" .. askRow], "Watered")
    setText(made["gtr_h_" .. askRow], "Harvested")
  end
  ask, askRow = nil, nil
end
local function onWaterBtn(p, i)
  if ask == p then resetAsk(); replant(p) else water(p) end
end
local function onHarvestBtn(p, i)
  if ask == p then resetAsk(); clearPlanter(p); return end
  resetAsk()
  ask, askAt, askRow = p, now(), i
  local st = state(p, clock())
  if st.kind ~= "ready" then say(label(p) .. " isn't ready yet (" .. dur(growSecs(p) - sched(p, clock())) .. " to go). Replant or Clear anyway?") end
  setText(made["gtr_w_" .. i], "Replant")
  setText(made["gtr_h_" .. i], "Clear")
end

-- Farm: a card header with the barn icon, the name underlined in gold, and its actions.
local function farmRow(f, i)
  local title = UI.Column{ style = { flexGrow = 1, marginLeft = 8, alignItems = "start" }, children = pack(
    UI.Label{ text = f.name, style = { color = GOLD, fontSize = 17, fontStyle = "bold" } },
    rule(GOLD, 1, 1, 2),
    UI.Label{ id = "gtr_fi_" .. i, text = "", style = { fontSize = 11, color = DIM } }) }
  return UI.Column{ style = { marginTop = 12, marginBottom = 2, paddingTop = 6, paddingBottom = 6, paddingLeft = 6, paddingRight = 6,
    backgroundColor = PANEL, borderRadius = 8, borderWidth = 1, borderColor = EDGE }, children = pack(
    UI.Row{ style = { alignItems = "center" }, children = pack(
      UI.Button{ text = f.collapsed and "+" or "-", tooltip = f.collapsed and "Show this farm" or "Hide this farm",
        style = { width = 26 }, onClick = function() f.collapsed = not f.collapsed; save(); rebuild() end },
      icon("farm", 28, f.zone),
      title,
      icon("pin", 16),
      UI.Button{ id = "gtr_go_" .. i, text = (goFarm == f) and "Stop" or "Go to farm", style = { marginLeft = 2 },
        tooltip = "Point the compass at this farm and pin it on the map", onClick = function() guideTo(f) end },
      UI.Button{ text = "+ Area", style = { marginLeft = 4 }, tooltip = "Walk into each area and save it",
        onClick = function() startAddWalk(f) end },
      UI.Button{ text = "Edit", style = { marginLeft = 4 }, onClick = function() openFarmBox(f) end }) },
    (f.notes ~= "") and UI.Label{ text = f.notes, style = { fontSize = 12, color = PARCH, whiteSpace = "wrap", marginLeft = 64, marginTop = 2 } } or nil) }
end

local function areaRow(a, i)
  local kids = {}
  -- in "my order" view each area can be moved up or down within its farm
  if prefs.sort == "order" then
    kids[#kids + 1] = UI.Button{ text = "^", tooltip = "Move up", onClick = function() moveArea(a, -1) end }
    kids[#kids + 1] = UI.Button{ text = "v", tooltip = "Move down", style = { marginLeft = 2, marginRight = 6 },
      onClick = function() moveArea(a, 1) end }
  end
  kids[#kids + 1] = icon(TYPE_ICON[a.type] or "outside", 24, locLabel(a.type))
  kids[#kids + 1] = UI.Column{ style = { flexGrow = 1, alignItems = "start", marginLeft = 6 }, children = {
    UI.Label{ text = a.name, style = { color = GREEN, fontSize = 15, fontStyle = "bold" } },
    UI.Label{ id = "gtr_ai_" .. i, text = "", style = { fontSize = 11, color = DIM } },
  } }
  kids[#kids + 1] = icon("water", 16)
  kids[#kids + 1] = UI.Button{ text = "Water all due", style = { marginLeft = 2 },
    tooltip = "Record a watering for every bed here whose window is open", onClick = function() waterAllDue(a) end }
  kids[#kids + 1] = UI.Button{ text = "Plant", style = { marginLeft = 4 }, onClick = function() openPlant(nil, a) end }
  kids[#kids + 1] = UI.Button{ text = "Edit", style = { marginLeft = 4 }, onClick = function() openAreaBox(a) end }
  return UI.Row{ style = { alignItems = "center", marginLeft = 12, marginTop = 6, marginBottom = 2, paddingTop = 4, paddingBottom = 4,
    paddingLeft = 6, paddingRight = 4, backgroundColor = PANEL_SOFT, borderRadius = 6 }, children = kids }
end

local function planterRow(p, i)
  -- the title already says seed and beds ("Garlic – beds 1-8"); this line adds the rest
  local extra = {}
  local bt = plantingBedTypes(p, areaOf(p))
  if bt ~= "" then extra[#extra + 1] = bt end
  if seedInfo(p.seed).unknown then extra[#extra + 1] = "unknown seed, timed as Quick" end
  if (p.off or 0) ~= 0 then extra[#extra + 1] = "synced " .. sdur(p.off) end
  if speedOf(p) > 1 then extra[#extra + 1] = "x" .. speedOf(p) .. " test" end
  local sub = table.concat(extra, ", ")
  local st = state(p, clock())
  local stIcon = ({ ready = "ready", water = "water", wait = "clock", grow = "sprout" })[st.kind] or "sprout"
  -- growth bar: a track with a fill whose width follows the crop's progress (updated every second)
  local bar = try("Column", { style = { width = BAR_W, height = 5, backgroundColor = TRACK, borderRadius = 3, marginTop = 3 }, children = {
    UI.Column{ id = "gtr_bar_" .. i, style = { width = 1, height = 5, backgroundColor = GREEN, borderRadius = 3 }, children = {} } } })
  return UI.Row{ style = { alignItems = "center", marginLeft = 30, marginTop = 2, paddingTop = 3, paddingBottom = 3 }, children = pack(
    icon(stIcon, 22, (statusText(p, st))),
    UI.Column{ style = { flexGrow = 1, alignItems = "start", marginLeft = 8 }, children = pack(
      UI.Row{ style = { alignItems = "center" }, children = {
        UI.Label{ text = label(p), style = { color = PARCH, fontStyle = "bold" } },
        UI.Label{ text = "  " .. sub, style = { fontSize = 11, color = DIM, whiteSpace = "wrap" } },
      } },
      UI.Label{ id = "gtr_act_" .. i, text = "", style = { color = GOLD, fontSize = 13 } },
      bar,
      (p.missed > 0) and UI.Row{ style = { alignItems = "center", marginTop = 2 }, children = pack(
        icon("warn", 12),
        UI.Label{ id = "gtr_miss_" .. i, text = "", style = { fontSize = 11, color = RED, marginLeft = 4 } }) } or nil) },
    UI.Button{ id = "gtr_w_" .. i, text = "Watered", tooltip = "Record a watering for the current window",
      style = { marginLeft = 6 }, onClick = function() onWaterBtn(p, i) end },
    UI.Button{ id = "gtr_h_" .. i, text = "Harvested", tooltip = "Then pick Replant (same seed) or Clear",
      style = { marginLeft = 4 }, onClick = function() onHarvestBtn(p, i) end },
    UI.Button{ text = "Sync", tooltip = "Sync from tooltip: type the game's \"Next watering in\" time",
      style = { marginLeft = 4 }, onClick = function() openSync(p) end },
    (nOf(p) > 1) and UI.Button{ text = "Split", tooltip = "Break into " .. nOf(p) .. " single beds you can manage one by one",
      style = { marginLeft = 4 }, onClick = function() splitPlanting(p) end } or nil) }
end

local function dueCount(ps, t)
  local n = 0
  for _, p in ipairs(ps) do if needsYou(state(p, t)) then n = n + nOf(p) end end
  return n
end

local tileText = {}
local function setTile(id, v)
  v = tostring(v)
  if tileText[id] ~= v then tileText[id] = v; setText(made[id], v) end
end

local function refreshRows()
  local t = clock()
  local due = dueCount(planters, t)
  local head = (#farms == 0 and #planters == 0) and "No farms yet" or
    (plural(#farms, "farm") .. ", " .. plural(countOf(planters), "bed") ..
      (due > 0 and (", " .. due .. " need" .. (due == 1 and "s" or "") .. " you") or ", all fine"))
  setText(made.gt_head, head)
  -- summary tiles
  local nWater, nReady, nMissed = 0, 0, 0
  for _, p in ipairs(planters) do
    local k = state(p, t).kind
    if k == "water" then nWater = nWater + nOf(p) elseif k == "ready" then nReady = nReady + nOf(p) end
    if p.missed > 0 then nMissed = nMissed + nOf(p) end
  end
  setTile("gt_s_water", nWater); setTile("gt_s_ready", nReady); setTile("gt_s_missed", nMissed); setTile("gt_s_total", countOf(planters))
  local hereNow = nearestArea() -- the area you're standing in (within 15 m), if any
  for _, r in ipairs(rows) do
    local txt, color
    if r.kind == "p" then
      local st = state(r.p, t)
      txt, color = statusText(r.p, st)
      local m = missedText(r.p)
      if r.missText ~= m then r.missText = m; setText(r.miss, m) end
      if r.bar then
        local T = growSecs(r.p)
        local w = math.max(1, math.floor(BAR_W * math.max(0, math.min(1, sched(r.p, t) / T)) + 0.5))
        local barColor = (st.kind == "ready") and GOLD or ((st.kind == "water") and BLUE or GREEN)
        if r.barW ~= w or r.barColor ~= barColor then
          r.barW, r.barColor = w, barColor
          pcall(function() r.bar:SetStyle({ width = w, height = 5, backgroundColor = barColor, borderRadius = 3 }) end)
        end
      end
    elseif r.kind == "farm" then
      local ps = farmPlanters(r.f)
      local d = dueCount(ps, t)
      local dist = distanceText(r.f.zone, r.f.x, r.f.z)
      txt = r.f.zone .. (dist and (", " .. dist) or "") .. ", " .. plural(countOf(ps), "bed") .. (d > 0 and (", " .. d .. " need you") or "")
      local go = (goFarm == r.f) and "Stop" or "Go to farm"
      if r.goText ~= go then r.goText = go; setText(r.go, go) end
    elseif r.kind == "area" then
      local ps = plantersOf(r.a)
      local d = dueCount(ps, t)
      local f = farmById[r.a.farmId]
      local dist = (r.a.x and f) and distanceText(f.zone, r.a.x, r.a.z) or nil
      -- "you're here" only on the area you're standing in; others show their distance
      local where_
      if r.a == hereNow then where_ = ", you're here"
      elseif dist and dist ~= "here" then where_ = ", " .. dist
      elseif not r.a.x then where_ = ", no spot set"
      else where_ = "" end
      txt = locLabel(r.a.type) .. ": " .. contents(r.a, ps) .. (d > 0 and (", " .. d .. " due") or "") .. where_
    end
    if txt and r.text ~= txt then r.text = txt; setText(r.label, txt) end
    if color and r.color ~= color then r.color = color; pcall(function() r.label:SetStyle({ color = color }) end) end
  end
  if ask and now() - askAt >= 6 then resetAsk() end
end

-- The game limits how fast add-ons make UI elements, so the list is built a
-- few items per frame, and rebuild requests are merged.
local MAX_ITEMS = 150
-- Rows now hold pictures and bars (more elements each), so they're built one per frame.
local ITEMS_PER_FRAME = 1
local ROWS_PER_FRAME = 3 -- seed buttons in the plant dialog
local pending, pendingAt, wantRebuild, lastBuild = nil, 1, false, -10

rebuild = function() wantRebuild = true end

local function isShown()
  if not win then return false end
  local ok, shown = pcall(function() return win:IsShown() end)
  return ok and shown
end

local function filterLabel() return prefs.zoneFilter == "" and "All zones" or prefs.zoneFilter end

local function startBuild()
  wantRebuild = false; lastBuild = now()
  if not list then return end
  for k in pairs(made) do
    if string.sub(k, 1, 4) == "gtr_" then made[k] = nil end
  end
  ask, askRow = nil, nil
  list:Clear()
  rows = {}
  local shown = items()
  if #shown == 0 then
    list:Add(UI.Label{ text = #farms == 0 and "No farms yet. Stand at your farm and press New farm, then add an area and plant." or
      ("No farms in " .. filterLabel() .. "."), class = "dim", style = { whiteSpace = "wrap", color = DIM } })
  end
  pending, pendingAt = shown, 1
  setText(made.gt_filter, filterLabel())
end

local function buildSome()
  if not pending or not list then return end
  local stop = math.min(#pending, MAX_ITEMS, pendingAt + ITEMS_PER_FRAME - 1)
  for i = pendingAt, stop do
    local it = pending[i]
    if it.kind == "farm" then
      list:Add(farmRow(it.f, i))
      rows[#rows + 1] = { kind = "farm", f = it.f, label = made["gtr_fi_" .. i], go = made["gtr_go_" .. i] }
    elseif it.kind == "area" then
      list:Add(areaRow(it.a, i))
      rows[#rows + 1] = { kind = "area", a = it.a, label = made["gtr_ai_" .. i] }
    elseif it.kind == "p" then
      list:Add(planterRow(it.p, i))
      rows[#rows + 1] = { kind = "p", p = it.p, label = made["gtr_act_" .. i], miss = made["gtr_miss_" .. i], bar = made["gtr_bar_" .. i] }
    else
      list:Add(UI.Label{ text = it.text, class = "dim",
        style = { fontSize = 11, color = DIM, whiteSpace = "wrap", marginLeft = it.indent or 14 } })
    end
  end
  pendingAt = stop + 1
  if pendingAt > math.min(#pending, MAX_ITEMS) then
    if #pending > MAX_ITEMS then
      list:Add(UI.Label{ text = (#pending - MAX_ITEMS) .. " more lines (hide a farm with - or pick a zone to see them)",
        class = "dim", style = { fontSize = 11, color = DIM } })
    end
    pending = nil
    refreshRows()
  end
end

---------------------------------------------------------------- alerts and catch-up
local function alertLine(p, msg) return label(p) .. " (" .. where(p) .. "): " .. msg end

local function checkAlerts()
  local t = clock()
  local out, dirty, changed = {}, false, false
  for _, p in ipairs(planters) do
    if applyMissed(p, t) then dirty = true end
    local st = state(p, t)
    local a = alerted[p.id]; if not a then a = {}; alerted[p.id] = a end
    if st.kind == "water" then
      -- window 1 is already open at planting (primeAlerts marks it), unless a sync offset delays it
      if a.open ~= st.k then
        a.open = st.k
        if prefs.aOpen then out[#out + 1] = alertLine(p, "watering window " .. st.k .. " is open, closes in " .. dur(st.left)) end
      end
      if st.left <= hourOf(p) and a.close ~= st.k then
        a.close = st.k
        if prefs.aClose then out[#out + 1] = alertLine(p, "water in the next " .. dur(st.left) .. " or you'll miss window " .. st.k) end
      end
    elseif st.kind == "ready" and not a.ready then
      a.ready = true
      if prefs.aReady then out[#out + 1] = alertLine(p, "ready to harvest") end
    end
    local sk = st.kind .. (st.k or 0) .. ":" .. p.missed
    if lastKind[p.id] ~= sk then lastKind[p.id] = sk; changed = true end
  end
  if dirty then save() end
  if changed then rebuild() end
  if #out > 0 then
    for _, l in ipairs(out) do say(l) end
    showNotice(out[1] .. (#out > 1 and ("  (+" .. (#out - 1) .. " more in chat)") or ""))
  end
end

-- On load: count windows missed while you were away, and mark what's already
-- happened as alerted (the catch-up report covers it).
local function startCatchUp()
  local t = clock()
  local due, missed = {}, {}
  local nextP, nextSt = nil, nil
  for _, p in ipairs(planters) do
    local before = p.missed
    applyMissed(p, t)
    if p.missed > before then missed[#missed + 1] = label(p) end
    local st = primeAlerts(p, t)
    if needsYou(st) then due[#due + 1] = alertLine(p, (statusText(p, st)))
    elseif not nextSt or st.left < nextSt.left then nextP, nextSt = p, st end
  end
  if #missed > 0 then save() end
  local lines = {}
  if migratedNote then lines[#lines + 1] = migratedNote end
  if #missed > 0 then lines[#lines + 1] = "missed a watering while you were away: " .. table.concat(missed, ", ") end
  if #due > 0 then
    lines[#lines + 1] = #due .. " bed" .. (#due == 1 and "" or "s") .. " need you now:"
    for _, l in ipairs(due) do lines[#lines + 1] = "  " .. l end
  elseif nextP then
    lines[#lines + 1] = "nothing due. Next: " .. alertLine(nextP, (statusText(nextP, nextSt)))
  end
  catchUp = { lines = lines, notice = (#due > 0) and (#due .. " bed" .. (#due == 1 and " needs" or "s need") .. " you. Click to open Greenthumb.") or nil }
  catchUpAt = now() + 3
end

---------------------------------------------------------------- inputs
local function inputText(e)
  if not e then return "" end
  local ok, v = pcall(function() return e:GetText() end)
  return (ok and type(v) == "string") and v or ""
end
local function makeInput(id, placeholder)
  for _, kind in ipairs({ "TextInput", "TextField", "Input" }) do
    if hasUI(kind) then
      local ok, e = pcall(UI[kind], { id = id, placeholder = placeholder, style = { flexGrow = 1 } })
      if ok and e then return e end
    end
  end
  return nil
end
-- Dialog panels: a dark rounded card with a coloured edge.
-- Only one panel (new farm, area edit, walk, plant, sync) is open at a time:
-- each registers how to close itself, and opening one closes the rest.
local panelClosers = {}
local function soloPanel(name)
  for k, close in pairs(panelClosers) do
    if k ~= name then pcall(close) end
  end
end

local function boxStyle(color)
  return { marginBottom = 8, paddingTop = 8, paddingBottom = 8, paddingLeft = 10, paddingRight = 10,
    borderWidth = 1, borderColor = color, borderRadius = 8, backgroundColor = PANEL }
end

---------------------------------------------------------------- farm box (new / edit)
local farmBox, farmHead, farmNameIn, farmNotesIn, farmEditing = nil, nil, nil, nil, nil
local farmDelAt = 0

local function closeFarmBox() farmEditing = nil; showEl(farmBox, false) end
panelClosers.farm = closeFarmBox
openFarmBox = function(f)
  if not farmBox then
    if f then say("use /gth farm <name> to make a farm; editing needs the game's text boxes")
    else local nf = newFarm("", ""); if nf then startAddWalk(nf) end end
    return
  end
  soloPanel("farm")
  farmEditing = f
  farmDelAt = 0
  setText(farmHead, f and ("Edit farm " .. f.name .. " (" .. f.zone .. ")") or
    ("New farm here in " .. (zone or sceneName()) .. ". Stand at its entrance or middle."))
  setText(farmNameIn, f and f.name or "")
  setText(farmNotesIn, f and f.notes or "")
  setText(made.gt_fb_save, f and "Save" or "Create farm")
  setText(made.gt_fb_del, "Delete")
  showEl(made.gt_fb_editrow, f ~= nil)
  showEl(farmBox, true)
  if not isShown() then setShown(true); rebuild() end
end
local function saveFarmBox()
  local name, notes = clean(inputText(farmNameIn)), clean(inputText(farmNotesIn))
  local f = farmEditing
  closeFarmBox()
  if f then
    if name ~= "" then f.name = name end
    f.notes = notes
    reindex(); save(); say("saved farm " .. f.name); rebuild()
  else
    local nf = newFarm(name, notes)
    if nf then startAddWalk(nf) end
  end
end

local function farmBoxSpec()
  farmNameIn = makeInput("gt_fb_name", "Farm name, e.g. Riverside Farm")
  farmNotesIn = makeInput("gt_fb_notes", "Notes (optional), e.g. lot 4, row house; key in the chest")
  if not farmNameIn then return nil end
  local kids = {
    sectionTitle("farm", "", "gt_fb_head", GOLD),
    UI.Row{ style = { marginBottom = 4 }, children = { farmNameIn } },
  }
  if farmNotesIn then kids[#kids + 1] = UI.Row{ style = { marginBottom = 4 }, children = { farmNotesIn } } end
  kids[#kids + 1] = UI.Row{ style = { alignItems = "center" }, children = {
    UI.Button{ id = "gt_fb_save", text = "Create farm", style = PRIMARY, onClick = saveFarmBox },
    UI.Button{ text = "Cancel", style = { marginLeft = 6 }, onClick = closeFarmBox },
  } }
  kids[#kids + 1] = UI.Row{ id = "gt_fb_editrow", visible = false, style = { alignItems = "center", marginTop = 4 }, children = {
    UI.Button{ text = "Move here", tooltip = "Save where you're standing as this farm's spot",
      onClick = function() local f = farmEditing; closeFarmBox(); if f then moveFarmHere(f) end end },
    UI.Button{ text = "Walk this farm", style = { marginLeft = 6 }, tooltip = "Step through the entrance and each area to save their spots again",
      onClick = function() local f = farmEditing; closeFarmBox(); if f then startWalkFarm(f) end end },
    UI.Button{ id = "gt_fb_del", text = "Delete", style = { marginLeft = 6 }, tooltip = "Only when nothing is planted in it (click twice)",
      onClick = function()
        local f = farmEditing; if not f then return end
        if now() - farmDelAt < 3 then
          if deleteFarm(f) then closeFarmBox() end
        else farmDelAt = now(); setText(made.gt_fb_del, "Sure?") end
      end },
  } }
  return UI.Column{ id = "gt_farm_box", visible = false, style = boxStyle(GOLD), children = kids }
end

---------------------------------------------------------------- small UI jobs (built a few per frame)
local uiJobs = {}
local function queue(fn) uiJobs[#uiJobs + 1] = fn end

---------------------------------------------------------------- bed types
-- Add a bed type of your own (returns its name; an existing type is reused).
local function addBedType(name)
  name = clean(name):gsub("[;,]", " ")
  if name == "" then return nil end
  for _, t in ipairs(bedTypes()) do if key(t) == key(name) then return t end end
  customBeds[#customBeds + 1] = name
  save()
  say("new bed type: " .. name)
  return name
end
-- A bed-type picker: the game's dropdown, or a button that steps through the types.
local function bedPicker(value, onPick, width)
  local choices = bedTypes()
  local dd = try("Dropdown", { choices = choices, value = (value and value ~= "") and value or choices[1],
    style = { width = width or 220 }, tooltip = "Planting bed type", onChange = function(_, v) onPick(v) end })
  if dd then return dd end
  local i = 1
  for k, t in ipairs(choices) do if t == value then i = k end end
  local btn
  btn = UI.Button{ text = choices[i], tooltip = "Click for the next bed type",
    onClick = function() i = i % #choices + 1; setText(btn, choices[i]); onPick(choices[i]) end }
  return btn
end

---------------------------------------------------------------- area box (new / edit)
local areaBox, areaHead, areaNameIn, areaEditing, areaFarm = nil, nil, nil, nil, nil
local areaType = "Outside"
local areaDelAt = 0
local afterArea = nil -- called with the new area (the plant dialog uses it)
-- bed setup being edited: how many, numbered or just a count, and each bed's type
local ab = { count = nil, numbered = true, types = {}, all = DEFAULT_BEDS[1], lastCount = nil }
local abCountIn, abTypeIn = nil, nil

local function refreshNumbering()
  setText(made.gt_ab_num1, ab.numbered and "[Numbered beds]" or "Numbered beds")
  setText(made.gt_ab_num0, ab.numbered and "Just count" or "[Just count]")
  showEl(made.gt_ab_gridrow, ab.numbered and (ab.count or 0) > 0)
end
-- The per-bed grid: one button per bed showing its type; click to step through the types.
local function buildBedGrid()
  local grid = made.gt_ab_grid; if not grid then return end
  pcall(function() grid:Clear() end)
  for k in pairs(made) do if string.sub(k, 1, 7) == "gt_abg_" then made[k] = nil end end
  local n = math.min(ab.count or 0, 60)
  local row
  for i = 1, n do
    local bi = i
    queue(function()
      if (bi - 1) % 4 == 0 then row = UI.Row{ style = { marginBottom = 2 }, children = {} }; grid:Add(row) end
      row:Add(UI.Button{ id = "gt_abg_" .. bi, text = bi .. " " .. (bedShort(ab.types[bi]) ~= "" and bedShort(ab.types[bi]) or "-"),
        tooltip = "Bed " .. bi .. ": click for the next type", style = { width = 110, marginRight = 4 },
        onClick = function()
          local list = bedTypes()
          local at = 0
          for k, t in ipairs(list) do if t == ab.types[bi] then at = k end end
          ab.types[bi] = list[at % #list + 1]
          setText(made["gt_abg_" .. bi], bi .. " " .. bedShort(ab.types[bi]))
        end })
    end)
  end
  refreshNumbering()
end
-- The "All beds" dropdown is rebuilt when a new type is added, so it lists it.
local function buildAllPicker()
  local holder = made.gt_ab_allholder; if not holder then return end
  pcall(function() holder:Clear() end)
  queue(function()
    holder:Add(bedPicker(ab.all, function(v)
      ab.all = v
      for i = 1, (ab.count or 0) do ab.types[i] = v end
      buildBedGrid()
    end))
  end)
end
local function loadBedSetup(a)
  ab.count = a and a.count or nil
  ab.numbered = not (a and a.numbered == false)
  ab.types = {}
  if a and a.bedTypes then for i, t in ipairs(a.bedTypes) do ab.types[i] = t end end
  ab.all = (a and a.bedTypes and a.bedTypes[1] ~= "" and a.bedTypes[1]) or ab.all or DEFAULT_BEDS[1]
  ab.lastCount = ab.count
  setText(abCountIn, ab.count and tostring(ab.count) or "")
  setText(abTypeIn, "")
  buildAllPicker()
  buildBedGrid()
end
-- Copy the bed setup into an area (beds without a type get the "All beds" type).
local function applyBedSetup(a)
  a.count = ab.count
  a.numbered = ab.numbered
  if ab.count and ab.count > 0 then
    a.bedTypes = {}
    for i = 1, ab.count do a.bedTypes[i] = (ab.types[i] and ab.types[i] ~= "") and ab.types[i] or ab.all end
  end
end

local function refreshAreaTypes()
  for _, l in ipairs(LOCATIONS) do
    local t = l .. " " .. GROWTH[l]
    setText(made["gt_ab_t_" .. l], (areaType == l) and ("[" .. t .. "]") or t)
  end
end
local areaOpen = false
local function closeAreaBox() areaEditing, areaFarm, afterArea, areaOpen = nil, nil, nil, false; showEl(areaBox, false) end
panelClosers.area = closeAreaBox
openAreaBox = function(a, f, after)
  f = f or (a and farmById[a.farmId])
  if not f then say("make a farm first (New farm)"); return end
  if not areaBox then
    if a then say("use /gth area <name> <type> to add areas; editing needs the game's text boxes")
    else local na = newArea(f, "", prefs.loc); if after then after(na) end end
    return
  end
  soloPanel("area")
  areaEditing, areaFarm, afterArea = a, f, after
  areaType = a and a.type or prefs.loc
  areaDelAt = 0
  local inZone = key(f.zone) == zoneKey
  setText(areaHead, a and ("Edit area " .. f.name .. " > " .. a.name .. (a.x and "" or " (no spot set yet)")) or
    ("New area in " .. f.name .. (inZone and ". Stand inside it: its spot will be where you are now." or
      ". You're not in " .. f.zone .. ", so set its spot later with Edit > Set area spot here.")))
  setText(areaNameIn, a and a.name or "")
  setText(made.gt_ab_save, a and "Save" or "Create area")
  setText(made.gt_ab_del, "Delete")
  showEl(made.gt_ab_del, a ~= nil)
  showEl(made.gt_ab_spot, a ~= nil)
  refreshAreaTypes()
  loadBedSetup(a)
  areaOpen = true
  showEl(areaBox, true)
  if not isShown() then setShown(true); rebuild() end
end
local function saveAreaBox()
  local name = clean(inputText(areaNameIn))
  local cnt = tonumber((inputText(abCountIn):match("%d+")) or "")
  if cnt then ab.count = math.max(0, math.min(500, cnt)) end
  local a, f, after, typ = areaEditing, areaFarm, afterArea, areaType
  closeAreaBox()
  if a then
    applyBedSetup(a)
    editArea(a, name, typ)
  elseif f then
    local na = newArea(f, name, typ)
    applyBedSetup(na); save()
    if after then after(na) end
  end
end

local function areaBoxSpec()
  areaNameIn = makeInput("gt_ab_name", "Area name (optional), e.g. Greenhouse 1 or Back field")
  if not areaNameIn then return nil end
  local types = { UI.Label{ text = "Type:", style = { color = DIM, marginRight = 4 } } }
  for _, l in ipairs(LOCATIONS) do
    local ll = l
    types[#types + 1] = UI.Button{ id = "gt_ab_t_" .. l, text = l, style = { marginRight = 4 },
      tooltip = locLabel(l), onClick = function() areaType = ll; refreshAreaTypes() end }
  end
  abCountIn = makeInput("gt_ab_count", "e.g. 8")
  abTypeIn = makeInput("gt_ab_newtype", "New bed type, e.g. Raised Garden Bed")
  local beds = {
    -- how many planting beds, and whether you pick them by number
    UI.Row{ style = { alignItems = "center", marginBottom = 4 }, children = pack(
      UI.Label{ text = "Planting beds:", style = { color = DIM, marginRight = 6 } },
      abCountIn and UI.Row{ style = { width = 70 }, children = { abCountIn } } or nil,
      UI.Button{ id = "gt_ab_num1", text = "Numbered beds", style = { marginLeft = 8 }, tooltip = "Pick beds by number when planting (bed 1, 2, 3 ...)",
        onClick = function() ab.numbered = true; refreshNumbering() end },
      UI.Button{ id = "gt_ab_num0", text = "Just count", style = { marginLeft = 4 }, tooltip = "Just say how many beds when planting",
        onClick = function() ab.numbered = false; refreshNumbering() end }) },
    -- one type for every bed
    UI.Row{ style = { alignItems = "center", marginBottom = 4 }, children = {
      UI.Label{ text = "All beds:", style = { color = DIM, marginRight = 6 } },
      UI.Column{ id = "gt_ab_allholder", children = {} },
    } },
    -- or each bed its own type
    UI.Column{ id = "gt_ab_gridrow", visible = false, style = { marginBottom = 4 }, children = {
      UI.Label{ text = "Each bed (click to change its type):", style = { color = DIM, fontSize = 11, marginBottom = 2 } },
      UI.Column{ id = "gt_ab_grid", children = {} },
    } },
  }
  if abTypeIn then
    beds[#beds + 1] = UI.Row{ style = { alignItems = "center", marginBottom = 6 }, children = {
      abTypeIn,
      UI.Button{ text = "+ Add type", style = { marginLeft = 6 }, onClick = function()
        local t = addBedType(inputText(abTypeIn))
        if t then setText(abTypeIn, ""); ab.all = t; buildAllPicker(); buildBedGrid() end
      end },
    } }
  end
  local kids = {
    sectionTitle("plus", "", "gt_ab_head", GREEN),
    UI.Row{ style = { marginBottom = 4 }, children = { areaNameIn } },
    UI.Row{ style = { alignItems = "center", marginBottom = 4 }, children = types },
  }
  for _, k in ipairs(beds) do kids[#kids + 1] = k end
  kids[#kids + 1] = UI.Row{ style = { alignItems = "center" }, children = {
      UI.Button{ id = "gt_ab_save", text = "Create area", style = PRIMARY, onClick = saveAreaBox },
      UI.Button{ text = "Cancel", style = { marginLeft = 6 }, onClick = closeAreaBox },
      UI.Button{ id = "gt_ab_spot", text = "Set area spot here", style = { marginLeft = 6 },
        tooltip = "Stand inside the area: near this spot Greenthumb picks this area for you",
        onClick = function() local a = areaEditing; if a and setAreaSpot(a) then closeAreaBox() end end },
      UI.Button{ id = "gt_ab_del", text = "Delete", style = { marginLeft = 6 }, tooltip = "Only when nothing is planted in it (click twice)",
        onClick = function()
          local a = areaEditing; if not a then return end
          if now() - areaDelAt < 3 then
            if deleteArea(a) then closeAreaBox() end
          else areaDelAt = now(); setText(made.gt_ab_del, "Sure?") end
        end },
  } }
  return UI.Column{ id = "gt_area_box", visible = false, style = boxStyle(GREEN), children = kids }
end

---------------------------------------------------------------- farm layout + Walk the farm (/gth setup)
-- farm-layout.tsv (farm, area, type, order) lists farms and their areas. /gth setup
-- creates whatever is missing (never duplicates, never deletes or changes), then
-- walks you through saving the farm entrance and a spot inside each area.
local function readLayout()
  if type(ShroudLuaPath) ~= "string" or type(io) ~= "table" or type(io.open) ~= "function" then return nil, "no file access" end
  local tried = {}
  for _, path in ipairs({ ShroudLuaPath .. "/greenthumb/farm-layout.tsv", ShroudLuaPath .. "/farm-layout.tsv" }) do
    tried[#tried + 1] = path
    local text
    pcall(function() local f = io.open(path, "r"); if f then text = f:read("*a"); f:close() end end)
    if text and text ~= "" then
      text = text:gsub("^\239\187\191", "") -- UTF-8 BOM
      local rows, n = {}, 0
      for ln in string.gmatch(text, "[^\r\n]+") do
        local f = {}
        for part in string.gmatch(ln .. "\t", "([^\t]*)\t") do f[#f + 1] = clean(part) end
        n = n + 1
        local isHeader = string.lower(f[1] or "") == "farm" and string.lower(f[2] or "") == "area"
        if not isHeader and string.sub(ln, 1, 1) ~= "#" and (f[1] or "") ~= "" and (f[2] or "") ~= "" then
          rows[#rows + 1] = { farm = f[1], area = f[2], type = locationName(f[3]) or "Outside", order = tonumber(f[4] or "") or n }
        end
      end
      table.sort(rows, function(a, c)
        if a.farm ~= c.farm then return a.farm < c.farm end
        return a.order < c.order
      end)
      return rows, path
    end
  end
  return nil, table.concat(tried, " or ")
end

-- A farm's areas in your order. Used by the walk and the plant dialog.
local areaChoices = orderedAreas

-- Two kinds of walk share one panel:
--   steps: go through a farm's entrance and existing areas, saving a spot at each
--          (/greenthumb setup, or Edit > Walk this farm)
--   add:   right after New farm (or + Area): stand in each area, name it, pick its
--          type and press Save area here, as many times as you like
local walk = nil -- { mode = "steps", steps = { { kind = "farm"|"area", f, a } }, i } or { mode = "add", f, added, type }
local walkBox, walkCountIn, walkNameIn = nil, nil, nil

local function walkStep() return walk and walk.mode == "steps" and walk.steps[walk.i] or nil end

local function refreshWalkTypes()
  for _, l in ipairs(LOCATIONS) do
    local t = l .. " " .. GROWTH[l]
    setText(made["gt_wk_t_" .. l], (walk and walk.type == l) and ("[" .. t .. "]") or t)
  end
end

local function refreshWalk()
  if not walk then return end
  local adding = walk.mode == "add"
  showEl(made.gt_wk_namerow, adding and walkNameIn ~= nil)
  showEl(made.gt_wk_typerow, adding)
  showEl(made.gt_wk_skip, not adding)
  showEl(made.gt_wk_back, not adding)
  setText(made.gt_wk_save, adding and "Save area here" or "Save here")
  setText(made.gt_wk_finish, adding and "Done" or "Finish")
  if adding then
    local f = walk.f
    setText(made.gt_wk_head, "Add areas: " .. f.name)
    setText(made.gt_wk_step, plural(walk.added, "area") .. " added")
    setText(made.gt_wk_text, "Walk into an area, give it a name, pick its type and press Save area here. Done when you've added them all.")
    setText(made.gt_wk_status, key(f.zone) == zoneKey and ("Areas so far: " .. #areasOf(f) .. ".")
      or ("You're not in " .. f.zone .. "; go there to save areas."))
    showEl(made.gt_wk_countrow, walkCountIn ~= nil)
    refreshWalkTypes()
    return
  end
  local s = walkStep()
  if not s then return end
  local f = s.f
  setText(made.gt_wk_head, "Walk the farm: " .. f.name)
  setText(made.gt_wk_step, walk.i .. " / " .. #walk.steps)
  if s.kind == "farm" then
    setText(made.gt_wk_text, "Stand at the entrance of " .. f.name .. ", then press Save here.")
    setText(made.gt_wk_status, "Saves the farm's zone and spot (now: " .. f.zone .. ").")
    showEl(made.gt_wk_countrow, false)
  else
    local a = s.a
    setText(made.gt_wk_text, "Stand inside " .. a.name .. " (" .. locLabel(a.type) .. "), then press Save here.")
    local dist = a.x and distanceText(f.zone, a.x, a.z)
    setText(made.gt_wk_status, a.x and ("Spot already saved" .. (dist and (", " .. dist .. " from you") or "") .. ". Save here moves it.")
      or "No spot saved yet.")
    showEl(made.gt_wk_countrow, walkCountIn ~= nil)
    setText(walkCountIn, a.count and tostring(a.count) or "")
  end
end

local function closeWalk()
  showEl(walkBox, false)
  if walk and walk.mode == "add" then
    say(walk.f.name .. ": " .. plural(walk.added, "area") .. " added" ..
      (walk.added > 0 and ". Standing in one now picks it for planting and watering." or "."))
  elseif walk then
    local n = 0
    for _, s in ipairs(walk.steps) do if s.kind == "area" and s.a.x then n = n + 1 end end
    local total = 0
    for _, s in ipairs(walk.steps) do if s.kind == "area" then total = total + 1 end end
    say("walk finished: " .. n .. " of " .. plural(total, "area") .. " have a spot. Standing in one now picks it for planting and watering.")
  end
  walk = nil
  rebuild()
end

local function walkMove(d)
  if not walk then return end
  walk.i = walk.i + d
  if walk.i < 1 then walk.i = 1 end
  if walk.i > #walk.steps then closeWalk(); return end
  refreshWalk()
end

-- The walk's bed count + bed type: every bed of the area gets that type
-- (mix types per bed later with Edit on the area). Existing per-bed types are
-- kept unless the bed count changes.
local walkBedType = DEFAULT_BEDS[1]
local function walkBeds(a)
  local n = tonumber((inputText(walkCountIn):match("%d+")) or "")
  if not n then return end
  n = math.max(0, math.min(500, n))
  local changed = a.count ~= n or not a.bedTypes
  a.count = n
  if a.numbered == nil then a.numbered = true end
  if changed and n > 0 then
    a.bedTypes = {}
    for i = 1, n do a.bedTypes[i] = walkBedType end
  end
end
local function buildWalkBedPicker()
  local holder = made.gt_wk_bedholder; if not holder then return end
  pcall(function() holder:Clear() end)
  queue(function() holder:Add(bedPicker(walkBedType, function(v) walkBedType = v end, 200)) end)
end

local function walkSave()
  if walk and walk.mode == "add" then
    local f = walk.f
    if key(f.zone) ~= zoneKey then say("you're not in " .. f.zone .. "; go to " .. f.name .. " to save its areas"); return end
    if not position() then say("can't read your position"); return end
    local a = newArea(f, inputText(walkNameIn), walk.type)
    walkBeds(a); save()
    walk.added = walk.added + 1
    setText(walkNameIn, ""); setText(walkCountIn, "")
    refreshWalk()
    return
  end
  local s = walkStep(); if not s then return end
  local px, py, pz = position()
  if not px then say("can't read your position"); return end
  if s.kind == "farm" then
    s.f.x, s.f.y, s.f.z, s.f.zone = px, py, pz, zone or sceneName()
    reindex(); save()
    say(s.f.name .. ": entrance saved in " .. s.f.zone)
  else
    walkBeds(s.a)
    if not setAreaSpot(s.a, true) then return end
    say(s.a.name .. ": spot saved" .. (s.a.count and (", " .. plural(s.a.count, "bed") ..
      ((s.a.bedTypes and s.a.bedTypes[1]) and (" (" .. s.a.bedTypes[1] .. ")") or "")) or ""))
  end
  walkMove(1)
end

-- Walk every farm in the list (entrance, then its areas in order).
local function startWalk(farmList)
  local steps = {}
  for _, f in ipairs(farmList) do
    steps[#steps + 1] = { kind = "farm", f = f }
    for _, a in ipairs(areaChoices(f)) do steps[#steps + 1] = { kind = "area", f = f, a = a } end
  end
  if #steps == 0 then say("nothing to walk: make a farm first (New farm or farm-layout.tsv)"); return end
  if not walkBox then say("the walk panel isn't available here; use Edit > Move here and Set area spot here instead"); return end
  soloPanel("walk")
  walk = { mode = "steps", steps = steps, i = 1 }
  buildWalkBedPicker()
  if not isShown() then setShown(true) end
  showEl(walkBox, true)
  refreshWalk()
  rebuild()
end
startWalkFarm = function(f) startWalk({ f }) end
-- closed by another panel: just hide it (Done / Finish give the summary)
panelClosers.walk = function() if walk then walk = nil; showEl(walkBox, false); rebuild() end end

-- Add areas one after another while walking the farm (no file needed).
startAddWalk = function(f)
  if not f then return end
  if not walkBox then openAreaBox(nil, f); return end
  soloPanel("walk")
  walk = { mode = "add", f = f, added = 0, type = prefs.loc or "Outside" }
  buildWalkBedPicker()
  setText(walkNameIn, ""); setText(walkCountIn, "")
  if not isShown() then setShown(true) end
  showEl(walkBox, true)
  refreshWalk()
  rebuild()
end

local function runSetup()
  local rows, from = readLayout()
  if not rows then
    local f = nearestFarm() or farmById[prefs.farmId]
    say("no farm-layout.tsv found (looked in " .. tostring(from) .. ")" ..
      (f and ("; walking " .. f.name .. " as it is") or ""))
    if f then startWalk({ f }) end
    return
  end
  local px, py, pz = position()
  local newFarms, newAreas, walkFarms, seen = 0, 0, {}, {}
  for _, r in ipairs(rows) do
    local f
    for _, x in ipairs(farms) do if key(x.name) == key(r.farm) then f = x end end
    if not f then
      -- placed where you are for now; the walk's first step saves the real entrance
      f = { id = newId("f"), name = r.farm, zone = zone or sceneName(), x = px or 0, y = py or 0, z = pz or 0,
        notes = "", collapsed = false }
      farms[#farms + 1] = f; farmById[f.id] = f; newFarms = newFarms + 1
    end
    if not seen[f.id] then seen[f.id] = true; walkFarms[#walkFarms + 1] = f end
    local a
    for _, x in ipairs(areas) do if x.farmId == f.id and key(x.name) == key(r.area) then a = x end end
    if not a then
      a = { id = newId("a"), farmId = f.id, name = r.area, type = r.type, order = r.order }
      areas[#areas + 1] = a; areaById[a.id] = a; newAreas = newAreas + 1
    elseif not a.order then
      a.order = r.order -- only fills in the layout order; nothing else of yours changes
    end
  end
  reindex(); save()
  say("farm layout: " .. plural(#rows, "area") .. " in the file; added " .. plural(newFarms, "farm") .. " and " ..
    plural(newAreas, "area") .. " (nothing changed or removed).")
  startWalk(walkFarms)
end

local function walkBoxSpec()
  walkNameIn = makeInput("gt_wk_name", "Area name, e.g. GH1 or Back field (optional)")
  walkCountIn = makeInput("gt_wk_count", "e.g. 8")
  local types = { UI.Label{ text = "Type:", style = { color = DIM, marginRight = 4 } } }
  for _, l in ipairs(LOCATIONS) do
    local ll = l
    types[#types + 1] = UI.Button{ id = "gt_wk_t_" .. l, text = l, style = { marginRight = 4 }, tooltip = locLabel(l),
      onClick = function() if walk then walk.type = ll; prefs.loc = ll; refreshWalkTypes() end end }
  end
  local kids = {
    UI.Row{ style = { alignItems = "center", marginBottom = 2 }, children = {
      UI.Row{ style = { flexGrow = 1, alignItems = "center" }, children = pack(icon("pin", 20),
        UI.Label{ id = "gt_wk_head", text = "", style = { color = GOLD, fontSize = 16, fontStyle = "bold", marginLeft = 6 } }) },
      UI.Label{ id = "gt_wk_step", text = "", style = { color = BLUE } },
    } },
    UI.Label{ id = "gt_wk_text", text = "", style = { color = PARCH, fontSize = 15, whiteSpace = "wrap", marginBottom = 2 } },
    UI.Label{ id = "gt_wk_status", text = "", style = { color = DIM, fontSize = 11, whiteSpace = "wrap", marginBottom = 4 } },
  }
  if walkNameIn then
    kids[#kids + 1] = UI.Row{ id = "gt_wk_namerow", visible = false, style = { marginBottom = 4 }, children = { walkNameIn } }
  end
  kids[#kids + 1] = UI.Row{ id = "gt_wk_typerow", visible = false, style = { alignItems = "center", marginBottom = 4 }, children = types }
  if walkCountIn then
    kids[#kids + 1] = UI.Column{ id = "gt_wk_countrow", style = { marginBottom = 4 }, children = {
      UI.Row{ style = { alignItems = "center", marginBottom = 4 }, children = {
        UI.Label{ text = "How many planting beds here?", style = { color = DIM, marginRight = 6 } },
        UI.Row{ style = { width = 70 }, children = { walkCountIn } } } },
      UI.Row{ style = { alignItems = "center" }, children = {
        UI.Label{ text = "Bed type:", style = { color = DIM, marginRight = 6 } },
        UI.Column{ id = "gt_wk_bedholder", children = {} } } },
    } }
  end
  kids[#kids + 1] = UI.Row{ style = { alignItems = "center" }, children = {
    UI.Button{ id = "gt_wk_save", text = "Save here", style = PRIMARY, tooltip = "Save where you're standing", onClick = walkSave },
    UI.Button{ id = "gt_wk_skip", text = "Skip", style = { marginLeft = 6 }, onClick = function() walkMove(1) end },
    UI.Button{ id = "gt_wk_back", text = "Back", style = { marginLeft = 6 }, onClick = function() walkMove(-1) end },
    UI.Button{ id = "gt_wk_finish", text = "Finish", style = { marginLeft = 6 }, onClick = closeWalk },
  } }
  return UI.Column{ id = "gt_walk_box", visible = false, style = boxStyle(BLUE), children = kids }
end

---------------------------------------------------------------- plant dialog: farm -> area -> seed -> count
local plantBox, plantHead, seedList, seedLbl, searchIn = nil, nil, nil, nil, nil
local plantOpen = false
local pick = { seed = nil, farmId = "", areaId = "", count = 1, sel = {} }
local seedJobs, lastSearch = nil, nil
local fillSeeds -- defined below (the seed dropdown)

local function seedMatches(s, q)
  local name = string.lower(s.name)
  for w in string.gmatch(string.lower(q or ""), "%S+") do
    if not string.find(name, w, 1, true) then return false end
  end
  return true
end

-- Farms for the picker: the ones in your zone first, then A to Z.
local function farmChoices()
  local out = {}
  for _, f in ipairs(farms) do out[#out + 1] = f end
  table.sort(out, function(a, c)
    local ah, ch = key(a.zone) == zoneKey, key(c.zone) == zoneKey
    if ah ~= ch then return ah end
    return string.lower(a.name) < string.lower(c.name)
  end)
  return out
end

local closePlantNow -- defined below (closePlant)
-- The area being planted (nil if the farm/area pick doesn't match up).
local function pickArea()
  local a = areaById[pick.areaId]
  if a and a.farmId == pick.farmId then return a end
  return nil
end
local pickersOpen = false

-- One line per bed in the "pick beds" grid: free, selected, or already planted.
local function bedButtonText(a, n, taken)
  local t = bedShort(bedTypeOf(a, n))
  if taken then return n .. " " .. shortName(taken.seed) end
  return (pick.sel[n] and ("[" .. n .. "]") or tostring(n)) .. (t ~= "" and (" " .. t) or "")
end
local function selectedBeds()
  local out = {}
  for n in pairs(pick.sel) do out[#out + 1] = n end
  table.sort(out)
  return out
end

-- A seed's real timing in an area (Outside when none is picked), with any synced
-- correction for that seed and growth type: time until ready, and the watering window.
local function seedTiming(s, a)
  local loc = a and a.type or "Outside"
  local T = growFor(s.name, loc, prefs.speed)
  local off = (learned[learnKey(s.name, loc)] or 0) / prefs.speed
  return math.max(0, T + off), T / 3
end
-- "Garlic – 12h, 16 crops, 8g"
local function seedChoice(s, a)
  local ready = seedTiming(s, a)
  return shortName(s.name) .. " – " .. dur(ready) .. ", " .. s.yield .. " crops, " .. s.price .. "g"
end

local function updatePick()
  local f, a = farmById[pick.farmId], pickArea()
  setText(made.gt_pf, f and (f.name .. " (" .. f.zone .. ")") or "No farm yet: press New farm")
  setText(made.gt_pa, a and (a.name .. ", " .. locLabel(a.type)) or (f and "No area yet: press New area" or "-"))
  showEl(made.gt_pickers, pickersOpen or not a)
  local ps = a and plantersOf(a) or {}
  local free = a and freeBeds(a, ps) or {}
  setText(plantHead, a and ("Plant in " .. a.name) or "Plant: pick a farm and area")
  setText(made.gt_plant_sub, a and ((f and (f.name .. ", ") or "") .. locLabel(a.type) .. ", " ..
    (a.count and (#free .. " of " .. a.count .. " beds empty") or "bed count not set (Edit the area)")) or "")
  -- seed: the list until one is picked, then just the pick
  showEl(made.gt_seedpick, not pick.seed)
  showEl(made.gt_seedrow, pick.seed ~= nil)
  showEl(made.gt_where, pick.seed ~= nil and a ~= nil)
  if pick.seed then
    local ready, every = seedTiming(pick.seed, a)
    setText(seedLbl, shortName(pick.seed.name) .. ": ready in " .. dur(ready) .. ", water every " .. dur(every) ..
      ((prefs.speed > 1) and (" (test speed x" .. prefs.speed .. ")") or ""))
  end
  if not a then return end
  -- where to plant: the whole area, picked beds, or a count
  local numbered = (a.count or 0) > 0 and a.numbered ~= false
  showEl(made.gt_pw_all, a.count ~= nil and #free > 0)
  setText(made.gt_pw_all, "Plant all " .. #free .. " empty beds")
  showEl(made.gt_pw_numbered, numbered)
  showEl(made.gt_pw_count, not numbered)
  local nsel = #selectedBeds()
  setText(made.gt_pw_sel, nsel > 0 and ("Plant " .. nsel .. " selected " .. (nsel == 1 and "bed" or "beds")) or "Pick beds above")
  setText(made.gt_pc, tostring(pick.count))
  setText(made.gt_pw_hint, (a.count and #free == 0) and "Every bed in this area is planted. Harvest or Clear one first." or
    (not a.count and "Tip: Edit the area to set how many beds it has, so you can plant them all at once or pick them by number." or ""))
end

-- The bed grid for numbered areas, rebuilt when the area changes or after planting.
local function buildPlantGrid()
  local grid = made.gt_pgrid; if not grid then return end
  pcall(function() grid:Clear() end)
  for k in pairs(made) do if string.sub(k, 1, 7) == "gt_pgb_" then made[k] = nil end end
  local a = pickArea()
  if not (a and a.count and a.count > 0 and a.numbered ~= false) then return end
  local taken = takenBeds(plantersOf(a))
  local row
  for i = 1, math.min(a.count, 60) do
    local n = i
    queue(function()
      if (n - 1) % 4 == 0 then row = UI.Row{ style = { marginBottom = 2 }, children = {} }; grid:Add(row) end
      local tk = taken[n]
      row:Add(UI.Button{ id = "gt_pgb_" .. n, text = bedButtonText(a, n, tk),
        tooltip = tk and ("Bed " .. n .. ": " .. label(tk) .. " is planted here") or
          ("Bed " .. n .. (bedTypeOf(a, n) ~= "" and (", " .. bedTypeOf(a, n)) or "") .. ": click to select"),
        style = { width = 110, marginRight = 4, color = tk and DIM or PARCH },
        onClick = function()
          if tk then say("bed " .. n .. " already has " .. label(tk)); return end
          pick.sel[n] = (not pick.sel[n]) or nil
          setText(made["gt_pgb_" .. n], bedButtonText(a, n, nil))
          updatePick()
        end })
    end)
  end
end

local function setPickArea(a)
  pick.areaId = a and a.id or ""
  pick.sel = {}
  local ar = pickArea()
  if ar and ar.count then pick.count = math.max(1, #freeBeds(ar, plantersOf(ar))) end
  buildPlantGrid()
  updatePick()
  -- seed times depend on the area's growth rate
  if lastSearch ~= nil and fillSeeds then fillSeeds(lastSearch) end
end
local function pickFarm(f)
  pick.farmId = f and f.id or ""
  local as = areaChoices(f)
  local keep = areaById[pick.areaId]
  if keep and f and keep.farmId == f.id then setPickArea(keep) else setPickArea(as[1]) end
end
local function stepPick(listOf, cur, d)
  local l = listOf
  if #l == 0 then return nil end
  local at = 0
  for i, x in ipairs(l) do if x.id == cur then at = i end end
  if at == 0 then return l[1] end
  return l[(at - 1 + d) % #l + 1]
end

-- The seed picker: a dropdown (sorted by name, filtered by the search box) whose
-- lines show each seed's real time in the picked area: "Garlic – 12h, 16 crops, 8g".
-- Without the game's dropdown it falls back to a list of buttons.
fillSeeds = function(q)
  if not seedList then return end
  pcall(function() seedList:Clear() end)
  seedJobs = {}
  local a = pickArea()
  local list = {}
  for _, s in ipairs(SEEDS) do if seedMatches(s, q) then list[#list + 1] = s end end
  table.sort(list, function(x, y) return shortName(x.name) < shortName(y.name) end)
  if #list == 0 then
    seedList:Add(UI.Label{ text = "No seed matches \"" .. q .. "\".", style = { color = DIM } })
    return
  end
  if hasUI("Dropdown") then
    local choices, bySeed = { "Choose a seed (" .. #list .. ")" }, {}
    for _, s in ipairs(list) do
      local line = seedChoice(s, a)
      choices[#choices + 1] = line
      bySeed[line] = s
    end
    seedJobs[1] = function()
      local dd = try("Dropdown", { choices = choices, value = choices[1], style = { width = 320 },
        tooltip = "Times are for " .. (a and locLabel(a.type) or "Outside (1x growth)"),
        onChange = function(_, v) if bySeed[v] then pick.seed = bySeed[v]; updatePick() end end })
      if dd then seedList:Add(dd) end
    end
    return
  end
  for _, s in ipairs(list) do
    local ss = s
    seedJobs[#seedJobs + 1] = function()
      seedList:Add(UI.Button{ text = seedChoice(ss, a), tooltip = ss.name, style = { color = PARCH, marginBottom = 2 },
        onClick = function() pick.seed = ss; updatePick() end })
    end
  end
end

-- Plant the picked seed: all empty beds, the selected beds, or a count.
local function plantPicked(how)
  local a = pickArea()
  if not pick.seed then say("pick a seed first"); return end
  if not a then say("pick an area first (or press New area)"); return end
  local ps = plantersOf(a)
  if how == "all" then
    local free = freeBeds(a, ps)
    if #free == 0 then say("every bed in " .. a.name .. " is planted"); return end
    plant(a, pick.seed, #free, "", (a.numbered ~= false) and free or nil)
    closePlantNow()
    return
  elseif how == "selected" then
    local sel = selectedBeds()
    if #sel == 0 then say("click the beds you want first"); return end
    plant(a, pick.seed, #sel, "", sel)
  else
    plant(a, pick.seed, pick.count, "", nil)
  end
  -- stay open for the next seed in this area
  pick.seed, pick.sel = nil, {}
  fillSeeds(lastSearch or "")
  local ar = pickArea()
  if ar and ar.count then pick.count = math.max(1, #freeBeds(ar, plantersOf(ar))) end
  buildPlantGrid()
  updatePick()
end

-- Default farm/area: the one you asked for, else the area you're standing in,
-- else the last one used, else the nearest farm here.
openPlant = function(seed, a)
  if not plantBox then say("the plant dialog isn't available; use /gth plant <seed> [count]"); return end
  if not isShown() then setShown(true); rebuild() end
  soloPanel("plant")
  pick.seed = seed
  pickersOpen = false
  a = a or nearestArea()
  if a then pick.farmId = a.farmId; setPickArea(a)
  elseif not farmById[pick.farmId] then
    local last = areaById[prefs.areaId]
    local near = nearestFarm()
    if near and not (last and last.farmId == near.id) then pickFarm(near)
    elseif last then pick.farmId = last.farmId; setPickArea(last)
    else pickFarm(farmById[prefs.farmId] or farmChoices()[1]) end
  else
    setPickArea(pickArea())
  end
  plantOpen = true
  showEl(plantBox, true)
  updatePick()
  if lastSearch == nil then lastSearch = inputText(searchIn); fillSeeds(lastSearch) end
end
local function closePlant()
  plantOpen = false
  showEl(plantBox, false)
end
closePlantNow = closePlant
panelClosers.plant = closePlant

local function plantBoxSpec()
  searchIn = makeInput("gt_search", "Search seeds, e.g. rose")
  local kids = {
    sectionTitle("sprout", "", "gt_plant_head", GOLD),
    UI.Row{ style = { alignItems = "center", marginBottom = 6 }, children = {
      UI.Label{ id = "gt_plant_sub", text = "", style = { color = DIM, fontSize = 12, flexGrow = 1, whiteSpace = "wrap" } },
      UI.Button{ text = "Change", tooltip = "Pick a different farm or area",
        onClick = function() pickersOpen = not pickersOpen; updatePick() end },
    } },
    -- farm and area pickers, only when you ask for them (or nothing is picked yet)
    UI.Column{ id = "gt_pickers", visible = false, style = { marginBottom = 6 }, children = {
      UI.Row{ style = { alignItems = "center", marginBottom = 4 }, children = {
        UI.Label{ text = "Farm:", style = { color = DIM, width = 44 } },
        UI.Button{ text = "<", onClick = function() pickFarm(stepPick(farmChoices(), pick.farmId, -1)) end },
        UI.Button{ text = ">", style = { marginLeft = 2 }, onClick = function() pickFarm(stepPick(farmChoices(), pick.farmId, 1)) end },
        UI.Label{ id = "gt_pf", text = "", style = { color = GOLD, flexGrow = 1, marginLeft = 6, whiteSpace = "wrap" } },
        UI.Button{ text = "New farm", style = { marginLeft = 4 }, onClick = function() openFarmBox(nil) end },
      } },
      UI.Row{ style = { alignItems = "center" }, children = {
        UI.Label{ text = "Area:", style = { color = DIM, width = 44 } },
        UI.Button{ text = "<", onClick = function() setPickArea(stepPick(areaChoices(farmById[pick.farmId]), pick.areaId, -1)) end },
        UI.Button{ text = ">", style = { marginLeft = 2 }, onClick = function() setPickArea(stepPick(areaChoices(farmById[pick.farmId]), pick.areaId, 1)) end },
        UI.Label{ id = "gt_pa", text = "", style = { color = GREEN, flexGrow = 1, marginLeft = 6, whiteSpace = "wrap" } },
        UI.Button{ text = "New area", style = { marginLeft = 4 }, onClick = function()
          -- the area box replaces this panel; once the area is made, planting carries on in it
          openAreaBox(nil, farmById[pick.farmId], function(na) openPlant(pick.seed, na) end) end },
      } },
    } },
  }
  -- step 1: pick a seed
  local seedPick = {}
  if searchIn then seedPick[#seedPick + 1] = UI.Row{ style = { marginBottom = 4 }, children = { searchIn } } end
  seedPick[#seedPick + 1] = UI.Column{ id = "gt_seeds", style = { alignItems = "start" }, children = {} }
  kids[#kids + 1] = UI.Column{ id = "gt_seedpick", style = { marginBottom = 4 }, children = seedPick }
  -- the picked seed
  kids[#kids + 1] = UI.Row{ id = "gt_seedrow", visible = false, style = { alignItems = "center", marginBottom = 6, paddingTop = 4, paddingBottom = 4,
    paddingLeft = 6, backgroundColor = PANEL_SOFT, borderRadius = 6 }, children = pack(
    icon("sprout", 20),
    UI.Label{ id = "gt_pick", text = "", style = { color = PARCH, fontStyle = "bold", whiteSpace = "wrap", flexGrow = 1, marginLeft = 6 } },
    UI.Button{ text = "Change seed", onClick = function() pick.seed = nil; updatePick(); fillSeeds(lastSearch or "") end }) }
  -- step 2: where to plant it
  kids[#kids + 1] = UI.Column{ id = "gt_where", visible = false, style = { marginBottom = 4 }, children = {
    UI.Button{ id = "gt_pw_all", text = "Plant all empty beds", style = PRIMARY,
      tooltip = "One line for the whole area, watered and harvested together", onClick = function() plantPicked("all") end },
    UI.Column{ id = "gt_pw_numbered", style = { marginTop = 6 }, children = {
      UI.Label{ text = "or pick beds:", style = { color = DIM, marginBottom = 2 } },
      UI.Column{ id = "gt_pgrid", children = {} },
      UI.Button{ id = "gt_pw_sel", text = "Pick beds above", style = { marginTop = 4 }, onClick = function() plantPicked("selected") end },
    } },
    UI.Row{ id = "gt_pw_count", style = { alignItems = "center", marginTop = 6 }, children = {
      UI.Label{ text = "How many beds?", style = { color = DIM, marginRight = 6 } },
      UI.Button{ text = "-", onClick = function() pick.count = math.max(1, pick.count - 1); updatePick() end },
      UI.Label{ id = "gt_pc", text = "1", style = { color = GOLD, fontStyle = "bold", marginLeft = 8, marginRight = 8 } },
      UI.Button{ text = "+", onClick = function() pick.count = math.min(500, pick.count + 1); updatePick() end },
      UI.Button{ text = "+5", style = { marginLeft = 4 }, onClick = function() pick.count = math.min(500, pick.count + 5); updatePick() end },
      UI.Button{ text = "Plant", style = { marginLeft = 8, backgroundColor = PRIMARY.backgroundColor, color = PRIMARY.color },
        onClick = function() plantPicked("count") end },
    } },
    UI.Label{ id = "gt_pw_hint", text = "", style = { color = DIM, fontSize = 11, whiteSpace = "wrap", marginTop = 4 } },
  } }
  kids[#kids + 1] = UI.Row{ style = { alignItems = "center" }, children = {
    UI.Button{ text = "Close", onClick = closePlant },
  } }
  return UI.Column{ id = "gt_plant_box", visible = false, style = boxStyle(GREEN), children = kids }
end

---------------------------------------------------------------- sync from tooltip
local syncBox, syncQ, syncIn, syncTarget = nil, nil, nil, nil

local function closeSync()
  syncTarget = nil
  showEl(syncBox, false)
end
panelClosers.sync = closeSync
openSync = function(p)
  if not (syncBox and syncIn) then
    say("type the game's \"Next watering in\" time with /gth sync " .. label(p) .. " > 41m")
    return
  end
  soloPanel("sync")
  syncTarget = p
  setText(syncQ, "Sync " .. label(p) .. " (" .. shortName(p.seed) .. ", " .. where(p) .. ", " .. locLabel(p.location) ..
    "): hover the bed in game and type its \"Next watering in\" time, e.g. 41m or 2h 5m.")
  setText(syncIn, "")
  showEl(syncBox, true)
end
local function applySync()
  local p = syncTarget
  if not p then closeSync(); return end
  local secs = parseDuration(inputText(syncIn))
  if not secs or secs <= 0 then say("couldn't read that time; type it like 41m or 2h 5m"); return end
  closeSync()
  syncPlanter(p, secs)
end
local function syncBoxSpec()
  syncIn = makeInput("gt_sync_in", "Next watering in, e.g. 41m or 2h 5m")
  if not syncIn then return nil end
  return UI.Column{ id = "gt_sync_box", visible = false, style = boxStyle(BLUE), children = {
    sectionTitle("sync", "", "gt_sync_q", BLUE),
    UI.Row{ style = { marginBottom = 4 }, children = { syncIn } },
    UI.Row{ style = { alignItems = "center" }, children = {
      UI.Button{ text = "Set", style = PRIMARY, tooltip = "Move this bed's next window to open after that time", onClick = applySync },
      UI.Button{ text = "Cancel", style = { marginLeft = 6 }, onClick = closeSync },
    } },
  } }
end

---------------------------------------------------------------- window
setShown = function(on)
  if not win then return end
  if on then win:Show() else win:Hide() end
  prefs.open = on; save()
end
local function toggle()
  if not win then return end
  local shown = isShown()
  setShown(not shown)
  if not shown then rebuild() end
end

local function zoneOptions()
  local seen, out = {}, {}
  for _, f in ipairs(farms) do
    local k = key(f.zone)
    if k ~= "" and not seen[k] then seen[k] = true; out[#out + 1] = f.zone end
  end
  table.sort(out, function(a, c) return string.lower(a) < string.lower(c) end)
  table.insert(out, 1, "")
  return out
end
local function stepFilter(d)
  local opts = zoneOptions()
  local at = 1
  for i, z in ipairs(opts) do if key(z) == key(prefs.zoneFilter) then at = i end end
  prefs.zoneFilter = opts[(at - 1 + d) % #opts + 1]
  save(); rebuild()
end

-- "Going to Riverside Farm: 120 m NE" above the list while you're guided somewhere.
refreshTrack = function()
  local lbl = made.gt_track_lbl; if not lbl then return end
  if not goFarm then showEl(made.gt_track_row, false); return end
  showEl(made.gt_track_row, true)
  local d = distanceText(goFarm.zone, goFarm.x, goFarm.z)
  local t
  if key(goFarm.zone) ~= zoneKey then t = goFarm.name .. ": travel to " .. goFarm.zone
  elseif d == "here" then t = goFarm.name .. ": you're here!"
  else t = goFarm.name .. ": " .. (d or "?") end
  setText(lbl, t)
end

-- "You're in GH3 - Left" at the top while you stand near an area's spot.
local hereArea, hereText, hereSub = nil, nil, nil
local function refreshHere()
  local a = nearestArea()
  hereArea = a
  if not a then
    if hereText then hereText = nil; showEl(made.gt_here_row, false) end
    return
  end
  local f = farmById[a.farmId]
  local ps = plantersOf(a)
  local d = dueCount(ps, clock())
  local t = "You're in " .. a.name
  local sub = (f and (f.name .. ", ") or "") .. locLabel(a.type) .. ": " .. contents(a, ps) ..
    (d > 0 and (", " .. d .. " due") or "")
  if hereText == nil then showEl(made.gt_here_row, true) end
  if t ~= hereText then hereText = t; setText(made.gt_here_lbl, t) end
  if sub ~= hereSub then hereSub = sub; setText(made.gt_here_sub, sub) end
end

-- A summary tile: an icon and a big number over a small caption.
local function tile(id, caption, color, iconName)
  return UI.Column{ style = { flexGrow = 1, alignItems = "center", paddingTop = 6, paddingBottom = 6, marginRight = 6,
    backgroundColor = PANEL, borderRadius = 8, borderWidth = 1, borderColor = EDGE }, children = pack(
    UI.Row{ style = { alignItems = "center" }, children = pack(
      icon(iconName, 18),
      UI.Label{ id = id, text = "0", style = { color = color, fontSize = 22, fontStyle = "bold", marginLeft = 6 } }) },
    UI.Label{ text = caption, style = { color = DIM, fontSize = 11 } }) }
end

local function buildWindow()
  local children = {
    -- header: app icon, name and summary, main actions; underlined in gold
    UI.Row{ style = { alignItems = "center" }, children = pack(
      appImage(36),
      UI.Column{ style = { flexGrow = 1, alignItems = "start", marginLeft = 8 }, children = {
        UI.Label{ text = "Greenthumb", class = "title", style = { color = GOLD, fontSize = 20, fontStyle = "bold" } },
        UI.Label{ id = "gt_head", text = "", style = { color = DIM, fontSize = 12 } },
      } },
      icon("farm", 18),
      UI.Button{ text = "New farm", style = { marginLeft = 2 }, tooltip = "Save the spot you're standing on as a farm, then add its areas",
        onClick = function() openFarmBox(nil) end },
      icon("sprout", 18),
      UI.Button{ text = "Plant here", style = { marginLeft = 2, backgroundColor = PRIMARY.backgroundColor, color = PRIMARY.color },
        tooltip = "Pick farm, area, seed and count", onClick = function() if plantOpen then closePlant() else openPlant() end end }) },
    rule(GOLD, 2, 6, 8),
    -- summary tiles
    UI.Row{ style = { alignItems = "stretch", marginBottom = 8 }, children = {
      tile("gt_s_water", "Water now", BLUE, "water"),
      tile("gt_s_ready", "Ready", GREEN, "ready"),
      tile("gt_s_missed", "Missed", RED, "warn"),
      tile("gt_s_total", "Beds", PARCH, "sprout"),
    } },
    UI.Row{ id = "gt_track_row", visible = false,
      style = { alignItems = "center", marginBottom = 8, paddingTop = 6, paddingBottom = 6, paddingLeft = 8, paddingRight = 6,
        borderWidth = 1, borderColor = GOLD, borderRadius = 8, backgroundColor = PANEL }, children = pack(
        icon("pin", 22),
        UI.Label{ id = "gt_track_lbl", text = "", style = { flexGrow = 1, color = GOLD, fontSize = 15, fontStyle = "bold", whiteSpace = "wrap", marginLeft = 8 } },
        UI.Button{ text = "Stop", tooltip = "Stop guiding", onClick = function() guideTo(nil) end }) },
    UI.Row{ id = "gt_here_row", visible = false,
      style = { alignItems = "center", marginBottom = 8, paddingTop = 6, paddingBottom = 6, paddingLeft = 8, paddingRight = 6,
        borderWidth = 1, borderColor = GREEN, borderRadius = 8, backgroundColor = "#1E3A14CC" }, children = pack(
        icon("sprout", 26),
        UI.Column{ style = { flexGrow = 1, alignItems = "start", marginLeft = 8 }, children = {
          UI.Label{ id = "gt_here_lbl", text = "", style = { color = GREEN, fontSize = 16, fontStyle = "bold" } },
          UI.Label{ id = "gt_here_sub", text = "", style = { color = PARCH, fontSize = 11, whiteSpace = "wrap" } },
        } },
        UI.Button{ text = "Plant", style = { backgroundColor = PRIMARY.backgroundColor, color = PRIMARY.color },
          tooltip = "Plant in this area", onClick = function() if hereArea then openPlant(nil, hereArea) end end },
        UI.Button{ text = "Water all due", style = { marginLeft = 4 },
          onClick = function() if hereArea then waterAllDue(hereArea) end end }) },
  }
  children = compact(children)
  for _, spec in ipairs({ walkBoxSpec, farmBoxSpec, areaBoxSpec, plantBoxSpec, syncBoxSpec }) do
    local box = spec()
    if box then children[#children + 1] = box end
  end
  local function setOrder(v)
    prefs.sort = v
    if prefs.sort == "order" then say("areas in your order: use ^ and v on an area to move it") end
    save(); rebuild()
  end
  -- "Areas:" as a dropdown when the game has one, else a button that switches
  local orderPicker = try("Dropdown", { choices = { "Soonest first", "My order" },
    value = (prefs.sort == "order") and "My order" or "Soonest first", style = { width = 150 },
    tooltip = "How areas are listed inside each farm",
    onChange = function(_, v) setOrder((v == "My order") and "order" or "soonest") end })
  if not orderPicker then
    orderPicker = UI.Button{ id = "gt_order", text = (prefs.sort == "order") and "My order" or "Soonest first",
      tooltip = "Soonest first, or your own order (then ^ v move an area)",
      onClick = function()
        setOrder((prefs.sort == "order") and "soonest" or "order")
        setText(made.gt_order, (prefs.sort == "order") and "My order" or "Soonest first")
      end }
  end
  local rest = {
    -- section heading, underlined
    sectionTitle("farm", "Your farms"),
    rule(GOLD, 1, 4, 6),
    UI.Row{ style = { alignItems = "center", marginBottom = 4 }, children = {
      UI.Button{ text = "<", tooltip = "Previous zone", onClick = function() stepFilter(-1) end },
      UI.Label{ id = "gt_filter", text = filterLabel(), style = { color = BLUE, fontStyle = "bold", marginLeft = 6, marginRight = 6 } },
      UI.Button{ text = ">", tooltip = "Next zone", onClick = function() stepFilter(1) end },
      UI.Button{ text = "This zone", style = { marginLeft = 6 }, onClick = function() prefs.zoneFilter = zone or ""; save(); rebuild() end },
      UI.Label{ text = "", style = { flexGrow = 1 } },
      UI.Label{ text = "Areas:", style = { color = DIM, marginRight = 6 } },
      orderPicker,
    } },
    UI.Row{ style = { alignItems = "center", marginBottom = 6, paddingTop = 4, paddingBottom = 4, paddingLeft = 6,
      backgroundColor = PANEL_SOFT, borderRadius = 6 }, children = pack(
      icon("bell", 16),
      UI.Label{ text = "Alerts:", style = { color = DIM, marginLeft = 6, marginRight = 6 } },
      UI.Toggle{ id = "gt_t_open", text = "Window opens", value = prefs.aOpen,
        onChange = function(_, v) prefs.aOpen = (v == true); save() end },
      UI.Toggle{ id = "gt_t_close", text = "1 h left", value = prefs.aClose,
        onChange = function(_, v) prefs.aClose = (v == true); save() end },
      UI.Toggle{ id = "gt_t_ready", text = "Ready", value = prefs.aReady,
        onChange = function(_, v) prefs.aReady = (v == true); save() end }) },
    UI.Column{ id = "gt_list", style = { paddingRight = 10 }, children = {} },
    rule(EDGE, 1, 10, 4),
    UI.Label{ id = "gt_foot", text = "", class = "dim", style = { fontSize = 11, color = DIM, whiteSpace = "wrap" } },
  }
  for _, c in ipairs(compact(rest)) do children[#children + 1] = c end

  win = UI.Window{
    id = "greenthumb_main", title = "Greenthumb",
    width = prefs.w, height = prefs.h, minWidth = 300, minHeight = 240,
    x = prefs.x, y = prefs.y, resizable = true, escCloses = false,
    onClose = function() prefs.open = false; save() end,
    children = { UI.Scroll{ id = "gt_body", style = { flexGrow = 1 }, children = {
      UI.Column{ style = { paddingLeft = 10, paddingRight = 10, paddingTop = 6, paddingBottom = 8, backgroundColor = BODY, borderRadius = 6 },
        children = children } } } },
  }
  list = made.gt_list
  plantBox, plantHead, seedList, seedLbl = made.gt_plant_box, made.gt_plant_head, made.gt_seeds, made.gt_pick
  if not (plantBox and seedList) then plantBox = nil end
  syncBox, syncQ = made.gt_sync_box, made.gt_sync_q
  if not (syncBox and syncQ) then syncIn = nil end
  farmBox, farmHead = made.gt_farm_box, made.gt_fb_head
  areaBox, areaHead = made.gt_area_box, made.gt_ab_head
  walkBox = made.gt_walk_box
  if not prefs.open then win:Hide() end
end

local function refreshFoot()
  local t = "Planting counts as the first watering. Areas set the growth: Outside 1x, Greenhouse 2x, Inside 0.1x."
  if prefs.speed > 1 then t = t .. " Test speed x" .. prefs.speed .. " for new plantings (/gth speed 1 to stop)." end
  if not realClock then t = t .. " No real-time clock: timers only run while you're logged in." end
  setText(made.gt_foot, t)
end

---------------------------------------------------------------- commands
local function argText(...)
  local parts = {}
  for _, a in ipairs({ ... }) do
    if type(a) == "table" then
      if #a > 0 then
        for _, x in ipairs(a) do parts[#parts + 1] = tostring(x) end
      else
        -- a context table: take the typed text from whichever field holds it
        local t = a.args or a.text or a.raw or a.line or a.input or a.message
        if type(t) == "table" then for _, x in ipairs(t) do parts[#parts + 1] = tostring(x) end
        elseif t ~= nil then parts[#parts + 1] = tostring(t) end
      end
    elseif a ~= nil then parts[#parts + 1] = tostring(a) end
  end
  return table.concat(parts, " ")
end

-- Returns the seed, or nil and a list of close matches.
local function findSeed(q)
  local k = key(q)
  if k == "" then return nil, {} end
  if SEED_BY_KEY[k] then return SEED_BY_KEY[k] end
  local hits = {}
  for _, s in ipairs(SEEDS) do
    if key(shortName(s.name)) == k then return s end
    if seedMatches(s, q) then hits[#hits + 1] = s end
  end
  if #hits == 1 then return hits[1] end
  return nil, hits
end

local function findFarm(q)
  local k = key(q)
  if k == "" then return nil end
  for _, f in ipairs(farms) do if key(f.name) == k then return f end end
  for _, f in ipairs(farms) do if string.find(key(f.name), k, 1, true) then return f end end
  return nil
end

-- Nearest planter: by name (part of it), or in this zone when the name is empty.
local function nearestPlanter(name, test)
  local want = key(name)
  local best, bestD
  local px, _, pz = position()
  for _, p in ipairs(planters) do
    local ok
    -- match the name you see ("garlic bed 3" finds "Garlic – bed 3")
    if want ~= "" then ok = string.find(key(label(p)), want, 1, true) ~= nil
    else ok = key(p.zone) == zoneKey and (not test or test(p)) end
    if ok then
      local d = px and ((p.x - px) ^ 2 + (p.z - pz) ^ 2) or 0
      if not bestD or d < bestD then best, bestD = p, d end
    end
  end
  return best
end

local function listToChat(dueOnly)
  local t = clock()
  local n = 0
  for _, it in ipairs(items(true)) do
    if it.kind == "p" then
      local p = it.p
      local st = state(p, t)
      if not dueOnly or needsYou(st) then
        n = n + 1
        local m = missedText(p)
        say(where(p) .. " | " .. label(p) .. " | " .. shortName(p.seed) .. ", " .. locLabel(p.location) .. " | " ..
          (statusText(p, st)) .. (m ~= "" and (" | " .. m) or ""))
      end
    end
  end
  if n == 0 then say(dueOnly and "nothing needs you right now" or "no beds yet") end
end

local function command(...)
  local text = argText(...):gsub("^%s+", "")
  local verb, rest = text:match("^(%S+)%s*(.*)$")
  verb = verb and string.lower(verb) or ""
  rest = rest or ""
  if verb == "greenthumb" or verb == "gth" or verb == "gt" then
    verb, rest = rest:match("^(%S*)%s*(.*)$"); verb = string.lower(verb or ""); rest = rest or ""
  end
  if verb == "" or verb == "open" then toggle()
  elseif verb == "setup" then runSetup()
  elseif verb == "farm" then
    if clean(rest) == "" then openFarmBox(nil)
    else local nf = newFarm(rest, ""); if nf then startAddWalk(nf) end end
  elseif verb == "area" then
    local f = nearestFarm() or farmById[prefs.farmId]
    if not f then say("make a farm first: /gth farm <name>"); return end
    local typ
    local head, last = rest:match("^(.-)%s*(%S+)$")
    if last and locationName(last) then typ, rest = locationName(last), head end
    if clean(rest) == "" and not typ then openAreaBox(nil, f); return end
    newArea(f, rest, typ or prefs.loc)
  elseif verb == "plant" then
    local name
    local a, c = rest:match("^(.-)%s*>%s*(.*)$")
    if a then rest, name = a, c end
    local count = 1
    local head, n = rest:match("^(.-)%s+(%d+)$")
    if n then rest, count = head, tonumber(n) end
    if clean(rest) == "" then openPlant(); return end
    local seed, hits = findSeed(rest)
    if not seed then
      if hits and #hits > 1 then
        local names = {}
        for _, s in ipairs(hits) do names[#names + 1] = shortName(s.name) end
        say("which one? " .. table.concat(names, ", "))
      else say("no seed called " .. rest .. ". Open the window's Plant here list to browse them.") end
      return
    end
    local area = nearestArea() or areaById[pick.areaId] or areaById[prefs.areaId]
    if not area then say("pick a farm and area in the Plant here dialog first (or /gth farm, then /gth area)"); openPlant(seed); return end
    plant(area, seed, count, name or "")
  elseif verb == "water" then
    local here = nearestArea()
    if string.lower(clean(rest)) == "all" then
      if not here then say("you're not in an area (stand near its spot, or set one with Edit > Set area spot here)"); return end
      waterAllDue(here); return
    end
    local needs = function(x) return state(x, clock()).kind == "water" end
    local p
    -- standing in an area: its planters come first
    if here and clean(rest) == "" then
      for _, x in ipairs(plantersOf(here)) do if not p and needs(x) then p = x end end
    end
    p = p or nearestPlanter(rest, needs)
    if not p then say(clean(rest) ~= "" and ("no bed named " .. rest) or ("nothing in " .. (zone or "this zone") .. " needs water right now")); return end
    water(p)
  elseif verb == "sync" then
    -- /gth sync [name >] <time>: no name = the nearest planter in this zone
    local name, time = rest:match("^(.-)%s*>%s*(.*)$")
    if not name then name, time = "", rest end
    local secs = parseDuration(time)
    if not secs or secs <= 0 then say("usage: /gth sync [name >] <next watering in>, e.g. /gth sync 41m or /gth sync garlic bed 3 > 2h 5m"); return end
    local p = nearestPlanter(name)
    if not p then say(clean(name) ~= "" and ("no bed named " .. name) or ("no beds in " .. (zone or "this zone"))); return end
    syncPlanter(p, secs)
  elseif verb == "go" then
    if clean(rest) == "" then guideTo(nil); return end
    local f = findFarm(rest)
    if not f then say("no farm called " .. rest); return end
    if goFarm ~= f then guideTo(f) end
  elseif verb == "list" then listToChat(false)
  elseif verb == "due" then listToChat(true)
  elseif verb == "speed" then
    local n = tonumber(rest)
    if string.lower(rest) == "off" then n = 1 end
    if not n then say("test speed is x" .. prefs.speed .. ". /gth speed 60 makes new plantings grow 60 times faster (hours become minutes); /gth speed 1 stops it."); return end
    prefs.speed = math.max(1, math.min(3600, math.floor(n)))
    save(); refreshFoot(); updatePick()
    say(prefs.speed > 1 and ("test speed x" .. prefs.speed .. ": beds you plant from now on grow " .. prefs.speed .. " times faster. Existing beds keep their speed.")
      or "test speed off; new plantings use real time")
  else
    say("commands: /greenthumb, /gth setup, /gth farm <name>, /gth area <name> [outside|greenhouse|inside], /gth plant <seed> [count] [> name], " ..
      "/gth water [name|all], /gth sync [name >] <time>, /gth go [farm], /gth list, /gth due, /gth speed <n>")
  end
end

-- Slash commands are registered with a table (the form Crafters Ledger uses);
-- the older Shroud.Command(name, fn) form is only tried if that's rejected.
local function registerCommand(name, help)
  if not (Shroud and Shroud.Command) then return false, "commands unavailable" end
  local run = function(...) command(...) end
  local ok, registered, why = pcall(function() return Shroud.Command{ name = name, help = help, run = run } end)
  if ok and registered ~= false then return true end
  local ok2, reg2 = pcall(Shroud.Command, name, run)
  if ok2 and reg2 ~= false then return true end
  return false, (ok and (why or "rejected")) or registered
end

---------------------------------------------------------------- launcher icon
local launcher = nil
local function texture(file)
  if type(ShroudLoadTexture) ~= "function" then return -1 end
  for _, p in ipairs({ "greenthumb/" .. file, file }) do
    local ok, id = pcall(ShroudLoadTexture, p)
    if ok and type(id) == "number" and id >= 0 then return id end
  end
  return -1
end

-- The plant icon on screen: click it to show / hide the window (drag it where you like).
local function buildLauncher()
  local tex = texture("icon.png")
  if not hasUI("HudFrame") or not hasUI("IconButton") or tex < 0 then return false end
  local ok, f = pcall(UI.HudFrame, { id = "gt_launcher", x = prefs.lx, y = prefs.ly,
    width = 40, height = 40, children = {
      UI.IconButton{ id = "gt_icon", texture = tex, onClick = toggle,
        tooltip = "Greenthumb: show / hide", style = { width = 40, height = 40 } },
    } })
  if ok then launcher = f; return true end
  say("couldn't make the plant icon: " .. tostring(f)); return false
end

---------------------------------------------------------------- callbacks
function ShroudOnStart()
  pcall(function() math.randomseed(clock()) end)
  zone = sceneName(); zoneKey = key(zone)
  load()
  if key(prefs.zoneFilter) ~= "" then
    local found = false
    for _, f in ipairs(farms) do if key(f.zone) == key(prefs.zoneFilter) then found = true end end
    if not found then prefs.zoneFilter = "" end
  end

  tex.icons, tex.app = texture("icons.png"), texture("icon.png")
  local ok, err = pcall(buildWindow)
  if not ok then say("couldn't build the window: " .. tostring(err)) end
  pcall(buildNotice)
  local okL, hasIcon = pcall(buildLauncher)
  pcall(startCatchUp)
  pcall(refreshFoot)
  pcall(writeTsv)
  rebuild()

  -- /gt is taken by the game (it wants a character name), so the short form is /gth.
  local regOk, regWhy = registerCommand("greenthumb", "Greenthumb: /greenthumb setup, plant, water, sync, go, list, due, speed")
  registerCommand("gth", "Greenthumb (short for /greenthumb)")
  if not regOk then say("couldn't register /greenthumb (" .. tostring(regWhy) .. "); use the plant icon or a key from Add-Ons") end
  -- No default key: the game rejects add-on keybinds that claim one. Set it in Add-Ons.
  if Shroud.Keybind then
    pcall(Shroud.Keybind, { id = "toggle", label = "Show/hide Greenthumb", onPress = toggle })
  end
  say("v" .. VERSION .. " ready. " .. plural(#farms, "farm") .. ", " .. plural(countOf(planters), "bed") ..
    " saved. Open with " .. ((okL and hasIcon) and "the plant icon, " or "") .. "/greenthumb, or set a key in Add-Ons.")
  if not realClock then say("the game didn't give a real-time clock; timers only run while you're logged in") end
end

local function update()
  if mapDirty and now() >= mapRetryAt then mapDirty = false; local ok = pcall(syncMap); if not ok then mapRetryAt = now() + 12 end end
  if wantRebuild and now() - lastBuild >= 0.5 and (isShown() or not win) then pcall(startBuild) end
  if seedJobs and #seedJobs > 0 then
    for _ = 1, ROWS_PER_FRAME do
      local job = table.remove(seedJobs, 1); if not job then break end
      local ok, err = pcall(job); if not ok then seedJobs = nil; say("couldn't list the seeds: " .. tostring(err)); break end
    end
  end
  if #uiJobs > 0 then
    for _ = 1, ROWS_PER_FRAME do
      local job = table.remove(uiJobs, 1); if not job then break end
      local ok, err = pcall(job); if not ok then uiJobs = {}; say("couldn't finish the panel: " .. tostring(err)); break end
    end
  end
  if pending then
    local ok, err = pcall(buildSome)
    if not ok then pending = nil; say("couldn't finish the list: " .. tostring(err)) end
  end
  if catchUp and now() >= catchUpAt then
    local c = catchUp; catchUp = nil
    for _, l in ipairs(c.lines) do say(l) end
    if c.notice then showNotice(c.notice) end
  end
  if noticeUntil > 0 and now() >= noticeUntil then hideNotice() end

  local dt = tonumber(ShroudDeltaTime) or 0
  tick = tick + dt
  if tick >= 1 then
    tick = 0
    local z = sceneName()
    if z ~= zone then
      zone, zoneKey = z, key(z)
      if plantOpen then updatePick() end
      -- a new scene drops the beacon; the pin is placed again (or removed) by syncMap
      beaconOn, beaconFor, mapDirty = false, nil, true
      updateBeacon()
    end
    checkAlerts()
    refreshTrack()
    refreshHere()
    if isShown() then refreshRows() end
    if farmDelAt > 0 and now() - farmDelAt >= 3 then farmDelAt = 0; setText(made.gt_fb_del, "Delete") end
    if areaDelAt > 0 and now() - areaDelAt >= 3 then areaDelAt = 0; setText(made.gt_ab_del, "Delete") end
  end
  searchTick = searchTick + dt
  -- area box: a new bed count rebuilds the per-bed grid
  if areaOpen and abCountIn and searchTick >= 0.5 then
    local c = tonumber((inputText(abCountIn):match("%d+")) or "")
    if c ~= ab.lastCount then
      ab.lastCount = c
      ab.count = c and math.max(0, math.min(500, c)) or nil
      buildBedGrid()
    end
  end
  if plantOpen and searchIn and searchTick >= 0.5 then
    searchTick = 0
    local q = inputText(searchIn)
    if q ~= lastSearch then lastSearch = q; fillSeeds(q) end
  end
  posTick = posTick + dt
  if posTick >= 3 and win then
    posTick = 0
    pcall(function()
      local changed = false
      local x, y = win:GetPosition()
      local w, h = win:GetSize()
      -- the game can report 0,0 before a window is laid out; ignore that
      if x and y and (x ~= 0 or y ~= 0) and (math.floor(x) ~= math.floor(prefs.x) or math.floor(y) ~= math.floor(prefs.y)) then
        prefs.x, prefs.y, changed = x, y, true
      end
      if w and h and w > 50 and h > 50 and (math.floor(w) ~= math.floor(prefs.w) or math.floor(h) ~= math.floor(prefs.h)) then
        prefs.w, prefs.h, changed = w, h, true
      end
      if notice then
        local nx, ny = notice:GetPosition()
        if nx and ny and (nx ~= 0 or ny ~= 0) and (math.floor(nx) ~= math.floor(prefs.nx) or math.floor(ny) ~= math.floor(prefs.ny)) then
          prefs.nx, prefs.ny, changed = nx, ny, true
        end
      end
      if launcher then
        local lx, ly = launcher:GetPosition()
        if lx and ly and (lx ~= 0 or ly ~= 0) and (math.floor(lx) ~= math.floor(prefs.lx) or math.floor(ly) ~= math.floor(prefs.ly)) then
          prefs.lx, prefs.ly, changed = lx, ly, true
        end
      end
      if changed then save() end
    end)
  end
end

local reported = {}
function ShroudOnUpdate()
  local ok, err = pcall(update)
  if not ok then
    local msg = tostring(err)
    if not reported[msg] then reported[msg] = true; say("problem (reported once): " .. msg) end
  end
end

-- If you clear the beacon in the game (or another add-on replaces it), stop guiding.
function ShroudOnBeaconCleared()
  if beaconOn then beaconOn, beaconFor = false, nil; goFarm = nil; mapDirty = true; refreshTrack(); rebuild() end
end
function ShroudOnBeaconSet(x, y, z)
  if beaconFor and (math.abs((x or 0) - beaconFor.x) > .05 or math.abs((z or 0) - beaconFor.z) > .05) then
    beaconOn, beaconFor = false, nil
  end
end
function ShroudOnBeaconArrived()
  if goFarm then say("you reached " .. goFarm.name) end
end

function ShroudOnDisableScript()
  save()
  hideNotice()
  if beaconOn then pcall(ShroudClearBeacon) end
  if mapPlaced then pcall(ShroudRemoveMapMarker, MARKER) end
end
