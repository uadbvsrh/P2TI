# Changelog

## 0.53.0 (Houston sells insurance)

The user: "add dialogue with houston for insurance".

- **`lua/armory_insurance.lua`:** `Insurance.Weapons()` (the insurable weapons dearest first,
  then by name; the insured by name; each `{ container, instance_id, data, price }`);
  `Insurance.InsureAll()` (at home, all or nothing: one `Armory.Take` of the sum, a policy
  each, one save); the policy writing shared as `add_policy` with `Insure`.
- **`lua/safehouse.lua`:** Houston's room (`american`, action `insurance`): "Insured: ..." or
  "None of your weapons is insured.", the weapons coming back (`ReturnLines`), "Not insured: ...
  (the 5 dearest, "and N more"). Lost, an insured weapon is back in your locker <delay> after the
  heist.", **Insure all ($X)** and up to `Home.REPAIR_BUTTONS` (5) **Insure the X ($Y)**; the
  result as a hint. Nothing with the armory off.
- **Tests:** `insurance_tests.lua` +24 (106). 3786 checks. Mutation check: 70 mutants, 2
  survive (a log line, a name tie-break).

Defaults for the user to review: the weapon view's price and Duke's discounts apply; Insure all
is all or nothing; at most 5 weapon buttons, dearest first; no Cancel in Houston's menu (the
weapon view has it).

## 0.52.0 (the medic bag at $35,000)

The user: "make price for medic bag 35k".

- **`lua/ammo.lua`:** `Ammo.PRICES.item.doctor_bag` 35000 (was 12000). The bring list, its
  refunds and the heist's restock all read it.
- **Tests:** `bag_price_tests.lua` +1. 3762 checks.

## 0.51.0 (the locker scrolls, 12x20)

The user: "make locker scrollable". Answer: "12x20, show 8 rows".

- **`lua/inventory.lua`:** `PDTI.LOCKER` 12x20 (was 12x10). Saved items keep their cells.
- **`lua/ui_beardlib.lua`:**
  - `draw_grid(win, container, x, y, model, first_row, rows)`: only those rows, the first at
    `y` (other grids unchanged).
  - `LOCKER_VIEW` 8, `LOCKER_STEP` 2; `PDTI.UILockerScroll(delta)` keeps `view.locker_top` in
    bounds and returns top, rows, total.
  - The Locker tab: **Up** / **Down** buttons and "Rows a-b of 20 (the mouse wheel scrolls)".
  - `wheel_dir(button)` (`Idstring("mouse wheel up/down")`); in `_UIMousePressed` the wheel
    over a locker cell scrolls, redraws, draws the drag preview again while dragging, and takes
    the press; anywhere else it is left to the game.
- **Tests:** `ui_tests.lua` +11 (223); `parts_tests.lua` fills the bigger locker. 3761 checks.
  Mutation check: 36 mutants of the new lines, none survive (the redundant wheel guards and a
  "changed?" check were removed).

Defaults for the user to review: 8 rows shown, 2 rows per wheel step; the scroll position is
kept while the screen is open and across redraws; a weapon sent to the locker with Ctrl+click
lands in the first free cell, which may be out of view (the screen does not scroll to it).

## 0.50.0 (Rust repairs your weapons)

The user: "i've changed my mind on ledger, but add dialogue option with rust for repairs". The
heist ledger is dropped.

- **`lua/armory_wear.lua`:** `Wear.Worn()` (your weapons under 100%, not free, as
  `{ container, instance_id, data, cond, price }`, worst first, then by name);
  `Wear.RepairAll()` (at home, all or nothing: one `Armory.Take` of the sum, then `cond = 100`
  on each through one `PDTI.EditItems`; "Repaired N weapon(s) for $X: 100%").
- **`lua/safehouse.lua`:** Rust's room (`wild`, action `repair`): a "Worn: ..." line (the 5
  most worn named, "and N more"), **Repair all ($X)** and up to `Home.REPAIR_BUTTONS` (5)
  **Repair the X, N% ($Y)** buttons (`Wear.Repair`); nothing worn: "Your weapons are in full
  condition."; the result as a hint. Not shown with the armory off.
- No clearing of heist wear on repair was needed: the menu's `Wear.Apply(true)` empties the
  heist values before you are at home.
- **Tests:** `wear_tests.lua` +19 (119). 3750 checks. Mutation check: 50 mutants of the new
  lines, none survive.

Defaults for the user to review: the weapon view's price (20% of the built price from 0%), no
discount from Rust's tier; Repair all is all or nothing; at most 5 weapon buttons; insured
weapons waiting to come back are not listed (not items yet).

## 0.49.0 (weapon skins, through Sydney)

The user: "start working on skins, add dialogue with sydney to change the skins for weapons".
Plan answers: a skin list (now Sydney's screen, the weapon view shows the skin); "Any number of
guns"; legendary fixed parts "Free, gun locked"; StatBoost "Yes, as in game".

- **New `lua/armory_skins.lua` (`PDTI.WeaponSkins`):**
  - Item data: `skin_id`, `skin_iid`, `skin_quality`, `skin_bonus`, `skin_color` (cleared to
    false).
  - `Owned(weapon_id)`: `get_inventory_tradable()` entries of category `weapon_skins` that
    `weapon_cosmetics_type_check` allows, one per skin (StatBoost first, then quality
    mint > fine > general > worn > poor); plus `is_a_unlockable` / `is_a_color_skin` skins the
    game has (`has_item(global_value, "weapon_skins", id)`, the DLC unlocked). Colours get
    `color = 1`. Sorted by name.
  - `Apply(c, iid, skin_id)` / `Remove(c, iid)`: at home, an owned skin. A legendary skin
    (`default_blueprint`) replaces the build; your buyable parts go through `Parts.PlaceOff`
    (all or none). Removing one gives `DefaultBlueprint` plus the parts fitted beside it.
    A build change goes through `Parts.SetBuild` (weight, insurance, plan, hands); otherwise
    `SyncEquipped` + `ApplyHands` for a gun in hand.
  - `LockReason(d)`: a `locked` skin refuses `Parts.CanFit` and `Parts.ApplyBuild`.
  - `Sweep()` at the menu (`Armory.OnMenu`, after insurance): a skin whose copy is no longer
    in the tradable list (or colour no longer unlocked) comes off. Nothing without a Steam
    inventory.
- **`lua/armory.lua`:** `Armory.Cosmetics(d)` (`{id, instance_id, quality, bonus,
  color_index, pattern_scale = weapon_color_pattern_scale_default}`), `Armory.BuildKey(d)`
  (blueprint + skin: the unit tag, so a skin change remakes the gun in hand); `put_in` passes
  cosmetics; `Build` carries `cosmetics`, `customize_locked` and `locked_name`; `same_build`
  compares the cosmetics; `BuildPrice` leaves out the skin's own parts; the file keeps the skin
  fields of captured weapons and returns (a StatBoost only when true).
- **`lua/armory_parts.lua`:** `Parts.PlaceOff` exported; `SellPrice` leaves out the skin's own
  parts; the lock in `CanFit` and `ApplyBuild`.
- **`lua/armory_insurance.lua`:** `Claim` copies the skin fields.
- **`lua/safehouse.lua`:** Sydney's room (`sydney`, action `skins`): **Weapon skins** opens
  `PDTI.OpenSkins()`.
- **`lua/ui_beardlib.lua`:** `view.skins_mode`: the centre window alone (`draw_skins`): your
  weapons (hands first, 9 a page), a weapon's skins (on it marked), Remove, Back, the status,
  Close. The weapon view's "Skin: ..." line.
- **Tests:** new `skins_tests.lua` 83. 3731 checks. Mutation check: 334 mutants of the new and
  changed lines, survivors fixed with tests; what remains is the file guard, the log, display
  guards, the layout's `y` steps, sort tie-breaks and resets on close (plus unrelated locker
  lines the pattern matched).

Defaults for the user to review: Sydney's screen at any room tier, free of charge; your best
copy is picked for you (no choosing between copies); a colour uses its first colour and the
default pattern; a plain skin change keeps insurance, a legendary one (a build change) ends it
and pays it back; market and free weapons come without a skin but can wear one; skins change
only at home.

## 0.48.0 (lasting body damage, Dallas's heal)

The user: "make that damaged body parts would stay with the player even after the end of the
heist, and add option in dialogue with dallas in which you can heal everything for 15000".
Answers: no free heal between heists; black parts stay black; ended in custody "all parts at 0
hp, only head is at 1 hp"; "$15,000, also menu"; "yes".

- **New `lua/body_lasting.lua` (`PDTI.BodyLasting`):**
  - The file `pdti_save_body_profile<n>.json` (`PDTI.SaveFileName("body")`, else
    `pdti_body.json` / `pdti_body_profile<n>.json`): `{ frac = { part = 0..1 }, in_heist }`,
    clamped, nonsense full. Written at once (not the inventory).
  - `OnLevelStart` (`heist_start.lua`, after `Body.OnHeistStart`, and for the safehouse before
    its early return) sets `Body.start_frac` from the file and marks a heist `in_heist`.
  - `OnMissionEnd` (`stash.lua`'s end-screen hook): no player unit (custody), a downed state
    (`bleed_out`, `fatal`, `incapacitated`, `arrested`) or a black head: every part 0 and the head
    `EFFECTS.revive_head` (1 HP); otherwise `Body.state.frac`. Not in the safehouse.
  - `OnMenu` (`safehouse.lua`'s menu hook, after the armory): a heist still marked (left, quit)
    ends down; then `Body.ShowParts` (the screen's parts, no owner).
  - `HealAll`: at home only, hurt only, `PRICE` 15,000 from `managers.money`, every part 1,
    saved; in the safehouse `Body.FullHeal` (the game's health too).
- **`lua/body.lua`:** `reset_start` uses `Body.start_frac` once (Frenzy's start-black still
  applies); `attach` lifts a carried head to the revive value; `Body.FullHeal`,
  `Body.ShowParts` (not with a live owner), `Body.push_health` exported.
- **`lua/safehouse.lua`:** Dallas's room (`russian`, action `heal`): "Hurt: ..." line and
  **Heal everything ($15,000)** when hurt; the hint says what happened.
- **`lua/ui_beardlib.lua`:** the shop's **Health** tab ("Health (hurt)") at home: the health
  figure (`draw_health` takes a position and returns its height), Heal everything / "You are not
  hurt.", a line on lasting damage, the status.
- **Tests:** new `lasting_tests.lua` 57. 3648 checks. Mutation check: 165 mutants of the new
  lines, 13 survive (the file guard, log lines, initial values, the file's error paths, and the
  in-heist health window's existing line); dead code found by it removed.

Defaults for the user to review: custody *during* a heist still gives a fresh body; leaving or
quitting a heist counts as ending down; overheal and the Painkillers delay are not carried;
nothing in the safehouse hurts you lastingly; a flat $15,000 with no Dallas tier discount; with
health per body part off, none of this.

## 0.47.0 (weapon condition: wear, jams, repair)

The user picked "Weapon condition" from `PDTI_IDEAS_HANDOUT.md` (4.2), then: wear "By class,
~2500 rds", clear a jam with "Its own key", at 0% "Only jams more", repair "Home, cheaper (20%)";
"yes, build now".

- **New `lua/armory_wear.lua` (`PDTI.Wear`):**
  - `Wear.ROUNDS` (100% -> 50%): minigun 1,000, lmg 1,500, snp 3,500, pistol 3,500, others
    2,500 (by the weapon's tweak categories). `PerRound` = 50 / rounds.
  - `JamChance`: 0 at >= 50%, then linear to `JAM_MAX` 0.1 at 0%. `JamText` for the view.
  - The condition is the weapon item's `data.cond` (missing: 100). `Wear.Cond` reads the heist's
    live value first. Free weapons are always 100.
  - In a heist: the wrapped `NewRaycastWeaponBase.fire` calls `Wear.OnShot` when the game fired
    (an akimbo second gun counts for its parent's uid, `_pdti_uid` from `armory.lua`'s
    `tag_unit`). Not at home or in the safehouse. The weapon item of a uid is looked up once
    (`Wear.known`).
  - A jam: `Wear.jammed[uid]`, the gun's `stop_shooting` (the automatic fire sound), the hint,
    and a write. The wrapped `NewRaycastWeaponBase.start_shooting_allowed` returns false for a
    jammed gun, so `PlayerStandard` never reaches `trigger_*` / `fire`: no round is used.
    `PlayerStandard._check_action_primary_attack` is wrapped for the click (`dryfire`) and the
    hint on a press.
  - The Clear Jam key (`mod.txt` keybind `pdti_clear_jam`, `lua/ui_clear_jam.lua`):
    `Wear.StartClear`; `Wear.Tick` (each frame, `hooks_game.lua`) clears after `CLEAR_TIME`
    1 s, and stops if the equipped gun changes or a reload starts.
  - Saving: the heist's wear goes into the armory file (`wear = { "<uid>": cond }`), at the first
    shot, then at most every 30 s, on a jam and at `Armory.OnMissionEnd`. `Armory.OnHeistStart`
    seeds the live values from it (the next day of a heist). `Armory.OnMenu` calls `Wear.Apply`
    (not final) before `ApplyLost`, so `Insurance.Claim` copies the lost condition, and
    `Wear.Apply(true)` after `ApplyCaptured` / `HotMod.ApplyWin`, which clears the file's table.
  - Repair: `Wear.RepairPrice` = built price x 20% x wear / 100; `Wear.Repair` at home only.
    `Wear.SellFactor` = 0.5 + cond / 200, used in `Parts.SellPrice` for weapons.
- **`lua/armory.lua`:** the file's `wear` table is sanitized (clamped 0..100); `cond` is kept on
  captured and returning weapons. **`lua/armory_insurance.lua`:** a return keeps the lost
  weapon's `cond`.
- **`lua/ui_beardlib.lua`:** the wear bar (`pdti_wear_bar`) on the hand boxes and the item's
  first grid cell (not at 100%); the view's "Condition N%: ..." line and the
  **Repair for $X (to 100%)** button.
- **Tests:** new `wear_tests.lua` 100. 3591 checks. Mutation check (each line deleted):
  `lua/armory_wear.lua` 201 mutants, 11 survive, all the file guard, log lines, the test-replaced
  clock and dice, initial values and a local's declaration; dead code found by it removed. The
  29 wear lines in `armory.lua`, `armory_insurance.lua`, `armory_parts.lua` and
  `ui_beardlib.lua`: all caught (a duplicate hook install removed).

Defaults for the user to review: pistols and snipers 3,500 rounds, LMGs 1,500, the minigun
1,000; the jam chance linear from 50% to 1 in 10 at 0%; a gun at 0% sells for half; parts don't
wear; an insured gun comes back as worn as it was lost; market and picked-up guns start at 100%;
an akimbo pair is one condition and a jam stops both; reloading or switching stops a clear;
nothing wears in the safehouse (the shooting range); the wear is written at most every 30 s
(a crash loses at most 30 s of wear); the bar is not drawn at 100%; the Clear Jam key has no
default key.

## 0.46.0 (lobby isolation: PDTI players only meet PDTI players)

The user: "plan the next phase" -> "Lobby isolation" (the armory's rule: "No hosting or joining
vanilla players"), "Any PDTI version".

- **New `lua/lobby.lua` (`PDTI.Lobby`):**
  - `ApplyKey` adds `_pdti` to `_BUILD_SEARCH_INTEREST_KEY` of `NetworkMatchMakingSTEAM`,
    `NetworkMatchMakingEPIC` and `NetworkMatchMaking` (whichever exist with a string key). The game
    uses that key for a new lobby's attribute, the lobby search's filter, the friends' list and the
    invite check (`join_server_with_check`). `InstallHooks` wraps those four calls so the key is
    put back first (another mod may set its own later), wraps `BaseNetworkSession.on_entered_lobby`
    and `add_peer` to start the looks, and registers the `PDTI_hello` receive hook.
  - The check (online, with SuperBLT's `LuaNetworking`; looks once a second through
    `DelayedCalls` while a session exists): hello = "<version>;<1 if I know you>", resent every
    2 s to who has not answered; the host removes a player 15 s after they could talk (verified,
    in the lobby or synched, not loading; the clock restarts otherwise) with the chat line to all
    and the game's own kick (`send_to_peers("kick_peer", id, 0)` + `on_peer_kicked`); a client
    leaves a silent host's lobby (`MenuCallbackHandler:_dialog_leave_lobby_yes`, a dialog) or, in
    a heist, warns once. Another version: one local chat line. No `LuaNetworking`: no checks,
    logged once.
- **New `lua/hooks_net.lua`;** `mod.txt` hooks it on `lib/network/matchmaking/networkmatchmakingsteam`,
  `.../networkmatchmakingepic` and `lib/network/base/basenetworksession`. `lua/main.lua` loads
  `lobby` and installs its hooks.
- **Tests:** new `lobby_tests.lua` 76 (fake classes after the game's matchmaking and session code).
  3491 checks. Mutation check of `lua/lobby.lua`: 57 of 57 caught (one dead line removed).

Defaults for the user to review: 15 s from when the player can talk; the game's kick (no rejoin
of that lobby); a client leaves only in the lobby, never in a heist; always on (no option).

## 0.45.1 (Duke's insurance tiers)

The user: "tier 2 insurence cost 20%, tier 3 back after a loss in 5 mins".

- **`lua/perks.lua`:** `Perks.InsuranceShare`: 20% from tier 2 (tier 3 keeps it);
  `Perks.InsuranceDelay`: 5 min at tier 3 only (tier 2 keeps 10). Duke's texts: tier 2 "Weapon
  insurance costs 20% (not 30%)", tier 3 "Also: a lost weapon is back in 5 minutes (not 10)".
  0.45.0's tier 3 of 10% and 2 minutes is gone.
- **Tests:** `perks_tests.lua` 149 (the tiers and the lines), `insurance_tests.lua` 82 (tier 2
  paid 20%, back after 10 min; tier 3 20%, back after 5 min). 3415 checks. Mutation check: 4 of 4.

## 0.45.0 (weapon insurance; Duke's room)

The user: "next phase" (the armory's next step: insurance, set by the user when the armory
began: "Insurance would cost 30% of built weapon price(includes all mods) and would give back
weapon 10 real life minutes after the heist ended"). Asked: a payment covers a weapon until it
is lost; Duke's room: "cheaper and faster insurance".

- **New `lua/armory_insurance.lua` (`PDTI.Insurance`):** `Insure` (at home, not a free weapon,
  30% of `Armory.BuildPrice` via `Armory.Take`), `Cancel`/`CancelItem` (paid back via
  `Armory.Give`), `OnBuildChanged` (at home a policy for another build is cancelled and paid back,
  with a note), `OnSold`, `Claim` (a lost insured weapon: a return `Armory.MakeData` of the insured
  build, a new uid, no magazine, due `ended_at + Delay()`; another build than the insured one:
  paid back instead), `Sweep` (at home, nothing waiting to be taken out: a policy whose weapon is
  gone or has another build is paid back), `Deliver` (due returns into the locker; no room: waits,
  logged once; a hint), `Tick` (once a second), `Returns`/`ReturnLines`. `Insurance.Now` is the
  clock (tests replace it).
- **`lua/armory.lua`:** the file keeps `policies` (by uid), `returns` and `ended_at` (broken
  entries dropped; `next_uid` past a return's uid); `mark_lost` stamps `ended_at`; `ApplyLost`
  claims a removed weapon; `OnMenu` sweeps and delivers after `ApplyWin`.
- **`lua/armory_hotmod.lua`:** `ApplyWin` claims a weapon gone in a won heist.
- **`lua/armory_parts.lua`:** `set_build` calls `OnBuildChanged`; `Parts.Sell` pays the insurance
  back and says so.
- **`lua/perks.lua`:** Duke (`myh`) is "Insurance": `Perks.InsuranceShare` (20% / 10%) and
  `Perks.InsuranceDelay` (5 / 2 min) at tiers 2 / 3.
- **Ticks:** `lua/hooks_game.lua` (every frame in game; acts at home only: the safehouse) and
  `lua/safehouse.lua`'s main-menu update (every frame, not only while a trip waits).
- **`lua/ui_beardlib.lua`:** the weapon view's Insure / insured line + Cancel / free-weapon line
  and the note after a change; a blue `pdti_ins_mark` on an insured weapon's top-right grid cell
  and its PRI/SEC box; return lines under the Locker label and in the market's Weapons tab.
- **Tests:** new `insurance_tests.lua` 80; `perks_tests.lua` 149, `hooks_tests.lua` 28,
  `safehouse_tests.lua` 203. 3413 checks. Mutation check of the new code: 45 of 45 caught (one
  redundant condition removed: `Armory.InHeist` already counts a session-only inventory).

Defaults for the user to review: the game's normal prices (not the day's); back without its
magazine; always into the locker; any change at home cancels and pays back; thrown away in a
heist counts as lost; Duke tier 2 = 20% / 5 min, tier 3 = 10% / 2 min; return times as clock time.

## 0.44.1 (loot prices sorted by price)

The user: "sort loot in the market by prices".

- **`lua/market.lua`:** `Market.Catalog()` sorts by today's price (`now`), dearest first; the
  same price by name, then id. Its only user is the price list on Scarface's Market screen.
- **`lua/ui_beardlib.lua`:** the list's label says "dearest first".
- **Tests:** `market_tests.lua` 84 (the order, today's price over the real one, the same price
  by name), `ui_tests.lua` 212 (the rows' order, the graph on the first row). 3327 checks.

## 0.44.0 (the game's mods into the locker, parts mark their weapons, ammo box reasons)

The user: "make that all weapon mods player have would be in the stash, and that when you drag
weapon mod all compatable weapons would be marked with green. Also when player goes into the
heist with no guns, and then takes one, he still cant take ammo boxes for loose ammo". Asked:
the stash is the locker, the mods are the game's own (drops); the box stayed on the floor; the
build's skills are not known.

- **`lua/armory_parts.lua`:** `Parts.Importable(part_id)` (a factory part with a black market
  entry, not ammunition) and `Parts.ImportGameMods()`: at home, on the mod's own save only
  (`PDTI_SEPARATE_SAVE`), every mod of `managers.blackmarket:get_inventory_category("weapon_mods")`
  is taken out with `remove_item` and added to the locker as a part item (its global value, a
  new uid); refused by the locker after all, it is given back (`add_to_inventory`). One that
  has no room waits; the progress is saved once (`save_progress`), the armory too; a hint and a
  log line. `Armory.OnMenu` calls it.
- **`lua/ui_interaction.lua`:** `PDTI.UIFitWeapons()`: for a held part, the weapons of yours
  whose kind takes it (`Parts.Takes`), by container and instance id.
- **`lua/ui_beardlib.lua`:** `show_fit_marks()` tints those weapons' drawn cells (the grid's
  and PRI/SEC's boxes) light green (`pdti_fit_mark`, layer 49, under the placement preview);
  `show_preview` draws them first, on every move, and the drop clears them.
- **`lua/skills_ammo.lua`:** `AS.TellBoxRefused()`: the first standard box a heist refuses
  for Bulletstorm or Extra Lead hints which skill (reset in `AS.OnHeistStart`).
- **`lua/ammo_hooks.lua`:** `Ammo.BoxLeftReason(unit)` (each gun: no weapon in your hands, why it
  is not managed, or its room and pickup; the bag skills). The box hook logs it when the game's
  pickup refused a plain box (once a box, once a reason). The unarmed then picked-up case works
  in the tests; in the game it could not be told apart from the skills, so the log will say.
- **Tests:** `parts_tests.lua` 212, `ammo_specialist_tests.lua` 113, new `unarmed_box_tests.lua`
  19 (the armory, the ammunition system and the skills on the game's box pickup). 3323 checks.

## 0.43.0 (Duke opens the Story Line)

The user: "make that interaction with duke will open career mode" (career mode: the game's
Story Line, their choice).

- **`lua/safehouse.lua`:** `Home.ROOM_ACTIONS.myh = "story"`. Duke's room menu
  (`ShowRoomMenu`) puts "Story Line (leaves the safehouse, comes back)" first (focused),
  offline only. `Home.ToStoryLine()` leaves the safehouse marked `to_story` (the shared
  `leave_for(mark, what)`, which `ToMenuInventory` now uses too). Back in the main menu,
  `OnMenuMain` plans the menu inventory's trip with `node = Home.STORY_NODE`
  ("story_missions", the page crime.net's sidebar opens), `what` (its name in the log and
  the hint) and `offline` (the game's `play_single_player` before the page opens, as crime.net
  offline does). Backing out to the first page loads the safehouse; a story heist's contract
  page and the heist are left to the game.
- **Tests:** `safehouse_tests.lua` 201 (Duke's menu and its order, online, the trip). 3278
  checks.

## 0.42.0 (the weapons market in pages)

The user: "Now for weapon market make different pages for secondary and primary and for each
weapon type".

- **`lua/armory.lua`:** `Armory.TYPES` (id, name, short name, in the order a page lists them)
  and `Armory.Type(weapon_id)`: "akimbo" when the game's categories have it, else the first
  category when it is a listed type, else "special". `Armory.Catalog()` rows carry `wtype`.
- **`lua/ui_beardlib.lua`:** `weapon_view(rows)` splits the catalog by page (primaries,
  secondaries) and type, settles `view.weapon_page`, `view.weapon_type` (an empty page or a
  type the page lacks gives way to the first that has weapons) and `view.weapon_pick` (one of
  the list shown). The middle window calls it first (it is drawn before the list). The list
  (`draw_weapon_prices`) has the page buttons `wmarket_page_<page>` ("Primary (n)"), the type
  buttons `wmarket_type_<type>` (four a row), and the label "<type name>  (n)". A page button
  resets the type.
- **Tests:** `ui_tests.lua` 211 (the pages, the types and their order, the pick following
  them); `pictures_tests.lua` 88 (the Chimano on the Secondary page, the page kept). The
  guide's test table gets `template_tests.lua` (46), left out in 0.41.0. 3266 checks.

## 0.41.0 (the weapon's view around the weapon, and build templates)

The user: "start working on gun build templates, and in weapon mod menu make that in center
would be the image of the weapon, mod slots would be on top and bottom sides. for example
sights and gadgets should be on the top side, while handle and foregrip on bottom".

- **The weapon's view is built around the weapon** (`lua/ui_beardlib.lua`):
  - The picture of the weapon (the game's own icon, `ui_pictures.lua`) is in the **middle**
    of the view, 120 high (at scale 1; it was 72 and at the top).
  - The slots are around it: the ones **on top of the weapon** (the sights, the gadgets, the
    boosts) above the picture, the ones **under the weapon** (the grip, the handguard, the
    vertical grip, the stock, the magazine, and the weapon's own parts: the barrel, the
    muzzle, the receivers, the slide) below it.
  - `TOP_TYPES`, `TOP_ORDER` and `BOTTOM_ORDER` say what goes where; `slot_bands()` splits
    the slots and orders them, `draw_slot_band()` draws a band, `draw_slot_box()` a box.
  - The slots keep their boxes and their behaviour (drag a part onto one to fit it, drag
    yours out, Ctrl+click it). Their numbers follow the new order: the top band first.
  - The picture of a **part's** view stays as it was (at the top).
- **New `lua/armory_templates.lua` (`PDTI.Templates`): gun build templates.** A template is
  the parts you fitted on a weapon, beyond the weapon's own: a recipe, not a copy of the
  parts.
  - `Save(weapon_data)`: the build of a weapon becomes a template, named after the weapon
    ("AMCAR build", "AMCAR build 2"). The weapon's own parts are not in it.
  - `All()`, `Find(id)`, `Count()`, `Describe(t)`, `Delete(id)`.
  - `Apply(id, container, instance_id)`: the parts the weapon takes and you own go on it;
    the parts that come off become items again (in the locker, or next to the weapon). What
    is left out is said: a part the weapon does not take, or one you do not own.
  - The templates are in their own file, one per profile (`pdti_templates.json`, or
    `pdti_save_templates_profile<n>.json` on the mod's own save). A template without parts
    is left out; a broken file is ignored.
  - A build is changed at home: in a heist the templates are not shown (a change takes time
    there, and a template is a whole build at once).
- **`lua/armory_parts.lua`:**
  - `Parts.ApplyBuild(weapon_c, weapon_iid, part_ids)` fits a whole build: the plan is made
    first (nothing is touched until it is known to work), then the parts leave the
    inventory, the parts that come off are placed, and the build is set. When they cannot
    all be placed, nothing changes and the parts are put back.
  - `Parts.OwnedItem(part_id)`: the part you own as an item (its container and the item).
  - `change()` is split: `change_bp()` works on a build given (the game's own changer only
    edits the list given).
- **The weapon's view shows the templates** (`lua/ui_beardlib.lua`): "Save this build as a
  template", and a row per template with **Apply** and **Del**. At most eight templates are
  listed; the rest are counted in a line.
- **The tests:**
  - **New `tests/template_tests.lua`:** 43 checks (saving, applying, what is left out and
    why, the parts that come off, the file, the screen).
  - `parts_tests.lua`: the slots' new order and the two bands around the picture.
  - `pictures_tests.lua`: the picture in the middle of the view, 120 high.
- **`lua/main.lua`** loads the new module; `tests/mock_env.lua` loads it too.

## 0.40.1 (names on pictures optional)

The user: "make text optional".
- New setting `item_picture_names` (on): `ammo.lua`'s defaults and saved keys, and Options →
  General → "Names on pictures". `Pictures.ShowNames()` reads it.
- Off:
  - `draw_grid` leaves the name out of a pictured item's cell;
  - `draw_weapon_slot` leaves out PRI's / SEC's text and draws the picture without the 0.45
    alpha.
- Items without a picture, the weapon view, the slot boxes and the market keep their text.
- 8 new checks in `pictures_tests.lua` (87). Five mutants on the new lines, all killed.

## 0.40.0 (pictures of weapons and parts)

Asked by the user: "are there pictures for weapons in game? like to directly import pic of CAR-4
rifle directly in UI?" Planned and approved: the game's own icons, drawn on the screen.

- **New `lua/ui_pictures.lua` (`PDTI.Pictures`)** finds and loads pictures; it draws nothing.
  - `WeaponPath(id)`: `managers.blackmarket:get_weapon_icon_path(id)` (no skin).
  - `PartPath(id)`: `guis/[dlcs/<texture_bundle_folder>/]textures/pd2/blackmarket/icons/mods/<id>`,
    the bundle from `tweak_data.blackmarket.weapon_mods[id]`. This rule is not in the decompiled
    source, so every miss is logged once with the path tried.
  - Both are kept only when `DB:has(Idstring("texture"), path)`, and cached (misses too).
    `ItemPath(item)` for weapon and part items; nil with the `item_pictures` setting off.
  - `Ready(path)`: asks `managers.menu_component:request_texture` once and is true when its
    callback came (at once without a loader, or when the request fails). The callback asks for
    one redraw (`PDTI.UIRedrawSoon`); one that comes during the request (the game had the
    texture) draws nothing more. `ReleaseAll()` calls `unretrieve_texture` with each index.
  - `Size(path, panel)`: the texture's size from a hidden bitmap (removed at once), cached.
  - `Slices(tw, th, cols, rows, cw, ch, gap, rotated, margin)`: the picture fitted into an
    item's whole area (shape kept, centred), a piece per cell it reaches, with its texture rect.
    A turned item gets the whole picture in each cell, turned 90 degrees about the item's centre
    and cut by the cell's panel: a bitmap turns about its own centre, so the pieces meet
    whichever way the engine turns it.
- **`lua/ui_beardlib.lua`:**
  - Pictures go on an item's own panel at layer 3. Its title is raised to 5, above the
    background (2), the highlight (1) and the border (4); the drop preview stays at 50.
  - **The grid:** a piece per cell; a pictured item's name moves top-left.
  - **PRI and SEC** (72 x 30 boxes full of text): the whole picture behind the text, at alpha 0.45.
  - **The views:** `inspect_picture` (72 high at scale 1) under the name of a weapon's or a
    part's view.
  - **The slot boxes:** the picture on the right of a part's box (not a standard part's), with
    the text left-aligned and its font fitted to the rest.
  - **The market:** `wmarket_picture` above Buy for the picked weapon.
  - No picture means no box and no gap.
  - `PDTI.UIRedrawSoon()`: one redraw on MenuUI's next update for every picture that came, none
    while dragging. The flag is cleared on close in case MenuUI drops the callback.
  - On close the pictures are removed (`view.pics`), then the textures given back: the hidden
    screen keeps its items, and the game removes its own before giving its textures back.
    Dead entries are forgotten at each redraw.
- **The setting:** `item_pictures` (on) in `ammo.lua`'s defaults and saved keys, and in Options →
  General.
- **The tests:**
  - **`tests/mock_env.lua`:**
    - a fake panel's `bitmap` (recorded per item, its size from `ENV.texture_sizes`);
    - `ENV.probes` counts the hidden size reads;
    - a fake title (layer 3) per item.
  - **New `tests/pictures_tests.lua`:** 79 checks.
  - **Mutation run:** 60 mutants; 58 killed. Two survive, each with no visible effect: the
    per-item pieces cache (it only saves work) and forgetting dead pictures (memory; the mock's
    `alive` cannot tell).
- Not tested in the game. To check: whether the part-icon rule finds the pictures, and how a
  turned picture and the faint PRI/SEC one look.

## 0.39.0 (hot modding: weapon parts changed during a heist)

The phase after 0.38.x, planned with the user. Their answers: changes made in a heist are kept
after a win; a change takes time by the part (shooting, aiming, reloading or switching stops
it); every part but magazines can be changed in a heist.

- **New `lua/armory_hotmod.lua` (`PDTI.HotMod`):**
  - `Fit` / `TakeOff` take the same arguments as `Parts.Fit` / `Parts.TakeOff`. At home they call
    those at once. In a heist they check first (`Parts.CheckFit` / `CheckTakeOff`, and the
    target cell with `CanPlace`) and start a timed job (`TIMES` by part type, 2-10 s, `Time`
    returns the default of 4 for other types).
  - One job at a time (`Busy`).
  - `Tick(dt, input)` runs from the `hooks_game.lua` frame wrapper, next to `Gear.Tick`.
    - It stops the job on `Ammo.ActionPressed` (not while the screen is open: the game gets no
      input, and the wheel scrolls the screen) or when `managers.player:current_state()` is not
      standard, carry or mask_off. `Stop` makes no change; the time is lost.
    - When the time is up, the weapon and part are found again by uid wherever they are, and
      `Parts.Fit` / `TakeOff` checks everything again. A take-off whose cell was taken meanwhile
      comes off next to the weapon.
    - It redraws the screen when a second passes, not while dragging.
  - `Active()` gives the screen the job's kind, type, weapon uid and progress.
  - **`RecordWin(d)`** runs in `OnMissionEnd(true)` and appends to `d.after`:
    - `builds`: carried weapons from the snapshot whose blueprint differs from the snapshot's;
    - `gone`: snapshot uids no longer present (fitted, thrown away, left on the ground);
    - `parts`: carried part items not in the snapshot (taken off in the heist), with their
      container.
  - **`ApplyWin()`** runs in `OnMenu` (after `ApplyLost` / `ApplyCaptured`) and in
    `OnHeistStart`, so a heist's next day starts with what the day before changed.
    - Builds go through `Parts.SetBuild` (weight, `Plan.ReshapeStored`, and the game's slot for
      a weapon in your hands).
    - Gone items are removed.
    - Parts are added where they were, else the locker; with no room they wait. A part whose uid
      is already there is not added twice.
- **`armory.lua`:**
  - **The snapshot:** `Armory.TakeSnapshot` (from `OnSpawn`, once per heist: `taken_set`) notes
    `d.taken` (the uids of `Brought()`) and `d.taken_bp` (each carried weapon's blueprint).
    `OnHeistStart` and `mark_lost` clear it.
  - **Failure:** lost is `Brought()` ∪ dropped ∪ `d.taken`. Before, a part fitted in the heist
    was no longer an item at the end and escaped the loss. A left heist (`OnMenu`) still uses
    `Brought()`: the menu's inventory is the one the heist began with, so the snapshot is not
    written to the file (it is read only in the level that took it).
  - **The file:** `sanitize` reads `taken`, `taken_bp`, `taken_set` and
    `after{builds, gone, parts}` and keeps `next_uid` above the waiting parts' uids.
  - `apply_inventory` compares builds in a heist too. Only a unit this mod made carries
    `_pdti_bp`; a picked-up one is taken as it is. This replaces 0.38.3's "never in a heist".
  - `Armory.Owned` exposes `owned_items`.
- **`armory_parts.lua`:**
  - `at_home` now only guards selling.
  - `changeable(part_id)` refuses a magazine part in a heist.
  - `Parts.Reachable(c)` refuses the locker in a heist. It guards both items of a fit, the
    weapon and target of a take-off, and `place_off`'s places.
  - `CheckFit` / `CheckTakeOff` are split out of `Fit` / `TakeOff`.
  - `Parts.SetBuild` exposes `set_build`.
- **`ui_interaction.lua`:**
  - The four change paths call `HotMod` (`changer()`): a drop on a weapon, a drop on a slot,
    a slot dragged out onto a cell, and Ctrl+click.
  - A busy job makes the fit preview, the slot preview and a slot drag refuse with
    "wait: the X is being fitted".
- **`ui_beardlib.lua`:**
  - `_UIInspect` works in a heist, but not on the locker.
  - In a heist the middle window is drawn only while the view is open, and `health_shown()`
    hides the health window meanwhile.
  - The view in a heist has no Sell button and has a heist help line. Its magazine slot is
    marked "(at home)", and the slot being changed shows "Fitting... N%".
- **Tests:** new `tests/hotmod_tests.lua` (112). parts 188 -> 189 (two heist checks rewritten:
  a sight can be changed and a magazine not; a gun this mod made with another build is made
  again, one the game made is not). 3122 in total.
- **Mutation test:** 89 mutants. 78 were killed at first. Of the 11 survivors, 9 are killed
  by new tests; 2 showed redundant code, which is removed (the union on a left heist, the
  snapshot's file write).

## 0.38.3 (part changes show on the gun in your hands)

User report: "mod changes aren't instant, when weapon was in primary and player put off the sight
it still was on the gun, and when the gadget was put on the weapon, it didnt appeared on weapon
until it was dragged and dropped to inventory, and used again". The game log showed the
safehouse: every fit updated the game's slot (`SyncEquipped`), but the gun in hand was never
made again.

- **`armory.lua`:**
  - `tag_unit` also marks a unit with the build it was made with (`_pdti_bp`, the item's
    blueprint text). `load_gun` and `apply_inventory` pass it; `unit_bp` reads it.
  - `apply_inventory`, outside a heist: the same weapon whose unit was made with another build
    is put in again (`stash_gun`, `put_in`, `load_gun`, as for a swapped weapon). A unit without
    the mark (made by the game at spawn from the hands' build) is taken as it is and marked.
  - In a heist the build is not compared. A picked-up weapon's build may differ from its item's,
    and parts don't change there.
- **`armory_parts.lua`:** `set_build` calls `Armory.ApplyHands` after `SyncEquipped` for a
  weapon in PRI/SEC, so the gun changes with the part, without waiting for the screen to redraw.
- **Tests:** parts 178 -> 188 (3009 in total).
- **Mutation test:** 9 mutants, all killed.

## 0.38.2 (the weapon view: slots)

User request: "make that weapon mods would have all their own slots on the weapons instead of the
list, and to remove them you either have to drag and drop or crtl+click".

- **`armory_parts.lua`:**
  - `Parts.Slots(weapon_data)` replaces `FreeSlots`: `OnWeapon`'s rows plus `{ ptype }` for each
    kind for sale with nothing fitted, sorted by slot. `by_slot` compares a missing part id as
    "" (LuaJIT's sort can compare an element with itself; a test makes it do so).
  - `Parts.TakeOff(weapon_c, weapon_iid, part_id[, to_c, x, y, rotated])`: with a place, the
    part goes exactly there (`AddItem`) and any other part that comes off goes next to the
    weapon. All or nothing: the placed part is removed again when the rest has no room.
- **`ui_interaction.lua`:** the slot drag.
  - `slot_drag` is a part being dragged out of its slot. It is not held; it stays on the weapon
    until let go on a cell.
  - New functions: `UIGetSlotDrag`, `UISlotDragStart`, `UISlotTakeOff` (Ctrl+click),
    `UISlotPreview` and `UIGetStatus` (the raw status).
  - `UIDragPreview` shows the part's footprint for a slot drag (`CanPlace`).
  - `UIDragDrop`:
    - A slot drag let go on a cell takes the part off there. Anywhere else it stays on.
    - A part let go on its slot (`{ mod_slot = ... }`) is fitted. Another slot, or an item that
      isn't a part, stays where it was.
  - Rotate, cancel, pick up and reset all end a slot drag.
- **`ui_beardlib.lua`:**
  - The weapon view draws `inspect_slot_<i>` boxes, 3 to a row: blue for yours, grey for the
    weapon's own, dark when empty, brighter while dragged out. The Take off rows, the count of
    parts and the free-slots line are gone, replaced by a count of slots and a help line.
  - Mouse handling:
    - `_UIHit` finds slot boxes (`view.slots`) and counts the middle window as the inventory
      ("window"). Before, a drop there threw the item away.
    - A press on a slot drags its part out, or takes it off with Ctrl.
    - A move over a slot lights that box.
    - The view's status line shows a slot action's outcome.
- **Help texts:** the locker help, a part's view and `GRID_TEXT` mention slots.
- **Tests:** parts 112 -> 178 (2999 in total).
- **Mutation test:** 62 mutants.
  - Redundant code removed:
    - the slot-drag check in `UISlotPreview` (a slot drag holds nothing);
    - the slot check on the right press (`_UIInspect` refuses it).
  - Tests added for the survivors: the empty-slot sort, a gone weapon's slot preview, the failed
    slot drop's wording, the plain-click hint, the layout, and the empty and lifted colours.
  - All killed now.

## 0.38.1 (right-click: the weapon view)

User request: "make that on clicking right mouse button would open a UI of the weapon with every
mod on it".

- **`ui_beardlib.lua`:**
  - `is_right(button)` matches the game's `Idstring("1")`.
  - `_UIMousePressed`: a right press on a weapon or part cell (PRI/SEC included) opens Inspect,
    redraws and swallows the click. Anything else, outside the cells or while dragging, is
    left alone (nil).
  - Inspect's weapon branch lists every part on the weapon (`Parts.OnWeapon`), slot by slot:
    standard parts as "(standard)" or "the weapon's own" when unnamed, non-buyable ones as
    "(comes with the weapon)", yours with Take off (a button row; the others are lines). Then
    free slots (`Parts.FreeSlots`), and concealment in the weight line.
  - The locker help is two lines.
- **`armory_parts.lua`:** `TYPE_NAMES`, `ORDER`, `TypeName`, `KnownName`, `OnWeapon` (sorted by
  slot), `FreeSlots` (types with a part for sale and nothing fitted) and `Concealment`.
- **Help texts:** the status line and `GRID_TEXT` mention the right click.
- **Tests:** parts 97 -> 112 (2933 in total). A 22-part weapon's view fits 720p.
- **Mutation test:** 21 mutants, 18 killed at first; 3 got tests (unknown slot names and order,
  the free slots' order), all killed now.

## 0.38.0 (Release B: weapon parts as grid items)

This is the next phase of the weapon market (user decisions of 2026-11-17: "Parts as items now",
fitted in the menu; "hot modding" in a heist later). Approved plan: Release B.

**New `lua/armory_parts.lua` (`PDTI.Parts`):**
- **Item:** `weapon_part`, with `uid` from the armory's counter, `part_id`, `ptype`, `name`,
  `for_weapon`, `global_value`, `w`/`h`/`weight` by type (`Parts.SIZES`).
- **`ForWeapon`:** follows the game's droppable-mod rule (`get_parts_from_weapon_id`, `pc`/`pcs`,
  DLC owned via `managers.dlc`, `unatainable`). Also left out: the default blueprint,
  `is_a_unlockable`, `ammo` type, and `magazine` type for weapons whose `Plan.InfoFor` is `sized`
  (AR/SMG).
- **Prices and buying:** `Price` is `get_weapon_modify_price` × `Armory.Factor(part_id)`. `Buy`
  checks the locker before paying and pays back with `Armory.Give` if the add fails.
- **`CanFit` / `Fit`:** checks the type list (`Takes`), already fitted, and `can_add_part`'s
  blocker. The new build comes from `change_part_blueprint_only` on a copy. Parts pushed off
  that are not standard issue and are buyable become items: the weapon's container first, then
  locker, backpack, rig. All or none.
- **`set_build`:** updates the blueprint and weight (`Armory.Weight`). It calls
  `Plan.ReshapeStored` and, for a hand weapon, `Armory.SyncEquipped`.
- **`CanTakeOff` / `TakeOff`:** fits the default part of that type when there is one (the game's
  own Remove does this), else removes the part.
- **`Fitted`, `FitsYours`, `SellPrice`, `Sell`:** 50% of today's price for the weapon and its
  buyable fitted parts. Free weapons are refused. The loaded magazine is paid back through
  `Plan.SellMagazines`.
- **Closed in a heist:** `Armory.InHeist()`; the safehouse is home.

**`armory.lua`:**
- Exposes `PART_ITEM_ID`, `Take`, `Give` (spending cash), `InHeist` and `NewUid`.
- `Brought` and `ApplyLost` cover part items (`owned_items`), so carried parts are lost with a
  failed or left heist.
- `GRID_TEXT` mentions parts.

**`plan.lua`:**
- `Plan.ReshapeStored(uid)`: stored `gun*_` magazines take the new build's size.
- `Plan.SellMagazines(d)`: refunds the stored magazines and the box magazine tagged with the
  weapon's uid.

**`ui_interaction.lua`:** `fit_target`. A held part over a weapon makes the preview the weapon's
rectangle (1x1 in PRI/SEC through `ItemSize(..., container)`), and the drop calls `Parts.Fit`.
`describe` names parts.

**`ui_beardlib.lua`:**
- `shift_down()`. Inspect opens on Shift without Ctrl, in the cell callback, the PRI/SEC boxes
  and `_UIMousePressed`. It is not opened in a heist or for other items, and a held item is let
  go.
- `draw_inspect`: weight, magazine, fitted parts with Take off, Sell with two clicks, Close.
- `draw_part_list`: a scroll list under the weapons market's Buy, with a signature cache like
  the weapon prices. It is cleared when not drawn and when the screen closes.
- Part cell label: the type tag, then the name's first word.

**Load lists:** `lua/main.lua` and `tests/mock_env.lua`. `tests/parts_tests.lua` (97) is in
`run_all`.

**Tests:** 2918 in total (2821 + 97).
- **Mutation test:** 67 mutants, 46 killed at first.
  - 7 survivors were redundant and removed: `session_only` in `at_home`, the two after-change
    checks, `SellPrice`'s free check, the box `RemoveItem` in `SellMagazines`
    (`SyncGunSlots` removes it), the UI's pre-check before `Fit`, and clearing Inspect after a
    sale.
  - The other 14 got tests and are killed.

Defaults for the user to review:
- Every buyable part is for cash, with no daily stock, at the game's price ±30% a day.
- DLC parts only if you own the DLC. Achievement parts and shotgun ammo parts are not sold.
- AR/SMG magazine parts are not sold (PDTI's magazine sizes replace them).
- Parts don't stack (each its own item).
- Default parts are not items: replacing one makes it vanish, and taking a part off brings it
  back.
- A part forbidden by a fitted part is refused, naming the blocker. Parts the new one pushes off
  come off as items.
- Selling pays 50% of today's price (weapon plus fitted parts, plus its loaded magazine back).
  Free weapons can't be sold.
- Parts are changed only outside a heist (menu and safehouse).

## 0.37.7 (magazines belong to weapons)

User request: "make that magazines are connected to weapons, and not to the slot".
- **Before:** every plan magazine and loose stack carried `plan_slot`, and `Plan.Refresh` reshaped
  a slot's ammunition into whatever weapon was in it (a shotgun turned magazines into shells).
- **Before, the gun's magazine:** it stayed in the slot's box when the weapon left. The user's save
  had AMCAR and Chimano magazines in empty PRI / SEC boxes, with all weapons in the locker.
- **Before, in a heist:** a weapon taken out lost its loaded magazine (`DropGunLeftovers`) and
  came back with a free full one.

**`plan.lua`:**
- **Weapon kinds:**
  - Ammo is keyed by weapon kind: `plan_weapon`, `queue_key = "plan:<weapon_id>"`, `wtag`.
  - `kind_of` reads older items by `pid` when they have `plan_slot`.
  - The public API stays per slot; the slot maps to the kind of the weapon in it.
  - `Plan.MenuWeapon` reads the hand item with grid weapons (an empty hand has none).
  - `Plan.InfoFor` and `Plan.KindInfo`: the hand weapon of the kind first (its parts), else one of
    yours, else the game's; nil for an unknown weapon.
- **`Plan.Refresh`:** reshapes each kind by its own info, and no longer converts a slot's
  ammunition.
- **`Plan.SyncGunSlots` (menu):** box magazines carry `weapon_uid`.
  - A box magazine of another weapon is folded into that weapon item (`Ammo.GunFields`), or goes
    with it if it is gone.
  - Untagged magazines of another kind (older saves) go into an owned weapon of that kind that
    holds none, else into the grid (marked `was_gun`), else are paid back.
  - The hand weapon unfolds its stored magazines. A weapon without `gun_set` gets a full free one.
  - A magazine taken out of a box loses its tag.
  - Without grid weapons: the magazine that left the gun returns when its weapon does, and each
    kind gets its free magazine once (`gun_filled` is a list).
- **`PDTI.GunSlotAccepts`:**
  - Menu: the hand weapon's kind.
  - Heist: the gun in that slot's key, or the magazine's own slot when there is no player.
- **`Plan.Bind`:** binds by `wep._name_id`. With an empty box and a grid weapon, it loads what the
  weapon item holds (an emptied weapon starts without a magazine).

**`ammo.lua`:**
- `Identify` has `weapon`. `WeaponTag` gives the short name, with "2x" for akimbo.
- `MagazineData` and `LooseData` carry `wtag`. `OnHeistStart` keeps `plan_weapon`.
- **New:**
  - `StoredMagazines` and `GunFields`: the flat fields on the weapon item (`gun_set`, `gun_n`,
    `gun1_*`, `gun2_*`, `gun_weight`, `gun_chamber`, `gun_clip`, `gun_in`).
  - `GunState`: reads the gun.
  - `EmptyGun`.
  - `LoadGun`: binds the kind first, drops the replaced gun's leftovers, then loads each stored
    magazine through the gun box's own `put_in`. It skips items marked `gun_in`.

**`armory.lua`:**
- Hand units carry `_pdti_uid`, so two of one model are told apart.
- `stash_gun` runs before `put_in` replaces a unit, in `take_out`, and before a unit becomes the
  stand-in. `load_gun` runs after `put_in`.

**`inventory.lua`:**
- The box check asks `PDTI.GunSlotAccepts`, skipped while loading.
- A weapon's weight includes `gun_weight`.

**`ui_beardlib.lua`:** loose rounds show `wtag`.

**Tests:**
- armory 153 -> 177, gun_slot 53 -> 80, plan 50 -> 55, typed_ammo 141 -> 144 (2821 in total).
- Three old checks were rewritten for the new rule (no conversion when the weapon changes).
- **Mutation test:** 31 of 53 killed at first.
  - 7 survivors were redundant code and were removed: akimbo `_pdti_gun_empty` in `EmptyGun`, the
    per-gun guard in `LoadGun`, the tag carried through a reshape, Bind's other-box branch, the
    pickup's own tag, the stand-in check in `stash_gun`, and the `plan_slot` rewrite triggers.
  - The other 15 got tests and are killed now.

Defaults for the user to review:
- A magazine fits only its own weapon model (AMCAR magazines don't fit the CAR-4).
- A weapon you emptied starts the heist without a magazine; a new weapon comes with one full
  magazine, free.
- A weapon's loaded magazine counts in its weight wherever it is.
- Ammo for a weapon you don't bring stays in your grid as that weapon's (useless until you hold it).

## 0.37.6 (no weapon in your hands)

User report: "if there is no primary, secondary cant be taken away". The log showed both blockers:
the heist rule that kept the last weapon in your hands, and in the safehouse the free Chimano 88
issued into SEC right after the user discarded their only secondary (a captured CMP).
- **User choices:** "no weapon at hands at all", and keep discarding weapons dropped outside the
  windows.

- **`armory.lua`:**
  - `HandLeaveCheck` is removed (and its call in `inventory.lua` `storage_locked`).
  - **Both slots empty (`make_unarmed`, in a heist and in the safehouse):** the secondary's unit
    (else a Chimano 88 added, else the primary) becomes the stand-in: `_pdti_unarmed`, ammo 0,
    `set_visibility_state(false)`, HUD ammo 0, its gun slot's magazine dropped. It gets a fake
    `_picked_up_weapon_data = { is_npc = true, ammo = { total = 0, clip = 0 } }`, so Pick Up
    Weapons never drops it and its `replenish` hook gives 0.
  - The vanilla player state needs a weapon unit (about 140 uses of `_equipped_unit` in
    `playerstandard.lua`), so a true empty inventory is not possible. This is the same idea as
    the game's own mask-off state.
  - A stand-in never counts as a slot's weapon (a real Chimano 88 is put in). `OnPickup` applies
    the hands, so the stand-in leaves at once.
  - **PlayerStandard hooks while the stand-in is equipped:**
    - Return nil for `_check_action_primary_attack`, `_reload`, `_weapon_firemode`,
      `_weapon_gadget`, `_deploy_underbarrel`, `_cash_inspect` and `_deploy_bipod`.
    - `_check_action_steelsight` ends aiming and blocks it.
    - The `update` post-hook clears `_equipped_visibility_timer` and hides the unit again (the
      game shows the equipped weapon every frame once that timer runs out).
  - `RaycastWeaponBase.add_ammo` / `add_ammo_from_bag` give the stand-in nothing.
  - `holds_nothing` checks `alive` first.
  - **Free weapons:** `free_due` in the armory file. It is true for a new file and set by
    `mark_lost` when anything was lost; `IssueFree` runs only when it is due, then clears it. An
    older file owes none.
- **`ammo.lua`:** `Identify` returns nil for the stand-in (the ammunition system leaves it alone).
- **`loadout.lua`:** with grid weapons, an empty slot has no entry in the menu too.
- **`ui_beardlib.lua`:** an empty slot reads "no weapon" (the "free Chimano" label is gone).
- **Tests:** `armory_tests.lua` 136 -> 153, `gun_slot_tests.lua` 51 -> 53 (2762 in total).
  Mutation test: 27 of 29 killed at first; the 2 survivors got tests and are killed now.

Defaults for the user to review:
- The stand-in is a pistol others may still see on you.
- Melee and throwables work with no weapon.
- Free weapons come only on a new save or after a loss.
- An empty slot means going into the heist with nothing there.

## 0.37.5 (fixes: a crash on picking up a weapon, a false "no room" for the magazine)

User report: "picked up weapons anyways have an issue that when you want to take out magazine game
says "no room for the magazine in a rig, despite that there is clearly place for it"", and "also
check the crashlog".

- **The crash** (`crash.txt`, 21:16:17, access violation, script stack
  `armory.lua:702` <- `add_unit_by_factory_name` <- Pick Up Weapons' `interact`):
  - `OnPickup` read `before_unit:base()._picked_up_weapon_data` after the game's `add_unit` had
    deleted that unit. A deleted unit's methods crash the engine, which `pcall` cannot catch.
  - The hook now reads it before the call, only for a unit that is `alive`. It passes `{ enemy }`
    to `OnPickup`, which never touches the old unit.
  - The tests' fake game marks the replaced unit deleted and counts any touch.
- **The false "no room":**
  - A weapon leaving your hands left its in-gun magazine item (`in_gun = true`) in
    `gun_primary`/`gun_secondary`. The next weapon's `place_gun_item` was refused ("the weapon
    already has its magazine"), so `_pdti_gun_items` stayed empty, `UnloadPlaces` found nothing,
    and `ChosenReload` showed the "no room" hint.
  - New `Ammo.DropGunLeftovers(c, keep)` removes in-gun items that the gun in hand does not
    claim. `SyncGunSlot` runs it first, for every weapon including shell-by-shell and no-reload
    ones. The armory's `take_out` runs it for an emptied selection.
  - `UnloadPlaces` returns why (`"none"` / `"room"`). On `"none"`, `ChosenReload` syncs once and
    retries; otherwise the hint names a slot holding another magazine.
- The "picked up ... is your primari now" log text now says primary or secondary.
- **Tests:**
  - `armory_tests.lua` 132 -> 136, `gun_slot_tests.lua` 44 -> 51, `wheel_tests.lua` 79 -> 81
    (2743 in total).
  - Mutation test: 13 of 16 killed at first. Two survivors got tests and are killed now (SEC's
    magazine slot, a selection whose weapon is already gone). The third is equivalent: the
    `"room"` reason, since any reason but `"none"` shows the no-room hint.

## 0.37.4 (Pick Up Weapons: picked-up weapons replace the slot's weapon)

User request: "make that weapon can be picked out from the slot during heist and weapons from mod
pick up weapons would replace those slots". The first half is 0.37.3, which the user had not
installed yet (the game log still showed 0.37.2): this release includes it.

- **How Pick Up Weapons swaps:**
  - Its interaction drops your current weapon of that selection as a world pickup
    (`create_player_pickup`), except a weapon that was an enemy's.
  - It then calls `player:inventory():add_unit_by_factory_name(factory, true, false, blueprint,
    cosmetics, texture_switches)` with `PickUpWeapons._picked_up_weapon_data` set while the call
    runs.
  - Its `assemble` pre-hook stores that data on the new weapon base.
- **`armory.lua`:**
  - A wrap of `PlayerInventory.add_unit_by_factory_name` acts only with that data set, in a
    heist, with grid weapons. It notes the selection's unit before the call and runs
    `OnPickup` after it.
  - **`OnPickup`:**
    - Takes the slot's item out of the grid. It goes to `Armory._dropped` if Pick Up Weapons
      dropped it (the old unit was in your hands and was not an enemy's).
    - A non-enemy pickup is matched against `_dropped` (factory and sorted blueprint, else
      factory) and gives the same item back.
    - Otherwise it makes a new item from the built unit's factory and blueprint (the default when
      none), with `picked = true`. `HandCheck` lets a picked item into a hand even if the game
      has not unlocked it.
    - Then it redraws the screen.
  - **`OnMissionEnd(true)`:** the `_dropped` uids are lost. The picked items you still carry go
    to `captured` (with where they were, once per uid, saved in the armory file; `sanitize`
    keeps only whole entries).
  - **`OnMissionEnd(false)`:** brought = the grid's weapons plus `_dropped`, and `captured` is
    cleared. A left heist also clears `captured`.
  - **`ApplyCaptured` (at the menu, after `ApplyLost`):** into the slot it was in (if empty and
    unlocked), else the locker, else it waits. A uid already in the inventory is skipped.
  - `OnHeistStart` clears `_dropped`. `OnSpawn` installs the hooks (`PlayerInventory` exists by
    then).
- **Tests:** `armory_tests.lua` 97 -> 132 (2730 in total). Mutation test: 30 of 30 killed after
  test additions. Two redundant lines were removed: the heist check in `HandCheck` (picked items
  only exist in a heist) and a category override equal to the weapon's own.

Defaults for the user to review:
- A won heist keeps every picked-up weapon you still carry (in its slot, or the locker) and loses
  your weapons left on the ground.
- Not-unlocked won weapons go to the locker. They can be used in a heist only when picked up there.
- A multi-day job only applies this at the menu: on day 2 you have your planned weapons again.
- The ammunition in a picked-up weapon is Pick Up Weapons' own.

## 0.37.3 (the weapon slots are your hands in the heist)

User report: "when taken out of slot weapons are still there. Make it that when no weapons is in
slot, player cant reach this weapon. Also i have a bug where i cant set taken out weapons back".

- **Why:**
  - Both weapons had been moved to the backpack on the raid's briefing screen, but the game
    had already been given its weapons, so the player still held them.
  - In the heist the hands were locked, so the weapons could not go back.
- **`armory.lua`:**
  - `ApplyHands(unit)` makes the player's inventory (selections 2 and 1) match PRI and SEC. A
    slot's weapon is added with `add_unit_by_factory_name(factory, false, true, blueprint)`
    when the selection holds another factory or none.
  - An empty slot's selection is removed: equip the other first, then `remove_selection`, then
    delete the unit the way `add_unit` does, then clear its HUD ammo. Additions come first, and
    the last weapon is never removed.
  - Both slots empty in a heist: a session-only free Chimano 88 item in SEC.
  - `OnSpawn` runs it for each new player unit (`hooks_game.lua`: the heist begins, after
    custody). The screen's redraw runs it too.
  - `HandLeaveCheck`: in a heist the last weapon in your hands stays.
  - `HandItem` and `InUse` read with `FindFirstItem`.
  - `brought` is now taken when the heist ends (`OnMissionEnd(false)`, or a left heist at the
    menu, from the plan), so moves on the briefing screen count.
- **`inventory.lua` `storage_locked`:** in a heist only the locker is refused, plus the armory's
  last-weapon check.
- **`loadout.lua`:** with the armory in use, a weapon entry is the slot's item (name, weight).
  In a heist an empty slot has no entry, so a weapon moved to the backpack is counted once.
- **`ui_beardlib.lua`:** an empty slot reads "no weapon" ("free Chimano 88" for SEC when both
  are empty), only when the armory is in use.
- **Tests:** `armory_tests.lua` 80 -> 97, `ui_tests.lua` 199 -> 201, `safehouse_tests.lua`
  187 -> 189 (2695 in total). The armory tests' game now has its own equipped weapons.
- **Mutation test:** 25 of 25 killed. Of the 2 first-round survivors, one was a redundant check in
  `HandItem` (removed) and one was hidden by the test game having no equipped weapon.

Defaults for the user to review: the last weapon cannot be taken out in a heist; both slots empty
in a heist gives a free Chimano 88 for that heist; a weapon put back into your hands comes with a
full magazine in it (to be fixed with the ammunition of swapped weapons); the briefing screen is
still planning (saved, and the locker is open there).

## 0.37.2 (the free weapons are real items)

User report: "weapons in inventory are still not real, they cant be taken to inventory".

- **Why:** with no weapon in a slot, PRI / SEC showed the game's free AMCAR / Chimano 88. That
  was only a label (the game's weapon), so there was nothing to drag.
- **Your AK-74:** the save files show it was in PRI and was later removed by the death rule.
  The likely cause is a safehouse raid left unfinished (the raid is a heist); the log of that
  session was overwritten, so this is not confirmed.
- **`armory.lua` `Armory.IssueFree()`:**
  - In the menu, for each kind (primary, secondary) you own no weapon of, it adds the game's
    free weapon as a `weapon` item (`free = true`) into its slot, or the locker.
  - It is called from `SyncEquipped`: menu entry, every redraw of the screen, after the game
    reads its save.
  - It saves the armory file, so the uid counter never goes back.
  - It is skipped in a heist, with restoration-mod, and when the game does not know the weapon.
- **`ui_beardlib.lua`:** an empty slot reads "PRI empty (AMCAR) x kg" (the game's own weapon,
  not an item).
- **Tests:** `armory_tests.lua` 73 -> 80, `ui_tests.lua` 197 -> 199 (2674 in total). The
  mutation test for these changes killed 8 of 8; the 2 first-round survivors led to the
  saved-uid and unknown-weapon tests.

Defaults for the user to review: a free weapon is given only when you own none of its kind, so
an emptied slot stays empty (and the game uses its own AMCAR there); free weapons are lost on
death like any weapon and given again at the next menu; the safehouse raid counts as a heist.

## 0.37.1 (the weapon slots are part of the inventory)

User request: "make the weapons in inventory just another slot, and players would be able to drag
and drop their weapons from the inventory to slots, and from slots, to their inventory".

- **`ui_beardlib.lua`:**
  - `draw_weapon_slot`: the PRI and SEC boxes of the left window are the `hand_primary` /
    `hand_secondary` cell (registered in `view.cells` at 0,0, so the mouse drag, its preview,
    click and Ctrl+click work on them).
  - An empty slot shows the free weapon. `slot_entry` draws the slots also when the game's
    loadout cannot be read.
  - `draw_locker` draws only the locker.
  - Leaving the market now clears its price graph from the left window (`GRAPH` was only cleared
    in market mode).
- **`inventory.lua`:** `PDTI.HAND` is 1x1, and a weapon in a hand slot takes one cell
  (`dimensions`), like a magazine in a gun slot.
- **`ui_interaction.lua`:**
  - The drag preview over a weapon slot is that one cell.
  - Ctrl+click sends any weapon to its slot first (`quick_targets`). The locker's list no longer
    names the hands.
  - Messages name the slots ("the secondary slot").
  - The click's hand special case is gone, because the slot is one cell.
- **Tests:** `armory_tests.lua` 71 -> 73, `ui_tests.lua` 188 -> 197 (2665 in total). The side
  windows' height checks are 680 instead of 620: the test screen now draws the weapon row as the
  game always did. The mutation test for these changes killed 13 of 13; of the first round's 3
  survivors, two led to new tests and one to removing a redundant guard.

Defaults for the user to review: the slot shows "free" with the game's AMCAR / Chimano 88 when
empty; Ctrl+click on a slot sends the weapon to the locker first, then the backpack.

## 0.37.0 (the mod's own save; weapons as grid items)

- **`save_slot.lua` (new):**
  - On the hook `lib/managers/savefilemanager` it sets `PROGRESS_SLOT` / `BACKUP_SLOT` = 86 on
    WIN32 (restoration-mod's pattern: 77) and `PDTI_SEPARATE_SAVE`.
  - As a mod part, `SaveSlot.OnMenu` (from the safehouse's `MenuMainState` hook) shows the start
    dialog once on a fresh save (level 0, rank 0, no `pdti_save_start.json`). Level 100 comes from
    `add_points(need, false, true)` one level at a time, then
    `custom_safehouse:add_coins_ingore_locked(120)`,
    `money:_add_to_total(100000, {no_offshore})`, `money:add_to_offshore(100000)` and
    `savefile:save_progress()`.
- **`inventory.lua`:**
  - `PDTI.SeparateSave()` / `SaveFileName(what, index)` give the `pdti_save_*` file names (also
    used by `stash.lua` and `armory.lua`).
  - New containers `hand_primary`, `hand_secondary` (5x2, one weapon of the category, the
    armory's `HandCheck` for unlocks, skipped while a save is read) and `locker` (12x10), all in
    `PDTI.STORAGE`: not counted in the total weight, and moves into or out of them are refused
    in a heist (`storage_locked`).
- **`armory.lua` rewritten:**
  - The weapons are `weapon` items with flat data (`uid, weapon_id, factory_id, category,
    blueprint` text, `name, w, h, weight`). `Buy` puts one in the locker (room checked before
    paying).
  - `SyncEquipped` writes slot 1 of the game's `crafted_items` per category from the hand (or
    the default), then updates the menu scene, the outfit and `Plan.Refresh`. It runs on menu
    entry, on every redraw of the screen in the menu, and after `BlackMarketManager:load`.
  - Death: `OnHeistStart` records `brought` (every weapon item not in the locker);
    `OnMissionEnd(false)` and a left heist move them to `lost`; `OnMenu` -> `ApplyLost` removes
    them from the inventory.
  - Removed: the forced-weapon hook, hands/where, Gift and Reconcile.
  - `BlackMarketGui` `buy_weapon_callback`, `choose_weapon_mods_callback` and
    `sell_item_callback` (weapons) show a message instead.
- **UI:** the Locker tab (`draw_locker`: the hands and the locker drawn with `draw_grid`); a
  weapon cell shows its name; a hand takes the weapon at its corner (click, drag, preview);
  Ctrl+click locker <-> hand. The Weapons tab is gone.
- Tests: `armory_tests.lua` 62 -> 71 (rewritten), `save_slot_tests.lua` 19 (new), `ui_tests.lua`
  185 -> 188, `safehouse_tests.lua` 186 -> 187 (2654 in total). Mutation test: 36 of 36 killed.

Defaults for the user to review: slot 86; the locker 12x10 (no upgrade yet); hands 5x2 (the
minigun is now 5x2); a locked weapon cannot go into a hand; the start offer once per new save;
the 0.36.0 armory file and the old mod files are left alone.

## 0.36.0 (the armory: weapon market, weapon loss, no restart)

- **`armory.lua` (new, `PDTI.Armory`):** own file `pdti_armory.json` / `pdti_armory_profileN.json`
  (atomic save as the stash): `weapons {uid, weapon_id, factory_id, blueprint, where =
  stash|hands|carried}`, `hands`, `stock {day, bought}`, `in_heist`, `gifted`. Prices from
  `MoneyManager:get_weapon_price_modified` + `get_weapon_modify_price` for non-default parts;
  daily factor 1 +- 0.3 and stock 0-3 from `Market.Hash` per weapon and day. `Buy`, `SetHands`,
  `ClearHands`, `Carry` (a `weapon` grid item with its own size and weight), `Store`,
  `Reconcile`, `HandsBuild` (cached; the free AMCAR / Chimano 88 when a hand is empty).
- **Hooks:** `BlackMarketManager.forced_primary` / `forced_secondary` return the hands build (a
  level's own forced weapon first). Restart: `singleplayer_restart`, `_restart_level_visible`
  false; `restart_game`, `restart_level`, `VoteManager.restart` / `restart_auto` blocked.
  `GameOverState.continue` leaves the job (`MissionEndState` network shutdown and start menu).
- **Death:** `OnHeistStart` (from `heist_start.lua`, not the safehouse) sets `in_heist`;
  `OnMissionEnd(success)` (the stash's `MissionEndState` wrap) keeps all on a win, else `Lose`
  removes hands + carried weapons and their items. `OnMenu` (the safehouse's `MenuMainState`
  hook) treats a set `in_heist` as a failure, runs the one-time `Gift` of the vanilla equipped
  builds and `Reconcile`.
- **`items.lua`:** `weapon` item (`size_by_data`, `weight_by_data`); **`inventory.lua`**
  `item_weight` reads `data.weight` for it.
- **UI:** market Loot / Weapons tabs (weapon list kept like the loot prices, `wmarket_*`), the
  inventory's Weapons tab (`armory_*`).
- Tests: `armory_tests.lua` (62, new), `ui_tests.lua` 171 -> 185, `safehouse_tests.lua` 185 ->
  186 (2622 in total). Mutation check: 39 of 39 caught (6 survivors got tests).

Defaults for the user to review: daily price +-30%, stock 0-3 per weapon; weapon sizes (pistol
2x1, SMG 3x2, rifle / shotgun 4x2, sniper / LMG 5x2, minigun 5x3); the free AMCAR + Chimano 88;
the first-run gift of your two equipped builds; a build's price counts only parts beyond the
default; the market and weapon changes closed during a heist (swapping comes in 0.38.0).

## 0.35.3 (pre-roll and Duke's room undone)

- **`loot_quality.lua`:** removed `WorldBags`, `PreRoll`, `Sees`, `Blocked`, `WorldTick`, the
  known / seen flags, Duke's reroll and aim hint, the contour "highlight" mark and the material
  refresh. `ForPickup` again: the thrown bag's roll (`held_before`, no hint), else a new roll
  (plus the contract High roll). **`loot.lua`:** `Loot.Tick` no longer calls `WorldTick`.
- **`perks.lua`:** `myh` back to `ready = false` with its old texts.
- Kept: the 0.35.2 Stackable rework and fewer hints.
- Tests: `loot_quality_tests.lua` 114 -> 81 (Duke and sight tests removed, pickup-roll and hint
  tests added), `perks_tests.lua` back to the plain "not made" check (2545 in total). Mutation
  check of the restored paths: 4 of 4 caught.

Defaults for the user to review: none new.

## 0.35.2 (Stackable carries any bag of its loot; fewer hints; outline marks)

- **`loot.lua`:** `StackKey` = carry_id + multiplier + dye fields (no quality / mods). `stack_for`
  takes a stored bag whose own limit has room (only a Stackable bag has one) and refuses a
  joining stack. `join_spec` appends the joining roll to `data.extra` ("q:mods;..."; an old
  stack's copies are written out first). `pop_spec` takes the last rider off (TakeOut, Remove).
  `Loot.Gather` (from `Loot.Add` for stored bags and after `StashCarried` of the hands bag) pulls
  single bags onto a Stackable one. The "stacked" hint is gone (log only).
- **`loot_quality.lua`:** `EncodeRoll` / `DecodeRoll` / `ExtraRolls` / `StackRolls`; `Describe`
  lists the riders; `AnyCarried` sees riders' modifiers. `ForPickup` returns `held_before`; `Stamp`
  hints only for bags not held before. Aim hint: High+ only, once per bag (`_pdti_hinted`).
  `paint_outline` calls `refresh_material` when the list is empty; `OutlineUnit` also adds the
  unit's `contour` "highlight" with the colour once (`_pdti_contour`) and logs `outlined (...)`
  once per bag.
- **`stash.lua`:** capture uses `StackRolls`. **`carry.lua`:** `LootFactor` per bag of a stack.
- Tests: `loot_quality_tests.lua` 91 -> 114, `stash_tests.lua` 57 -> 58 (2578 in total).
  Mutation test: 21 of 21 caught (after three tests were added for the first survivors).

Defaults for the user to review: a Stackable bag holds 3 riders (4 bags in all); riders come off
last-in first-out; the game's "highlight" mark may show through walls (it is the game's marking
outline).

## 0.35.1 (Duke's outline seen through the floor; Stackable pickups)

- **`loot_quality.lua`:** `Sees` aims `AIM_UP` 25 cm above the bag's origin; `Blocked(from, to,
  unit)` casts to `RAY_SHORT` 30 cm before the bag (no ray closer), without `"report"`, and a hit
  on the bag itself is not a wall. Log `seen:` for High+ bags with Duke tier 2+.
- **`loot.lua`:** `Loot.StackKey` (carry_id, quality, mods, multiplier, dye fields; nil = false /
  default) replaces exact data equality in `stack_for`. `Loot.WorldBagData` / `WouldStack`:
  `PickupBlocked` and the swap allow a pickup that joins a stack. In `Loot.Tick`, a carried bag
  with no place of its own goes onto its stack with `StashCarried(rolled)`, reusing the roll
  already made (a second `Stamp` used to reroll it, so it never matched).
- Tests: `loot_quality_tests.lua` 74 -> 91 (2554 in total). Mutation test: 13 of 13 caught
  (after two tests were added for the first survivors).

Defaults for the user to review: the aim point (25 cm up) and the 30 cm short ray.

## 0.35.0 (loot rolled at the heist start; Duke's room)

- **`loot_quality.lua`:** `WorldTick` (from `Loot.Tick`, every `SCAN_EVERY` 0.25 s, not in the
  safehouse): `WorldBags` (interactive units with carry data that `Stash.IsLootBag` accepts),
  `PreRoll` gives every one without `_pdti_quality` a roll, then marks `_pdti_seen` when `Sees`
  (camera position / forward, within `SEEN_DISTANCE` 2000 cm, cos >= `SEEN_COS` 0.77, no
  `world_geometry` ray hit via `LQ.Blocked`) and, with Duke tier 2+, `OutlineUnit`.
  The outline (`make_set_contour`, `OutlineUnit`) needs the bag known: `_pdti_known` (you threw
  it, set in `sync_carry_data`) or seen with Duke tier 2+. `ForPickup`: a world roll is kept; a
  bag held before (`known`) is untouched; Duke tier 3 rerolls the first Standard pickup
  (`runtime.rerolled`), then the contract High roll. Aiming (`selected_color`) at a known bag with
  Duke tier 3 hints `Describe` (every `AIM_HINT_EVERY` 4 s per bag). `LQ.Reset` (now also from
  `Loot.OnHeistStart`) clears the reroll, the scan time and the hints.
- **`perks.lua`:** Duke ready; texts.
- Tests: `loot_quality_tests.lua` 49 -> 74 (2537 in total). Mutation test: 20 of 20 caught
  (after two tests were added for the first survivors).

Defaults for the user to review: "seen" = within 20 m and about 40 degrees of where you look,
checked 4 times a second; Duke's tier 3 reroll is automatic (the first Standard bag picked up),
not a button; bags other players throw are not outlined for you unless you saw them with Duke.

## 0.34.2 (the price list keeps its scroll; only capturable loot)

- **`ui_beardlib.lua`:** the price list has its own label (`pdti_prices`), so a redraw's
  `ClearItems(DYN)` leaves it; `draw_prices` makes it again only when its signature (position, row
  height, every row's text) changed; it is removed when the market closes or the screen is in
  inventory mode. The graph and the other lines are drawn again as before.
- **`market.lua`:** `Catalog` takes only loot with its own `bag_value` that `Stash.IsLootBag`
  accepts (no small loot, vehicles or `skip_exit_secure`) -- what can be captured.
- Tests: `ui_tests.lua` 167 -> 171, `market_tests.lua` 79 -> 81 (2512 in total). Mutation test:
  7 of 7 caught.

## 0.34.1 (all loot priced; the mouse while the market is open)

- **`market.lua`:** `BaseValue` reads like `MoneyManager:get_bag_value`: `tweak_data:get_value(
  "money_manager", "bag_values", bag_value or "default")`, decoded with
  `Application:digest_value(v, false)` (the values are digested strings in the game; 0.34.0's
  `tonumber` gave nil, so `Catalog` left almost everything out). `Catalog` now takes every carry
  entry with a bag `type` (in `carry.types`), not `being`, not `is_vehicle`, not small loot; no
  `bag_value` means "default".
- **`ui_beardlib.lua`:** `PDTI.UIKeepInputBlocked()`, run every frame by the game hook while the
  screen is open: blocks the controller if it was not blocked yet, and turns it off again if
  something (the closing room-menu dialog) turned it on, remembering to turn it on at close.
- Tests: `market_tests.lua` 75 -> 79, `ui_tests.lua` 163 -> 167, `hooks_tests.lua` 26 -> 27 (2506
  in total). Mutation test: 8 of 8 caught (after two tests were made stricter).

Defaults for the user to review: mission items without a value of their own (engines, a goat,
bike parts...) are listed at the game's default value.

## 0.34.0 (the market's price list and 7-day graph)

- **`market.lua`:** `BaseValue` (`tweak_data.money_manager.bag_values[carry.bag_value]`);
  `Catalog()` (every `tweak_data.carry` entry with a bag value, no `is_vehicle`, not in
  `carry.small_loot`; one row per name; `{carry_id, name, real, now, change, stashed}`); a sales log
  `market.sales[carry_id][day number] = count` written by `OnSold` (kept `SALES_KEEP` 20 days, in
  `Sanitize`); `SaturationAt(carry_id, n)` replays it; `History(carry_id)` = `HISTORY_DAYS` 7 days
  of `{day, factor, price}`, past days from that day's drift, featured type and `SaturationAt`,
  today from the live `Factor`; `DayString(n)`.
- **`ui_beardlib.lua`:** in market mode the left window draws `draw_prices`: a nested `Menu`
  (`scrollbar`, `auto_height`, `max_height` = 10 rows) of row buttons; a click redraws only the
  graph (label `pdti_graph`), so the list keeps its scroll position. The graph: 7 bars scaled
  between the week's lowest (25%) and highest price, price above (short money: $2.9k), weekday
  below, today in gold.
- Tests: `market_tests.lua` 56 -> 75, `ui_tests.lua` 157 -> 163 (2497 in total). Mutation test:
  14 of 14 caught (after three tests were added for the first survivors).

Defaults for the user to review: "real price" is the game's base bag value (no difficulty);
10 rows visible; the stashed type (or the first) is shown in the graph when the market opens.

## 0.33.1 (the market through Scarface)

- **`safehouse.lua`:** `Home.ROOM_ACTIONS.terry = "market"`: Scarface's room menu (talking to him,
  `talk_to_heister_terry`) gets a **Market** button calling `PDTI.OpenMarket`.
- **`ui_beardlib.lua`:** the Market tab is gone from the inventory's middle window.
  `PDTI.OpenMarket()` opens the screen in `view.market_mode`: the left and right windows stay empty
  (1x1), the middle window draws the market, its status line and a Close button; closing resets the
  mode. `PDTI.IsMarketOpen()`.
- Tests: `ui_tests.lua` 152 -> 157, `safehouse_tests.lua` 181 -> 185 (2472 in total). Mutation
  test: 4 of 5 caught; the survivor was a redundant line (the safehouse is never "in a heist"),
  removed.

Defaults for the user to review: the market has no way in outside the safehouse; Scarface's
Market button is there at every room tier.

## 0.33.0 (safehouse phase 4: the market and contracts; Ethan & Hila)

- **New `market.lua`** (`PDTI.Market`), state in the stash file under `market` (`Market.Sanitize`
  from `stash.lua`'s sanitize): `sat` per loot type `{level, day}`, `active` contracts, `taken`
  offers of `taken_day`, `high_rolls`.
  - Prices: `Price(bag)` = value x `Drift` (a hash of the day and the type, `DRIFT` 0.2) x
    (1 - `Saturation`) x `FEATURED` 1.25 for Ethan & Hila's type. `OnSold` adds `SAT_STEP` 0.08,
    `SAT_RECOVER` 0.04 a day, `SAT_MAX` 0.6. Day = `os.date("%Y-%m-%d")`, `DayNumber` for the
    difference.
  - Contracts: `Offers(day)` (deterministic, `OFFERS` 3 + 1 with E&H tier 2) from `Pool()`
    (`POOL` types that exist in `tweak_data.carry`, plus the stash's types); `LEVELS` Easy /
    Medium / Hard; `Accept` (`MAX_ACTIVE` 3, due = today + days - 1), `Active` drops run-out ones,
    `Deliver` takes the cheapest `Matching` bags (`Stash.Remove`), pays value x mult (`Stash.Pay`),
    `custom_safehouse:add_coins`, Hard adds a High roll.
  - `TakeHighRoll`: `LQ.ForPickup` rerolls a Standard new bag with `LQ.Roll(carry_id, 2)`.
- **`stash.lua`:** `StoredPrice` is the market price, `SellNowPrice` a share of it; sales call
  `Market.OnSold`; `Stash.Pay`, `Stash.Remove` exported.
- **`perks.lua`:** Ethan & Hila ready.
- **`ui_beardlib.lua`:** a fourth tab **Market** (offers, your contracts with Deliver, featured type,
  High rolls); the Stash tab shows today's change.
- Tests: new `market_tests.lua` (56), `ui_tests.lua` 144 -> 152, `stash_tests.lua` (the stash sale
  after a sale of the same type is the market's 92%) -- 2463 in total. Mutation test: 25 of 25
  caught (after two tests were added for the first survivors).

Defaults for the user to review: drift +-20%, saturation -8% a sale / +4% a day / 40% floor;
3 offers a day, 3 contracts at a time; the level table above; the only rare reward is the High roll
(the plan's upgrade voucher and special magazine are not made); the contract pool's 10 loot types.

## 0.32.1 (room bonuses: Jacket)

- **`perks.lua`:** Jacket ready. `MeleeChargeFactor` (1.5 at tier 2+) multiplies
  `PlayerStandard._get_melee_charge_lerp_value` (capped at 1); `OnMeleeKill` at tier 3 from a
  `CopDamage.damage_melee` wrap (your unit, `attack_data.result.type == "death"`): `Body.HealPart` on
  `MostHurtPart` (lowest fraction, not black, not full) by `MELEE_KILL_HEAL` (15%) of its max.
- Tests: `perks_tests.lua` 136 -> 146 (2399 in total). Mutation test: 7 of 7 caught.

Defaults for the user to review: "50% faster" is the charge reached x1.5 (a full charge in 2/3 of
the time); civilians killed by melee heal too; with the body parts off the kill heal does nothing.

## 0.32.0 (room bonuses, part 2: Dallas, Sangres, Rust, Houston, Clover, Joy)

- **`perks.lua`:** these six are ready. `Perks.Worn(piece)`: an option counts in `Level` only while
  its rig, backpack or armour class is worn. New: `ReviveCount`, `BagRecharges`, `ReviveItem`,
  `FakTimeFactor`, `BagExtraUses(container)`, `RigRefillOn`, `RigBagRefill` (the guns'
  `add_ammo_from_bag` with the item's `data.uses`, or a full bag of yours + Rust's one; uses left are
  written to the item, an empty bag removed), `RigConcealRelief`, `LootSlot` (`LOOT_SLOTS` 2x2 / 2x4),
  `HackFactor`, `KeycardClone`, `OnHeistStart`. Hooks: `TimerGui._start` (x0.75 once per timer, not
  `is_drill` / `is_saw`), `TimerGui.set_timer_multiplier` (keeps it), `PlayerManager.remove_special`
  (`bank_manager_key`, once per heist).
- **`gear.lua`:** `revives_used` against `ReviveCount`; `OnDoctorBagPlaced` (from `deployables.lua`
  after a doctor bag is placed) gives one back; with a first aid kit no full body heal, then
  `band_aid_health` once you are up.
- **`skills_ammo.lua`:** `OnBagDeploy(data, container)` adds Rust's extra use to the bag that appears
  (local `_ammo_amount`). **`skills_medic.lua`:** the first aid kit deploy time override multiplies
  Sangres' factor. **`skill_rules.lua`:** `Rules.HiddenWeight()` comes off the live weight for R4.
- **`inventory.lua`:** a new container `loot_slot` (like the pouch: `NO_SECTION` without Clover; loot
  bags only); refitted by a backpack change and a bonus change; in the view model. `loot.lua` places
  bags there first. The right window draws it next to the backpack.
- **New keybind** `pdti_rig_ammo_bag` (`lua/ui_rig_bag.lua`).
- Tests: `perks_tests.lua` 83 -> 136, `ui_tests.lua` 143 -> 144 (2389 in total). Mutation test: 19
  of 20 caught; the survivor (skip a gun once the bag is empty) is equivalent.

Defaults for the user to review: Rust's refill takes from the first ammo bag found in the rig; a full
bag is the game's base 4 uses + your upgrades + Rust's 1; the keycard is `bank_manager_key` only.

## 0.31.1 (the laptop: the Contract Broker)

- User request: the laptop on the second floor opens the Contract Broker instead of only leaving
  the safehouse. The broker is a crime.net menu component (`MenuComponentManager:
  create_contract_broker_gui`, node `contract_broker`), so it cannot open inside a level: the
  laptop makes a trip like Chains' room.
- **`Home.OnInteract` / `Home.ToBroker` (`safehouse.lua`):** a hook on `BaseInteractionExt.interact`
  and `UseInteractionExt.interact`. In the safehouse, offline, the tweak `exit_to_crimenet` sets
  `Global.pdti_home.to_broker` and `Global.load_crime_net` (as the game's `leave_safehouse`) and calls
  `_dialog_end_game_yes`; the game's interaction does not run. Failing: marks cleared, the game's
  runs. Every other tweak is logged once per visit.
- **`Home.BrokerTick`:** `MenuMainState:at_enter` opens `crimenet_single_player` itself; half a
  second after it is seen, `open_node("contract_broker")`, once. Back on `main` after any other
  page: `Home.Go`. On `main` for 2 s without crime.net: `play_single_player` + open
  `crimenet_single_player` once, then a hint once. Dialogs: `GIVE_UP` before crime.net.
- Not seen in game yet: that the second-floor laptop is `exit_to_crimenet` (the log line `used in
  the safehouse: ...` will show it).
- Tests: `safehouse_tests.lua` 158 -> 181 (2335 in total). Mutation test: 14 of 14 caught (after 2
  more tests).

Defaults for the user to review: half a second on crime.net before the broker opens; offline only.

## 0.31.0 (safehouse room bonuses, part 1)

- Phase 5 of the safehouse plan comes before the market (the user's order). The perk table is the
  one agreed on 2026-11-17: each rig, backpack and armour class has two room options (pick one in
  the inventory), the room's tier 2 unlocks it and tier 3 upgrades the same option.
- **New `lua/perks.lua` (`PDTI.Perks`),** loaded before `inventory.lua` (the save is read when that
  file loads; a row a room adds must exist by then). `Perks.ROOMS`, `PIECES`, `OPTIONS` (`ready =
  false`: shown, cannot be picked), `Tier` (max of the game's `get_room_current_tier`, asked only
  when `_global.rooms` exists, and the saved tier), `Active`, `Level`, `Equipment` (a cached copy of
  the rig or backpack definition with the option's `apply`), `Choices`, `WhyLocked`, `RoomLines`,
  the bonus functions, `Tick` (light armour break), `InstallHooks`.
- **Inventory save:** `perks` (piece -> room) and `room_tiers` (room -> tier). Every save adds the
  game's current tiers (never lowers). `sanitize_loaded` reads them before the items.
  `get_equipment_definition` / `get_rig` go through `perked()`. `PDTI.SetPerkChoice(piece, room)`
  refits the rig and the backpack like `SetEquipment` (shared `refit_and_save`), `PDTI.PerkState`,
  `PDTI.NoteRoomTiers`.
- **Hooks:** `PlayerManager.body_armor_regen_multiplier` (Sydney), `damage_reduction_skill_multiplier`
  (Jimmy), `CustomSafehouseManager.set_room_tier` (remember tiers); installed from the game tick, the
  menu (`hooks_home.lua`) and `main.lua`. `LootQuality.Chances()` (Bonnie), `Stash.Capacity()` /
  `SellNowShare()` (vault, Scarface), `Armour.PlateTime()`, firing vs reload cancel, `SpeedFactor`
  (Wick, Jiro).
- **UI:** the "Rig" heading became two tabs, Rig and backpack / Room bonuses (same height). The
  safehouse room menu lists the room's bonus with the tiers you have.
- **Changed from the agreed table:** Chains' tier 3 is an 8x4 ammunition part, not 7x5: a fifth
  row made the inventory window 644 px tall (the limit at 720p is 620).
- Not made yet: Dallas, Sangres, Rust, Houston, Clover, Duke, Joy, Jacket, Ethan & Hila.
- Tests: new `perks_tests.lua` (83), `ui_tests.lua` 136 -> 143 (2312 in total). Mutation test of
  `perks.lua`: 13 of 13 caught (after 3 tests for saved choices).

Defaults for the user to review: Bodhi's weight limits (20 / 24 kg), Chains' tier 3 as 8x4, Sydney
applies to every hit's regeneration delay (not only after the armour broke), Jimmy's half damage
starts on the frame after the breaking hit.

## 0.30.8 (the menu inventory trip: no bounce)

- In-game report: the game went straight back to the safehouse. Log: the page was opened inside
  `MenuMainState:at_enter` and on the next check the menu was still on `main`, which counted as
  "back on the first page".
- **`Home.InventoryTick` rewritten:** waits `INVENTORY_DELAY` (0.5 s) before `open_node`; returns
  to the safehouse only after `p.left_main` (a page other than `main` was seen, logged as `in the
  menu's "<page>" page`); still on `main` after `INVENTORY_RETRY` (2 s): one more try; then you
  stay in the menu with a log and a hint (open it yourself). No time limit once you left `main`,
  dialogs included.
- Tests: `safehouse_tests.lua` 151 -> 158 (2222 in total). Mutation test: 7 of 7 caught.

Defaults for the user to review: 0.5 s settle, 2 s before the second try.

## 0.30.7 (Chains' room: the menu inventory and back)

- The user meant Chains' room and the game's own menu inventory (build, weapon mods, ...), not
  Wolf and the mod's screen. A level has only the small weapon picker, so the room makes a trip.
- **`Home.ToMenuInventory()` (`safehouse.lua`):** sets `Global.pdti_home.to_inventory` and calls
  `MenuCallbackHandler:_dialog_end_game_yes()` (the game's "end game": save, `load_start_menu`).
  `Home.OnMenuMain` takes the mark first (reason "back from the inventory", allowed with the option
  off, no black cover) and `Home.InventoryTick` opens `Home.INVENTORY_NODE` ("inventory") once the
  first page is up, then waits (no time limit) until you are back on `main`, then `Home.Go` (the
  briefing is passed). A failing `open_node` goes straight back.
- `Home.ROOM_ACTIONS = { spanish = "menu_inventory" }`, `Home.ROOM_ZONES.spanish` at
  (650, -1674, 0) (moved to where Chains stands). His room's menu has "Menu inventory".
- The `AccessWeaponMenuInteractionExt.interact` hook and the deferred `open_inventory` are removed:
  the racks are the game's again.
- Tests: `safehouse_tests.lua` 147 -> 151 (2215 in total). Mutation test: 9 of 10 caught; the
  survivor (the safehouse check in `ToMenuInventory`) is made by every caller first.

Defaults for the user to review: the inventory page is the node "inventory" (to confirm in the
game); the way back starts when you reach the menu's first page.

## 0.30.6 (Wolf's room opens the inventory)

- In-game report: the room menu the user got was Chains' (`spanish`, tier 3: Close only); the
  heister list showed Chains at (650, -1674, 0) right above Wolf at (954, -1765, -400). The user
  asked for the room itself, not Wolf, to open the inventory.
- **Room zones (`safehouse.lua`):** `Home.ROOM_ZONES = { german = { at = (954, -1765, -400),
  radius = 600, height = 250 } }`; the centre is moved to where the room's heister stands
  (`Home.FindZones`, looked for until found; logged). `Home.RoomAt(pos)`.
- New hook (tag `home`) on `PlayerCivilian._check_action_interact` (the safehouse's player
  state has its own): on `btn_interact_press`, `Home.RoomInteract()` (safehouse, screen closed,
  `managers.interaction:active_unit()` nil, inside a room whose `ROOM_ACTIONS` is `inventory`)
  opens the screen and the game's interact does not run that frame.
- `Home.ZoneTick` (from `GameTick`, every 0.25 s): a hint when you walk into such a room.
- Tests: `safehouse_tests.lua` 134 -> 147 (2211 in total). Mutation test: 9 of 10 caught; the
  survivor (the safehouse check in `RoomInteract`) is repeated in `OpenArmory`.

Defaults for the user to review: the room is 6 m around Wolf, one floor high (2.5 m up or down).

## 0.30.5 (Wolf's menu: the daily side job, the heister list)

- In-game report: no menu from Wolf, and no log line for it either. Either his talk took the
  daily side job (the menu is skipped then, and that was silent) or his unit is not a talkable
  heister. `Home.OnDailyTaken` now logs it and shows a hint ("talk to them again");
  `Home.Heisters()` / `Home.LogHeisters()` log every heister in the level once on arrival
  (`heisters here: wolf (german) at (x, y, z); ...`, ` off` when not active).
- `round`/`xyz` moved to the top of `safehouse.lua` (used before the probe section now).
- Tests: `safehouse_tests.lua` 131 -> 134 (2198 in total).

Defaults for the user to review: none new.

## 0.30.4 (rooms upgraded in the safehouse)

- **Room menus on the heisters (`safehouse.lua`):** new hook (tag `home`, from
  `Home.InstallGameHooks`) on `CivilianHeisterInteractionExt.interact`: after the game's answer,
  `Home.OnHeister` (safehouse only) finds the room with `Home.RoomOfHeister` (`ext.character`,
  else the `talk_to_heister_<who>` tweak; `CriminalsManager.convert_new_to_old_character_workname`;
  `ecp_male`/`ecp_female` -> `ecp`; only ids in `tweak_data.safehouse.rooms`) and
  `Home.ShowRoomMenu` shows a `managers.system_menu:show` dialog (id `pdti_room_menu`): tier, max,
  coins, the next tier's `help_id_<tier>` text, its `get_upgrade_cost`. Skipped when the talk
  takes the daily side job (`is_daily_contractor` and not `is_daily_accepted`).
- **`Home.UpgradeRoom`:** `purchase_room_tier` + `set_room_tier` (as `CustomSafehouseMapPoint`
  does), `managers.savefile:save_progress()`, a hint. Refused at the top tier or without the coins.
- **`Home.ROOM_ACTIONS = { german = "inventory" }`:** Wolf's menu has Open inventory; it sets
  `Home.open_inventory` and `Home.GameTick` opens the screen on the next frame (not inside the
  dialog's click).
- Tests: `safehouse_tests.lua` 119 -> 131, `hook_chain_tests.lua` fakes the heister class (2195 in
  total). Mutation test: 12 of 12 caught.

Defaults for the user to review: the menu opens after every talk with a room's heister (except the
daily side job's); the new tier shows after re-entering the safehouse; the vault and living room
have no menu (no heister there).

## 0.30.3 (a waiting raid comes first)

- **`Home.RaidWaiting()` / `Home.OfferRaid()` (`safehouse.lua`):** in `Home.MenuTick`, at the
  main menu's first page, when `managers.custom_safehouse:is_being_raided()` is true the black
  cover is taken away and `managers.menu:open_node("crimenet_contract_chill")` opens the game's
  raid contract (`MenuCrimeNetContactChillInitiator`: difficulty, One Down, Defend, Ignore, Back)
  instead of `Home.Go`. If the node cannot open, the safehouse as before.
- New hooks (tag `home`, `Home.InstallRaidHooks`, from `InstallMenuHooks` and `OnMenuMain`):
  `MenuCallbackHandler.play_chill_combat`: on the offered contract, with no session it calls
  `play_single_player()` first, so the game's own code takes `start_single_player_job`
  (`chill_combat`, the chosen difficulty and One Down). `ignore_chill_combat`: after the game's
  ignore, a new pending trip with `no_raid` (and the cover) goes on to the safehouse. Both do
  nothing for a contract opened from the game's own safehouse page.
- The raid's briefing is not passed (only `chill` is); after the raid ends offline the way home
  brings you back to the safehouse as after any job.
- Tests: `safehouse_tests.lua` 106 → 119 (2183 in total). Mutation test: 10 of 10 caught.

Defaults for the user to review: the raid is offered after an offline job too, not only at game
start; Back leaves you in the main menu.

## 0.30.2 (the armory opens the inventory)

- **`Home.OpenArmory()` (`safehouse.lua`):** in the safehouse it opens the inventory screen
  (`PDTI.SetUIOpen(true)`, checked with `PDTI.IsUIOpen()`); already open counts as done. New hook
  (tag `home`, installed by `Home.InstallGameHooks` each frame) on
  `AccessWeaponMenuInteractionExt.interact` (the racks `access_weapon_primary` /
  `access_weapon_secondary`): when the screen opened, it runs `BaseInteractionExt.interact` (the
  game's sound and triggers) and returns true without `open_in_game_loadout`; otherwise the game's
  weapon menu, as before. Not in `chill_combat`.
- Tests: `safehouse_tests.lua` 100 → 106, `hook_chain_tests.lua` fakes the armory class (2170 in
  total). Mutation test: 4 of 5 caught; the survivor (`opened` from `SetUIOpen`) is covered by the
  `IsUIOpen()` check after it.

Defaults for the user to review: both racks open the inventory screen, so the game's weapon menu
is not reachable in the safehouse any more (weapons are chosen in the main menu or a briefing).

## 0.30.1 (straight into the safehouse)

- **No main menu on the way (`safehouse.lua`):** `Home.DELAY` is 0 and the `MenuMainState.at_enter`
  hook calls `Home.MenuTick(0)` right after `Home.OnMenuMain`, in the same frame (vanilla does the
  same for `-level`). When a trip is planned, `Home.Cover(true)` plays a black overlay
  (`managers.overlay_effect:play_effect`, fade in 0, sustain 60 s, `Color.black`); it is stopped
  whenever you stay in the menu (another page, busy too long, the start failed, a hook error) and
  while a dialog is open. `Home.MenuState` now returns `"dialog"` for an open system dialog
  (`"wait"` stays for a busy save or a menu not up yet).
- **The safehouse's briefing is passed:** `Home.Go` sets `Global.pdti_home.skip_briefing` when it
  started the trip. New hooks (tag `home`) on `IngameWaitingForPlayersState.at_enter` (takes the
  mark: `self._pdti_auto` only in the safehouse, offline, option on) and `update` →
  `Home.BriefingTick`: `managers.menu_component:on_ready_pressed_mission_briefing_gui(true)` and
  `start_game_intro()`, then, once `_skip_promt_shown` and `_audio_started`,
  `hud:blackscreen_skip_circle_done()` + `_skip()` (vanilla's `-auto_enter_level` path). A failure
  is logged and the briefing is left to you. `OnMenuMain` clears a stale mark.
- `mod.txt` hooks `lib/states/ingamewaitingforplayers` → `hooks_home.lua`, which now also calls
  `Home.InstallBriefingHooks`; `main.lua` calls it too.
- Tests: `safehouse_tests.lua` 77 → 100 (2164 in total). Mutation test: 14 of 15 caught; the
  survivor is the guard before `start_game_intro`, which the game's own function repeats.

Defaults for the user to review: the briefing is passed only on the mod's own trips (not when you
use the menu's safehouse button); a dialog on the menu stops the black screen and waits up to 30 s.

## 0.30.0 (the safehouse as your base: safehouse phase 3 of 5)

- **`PDTI.InSafehouse()` (`inventory.lua`):** true when `managers.job:current_job_id() == "chill"`
  and `restoration` is nil (no pcall, no tables: called every frame). The raid `chill_combat` is a
  heist. In the safehouse the mod is in "menu" mode:
  - `PDTI.InHeist()` false (`ui_model.lua`), so the screen is the menu's (bring list, rig and
    backpack choice, buying, Captured, Stash) and `Plan`/`RequestEquip` are allowed.
  - `hooks_game.lua` does not set `session_only`: everything is saved.
  - `heist_start.lua` only loads the profile: no `Plan.StartRestock`, no `OnHeistStart` of any part.
  - New `Ammo.On()` (`settings.enabled` and not the safehouse) replaces the 14 reads of
    `Ammo.settings.enabled` in `ammo_hooks.lua`; `Ammo.SkipReason` returns "the safehouse", so every
    weapon is the game's own there; `Ammo.GameTick` only installs its hooks; `Plan.Bind` refuses.
  - `Loot.Tick` installs hooks and returns; `Dep.Manages`, `Dep.BlocksGame`, `Dep.Place`,
    `Dep.ItemToHandFor` and `Dep.OnHeistStart` are inert; the deploy HUD line is hidden;
    `Armour.StartPlate` refuses ("Not in the safehouse").
- **New `lua/safehouse.lua` (`PDTI.Safehouse`, loaded after stash):**
  - The way home: `Global.pdti_home = { booted, after_job }` (Global survives the Lua reload).
    `OnLevelStart` (from `heist_start.lua`) sets booted and clears after_job; the wrapped
    `MissionEndState.at_enter` (tag `home`) sets `after_job` when the job is not the safehouse and
    `Global.game_settings.single_player`; the wrapped `MenuMainState.at_enter` asks once
    (`OnMenuMain`: game start or after_job, option on, `Blocked` nil: no invite, no
    `load_start_menu_lobby`, no `exe_argument_level`, not online) and sets `Home.pending`; the
    wrapped `MenuMainState.update` runs `MenuTick`: after `DELAY` 1 s, when `MenuState()` is "ready"
    (no system dialog, save not busy, the selected node is `main`), `Home.Go` calls
    `MenuCallbackHandler:play_single_player()` and `start_single_player_job({ job_id = "chill",
    difficulty = "normal" })`, as the game's own "enter safehouse" does. A dialog or a busy save
    is waited for up to `GIVE_UP` 30 s; another node cancels.
  - New hook `lib/states/menumainstate` -> `lua/hooks_home.lua` (`InstallMenuHooks`; `main.lua`
    also asks, whichever is loaded second).
  - `Home.GameTick` (from `hooks_game.lua`): installs the end screen hook; once per visit, after
    `HINT_AFTER` 4 s in the safehouse, a hint about the inventory key and the bags waiting.
  - The probe: `Home.Probe()` on opening the inventory screen in the safehouse logs the
    player's position and up to 20 interactable units within 6 m, nearest first
    (`managers.interaction._interactive_units`: tweak id, `unit_data().unit_id`, position, name key,
    off or not).
- **Option** `safehouse_home` ("Start in the safehouse", on; `Ammo.settings`, saved in
  `issr_reload_settings.txt`).
- **Tests:** new `safehouse_tests` (77); `hook_chain_tests` checks the stash and the way home on
  the same `MissionEndState.at_enter` (8). 2141 checks. Mutation run: 33 of 33 caught (one missed
  at first, the `Dep.Place` guard: the test placed with an empty equipment object).
- **Defaults for the user to review:**
  - **Changed from the plan:** after a job with a crew there is no automatic trip (the plan
    said a safehouse lobby would open): it would pull the whole lobby along. Offline only.
  - A lost job also takes you to the safehouse; a job left before its end screen does not.
  - The world spots are not built: the probe comes first (the plan's order), because the units
    of the safehouse level are not known without looking in the game.
  - The weight still slows you in the safehouse (unchanged); it can be switched off there.
  - Weapons in the safehouse are the game's own, with the game's ammunition.
  - With restoration-mod the safehouse stays a heist and nothing starts there.
  - The delay of 1 s, the 30 s limit and the arrival hint (4 s after you spawn, 7 s long).


## 0.29.2 (fix: trip mines from the inventory as shaped charges)

- **Cause:** the shaped charge interaction (`MissionDoorDeviceInteractionExt`, `required_deployable
  = "trip_mine"`, `deployable_consume`) checks `PlayerManager:has_deployable_left` and takes one
  with `remove_equipment`; both read only the game's own equipment selections, where an
  inventory trip mine is not. `remove_equipment` also indexes the entry without a check (an
  error when the game has none).
- **`hooks_player_manager.lua`:** `has_deployable_left` is also true when an item of that
  equipment is to hand (`Dep.ItemToHandFor`: rig and pockets). `remove_equipment` takes the
  game's own when `Dep.GameCount` > 0 (vanilla placement, which also calls it, is unchanged),
  else consumes the inventory item (`Dep.Consume`, logged `[PDTI DEPLOY] used a trip_mine from the
  inventory`); with neither, it returns instead of erroring.
- **`deployables.lua`:** `Dep.ItemToHandFor(equipment_id)`, `Dep.GameCount(equipment_id, slot)`.
- **Tests:** `deployables_new_tests` +8. 2063 checks.
- **Defaults for the user to review:** the game's own trip mines are used before the inventory's;
  a backpack trip mine does not count.


## 0.29.1 (the captured loot choice on the end screen; FATAL on a thrown bag)

- **End screen (`stash.lua`):** `Stash.at_end_screen` is set by a successful capture.
  `Stash.Holding()` (end screen, bags pending, window not failed) makes the wrapped
  `MissionEndState._continue_blocked` return true and the wrapped `HUDStageEndScreen.update`
  skip stage 1 (`stage_money_counter_init`), so nothing is counted up or continued before the
  choice. Both open the window (`PDTI.SetCaptureOpen`). A sale on the end screen is added to
  `managers.money._bag_payout` (display only; the money is paid by `add_to_total`).
  Failsafe: no window / an error -> `window_failed`, nothing waits; "wait" (BeardLib makes the
  window on its next update) is retried for `WINDOW_TRIES` (600) frames.
  `Stash.InstallHooks` is called again at capture (the end screen classes exist then).
  Logs the game's bag payout after `at_enter`.
- **UI (`ui_beardlib.lua`):** a MenuUI of its own (`PDTI_Capture`, layer 1200, window
  `pdti_capture`, Center) with `draw_captured`, the stash space and the reason a bag did not
  fit; drawn smaller until it fits the screen; closes when nothing waits; keys S (stash all) and
  X (sell all now) while it is open. Stash buttons no longer sync guns or redraw the inventory
  when it is closed (`stash_after`).
- **Fix:** `PDTI.CarryExt(unit)` returns a unit's carry data or nil without raising (an error in
  a `pcall` is still logged as FATAL by the game). Used by the outline (`quality_of_unit`), the
  throw (`sync_carry_data`), pickup, the secure zone and `Loot`'s world bag checks. The user's
  log had `loot_quality.lua:279: attempt to index a nil value` from `server_drop_carry` ->
  `set_active` -> `set_contour`.
- **Tests:** `stash_tests` 57 (+16), `ui_tests` 136 (+19). 2055 checks. Mutation run on the hold and
  the window: 12 of 12 caught.
- **Defaults for the user to review:** the end screen waits only for bags of this job and any
  left from before (all must be chosen); S/X keys; about 10 seconds for the window to appear
  before giving up; a sale shows in the bags' payout line, a stashed bag shows nothing there.


## 0.29.0 (capture, stash and the bag payout: safehouse phase 2 of 5)

- **New `lua/stash.lua` (`PDTI.Stash`, loaded after loot_quality; hooks installed from
  `Loot.Tick`, tag `stash`):**
  - Own file `SavePath/pdti_stash.json` (`pdti_stash_profileN.json`), written at once also in a
    heist (`session_only` does not apply): `{version, next_id, bags[], pending[], known[]}`, a
    bag `{id, carry_id, quality, mods, value}`; sanitized on load (bad entries dropped, ids made
    unique).
  - Capture: wraps `MissionEndState.at_enter` (after the game secured the bags in hands).
    Success, not the safehouse (`chill` / `chill_combat`): stored inventory bags (amounts of a
    stack counted; none in custody, i.e. no player unit) every day; `managers.loot._global.secured`
    on the last stage (`managers.job:on_last_stage()`), only bags with a `bag_value`, not small
    loot, vehicles or `skip_exit_secure`. Failure: nothing, and `known` is cleared.
  - Known rolls: the bag in hands at the end (`LQ.HandsData`) and bags thrown into a secure zone
    (`ElementCarry.on_executed`, operations `secure`/`secure_silent`, host/offline) are kept in
    `known` and matched by carry id to secured entries; the others roll at capture.
  - Value: `managers.money:get_secured_bonus_bag_value(carry_id, 1)` x tier value (x1/x2/x4).
  - Payout: `LootManager.get_secured_bonus_bags_value` and `get_secured_mandatory_bags_value`
    return 0 unless `is_vehicle` (covers the payout and the end screen).
  - `Keep`, `SellNow` (x `SELL_NOW` 0.5), `Sell` (x `SELL_STORED` 1.0), `KeepAll`, `SellAllNow`;
    paid with `managers.money:add_to_total` (the game's spending/offshore split).
  - Space: `CELLS` 48, a bag 4, Compact 2, 4 Stackable bags of the same kind share a place.
- **UI (`ui_beardlib.lua`):** the menu's middle window gets tabs (`draw_shop`): Captured (opens
  first while bags wait; per bag Stash / Sell, Stash all / Sell all now), Stash (list, total,
  Sell), Bring list. Rows coloured by quality (`line` takes a `foreground` colour).
- **Tests:** new `stash_tests` (41); `ui_tests` +10 (117); `hook_chain_tests` covers the stash
  hooks (7). 2020 checks. Mutation run on `stash.lua`: 20 of 20 caught (two missed at first,
  small loot with a carry entry and a stack of bags in the inventory; tests added).
- **Defaults for the user to review:**
  - The stash is a list with room counted in grid places (12 bags), not a grid you drag bags
    in; a grid can come with the safehouse screens (0.30.0).
  - Sell from the stash pays 100% of the value until the market (0.31.0).
  - Sale money is split like a heist payout (most of it offshore). The alternative is all to
    spending cash.
  - Mandatory bags (the job's objective bags) are captured too and no longer paid.
  - A bag left unchosen waits in Captured (it does not go to the stash on its own, because the
    stash can be full).
  - Co-op: as a client, a bag you threw into the secure zone rolls again at capture (the
    secure runs on the host); the host's capture is the one tested.
  - Multi-day jobs: inventory bags are captured at the end of each day, even if a later day is
    lost.


## 0.28.2 (thrown bags of quality are outlined)

- **`loot_quality.lua`:** wraps `CarryInteractionExt.set_contour` (the class gets its own
  `set_contour` that calls `CarryInteractionExt.super.set_contour` on each call, so a later hook
  on the base class still applies, then `PDTI.Wrap` tag `loot_quality`). For a bag unit whose
  carry data has `_pdti_quality` 2 or 3, any colour but `selected_color` paints the materials'
  `contour_color` with `LQ.OUTLINE` (High 0.25/0.55/1.0 blue, Exceptional 1.0/0.75/0.1 gold) and
  `contour_opacity` 1; `selected_color` (looking at it) stays the game's. `LQ.OutlineUnit` paints
  a bag right after the throw (`sync_carry_data`). Colours are cached `Vector3`s.
- **Tests:** `loot_quality_tests` checks gold and blue outlines, always visible, the game's
  selected outline while looked at, and a Standard bag unchanged (49). 1968 checks.
- **Defaults for the user to review:** colours match the inventory cells (blue, gold); the
  outline is on all the time, also far away; only bags you threw (the roll lives on your side),
  so a friend's thrown quality bag is not outlined for you.


## 0.28.1 (fix: no sign of a bag's quality in the heist)

- **`loot_quality.lua`:** `LQ.Stamp` shows a hint (`PDTI.Hint`, `LQ.HINT_TIME` = 5 s) with
  `LQ.Describe` for quality 2 and 3 when a bag comes into your hands from the world (a new roll
  or a bag picked up again). The log line now also covers a bag picked up again:
  `[PDTI LOOT] <carry id> picked up again: <quality> (<mods>)`.
- Found from the user's 0.28.0 log: 22 diamond rolls (16 Standard, 5 High, 1 Exceptional), but
  the quality was only visible in the inventory screen.
- **Tests:** `loot_quality_tests` checks the hint for a High quality bag, once, and none for a
  Standard bag (43). 1962 checks.
- **Defaults for the user to review:** the hint stays 5 s; it repeats each time the bag comes
  from the world into your hands (not when it comes out of your inventory).


## 0.28.0 (loot quality: safehouse phase 1 of 5)

- **New `lua/loot_quality.lua` (`PDTI.LootQuality`, loaded after loot):** a bag rolls on first
  pickup (`LQ.Roll`: Standard 0.80 x1 / High 0.17 x2, 1 modifier / Exceptional 0.03 x4, 2
  different modifiers; `LQ.random` replaceable). Item data gets `quality` (1-3), `mods`
  (comma string, fixed order `LQ.MOD_ORDER`), and for Compact `w`/`h` = 2x1, for Stackable
  `max_stack` = 4. Logged once per roll: `[PDTI LOOT] <carry id> rolled <quality> (<mods>)`.
  Off when `restoration` exists.
- **Keeping the roll:** `PlayerManager.drop_carry` / `force_drop_carry` remember the bag in hands;
  `PlayerManager.sync_carry_data` (where the game makes the thrown bag, for the local peer) puts
  the roll on the unit's carry data (`_pdti_quality`); `CarryInteractionExt.interact` takes it
  back on pickup (`LQ.ForPickup`); `Loot.Tick` stamps a new hands item with it (`LQ.Stamp`), or
  rolls when the bag had none. Hooks via `PDTI.Wrap` (tag `loot_quality`), installed from
  `Loot.Tick`.
- **Modifiers:** Runner (`PlayerCarry._check_action_run` -> the standard state's, eligible only
  for `can_run == false`), Nimble (`PlayerCarry._perform_jump` without the jump modifier,
  eligible only for `jump_modifier < 1`), Light (`Carry.LootFactor` counts 0.5 of the bag),
  Compact, Discreet (the thrown unit's attention removed, as the game does on a zipline),
  Balanced (throw `dir` x1.5, not on a zipline), Quick hands (`_carry_blocked_cooldown_t = 0`
  after the throw), Padded (`PlayerManager.modify_value("damage_taken")` x0.85 while any carried
  bag has it), Stackable.
- **`inventory.lua`:** `def.size_by_data` (an item's own `data.w`/`data.h`) and
  `def.stack_by_data` (`data.max_stack`), used by the loot bag; `PDTI.ItemMaxStack(def, data)`
  in `AddItem`, `EditItems` set_amount, `MergeStacks` and the load; `PDTI.SameItemData`.
- **`loot.lua`:** `Loot.StackOnto` / `Loot.TryStack` (a stored stackable bag joins a stack of
  the same bag), `Loot.TakeOut` from a stack takes one bag into its own place,
  `Loot.QUALITY_FIELDS`; a different bag in hands gets its own roll.
- **UI:** cell label `Bag HQ` / `Bag EX` (and `xN` on stacks), High blue, Exceptional gold; the
  held item line shows kind, quality and modifiers (`LQ.Describe`).
- **Tests:** new `loot_quality_tests` (39); `hook_chain_tests` covers the new hooks (6); the
  test environment rolls Standard unless a test sets `LQ.random`. 1958 checks. Mutation run:
  17 of 18 mutants caught (the missed one, `Roll` not sorting, is equivalent: `Apply` sorts).
- **Defaults for the user to review:**
  - Modifier strengths: Light 50% of the slowdown, Balanced x1.5 throw, Padded -15% damage,
    Stackable 4, Compact 2x1. Several bags with the same modifier do not add up.
  - "Use items while holding" (from the handling idea) is not built: the use key throws the
    bag in the game's carry state; Handling is Balanced + Quick hands.
  - Stealth: carrying a bag adds no detection in vanilla, so Discreet works on the thrown
    bag (guards do not notice it). It only works where you host or play offline (the host's
    guards).
  - The quality is per player and not synced: another player rolls their own.
  - The value multiplier is stored now and paid from 0.29.0 (stash, instant sale).


## 0.27.4 (clean-up and per-frame speed; no gameplay change)

No numbers, hook targets, save format, settings keys, log or hint texts changed. Measured in an
offline harness (mock game, one typed rifle): the per-frame tick went from about 60 µs and
16.3 KB of garbage to about 40 µs and 5.9 KB.

- **Shared helpers in `inventory.lua`:** `PDTI.Wrap(store, tag, class, fn, make, key)` (the
  `HookHas`/`HookMark` wrap every module had its own copy of), `PDTI.WrapKey`,
  `PDTI.Logger(prefix)`, `PDTI.Hint(text, time)`, `PDTI.AppTime()`, `PDTI.GameTime()`,
  `PDTI.PlayerUnit()`, `PDTI.PlayerDamage()`, `PDTI.FindFirstItem(predicate)`. armour, body,
  carry, loot, ammo, ammo_hooks, ammo_hud, loadout, skills, skills_ap and others use them.
- **Removed (no callers):** `Ammo.InFamily`, `Ammo.IsShotgun`, `Ammo.AddMagazine`,
  `Ammo.InstalledRoom`, `Ammo.JobActive`, `Dep.SuppressVanillaDeploy`, `Loadout.TotalWeight`,
  `Plan.ResetCache`, an unused local in deployables.lua.
- **Per frame, no garbage where there was some:**
  - `Ammo.ForEachWeapon` sorts into reused scratch lists (same order: highest selection first)
    instead of building tables and a sort closure; it always clears them, also when the game
    raises an error, and passes that error on as before. `EnsureAllSupplies` uses a static
    function.
  - `Skills.Install` and every skill module (skills_ammo, doctor_buffs, skills_brawler,
    skills_medic, skills_ghost, skills_ap, skills_silent, perk_yakuza, skills.lua), carry and
    armour: the hook makers and the functions handed to `Body.mods`, `Ammo.*`,
    `round_speed_mods` and `Carry.relief` are built once at load instead of every frame. The
    installers still run every frame. `Body.mods.recoil` and `.spread` are now one function.
  - `Loot` finds the bag in your hands with `PDTI.FindFirstItem` instead of listing all bags.
  - `ammo.lua`: `EquippedUnit`, `IsSecondGun`, `SlotOf`, `SizeClass`, `FeedMode` without
    per-call closures or tables; `ParseLoad`, `FilterLoad`, `LoadString` in one pass;
    `SyncGunSlot` no longer identifies the gun twice.
  - `carry.lua`: the `movement_speed_multiplier` hook has no per-call closures.
- **Simplified:** `body.lua` `push_health` (revive, `HealHead`, `HealPart`); `ammo_hooks.lua`
  `parent_base`, `player_time`; `ammo.lua` `magazine_items`, `top_up_stack`; `inventory.lua`
  `commit_deployable`; `ui_beardlib.lua` `kind_ids`.
- **Tests:** `akimbo_tests` checks `ForEachWeapon`'s order, error pass-through and clean-up (54);
  `ammo_conservation_tests` compares the old and new load helpers on 400 random loads and checks
  that the gun slot follows the gun for a rifle and akimbo (13). 1918 checks.
- **Defaults for the user to review:**
  - `SyncGunSlot` still rebuilds the gun's data every frame (about 2.2 KB per gun): a "nothing
    changed" shortcut was rejected because the loaded magazine is changed in place by firing and
    other mods change weapon fields.
  - Functions only named in the docs (`Body.Summary`, `PDTI.LogDiagnostics`,
    `PDTI.MergeStacks`, `PDTI.RegisterEquipment`, `PDTI.UnregisterItemUse`,
    `PDTI.RequestRotate`, `PDTI.RefreshUI`) were kept as console/public API.

## 0.27.3 (fix: the Laser Chronometer is a throwable)

- **`loadout.lua`:** `Loadout.Weightless` now applies to the throwable (id, `name_id`, name), not
  to the weapons: a match weighs 0 per piece. It weighed `DEFAULT_THROWABLE` (0.4 kg) x 30.
  Logged once: `[PDTI LOADOUT] throwable <id> (<name>) weighs nothing`. The weapon check of
  0.27.2 is removed.
- **Tests:** `speed_tests` checks the chronometer as a throwable of 30 pieces (0 kg, nothing in
  the load) and that another unknown throwable keeps 0.4 kg a piece (39). 1903 checks.

## 0.27.2 (fix: the Laser Chronometer weighed 12 kg)

- **`loadout.lua`:** `Loadout.WEIGHTLESS = { "chrono" }` and `Loadout.Weightless(...)`: a weapon
  whose id, `name_id` or localized name contains it (any case, plain text) weighs 0. It is
  logged once (`[PDTI LOADOUT] <id> (<name>, categories ...) weighs nothing`), so the real id
  shows in the game log. The Espionage Weapon Pack (2026) is newer than the vanilla source dump
  used here; its category gave 12 kg (the flamethrower's weight at concealment 0).
- **Tests:** `speed_tests` checks the match and a chronometer in a 12 kg category in the
  loadout and the load (37). 1901 checks.
- **Defaults for the user to review:** matched by "chrono" in the id or name until the real
  weapon id is known from the log.

## 0.27.1 (Sneaky Bastard without a cap)

- **`skills_ghost.lua`:** `G.VelocityDodge()` is `DODGE_MAX x speed / ref`, no longer capped at
  `DODGE_MAX` (0.10). A NaN or infinite speed reading gives 0. New skill text.
- **Tests:** `ghost_skills_tests` checks the uncapped dodge (900 cm/s, 4x sprint = 40%), the ace
  above run speed and the broken readings (43). 1898 checks.
- **Defaults for the user to review:**
  - The rate stays: 10% at the base sprint speed (ace: base run speed), linear above it.
  - Only the horizontal speed counts (`_last_velocity_xy`), so falling adds nothing; ziplines,
    speed boosts and other fast movement do.
  - Nothing limits the total: with other dodge (armour, Duck and Cover, perk decks) it can come
    close to 100% at very high speed.

## 0.27.0 (Yakuza by black limbs; Extra Heist Info buffs)

- **New `lua/perk_yakuza.lua` (`PDTI.Yakuza`):** wraps `PlayerManager.get_damage_health_ratio`
  (id `yakuza`): for the categories `armor_regen` and `movement_speed`, with the deck and
  health per body part, it returns `min(1, black limbs / 4)` (`/ 2` with card 9's threshold
  upgrades) instead of the health-based ratio. The game's formulas stay
  (`body_armor_regen_multiplier`, `movement_speed_multiplier`). New texts for the deck and
  cards 1, 3, 5, 7, 9.
- **New `lua/ehi_buffs.lua` (`PDTI.EHIBuffs`):**
  - On EHI's `BuffsInit` callback it adds buff definitions to `tweak_data.ehi.buff`
    (`PDTI_Barrier`, `PDTI_BarrierCooldown`, `PDTI_Doctor`, `PDTI_Painkillers`, `PDTI_Overheal`,
    `PDTI_Momentum`, `PDTI_Ignite`; icons from `tweak_data.skilltree.skills[id].icon_xy`).
  - It patches `EHIYakuzaBuffTracker.UpdateValue` and `EHIBerserkerBuffTracker.PreUpdate` /
    `UpdateValue` to read `PDTI.Yakuza.Scale()` and `PDTI.Brawler` while the reworks are in
    force (EHI's Berserker deleted itself before, since the vanilla upgrades are off).
  - `E.Poll()` runs from the game hook (every 0.1 s) and pushes the values with
    `managers.ehi_buff:AddBuff` / `AddGauge` / `RemoveBuff`. A timer is set again only when it
    is renewed; EHI counts it down.
- **Loading:** `main.lua` loads `perk_yakuza` and `ehi_buffs` after `skills_brawler`.
  `hooks_game.lua` calls `EHIBuffs.Poll` after `Body.UpdateHud`.
- **Tests:** new `tests/yakuza_ehi_tests.lua` (49). 1894 checks. 10 mutations, all caught.
- **Defaults for the user to review:**
  - "Limbs" = both arms and both legs; the body and the head do not count (Berserker counts the
    body).
  - Linear: a quarter of the bonus per black limb; card 9 = the full bonus at 2 black limbs
    (vanilla's card 9 doubled the health range).
  - Vanilla's low-health side is gone entirely: low health with no black limb gives nothing.
  - With Frenzy the deck starts at its full bonus (Frenzy's limbs start black).
  - Black limbs also stop the crew's health regeneration (`team.crew_health_regen`), as
    vanilla's low health did.
  - EHI: the new buffs have no on/off option in EHI's menu (always shown when in force);
    Unseen Strike's stored rounds are not shown.

## 0.26.1 (fix: skill texts)

- **`skills.lua`:** `Skills.TEXT_KEYS` holds the skills whose text ids in the game are not
  `menu_<id>_beta`: `optic_illusions` (`menu_optic_illusions`), `hitman`
  (`menu_spotter_teamwork_beta`), `frenzy` (`menu_frenzy`). `Skills.Text` uses it.
  Before this, Optical Illusions and High Value Target kept the vanilla text in the skill tree.
  Every other reworked skill was checked against `skilltreetweakdata.lua`.
- **Tests:** `silent_killer_tests` checks the two text ids (71). 1845 checks.

## 0.26.0 (skill rework, phase 5: Shinobi, Artful Dodger, Berserker, Frenzy)

- **New `lua/skills_ghost.lua` (`PDTI.GhostSkills`):**
  - Cleaner ace sets `bodybags_bag.h = 1`, ECM Specialist basic sets `ecm_jammer.max_stack = 2`
    (both on Install, with deployables on).
  - Cleaner ace wraps `PlayerCarry._check_action_run` / `_get_max_walk_speed` (id `cleaner`)
    for the `being` carry type.
  - Inner Pockets ace: `PDTI.PocketsBig` (pockets `PDTI.POCKETS_BIG` 2x3 / 6 kg).
  - Sneaky Bastard: `player.detection_risk_add_dodge_chance` off, and a wrap of
    `PlayerManager.skill_dodge_chance` (id `dodger`) adds `0.10 x min(1, speed / ref)`. The speed is the
    player state's `_last_velocity_xy`; ref is `RUNNING_MAX` (575), or `STANDARD_MAX` (350) with the ace.
  - `GhostSkills.Tidy()` (inventory open and heist start) splits stacks above the limit and
    moves items that no longer fit where they are.
- **New `lua/skills_brawler.lua` (`PDTI.Brawler`):**
  - Berserker: `melee_damage_health_ratio_multiplier`, `damage_health_ratio_multiplier` off. Wraps
    (id `berserker`) on `CopDamage.damage_melee` and, with the ace, `CopDamage.damage_bullet` /
    `SentryGunDamage.damage_bullet` scale the player's hits.
  - Frenzy: `player.max_health_reduction` off, and `player.health_damage_reduction` with the ace
    reads as the basic's.
- **`body.lua`:**
  - `Body.mods.part_max(id, max)` and `Body.mods.start_black(id)` (Frenzy), and `Body.ShareMax`.
  - A fresh start (heist, custody) applies `start_black`; `RestoreAll` (doctor bag) does not.
  - When parts start black, the game's health drops to the parts' sum.
- **`inventory.lua`:** `PDTI.POCKETS` / `POCKETS_BIG`, read through `PDTI.PocketsBig`.
- **`skills.lua`:** `Skills.Text(id, desc, name, key)` takes a raw text id (`menu_frenzy`).
- **Defaults for the user to review:**
  - **Cleaner ace:** walking with a body stays at the game's 50%; running is 70% of the run speed.
    Vanilla's extra body bag stays.
  - **Inner Pockets ace:**
    - the 2 cells are a third pocket row, and the pockets' weight cap goes from 4 to 6 kg;
    - vanilla's vest concealment is kept;
    - "no restrictions" = with any armour.
  - **Sneaky Bastard:**
    - both levels top out at vanilla's 10%;
    - the basic reaches it at the base sprint speed, the ace at the base running speed;
    - it needs the weight system;
    - the menu's stat screen shows no speed dodge.
  - **Berserker:** "ranged" = bullets (enemies and turrets), not grenades, fire or the HE blast. A
    black part whose penalties Painkillers ace holds off still counts.
  - **Frenzy:**
    - vanilla's slower healing and the basic's 10% damage reduction stay; the ace's 25% becomes 10%;
    - the parts start black again after custody;
    - black legs (no sprinting) and arms (recoil) apply from the start until a doctor bag.
  - **Before the skills can be read** (a save loaded in the menu), the pockets, the ECM stack and the body
    bag case take their skill sizes, so nothing is cut at load. The tidy step puts them right later,
    and what finds no room stays where it is (a hint says so).
- **Tests:** new `ghost_skills_tests` (39) and `brawler_tests` (43). 1844 checks.

## 0.25.0 (skill rework, phase 4: Silent Killer, Surefire, Body Expertise)

- **New `lua/skills_silent.lua` (`PDTI.SilentKiller`):** Silent Killer as in the guide. One observer
  (id `silent`) on `CopDamage.damage_bullet/explosion/fire/melee` and `SentryGunDamage.damage_bullet/
  explosion` sees the player's hits and kills; `CopDamage.check_medic_heal` (Optical Illusions ace),
  `CopActionHurt.init` (concussion and sickness length), `PlayerManager.movement_speed_multiplier`
  (Momentum). Switched off with the ammo system on: `player.team_damage_speed_multiplier_send`,
  `camouflage_bonus`, `silencer_concealment_penalty_decrease`, `silencer_concealment_increase`,
  `weapon.silencer_recoil_index_addend`, `silencer_enter_steelsight_speed_multiplier`,
  `silencer_spread_index_addend`, `player.detection_risk_add_crit_chance`, `marked_enemy_extra_damage`,
  `marked_inc_dmg_distance`, `unseen_increased_crit_chance`.
- **New `lua/skills_ap.lua` (`PDTI.Barrier`):** the Stacked Barrier; it soaks in a hook on
  `PlayerManager.modify_value("damage_taken")` (after dodge, before armour). Switched off:
  `player.automatic_mag_increase`, `player.ap_bullets`.
- **`ammo_hooks.lua`:** `Ammo.hp_crit_any` (HP crits beyond limbs), `Ammo.SureCrit` /
  `Ammo.on_sure_crit` (HP limb and HE dozer/turret crits), `Ammo.on_he_stun`.
  **`ammo.lua`:** `Ammo.BlastRange` (`Ammo.blast_mul`); `no_ap_skill` removed (hollow points leave
  `_use_armor_piercing` as the weapon has it).
- **`body.lua`:** `Body.HealPart(id, amount)`, `Body.lines` (extra lines in the health window).
- **`skills_ammo.lua`:** a `loose` spoil kind; `AmmoSkills.box_extra` (rounds an ammo box carries
  for you) taken with a standard box, and by the bag path while the box stays.
- **Defaults for the user to review:**
  - HE is the LMG's HE round (shotgun HE shells keep the game's explosion and take no part).
  - Optical Illusions ace: any crit kill, not only HP.
  - "Stunned" (The Professional ace) = concussed by your HE; the +20% is on the damage this
    machine works out (yours; on the host also bots' and turrets').
  - Low Blow basic: 2% of the part's maximum to your more hurt arm (arm hit) or leg (leg hit),
    per hit. Ace: the Medic only (not the Medic Dozer); the sickness is the game's ECM-feedback
    stun, held 4 s on the machine that runs the enemy (as a client the host's length applies).
  - Ignition: the Dragon's Breath fire damage.
  - Unseen Strike basic: the round lies in a box like the Spoils (walk over it). Ace: standard
    rounds store nothing; only damage that gets past the barrier clears the store.
  - Second Wind ace: only a special bullet; not for akimbo guns.
  - Barrier: the screen's units (10 = 1.0 of the game's health); the cooldown starts only when
    it fades by time (used up by damage it builds again at once); Body Expertise alone uses
    Surefire basic's cap, fade and cooldown; falls are not soaked.
- **Tests:** new `silent_killer_tests` (70) and `barrier_tests` (42); `typed_ammo_tests` updated
  for `no_ap_skill`. 1762 checks.

## 0.24.0 (skill rework, phase 3: Enforcer, Ammo Specialist)

- **New `lua/skills_ammo.lua` (`PDTI.AmmoSkills`):** the Ammo Specialist branch and R8 as in
  the guide. Hooks: `AmmoBagBase.spawn` / `sync_setup` (the owner's peer id), `_take_ammo`
  (Reserve Charge), `take_ammo` (Hot Swap), `CopDamage.die` / `drop_pickup` (Spoils, one-shot
  kills), `AmmoClip._pickup` (spoils, R8), `NewRaycastWeaponBase.fire` (the shot) and
  `reload_speed_multiplier`, `BaseInteractionExt._get_timer` (bag take). Switched off with the
  ammo system on: `player.double_drop`, `temporary.no_ammo_cost(_buff)`, the saw's stat upgrades,
  `player.extra_ammo_multiplier`, `pick_up_ammo_multiplier(_2)`, `regain_throwable_from_ammo`;
  levels: `player.no_ammo_cost` 0 (Bulletstorm), `ammo_bag.ammo_increase` 1 (Extra Lead).
- **`lua/skills.lua`:** `Skills.wrap(class, fn, make, id)` (several wraps of one function),
  `Skills.Level` (a hook on `PlayerManager:upgrade_level`), `Skills.Known`.
- **New container `pouch`** (`inventory.lua`, `PDTI.POUCH`, 2x2, loose rounds only, no room
  without Fully Loaded; kept while the skills can't be read yet); in `Ammo.ACTIVE`/`STORAGE`
  first; `AddLooseKey` fills it first; `LooseStacks` lists it first; the screen shows it
  after the pockets.
- **`lua/ammo.lua`:** `Ammo.round_speed_mods` (composed; the doctor buff moved there),
  `Ammo.EjectRounds` (`Ammo.eject_rounds`), `Ammo.PickupRange` (`Ammo.pickup_range_mul`).
  **`ammo_hooks.lua`:** the reload takes the next magazine before a refilled old one goes
  back; packing from the pouch without holstering (`Ammo.PouchPackAllowed`).
- **`deployables.lua`:** placing an `ammo_bag` item passes its data (`uses`) to the skills.
- **Defaults for the user to review:**
  - The saw stays unlockable as a secondary (saved loadouts keep working); only its stat
    upgrades are off.
  - Clean Swap refills for free (no bag ammo used); a magazine dropped by a double tap is
    not refilled.
  - Hot Swap skips akimbo guns.
  - Reserve Charge applies to your own takes from your own bag; "no loaded magazine" means no
    magazine with rounds for the gun in your hands anywhere in the inventory (the gun's own
    clip doesn't count).
  - Spoils: an ammo box with the `deployable_selected` outline, only on your screen
    (teammates see the enemy's normal drop). The Phalanx shield counts as a Shield, the
    Medic Dozer as a Medic. The counter resets each heist. Taser/Marshal magazines are the
    drum / standard size of your AR/SMG (75 / 30 for a 30-round gun); without an AR/SMG the
    rounds come loose for the gun in your hands.
  - The Cloaker's throwable is the `grenade` item; the Dozer's bag is an `ammo_bag` item
    with 1 use (set on the bag that appears within 5 s; the difference is synced to peers).
  - Auto-load: kills within 1 s of the shot count; magazines in the rig only.
  - On the Move: the gun stays in hand; shooting, aiming or reloading stops it.
  - Pouch leftovers go to the backpack (else anywhere; what fits nowhere is left behind) when
    the inventory opens or a heist starts. The pouch holds up to 8 kg.
- **Tests:** new `ammo_specialist_tests` (110). 1650 checks.

## 0.23.0 (skill rework, phase 2: the frame + Mastermind Medic)

- **New `lua/skills.lua`:** `Skills.Step(id)` (`managers.skilltree:skill_step`), `Basic`/`Ace`,
  `Skills.Off(cat, upgrade, when)` and `Skills.Override(cat, upgrade, fn)` applied in hooks on
  `PlayerManager:upgrade_value` / `has_category_upgrade`, `Skills.Text` (`menu_<id>_beta_desc`
  through `LocalizationManager:add_localized_strings` and `LocalizationManagerPostInit`),
  `Skills.OnInstall`. Off with restoration-mod. Installed from `main.lua`, the playermanager and
  blackmarketmanager hooks and the heist hook loop.
- **New `lua/skills_medic.lua`, `lua/doctor_buffs.lua`:** the Medic branch as in the guide.
  Switched off: `player.revive_health_boost` (Combat Medic ace), `first_aid_kit.damage_reduction_upgrade`
  (Quick Fix ace), `player.revive_damage_reduction_level` (Painkillers); `first_aid_kit.deploy_time_multiplier`
  is 1 while the armour is up (Quick Fix).
- **`lua/body.lua`:** `Body.mods` hook points (`spill_rate`, `revive_head_full`, `auto_revive_full`,
  `overheal_cap`, `suspend_time`, `recoil`, `spread`, `stamina`, `on_doctor_bag`, `buff_line`);
  `Body.SpillRate`, `Body.Over` (overheal, taken first in `hit_part`), `Body.Suspended` /
  `Body.Penalized` (`state.black_at`), `Body.ReviveHeadHP`, `Body.HealHead`; hooks on
  `band_aid_health` (a kit's heal may overheal; inside `_check_bleed_out` the black head first
  gets the revive value) and `_check_bleed_out`; `recover_health` reports the black parts it
  healed, `replenish` does not.
- **`lua/carry.lua`** `Carry.LoadRelief` (`Carry.relief`), **`lua/ammo.lua`** `Ammo.RoundInterval`
  (`Ammo.round_speed`).
- **Fix:** the Uppers auto-revive with a black head left the player at 0 health (the kit heals
  only parts that are not black).
- **Defaults for the user to review:**
  - Combat Doctor basic: the on/off effects become 50% (calm: half the shake; shrug off: half
    of the tases ignored, flashbangs half as long; steady legs: 75% of the push).
  - Any `recover_health` is a doctor bag (the medical rig's medic bag too); `replenish` is not.
  - Second wind relieves the load's slowdown only (not the loot bags').
  - Steady legs scales the melee push (the game's only push on the player).
  - Overheal and the buff are shown in the health window ("Overheal: +N", "Doctor's orders").
  - Combat Medic "revive someone" is the revive interaction (not freeing a cuffed player).
  - An auto-revive also heals the head to full with Combat Medic ace (being revived).
- **Tests:** new `medic_tests` (83). 1540 checks.

## 0.22.1 (fix: weight → concealment in the heist; vanilla only)

- **Fatal error in the log at spawn:** the game calls `get_suspicion_offset_of_local` while it
  spawns the player. R4's `visibility_modifiers` hook read the weight, `Loadout.Get` asked
  `PlayerManager:get_grenade_amount(peer)` before `_global.synced_grenades[peer]` existed
  (playermanager.lua:5366, "attempt to index a nil value"). The game logged it as a fatal
  error even inside pcall, and the penalty became 0 for the suspicion the game computed then.
  - `loadout.lua`: the count is read only when `synced_grenades[peer]` exists.
  - `Rules.ConcealmentPenalty` returns nil when the weight cannot be read, and
    `Rules.CurrentPenalty` keeps the last value then.
- **Menu:** `Rules.RefreshMenuDetection` redraws `PlayerInventoryGui:update_detection` when
  the inventory screen closes.
- **R4 is vanilla only** (`Rules.Restoration()`), like R3. This replaces the 0.22.0 default.
- **Tests:** `core_rules_tests` 37.

## 0.22.0 (skill rework, phase 1: core rules)

- **R1, `lua/body.lua`:** `spread_even` replaced by `Body.SpillTarget(from)` + `spill`:
  damage on a black part and the overflow of a part going black go at
  `Body.EFFECTS.spread_damage` (0.75, was 0.7) to the body; with the body black, or from
  the body, to the head; with both black nowhere. Explosions spill their black shares the
  same way.
- **R3, new `lua/skill_rules.lua`:** `Rules.ApplyEcm` scales `ecm_jammer_base_battery_life`,
  `ecm_jammer_base_low_battery_life` and `ecm_feedback_min/max_duration` by
  `Rules.ECM_FACTOR` once (the originals are kept in `tweak_data.upgrades._pdti_ecm`). Skipped
  when restoration-mod is loaded (`Rules.Restoration`).
- **R4:** `Rules.ConcealmentPenalty` (`floor((kg - Carry.FREE_WEIGHT) / CONCEAL_STEP)`,
  cached per inventory revision) is added to `BlackMarketManager:visibility_modifiers`.
  Installed from `main.lua`, from the new `lib/managers/blackmarketmanager` hook
  (`lua/hooks_rules.lua`) and in the heist's hook loop. Off with `Carry.enabled = false`.
- **Defaults for the user to review:**
  - ECM factor 0.5: jammer 10 s, 15 s with both duration skills. The feedback uses the same
    factor (7.5-10 s); with both feedback boosts its maximum is 15.6 s, not 15 s.
  - R4 also applies with restoration-mod (only R3 is vanilla-only).
  - What the head cannot take (a headshot over its HP) also goes on to the torso. You are
    down either way.
- **Tests:** new `core_rules_tests` (31); `body_tests` updated to the new spill (60).

## 0.21.5 (HE: concussion vs people, anti-armour vs bulldozers and turrets)

- `explosive.heavy_mul = 4`: `Ammo.HeCrit`'s sure-crit branch (turrets, bulldozers) gives
  `damage * heavy_mul * crit_mul`. `explosive.stun_chance = 1` (was 0.35);
  `dozer_stun_chance` stays 0.
- **Tests:** `lmg_ammo_tests` (54).

## 0.21.4 (crash fix: HE crit roll)

- **Crash:** `Ammo.HeCrit` called `dmg_ext:roll_critical_hit(attack_data)`. The current
  game's `CopDamage:roll_critical_hit(attack_data, damage, ...)` does arithmetic on `damage`
  without a fallback, so it raised "arithmetic on local 'damage' (a nil value)"
  (copdamage.lua:2672). The error inside the explosion's pcall chain still ended in a fatal
  error / access violation (crash.txt, 2026-11-11 16:07).
- **Fix:** new `Ammo.RollCrit` (with `Ammo.crit_roll`): `can_be_critical`, then
  `critical_hits.base_chance + managers.player:critical_hit_chance() *
  player_chance_multiplier`. The game's roll is not called by the HE crit any more.
- `make_crit_hook` (hollow points) takes the damage and the cap the game passes in.
- **Tests:** `lmg_ammo_tests` (52). The mock explosion passes the damage as the current game
  does, and a strict enemy roll records a call without it.

## 0.21.3 (ammo bag fix, box limit, HE stun)

- **Ammo bag (`make_bag_hook`):** for weapons without the magazine restock (loose-fed), the
  game's `add_ammo_from_bag` sees `min(total, get_ammo_max())`. restoration-mod computes
  `wanted = 1 - total / max`, negative above the maximum, so `took` was negative and
  `AmmoBagBase:_take_ammo` *added* it to `_ammo_amount`. The total is restored with what was
  added, and a negative result is returned as 0. The restock path divides the share by the
  weapon's `_ammo_ratio` and multiplies the share used by it, as restoration-mod's
  `process_ammo` does. Gadget results are never negative.
- **Boxes:** `Ammo.BOX_STACKS = 2`, `Ammo.BoxLimit()` (2 x the loose stack size),
  `Ammo.BoxRoom(wep)` (limit minus the weapon's loose rounds, all bullets) caps
  `add_ammo` without an amount override. `Ammo.BoxesFull(unit)`; a new `AmmoClip._pickup`
  hook (`LATE_HOOKS`, wrapped once the class exists) returns false for a plain box (no
  `_projectile_id`, no `_weapon_category`) when every managed gun is full.
- **HE stun:** `explosive.stun_chance = 0.35`, `dozer_stun_chance = 0`. After
  `CopDamage.damage_explosion` of a marked HE blast, `Ammo.HeStun` calls the game's
  `stun_hit` (variant "explosion", the blast's `col_ray`) on a living non-civilian, by
  `Ammo.stun_roll()`.
- **Tests:** new `tests/bag_box_tests.lua` (23); `lmg_ammo_tests` (48).

## 0.21.2 (HE rounds crit; always on bulldozers and turrets)

- **`ammo.lua`:** the `explosive` round has `blast_crit` and `sure_crit`. The HE bullet
  class from `Ammo.ExplosiveClass` overrides `on_collision_server`: while the game's blast
  runs, `Ammo.he_blast = { weapon, user }` (restored afterwards, also on an error).
- **`ammo_hooks.lua`:** `Ammo.HeCrit` runs before `CopDamage.damage_explosion` and
  `SentryGunDamage.damage_explosion` for an attack by the player with the marked weapon.
  On a turret or a bulldozer (`_tweak_table` starting with "tank", or the "tank" tag) it is a
  sure crit (`critical_hits.damage_mul`, else `headshot_dmg_mul`, else
  `Ammo.HE_CRIT_MUL` = 2). Elsewhere it uses the game's `roll_critical_hit`. It sets
  `attack_data.damage`, `critical_hit` and `_pdti_crit_decided`, and shows the crit
  marker. The `roll_critical_hit` hook returns no crit for a decided attack, so vanilla's
  own roll in `damage_explosion` does not crit a second time.
- **Tests:** `lmg_ammo_tests` (43).

## 0.21.1 (no weight cap in the rig)

- **`inventory.lua`:** `container_weight_limit` returns `math.huge` for every rig section
  (`RIG_INDEX`), so moves, adds, auto-placement, loot and the plan never refuse a rig by
  weight. The sections' `max_weight` stays in the definitions (other mods' rigs are still
  validated with it) but is not a cap. Pockets and backpacks keep theirs.
- **`ui_beardlib.lua`:** the weight line shows "Rig <kg>" without a limit (it summed
  `math.huge`).
- **Tests:** `gear_tests` (77): 19 stacks of 100 shells fill the assault rig (85 kg) and only
  a full grid refuses; 16 kits fill the medical part (was 14 kg); the small backpack still
  stops at 3 stacks with the weight message.

## 0.21.0 (LMG rounds: HE and penetrator)

- **`ammo.lua`:** LMGs are their own family (`lmg`): their magazines and belts keep the game's
  sizes and hold mixed loads, like box-magazine shotguns. `Ammo.LMG_ORDER`
  (standard, explosive, penetrator).
  - **HE round** (`explosive`, HE): x0.35 damage, no armour piercing, through nothing. It is the
    game's explosive bullet (`InstantExplosiveBulletBase`) with a 60 cm blast instead of 2 m
    (`Ammo.ExplosiveClass(range)`, a subclass; the game's class is not changed). 150 per round.
  - **Penetrator** (`penetrator`, PEN): x1.5 damage, always pierces armour plates, goes through
    enemies, shields and walls. From the shoulder the kick is x4 and climbs 25% per shot in a
    row, up to x12; on the bipod it is x1.15 and does not climb. 220 per round.
  - `Ammo.ApplyBullet` also sets the wall flag and the bullet class (and the class's hit masks),
    and puts the weapon's own back for other rounds. `ApplyLoaded` sets the clip maximum only for
    AR/SMG magazines (sizes).
- **`ammo_hooks.lua`:** the bullet hooks (damage, plates, recoil) also work for LMGs;
  `Ammo.OnBipod()`.
- **`plan.lua`:** `Plan.Info` gives LMGs the `lmg` family (the menu lists and prices the rounds).
- **`ui_beardlib.lua`:** colours for the LMG rounds (HE yellow, penetrator blue).
- **Tests:** new `lmg_ammo_tests.lua` (30); `shell_tests` updated.

## 0.20.2 (ammunition categories)

- **`ammo.lua`:** ammunition categories: AR/SMG, Shotgun, LMG (and Other).
  `Ammo.CATEGORY_ORDER`, `CATEGORY_NAMES`, `CATEGORY_BULLETS` (LMGs: standard rounds only)
  and `Ammo.AmmoCategory(info)`.
- **`plan.lua`:** `Plan.SlotsByCategory()`; `Plan.Rows` groups the bring list by category
  under "<Category> ammunition" headings.
- **`ui_beardlib.lua`:** the menu bring list draws the headings; the spawner has one row
  of bullet buttons per category (`spawn_bullet_<category>_<id>`), the spawn buttons name
  the category ("PRI magazine AR/SMG HP"), and spawning one category's rounds for a weapon
  of another is refused with the reason.
- **Tests:** `typed_ammo_tests` (141), `shell_tests` (64).

## 0.20.1 (no ammunition list; a full stack with Ctrl)

- **`ui_beardlib.lua`:** the right window (backpack side) no longer lists the loose rounds
  and magazines ("Ammunition"); the grids show them. Ctrl+click on a "PRI/SEC loose" spawn
  button spawns a full stack (`Ammo.MAX_STACK`, 100 rounds).
- **`ammo.lua`:** `Ammo.DevSpawnLoose(slot, bullet, rounds)` takes the number of rounds
  (default: one magazine's worth).
- **Tests:** `ui_tests` (107): the list is gone, a click spawns a magazine's worth, Ctrl+click
  a full stack.

## 0.20.0 (shotgun shells: the game's ammunition types)

- **`ammo.lua`:** bullet families. `Ammo.BULLETS` has the shotgun shells (`custom` 000
  Buckshot, `flechette`, `slug`, `tombstone`, `dragon`, `he`) with `family = "shell"` and
  the game's ammo part (`part`, `parts`); `hollow`/`ap` are `family = "rifle"`; `standard`
  is both (buckshot on a shotgun). `SHELL_ORDER`, `FAMILY_ORDER`, `STANDARD_NAMES`.
  `Ammo.ShellsAccepted(factory_id)` = the shells whose ammo part is in the gun's factory
  `uses` (missing parts skipped); `BulletsFor`, `BulletAllowed`, `SafeBullet`,
  `FilterLoad`, `BulletName`/`BulletShort` (family-aware), `HasLoad`.
  `Identify` marks every shotgun `typed = true, family = "shell", factory_id`; rifles get
  `sized = true, family = "rifle"`. `typed` now means "rounds have kinds"; the AR/SMG
  magazine sizes follow `sized` (MagAmount, SizeReloadFactor, put_in, magazine_data,
  BagMagazineSpec, plan). Specs of shotguns have no size (`norm_spec(spec, base, unsized)`).
  Loose and magazine data carry `family`; every bullet that goes into data passes
  `SafeBullet`, so a rifle round never becomes a shell or the other way round.
  Tubes: `gun_rounds` counts the whole clip for loose-fed guns; `PushLoaded`,
  `ShellChoices`, `NextShell`, `CycleShell`, `LoadShells` (chosen kind first, then the
  others in menu order, each on top). `ApplyLoaded` of a shotgun applies the top shell's
  profile and never changes the clip size. Prices: `custom 60, flechette 120, slug 150,
  tombstone 150, dragon 200, he 250` per shell.
- **`shells.lua` (new):** `Shells.Capture(wep)` runs the weapon's own `_update_stats_values(true)`
  once per shell on a copy of the blueprint (ammo parts replaced by the shell's), snapshots
  the result and puts the real blueprint back. A profile = `Shells.FIELDS` plus every plain
  value that differs between shells, never ammunition counts or the fire mode
  (`Shells.NEVER`). `Shells.Apply(wep, id)` copies a profile (tables copied);
  `Shells.Profiles` captures again when the blueprint changed or the game recalculated
  the weapon (`_current_stats` replaced). The gun's own ammo mod is ignored.
- **`ammo_hooks.lua`:** the damage hook pops the shell (`ShotBullet`) and applies its profile
  *before* the game's `_get_current_damage`, so damage, pellets, bullet class (fire, poison,
  explosive), armour piercing and shoot-through are the game's. `Ammo.ShellBase`. The
  rifle bullet hooks (pierce, recoil, crit) still only see rifles. Loose-fed reloads of a
  shotgun go through `LoadShells` (hint when the chosen kind ran out). The wheel on a tube
  shotgun cycles the next shell ("Next shell: ..."). Dropped-magazine tags keep `family`,
  `sized`, `factory_id` (old tags: a size means a rifle).
- **`plan.lua`:** `Plan.Info` gives shotguns `family = "shell"` and the factory id
  (`managers.weapon_factory:get_factory_id_by_weapon_id`). Plan magazines of shotguns have no
  size; `PickSpec`/`GunSpec`/`BagMagazineSpec` drop bullets the gun cannot use;
  `SetPickCount`, `SetSpec`, `Add` refuse them ("these rounds do not fit this weapon").
  `Rows`: a tube shotgun gets a header and its loose shell rows; magazines rows list the
  gun's shells. A tube starts the heist with `gun_bullet` (buckshot by default).
- **`ui_beardlib.lua` / `ammo_hud.lua`:** the "+Mag" editor has no size buttons for
  shotguns and wraps the shells three to a row; the loose rows wrap the same way; the dev
  spawner has the shells (five to a row). Colours for each shell. The HUD shows a tube's
  shells in colour and the next shell ("+SLG") after LOADED.
- **Tests:** `shell_tests` (61): families and the gun's part list, profiles from the game's
  function (slug, dragon's breath, HE), the real blueprint and ammunition count untouched,
  recapture, mixed box magazines shot by shot, magazine items, prices, rifle rounds refused,
  loose slugs onto a magazine, the tube (last in fires first, wheel, fallback, the game's
  reload), the menu plan.

## 0.19.9 (assault rig ammunition slots)

- **`items.lua`:** the shared `AMMO` section filter also takes `armor_kit` (the plate), so
  the Assault Rig's "Ammunition" part and the Medical Rig's pouches accept plates. The
  Assault Rig's "Ammunition" part has `max_weight = 30` (was 14: with loose shotgun shells at
  0.045 kg a round, three stacks of 100 made it full by weight).
- **`inventory.lua`:** `weight_refusal(container, adding)` (`PDTI.WeightRefusal`) names the
  container (the rig's section by its name) with its weight, what was added and the limit.
  It is used by `MoveItem`, `AddItem` and the stack move instead of "container weight limit
  exceeded".
- **Tests:** `gear_tests` (74): a plate in the assault rig's ammunition part and a medical
  pouch, not in the ammo bag part; six stacks of shells and a magazine fit; the seventh
  stack is refused with the new message.

## 0.19.8 (heals: the most hurt part first)

- **`body.lua`:** `Body.Heal` no longer splits a heal by what each part misses. It fills the
  part with the lowest `frac` (not black, unless `allow_black`) up to its maximum, then picks
  again, until the amount or the need runs out. It returns what was given. Every heal that
  goes through the `change_health`/`set_health` hooks (first aid kit, perks, skills,
  regeneration) uses it; a medic bag still restores every part.
- **Tests:** `body_tests` (60): a small heal goes only to the most hurt part, a bigger one
  fills it and goes on to the next, black parts are skipped, nothing is given beyond what
  is missing, and after a black leg's spread a heal still shows on one part.

## 0.19.7 (the bring list in its own window)

- **`ui_beardlib.lua`:**
  - `shop_window()` makes a `pdti_shop` window at `"Center"` (like `health_window()`). In the
    menu `redraw()` draws `draw_bring` in it, `SHOP_W` (500 at scale 1) wide; in a heist it
    is sized 1x1. `draw_right` draws the list itself only when there is no such window
    (`view.shop_drawn`).
  - `draw_bring(win, x, y, w)` and `draw_pick_rows(..., w)` take the width. Item rows (kinds
    without ":") go two to a row; weapon rows stay full width.
  - `redraw()` measures the tallest window. If it is taller than the screen
    (`view.menu._panel:h()`, else 720) it applies a smaller scale (at least 0.6) and draws
    again, at most three times. The scale stays until the screen is opened again.
- **Tests:** `ui_tests` (106): three windows in the menu, two items to a row, every window
  within 720 with the Large Backpack, the shop folded away in a heist and back in the menu,
  the shrink to fit. `typed_ammo_tests` and `menu_tests` look for the list in `pdti_shop`.

## 0.19.6 (all of the game's deployables)

- **Items (`items.lua`):** `trip_mine`, `ecm_jammer`, `spy_camera` (`placement = "look"`),
  `sentry_gun`, `sentry_gun_silent`, `grenade_crate`, and `armor_bag` (`deployable_id =
  "armor_kit"`, `placement = "none"`; `armor_kit` stays the armour plate). Prices in
  `Ammo.PRICES.item`. `Plan.Items` skips a deployable whose `tweak_data.equipments` entry is
  missing (`Plan.GameHas`).
- **`deployables.lua`:**
  - `Dep.ManagedEquipment` (any deployable definition, not only `Dep.MAP`) is used by
    `GameEquipment` and `GameManagedEquipment`.
  - `Dep.PlacementKind` and `Dep.ValidPlacement` mirror the game's
    `check_equipment_placement_valid`: look-at for trip mine, ECM and spy camera, none for
    the armor kit, shape for the rest.
  - `RunPlacement` primes with the right check and calls `fn(equipment, selected_index,
    data.unit)`, as `use_selected_equipment` does.
  - A client sentry request (`_sentrygun_placement_requested`) sets `Dep.pending_sentry`.
  - `Dep.ItemFor`, `HasRoomFor`, `Store`, `OnSentryPlaced`, `OnSentryPickedUp`.
  - `Dep.InstallGameHooks` (from the `hooks_game.lua` frame):
    `PlayerEquipment._sentry_gun_ammo_cost` is skipped while the ammo system is on, and
    `SentryGunBase.on_interaction` is refused without room.
- **`hooks_player_manager.lua`:** `check_equipment_placement_valid` uses
  `Dep.ValidPlacement`. `add_sentry_gun` stores the sentry as an item. For a pending
  sentry, `from_server_equipment_place_result` consumes the item instead of the game's count.
- **UI:** the deployable list only shows kinds with a count (or the pick); the spawner uses
  three columns (`list_button` takes a width).
- **Tests:** new `tests/deployables_new_tests.lua` (25). `deployable_tests` uses another
  mod's equipment (`mod_turret`) as the "game's own" example and checks that a brought
  sentry is blocked when not carried. `ui_tests` expects 11 spawn buttons.

## 0.19.5 (drag loose rounds onto a magazine to load it)

- **`ammo.lua`:**
  - `Ammo.CanLoadInto(loose, mag)`: same `queue_key`, the magazine not `in_gun`, not full.
  - `Ammo.LoadOneRound(loose_id, mag_id)`: finds both by instance id (wherever they are
    now) and moves one round with one `PDTI.EditItems` (magazine `rounds`+1, for typed
    magazines the stack's bullet pushed on top of `load`; stack `set_amount`-1 or `remove`).
  - `Ammo.LoadAllInto` (the menu) and `Ammo.StartLoad` (in a heist: `load_job`, a hint).
    `Ammo.LoadTick(dt)` loads one round per `round_interval`, redraws the open screen
    (not while dragging) and ends on full, empty, or a missing item. `Ammo.StopLoad`,
    `Ammo.LoadActive`.
- **`ammo_hooks.lua`:** `Ammo.GameTick` calls `Ammo.LoadTick` each frame. The `_get_input`
  hook stops the job when `Ammo.ActionPressed(input)` is true: any of `Ammo.ACTION_KEYS`
  (attack, aim, reload, melee, grenade, projectile, interact, use item, switch weapon,
  1/2, gadget, fire mode, inspect) or a wheel turn. Run, jump and duck do not stop it.
- **`ui_interaction.lua`:** `load_target` (`PDTI._UILoadTarget`): the held item is loose
  rounds and the cell holds a magazine. `UIDragPreview` then lights up the magazine (green
  or red, `load = true`), and `UIDragDrop` calls `Ammo.StartLoad` instead of moving the stack.
- **Tests:** new `tests/load_tests.lua` (24), added to `run_all.lua`.

## 0.19.4 (dropped magazines can be picked up)

- **Pickup (`ammo_hooks.lua`, `update_pickup`, exposed as `Ammo.UpdatePickup`):**
  - No `holster_start("pickup")`/`holstered` wait any more: restoration-mod replaces
    `_start_action_unequip_weapon`/`_update_equip_weapon_timers`, and the pickup never
    started. It is now a plain 1 s hold with the interaction bar (all HUD calls pcall'd).
  - Held = `Ammo.interact_held` (the game's `btn_interact_state`, recorded in the
    `_get_input` hook) or `controller:get_input_bool("interact")`.
  - `hide_pickup_hint()` (`remove_interact` + `hide_interaction_bar`) runs from
    `clear_pickup`, so the hint goes when nothing is aimed at. `Ammo.pickup_hint` tracks it.
  - `game_interaction(state)` (`_interacting()` or `interaction:active_unit()`): the game's
    interaction wins.
  - The `_get_input` hook clears `btn_interact_press/release/state` while a magazine is aimed
    at, so F does not intimidate.
  - Failures are logged once per reason (`pickup_problem`). `firearm_in_hand` was removed.
- **Tests:** `wheel_tests` 79 (the pickup flow); fake units have `position`.

## 0.19.3 (own drop as a fallback, drops caught at add_magazine, sliders snapped)

- **Cause, from the user's log and mods folder:** no installed mod defines
  `drop_magazine_object` (only restoration-mod calls it, guarded by `DMM_can_drop_magazine`),
  yet the game has it ("magazines are dropped by the installed magazine-drop mod" was logged),
  so it is in the current game's own code and drops nothing for the local player.
  `drop_mode` was 2 in `issr_settings.txt`.
- **Drop hook (`ammo_hooks.lua`):** while `orig` runs (in pcall), `managers.enemy.add_magazine`
  is wrapped to collect `{mag, col}`, then restored (the instance field is put back as it
  was). If nothing was added and `orig` is not the mod's own, `Ammo.FallbackDrop`
  (`SpawnMagazineUnit`) runs inside the same wrap. The collected entries are recorded in
  `Dropped`, not `_magazines[before+1..#]`: `EnemyManager:cleanup_magazines` replaces the table
  at `_MAX_MAGAZINES`.
- **Options (`options_menu.lua`):** `Options.Value` snaps sliders to `min + k*step` (step 1 for
  `int`), and the callback calls `item:set_value` with the stored value. New
  `Options.Precision(entry)` is passed as `display_precision` (0 for int, else the step's
  decimals).
- **Tests:** `wheel_tests` 66 (the drop mock goes through `add_magazine`, which replaces the
  list past its limit like the game); `options_tests` 29.

## 0.19.2 (own magazine drop, faster reload without a magazine, AP > HP damage)

- **Own drop (`ammo_hooks.lua`):** `Ammo.SpawnMagazineUnit(wep)` finds the magazine part
  (`Ammo.MagazinePart`: `wep._parts` whose factory type is "magazine"), spawns `part.name` at
  the part's position and a collision box (`Ammo.MAG_COLLISIONS`, chosen by
  `Ammo.MagazineCollision`: the `_crew` tweak's `pull_magazine_during_reload`, else the
  category) at the part's oobb centre, links them, hides `bullet_objects` when empty, pushes
  it and calls `managers.enemy:add_magazine`, like `HuskPlayerMovement:anim_clbk_spawn_dropped_magazine`.
  Both units are checked with `PackageManager:has(Idstring("unit"), ids)` first; otherwise
  nothing is spawned and the reason is logged once.
- `Ammo.OwnDrop = make_drop_hook(own_drop_orig)`, so the drop mode, the once-per-reload rule,
  the dump override and the `Dropped` record apply. `mag_out_drop` uses
  `drop_magazine_object` when a mod defines it, else `Ammo.OwnDrop`.
- **Empty gun:** `Ammo.GunWithoutMagazine` (`_issr_no_mag`, `_issr_mag_gone`, or both akimbo
  guns empty). The reload speed hook uses `Ammo.EMPTY_GUN_SPEED` = 1/0.7 for it.
  `reload_started` records `_pdti_started_empty`, and `mag_out_drop` drops nothing then.
- **Bullets:** hollow `damage` 1.1 (was 1.3), AP 1.3 (was 0.85).
- **Tests:** `wheel_tests` 64; damage expectations in `typed_ammo_tests` and
  `akimbo_buttons_tests`.

## 0.19.1 (wheel read from the mouse, fullest first, no lost magazines without a drop mod)

- **Wheel (`ammo_hooks.lua`):**
  - `wheel_dir()` polls `Input:mouse():pressed(Idstring("mouse wheel up"/"mouse wheel down"))`
    each frame and returns -1, 1 or nil, like BLT's keybind manager. `HandleWheel` no longer
    waits for `btn_switch_weapon_press`, which the wheel did not always set.
  - When the wheel turned, `btn_switch_weapon_press` is cleared; a keyboard switch-weapon
    press without a wheel turn passes through.
  - `wheel_free()`: nothing while `PDTI.IsUIOpen()` or `managers.hud:chat_focus()`.
- **Order (`ammo.lua`):** `Ammo.Magazines` sorts by fill fraction (rounds / capacity)
  descending, then `GRID_RANK`, y, x. This drives `NextMagazine`, `ChoiceList`, the default
  choice and the HUD queue.
- **Drops:**
  - The game has no player magazine drop; `NewRaycastWeaponBase.drop_magazine_object`
    comes from a mod such as Drop My Mag. `InstallHooks` logs whether it exists.
  - The drop hook ignores `drop_mode` when `_pdti_dump` is set (fast reload).
  - The single-gun and akimbo dump branches return the old magazine (`ReturnMagazine` /
    `SwapMagazine`) when no drop was counted, instead of losing it.
- **HUD (`ammo_hud.lua`):** `hud_panel()` is pcall'd. `rebuild_panel` pcalls `build_panel`
  and logs once per reason (`hud_problem`): the player HUD panel missing, drawing failed, or
  the weapon unknown. A half-built panel is removed.
- **Tests:** `wheel_tests` 55 (the `Input` mock reports "mouse wheel up"/"down"; new checks
  for the keyboard switch, the chat, the order, the dump drop and the HUD log).
  `reload_tests` and `akimbo_tests` expect the dumped magazine to be kept without a drop.
  `typed_ammo_tests`: the pockets-before-rig check uses two full magazines.

## 0.19.0 (mouse wheel chooses the magazine, take the magazine out, ISSR leftovers removed)

- **Choice (`ammo.lua`):**
  - `Ammo.selection[key]` holds an instance id or `"gun"`.
  - `ChoiceList` lists `"gun"` (if loaded), then the `Magazines` with rounds, or every
    magazine when the gun is empty.
  - `CurrentChoice` and `CycleChoice(wep, dir)`, which wraps round.
  - `NextMagazine` uses the selection first. `TakeMagazine` clears it when the chosen
    magazine is taken.
  - `GunLoaded`.
- **Take out:**
  - `Ammo.UnloadPlaces` finds a place in `STORAGE` for each gun magazine item, distinct
    places for akimbo.
  - `Ammo.Unload` runs `PDTI.MoveItem` out of the gun slot, then `SyncGunSlot` performs the
    existing `take_out`.
  - `ammo_hooks.lua`: `ChosenReload` (on a tap of R, when not reloading) sets
    `wep._pdti_unload` and calls `state:_start_action_reload_enter`. A chosen magazine with
    `clip_full` starts the reload as well.
  - `finish_unload` runs at `stage_out` in `track_reload` (and at NQR's `r_mag_out`). It
    unloads, calls `_interupt_action_reload` and redirects the camera to `idle`.
  - `can_reload` returns true while unloading. `drop_magazine_object` does nothing while
    unloading.
  - `on_reload` with the flag still set unloads instead of loading. `reload_interrupted`
    clears the flag.
- **Wheel:**
  - `Ammo.HandleWheel` runs in the `_get_input` hook. It clears `btn_switch_weapon_press`
    for magazine weapons, does nothing else while reloading, and reads the direction from
    `Input:mouse():pressed(Idstring("mouse wheel up"))` (otherwise next).
  - It sets `Ammo.panel_until` (`CHOICE_SHOW` = 2 s), which the panel-hide code in the
    reload hook respects.
  - New setting `wheel_choose`.
- **HUD (`ammo_hud.lua`):**
  - `rows.choice` and `Ammo.HudOrder(in_gun, n, choice, max_boxes)`.
  - A yellow mark under the chosen box(es). NEXT shows the chosen magazine, and
    "R: TAKE OUT" appears for `"gun"`.
- **Removed:**
  - The settings `max_extra_mags` and `ammo_max`, and `Ammo.ExtraMags`.
  - `MaxTotal` is now `BaseTotal` (gun + chamber + `MagAmount` × capacity, or `plan_max`),
    raised to the current total when that is more.
  - `add_ammo`'s room is unlimited, except for loose-fed and no-reload weapons. The
    inventory decides through `AddLooseKey`.
  - `BagRestock` uses `BaseTotal` for the budget. `MaxMagCount` stays without the extras
    and caps the new magazines a bag makes.
  - A dropped magazine is pickable when `Ammo.DroppedFits` (room in `STORAGE`), and
    `PickupDropped` falls back to the backpack.
- **Tests:**
  - New `wheel_tests.lua` (48). `options_tests` has 26 checks.
  - The akimbo maximum is now 102.
  - The bag share tests use `BaseTotal`.
  - Mutations caught: no stop at the magazine out, no `can_reload` bypass, the wheel not
    consumed, not blocked while reloading, the selection ignored, and a floor drop during a
    take-out.
  - 1167 checks in total.

## 0.18.10 (heavy armour falsely broken at heist start)

- `armour.lua`:
  - `state.had_armor` is set when `get_real_armor() > 0` and reset in `OnHeistStart`.
  - `check_broken` marks a vest broken only when `had_armor` is set and `_max_armor() > 0`.
  - `Armour.Protection` returns 0 unless `check_broken` is true.
- Cause: the game log showed `[PDTI ARMOUR] ICTV broken` in the first tick of a heist, and
  that blocked `_update_regenerate_timer` for the whole heist.
- Tests:
  - The `armour_tests` `player()` helper runs one `Armour.Tick` (the first frame).
  - Five new checks. The old rule fails four of them.
  - 1118 checks in total.
- The heist-start crash in this session was `load_packages()` (`gamesetup.lua:418`), a C++
  exception in `PackageManager:load`, so it was not caused by this mod.

## 0.18.9 (larger UI boxes, repeated clicks, Ctrl+click fill, options page)

- **Sizes (`lua/ui_beardlib.lua`):**
  - The constants come from `BASE` through `apply_scale(scale)`, which runs when the
    screen opens, using `Ammo.settings.ui_scale` (clamped 0.6 to 1.6).
  - Cells are now `CELL_W` × `CELL_H`, 36×32, instead of a square `CELL` of 30. `WIN_W` is
    320, so two windows are still 640 or less on a 1280×720 screen.
  - The left window is at most 586 high in the menu (the limit is 620).
  - `fit_font(text, w, h, base)` (`PDTI._UIFitFont`) estimates 0.55 × font per character
    and 1.15 × font per line, with a minimum of 8. Cells, buttons, list buttons, labels,
    one-line dividers and health boxes all use it.
  - `short_label` returns two lines.
  - The bullet `-`/`+` rows use `pm_group` and a third of `INNER_W` each. The health
    figure scales from a 280-wide layout.
- **Repeated clicks:**
  - BeardLib's `Item:MouseCheck(true)` needs `menu._highlighted == self`, and
    `ClearItems` calls `UnHighlight`.
  - `rehighlight()` (`PDTI._UIRehighlight`) runs at the end of `redraw()`. It queues
    `menu:MouseMoved(nil, managers.mouse_pointer._mouse:world_position())` with
    `RunCallbackNextUpdate`.
- **Ctrl+click fill:** `Plan.FillPick(slot, bullet)` and `Plan.ClearPick(slot, bullet)`.
  `pick_change` uses them when `ctrl_down()`. There is a hint line `bring_pick_hint`.
- **Options:**
  - New `lua/options_menu.lua`, hooked on `lib/managers/menumanager`.
  - BLT `MenuHelper` hooks: `LocalizationManagerPostInit`, `MenuManagerSetupCustomMenus`,
    `MenuManagerPopulateCustomMenus`, `MenuManagerBuildCustomMenus`. The page goes under
    `blt_options`.
  - The entries are data in `Options.LIST`. `Options.Value` converts the menu value: "on"
    is true, a choice index goes from 1-based to 0-based, and sliders are clamped and
    rounded.
  - `Options.Set` saves and, for HUD entries, calls `MarkPanelDirty` and `RefreshHud`.
  - `Ammo.SaveSettings()` writes `SETTING_FILES` with `json.encode`.
  - Also exposed: `Ammo.SETTING_FILES` and `Ammo.LoadSettings`.
  - New setting `ui_scale` in `issr_reload_settings.txt`.
  - `sound` is not offered, because nothing reads it.
- **Tests:**
  - The MenuUI mock gains `RunCallbackNextUpdate`, `update` and `MouseMoved`.
  - `ui_tests` has 97 checks and `typed_ammo_tests` has 139; the drum label is now
    `"75\nHP"`.
  - `options_tests.lua` is new (25).
  - Mutations caught: no rehighlight, FillPick adding one step, settings written into both
    files, no Ctrl in the UI, and `fit_font` ignoring the width.
  - 1113 checks in total.

## 0.18.8 (heavy armour and plates, finer body-part colours)

- **`lua/armour.lua` (new, loaded after `body`):**
  - `Armour.HEAVY` holds the broken-vest protection: `level_5` 0.10, `level_6` 0.18,
    `level_7` 0.25.
  - `Armour.Id()` reads `equipped_armor(true, true)` and is cached per heist.
    `Armour.IsHeavy()`.
- **Hooks** (tag `"armour"`, added to `hook_chain_tests`):
  - `PlayerDamage._update_regenerate_timer`: on heavy armour that is broken it sets
    `_current_state = nil` and does not count down.
  - `PlayerDamage._regenerate_armor`: skipped only inside `revive`, through a wrap of
    `PlayerDamage.revive`.
  - Perk paths (`change_armor`, `restore_armor`, regeneration on the side, the armour bag)
    are untouched.
- **Broken-vest protection:**
  - `Armour.Protection(pd)` is the vest's value when the armour is heavy and
    `get_real_armor() <= 0`.
  - `Body.Damage(amount, where, max, mul)` scales every part except the head by `mul`; a
    spread hit is scaled per share.
  - `make_change_health` passes `1 - Protection`.
- **Plates:**
  - `armor_kit` is renamed "Armour Plate" and gets `plan_item`; `Plan.Items()` lists
    `plan_item` items.
  - The keybind `pdti_insert_plate` runs `lua/ui_plate.lua`, which calls
    `Armour.StartPlate()`.
  - `Armour.Tick(input, dt)` runs from the game tick. It cancels on
    `btn_primary_attack_*` or `btn_reload_press`, or when the player is down.
  - When it finishes it removes one plate and calls `_regenerate_armor` with a bypass.
  - `Body.SpeedFactor` includes `Armour.SpeedFactor()` (0.6 while inserting).
- **Colours:** `Body.COLORS`, `Body.ColorName(frac)`: full at 0.999 or more, dark green
  above 0.75, yellow above 0.5, orange above 0.25, red above 0, black at 0.
- **Other:**
  - The setting `heavy_armour`.
  - The health window line `Armour.StatusLine()`.
- **Tests:** `armour_tests.lua` (44, mutations checked). 1072 checks.

## 0.18.7 (real money: pay when added, restock what is used)

- **Prices:** `Ammo.PRICES.item` (deployables and other items) and `Ammo.PRICES.throwable`.
  - `Ammo.UnitPrice(id)` uses a definition's own `price` first.
  - `Ammo.ThrowablePrice(id)` is 0 for `ability`/`base_cooldown` projectiles.
  - `Ammo.ItemPrice` prices every item.
- **Menu purchases:**
  - `Plan.Add` calls `Plan.Pay(price)`, which runs `managers.money:deduct_from_total` and adds
    to `PDTI.PlanPaid()`, a new save field `plan_paid`.
  - `Plan.Remove` calls `Plan.Refund(price)`: `add_to_spending` (no offshore), capped by
    `plan_paid`.
  - `Plan.CanAfford(price)` checks the price alone. `Plan.Cost()` is the worth of every item.
- **Restock:**
  - `Plan.ChargeHeist` and `charge_hint` are removed.
  - `heist_start` calls `Plan.StartRestock()`. It records the rounds by bullet, the priced
    items and (on the first tick) the throwables the plan brings.
  - The game tick calls `Plan.RestockTick()`:
    - Rounds are counted per weapon as `min(total drop, clip drop)`, priced by the last fired
      bullet, and only once `Ammo.SupplyReady(wep)`.
    - Item counts and the grenade count are compared with the last tick.
  - `Plan.Spend` caps everything by what the plan brought. `Plan.PayRestock` deducts at most
    every `Plan.RESTOCK_EVERY` (1 s).
- **Menu log errors:**
  - `loadout.lua` `throwable_entry` asks for the grenade count only with a player and a
    session.
  - `Loot.CarriedId` returns nil without a player unit.
- Tests:
  - `bag_price_tests.lua` rewritten for the new model (57 checks, mutations checked).
  - `loot_tests.lua` +1 and now spawns a player.
  - 1028 checks.

## 0.18.6 (a black arm cannot fire its akimbo gun)

- **`Body.ArmBlocked(id)`:** body health is active and the arm is black. `Ammo.ArmBlocked(g)`
  maps gun 1 (left, the second gun) to `arm_l` and gun 2 (right, the main gun) to `arm_r`.
- **`AkimboWeaponBase.fire` hook:**
  - A blocked gun is skipped: no shot, no `dryfire`, and a hint (`Ammo.ARM_HINT_INTERVAL`,
    2 s).
  - With a black arm the hook also takes over when there is no `_pdti_want` (per-button
    controls off): it fires the guns that can, at once, instead of the game's alternating fire.
- **`Body.EffectLines`:** one line per black arm about its akimbo gun.
- Tests: `akimbo_buttons_tests.lua` +11. 1004 checks.

## 0.18.5 (ammunition costs money, ammo bags restock magazines)

- **Prices:**
  - `Ammo.PRICES` (round by bullet, magazine case by size), with `Ammo.RoundPrice`,
    `Ammo.MagazinePrice(data)` (case plus every round of its load), `Ammo.ItemPrice(item)` and
    `Ammo.Money(n)`.
  - `Plan.Cost()` sums the plan's magazine and loose items (`data.plan_slot`). Also
    `Plan.Money()` (`managers.money:total()`), `Plan.CanAfford(extra)` and
    `Plan.AddPrice(kind)`. `Plan.Add` refuses when the plan would cost more than you have.
  - `Plan.ChargeHeist()` runs from `heist_start` right after `EnsureProfile`, while the
    inventory is still the plan. It calls `managers.money:deduct_from_total(cost)` once and
    sets `Plan.charge_hint`, which the game tick shows as a hint.
  - The menu adds a `bring_cost` line, and the price on `bring_pick_info_<slot>`.
- **Ammo bags:**
  - `Ammo.BagRestock(wep, available)` works for magazine weapons; loose-fed weapons keep the
    old path. The budget is `available × get_ammo_max()` rounds.
    1. Every magazine of the weapon (grid order) is topped up with its top bullet.
    2. New magazines of `Ammo.BagMagazineSpec` (the plan's `pick_size`/`pick_load`/
       `pick_bullet`, bottom trimmed to fit, full) are added while there are fewer than
       `MaxMagCount` and a full one fits the budget: rig and pockets, then the backpack.
  - It returns the share used, like the game.
  - The game's `add_ammo_from_bag` still runs for gadgets (the underbarrel) with the rest of
    the bag, with the main total shown as full.
  - `need_ammo` asks `Ammo.BagWanted(wep)`: a magazine not full, or room for one more.
  - No loose rounds from bags any more (`ammo_tests` updated).
- **Boxes:** unchanged (standard loose rounds). New `ammo_conservation_tests.lua`: a random
  walk of 200 steps × 20 seeds for a rifle and for akimbo SMGs, checking that special rounds
  only go down. It catches a fill that loads the magazine's own bullet from standard loose
  rounds.
- Tests: new `bag_price_tests.lua` (34) and `ammo_conservation_tests.lua` (2). 993 checks.

## 0.18.4 (fix: stack overflow from hooks wrapping each other)

- **Crash:** `ammo_hooks.lua:58: stack overflow` from `PlayerStandard:_check_action_primary_attack`
  → `recoil_multiplier`.
- **Cause:**
  - `NewRaycastWeaponBase.recoil_multiplier` was hooked by `ammo_hooks` (AP recoil, 0.18.2)
    and by `body` (arm health, 0.18.0).
  - Both re-check their hooks every frame and re-wrapped whenever the class function was not
    their own hook, so they wrapped each other once per frame.
  - The chain grew without bound, and each layer multiplied the recoil again: 2.4e13 after
    100 frames in the test.
- **Fix:** `PDTI.HookOwners` (a weak-keyed table), `PDTI.HookHas(fn, tag)` and
  `PDTI.HookMark(new, under, tag)` in `inventory.lua`.
  - Every wrap helper (`ammo_hooks`, `body`, `carry`, `loot`) marks its hook with the tags of
    the chain beneath it plus its own.
  - A helper skips the wrap when its tag is already in the current function's chain.
  - A function replaced by another mod (no tags) is still wrapped again, once.
- Tests: new `hook_chain_tests.lua` (5 checks). Without the fix it shows the re-wrapping and the
  runaway recoil. 957 checks.

## 0.18.3 (body parts follow the build's max health)

- **The bug:** the body hooks are installed from the game tick, after the player spawned, so
  the `replenish` in `PlayerDamage:init` is not seen. The parts only attached at the first
  health change. Until then `state.max` was the fallback 23 (230 on the screen), so the HUD
  and the health window showed base health for every build.
- **`Body.AttachPlayer()`:** attaches the local player's `character_damage()`. It is called
  every frame from `Body.UpdateHud` and before the health window draws. `attach` now calls
  `changed()` when the max health differs, so the screens follow it.
- **`attach` calls `pd:_check_update_max_health()` first.** The game rescales the health
  inside its own `change_health` when the max health changed, which used to happen after the
  hook had computed its delta. That counted the rescale twice, and the game's health and the
  parts' sum drifted apart: 88 against 69.7 in the test.
- Tests: `body_tests.lua` +6 (a Stoic-like 66-health build before its first hit, max health
  rising mid-heist, a change seen first in a hit). 952 checks.

## 0.18.2 (armour-piercing recoil)

- **Bullet spec:** `Ammo.BULLETS.ap` gains `recoil = 1.5`, `recoil_build = 0.1` and
  `recoil_build_max = 6`.
- **New optional hook:** `NewRaycastWeaponBase.recoil_multiplier` (`make_recoil_hook`). The
  game calls it once per shot, after firing, so the bullet is `Ammo.FiredBullet`: per round in
  a mixed magazine.
- **`Ammo.BulletRecoil(base)`:**
  - A shot within `1.5 × fire interval + Ammo.BURST_SLACK` (0.05 s) of the previous one
    continues the streak; the interval is `fire_mode_data.fire_rate / fire_rate_multiplier()`.
    Otherwise the streak starts again.
  - The factor is `recoil × (1 + min(streak, recoil_build_max) × recoil_build)`, which tops
    out at ×2.4.
  - The state is kept on the main weapon base (`_pdti_recoil_t`, `_pdti_recoil_streak`).
- **Scope:** only typed weapons (`typed_base`), the same as the other bullet hooks. The
  body-health arm multiplier stacks on top.
- Tests: new `recoil_tests.lua` (14 checks). 946 checks.

## 0.18.1 (the health window)

- **`ui_beardlib.lua`:** a third MenuUI window, `pdti_health` at `CenterBottom`. It is made
  on the first redraw in a heist with body health on, and emptied (size 1×1) otherwise. The
  menu keeps its two windows.
  - `draw_health`:
    - The total, rounded once from the real sum.
    - Six boxes (`health_part_<id>`) shaped like a body, with the text
      `<PART>\n<hp> / <max>` in the screen's units, coloured by `Body.PartColor`, or near
      black at 0.
    - `Body.EffectLines()`, then two lines on healing.
  - The one-line body summary in the left window is gone.
- **`body.lua`:**
  - New helpers: `Body.Frac`, `ShownHP`, `ShownMax` and `EffectLines`.
  - `Body.UpdateHud` redraws the open inventory screen when a part changed, at most every
    `Body.UI_REFRESH` (0.25 s). It compares `Body.ui_revision`, which the window sets when it
    draws.
- Tests: `ui_tests.lua` +12 (the window, the boxes and numbers, colour change, black part,
  effects, layout, documented parameters only, empty in the menu). `body_tests.lua` +4 (the
  refresh and its throttle). 932 checks.

## 0.18.0 (silent magazine loading, health per body part)

- **Sound:** `fill_one_round` no longer plays `pickup_ammo` for every round. The `sound` setting
  is kept so old settings files still load; it now does nothing. Picking up a dropped magazine
  still plays its sound.
- **Body health:** new `lua/body.lua`.
  - **Parts:** `Body.PARTS` (head 35, body 155, arms 60, legs 65 out of 440; bullet and melee
    hit weights) and `Body.EFFECTS`.
  - **State:** each part is stored as a fraction of its maximum. The maximum is the share ×
    `_max_health() * _max_health_reduction`.
  - **The core hook:** `PlayerDamage.change_health`.
    - Damage goes to `self._pdti_hit`, a part or `"spread"`.
    - Heals go to the parts that are not black, shared by what each part is missing.
    - The original is then called with the delta that makes the game's health equal the
      parts' sum, or 0 when the head is black.
  - **`set_health`:** a direct set is reconciled as a heal or as damage. `set_health(0)` from a
    deadly fall, a kill zone or `force_into_bleedout` blacks the head.
  - **`revive`:** the head becomes `revive_head` (0.1, which shows as 1 HP); the other parts are
    unchanged. `Body.FullOnNextRevive()` (medical rig self-revive in `gear.lua`) makes it a full
    restore instead.
  - **`recover_health` and `replenish`:** every part full. A revive inside them is a full one.
  - **Damage wrappers** set `_pdti_hit`: `damage_bullet` (roll), `damage_melee` (roll),
    `damage_fall` (a leg), and `damage_explosion`, `damage_fire`, `damage_killzone`,
    `damage_simple` (spread).
  - **Effects:**
    - `NewRaycastWeaponBase.recoil_multiplier` and `spread_multiplier`, the player's weapon only.
    - `PlayerStandard._start_action_running` is blocked, and `_check_action_run` stops a sprint
      already running.
    - `PlayerMovement._max_stamina` ×0.5.
    - `Carry.GetBreakdown().legs` joins the speed product.
  - **HUD:** a body figure (`Body.UpdateHud`, from the game tick, redrawn on change). The
    inventory screen shows `Body.Summary()` in a heist.
  - **Setting:** `body_parts` (default `true`).
- Tests: new `body_tests.lua` (43 checks), plus 2 checks in `feed_tests.lua`. 916 checks.

## 0.17.2 (akimbo guns follow the mouse buttons)

- **Input:** an optional hook on `PlayerStandard._get_input`. When the equipped weapon is
  magazine-fed akimbo (`Ammo.IsAkimbo`, ours, not skipped) and `akimbo_buttons` is on:
  - `wep._pdti_want = { left, right }`: left = primary attack, right = steelsight (right mouse).
    A gun fires on its button's press, or while held on full auto.
  - The fire inputs are merged: press = either press, state = either held, release = a release
    with neither held. The steelsight inputs are cleared and steelsight is ended.
  - Single fire: a new press while the other button is held calls `_check_stop_shooting`, so
    the game starts a new shot.
- **Firing:** an optional hook on `AkimboWeaponBase.fire`. With `_pdti_want` set, it fires only
  the wanted guns:
  - The right (main) gun: `super.fire(self)` with `_pdti_fire_gun = 2`.
  - The left (second) gun: `sb.super.fire(sb)` with `_pdti_fire_gun = 1`, then the sound when it
    fires alone, the HUD ammo and the fire animation.
  - The pair is reconciled while `_pdti_fire_gun` is set, so the round leaves that gun's
    magazine (`Ammo.AkimboPair` honours it). It previously came off the fuller one.
  - A gun with an empty magazine is skipped; if nothing fired, `dryfire`.
  - Without `_pdti_want` (turned off, or not ours) the game's `fire` runs.
- **Setting:** `akimbo_buttons` (default `true`) in `issr_reload_settings.txt`.
- Tests: new `akimbo_buttons_tests.lua` (25 checks). 871 checks.

## 0.17.1 (the gun's magazine in the weapon slot)

- **The gun's magazine is an item in a heist.**
  - It is a magazine item with `data.in_gun = true` in `gun_<slot>`, mirrored from the gun by
    `Ammo.SyncGunSlot`. This runs every frame from `GameTick` for both weapons, and after every
    inventory-screen action (buttons, cell clicks, drag and drop).
  - `wep._pdti_gun_items[g]` holds the item ids; `wep._pdti_gun_empty[g]` marks an empty
    akimbo gun.
  - In-gun items are not spares: `Ammo.Magazines` and `AllMagazines` skip them, so totals,
    reloads and filling are unchanged.
- **Sync rules**, per gun:
  - The gun has a magazine and its item is there: rounds, load and bullet follow.
  - The item is gone: it was taken out. It becomes a normal magazine (`in_gun = false`) with
    the current rounds, and the gun is emptied: the chamber round stays, `_issr_no_mag` and
    `_issr_mag_gone` are set, or for akimbo that gun's pair entry is 0.
  - The gun has no magazine but the item is there: the gun lost it (reload stage, drop), so the
    item is removed.
  - The slot is empty and a magazine of this weapon was put in: it is loaded at once (spec,
    load, clip, `ApplyLoaded`).
  - No loading while `_issr_in_reload`.
- **Reloads** call `Ammo.ClearGunItems` first; the slot is filled again from the new
  magazine.
  - Akimbo reloads skip empty guns when returning old magazines.
  - Two taps with an empty gun fill only that gun (`want`/`give_back`).
- Only in a heist (`PDTI.session_only`); the menu's slot is still the plan.
- Tests: new `gun_slot_tests.lua` (44 checks). 846 checks.


## 0.17.0 (weapon slots, mixed magazines, ammo colours)

- **Weapon slots.**
  - New containers `gun_primary` and `gun_secondary` (`PDTI.GUN_SLOTS`, at the end of
    `PDTI.CONTAINERS`).
  - Each is 2x1 and takes only magazines whose `data.slot` matches the weapon: one, or two for
    akimbo magazines. Every magazine counts as 1x1 there (`dimensions(item, rotated,
    container)`), and drag and drop onto it uses the hovered cell.
  - In reload order they come first (`GRID_RANK` 0). Ctrl+click moves to hand, then the
    backpack.
  - `Plan.Magazines` excludes them; `Plan.GunMagazines` returns them.
  - `Plan.Bind` loads them into the gun with their spec, load and rounds, and removes the items.
    An empty slot falls back to the older `gun_size/gun_bullet`, full.
  - `Plan.Defaults` puts a magazine in each slot. `Plan.Refresh` fills the slot once for
    0.16.0 plans (`plan_slots.gun_filled`).
  - The left window draws a box per weapon (name, weight) with its slot; the throwable and
    armour share a line.
- **Mixed loads.**
  - Magazine data has `load = "ap:10,hollow:20"` (top first), a string because the save keeps
    only plain values. `data.bullet` is the top bullet.
  - Helpers: `Ammo.ParseLoad`, `LoadString`, `LoadTop`, `LoadPush`, `LoadPop`, `FitLoad`,
    `LoadOf` and `LoadTag`.
  - Filling pushes rounds onto the top: the magazine's top bullet first, then any other.
    `FillMagazines` keeps filling the same magazine across bullet types.
- **The gun's load.**
  - `wep._pdti_loaded.load` (and per gun for akimbo) is the load at insertion.
    `Ammo.LoadedSpec` / `PairViews` return copies fitted to the rounds now in the gun.
  - The damage hook calls `Ammo.ShotBullet`. The game takes the round out of the clip before
    `_get_current_damage`, so the rounds missing since the last shot leave the top, and the
    last of them is the fired bullet (`wep._pdti_shot_bullet`).
  - The armour-pierce and limb-crit hooks use `Ammo.FiredBullet`.
  - The returned and dropped magazine keeps its remaining load.
- **Menu:**
  - `plan_slots.pick_load` holds the counts per bullet type. API: `Plan.PickSpec` (load, rounds,
    capacity), `PickCount`, `SetPickCount`, `ChangePickCount` (steps of 5) and `FlipPick`.
  - A smaller size keeps what fits.
  - The Gun buttons are gone. The "+Mag" row has sizes, Flip and `rounds/capacity`, plus a
    row of -/+ per bullet type.
- **Colours:** `PDTI.UI_BULLET_COLORS` (hollow red, ap green; standard keeps PRI/SEC). They
  apply to grid cells and to the HUD fill bands (`Ammo.HudSegments`).
- **Dev:** `Ammo.DevSpawnMagazine(slot, bullet)` and `DevSpawnLoose(slot, bullet)`, plus a
  Bullets row in the spawner.
- Tests: `typed_ammo_tests.lua` has 131 checks. The fill rules are updated for mixed loads;
  `ui_tests` looks for the loadout row instead of the label. 802 checks.


## 0.16.0 (magazine sizes and bullet types for assault rifles and SMGs)

- **Scope:** weapons whose size class is `assault_rifle` or `smg` and that are not loose-fed
  (`Ammo.Typed`), akimbo SMGs included. Every other weapon is unchanged.
- **Sizes** (`Ammo.MAG_SIZES`): compact x0.65 rounds / x0.85 reload time, standard, extended
  x1.5 / x1.15, drum x2.5 / x1.5.
  - The base is `tweak_data.weapon[id].CLIP_AMMO_MAX` (halved for akimbo). The game's magazine
    mods are ignored on these weapons.
  - The supply key is `<name_id>:typed`, so it no longer depends on `get_ammo_max_per_clip`.
  - Magazine items carry `size`, `bullet` and their own `capacity`; footprint and weight follow
    the capacity as before.
- **Bullets** (`Ammo.BULLETS`):
  - Hollow point: damage x1.3, armour-plate pierce chance 0, `_use_armor_piercing` off, no
    shooting through enemies or shields, and a forced critical hit on limb bodies
    (`rag_{Left,Right}{Arm,ForeArm,UpLeg,Leg}`) when `can_be_critical` allows it. Crit damage
    is `critical_hits.damage_mul or headshot_dmg_mul`, as in the game.
  - Armour piercing: damage x0.85, pierce chance 1, shoots through enemies and shields.
  - Standard: the weapon's own values (saved once in `_pdti_orig_flags`).
- **New optional hooks:**
  - `NewRaycastWeaponBase._get_current_damage`: the damage multiplier. It also sets the
    shoot-through flags for the next shot; the game reads them right after, which matters for
    akimbo, where the fuller gun's magazine fires next.
  - `NewRaycastWeaponBase.armor_piercing_chance`.
  - `CopDamage.roll_critical_hit`.
  - Only the player's typed weapon is affected; an akimbo second gun counts as its main
    weapon.
- **The loaded magazine:**
  - It is kept in `wep._pdti_loaded`, or `_pdti_pair_specs` per gun for akimbo.
  - `Ammo.ApplyLoaded` sets `set_ammo_max_per_clip` to its capacity before the game's
    `on_reload` fills the clip.
  - The outgoing magazine goes back (or swaps, or drops) with its own size and bullets.
  - Reload speed is multiplied by `1 / reload` of the incoming size, kept out of the tap factor.
- **Grid order:** `Ammo.Magazines` sorts pockets, rig, rig_2, rig_3, then y and x;
  `NextMagazine` is the first one with rounds. This applies to all magazine weapons.
- **Filling by bullet:**
  - Loose stacks of typed weapons carry `bullet`.
  - `FillMagazines`, the hold-R job, `NeedsFill` and `MagazinesNeedFill` put only matching
    bullets into a magazine; an empty one adopts any.
  - Pickups and bags are standard rounds.
- **Menu plan:**
  - `state.plan_slots[slot] = { gun_size, gun_bullet, pick_size, pick_bullet }`, saved per
    profile (`PDTI.GetPlanSlot` / `SetPlanSlot`, `Plan.SetSpec`).
  - `mag:<slot>` adds the picked spec; `loose:<slot>:<bullet>` kinds.
  - `Plan.Bind` puts the gun's chosen magazine in, full.
  - `Plan.Refresh` turns typed magazines into plain ones (and back) when the weapon type
    changes.
- **UI:**
  - The Bring list has Gun and +Mag size and bullet buttons, and a loose row per bullet.
  - Grid labels show `rounds BULLET`; the HUD footer shows the loaded spec.
- **Starting magazines** without a plan: `AMMO_MAX / base - 1` standard magazines.
- Tests: new `typed_ammo_tests.lua` (87 checks). The mock's `test_smg` is now an LMG, because
  the older tests need an untyped magazine weapon; `test_ar` and `test_akimbo_smg` are added.
  758 checks.


## 0.15.1 (loot bags)

- **No more wait between thrown bags.** After a throw, `Loot.Tick` waited until
  `PlayerManager:carry_blocked_by_cooldown()` was over. `drop_carry` sets that cooldown to
  1.2-1.5 s so you cannot grab the bag you just threw from the floor. It does not need to apply
  to a bag from your own inventory. The next bag is now taken out on the next frame. The
  cooldown still blocks picking bags up from the world.
- **No more bags than room.** The pickup checks were wrong:
  - While carrying, a second bag was allowed whenever the carried bag was already in the
    inventory, without checking for a place for the new one. With a full inventory you could
    pick up any number of bags that took no space.
  - The first bag was never checked.
  Now every loot bag needs its own free place (and weight) in the rig or the backpack
  (`Loot.RoomForPickup`). A bag you carry without a place, given by a mission while you had no
  room, allows no second bag on top of it. When blocked, the pickup shows a hint ("No room for
  the bag") and logs it. Body bags and mission items keep the game's rules.
- The swap path now keeps the game's own `can_carry` check, which it used to skip.
- Tests: `loot_tests.lua` now has 31 checks (throwing in a row, room rules); the mock's
  `drop_carry` sets the cooldown like the game: 671 checks.

## 0.15.0 (the Deployable slot, pre-planning, stacks of 100)

- **The game's Deployable slot opens the tactical inventory** instead of the game's
  deployable list, which the mod does not use. New `lua/hooks_menu.lua`, hooked on:
  - `lib/managers/menu/playerinventorygui`: `PlayerInventoryGui:open_deployable_menu`. This is
    the main menu's Inventory screen, and both deployable boxes use it.
  - `lib/managers/menu/missionbriefinggui`: `NewLoadoutTab:open_node(6)` and the older
    `LoadoutItem:open_node(5)`, the deployable item of the briefing's loadout tab.
  The other loadout items still open the game's menus. If the inventory screen cannot open
  (no BeardLib), the game's deployable menu opens.
- **The I key no longer opens the inventory in the main menu** (`run_in_menu: false`). In a
  heist it does.
- **Pre-planning works like the menu.** The heist start no longer stops saving. Saving stops
  when the player spawns: the first frame of `PlayerStandard`, or the first time a weapon's
  planned ammunition is bound, whichever comes first. In the briefing the rig, the backpack
  and what you bring can be changed and are saved to the profile.
- **Loose rounds: at most 100 per stack** (`loose_ammo.max_stack`). New rounds top up the
  open stack, then start a new one. In the menu, loose rounds also come in stacks of 100.
  Older saves with bigger stacks are split into stacks of 100 when loaded. Nothing is dropped.
- Tests: new `menu_tests.lua` (26): 651 checks.

## 0.14.0 (what you bring, per profile)

- **The menu chooses what you bring.** The deployables section is now a loadout screen in the
  menu. The left window chooses the rig and the backpack. The right window has a "Bring into
  every heist" list with - and + per entry: primary and secondary magazines, loose rounds
  (a magazine's worth per click), first aid kits, medic bags, ammo bags and body bags. The
  test spawner and the ammunition summary are shown in a heist only.
- **Magazines are chosen, not spawned.** Planned magazines are items in the grid from the
  menu on. They carry the slot they are for (`plan_slot`). The first time a weapon is used
  in a heist, they become its magazines, full, at the real size. Planned loose rounds become
  the weapon's loose rounds. A gun loaded round by round gets loose rounds instead of
  magazines. The ammunition maximum takes in everything you brought.
- **Every heist starts from the plan.** During a heist (from the moment it loads, briefing
  included) nothing is written to the save. The next heist loads the profile's inventory again.
- **Per-profile inventories.** The inventory is saved per game profile
  (`Global.multi_profile._current_profile`). Profile 1 keeps `pdti_inventory.json`, the others
  use `pdti_inventory_profile<N>.json`. A profile without a file starts as a copy of profile 1.
  The inventory follows the profile when the screen opens and when a heist starts.
- **The menu learns the real magazine size.** A heist writes each weapon's real magazine size,
  feed type and akimbo flag to `pdti_weapons.json`, keyed by weapon and blueprint. Until then
  the menu uses the weapon's base `CLIP_AMMO_MAX` and shows `~`. Planned magazines are resized
  when the weapon or its size changes.
- An inventory that was never opened in the menu works as before: the game's starting
  magazines are made in the heist. The first time it is opened in the menu, those defaults are
  filled in as the plan.
- Tests: new `plan_tests.lua` (51), and the UI tests check the bring list: 625 checks.

## 0.13.0 (akimbo)

- **Akimbo weapons were not managed at all.** The mod skipped every weapon with `_second_gun`,
  assuming it was an underbarrel. That is the field the game's akimbo weapon uses for its
  second gun. Now the akimbo weapon is managed through its main gun, and only the second gun
  itself is skipped.
- **One magazine per gun.** An akimbo magazine holds half the weapon's capacity. The weapon
  starts with twice as many magazines, and they are sized like the magazine of a single gun.
  The mod tracks the rounds of each gun's magazine. The guns fire in turn, so the fuller
  magazine gives the next round.
- **Akimbo reload by taps** (each within 0.5 s of the previous one):
  - 1 tap: both magazines are changed at normal speed, and both old ones go back to the inventory.
  - 2 taps: only the emptier magazine is changed, twice as fast.
  - 3 taps: both are changed 2.5 times as fast, and both old magazines are dropped with their rounds.
  With only one magazine left, a normal reload changes the emptier gun's magazine. When there
  is no free place, the old magazines take the places of the new ones.
- The ammo HUD shows a box per gun and `L x  R y  /capacity`.
- One-gun weapons are unchanged (a double tap is still a 50% faster reload).
- Tests: new `akimbo_tests.lua` (50): 574 checks.

## 0.12.0 (drag and drop, magazines filled one by one, ammunition weight)

- **Drag and drop** instead of click and click. Press on an item, hold, move, let go. While you
  drag, the cells the item would take are tinted: green where it fits, red where it does not.
  The cell under the cursor is the cell you grabbed the item by. Let go over a cell and the
  item goes there; over the inventory but not a cell, or where it does not fit, it stays where
  it was; **outside the inventory windows it is discarded** (a loot bag is thrown). R turns
  the item while you drag it. Ctrl and a press still moves the item to the other side at once.
- **Loose rounds fill one magazine at a time**: the magazine closest to full first, until it
  is full, then the next. Before, they were spread over all magazines (emptiest first).
- **Ammunition weighs by its rounds.** A loose round weighs by its weapon type (pistol 12 g,
  rifle 12 g, sniper 30 g, shotgun shell 45 g, grenade 230 g ...). A magazine weighs the empty
  magazine (60 g + 4 g per round it takes) plus the rounds in it, so a full one is heavier
  than an empty one, and the rig gets lighter as you shoot.
- Tests: new `drag_tests.lua` (37): 524 checks.

## 0.11.1

- **Colour-coded slots**: empty slots show what goes in them. Green: first aid kits and medic
  bags (medical rig). Amber: magazines and loose rounds (ammo pouches, the assault rig's
  ammunition part). Blue: ammo bags. Grey: anything (general rig). Violet: pockets. Brown:
  backpack.
- **The old magazine was lost when the rig and pockets were full.** It was put back before the
  new one was taken out, so there was no room for it. Now, when there is no free place to hand,
  the reload lasts 25% longer and the old magazine goes exactly where the new one was.
- **Tap R twice for a fast reload**: a second tap within 0.5 s of the first starts the reload
  again, so that it ends 50% sooner than a normal one. The magazine that was in the gun is
  dropped and every round left in it is gone. Interrupting it (switching weapons) cancels it.
- The reload speed goes through the game's `reload_speed_multiplier`, so the animation, the
  timer and what other players see stay in step.
- Tests: new `reload_tests.lua` (32): 487 checks.

## 0.11.0 (new rigs and backpacks, magazine sizes by weapon type)

- **Choose the rig and the backpack in the menu.** Outside a heist, the deployable section of
  the inventory screen is replaced by three rigs and three backpacks to click, with what the
  chosen one does. In a heist the equipment cannot be changed. Changing it keeps everything:
  what does not fit the new rig or backpack is moved where it fits (the pockets first); when
  something fits nowhere, the change is refused.
- **Rigs are made of sections**, each with its own rule:
  - Medical: 16 slots (8x2) for first aid kits and medic bags, two ammo pouches (1x3) for
    magazines and loose rounds. Once per heist, while you are down with a medic bag in your
    inventory, SPACE gets you up without help; the medic bag is used up.
  - Assault: 21 slots (7x3) for magazines and loose rounds, 12 slots (6x2) for ammo bags.
  - General: 18 slots (3x6) for anything; 25% faster.
- **Backpacks**: small (10 slots, 5x2, 25% faster), medium (20, 5x4), large (30, 6x5: the
  load and loot slow you 30% less, enemies focus you 50% more). Speed bonuses add up.
- **First aid kits take one slot.**
- **Magazine sizes by weapon type**: each type has its own steps for 2 slots (1x2), 3 in a
  line (1x3) and a 2x2 square: shotgun 6/10/20, assault rifle 30/60/100, SMG 32/50/80,
  pistol 20/33/50, revolver 8/20/40, sniper 10/20/30, LMG 60/100/150, minigun 200/400/700,
  flamethrower 150/300/500. Akimbo magazines (two guns) need twice as many rounds per step.
- Old saves: the old rigs and backpacks are renamed to the new ones; items that no longer fit
  where they were are placed elsewhere.
- The enemy focus goes through the attention weight the game uses for the camouflage skills;
  the enemies are run by the host, so it works when you host or play offline. Getting up uses
  the same message as the Messiah skill.
- Tests: new `gear_tests.lua` (68): 455 checks.

## 0.10.1

- **The screen around the windows was white.** BeardLib draws its full-screen background
  whenever `background_blur` is set, even to `false`, and without the blur texture it is
  white. The key is left out now: the game stays visible around the two windows.
- **No hints when the deployable changes** (X). The HUD line shows the pick.
- **Magazines take space by capacity**: under 30 rounds 1 cell, 30 or more 1x2, 60 or more
  1x3 (one line), 100 or more a 2x2 square. This holds for every weapon, so a pistol
  magazine takes one cell and an LMG box four. Moving, arranging and the room check for new
  magazines all use the size of that magazine.
- Tests: 381 checks.

## 0.10.0 (two small windows, what you place is what you carry, the X key)

- **The inventory screen is two small windows** at the edges of the screen, the middle stays
  free (no blur any more). Left: the loadout (weapons, throwables, armour), the pockets and
  the rig side by side, the deployable, the controls, weight and speed. Right: the backpack,
  the loose rounds and magazines, and the test spawner. Cells are 30 px instead of 38.
- **You can only place what you carry.** A deployable the game gave you (the ammo bag you
  brought) is not placed when there is none in your rig or pockets. Equipment the inventory
  does not manage (a sentry gun, a trip mine) stays the game's.
- **The first deployable found is your deployable**: the pockets first, then the rig, each
  read from the top left. After one is placed, the inventory is looked at again and the next
  one found is the deployable.
- **Your own pick wins**: pick a deployable (X, G on a held item, or the list) and it stays
  your deployable while you carry it, even when another kind comes first. When it is used up,
  the first one found is next. A new heist forgets the pick.
- **X picks the next kind you carry** (two first aid kits and an ammo bag: X goes to the ammo
  bag, X again back to the first aid kit). A sentry gun or trip mine you brought is in the
  cycle after your deployables. X does nothing while you type in the chat.
- **HUD**: a line above the magazine panel shows what G places now (`DEPLOY  First Aid Kit
  x2   [X]`) and changes as soon as the pick or the count changes.
- Tests: 365 checks.

## 0.9.0 (loot, armour and weapons slow you down)

- **Loot bags slow you per bag.** A bag's speed is the game's: its class modifier times the
  carry speed bonus every player has, at most 100% (heavy 75%, slightly heavy 90%, very heavy
  37.5%, light and medium 100%: the wiki's table). Light and medium bags cost 15% each after
  the first; every other bag costs its class penalty again for every bag (one heavy bag 75%,
  two 50%). Bags in your hands and in the inventory count alike; the game's own slowdown for
  the bag in your hands is replaced, so it is not counted twice. The carry skills still work.
  Loot bags no longer count as kilograms. You never drop below 10% speed.
- **Loadout slots**: primary, secondary, throwables and armour are shown with their weight.
  A weapon weighs by its category and its concealment (a pistol is always lighter than an
  assault rifle; better concealment is lighter; akimbo weighs twice). Throwables weigh per
  piece you still carry; perk deck abilities weigh nothing.
- **Armour**: the game's armour slowdown is taken out of its speed calculation and the armour
  slot applies exactly the same value (skills that reduce it still count). Its kilograms are
  shown but not counted again in the load.
- The speed is applied through `PlayerManager:movement_speed_multiplier`, the multiplier the
  game itself uses, instead of rewriting the speed table (that never had an effect in game).
  The screen shows the breakdown: load, armour, loot.
- Tests: new `speed_tests.lua` (34): 327 checks.

## 0.8.1 (fixes the in-game test of 0.8.0)

- **Crash with G while carrying a bag** (`hudinteraction.lua:88: _interact_circle is nil`).
  The game holds the deploy key back while a bag is carried (tap throws, hold deploys) and
  passes it on when the key is let go; the mod then started a deploy action of its own while
  the bag was thrown. The mod's key now never starts an action while a bag is carried, while
  the game's deploy key is held, or within 0.5 s of the game seeing it.
- **Deploying an item you did not bring** (a doctor bag when an ammo bag was brought) showed
  "wrong place" and no model: the game checks the placement only for equipment you brought.
  `PlayerManager:check_equipment_placement_valid` now checks the inventory's item itself.
- **Loose rounds no longer go into the magazine in the gun** (hold R or an ammo bag); they
  only go into the magazines in the rig and pockets.
- **Starting magazines go into the backpack** when the rig and pockets are full; the primary
  gets the first places. Single-shot weapons (one round) are loaded from the loose rounds.
- **Testing panel**: only items that do something (the deployables) can be spawned; new
  buttons spawn loose rounds or a full magazine for the primary and the secondary.
- Tests: 296 checks.

## 0.8.0 (fixes the in-game test of 0.7.1)

- Loose rounds never become a new magazine: packing (hold R) and the ammo bag only fill
  magazines in the rig and pockets and the one in the gun. Empty magazines taken out of
  the gun are kept as items. A magazine weapon only reloads with a magazine that has rounds.
- Weapons loaded round by round take their ammunition from the loose rounds and have no
  magazines: shell-by-shell shotguns (this fixes their infinite ammunition), double-barrelled
  shotguns, bows, crossbows, grenade launchers and single-loading rifles.
- Ammunition pickups follow the game: a box is taken even when it rolls less than one
  round; the fraction is kept for the next box (grenade launchers can be refilled again).
  The pickup skills of the game count.
- The HUD follows the inventory: any change updates the totals, both counters and the panel.
- Several loot bags: one in your hands, the rest in the inventory; throwing a bag brings
  the next one into your hands. Host and offline only; as a client one bag, as in the game.
- Primary ammunition is orange (`PRI`), secondary blue (`SEC`).
- Ctrl+click moves an item between rig/pockets and backpack.
- The NQR-only hooks are optional; the log line `the ammunition hooks are in place` shows
  up without NQR. A missing required hook is logged as `waiting for: ...`.
- `Ammo.MagAmountFor` was nil (assigned before its function existed); picking up a
  dropped magazine would have failed.
- Tests: new `feed_tests.lua` (63); the runner uses the interpreter it runs with (luajit,
  lua, texlua) and fails a file that prints no summary: 275 checks in total.

## 0.7.1 (fixes the first in-game test of the merged mod)

- The ammunition hooks are installed as soon as the game loads its weapon classes. In
  0.7.0 the installation was given up after the first try, so the reload, the pickup and
  the loose ammunition never ran: the game reloaded like vanilla and the magazines filled
  themselves. The log now says `the ammunition hooks are in place`.
- A deployable is placed through the deploy action of the game, so the player kneels
  down, the timer of the game runs and the item appears. Before, it appeared at once.
- The magazine panel follows the gun: it is refreshed when the clip or the weapon
  changes, so it no longer needs a reload to update.
- The ammunition of an ammo bag fills the magazines at once, like the original mod.
  What does not fit stays loose ammunition.
- Tests: a new `install_tests.lua` (16) covers the late installation of the hooks and
  the ammunition that follows it: 212 checks in total.

## 0.7.0 (the InsurgencySandstormStyleReload mod is merged in; not yet verified in-game)
- **One list for the ammunition.** The magazine supply is the inventory. The magazine queue of ISSR is gone: a magazine in the rig or the pockets is ready for a reload, a magazine in the backpack is carried but not ready, and nothing else exists. Moving or throwing away a magazine can therefore no longer make the mod invent a magazine that is nowhere in the inventory.
- **The loose rounds are the inventory.** Picking up ammunition puts the rounds into a `Loose Ammunition` stack (pockets, then rig, then backpack); the size of the stack is the number of rounds. Packing a magazine takes the rounds out of that stack, so the loose ammunition you carry really is the ammunition that gets used. The weapon's ammunition total is the magazine in the gun, the loose rounds and the rounds in the magazines you carry.
- **The reload code of ISSR, rewired.** The tap-to-reload, the hold-to-pack, the ammo pickup, the ammo bag and the HUD panel are the code of the InsurgencySandstormStyleReload mod, with the inventory as the supply. The settings of that mod are still read from `issr_settings.txt` and `issr_reload_settings.txt`.
- **The old InsurgencySandstormStyleReload mod must be removed.** Both mods hook the same reload functions otherwise. The API of ISSR is still exposed as `ISSR.api` for mods that read it.
- **Deployables place now.** The placement failed because the game's placement functions call `PlayerEquipment:valid_shape_placement` without the equipment data, and that function needs the data to create its placement dummy. The game creates the dummy while it checks the placement; calling the placement function directly skipped that step and died with an error. The mod checks the placement first, so the dummy exists and the item is placed. The item leaves the rig or the pockets, and the game's own equipment count is left alone.
- **The game deploys the item of the inventory.** `PlayerManager.selected_equipment`, `can_use_selected_equipment` and `use_selected_equipment` are patched (`lua/hooks_player_manager.lua`), so the game's own deploy action places the item you picked. While the mod places the deployable itself, the game does not start its deploy action, so one key press cannot place two things.
- **Loot costs space and weight.** While the player carries a bag of loot (the game's carry system), a `Loot Bag` item lies in the rig or the backpack (4 kg a bag). The game keeps carrying the bag, so the money is still paid out; when the bag is banked or dropped, the item goes away with it. (The game's "body bags" are for carrying corpses and are not loot.)
- New modules: `lua/ammo.lua` (the ammunition model), `lua/ammo_hooks.lua` (the game hooks), `lua/ammo_hud.lua` (the HUD panel), `lua/loot.lua` (the loot bags). Removed: `lua/magazines.lua`, `lua/loose_ammo.lua`, `lua/issr_bridge.lua`, `lua/hooks_equipment.lua`.
- New API: `PDTI.Ammo.*`, `PDTI.Loot.*`, `PDTI.FindItems`, `PDTI.Deployables.SyntheticEntry`.
- Save schema v6. A new heist clears the ammunition and the loot; the rest of the inventory is kept.
- The game's own equipment is left alone: if the selected equipment is a sentry gun or a trip mine, that key press places it and the inventory keeps its hands off. The four bag and kit types are the ones the inventory replaces.
- Tests: `ammo_tests.lua` (35, against a fake game: the supply, the reload, the pickup, the ammo bag, packing), `loot_tests.lua` (11), `deployable_tests.lua` (46), hooks 18, UI 62, core 21: 193 checks in total.
- Not verified in-game: the placement, the loot bags, the speed factor and the reload still need a run in PAYDAY 2.

## 0.6.0 (loose ammunition, deployables and carry weight; not yet verified in-game)
- **Loose ammunition is real inventory now.** Picked up rounds land in the inventory (pockets first, then rig, then backpack) as a `Loose Ammunition` item, and the amount of rounds is the size of the stack. New module `lua/loose_ammo.lua`: ISSR's loose counter stays the authority, the inventory is its mirror. Rounds that are packed into a magazine leave the inventory, rounds the player throws away leave the counter too, and a restored save is adopted instead of being wiped. The weapon's ammunition total, the pickup limit and the ISSR HUD are unchanged, because the counter still holds every round.
- **How many deployables you can place is what you carry.** The rig and the pockets are "to hand": three ammo bags in the rig mean three ammo bags you can place. A deployable in the backpack is carried but cannot be placed (same rule as magazines).
- **You pick the deployable yourself.** In the inventory screen you hold an item and press the deployable key (G, the same key the game uses for "Deploy Equipment") to make it your deployable; the side column also lists every deployable with the amount you carry. Outside the screen the same key places it. The pick is saved. While the inventory manages the deployable the game stops placing one by itself, so one key press never places two things. "Use the game's deployable" gives the deploy back.
- **Carry weight slows you down.** Up to 15 kg you run at full speed, from 60 kg you are 40% slower (`lua/carry.lua`). Tune `PDTI.Carry.FREE_WEIGHT`, `FULL_WEIGHT` and `MIN_FACTOR`, or set `PDTI.Carry.enabled = false`.
- New items: `Loose Ammunition` (stack of rounds, 0.012 kg per round), `Loot Bag` (deployable). The ammo bag, doctor bag and first aid kit are now deployables and may be carried in the pockets when they fit.
- New API: `PDTI.GetDeployable`, `PDTI.SetDeployable`, `PDTI.EditItems` with `set_amount`, `PDTI.LooseAmmo.*`, `PDTI.Deployables.*`, `PDTI.Carry.*`. The view model carries the deployable list, the loose ammunition and the speed factor.
- Save schema v5: the picked deployable is part of the save and survives a reload.
- New hook on `lib/managers/playermanager` (`lua/hooks_player_manager.lua`).
- Tests: `loose_ammo_tests.lua` (37, includes ISSR's own code when `ISSR_PATH` is set), `deployable_tests.lua` (44), magazines 59, UI 63, hooks 13, core 21, and 18 built-in self tests. `tests/run_all.lua` runs them all.
- Not verified in-game: the placement is now instant instead of hold-to-place, the speed factor needs a look at real movement values, and the loot bag placement is best effort.

## 0.5.0 (gameplay integration, not yet verified in-game)
- Reloading uses the magazines in the rig and pockets. `lua/magazines.lua` keeps ISSR's magazine queue and the inventory in step: ISSR owns the rounds, PDTI owns the carrying space. Only rig/pocket magazines are in the queue; a magazine moved to the backpack leaves it (keeping its rounds) and returns when moved back. Magazines that do not fit become loose rounds, so no ammunition is created or lost.
- Magazines are created from ISSR's queue at the start of each heist (last heist's magazine items are cleared) and show as `rounds/capacity`. The supply list no longer offers magazines.
- Placing a doctor bag, ammo bag or first aid kit needs the item in the inventory and consumes it (`lua/deployables.lua`, wraps `PlayerEquipment:use_*`). A deployable must still be equipped in the normal loadout.
- While the inventory screen is open no input reaches the player (`PlayerStandard._get_input` returns empty input), in addition to the controller block.
- New `PDTI.EditItems` (several item edits, one save, all or nothing).
- Fixed in testing: a failed disk save during magazine sync was mistaken for "no room".
- Tests: `magazines_tests.lua` (57, includes ISSR's own reload code when `ISSR_PATH` is set), `hooks_tests.lua` (13), UI 62, core 21.

## 0.4.2 (click fix, not yet verified in-game)
- Clicks: the window runs with `auto_align = false`, which per the BeardLib docs requires a manual `AlignItems(true)`; it was never called, so items were probably never positioned. Now called after every redraw.
- Removed `bg_callbacks` (docs: usually off).
- Fixed a layout bug found by the new layout tests: the control buttons overlapped the Magazines column. The info rows now sit below both.
- Tests: layout checks (no overlaps, nothing outside the window, fits 1280x720, aligned after every redraw). 61 UI checks, 21 core.

## 0.4.1 (in-game feedback fixes, not yet verified in-game)
- Game input is blocked while the screen is open (player controller disabled, previous state restored on close) so keys like R no longer reach the game. Uses `unit:base():controller():set_enabled()`; if the game rejects it the reason is written to the BLT log as `[PDTI UI] input not blocked: ...`.
- Esc closes the screen (BeardLib key trigger). Esc may also open the game's pause menu; see README.
- Added a Supplies column: one button per registered item, click to add one unit to the selected container (falls back to backpack, rig, pockets). Without a source of items the grids were always empty.
- Added "Discard held".
- Added a read-only Magazines (ISSR) column showing each equipped weapon's real queue: chamber, spare magazine rounds, loose rounds. In the main menu it says it is available during a heist. Moving live magazines is intentionally still not implemented (needs a safe ISSR transfer API).
- Tests: 55 UI checks (was 37).

## 0.4.0 (UI prototype, not yet verified in-game)
- Added an inventory screen built on BeardLib's MenuUI (`lua/ui_beardlib.lua`): pockets, rig and backpack grids, item labels coloured by category, weight/capacity line, status line.
- Click-to-pick-up / click-to-place with rotation (button or R key), cancel, per-container auto-arrange and next-backpack / next-rig buttons. All writes go through the validated PDTI API; invalid placements are rejected with the reason shown and nothing changes.
- New renderer-independent interaction layer (`lua/ui_interaction.lua`).
- Toggle with the "Toggle Tactical Inventory" keybind (set it in the BLT keybinds menu). Closing never changes inventory state.
- `main.lua` is now hooked in the main menu as well as in heists and loads only once per session.
- BeardLib is optional at load time: without it the screen logs a message and everything else keeps working.
- Added `tests/ui_tests.lua` (36 checks) and `tests/mock_env.lua`, a fake MenuUI that rejects parameters not in the BeardLib docs.
- Not done yet: drag and drop, icons/tooltips, hover preview, controller navigation, quick-access use, ISSR magazine display in the screen.

## 0.3.1
- Fixed item-use duplication: `PDTI.UseItem` now reserves (removes and saves one unit) before running the gameplay handler, and refunds the unit through the new `PDTI.RestoreItemUnits` if the handler fails or errors. A failed save can no longer grant a free effect; a crash mid-use can only lose an item, never duplicate it.
- Added `tests/run_tests.lua`, a self-contained offline regression suite (21 checks: rollback on failed saves for add/remove/move/auto-arrange, unwritable save directory, item-use reserve/refund, save recovery from truncated, empty, missing and fully corrupt files). Replaces the old prose-only test report.
- Audit note: the file-handle leak and `AutoArrange` commit-before-save problems described in the project handover were already corrected in 0.3.0; tests now cover them.

## 0.2.0
- Reworked inventory data model and public API.
- Added schema version 2 and migration of the 0.1.0 save layout.
- Added detached read snapshots to prevent accidental external mutation.
- Added backpack and tactical-rig equipment definitions.
- Added per-container weight limits and rig category restrictions.
- Added grid validation, rotation, first-fit placement and move rollback.
- Added stack splitting and merging.
- Added pockets and quick-access view data.
- Added extensible item registration.
- Replaced the initial ISSR bridge with an adapter matching the uploaded mod's actual API.
- Added ISSR magazine snapshots without removing or changing magazine queue entries.
- Added 7 built-in model tests and an inventory UI specification.

## 0.1.0
- Initial inventory data-model prototype.
- Basic pockets, rig and backpack containers.
- Initial read-only ISSR bridge concept.

## 0.3.0
- Bumped save schema to v4 with migration from the 0.1.0/0.2.0 layouts.
- Added temporary-file saves, `.bak` recovery and recovery-safe handling of malformed primary saves.
- Added rollback when local inventory mutations cannot be persisted.
- Preserved unknown optional-mod item instances and custom backpack/rig selections until their definitions register.
- Added third-party backpack/rig registration with definition validation.
- Added occupancy maps and deterministic first-fit auto-arrangement.
- Added registered item-use handlers; an item is consumed only after its handler reports success.
- Added UI interaction state and request APIs for selection, move, rotate, equip and arrange.
- Added runtime diagnostics and inventory-state validation.
- Reworked ISSR snapshots to read existing `ISSR.mags` queues without calling lazy `queue_of()` or mutating magazine state.
- Expanded self-tests to 12 checks; LuaTeX integration and recovery/migration smoke tests passed.
- Graphical UI, live magazine transfer, actual item effects, multiplayer synchronization and in-game testing remain future work.
