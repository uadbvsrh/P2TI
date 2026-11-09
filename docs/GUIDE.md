# PAYDAY 2: Tactical Inventory: detailed guide

Per-release technical notes are in `CHANGELOG.md`; the vision and goals are in `README.md`.

An extraction-shooter inventory for PAYDAY 2: grid backpacks, tactical rigs, quick-access
pockets, magazines and loose ammunition that are real inventory items, deployables that
follow what you carry, loot that costs space and weight, and a movement penalty for heavy
loadouts.

**0.7.0 merged the InsurgencySandstormStyleReload mod into this mod.** The magazine supply
is no longer a second list next to the inventory, it *is* the inventory. Remove the old
`InsurgencySandstormStyleReload` folder from `mods/`.

## What changed in 0.18.7

- **Prices are now real money.** In 0.18.5 the price was only taken when a heist started, so
  building a plan in the menu cost nothing. Now everything is paid from your spending cash
  when you add it.
  - `+` in the menu pays at once, and `-` pays it back. You never get back more than you paid,
    so a plan from before 0.18.7, or the one the menu fills in for you, was free and gives
    nothing back.
  - `+` refuses what you cannot afford, with the price and your money.
  - The menu shows what your loadout is worth and your money. Each deployable row shows its
    price, and the `+Mag` row shows the next magazine's.
- **Everything costs money, deployables included.** First aid kit $4,000, doctor bag $12,000,
  ammo bag $10,000, body bags $3,000, and so on (`Ammo.PRICES.item`; an item mod can give its
  definition a `price`). Ammunition keeps its 0.18.5 prices.
- **What a heist uses up is paid again.** The plan comes back every heist, so what you use is
  bought again to restock it, as you use it (at most once a second):
  - every round fired, by its bullet;
  - every kit or bag placed or used, and every item left behind;
  - every throwable thrown ($2,500; perk-deck abilities are free).
  - Never more than the plan brought: rounds from ammo boxes and bags, and grenades picked up,
    are free to use. A reload, or a magazine dropped with rounds in it, is not a round used.
  - The old full charge at the start of every heist is gone.
- **Fix: errors in the game log in the menu.** The inventory screen asked the game for your
  throwables' count and your carried loot in the menu, where neither exists. The game logged
  these errors even though they were caught. It now asks only in a heist.

## What changed in 0.18.6

- **A black arm cannot fire its akimbo gun.** The left gun is in the left hand, the right gun in
  the right: with the left arm at 0 the left gun does not fire, whichever button or fire mode
  you use, and the right gun keeps working. Both arms black: the akimbo guns cannot fire at all.
  - No empty click (the gun is not empty); a hint says which arm it is, at most every 2 s.
  - It also applies when the per-button akimbo controls are turned off.
  - A medic bag heals the arm and the gun fires again. The health window lists it.
  - Other weapons still fire with a black arm (with more recoil and spread, as before).

## What changed in 0.18.5

- **Ammunition costs money.** What the menu plan brings is bought at the start of every heist
  (the heist restocks it), and a hint shows what it cost.
  - Every round has a price: standard $30, hollow point $90, armour piercing $180.
  - Every magazine costs its case by size (compact $600, standard $1,000, extended $2,000,
    drum $5,000) plus its rounds. A standard 30-round magazine of standard rounds is $1,900;
    a drum of 75 armour-piercing rounds is $18,500.
  - Loose rounds cost their rounds. Weapons without sizes and bullets count as standard
    magazines of standard rounds.
  - The menu shows "Ammo cost per heist" and your money, and the `+Mag` row shows what the
    next magazine costs. `+` refuses what you cannot afford.
  - All prices are in `Ammo.PRICES` (`lua/ammo.lua`).
- **Ammo bags restock magazines.**
  - Every magazine you carry for the weapon is filled to full with its own bullets: a
    half-empty AP magazine comes back full of AP.
  - Then new full magazines of the kind chosen in the menu (`+Mag`: size and bullets) are
    added, up to the number of magazines you may carry, as far as there is room.
  - A bag gives no loose rounds. A nearly empty bag gives what it has left.
- **Ammo boxes give standard loose rounds only.** This was already the rule, and a new test
  now plays 40 random heists (a rifle and akimbo SMGs: shots, reloads, boxes, holding R,
  magazines in and out of the weapon's slot). It checks that AP and hollow-point rounds never
  appear out of nowhere. I could not reproduce special rounds coming from boxes; if it happens
  again, note what you did just before.

## What changed in 0.18.4

- **Fix: the crash when shooting after a few minutes in a heist.** In 0.18.2 and 0.18.3 the AP
  recoil and the arm health both hooked the game's recoil. They wrapped each other again every
  frame, so the chain grew until a shot overflowed the stack: the crash in `ammo_hooks.lua` and
  `body.lua`. It was not tied to the grenade launcher, which was just the gun in hand.
  - The same bug multiplied the recoil again with every frame, so AP recoil grew absurd long
    before the crash. Recoil is back to the intended values (AP ×1.5 up to ×2.4, a black arm
    ×1.35).
  - Every hook of the mod now knows which parts of the mod are already in its chain, so two
    parts hooking the same function never stack up again.

## What changed in 0.18.3

- **Fix: body parts use your build's full health.** The health from skills and perks (Stoic,
  armour converted to health, health skills) now reaches every body part from the moment you
  spawn. Before, the parts only learned your real max health at the first hit, so until then
  the screens showed the base 230.
- **Fix: a change of max health during a heist** (an armour change, a perk) no longer makes the
  game's health and the parts' sum drift apart.

## What changed in 0.18.2

- **Armour-piercing rounds are less stable.** Every AP shot kicks 1.5 times as hard as the
  gun normally does.
  - In full auto the kick builds up with every shot in a row, by +10% of that per shot, up
    to 2.4 times the gun's own recoil from the seventh shot on. Long bursts climb away from
    the target; short bursts and aimed single shots stay controllable.
  - A pause of about one and a half shot intervals settles the gun again. Spamming the
    trigger faster than that still counts as a burst.
  - The build-up follows each gun's own rate of fire.
  - In a mixed magazine only the AP rounds kick harder. Standard and hollow-point rounds keep
    the gun's recoil.
  - Black arms (body health) make it worse on top.

## What changed in 0.18.1

- **A health window in the inventory screen.** In a heist a third window, at the bottom
  middle, shows your body:
  - Every part is a box in the shape of a body, with its HP and its maximum
    (`L ARM 16 / 31`).
  - The colour shows how much is left: green (60% or more), yellow (30% or more), red, and
    black at 0.
  - The total is on top, as the game counts it.
  - Below, what your black parts do now (`A leg black: no sprinting, speed 85%`), and what
    heals what.
  - It updates while the screen is open, so you see a hit land.

## What changed in 0.18.0

- **Loading magazines is silent.** Holding R to fill magazines no longer plays a sound for
  every round.
- **Health per body part.** Your health is split into head, body, left and right arm, and left
  and right leg. The health ring shows their sum. See [Body health](#body-health).

## What changed in 0.17.2

- **Akimbo guns follow the mouse buttons.** The left button fires the left gun, the right
  button fires the right gun. The right button no longer aims while akimbo guns are out.
  - Each gun fires from its own magazine with its own bullets, so hollow points on the left and
    armour piercing on the right fire exactly where you click.
  - Hold both buttons on full auto and both guns fire. In single fire, each new press is a shot,
    even while the other button is held.
  - An empty gun only clicks; the other one keeps firing.
  - Only for magazine-fed akimbo guns. Other weapons aim with the right button as before.
  - To get the game's own akimbo controls back, set `"akimbo_buttons": false` in
    `issr_reload_settings.txt`.

## What changed in 0.17.1

- **The magazine in the gun really is in the weapon's slot.** In a heist the slot shows the
  magazine that is loaded, and its rounds follow your shots.
  - **Take it out** (drag it into the rig, pockets or backpack, or Ctrl+click): the gun has no
    magazine, and only a round in the chamber stays. The magazine keeps its rounds and bullets.
  - **Put one in** (drag a magazine of that weapon into the empty slot): it goes into the gun
    at once. The clip, size and bullets are the new magazine's.
  - Throw it away and the gun is empty, with the rounds gone.
  - Akimbo guns: each half of the slot is one gun's magazine. Take one out and that gun is
    empty; two taps of R then fill the empty gun and leave the other one alone.
  - During a reload the old magazine leaves the slot, and the new one appears when the reload
    ends.
- In the menu the slot still holds the magazine the heist starts with, as in 0.17.0.

## What changed in 0.17.0

- **The weapons are part of the inventory.** The primary and the secondary each show as a box
  (name and weight) with a **magazine slot** next to it (two cells for akimbo guns). Any
  magazine of that weapon fits in it, whatever its size.
  - In the menu, the magazine in the slot is the one the heist starts with in the gun. Drag
    a drum of hollow points there, and that is what you start with.
  - In a heist, a magazine you put in the slot is the next one a reload takes, before the
    pockets and the rig.
  - Ctrl+click takes it out again.
  - Plans from 0.16.0 get the magazine of their old "Gun" choice put in the slot once.
- **Mixed magazines.** A magazine can hold several bullet types, in order. The rounds on top
  are fired first.
  - In the menu, "+Mag" has a size and a count per bullet type (STD / HP / AP, 5 rounds per
    click, never over full).
  - Example: 10 AP on top of 10 HP in a compact magazine. **Flip** turns the order over.
    Fewer rounds than the magazine holds is fine too.
  - Each shot uses the bullet it fires: the first 10 shots are armour piercing, then the
    hollow points. Damage, plates, shoot-through and limb crits follow every round.
  - A magazine taken out of the gun keeps what is left in it, in order.
  - Packing loose rounds (hold R, ammo bags) puts the magazine's own top type in first, then
    any other type on top.
- **Ammo colours.** Standard rounds keep the weapon's colour (orange PRI, blue SEC), hollow
  points are red, armour piercing is green. A mixed magazine shows its top round's colour,
  and its label gets a `+` (for example `20 AP+`).
  - The ammo HUD draws each magazine's fill in bands of these colours, bottom to top.
- **Dev spawner:** a Bullets row (STD / HP / AP) picks what the PRI/SEC magazine and loose
  buttons spawn, e.g. "PRI magazine HP".
- The throwable and the armour now share one line, so the left window stays within the
  screen.

## What changed in 0.16.0

Assault rifles and SMGs (akimbo SMGs too) now take magazines of four sizes and three kinds
of bullets. Each magazine has its own size and bullets, and the magazine in the gun decides.

| Size | Rounds | Reload time |
|------|--------|-------------|
| Compact | x0.65 | x0.85 |
| Standard | x1 | x1 |
| Extended | x1.5 | x1.15 |
| Drum | x2.5 | x1.5 |

The sizes are relative to the weapon's own magazine. Bigger magazines also take more room
and weigh more. The game's magazine mods no longer change the magazine on these weapons.

| Bullets | Damage | Armour plates | Shoots through | Extra |
|---------|--------|---------------|----------------|-------|
| Standard (STD) | x1 | the weapon's | the weapon's | |
| Hollow point (HP) | x1.3 | never pierces (the AP skill does not apply) | nothing | every hit on an arm or a leg is a critical hit |
| Armour piercing (AP) | x0.85 | always pierces | enemies and shields | less stable: recoil x1.5, building up to x2.4 in full auto |

- **In the menu** (the Deployable slot), for an assault rifle or SMG:
  - **Gun** picks the size and bullets of the magazine you start with in the gun.
  - **+Mag** picks what the `+` of the magazine row adds.
  - Loose rounds are brought by bullet type (STD / HP / AP).
  - Example: a drum of hollow points in the gun, and the rig full of compact AP magazines.
- **Reloads take magazines in grid order**, the order you put them in: pockets first, then
  the rig, each read from the top left. The first magazine with rounds is loaded. This
  replaces "fullest first" for every magazine weapon.
- **Magazines keep their bullets.** A magazine you take out keeps its size and its bullets.
  Packing loose rounds (hold R, ammo bags) puts only matching bullets into a magazine; an empty
  magazine takes any bullets and becomes that kind. Ammo pickups and ammo bags give standard
  rounds.
- The grid shows a typed magazine as `28 HP`, and the ammo HUD shows the loaded magazine (for
  example `NEXT 75/75  D/HP`).
- Shotguns, snipers, LMGs, pistols and special weapons are unchanged.

## What changed in 0.15.1

- Loot bags: after a throw, the next bag is in your hands at once, so you can throw them one
  after another (before, you waited 1.2-1.5 s).
- You can no longer pick up more loot bags than you have room for. A bag needs a free place
  in the rig or the backpack; without one it stays on the floor and a hint says why.

## What changed in 0.15.0

- **The Deployable slot of the loadout opens the tactical inventory**: in the main menu's
  Inventory screen, and in the briefing's loadout tab (pre-planning). There you choose the
  rig, the backpack and what you bring. The I key no longer opens it in the main menu; in a
  heist it still does. Without BeardLib the game's deployable menu opens as before.
- **The briefing counts as the menu**: you can change the rig, the backpack and what you bring
  there, and it is saved to the profile. Saving stops when you spawn.
- **Loose rounds come in stacks of at most 100.** More rounds start a new stack. Older saves
  with bigger stacks are split when loaded.

## What changed in 0.14.0

- **Choose what you bring in the menu.** Open the inventory in the menu. The left window
  chooses the rig and the backpack. The right window lists what you bring, with **-** and
  **+** for each entry: primary and secondary magazines, loose rounds for each gun (a
  magazine's worth per click), first aid kits, medic bags, ammo bags and body bags. They are
  real items in the grid, so you can drag them where you want them.
- **Every heist starts with exactly what you chose.** Nothing is saved during a heist. What
  you use, drop or discard is back in the next one, in the same places.
- **The inventory belongs to the game profile.** Each profile has its own rig, backpack and
  items. Switching profiles in the menu switches the inventory. Profile 1 keeps the old save,
  and other profiles start as a copy of it.
- Magazines show the weapon's own size until it has been used in a heist (`~30`). After
  that, the menu knows the real size with every mod and skill. The first time the inventory
  is opened in the menu, the game's starting magazines are filled in for you.

## What changed in 0.13.0

- **Akimbo guns work with the ammunition system** (they were skipped entirely before). Each
  gun has its own magazine with half the weapon's capacity, so an akimbo weapon starts with
  twice as many (smaller) magazines. The guns fire in turn, and the HUD shows a box per gun.
- Akimbo reload: tap **R** once to change both magazines at normal speed. Tap twice to change
  only the emptier one, twice as fast. Tap three times to change both, 2.5 times as fast, and
  drop both old magazines with their rounds. Each tap must come within 0.5 s of the one before.

## What changed in 0.12.0

- Drag and drop: press on an item, hold, move, let go. The cells it would take are shown green
  (fits) or red (does not). Let go outside the inventory windows to discard it (loot bags are
  thrown). R turns it while dragging; Ctrl and a press still moves it to the other side.
- Loose rounds fill the magazine closest to full first, one magazine at a time.
- Magazines and loose rounds weigh by their rounds and weapon type.

## What changed in 0.11.1

- Empty slots are coloured by what goes in them (green medical, amber ammunition, blue ammo
  bags, grey anything, violet pockets, brown backpack).
- No free place for the magazine coming out of the gun: the reload lasts 25% longer and the
  old magazine takes the place of the new one (it used to be lost).
- Tap **R** twice: the reload is 50% faster, but the old magazine and its rounds are dropped.

## What changed in 0.11.0

Choose the rig and the backpack in the inventory screen while you are in the menu.

| Rig | Sections | Extra |
|---|---|---|
| Medical | 8x2 kits and medic bags, 2 pouches 1x3 for magazines and loose rounds | once per heist: SPACE while down gets you up, uses a medic bag |
| Assault | 7x3 magazines and loose rounds, 6x2 ammo bags | |
| General | 3x6 anything | 25% faster |

| Backpack | Slots | Extra |
|---|---|---|
| Small | 10 (5x2) | 25% faster |
| Medium | 20 (5x4) | |
| Large | 30 (6x5) | load and loot slow you 30% less; enemies focus you 50% more (host/offline) |

First aid kits take one slot. Magazines take 1, 2 (1x2), 3 (1x3) or 4 (2x2) slots by their
capacity, with steps for each weapon type (shotgun 6/10/20, assault rifle 30/60/100,
SMG 32/50/80, pistol 20/33/50, revolver 8/20/40, sniper 10/20/30, LMG 60/100/150).

## What changed in 0.10.1

- The game is no longer covered by a white screen while the inventory is open.
- Picking a deployable with X shows no hint (the HUD line shows it).
- Magazines take space by capacity: under 30 rounds 1 cell, 30+ 1x2, 60+ 1x3, 100+ 2x2.

## What changed in 0.10.0

- The inventory screen is two small windows at the screen edges; the middle stays free.
  Left: loadout, pockets, rig, deployable, controls. Right: backpack, ammunition, test spawner.
- You can only place a deployable that is in your rig or pockets, even the one you brought.
- The first deployable found (pockets, then rig, from the top left) is your deployable
  unless you picked one yourself. **X** picks the next kind you carry and wraps around.
- A HUD line above the magazine panel shows what **G** places now.

## What changed in 0.9.0

Your speed is load x armour x loot (never below 10%):

| Part | Rule |
|---|---|
| Load | Grid items (not loot bags) + weapons + throwables. Free up to 15 kg, 40% slower at 60 kg. |
| Armour | Exactly the game's armour slowdown (ICTV -42.5%), now shown in the armour slot. |
| Loot | Light/medium: 15% per bag after the first. Others per bag: slightly heavy 10%, heavy 25%, slightly very heavy 25%, very heavy 62.5%. |

Weapons weigh by category and concealment; the loadout is shown in the inventory screen.

## What changed in 0.8.1

- G while carrying a bag no longer crashes the game.
- A deployable you did not bring shows its model and can be placed.
- Loose rounds only go into the magazines in the rig and pockets, never into the one in the gun.
- Starting magazines go into the backpack when the rig and pockets are full.
- The testing panel only offers deployables, plus loose rounds and full magazines for both guns.

## What changed in 0.8.0

The in-game test of 0.7.1 found these problems:

| Problem in 0.7.1 | What 0.8.0 does |
|---|---|
| Holding R with no magazine in the rig or pockets made a new magazine out of loose rounds. | Loose rounds only go into magazines you carry (and the one in the gun). No magazine is ever made out of thin air. An empty magazine you take out of the gun is kept (rig, pockets, then backpack), so you can pack it again. A magazine weapon only reloads when a magazine with rounds is in the rig or pockets. |
| Pump shotguns had infinite ammunition. The game loads them shell by shell without calling the reload function, and the mod treated them as magazine guns. | Shotguns that load shell by shell, double-barrelled shotguns, bows, crossbows, grenade launchers and rifles loaded one cartridge at a time are **loaded from the loose rounds**. Every shell that goes in leaves the loose stack. They have no magazines; the game's reserve becomes loose rounds at the start. |
| Double-barrelled shotguns used magazines. | See above: they load two shells from the loose rounds. |
| A grenade launcher (pickup below one round per box) could not pick up ammunition boxes. | Like the game, a box is taken even when it rolls less than one round, and the fraction is kept: enough boxes add up to a grenade. The pickup also uses the game's pickup skills now. |
| The HUD only updated when the ammunition changed (a magazine thrown away showed after the next shot). | Every inventory change updates the totals, both ammo counters and the panel in the same frame. |
| Only one loot bag could be carried. | You carry one bag in your hands as in the game; picking up another puts the carried one into the inventory (when there is room). Throwing or securing the bag brings the next stored one into your hands, so you can throw them one after another. The inventory screen can stash the carried bag or take one out, and "Discard held" on a bag drops it. **As a client of another host you can still only carry one bag** (the host counts the bags each player carries and would flag more as cheating). |
| Primary and secondary ammunition looked the same. | Ammunition of the primary is orange and tagged `PRI`, of the secondary blue and tagged `SEC`. |
| (new) Moving items between rig/pockets and backpack took two clicks. | **Ctrl+click** moves an item from the rig or pockets into the backpack, and from the backpack into the pockets (or the rig when the pockets are full). |

Also: the log line `the ammunition hooks are in place` never appeared without the NQR mod,
because two of the hooks only exist with NQR. They are optional now. If a required hook
is missing the log says `waiting for: ...`.

## What changed in 0.7.1

The first in-game test of 0.7.0 found four problems. All of them are fixed:

| Problem in 0.7.0 | What 0.7.1 does |
|---|---|
| The ammunition hooks were never installed: the game loads its weapon classes *after* the mod and the mod did not try again. The result was vanilla reloads, no loose ammunition and magazines that filled themselves. | The hooks go in as soon as the classes exist, and the installation is repeated until every hook is in place. The log says `the ammunition hooks are in place`. |
| The deployable appeared at once when G was pressed. | The key asks the game to start its own deploy action: the player kneels down, the timer of the game runs and the item appears, exactly like in the game. |
| The magazine panel showed full magazines and did not follow the gun. | The panel is marked dirty when the clip or the gun changes, so it is up to date at once. |
| The ammunition of an ammo bag went into the loose ammunition first. | The bag fills the magazines at once, like the original mod; what does not fit stays loose. |

## What changed in 0.7.0

| Problem in 0.6.0 | What 0.7.0 does |
|---|---|
| The loose ammunition in the inventory was a mirror of ISSR's counter | The loose rounds are the inventory. Packing a magazine takes the rounds out of the stack you carry. |
| Moving or throwing away a magazine made ISSR invent a magazine that was nowhere in the inventory | There is only one list. A magazine in the backpack is stored, a magazine in the rig is ready, and nothing else exists. |
| Deployables did not place | The placement now primes the game's placement dummy first. The game's own `use_*` function places the item, and the item leaves the inventory. |
| Loot went into the game's own loot bag | The bag the player carries is a "Loot Bag" item in the rig or the backpack, so it costs space and weight. |
| Two mods had to be installed and kept in step | One mod. Remove the old InsurgencySandstormStyleReload folder. |

## Roadmap status

| Goal | Status |
|---|---|
| 1. Audit original framework and ISSR API | Completed |
| 2. Versioned saves, legacy migration and backup recovery | Implemented; Lua-tested |
| 3. Grid bounds, overlap, rotation and stack operations | Implemented; Lua-tested |
| 4. Backpack and tactical-rig definitions | Implemented |
| 5. Weight limits and container/category restrictions | Implemented |
| 6. Pockets and quick-access data | Implemented as API |
| 7. Extensible item/equipment registry | Implemented, including late-registration recovery |
| 8. Magazine system (merged from ISSR) | Implemented; the inventory is the supply |
| 9. Diagnostics and regression tests | 20 built-in tests plus 212 offline checks passed |
| 10. UI interaction foundation | Selection/move/rotate/equip/arrange API implemented; graphical screen present |
| 11. Loose ammunition in the inventory | Implemented; the rounds are the inventory |
| 12. Deployable count and deployable pick | Implemented; rig/pockets drive the count |
| 13. Movement penalty for heavy loadouts | Implemented; needs in-game tuning |
| 14. Loot bags as inventory items | Implemented; the game still carries the bag |
| 15. Item effects, multiplayer sync | Not implemented |

## Dependencies

- SuperBLT required.
- BeardLib required for the inventory screen (the data layer works without it).
- **The InsurgencySandstormStyleReload mod must be removed.** Its code is part of this mod
  now. Running both means both hook the same reload functions.

## Installation

1. Extract the `Payday2TacticalInventory` folder into `PAYDAY 2/mods/`.
2. Delete the old `InsurgencySandstormStyleReload` folder from `PAYDAY 2/mods/`.
3. Start PAYDAY 2.
4. The mod creates `pdti_inventory.json` in the SuperBLT save directory after the first
   successful inventory change.
5. Check `mods/logs` for `[PDTI]` messages.

Back up your SuperBLT save folder before testing development builds.

## Public API

```lua
-- Definitions
PDTI.RegisterItem(item_id, definition)
PDTI.RegisterEquipment("backpack" or "rig", equipment_id, definition)
PDTI.RegisterItemUse(item_id, callback)
PDTI.UnregisterItemUse(item_id)

-- Read-only state / view models
PDTI.GetState()
PDTI.GetContainer(name)
PDTI.GetContainerInfo(name)
PDTI.GetItemDefinition(item_id)
PDTI.GetItemDefinitions()
PDTI.GetEquipment()
PDTI.GetInventoryViewModel()
PDTI.GetOccupancyMap(container)
PDTI.GetUIState()
PDTI.GetUnresolvedItems()
PDTI.GetUnresolvedEquipment()
PDTI.GetDiagnostics()

-- Inventory operations
PDTI.CanPlace(container, item_id, x, y, rotated, ignore_id)
PDTI.FindFreeSpace(container, item_id, allow_rotation)
PDTI.AddItemAuto(container, item_id, amount, item_data, allow_rotation)
PDTI.AddItem(container, item_id, x, y, rotated, amount, item_data)
PDTI.FindItem(container, instance_id)
PDTI.FindItems(predicate)              -- read-only search, predicate(container, item)
PDTI.RemoveItem(container, instance_id, amount)
PDTI.MergeStacks(container, source_id, target_id, amount)
PDTI.SplitStack(container, instance_id, amount, x, y, rotated)
PDTI.MoveItem(from_container, instance_id, to_container, x, y, rotated)
PDTI.AutoArrange(container, allow_rotation)
PDTI.SetEquipment("backpack" or "rig", equipment_id)
PDTI.GetTotalWeight()
PDTI.GetQuickAccess()
PDTI.UseItem(container, instance_id, context)
PDTI.EditItems({ update = {...}, set_amount = {...}, remove = {...} })

-- Deployables
PDTI.GetDeployable()
PDTI.SetDeployable(item_id)          -- your own pick; nil: the first one found
PDTI.Deployables.Count(item_id)       -- what is to hand in the rig and pockets
PDTI.Deployables.GetOptions()
PDTI.Deployables.Place()
PDTI.Deployables.SetSelection(item_id)
PDTI.Deployables.Manages()
PDTI.Deployables.SyntheticEntry()     -- the equipment entry the game gets
PDTI.Deployables.KEY                  -- the key that places the deployable ("g")
PDTI.Deployables.CYCLE_KEY            -- the key that picks the next kind ("x")
PDTI.Deployables.ToHand()             -- the kinds to hand, in the order they are found
PDTI.Deployables.GetSelection()       -- what G places now
PDTI.Deployables.Cycle()              -- what X does

-- Ammunition (the merged InsurgencySandstormStyleReload system)
PDTI.Ammo.Identify(weapon)            -- key, pid, caliber, capacity of a weapon
PDTI.Ammo.Magazines(key)              -- the magazines of a supply that are to hand
PDTI.Ammo.LooseOf(weapon)             -- the loose rounds you carry
PDTI.Ammo.SetLoose(weapon, rounds)
PDTI.Ammo.ConsumeLoose(weapon, rounds)
PDTI.Ammo.AddLoose(weapon, rounds)
PDTI.Ammo.FillMagazines(weapon, rounds)
PDTI.Ammo.TakeMagazine(weapon)        -- takes the fullest magazine out of the rig
PDTI.Ammo.ReturnMagazine(weapon, rounds)
PDTI.Ammo.SyncTotal(weapon)
PDTI.Ammo.NeedsFill(weapon)
PDTI.Ammo.GetSummary()                -- the loose ammunition you carry
PDTI.Ammo.GetSupplySummary()          -- the magazine supplies you carry
PDTI.Ammo.OnHeistStart()

-- Loot
PDTI.Loot.Count()                     -- the bags of loot you carry
PDTI.Loot.Tick()

-- Carry weight
PDTI.Carry.GetSpeedFactor()
PDTI.Carry.ApplyToState(state)

-- UI interaction controller
PDTI.SetUIVisible(bool)
PDTI.SelectContainer(name)
PDTI.SelectItem(instance_id)
PDTI.RequestMove(from_container, instance_id, to_container, x, y, rotated)
PDTI.RequestRotate(container, instance_id)
PDTI.RequestEquip(kind, equipment_id)
PDTI.RequestAutoArrange(container, allow_rotation)
PDTI.RefreshUI()

-- Diagnostics / persistence
PDTI.ValidateState()
PDTI.RunSelfTests()
PDTI.LogDiagnostics()
PDTI.Save()
PDTI.Reset()
```

Grid coordinates are zero-based. Item dimensions are measured in cells. `rotated=true` swaps
width and height. Read APIs return detached copies; change inventory only through the
provided functions.

## Body health

Your health is split into six parts. The game's health is always their sum, so the health ring,
skills, perks and the other players see it as before. Armour still takes damage first; only
damage that reaches your health hits a part.

| Part      | Share of health | Bullet hits | When it is black (0)                      |
|-----------|-----------------|-------------|-------------------------------------------|
| Head      | 8%              | 6%          | you go down                               |
| Body      | 35%             | 42%         | half the stamina                          |
| Each arm  | 13.6%           | 12%         | recoil ×1.35 and spread ×1.25 (per arm); its akimbo gun cannot fire |
| Each leg  | 14.8%           | 14%         | no sprinting, speed ×0.85 (per leg)       |

- **Where hits land:** bullets roll for a part. Melee hits the head, body or arms. A fall hits a
  leg. Explosions, fire and kill zones spread over every part by its share.
- **Black parts:** damage on a black part, and whatever is left over when a part goes black,
  spreads to the other parts at 70%.
- **Going down:**
  - When your head reaches 0, you go down. A deadly fall or the game forcing you into bleed-out
    does the same.
  - When you are revived, your head has 1 HP. Every other part stays as it was, and black parts
    stay black.
- **Healing:**
  - A first aid kit and every healing skill heal only the parts that are not black.
  - A medic bag heals every part to full, black ones included. So does getting up with the
    medical rig's medic bag.
- **Where you see it:**
  - The HUD shows a small body figure above the health ring: green, then yellow, then red,
    then black.
  - In a heist the inventory screen has a health window: every part with its HP and its
    maximum, coloured the same way, plus the effects of the black parts. The speed line
    shows the leg penalty.
- **Turning it off:** set `"body_parts": false` in `issr_reload_settings.txt` to use the game's
  single health pool.

## Ammunition: the inventory is the supply

The magazine system of the InsurgencySandstormStyleReload mod is part of this mod now. The
reload code, the ammo pickup, the ammo bag and the HUD panel are the ones of that mod; what
changed is where the rounds live.

### Magazines

- A magazine is an item: `Spare Magazine`, with the rounds in `item.data.rounds`.
- A magazine in the **rig or the pockets** is ready: a reload takes it out of the inventory
  and loads it.
- A magazine in the **backpack** is carried but not ready. Move it to the rig or the pockets
  to use it.
- A reload puts the magazine that was in the gun back into the inventory. If there is no
  room for it, its rounds stay with you as loose ammunition.
- When a weapon type is used for the first time in a heist, its starting magazines appear
  in the rig.

There is no second list any more, so nothing can get out of step: throw a magazine away and
it is gone, move one to the backpack and it is out of the supply until you move it back.

### Loose ammunition

- Loose rounds are items too: `Loose Ammunition`, and the size of the stack is the number of
  rounds.
- Picking up ammunition puts the rounds into the inventory (pockets, then rig, then
  backpack).
- Holding **R** packs the loose rounds into the magazines, one round at a time. The rounds
  leave the stack as they go into the magazine, so the loose ammunition you carry really is
  the ammunition that gets used.
- An **ammo bag** restocks magazines (since 0.18.5): every magazine you carry for the weapon
  is filled to full with its own bullets, then new full magazines of the kind chosen in the
  menu (`+Mag`) are added, up to the number you may carry. It gives no loose rounds. Ammo boxes
  give standard loose rounds only.
- The weapon's ammunition total is the magazine in the gun, the loose rounds and the rounds
  in the magazines you carry, so the pickup limit follows what you actually carry.

### The HUD panel

Hold **R** and the panel of the InsurgencySandstormStyleReload mod appears: the magazine in
the gun first, then the magazines that are to hand, and the number of loose rounds. Its
settings are read from the old `issr_settings.txt` and `issr_reload_settings.txt` files, so
the values you already chose survive the merge.

## Deployables

How many deployables you can place is how many you carry **in the rig and the pockets**.
Three ammo bags in the rig mean three ammo bags you can place. A deployable in the
backpack is carried but cannot be placed, the same rule magazines follow.

Which one **G** places:

- **The first one found**: the pockets first, then the rig, each read from the top left
  (top row first, then left to right). After one is placed the inventory is looked at
  again, so a first aid kit in the pockets and an ammo bag in the rig place the kit first
  and then the bag.
- **Your own pick wins** while you carry it. **X** picks the next kind you carry and goes
  back to the first after the last; in the inventory screen, holding an item and pressing
  **G**, or clicking it in the deployable list, picks it too. "First found" in the list
  forgets your pick. A pick that is used up, and a new heist, go back to the first found.
- **What you place is what you carry**: the deployable the game gave you (the ammo bag you
  brought) is not placed when there is none in your rig or pockets. A sentry gun or a trip
  mine you brought stays the game's; it is in the X cycle after your deployables.
- The HUD shows what G places now in a line above the magazine panel.
- G does the placing through the game, so the player kneels down, the timer of the game
  runs and the item appears after the same time as in the game.

The placement uses the game's own code (`PlayerEquipment:use_*`), so the placement raycast,
the spawned unit and the statistics are the normal ones. One item is taken out of your rig
or pockets when the placement worked.

> **Why the placement used to fail.** The game's placement functions call
> `PlayerEquipment:valid_shape_placement` with only the equipment id, but that function
> needs the equipment data to create its placement dummy. The game creates the dummy while
> it checks whether the placement is valid, which happens before the placement function is
> called. Calling the placement function directly skipped that step, and the call died with
> an error instead of placing anything. The mod now checks the placement first, so the
> dummy exists and the placement works.

The key of the mod asks the game to start its own deploy action, and that action places
the item of the inventory, so a single key press never places two things. When the game
does not see the key press itself (the key was rebound), the mod starts the same action
by hand.

The game keeps its own equipment when it is something else: if the selected equipment is a
sentry gun or a trip mine, that key press places the sentry gun, and the inventory keeps its
hands off. The four bag and kit types are the ones the inventory replaces.

The pick is saved with the inventory.

## Loot

In the game, a bag of loot is picked up into the carry system: the player carries one bag on
the back, can drop it and banks it at the escape zone. The bag takes no space in an
inventory, because the game has no inventory.

While the player carries a bag of loot, a **Loot Bag** item lies in the rig or the backpack
here, 4 kg a bag. Carrying loot costs space and weight, and it slows you down like
everything else. The game keeps carrying the bag, so the money is still paid out at the end
of the heist; when the bag is banked or dropped, the item goes away with it.

(The game's "body bags" are something else: they are for carrying corpses.)

## Carry weight and speed

Up to `FREE_WEIGHT` (15 kg) you run at full speed. From `FULL_WEIGHT` (60 kg) on you are
`MIN_FACTOR` (0.6, so 40% slower) times as fast. In between it is a straight line. Tune
the three numbers in `lua/carry.lua`, or switch the penalty off with
`PDTI.Carry.enabled = false`.

The factor is applied to the game's own speed values, so nothing is rewritten under the
game's feet. It is applied to the movement speed table, which every player in the
session shares, so in co-op everybody walks at the speed of the heaviest loadout.

Three ammo bags, a doctor bag and four loot bags is a lot of weight: you can carry it,
but you are a turtle. That is the point.

## UI status

The screen is two small windows at the edges of the screen, so the middle stays free. The
left one shows the loadout, the pockets and the rig, the deployable and the controls; the
right one the backpack, the loose rounds and magazines and the test spawner. There is
drag and drop: press on an item, move it and let go over a cell.

## Not yet implemented

- Multiplayer synchronization and host authority.
- Backpack/rig player models and access animations.
- Item effects for medical and utility items (the item-use API is there, the effects are
  not).
- The loot is still counted in bags; the individual valuables are not items yet.
- Loot rarity (planned for 0.19.0): small valuables become inventory items paid out when you
  escape, and bags get random tiers that depend on where they came from (display cases are
  common, safes roll rarer).

## Testing

Run `PDTI.RunSelfTests()` after the mod loads (20 model checks). Offline:

```
texlua tests/run_all.lua
```

That runs every suite, each in its own process:

| Suite | Checks | What it covers |
|---|---|---|
| `run_tests.lua` | 21 | the inventory model: rollback on failed saves, save recovery, item use |
| `ui_tests.lua` | 89 | the inventory windows (and the health window in a heist) against a fake BeardLib MenuUI, layout, overlap, fit |
| `hooks_tests.lua` | 26 | the hook scripts, mod.txt and the heist start |
| `ammo_tests.lua` | 49 | the ammunition system against a fake game: supply, reload, pickup, ammo bag, packing |
| `install_tests.lua` | 16 | the hooks go in when the game loads its weapon classes late |
| `loot_tests.lua` | 32 | the loot bags that follow the game's carry, nothing asked in the menu |
| `deployable_tests.lua` | 82 | count, first found, own pick, X cycle, blocking, placement, HUD line, carry weight |
| `feed_tests.lua` | 74 | loose-fed weapons, magazines never created, the HUD refresh |
| `speed_tests.lua` | 34 | loot, armour and weapon weight on the speed |
| `drag_tests.lua` | 37 | drag and drop, the fill order, ammunition weight |
| `reload_tests.lua` | 32 | double tap, the swap when there is no room, slot colours |
| `gear_tests.lua` | 68 | rig sections, backpacks, their speed, enemy focus, getting up, magazine sizes, old saves |
| `plan_tests.lua` | 50 | menu plan, per-profile inventories, every heist starting from the plan |
| `menu_tests.lua` | 26 | the Deployable slot opens the inventory, the briefing is the menu, stacks of 100 |
| `akimbo_tests.lua` | 50 | akimbo: half-size magazines, one per gun, 1/2/3 taps, no room, packing, HUD |
| `gun_slot_tests.lua` | 44 | the magazine in the gun in the weapon's slot: out, in, reloads, akimbo halves, the screen |
| `recoil_tests.lua` | 14 | AP recoil: x1.5 per shot, the full-auto build-up and its x2.4 cap, a pause resets it, fast taps count, the rate of fire, mixed magazines, other bullets and weapons untouched |
| `hook_chain_tests.lua` | 5 | two parts of the mod on one game function: no re-wrapping over 100 frames, recoil applied once per part, re-wrapped once after another mod replaces it |
| `bag_price_tests.lua` | 57 | boxes give standard rounds only, bags refill magazines with their own bullets and add new ones of the menu choice, nearly empty bags, prices by size and bullet, `+` pays and `-` pays back (never more than paid), deployable prices, refused without money, the restock of rounds, items and throwables used (capped by the plan), the menu lines |
| `ammo_conservation_tests.lua` | 2 | 40 random heists (rifle, akimbo SMGs): special rounds never appear out of nowhere |
| `body_tests.lua` | 53 | health per body part: where hits land, black parts and the 70% spread, head down and revive at 1 HP, first aid kit vs medic bag, arm/leg/body effects, deadly falls, Frenzy, turned off, the open screen refreshed on a hit |
| `akimbo_buttons_tests.lua` | 36 | akimbo: left button = left gun, right button = right gun, no aiming, own magazines, single fire, turned off, a black arm cannot fire its gun |
| `typed_ammo_tests.lua` | 131 | AR/SMG sizes and bullets, mixed magazines shot by shot, the weapon slots, colours, the dev spawner, the menu plan, the UI |

1028 checks in total. These are code-level tests, not substitutes for in-game testing on a
clean PAYDAY 2 profile. The current environment cannot launch PAYDAY 2, so the runtime hook
compatibility, the menu rendering and the multiplayer behavior remain unverified.

The log prefixes help when something goes wrong in game: `[PDTI]`, `[PDTI AMMO]`,
`[PDTI DEPLOY]`, `[PDTI LOOT]`, `[PDTI CARRY]`, `[PDTI UI]`, `[PDTI DIAG]`.

## Older releases

### 0.6.0

Loose ammunition, deployables that follow what you carry and a movement penalty for heavy
loadouts. The ammunition was a mirror of ISSR's counter; the magazine supply was ISSR's
queue. Both are gone in 0.7.0.

### 0.3.0

- Temporary-file save writes and one `.bak` recovery copy.
- Invalid primary JSON falls back to the previous backup. The corrupt primary is
  removed/restored from the backup before future saves, so a later save cannot rotate the
  corrupt file over the known-good copy.
- Save failures roll back local inventory mutations.
- Schema v4 preserves unknown item IDs and custom equipment selections from optional mods;
  those entries are restored when their definitions register later.
- `PDTI.RegisterEquipment(kind, id, definition)` for third-party backpacks and rigs.
- `PDTI.GetOccupancyMap(container)` for cell-level UI rendering.
- `PDTI.AutoArrange(container, allow_rotation)` for deterministic first-fit rearrangement.
- `PDTI.RegisterItemUse(item_id, callback)` and `PDTI.UseItem(container, instance_id, context)`.
- UI interaction state and request APIs for selection, movement, rotation, equipment changes
  and rearrangement.
- `PDTI.ValidateState()` and runtime diagnostics.

The item-use API intentionally has no built-in gameplay effects yet. A gameplay integration
must register an effect and return `true` only after the effect succeeds. A failed handler
does not consume the item. As with any external side effect, integrations should also handle
the rare case where the game effect succeeds but the save device fails during item
consumption.

### 0.4.0

The BeardLib inventory screen: bind **Toggle Tactical Inventory** in the BLT keybinds menu.
Click an item to pick it up, click a cell to drop it there (the clicked cell becomes the
item's top-left cell). Rotate with the button or R, cancel with "Cancel hold".

The screen has only been run against a fake MenuUI that checks parameter names against the
BeardLib docs. Cell sizes, positions, the blur background, cursor handling and whether
redrawing from inside a click callback is safe still need an in-game check.
