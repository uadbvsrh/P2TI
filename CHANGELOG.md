# Changelog

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
