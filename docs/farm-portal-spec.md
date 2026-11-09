# Guild Farm Portal — build spec for rampage.truechaos.com + Greenthumb

Owner / designer: **Kronic** (site title **Architect**). Commit as Kronic (folder identity).
Repos: `rampage-site` (website, Cloudflare Pages project `rampage-guild`), `E:\dev\sota\addons\greenthumb`
(add-on), `E:\dev\sota\addons\lodestone` (holds the Lodestone Sync program in `sync/`).
Build in phases. Finish, test and commit each phase before starting the next.

---------------------------------------------------------------------------------------------------
## 1. Goal

The guild's farms live on the website. Members sign in, see one shared, accurate picture of every
farm, area and bed, record plantings and waterings from a phone or from the game, and get email
(texts later) when beds need water. Officers configure everything (farms, areas, beds, seeds,
timings, wording, ranks) from the site with no code changes. The website is the single source of
truth; the Greenthumb add-on and every browser show the same data.

Easy to use: phone-first layouts, big buttons, one tap per action, plain language, every time
shown in the viewer's own time zone (default America/Chicago).

---------------------------------------------------------------------------------------------------
## 2. Decisions already made

- Farms are **Guild** by default (every Guildsman can see; only listed people can work). **Private**
  only when someone selects it (only listed people can see). People are added to a farm when they
  need or want to help.
- Members CAN mark beds watered from the website (honor system). The activity log shows the source
  (game or web) and who.
- Build the guild farm first; personal farms use the same system.
- Alerts: email first via Resend; texts (SMS) later. Each farm chooses who gets each alert type —
  one person or many (named members, a farm role, or a rank).
- Starting people: **Kronic = Architect**; **Bain Rampage = Lord**; **Arcuss Blackwing = Lord**.
  Bain, Arcuss and Kronic lead the guild as equals.
- Rename the guild leader **"Zain Rampage" → "Bain Rampage"** everywhere in code/content defaults
  (initial Z → B). The live roster is renamed by hand in the Guild Back End.

---------------------------------------------------------------------------------------------------
## 3. Ranks (site-wide) — replace guest/member/editor/admin

Ranks are bundles of permissions stored as editable data (Architect and Lords can rename ranks,
change their permissions, or add ranks from the Guild Back End). Keep the existing role values
working by mapping them:

| Rank        | Old role | Default permissions |
|-------------|----------|---------------------|
| Traveler    | guest    | public pages only |
| Guildsman   | member   | farm.create (own farms), alerts.self, plus whatever farm roles grant |
| Scribe      | (new)    | Guildsman + words.edit |
| Steward     | editor   | Guildsman + seeds.edit (+ existing editor powers on site content) |
| Knight      | (new)    | Steward + Scribe + members.manage, alerts.channels, synckeys.manage |
| Lord / Lady | admin    | everything incl. ranks.manage, except site settings and the Architect |
| Architect   | owner    | superadmin: everything incl. site settings and other admins; outside the guild's ranks; cannot be demoted, removed or edited by anyone else |

The Architect is the existing site "owner" flag. Ranks are ordered for "at least" checks:
Traveler < Guildsman < Scribe < Steward < Knight < Lord < Architect (Scribe and Steward are
siblings in practice; use permissions, not order, for their features).

## 4. Farm roles (per farm)

| Farm role | Permissions on that farm |
|-----------|--------------------------|
| Landowner | farm.view, farm.tend, farm.claim, farm.setup, farm.people, farm.own |
| Overseer  | farm.view, farm.tend, farm.claim, farm.setup |
| Farmhand  | farm.view, farm.tend, farm.claim |
| Watchman  | farm.view (+ receives alerts) |

A new farm: visibility Guild, creator = Landowner. Lords and the Architect can act on any farm.

## 5. Permissions

farm.view, farm.tend (plant/water/harvest), farm.claim (claim/release watering windows),
farm.setup (areas, beds, bed types, order), farm.people (add/remove people, set farm roles),
farm.own (privacy, rename, delete), farm.create, seeds.edit (seeds, grow times, yields,
multipliers, bed types guild-wide), words.edit (page text, seed notes, alert wording),
members.manage (invites, member ranks), synckeys.manage (any member's keys), alerts.channels
(email/SMS provider settings), alerts.self (own alert settings), ranks.manage (ranks, farm roles,
their permissions), site.settings (Architect only).

**Every API call checks permissions on the server**, whether it comes from a browser session or a
game sync key. A Farmhand's sync key can water but cannot change a farm's beds.

---------------------------------------------------------------------------------------------------
## 6. Data (Cloudflare D1)

Add a D1 database (binding `FARM`) to the Pages project. Users, sessions and site content stay in
KV (`GUILD`) as today; ranks config is a KV doc (`ranks`) editable from the Back End.

Tables (SQL migrations in `migrations/`):

- `farms(id, name, zone, x, y, z, notes, visibility['guild'|'private'], created_by, created_at, updated_at)`
- `farm_members(farm_id, user_id, role['landowner'|'overseer'|'farmhand'|'watchman'], added_by, added_at)`
- `areas(id, farm_id, name, type['outside'|'greenhouse'|'inside'], x, y, z, sort, bed_mode['numbered'|'count'], bed_count, default_bed_type, updated_at)`
- `beds(id, area_id, number, bed_type)`
- `bed_types(id, name, builtin)`  — Large/Medium/Small Planting Bed, Planting Barrel, Planting Pot + custom
- `seeds(id, name, speed['quick'|'medium'|'slow'], base_hours, avg_yield, price, notes, active)`
- `growth_types(type, multiplier, label)` — outside 1.0 "1x growth", greenhouse 2.0 "2x growth", inside 0.1 "0.1x growth"
- `timing_corrections(seed_id, area_type, offset_seconds, set_by, set_at)` — from "Sync from tooltip"
- `plantings(id, area_id, seed_id, beds_json, count, planted_at, planted_by, source['game'|'web'], harvested_at, status)`
- `waterings(id, planting_id, window_index, watered_at, watered_by, source, counted[0|1])`
- `claims(id, planting_id|area_id, window_index, user_id, claimed_at, released_at)`
- `alert_rules(farm_id, alert_type, recipients_json)`  — recipients: user ids, farm roles, ranks
- `alert_prefs(user_id, email, email_on, sms_number, sms_on, quiet_start, quiet_end, tz, digest_on)`
- `alerts_sent(key, sent_at)` — dedupe key `<planting>:<window>:<type>:<user>`
- `events(id, client_event_id UNIQUE, user_id, source, type, payload_json, at, applied_at)` — every change; idempotent
- `characters(user_id, character_name)` — links in-game names (Kronic) to site accounts

Seed `seeds` with the 27 SotA Lore seeds (see Greenthumb SPEC.md / seed table) and `growth_types`.

**Timing math (server is the authority):** T = base_hours / multiplier (outside 24h, greenhouse
12h, inside 240h for Quick). Planting counts as water 1. Window k (1..3) runs from (k-1)·T/3 to
k·T/3, plus any timing correction offset. Harvest at T. A window that closes with no counted
watering = missed. The earliest real watering of a window counts; later ones are logged only.

---------------------------------------------------------------------------------------------------
## 7. Pages (phone-first)

| Page | Who | What |
|------|-----|------|
| `/farm` Today | Guildsman+ | Summary tiles (Water now, Ready, Missed, Beds); Water now / due in 24h / ready lists; who claimed what; one-tap **Watered** per planting and **Water all due** per area |
| `/farm/<farm>` Farm map | farm.view | Farm → areas in order → bed grid colored by state (blue growing, yellow water now, red closing/missed, green ready); tap a bed for crop, timer, history |
| Plant | farm.tend | Pick farm → area (remembered) → seed **dropdown** showing real time for that area ("Garlic – 12h, 16 crops, 8g") → beds (all empty / pick numbers / count) |
| Watering run | farm.tend | Checklist in area order; tick each as watered |
| Schedule & claims | farm.claim | 3-day timeline of windows; claim/release ("I'll do GH3 tonight") |
| My alerts | alerts.self | Email on/off, (SMS later), alert types, farms/areas followed, quiet hours, time zone, daily digest, Send test alert |
| Activity | farm.view | Who planted/watered/harvested/changed what, when, from game or web |
| Farm setup | farm.setup | Farm details, privacy (farm.own), people + farm roles (farm.people), areas, beds, bed types, order, alert recipients per alert type |
| Back End → Greenthumb tab | seeds.edit / words.edit | Seeds, grow times, yields, prices, multipliers, bed types, alert wording, portal page text |
| Back End → Ranks | ranks.manage | Rename ranks/farm roles, tick permissions, add ranks; assign member ranks (members.manage) |
| Profile → Game sync | Guildsman+ | Make/revoke own sync key; link characters |

All visible wording uses the site's existing editable-text system so Scribes can change it.
Pages refresh every 15 s and after every action; show "Synced 8 s ago".

---------------------------------------------------------------------------------------------------
## 8. API (Pages worker)

Browser (session cookie) and game (Bearer sync key) use the same endpoints; both resolve to a user,
then permissions are checked.

- `GET /api/farm/state?since=<rev>` — farms/areas/beds/plantings/claims/seeds the user can see, plus server time; `since` returns only changes
- `POST /api/farm/events` — body `{events:[{client_event_id, type, at, ...}]}`; types: plant, water, water_area, harvest, split, claim, release, sync_offset; idempotent by client_event_id; returns applied/rejected per event + new rev
- `POST /api/farm/setup/*` — farms, areas, beds, people, privacy, alert rules (permission-checked)
- `GET/POST /api/farm/alerts/me`, `POST /api/farm/alerts/test`
- `GET/POST /api/admin/seeds`, `/api/admin/ranks`, `/api/admin/bed-types`
- Sync keys: every member can create/revoke their own under Profile → Game sync (prefix `gth_`
  or reuse `lds_`); store only SHA-256 hash → `{user_id, name, at, used}`; show once. Knights+
  can revoke anyone's. Existing Lodestone keys keep working and now resolve to their user.

---------------------------------------------------------------------------------------------------
## 9. Alerts

- Separate Cloudflare **Worker** `greenthumb-cron` (Pages can't run cron) bound to the same D1 and
  KV, cron every 5 minutes.
- Each run: find windows that just opened, close within 1 h, closing within 1 h with no watering
  or claim (escalation), and crops ready; resolve recipients from `alert_rules` (defaults below)
  and each recipient's `alert_prefs`; respect quiet hours (escalation ignores quiet hours); dedupe
  via `alerts_sent`; group into one email per person per run.
- Defaults: window opens → claimer, else all Farmhands; 1 h left → claimer + Overseer;
  escalation → everyone on the farm; ready → Landowner + Overseer; daily digest → opted-in.
- Email via **Resend** API (`RESEND_API_KEY` secret on the Worker and Pages), from
  `Greenthumb <alerts@mail.truechaos.com>`; Kronic's own alerts go to `greenthumb@truechaos.com`.
  Subject e.g. "GH2 at Kronic's Farm: 6 Garlic need water (closes 9:40 pm)". Include a link to /farm.
- SMS later (Twilio); keep a channel abstraction so it's a drop-in.

---------------------------------------------------------------------------------------------------
## 10. Game sync (Greenthumb + Lodestone Sync program)

- Greenthumb writes every action as an event to `greenthumb-outbox.tsv` in the Lua folder
  (client_event_id, type, at (os.time), farm/area/planting ids, beds, seed, offset).
- The Lodestone Sync program (one program for both add-ons, one key per member) sends the outbox
  to `POST /api/farm/events` every ~10 s, then truncates what was accepted; pulls
  `GET /api/farm/state?since=` every 10–15 s and writes `greenthumb-state.tsv`; also measures the
  PC clock offset vs server time and writes it into the state file.
- Greenthumb reads the state file when it changes and shows the server's data (other members'
  actions included); its own unsent actions show as "local" until accepted. Shows
  "Synced 8 s ago" (red if > 2 min). Setup changes made in game are sent as events and
  permission-checked.
- Offline: actions queue in the outbox and go up when the program is running again.
- Migration: on first sync, Greenthumb's local farms/areas/plantings (from 0.2.x) are offered to
  upload into the site (Landowner = the key's user); after that the site is the source.

---------------------------------------------------------------------------------------------------
## 11. Phases (do one at a time)

0. **Rename + ranks.** Zain → Bain in code defaults. Rank system (Section 3) with mapping from old
   roles; permissions helper (`can(user, perm, farm?)`); Back End → Ranks page; Architect locked.
1. **D1 + Farm setup.** Binding, migrations, seed data; Farm setup page (farms, privacy, people,
   areas, beds, bed types, order); farm roles enforced.
2. **Daily use.** Today, Farm map, Plant (seed dropdown with real times), Watering run, claims,
   Activity; events endpoint used by the browser; 15 s refresh.
3. **Game sync.** Sync keys per member + character links; state/events endpoints for keys;
   Lodestone Sync program extended; Greenthumb outbox/state files + migration upload.
4. **Alerts.** greenthumb-cron Worker, Resend email, My alerts, per-farm recipients, escalation,
   digest, test alert.
5. **Admin content.** Back End → Greenthumb tab (seeds, timings, multipliers, bed types, alert
   wording, page text).

Each phase: update README, add tests where the repo has them, run locally
(`wrangler pages dev`), show Kronic before deploying (he reviews before anything goes live),
commit as Kronic, push only when he says.

## 12. Constraints

- Never commit secrets (Resend key, session key); use Wrangler/Cloudflare secrets.
- Keep the existing KV content, users and Lodestone sync working throughout.
- Don't show real names anywhere public; credit add-ons to Kronic.
- Add-on code: follow Greenthumb/Lodestone lessons (pcall UI probes, throttled row building, no
  default keybind, plain ASCII in game-visible text).
- Ask before creating new Cloudflare resources (D1 database, Worker, DNS) — Kronic creates or
  approves them.
