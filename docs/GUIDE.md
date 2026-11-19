# PAYDAY 2: Tactical Inventory: detailed guide

Per-release technical notes are in `CHANGELOG.md`; the vision and goals are in `README.md`.

An extraction-shooter inventory for PAYDAY 2: grid backpacks, tactical rigs, quick-access
pockets, magazines and loose ammunition that are real inventory items, deployables that
follow what you carry, loot that costs space and weight, and a movement penalty for heavy
loadouts.

**0.7.0 merged the InsurgencySandstormStyleReload mod into this mod.** The magazine supply
is no longer a second list next to the inventory, it *is* the inventory. Remove the old
`InsurgencySandstormStyleReload` folder from `mods/`.

## What changed in 0.53.0

- **Houston insures your weapons.** In the safehouse, talk to Houston. His menu says which of
  your weapons are insured, which are on their way back (and when), and which are not insured.
  - **Insure all ($X)**: every weapon that isn't insured, in one payment. Short of money,
    nothing is insured and the total is shown.
  - **Insure the AMCAR ($3,300)**: one weapon, for the 5 dearest uninsured ones (more are
    counted as "and N more"; Insure all covers them).
  - Same price and rules as the weapon view: 30% of the built price (Duke's room makes it
    cheaper and faster); the free weapons need none. Cancel stays in the weapon view.
- **Try it:** talk to Houston in the safehouse and insure a weapon; its locker item gets the
  insured mark.

## What changed in 0.52.0

- **The medic bag (doctor bag) costs $35,000** (was $12,000), in the bring list and when a
  heist restocks one you used up.

## What changed in 0.51.0

- **The locker is bigger and scrolls.** It is now **12x20** cells (twice the room) and the
  Locker tab shows **8 rows** at a time.
  - Scroll with the **mouse wheel over the locker**, or the **Up** / **Down** buttons above it
    (2 rows a step). A line says which rows you see ("Rows 3-10 of 20").
  - The wheel works **while you drag** a weapon or part, so you can carry it to a row further
    down; the drop preview follows.
  - The wheel anywhere else does what it did before.
- **Try it:** open the Locker tab, scroll down with the wheel, and drag a weapon into row 15.

## What changed in 0.50.0

- **Rust repairs your weapons.** In the safehouse, talk to Rust. His menu lists your worn
  weapons, worst first ("Worn: AMCAR 63%, Chimano 88 40%"), and offers:
  - **Repair all ($X)**: every worn weapon back to 100% in one payment. Short of money,
    nothing is repaired and the total is shown.
  - **Repair the AMCAR, 63% ($1,200)**: one weapon, for the 5 most worn ones (more are counted
    as "and N more"; Repair all covers them).
  - The price is the same as in the weapon view: 20% of the built price from 0%.
  - Nothing worn: "Your weapons are in full condition."
- The weapon view's Repair button stays.
- **Try it:** wear a gun in a heist, then talk to Rust in the safehouse and repair it; the
  hint says what it cost, and the weapon view shows 100%.

## What changed in 0.49.0

- **Weapon skins.** Your weapons can wear the skins and weapon colours you own in the game.
  **Sydney** changes them: in the safehouse, talk to Sydney and pick **Weapon skins**.
  - The screen lists your weapons (those in your hands first). Pick one: you see the skins
    you own that fit it, one row per skin. Click a skin to put it on, **Remove the skin** to
    take it off. 9 rows a page, with Prev / Next.
  - **Any number of your guns can wear the same skin.**
  - With several copies of a skin, your best one is used: a **StatBoost** copy first, then
    the best quality. A StatBoost works as in the game.
  - **Weapon colours** (and skins the game unlocks for you) are listed when the game says
    you have them. A colour uses its first colour and the game's default pattern.
  - **A legendary skin brings its own parts.** The parts you fitted come off (next to the
    gun, else the locker, the backpack, the rig; with no room for all of them nothing
    changes and you are told why). The skin's parts are **free**: they are not in the gun's
    price or sale price. A locked legendary skin **locks the gun**: no part goes on until
    Sydney takes the skin off. Taking it off gives the gun its own parts back.
  - Skins change **at home only** (not in a heist). The weapon view shows what a gun wears.
  - Others see your skin online (the game's slot wears it). A skin you sell on Steam comes off
    your gun at the menu, as the game does.
  - An insured gun that is lost comes back wearing its skin.
- **Try it:** in the safehouse, talk to Sydney, pick **Weapon skins**, pick your primary,
  click a skin. Your gun in hand changes at once. Try a legendary one on a gun with parts:
  check the backpack for the parts that came off.

## What changed in 0.48.0

- **Body damage now lasts between heists.** Each body part keeps the health it had when the
  heist ended. The next heist (and the safehouse) starts that way.
  - **Black parts stay black,** with their penalty, until healed. The head never starts below
    1 HP.
  - **Nothing heals for free** between heists. In a heist: a first aid kit or a medic bag, as
    before.
  - **Ending a heist down or in custody** (won or failed), **or leaving / quitting a heist**:
    every part comes home at 0 (black), the head at 1 HP.
  - Back from custody *during* a heist you still get a fresh body; only the end counts.
- **Dallas heals you:** in the safehouse, talk to Dallas. When you're hurt his menu says what
  is hurt and has **Heal everything ($15,000)**: every part to full, black ones too, at once.
- **The menu's Health tab** (the inventory screen, next to Locker) shows your body as the
  heist's health window does, with the same **Heal everything ($15,000)** button. The tab says
  "Health (hurt)" while a part is hurt.
- **Try it:** take a few hits in a heist and finish it. In the menu, open the Health tab: the
  hurt parts are there. Start another heist: you start hurt. Heal at Dallas or in the tab.

## What changed in 0.47.0

- **Weapon condition.** Your weapons wear as you fire them in a heist.
  - A weapon starts at **100%**. Each round fired takes a little. A rifle, SMG or shotgun goes
    from 100% to 50% in about **2,500 rounds**; pistols and snipers in 3,500; LMGs in 1,500;
    the minigun in 1,000.
  - **Jams.** Above 50% a gun never jams. Below 50% a shot can jam it, more often as it wears:
    about 1 shot in 20 at 25%, 1 in 10 at 0%. It never breaks for good.
  - **A jammed gun doesn't fire:** the trigger only clicks, and no round is used. Press
    **Clear Jam** to rack it: about 1 second. Switching weapons or reloading stops the clear.
    **Bind the key first:** Options > Mod Keybinds > Clear Jam (it has no key until you set
    one).
  - **Repair at home.** Right-click the weapon (the menu or the safehouse) and press **Repair**.
    A gun worn down to 0% costs 20% of its built price; less wear costs less (from 50%: 10%).
  - **Seeing it:** a worn gun has a thin bar along the bottom of its box (PRI, SEC, and its
    first cell in a grid): green, yellow below 50%, red below 25%. Its view says "Condition 40%:
    jams about 1 shot in 50." No bar at 100%.
  - **A worn gun sells for less:** at 0% half its normal sale price.
  - The free AMCAR and Chimano 88 never wear. Nothing wears in the safehouse. Weapon parts
    don't wear. New guns (the market, picked up in a heist) start at 100%.
  - An insured gun that was lost comes back as worn as it was lost.
- **Try it:** take a bought gun into a heist and fire a few magazines; back home, its view
  shows less than 100% and a Repair price. To see a jam quickly you need a gun below 50%
  (about 2,500 rifle rounds).

## What changed in 0.46.0

- **Online, PDTI players only play with PDTI players.**
  - Crime.net, the server browser, quickplay and your friends' lobbies show only lobbies of PDTI
    players, and vanilla players don't see yours. An invite or Steam's "Join game" between PDTI
    and vanilla fails with the game's own "failed to join" dialog.
  - Any PDTI version plays with any other (0.46.0 or later: older versions are in the vanilla
    list). A different version is said in the chat, to you only: "Ann has PDTI 0.45.1 (you:
    0.46.0)".
  - A host checks everyone who joins (the lobby, and drop-ins in a heist). A player whose game
    has not answered 15 s after they could (not while loading) is removed with the game's own
    kick, and the lobby's chat says why: "<name> was removed: this game needs the Tactical
    Inventory mod (PDTI)".
  - A client whose host has not answered in 15 s leaves the lobby (a dialog says why). In a heist
    it only warns: leaving would lose the weapons you brought.
  - Offline play is the same as before.

## What changed in 0.45.1

- **Duke's room, changed:** tier 2 makes weapon insurance cost 20% (not 30%); tier 3 also brings
  a lost weapon back in 5 minutes (not 10). (0.45.0's tier 3 of 10% and 2 minutes is gone.)

## What changed in 0.45.0

- **Weapon insurance.** Right-click a weapon at home (the menu or the safehouse) and press
  **Insure**: it costs 30% of the weapon's built price (the game's normal price of the weapon
  and of every part on it beyond its own). Free weapons (the AMCAR, the Chimano 88) need none.
  - It lasts **until the weapon is lost**: won heists don't use it up.
  - Lost (a failed or abandoned heist, left on the ground or thrown away in a won one), the
    weapon comes back into your **locker 10 real minutes after the heist ended**, with the build
    you insured and without its loaded magazine. The time runs while the game is closed; it
    arrives in the main menu or the safehouse (a heist keeps it until you're home); with a full
    locker it waits for room. A hint says when it is back.
  - On its way, the Locker tab and the market's Weapons tab say when: "Insurance: the CAR-4 is
    back at 14:32".
  - An insured weapon has a small blue mark in the corner of its box (the grid, PRI, SEC); its
    view says it is insured and has **Cancel insurance** (paid back).
  - **Changing an insured weapon at home** (fitting or taking off a part, a build template, what
    a won heist changed) cancels its insurance and pays it back: insure it again for the new
    price. Changes made in a heist count once you're home. Selling it or throwing it away at
    home pays the insurance back too.
- **Duke's room: insurance.** Tier 2: insurance costs 20% and a lost weapon is back in 5
  minutes. Tier 3: 10% and 2 minutes. (His Story Line button stays.) (Changed in 0.45.1.)

## What changed in 0.44.1

- **The market's loot prices are sorted by price:** the dearest loot today at the top, the
  cheapest at the bottom (today's price, with the day's change, not the base value; loot at the
  same price by name). The graph opens on the top row (or the first loot you have in the stash).

## What changed in 0.44.0

- **The game's own weapon mods are yours as parts.** The mods the game gives you (the cards
  after a heist, and any it gave before) move into your **locker** as part items the next time
  you are in the main menu (on the way to the safehouse too), so they are fitted by dragging
  like bought ones. A hint says how many came in.
  - They leave the game's inventory as they go (never counted twice). This is done only on the
    mod's own save (slot 86); on the game's own save they stay where they are.
  - No room in the locker: the rest wait in the game's inventory and come in at a later menu
    (a small part still goes into a small place).
  - Ammunition types (slugs, AP, ...) stay the game's: the ammunition system owns them.
- **Dragging a part marks the weapons that take it green**: every weapon of yours on the
  screen (PRI, SEC, the locker, a packed one) that the game lets take that part, also one that
  has a part of that kind already. Let go on one to fit it, as before.
- **Ammo boxes after going in unarmed:** a gun you pick up with Pick Up Weapons takes boxes
  (tested: unarmed, an enemy's Compact-5 picked up, then a CAR-4, each box gives loose rounds).
  What does keep boxes on the floor:
  - **Bulletstorm or Extra Lead** (the skills that make ammo bags your ammunition): standard
    boxes stay on the floor, with or without a gun. The first box of a heist now says so.
  - A gun at the box limit (two stacks of loose rounds) takes no more, as before.
  - Anything else is a fault: the log now says why a box stayed ("an ammo box stayed on the
    floor: new_mp5: room ..., pickup ...", once a reason).

## What changed in 0.43.0

- **Duke opens the Story Line** (the game's campaign, Story Line in crime.net). Talk to Duke in
  his room: his menu's first button is **Story Line (leaves the safehouse, comes
  back)**, picked already, so the interact or Enter key takes you there. His room's tier and
  Upgrade stay in the same menu.
  - You leave the safehouse for the main menu, and the game's Story Line page opens on its own,
    offline, as the safehouse is. Start the next story heist there as usual (its contract page
    opens, then the heist).
  - Back out of the Story Line to the menu's first page and the safehouse loads again, the way
    Chains' menu inventory does. After a story heist you come back to the safehouse as after
    any offline job.
  - If the page does not open, it is tried once more; then a hint says to open the Story Line
    yourself (crime.net's sidebar), and backing out still brings you home.
  - With a crew (online) Duke's menu has no Story Line button.

## What changed in 0.42.0

- **The weapons market has pages** (Scarface's market, the Weapons tab): **Primary** and
  **Secondary** at the top of the list, each with how many weapons it has, and under them a
  button for each type of weapon on that page. The list shows that type alone.
  - **Primary:** rifles, shotguns, LMGs, snipers, akimbo, special.
  - **Secondary:** pistols, SMGs, shotguns, special.
  - **Special** is everything else: bows, crossbows, grenade launchers, saws, miniguns,
    flamethrowers. A weapon with akimbo among its kinds is **Akimbo**.
  - Only the types a page has get a button. A new page opens on its first type, and the
    weapon picked in the middle is the first of the list until you pick another.
  - The market remembers the page and the type while the game runs.

## What changed in 0.41.0

- **The weapon's view is built around the weapon itself:** the picture of the weapon (the
  game's own icon) is in the middle of the view, and its slots are around it:
  - **On top of the weapon:** the sights, the gadgets (the laser) and the boosts.
  - **Under the weapon:** the grip (the handle), the handguard and the vertical grip, the
    stock, the magazine, and the weapon's own parts (the barrel, the muzzle, the receivers,
    the slide).
  - Everything else about the slots is as before: drag a part onto its slot to fit it, drag
    yours out onto a cell (or Ctrl+click it) to take it off.
- **Gun build templates:** a build you saved, to put on another weapon.
  - **Save:** in a weapon's view, **"Save this build as a template"**. The template is the
    parts you fitted on it, beyond the weapon's own parts.
  - **Use:** in any weapon's view, **Apply** next to a template. The parts the weapon takes
    and you own go on it; the parts that come off it become items again (in your locker, or
    next to the weapon).
  - **The parts stay yours:** a template is a recipe, not a copy of the parts. You need the
    parts as items to apply one, and what the template leaves out is said: a part the weapon
    does not take, or one you do not own.
  - **Delete:** **Del** next to a template. A template is named after the weapon it was made
    from ("AMCAR build", "AMCAR build 2").
  - The templates are in their own file (one per profile): `pdti_templates.json`.
  - A build is changed at home: in a heist the templates are not shown (a change takes time
    there, and a template is a whole build at once).

## What changed in 0.40.1

- **The names on pictures are optional:** Options → General → **"Names on pictures"** (on by
  default). Off: a pictured weapon or part in the grid shows its picture alone. PRI and SEC
  show the weapon's picture at full strength, with no name or weight.
- Unchanged with it off: items without a picture keep their names, and the weapon view, its
  slot boxes and the market keep their text.

## What changed in 0.40.0

- **Pictures of your weapons and parts** on the inventory screen, the game's own (the ones its
  inventory and modding screens show):
  - **In the grid:** a weapon or part shows its picture across all its cells, with its name in
    the top-left corner. A turned weapon's picture turns with it.
  - **PRI and SEC:** the weapon's picture, faint, behind its name and weight.
  - **A weapon's view** (right-click): its picture at the top, under its name. A part's view
    shows the part's picture.
  - **The slot boxes:** each part of yours, or a named one, shows its picture on the right of
    its box. The weapon's own standard parts and empty slots show none.
  - **The market's Weapons tab:** the weapon you pick shows its picture above Buy.
- The picture is the stock gun: parts you fitted don't show on it, as in the game's own
  inventory. A weapon with a skin shows the stock picture too.
- A weapon or part the game has no picture for keeps the old look (its name on its colour).
  Each one is noted once in the game log (`no picture for part ... at ...`).
- Pictures show a moment after the screen opens the first time: the game loads them, then the
  screen is drawn again.
- **Options → General → "Pictures of weapons and parts"** (on by default) turns them off.

## What changed in 0.39.0

- **Weapon parts can be changed during a heist** ("hot modding"): take the suppressor off, put
  the laser from your backpack on.
  - **How:** open the inventory and right-click a weapon in PRI, SEC, the backpack or the rig.
    Its slots take the middle of the screen (the health window steps aside until you close
    the view). Then use the slots as at home: drag a part onto its slot or onto the weapon,
    drag a part out of its slot onto a cell, or Ctrl+click a slot.
  - **It takes time, by the part:**

    | Part | Seconds |
    |---|---|
    | Muzzle, gadget, boost | 2 |
    | Sight, grip, vertical grip | 3 |
    | Stock (and any other part) | 4 |
    | Slide, handguard | 6 |
    | Barrel | 8 |
    | Upper or lower receiver | 10 |

  - The slot shows "Fitting... 40%" or "Taking off... 40%". When the time is up, the part is on
    (or off) and the gun in your hands is made again with it, its magazine and rounds kept.
  - **What stops it:** shooting, aiming, reloading, switching weapons, melee, throwing,
    interacting, the mouse wheel, or going down, cuffed or tased. The change is not made and its
    time is lost. Moving, crouching and sprinting don't stop it. While the inventory screen is
    open the game gets no input, so nothing you do there stops it.
  - **Rules in a heist:**
    - one change at a time;
    - magazines are changed at home;
    - the locker stays at home, so a part or weapon in it can't be used, and nothing comes off
      into it (parts that come off go next to the weapon: the backpack, then the rig);
    - nothing is sold.
  - The menu and the safehouse change parts at once, as before.
- **After the heist:**
  - **Won:** what you changed is kept. The weapon keeps its new build, a part fitted in the
    heist is used up, a part taken off is yours (where it was, else the locker; with no room
    anywhere it waits for the next menu), and a part thrown away is lost.
  - **Failed or left:** what you carried when the heist began is lost, including a part fitted
    in the heist and one thrown away. A part taken off in the heist went with its weapon.
  - **A heist of several days:** the next day starts with what the day before changed.
- Your detection risk is the one the heist began with. A weapon's own stats change at once.

## What changed in 0.38.3

- **Part changes show on the gun in your hands at once** (the safehouse). Fitting or taking off
  a part of the weapon in PRI or SEC used to change only the saved build: the gun you held
  kept its old parts until you took it out of the slot and put it back. Now it is made again
  with its new parts as soon as you let go of the part. Its magazine goes with it.
- A heist never rebuilds a gun for its parts: parts are only changed at home.

## What changed in 0.38.2

- **The weapon view shows the weapon's slots** instead of a list: a box for every slot (sight,
  barrel, muzzle, receivers, handguard, grip, stock, magazine, gadget and the rest), three to a
  row, with the part in it.
  - Your parts are blue, like part cells. The weapon's own parts are grey (named when the game
    names them, else "standard"); a skin's part says "(fixed)". An empty slot (one a part for
    sale fills) is dark and says "empty".
- **Taking a part off** (the Take off buttons are gone):
  - **Drag it out of its slot** and let go on a free cell of the locker, the backpack or the
    rig: it comes off there (R turns it while dragging). Let go anywhere else and it stays on;
    it is never thrown away.
  - **Ctrl+click its slot:** it comes off next to the weapon (the weapon's place, then the
    locker, the backpack, the rig).
  - The weapon's own part of that kind comes back, as before. The weapon's own parts and a
    skin's part don't come off.
- **Fitting a part:** drag it onto its slot. The slot lights up green, or red with why (another
  slot, a fitted part it doesn't go with). Dropping it onto the weapon's cell still works.
- An item let go over the middle window, but not on a cell, now stays where it was. Before,
  it was thrown away as if let go outside the inventory.

## What changed in 0.38.1

- **Right-click a weapon** (in PRI / SEC, the locker, the backpack or the rig) to open its view
  in the middle window. Shift+click still works too.
  - **Every part on it, slot by slot:** sight, barrel, muzzle, receivers, handguard, grip,
    stock, magazine, gadget and the rest. The weapon's own parts are marked "(standard)" (or
    "the weapon's own" when the game has no name for them). Parts that come with the weapon
    (from a skin) are marked so. Your parts have a Take off button.
  - **Its free slots:** the slots with nothing in them that a part for sale fills.
  - **Its weight and concealment**, its loaded magazine, Sell and Close, as before.
- Right-click a part to see what it is and which of your weapons it fits.
- Not in a heist yet: the view lives in the middle window, which a heist doesn't show.

## What changed in 0.38.0

- **Weapon parts are grid items.** Sights, suppressors, stocks, grips, lasers, barrels and the
  rest are bought at Scarface's market and kept in the locker, backpack or rig.
  - **Buying:** in the market's Weapons tab, pick a weapon on the left. Its parts are listed
    under its Buy button with today's price (the game's price, changed every day, each part on
    its own). Click a part, then "Buy". It goes into your locker.
  - **Fitting:** drag a part onto a weapon, in PRI / SEC, the locker, the backpack or the rig.
    The weapon lights green when it fits, red with the reason when not. The part it replaces
    comes off as an item next to the weapon. A part the new one doesn't go with comes off too.
    The weapon's own standard parts just go (they come back when you take yours off).
  - **Inspect:** Shift+click a weapon (or a part). The middle window shows its weight, its
    loaded magazine and its parts. "Take off" puts a part back into the grid and the weapon's
    own part of that kind comes back. "Sell" (click twice) pays half of today's price for the
    weapon and its parts, and pays back its loaded magazine.
  - **Weight:** a part weighs (a suppressor 0.5 kg, a barrel 0.8 kg). Fitted parts change the
    weapon's weight through its concealment.
  - **Death:** parts you carry into a heist that fails are lost, like weapons. The locker keeps
    its own. Fitted parts go with their weapon.
- **Not sold:** DLC parts of DLC you don't own, achievement parts, shotgun ammo parts (the
  ammunition system owns shells), and assault rifle / SMG magazine parts (PDTI's own magazine
  sizes replace those). A pistol's extended magazine is sold, and the magazine its weapon keeps
  takes the new size.
- Parts are changed outside a heist (the menu and the safehouse). Changing them during a heist
  comes next.
- The free AMCAR and Chimano can't be sold (throw them away instead).

## What changed in 0.37.7

- **Magazines belong to weapons now, not to the PRI / SEC slot.**
  - **The magazine loaded in a weapon goes with it.** Move a weapon from PRI to the locker or
    backpack and its magazine leaves the slot's magazine box with it (and weighs with it). Put
    it back and the same magazine, with its rounds and bullets, is in the box again.
  - **In a heist too:** take a weapon out of your hands and back, and it has the rounds it had.
    It no longer comes back with a free full magazine, and its loaded magazine is no longer lost.
  - **Spare magazines and loose rounds stay their weapon's.** Put another weapon into a slot and
    your AMCAR magazines stay AMCAR magazines (before, they turned into the new weapon's, and a
    shotgun turned them into shells). The new weapon's rows in the Bring list count only its own.
  - Loose rounds are labelled by their weapon ("AMCAR AP") instead of "PRI AP".
- **Rules:**
  - A magazine box takes only a magazine of the weapon in that slot, and nothing when the slot
    is empty.
  - A new weapon comes with one full magazine (free, as before). A magazine you take out of the
    box yourself stays out, and the weapon then starts the heist without one.
  - A weapon you throw away takes its magazine with it.
- **Your current save:** the AMCAR and Chimano magazines left in the empty PRI and SEC boxes go
  into the AMCAR and the Chimano in your locker.

## What changed in 0.37.6

- **You can have no weapon in your hands.** Take both weapons out of PRI and SEC (in a heist or
  in the safehouse) and you hold nothing: you cannot fire, aim, reload or switch, and your
  melee and throwables still work. The rule that kept your last weapon in your hands is gone.
- **How it works:** PAYDAY 2 cannot run without a weapon, so the last one stays as a hidden,
  empty stand-in (a pistol), the way the game keeps your guns in casing mode.
  - Ammo boxes and bags give it nothing (they stay for you), and Pick Up Weapons never drops it
    as a pickup.
  - Put a weapon into a slot (or pick one up) and it is in your hands again; the stand-in goes.
  - Other players may still see a pistol on you.
- **Free weapons:** the free AMCAR and Chimano 88 are given only on a new save and after you
  lose weapons (a failed or left heist, or weapons left on the ground). Throwing your own away
  no longer brings one back, so an empty slot stays empty.
- Empty slots read "no weapon" in the menu too: you go into the heist with nothing there (before,
  the game's own weapon was shown).

## What changed in 0.37.5

- **Fixed: the game crashed when you picked up a weapon** (Pick Up Weapons) while you had a weapon
  of that kind in your hands. The crash log pointed at the armory: it read the weapon being replaced
  after the game had deleted it.
- **Fixed: "No room for the magazine" when taking the magazine out of a weapon you had just put
  into your hands** (picked up, or dragged in from the backpack), even with room in the rig.
  - The old weapon's magazine stayed in the weapon's magazine slot, so the new weapon's magazine
    never got there and there was nothing to take out.
  - Now a weapon's magazine leaves the slot with the weapon.
  - If the slot holds another weapon's magazine (you put it there), R now says so: "The
    weapon's magazine slot holds another magazine: move it out first".

## What changed in 0.37.4

- **With the Pick Up Weapons mod, a weapon you pick up in a heist becomes that slot's weapon.**
  - It shows in PRI or SEC and counts in your load. You can pack it in your backpack or rig like
    your own weapons, even if the game has not unlocked it for you.
  - Your weapon from that slot lies on the ground, where that mod drops it. Pick it up again and
    it is your same weapon.
  - An enemy's weapon you swap for another is gone (that mod drops only your own weapons).
- **When the heist ends:**
  - **Won:** every weapon you picked up and still carry is yours. It goes into the slot it was in
    (if that slot is empty and the game lets you use the weapon), otherwise into the locker. A
    weapon of yours left on the ground is lost.
  - **Failed or left:** the usual death rule. Everything you brought is lost, including your
    weapons on the ground, and nothing picked up is kept.
- 0.37.3's changes (below) are included: if you skipped 0.37.3, install this one.

## What changed in 0.37.3

- **Your weapon slots are your hands, in the heist too.**
  - A weapon in PRI or SEC is a weapon you hold. An empty slot is no weapon: you cannot switch to
    it, and it weighs nothing.
  - In a heist you can drag a weapon from PRI or SEC into the backpack or rig, and back. Your
    hands change at once: a weapon taken out is gone from them, and one put in is ready to switch
    to.
  - The locker stays at home during a heist.
- **You are never unarmed:** in a heist the last weapon in your hands cannot be taken out. If you
  go into a heist with both slots empty, you get the free Chimano 88 in SEC for that heist.
- **The briefing (loading) screen** is still planning, as in the menu: what you change there is
  what you spawn with.
- **A failed or left heist** now counts every weapon you had outside the locker at its end,
  including weapons packed on the briefing screen (before, only what you had when the level
  loaded).
- Empty slots read "PRI empty / no weapon" (or "free Chimano 88" for SEC when both are empty).
- Known for now: a weapon put back into your hands comes with a full magazine in it (the
  ammunition of swapped weapons comes later).

## What changed in 0.37.2

- **The free weapons are real weapons now.** Whenever you own no primary (or no secondary) at
  all, in the slots, the locker, the backpack or the rig, the game's free AMCAR (or Chimano 88)
  is put into PRI (or SEC) as a weapon item. You can drag it into the backpack, the rig or the
  locker like any weapon. This happens on a new save and after a death that took your last
  weapon of a kind.
- **An empty slot says so:** "PRI empty (AMCAR)". The game still needs a weapon there and gives
  you its own AMCAR or Chimano 88, which is not an item. Put a weapon into the slot to use your
  own.
- **The safehouse raid is a heist.** Leaving or losing a raid loses the weapons you brought into
  it, like any heist. (This was already so in 0.37.0; now it is written here.)

## What changed in 0.37.1

- **Your weapons are slots of the inventory.** The PRI and SEC boxes at the top of the left
  window are the weapon slots now (they were only labels):
  - Drag a weapon from the locker, the backpack or the rig onto PRI or SEC to use it, and drag it
    off into the locker, backpack or rig. Click and click works too.
  - A slot takes one weapon of its kind, whatever its size. Off the slot, the weapon takes its own
    size again (a rifle 4x2, a pistol 2x1).
  - The slot under a dragged weapon lights green, or red with the reason (a pistol over PRI).
  - Ctrl+click on a weapon anywhere sends it to its slot; Ctrl+click on a slot sends the weapon
    back to the locker (or the backpack).
  - An empty slot shows the game's free weapon ("free").
- The Locker tab shows only the locker now.
- Fixed: the market's price graph could stay in the left window over the inventory after you
  went from the market to the inventory.

## What changed in 0.37.0

The armory reworked after the first test in the game: weapons are grid items, and the mod has
its own save.

- **The mod's own save.** With the mod on, the game keeps your progress in save slot 86 instead
  of 98 (the way restoration-mod uses 77). Playing with the mod no longer touches your vanilla
  progress, and the mod's files (inventory, stash, armory) have their own names on it
  (`pdti_save_..._profileN.json`). The old files stay as they were.
- **A new save starts at level 0.** The first time the menu opens on it, a dialog offers instead:
  **level 100, 120 Continental coins, $100,000 spending cash and $100,000 offshore.** The level
  comes the game's way, one level at a time, with its skill points and unlocks.
- **Every weapon is a grid item.** The inventory's **Locker** tab (in the menu and the
  safehouse) shows a 12x10 locker (12x20 since 0.51.0, scrolling) and your two hands, Primary and Secondary (in 0.37.1 the hands
  became the PRI and SEC slots of the left window).
  - Drag a weapon into a hand to take it into the heist. Ctrl+click in the locker sends a weapon
    to its hand; Ctrl+click on a hand sends it back.
  - A weapon in the backpack or rig is a spare you carry (its own size and weight).
  - A bought weapon goes into the locker.
  - An empty hand gets the game's default AMCAR or Chimano 88, free and never lost.
- **The game's weapon slots follow your hands.** Slot 1 of each kind is the weapon in that hand,
  so the game spawns it, shows it in the menu and counts its concealment itself. **This fixes
  the 0.36.0 bug where the bought weapon did not spawn.** Buying, modding and selling weapons in
  the game's own weapon screen is blocked, with a message.
- **Death is the same:** a failed or left heist loses every weapon you brought (in your hands and
  packed). The locker keeps the rest. The loss is taken out at the next menu, since a heist never
  writes the menu inventory.
- The 0.36.0 Weapons tab is gone. In a heist the locker and the hands do not change.

## What changed in 0.36.0

The armory, part 1 of 4: weapons are now something you own and can lose.

- **Your weapons are the mod's, in their own file** (`pdti_armory.json`, per profile like the
  stash). The game's weapon save is never changed. The first time you open the menu you get the
  two weapons you have equipped now, with their mods, once.
- **Buying:** Scarface's market has two tabs, **Loot** and **Weapons**. The Weapons tab lists
  every weapon you have unlocked, at the game's own price changed per day (up to 30% cheaper or
  dearer), with 0 to 3 for sale each day. Pick one on the left, **Buy** in the middle. It goes to
  your stash. The market is closed during a heist.
- **Choosing:** the inventory's new **Weapons** tab. **Use** puts a weapon in your hands (the one
  there goes back to the stash), **Unuse** takes it out. **Pack** puts a spare weapon in your
  backpack or rig (it takes room and weight: a pistol 2x1, an SMG 3x2, a rifle or shotgun 4x2, a
  sniper or LMG 5x2), **Stash** brings it back. Weapons do not change during a heist.
- **No weapon of your own in a hand: a free AMCAR / Chimano 88**, never lost.
- **A failed heist is death:** the weapons you brought (in your hands and packed) are lost. Your
  stash keeps the rest. A heist you leave or quit counts as failed (seen the next time the menu
  opens). A won heist keeps everything, also if you end it in custody. The safehouse is not a
  heist.
- **No restart:** the restart option and vote are gone, and the fail screen leaves the job
  instead of retrying the day.
- With restoration-mod the game's own weapons and restart, as before.
- Coming next: build templates and the weapon screen as a workbench (0.37.0), insurance and
  swapping weapons in a heist (0.38.0), no vanilla lobbies and Pick Up Weapons (0.39.0).

## What changed in 0.35.3

- **Back to rolling on pickup:** a bag rolls its quality the first time you pick it up, as before
  0.35.0. Nothing is rolled when the heist starts, and the mod no longer looks around the level.
  A bag you threw keeps its roll and its outline, as before.
- **Duke's room gives nothing** (not made, like before 0.35.0): no outline of seen bags, no aim
  hint, no reroll.
- Kept from 0.35.1-0.35.2: Stackable carries any bag of its loot, and no hint when you pick up a
  bag you threw.

## What changed in 0.35.2

- **Stackable means what it should:** a Stackable bag carries up to 3 more bags **of the same loot,
  any quality** (Standard diamonds ride on a Stackable diamond bag) in its one place. Each bag
  keeps its own roll: the tooltip says "with 2 Standard, 1 High quality", a Light bag riding on it
  still costs half the slowdown, each bag is captured with its own quality, and taking a bag off
  (or dropping it) takes the last one put on, with its roll. A Stackable bag put away gathers the
  single bags of its loot already in the inventory. Picking a bag up with no free place is allowed
  when a Stackable bag of its loot has room.
- **Fewer hints:** no hint when you pick up a bag you held before (you threw it), no "stacked"
  hint, and Duke's aim hint only for High and Exceptional bags and once per bag.
- **Duke's outline, second try:** the bag is also marked with the game's own "highlight" outline
  in its colour, and the bag's outline materials are fetched when the game had none yet. The log
  says once per bag how it was outlined (`outlined (...)`) -- send it if bags still show no
  colour.

## What changed in 0.35.1

- **Duke's outline works:** a bag counted as "behind a wall" because the sight line ran to its
  foot and hit the floor under it. It now looks at the middle of the bag and ignores the floor
  just under it and the bag itself. The log says `seen: <loot>, <quality>` for each High or
  Exceptional bag you see with Duke's room.
- **Stackable bags stack when your inventory is full:** picking one up used to be refused for
  lack of a free place, even with a stack of the same bags that had room. Now it goes onto that
  stack (with or without a bag already in your hands). Bags are "the same" when they share kind,
  quality, modifiers and dye pack state.
- Loot not bagged yet (gold, money, diamonds lying loose) has no quality until you bag it: the game
  only decides what bag it becomes then.

## What changed in 0.35.0

- **Loot quality is rolled when the heist starts**: every loot bag lying in the level rolls at
  once, and a bag that appears later (the mission spawns it) as soon as it is there. A bag made in
  your hands (bagging gold, money...) rolls when it is made, as before. Picking a bag up gives it
  the roll it already had.
- **You do not see the quality until you know it.** Bags lying in the level are not outlined in
  their colour any more -- except a bag you threw yourself.
- **Duke's room works** (pick nothing, it is on once upgraded):
  - Tier 2: a bag you have **seen** (in front of you, within 20 m, not behind a wall) is outlined
    in its quality's colour from then on: High blue, Exceptional gold (a Standard one keeps the
    game's outline).
  - Tier 3: also, aiming at a bag you have seen shows its quality and modifiers; and the first
    Standard bag you pick up each heist rolls again (a bag you held before never does).
- Every room bonus is made now.

## What changed in 0.34.2

- **The price list stays where you scroll it.** The screen is redrawn whenever your health or
  ammunition changes, and that made the list anew at the top. Now the list is kept and only made
  again when its rows change (a sale, a new day).
- **Only loot you can capture is listed**: bags with a value of their own that the escape
  secures (the same rule the stash uses). Engines, bike parts, batteries, ladders and other
  mission items are gone from the list.

## What changed in 0.34.1

- **Every loot type has a price** in the market's list. The game keeps its bag values encoded;
  0.34.0 read them wrongly, so most loot had no value and was left out. Loot without a value of
  its own (a goat, an engine...) has the game's default one ($100). People, vehicles and small
  loot are not in the list.
- **The mouse no longer turns the camera while the market is open.** Scarface's menu turned the
  controls back on when it closed; now they are turned off again every frame while the screen is
  open (and on again when it closes).

## What changed in 0.34.0

- **Prices in the market** (Scarface's Market screen, on the left):
  - A list of **every loot type** a bag can hold (not small loot or vehicles), the dearest
    today first (0.44.1; the same price: by name). It scrolls (mouse wheel or the scroll bar). Each row: the name (how many you have in the stash),
    **now** (today's price), **real** (the bag's base value in the game) and today's change.
  - Prices are for a Standard bag; your own bags are worth their value (difficulty and quality) x
    the same change.
  - **Click a row** to see its **price over the last 7 days** with today: a bar per day (today in
    gold) with the price above it and the day below.
- Past days show that day's drift and what your sales of that type had taken off by then. Sales
  made before 0.34.0 count for today's price but not for the past days of the graph.

## What changed in 0.33.1

- **The market is Scarface's now.** In the safehouse, talk to Scarface: his room's menu has a
  **Market** button. It opens a screen with the market alone (offers, your contracts, Deliver,
  Close or Esc). The inventory screen no longer has a Market tab; its Stash tab still sells bags at
  the market's price of the day.
- The market can only be reached in the safehouse (where Scarface is).

## What changed in 0.33.0

- **The market** (safehouse phase 4 of 5): a new **Market** tab in the inventory screen's middle
  window (in the menu and the safehouse).
  - **Prices change.** A stashed bag sells for its value x the day's price of its loot type
    (+-20%, the same all day, new each real calendar day) x how much of that type you sold lately:
    every bag of a type you sell takes 8% off the next one, and 4% comes back each day (never
    below 40%). The Stash tab shows today's change next to each bag ("+12% today").
  - **Sell now** after a heist pays its share (50%, more with Scarface's room) of that market
    price, and counts as a sale.
- **Contracts**: 3 offers a day (the same all day). **Accept** one (up to 3 at a time), then
  **Deliver** its bags from your stash before it runs out:

  | Level | Bags | Least quality | Days | Pays | Coins |
  |---|---|---|---|---|---|
  | Easy | 1-2 | Standard | 1 | the bags' value x1.3 | 1-2 |
  | Medium | 2-3 | Standard or High | 2 | x1.6 | 2-4 |
  | Hard | 2-4 | High | 3 | x2.0 | 4-6, and a **High roll** |

  The pay is the delivered bags' own value (no drift or sale discount); the cheapest bags that fit
  are given. Coins are Continental coins for the safehouse rooms. A **High roll** makes the next
  bag you pick up at least High (a bag that rolls High or better anyway keeps it for later).
  A contract not delivered by its last day is gone (nothing is lost but the offer).
- **Ethan & Hila's room works:** tier 2 -- one more offer a day; tier 3 -- also, one loot type a
  day sells for +25% (named in the Market tab).
- Still not made: Duke.

## What changed in 0.32.1

- **Jacket's room works** (no choice, it is on once the room is upgraded): tier 2 -- a melee attack
  charges 50% faster; tier 3 -- also, a melee kill heals your most hurt body part by 15% of its max
  (not a black part; only a doctor bag heals those).
- Still not made: Duke, Ethan & Hila.

## What changed in 0.32.0

- **Six more room bonuses work** (pick them in the inventory, **Room bonuses** tab):

  | Piece | Room | Tier 2 | Tier 3 |
  |---|---|---|---|
  | Medical Rig | Dallas | placing a doctor bag yourself gives the self-revive back | also two self-revives per heist (a doctor bag each) |
  | Medical Rig | Sangres | the self-revive uses a first aid kit (it heals like a kit, black parts stay black) | also a first aid kit goes down in half the time |
  | Assault Rig | Rust | an ammo bag placed from the rig has one more use | also: the new key **Refill From Rig Ammo Bag** takes from a bag in the rig without placing it |
  | General Rig | Houston | half of what is in the rig is not counted for concealment | none of it |
  | Medium Backpack | Clover | a 2x2 loot slot next to the backpack (loot bags only, filled first) | 2x4 (two bags) |
  | - | Joy | computer, laptop and hacking-device timers run 25% faster (not drills or saws) | also: once per heist a keycard is not used up |

- A rig or backpack bonus works only while that piece is worn; an armour bonus only with that armour
  class.
- Set the new key in Options > Mod Keybinds. A bag used that way keeps its remaining uses (they show
  on the item), and an empty one is gone.
- Still not made: Duke, Jacket, Ethan & Hila.
- Online: Rust's extra use and Joy's faster hacks are counted by your game; other players' games may
  show the bag's or the timer's own numbers.

## What changed in 0.31.1

- **The safehouse laptop opens the Contract Broker.** The laptop that used to just leave the
  safehouse for crime.net now takes you to offline crime.net with the **Contract Broker** already
  open. Pick a heist there and it starts as usual (you come back to the safehouse after it). Back
  out of the broker and out of crime.net to the menu's first page, and the safehouse loads again.
  With a crew (online) the laptop is the game's own exit.
- If crime.net does not come up, it is opened for you once; if that fails too you are told to open
  it yourself, and coming back to the menu's first page still takes you home.
- Every kind of object you use in the safehouse is now written to the log once by name
  (`used in the safehouse: ...`), to find the safehouse's objects for later bonuses.

## What changed in 0.31.0

- **Safehouse room bonuses.** Upgrading a heister's room now does something in heists.
  - **Rigs, backpacks and armour:** each one has two rooms to choose from. A room's tier 2
    unlocks its bonus and tier 3 makes it stronger. Pick one per piece in the inventory before the
    heist: the **Room bonuses** tab next to **Rig and backpack**. "No bonus" is always there; a dim
    button is a room below tier 2 (or a bonus not made yet), and clicking it says why.
  - **Other rooms** give their bonus by themselves from tier 2: Bonnie (better quality rolls),
    Scarface (sell-now pays more), the vault (a bigger stash).
  - Talking to a heister in the safehouse shows their room's bonus and which tier you have.
- **Working now:**

  | Piece | Room | Tier 2 | Tier 3 |
  |---|---|---|---|
  | Assault Rig | Chains | ammunition part 7x4 | 8x4 |
  | General Rig | Old Hoxton | 4x6 | 5x6 |
  | Small Backpack | Sokol | speed bonus 35% | 45% |
  | Small Backpack | Bodhi | 5x3, up to 20 kg | 6x3, up to 24 kg |
  | Medium Backpack | Dragan | 5x5 | 5x5, up to 35 kg |
  | Large Backpack | Wolf | weight and loot slow you 40% less | 50% less |
  | Large Backpack | Living room | enemies focus you +25% (not +50%) | no extra focus |
  | Light armour | Sydney | regenerates 25% sooner after a hit | 50% sooner |
  | Light armour | Jimmy | half damage for 2 s when it breaks | for 4 s |
  | Heavy armour | John Wick | a plate goes in in 1.5 s | 1 s |
  | Heavy armour | Jiro | firing does not stop a plate | and full speed while inserting |
  | - | Bonnie | High quality 25% (was 17%) | and Exceptional 6% (was 3%) |
  | - | Scarface | sell-now 65% | 75% |
  | - | Vault | stash +4 bags | +8 bags |

- **Shown but not made yet** (they cannot be picked): Dallas and Sangres (medical rig), Rust
  (assault rig ammo bags), Houston (general rig concealment), Clover (medium backpack loot slots),
  Duke, Joy, Jacket, Ethan & Hila.
- Room tiers are kept in the inventory save, so a bigger rig is there even before the safehouse
  data is loaded.

## What changed in 0.30.8

- **The trip to the menu inventory no longer bounces straight back.** The menu now settles for
  half a second before the Inventory page is opened, and the safehouse loads only after you were
  on another page and came back to the menu's first page. If the page does not open (tried twice),
  you stay in the menu: open the Inventory yourself, and coming back to the first page still takes
  you to the safehouse.

## What changed in 0.30.7

- **Chains' room takes you to the menu inventory.** Inside Chains' room, press interact while
  not aiming at anything usable (or choose "Menu inventory" in his room's menu): you leave the
  safehouse for the main menu's inventory page (build, skills, perks, weapon mods, masks, armour).
  When you back out of it to the menu's first page, the safehouse loads again (its briefing is
  passed). A loading screen each way. This works with "Start in the safehouse" off too.
- **Wolf's room** has no action any more (that was Chains' room, mixed up).
- **The weapon racks** open the game's weapon menu again, as in the game (0.30.2 is undone).
  The mod's own inventory screen stays on its key.

## What changed in 0.30.6

- **Wolf's room opens the inventory.** Inside Wolf's workshop (downstairs), press the interact
  key while not aiming at anything usable: the inventory screen opens. Walking in shows a hint.
  The room is the area around where Wolf stands (6 m across, one floor: Chains' room right above
  it does not count). Aiming at something usable (Wolf himself, a door, ...) works as before.

## What changed in 0.30.5

- **The daily side job and the room's menu:** when talking to a heister takes your daily side
  job, a hint now says so and that the room's menu opens on the next talk (before, nothing was
  shown, which looked like the menu did not work).
- **Which heisters are in the safehouse** goes to the log once on arrival (with their room and
  whether they can be talked to), to find out why a room's menu cannot be reached.

## What changed in 0.30.4

- **Rooms are upgraded in the safehouse.** Talk to a room's heister (Wolf in his workshop,
  Dallas in his room, ...) and, after their answer, the room's menu opens: its tier, your
  Continental coins, what the next tier brings and its price. **Upgrade** buys it the way the
  safehouse page of the menu does (the progress is saved); the room changes the next time you
  enter the safehouse. Without enough coins there is no Upgrade button and the menu says why.
- **Wolf's room opens the inventory:** his menu also has **Open inventory**.
- The heister who has your daily side job takes it as before (no menu that time). Rooms without a
  heister (the vault, the living room) have no menu yet.

## What changed in 0.30.3

- **A raid on the safehouse comes first.** When the game says your safehouse is under attack,
  the trip to the safehouse (at game start or after an offline job) opens the game's own raid
  contract instead: choose the difficulty and One Down, then **Defend** starts the raid offline
  (with its normal briefing), **Ignore** goes on to the safehouse, and **Back** leaves you in
  the main menu.

## What changed in 0.30.2

- **The armory opens the inventory.** In the safehouse, using the weapon racks (primary or
  secondary) opens the inventory screen (the menu's whole screen) instead of the game's weapon
  menu. If the screen cannot open (BeardLib missing or still loading), the game's weapon menu
  opens as before. The safehouse raid is unchanged.

## What changed in 0.30.1

- **Straight into the safehouse.** With "Start in the safehouse" on, the main menu is no
  longer shown on the way: the trip starts in the same moment the menu opens, under a black
  screen, and the loading screen follows. A dialog on the menu (a question from the game, for
  example) is shown and waited for; if it stays open for 30 seconds you stay in the menu.
- **No briefing for the safehouse.** On a trip the mod starts (at game start or after an
  offline job), the safehouse's briefing screen is passed: ready is pressed for you and Bain's
  intro on the black screen is skipped as soon as the game allows it. When you go to the
  safehouse yourself (the menu's safehouse button), the briefing is as usual.

## What changed in 0.30.0

- **The safehouse is your base** (safehouse phase 3 of 5). In the safehouse the mod behaves as
  in the menu:
  - The **inventory key** opens the whole screen there: what you bring, the rig and the
    backpack, buying, the **Captured** loot and the **Stash**. What you change is saved.
  - Your weapons are the game's own there (the ammunition system is off), so the shooting
    range uses up nothing of what you bring. No deployable or armour plate of the inventory
    can be placed or used there, and nothing is restocked or billed.
  - A hint tells you so when you arrive, and how many captured bags still wait for a choice.
  - The safehouse raid is a heist as before.
- **Start in the safehouse** (a new option, on): the game goes to your safehouse when it
  starts, and again after every job you finish offline (won or lost). Since 0.30.1 it goes
  at once, without showing the main menu or the safehouse's briefing; a dialog on the screen
  is shown and waited for. Leaving the safehouse takes you to Crime.net as usual.
  Not after a job with a crew (you go back to the lobby with them), not after a job you left
  before its end, and not when you were invited to a game.
- **Stash and market spots are not there yet.** For now every time you open the inventory
  screen in the safehouse the log gets where you stand and what can be used nearby
  (`[PDTI HOME] probe: ...`); the spots are chosen from that.
- With restoration-mod none of this applies: the safehouse stays a heist.

## What changed in 0.29.2

- Fixed: **trip mines did not work as shaped charges on safes** (and doors) when they were in
  your inventory. The safe asks the game whether you have a trip mine left, and the game only
  counted the ones of its own loadout. A trip mine in your rig or pockets now counts, and
  setting the charge takes it out of the inventory (the game's own trip mines are used first).
  A trip mine in the backpack is not to hand, as for placing. You still need the shaped charge
  skill, as in the game.

## What changed in 0.29.1

- **Captured loot is chosen on the heist's end screen.** After a won job a "Captured loot"
  window opens over the end screen before the payout is counted up. Choose **Stash** or
  **Sell now** for every bag (or **Stash all** / **Sell all now**; the keys **S** and **X** do the
  same). Until every bag is chosen the payout waits and you cannot continue. What you sell
  then shows as the bags' line of the payout.
- If the window cannot be shown (no BeardLib, or it is not made within about 10 seconds),
  the end screen does not wait: the bags stay in the menu's Captured tab.
- Fixed: a FATAL ERROR line in the log when a bag was thrown (the bag had no carry data yet
  when the game set its outline). Nothing was broken in the game, but the error was logged.
- The log now says what the game paid for bags at the end (`the game's payout for bags: 0`).

## What changed in 0.29.0

- **Loot goes to your safehouse stash** (safehouse phase 2 of 5). When you win a job, every
  bag the crew secured and every bag still in your inventory is **captured**. In custody you
  keep the secured bags but lose the ones in your inventory; a lost job captures nothing.
- **The game no longer pays money for bags.** The contract payout, small loot, vehicles and XP
  stay as they were. The end screen shows 0 for bags.
- In the menu, the inventory screen's middle window has three tabs:
  - **Captured**: the bags of your last jobs. For each one choose **Stash** (keep it) or **Sell
    now** for 50% of its value; or **Stash all** / **Sell all now**. Opens first while bags
    wait. A bag you do not choose for keeps waiting.
  - **Stash**: the bags you kept, with today's market price and a **Sell** button (0.33.0: see
    "What changed in 0.33.0" for the market and the **Market** tab).
  - **Bring list**: what it was before.
- A bag's value is what the game would have paid for it on that job (difficulty and skills
  included), x2 for High quality and x4 for Exceptional. Money from a sale is split into
  spending cash and offshore like a heist payout.
- The stash holds 12 bags (48 places of an 8x6 grid; a Compact bag takes half a bag's place,
  4 Stackable bags of the same kind share one). It is saved in its own file,
  `pdti_stash.json` (`pdti_stash_profileN.json` for other profiles).
- Jobs of several days: bags in your inventory are captured at the end of each day; the secured
  bags on the last day (a roll you had on day 1 is kept until then).
- Off with restoration-mod (the game pays for bags as before).

## What changed in 0.28.2

- A thrown **High quality** bag has a **blue outline**, an **Exceptional** one a **gold
  outline**, visible all the time (the game outlines a bag only when you are near it). While
  you look at it, it shows the game's usual "selected" outline. Standard bags look as before.

## What changed in 0.28.1

- A **High quality** or **Exceptional** bag now says so when it comes into your hands: a hint
  with its kind, quality and modifiers (5 s). Standard bags show nothing. Before, the quality
  only showed in the inventory screen.

## What changed in 0.28.0

- **Loot quality.** The first time you pick up a loot bag it rolls a quality: Standard (80%),
  **High quality** (17%, worth x2, one modifier) or **Exceptional** (3%, worth x4, two
  modifiers). The bag keeps it: thrown and picked up again it is the same bag. The cell shows
  `Bag HQ` (blue) or `Bag EX` (gold); picking the bag up in the inventory screen shows its kind,
  quality and modifiers. The value counts from the next release, when loot goes to the
  safehouse stash; the modifiers work now.
- Modifiers (they work while the bag is in your hands or in your inventory):
  - **Runner**: you can run with it (only bags you cannot run with roll it).
  - **Nimble**: no jump penalty (only bags with one).
  - **Light**: half the slowdown the bag costs.
  - **Compact**: 2x1 cells instead of 2x2.
  - **Discreet**: guards do not notice it once thrown (when you host or play offline).
  - **Balanced**: thrown 50% further.
  - **Quick hands**: no wait before you can pick up a bag after throwing it.
  - **Padded**: 15% less damage taken while you carry it.
  - **Stackable**: up to 3 more bags of the same loot (any quality) ride with it in its place, each with its own roll (0.35.2).
- The quality is yours: a friend who picks the bag up rolls their own. Off with
  restoration-mod.

## What changed in 0.27.4

- Nothing to see in the game: a clean-up and speed release. Gameplay, numbers, saves and
  settings are unchanged.
- The mod does less work every frame: in the offline benchmark the per-frame cost fell from
  about 60 to 40 µs and the garbage it leaves for Lua to collect from about 16 KB to 6 KB
  (one rifle, test harness; the real game differs, the proportion should hold).
- Unused code was removed and repeated helpers (logging, hints, clocks, hook wrapping) now live
  in one place.

## What changed in 0.27.3

- The **Laser Chronometer** (Espionage Weapon Pack) is a throwable: 0.27.2 looked for it among
  the weapons. It now weighs nothing as a throwable (it weighed 0.4 kg for each of its 30
  pieces, 12 kg).

## What changed in 0.27.2

- An attempt to make the Laser Chronometer weigh nothing (as a weapon; it is a throwable, see
  0.27.3).

## What changed in 0.27.1

- **Sneaky Bastard**'s speed dodge has no cap any more: 10% at full sprint (ace: at running
  speed), and more the faster you go (the ace gives about 16% at full sprint). Speed bonuses
  raise it; a heavy load lowers it.

## What changed in 0.27.0

- **Yakuza perk deck** now scales with your **black limbs** instead of missing health: each
  black arm or leg gives a quarter of the deck's bonus (faster armour recovery, faster
  movement), all four give it in full. Card 9 gives the full bonus at 2 black limbs. Needs
  **Health per body part**; with it off the vanilla deck stays. See
  [Perk deck: Yakuza](#perk-deck-yakuza).
- **Extra Heist Info** (if you use it) shows this mod's buffs in its buff bar: Stacked
  Barrier and its cooldown, Doctor's orders, Painkillers, Overheal, Momentum and Ignite. Its own
  Yakuza and Berserker buffs show the reworked values. See
  [Extra Heist Info](#extra-heist-info).

## What changed in 0.26.1

- The skill tree showed the vanilla texts of **Optical Illusions** and **High Value Target**:
  the game names those texts differently from the other skills (`menu_optic_illusions_desc`,
  `menu_spotter_teamwork_beta_desc`). They now show the reworked effects. The effects
  themselves were already the reworked ones.

## What changed in 0.26.0

The last part of the skill rework: Ghost **Shinobi** and **Artful Dodger**, Fugitive
**Berserker** and **Frenzy**. Vanilla only; each falls back to the game's skill when the PDTI
system it needs is off. See [Skills](#skills).

- **Cleaner** ace: the body bag case takes 2 cells instead of 4, and you can run with a bagged
  body (at 70% of the run speed).
- **ECM Specialist** basic: ECM jammers stack 2 to a cell.
- **Inner Pockets** ace: +2 pocket cells (a third row), with any armour.
- **Sneaky Bastard**: dodge comes from your speed, not your concealment: none standing still,
  10% at full sprint (ace: at running speed). A heavy load keeps you from the maximum.
- **Berserker**: +10% melee damage for each black arm, leg or body (up to +50%); ace: bullets
  too.
- **Frenzy**: your arms and legs start the heist black and hold at most 1 HP. A doctor bag
  fills them. Ace: the body too, and everything they lost goes to your head.
- Items that no longer fit after you change skills (the third pocket row, a body bag case,
  a stack of 2 ECMs) are moved where they fit when you open the inventory or start a heist.

## What changed in 0.25.0

The skill rework goes on: the Ghost **Silent Killer** branch (the hollow point and HE side) and
the Technician **Surefire** and **Body Expertise** (the armour piercing side). Vanilla only;
with the ammo system off these skills are the game's again. See [Skills](#skills).

- **Second Wind**: every sure crit (HP on a limb or a cloaker, HE on a dozer or a turret)
  gives +10% speed for 3 s. Ace: a melee kill loads loose special rounds into your gun.
- **Optical Illusions**: hollow points always crit cloakers. Ace: a medic can't save an
  enemy you kill with a crit.
- **The Professional**: HE stuns last 50% longer. Ace: stunned enemies take +20% damage.
- **Low Blow**: HP hits on arms and legs heal your own arm or leg a little. Ace: killing a
  medic from behind makes the enemies around him sick for 4 s.
- **High Value Target**: HE blasts 30% larger. Ace: after an HE crit on a dozer or a turret,
  your HE hits set enemies on fire for 2 s.
- **Unseen Strike**: a crit kill on natural prey drops a round of that kind. Ace: your hits
  with special rounds store rounds for your next ammo box (up to 20; damage clears them).
- **Surefire**: AP headshots build a **Stacked Barrier** (10 each, up to 50) that soaks
  damage before your armour; it fades 3 s after your last such hit, then 10 s of cooldown.
  Ace: 60, 4 s, 9 s. **Body Expertise**: AP body shots with automatic weapons add 3 / 9.
- Hollow points no longer switch off the weapon's armour-piercing flag (the vanilla AP
  skill they were excluded from is gone with the bullets on).

## What changed in 0.24.0

The skill rework goes on: the Enforcer **Ammo Specialist** branch (vanilla only; see
[Skills](#skills)). With the ammo system off these skills are the game's again.

- **Scavenger**: magazines on the floor are picked up from 50% farther and ammo bags are
  taken from 50% faster (boxes keep the game's +50% range). Ace: reloads +15%.
- **Bulletstorm**: taking from an ammo bag reloads your gun at once. Ace: a reload within
  3 m of one of your ammo bags puts the magazine you take out back full.
- **Spoils** (the Portable Saw slot): every 10th special you kill drops an item instead of
  ammo (Medic: first aid kit, Shield: armour plate, Taser: drum of hollow points, Marshal
  sniper: magazine of AP, Cloaker: throwable, Bulldozer: an ammo bag with 1 use). Ace: a
  melee kill on a special always drops it.
- **Extra Lead**: +2 uses per ammo bag. Ace: your bags keep one use for when you have no
  loaded magazine left.
- **Speed Loader** (the Saw Massacre slot): packing 3x faster, tube shotguns load 25% faster.
  Ace: 3 kills with one shot pack the emptiest magazine in your rig at once.
- **Fully Loaded**: a 2x2 **ammo pouch** for loose rounds; rounds you pick up go there
  first. Ace: packing from the pouch keeps your gun in hand, so you can sprint.
- **Bulletstorm and Extra Lead** take the bag path: you can't pick up standard ammo boxes
  (spoils, throwables and arrows still).

## What changed in 0.23.0

The skill rework starts: the Mastermind **Medic** branch (vanilla only; see [Skills](#skills)).

- **Combat Medic** ace: reviving someone, or being revived, heals your head to full.
- **Quick Fix**: first aid kits deploy twice as fast only while your armour is broken. Ace:
  a kit's healing past a part's maximum stays as **overheal** (up to +25% of the part); it
  does not fade and goes first when that part is hit.
- **Painkillers**: a black part passes on 50% instead of 75%. Ace: an arm, leg or the torso
  that goes black keeps working for 40 s.
- **Uppers**: first aid kits stack 3 to a slot. Ace: the auto-revive heals your head to full.
- **Combat Doctor**: a doctor bag that heals black parts gives a buff by the parts it healed
  (torso: stamina, no screen shake, tasers and flashbangs shrugged off, +10% crit; legs:
  half the load's slowdown, no push; arms: steady aim, faster reloads and round packing,
  faster interactions). Ace: 60 s per black part healed and double for both limbs; basic:
  60 s at half strength.
- **Fixed:** an auto-revive (Uppers) with a black head healed every part but the head and
  left you standing at 0 health. The head now gets the revive value first.

## What changed in 0.22.1

- **Weight → concealment works in the heist.** The game works out your stealth detection
  once, while the player spawns. At that moment the weight read asked the game for the
  throwable count before the game had set it up: the game logged a fatal error and the
  penalty fell back to 0. The count is no longer asked for before it exists, and a weight
  that cannot be read keeps the last penalty instead of 0.
- **The menu's detection meter follows the inventory.** It is redrawn when the inventory
  screen closes, so what you bring shows in it at once.
- **Vanilla only:** with restoration-mod loaded the weight costs no concealment (like the
  ECM rule).

## What changed in 0.22.0

The first part of the skill rework (`SKILLS_REWORK_SPEC.md`): the core rules every player
gets, with or without skills. The skills themselves come in the next releases.

- **A black part passes damage on to the torso, then the head.**
  - A hit on a black part, and whatever is left over when a part goes black, goes on at
    **75%** to the **torso** only (was 70% split over every other part).
  - When the torso is black, the 75% goes to the **head**. A hit on the black torso itself
    goes to the head too, and so does what the torso cannot take.
  - So once the torso is black, every hit on a black part drains the head, and you go down
    when the head reaches 0.
- **ECMs last half as long.** Every ECM duration of the game is halved: a jammer lasts 10 s,
  15 s with both duration skills (was 20 s / 30 s); the low-battery phase and the feedback
  are halved too. Not with restoration-mod.
- **Weight costs concealment.** Every 3 kg over 15 kg is one point of concealment less
  (30 kg: -5, 60 kg: -15). It counts for stealth detection and for every skill that reads
  your detection risk, and the menu shows it. Off with the movement penalty
  (`PDTI.Carry.enabled = false`). Vanilla only (since 0.22.1).
- Unchanged and now tested as rules: first aid kits never heal black parts (only doctor bags
  do), ammo boxes stop at two stacks per weapon, and the game's "carry more deployables"
  upgrades change nothing (you place what you carry).

## What changed in 0.21.5

- **LMG HE rounds: a concussion round against people, an anti-armour round against
  bulldozers and turrets.**
  - Against bulldozers and turrets an HE blast does 4 times its damage, then the sure
    critical hit (x2): 2.8 times a standard round. restoration-mod's bulldozers also take
    x2.5 from explosions, so on a bulldozer it is about 7 standard rounds.
  - Every other enemy who survives an HE blast is stunned, every time, like by a concussion
    grenade (was a 35% chance). The damage to them stays low (0.35 of a standard round), so
    standard rounds still kill people faster.

## What changed in 0.21.4

- **Fix: the game crashed when an LMG HE round hit an enemy.** To roll the blast's critical
  hit, the mod called the game's own crit roll without the damage, which the current game
  needs ("attempt to perform arithmetic on local 'damage' (a nil value)" in
  `copdamage.lua`). The mod now rolls the crit itself with the same sums: the enemy's base
  chance plus your crit chance, if the weapon can crit with explosions.
- The hollow-point limb crit uses the damage the game passes in (and its cap), not the
  attack's raw damage.

## What changed in 0.21.3

- **Fix: ammo bags gained uses when you took from them.** Your inventory can hold more rounds
  than the game's maximum for a weapon. restoration-mod works out what you take as
  "1 - total / maximum", which is below zero then, and the bag got that much *more*. The game
  now never sees more than its maximum, and a bag never takes less than nothing. A bag also
  counts restoration-mod's ammo ratio of each weapon, as the game does.
- **Ammo boxes stop at two stacks.** A box fills a weapon's loose rounds up to two full
  stacks (200 rounds, every bullet kind counted). When both your primary and your secondary
  have that, boxes are not picked up any more and stay on the floor. Throwable pickups and
  arrows are not affected.
- **LMG HE rounds stun.** An enemy hit by an HE blast who survives it is dazed like by a
  concussion grenade, with a 35% chance per blast. Not bulldozers (they take sure critical
  hits instead), turrets or civilians.

## What changed in 0.21.2

- **LMG HE rounds can be critical hits.** The blast crits by your crit chance, as a bullet
  does (restoration-mod's explosions never crit on their own).
- **HE rounds always crit on bulldozers and turrets**, so the weak round is the one to
  bring against them. A critical hit multiplies the damage by the target's own critical
  multiplier (x2 when it has none).
- Only the blasts of your own HE rounds: grenades, launchers and other players' rounds are
  left to the game. With the vanilla game the blast is not rolled twice.

## What changed in 0.21.1

- **The rig has no weight cap.** Every rig and every part of it holds as much as its slots
  take, whatever it weighs. Everything you carry still slows you as before. The pockets and
  the backpack keep their caps. The inventory screen's weight line shows the rig's weight
  without a limit.

## What changed in 0.21.0

- LMGs have their own rounds. Their boxes and belts keep the game's sizes and can hold
  mixed loads; the top round fires first.
  - **HE round (HE):** very low damage (x0.35), and a small blast (60 cm) where it hits.
    It never pierces armour and never goes through anything.
  - **Penetrator (PEN):** x1.5 damage, through armour plates, enemies, shields and walls.
    From the shoulder it kicks four times as hard, and the kick climbs with every shot in a
    row up to twelve times: use short bursts at most. **Deploy the bipod** and it kicks only a
    little more than a standard round and does not climb.
- Prices: HE 150, penetrator 220 per round.

## What changed in 0.20.2

- Ammunition is sorted into categories: **AR/SMG**, **Shotgun** and **LMG**. The menu's
  bring list shows each category under its own heading.
- The spawner has one row per category. The spawn buttons say which category they spawn,
  and spawning shotgun shells for a rifle (or the other way round) is refused with the reason.
- LMGs take standard rounds only.

## What changed in 0.20.1

- The backpack side of the inventory screen no longer lists all your ammunition; the
  magazines and loose rounds are in the grids.
- Spawn for testing: Ctrl+click on "PRI loose" or "SEC loose" spawns a full stack of 100
  rounds (a plain click still spawns one magazine's worth).

## What changed in 0.20.0

- **Shotguns take the game's own ammunition types, shell by shell**: buckshot (the gun
  without an ammo mod), 000 Buckshot, Flechette, AP Slug, Tombstone Slug, Dragon's Breath
  and HE. Each shell does exactly what the game's ammo mod does (pellets, damage, fire,
  poison, explosion, armour piercing, shooting through shields); the mod asks the game for
  those values, it changes none of them. The ammo mod attached to the gun in the menu does
  not count: the shells you load decide.
- **Only the shells the gun takes**: the ones whose ammo mod the game lets you attach to that
  gun. Rifle rounds (hollow point, armour piercing) never go into a shotgun, and shells
  never go into a rifle; a plan made for another gun turns such rounds into standard ones.
- **Box-magazine shotguns** (Saiga/IZHMA, Steakout, Grimm, ...) keep the game's magazines;
  each magazine holds a mix of shells like a rifle magazine, the top one fired first. In
  the menu, the "+Mag" editor sets how many of each shell.
- **Tube shotguns** load shell by shell from the loose shells you carry. The mouse wheel
  chooses which kind goes in next ("Next shell: AP Slug"); the last shell loaded is fired
  first, as in a real tube. When the chosen kind runs out, the reload goes on with the next
  kind you carry. The HUD shows the shells in the tube in colour and the next one after
  LOADED.
- Prices per shell: buckshot $30, 000 $60, flechette $120, slug $150, tombstone $150,
  dragon's breath $200, HE $250.

## What changed in 0.19.9

- **The Assault Rig's ammunition slots no longer fill up by weight first.** The part had a
  14 kg limit, and loose rounds weigh by their kind: a stack of 100 shotgun shells is
  4.5 kg, so three stacks filled it with 18 of its 21 slots still empty, and the next
  magazine was refused. The limit is 30 kg now (all the weight still slows you as before).
- **Armour plates go in the ammunition slots**: the Assault Rig's ammunition part and the
  Medical Rig's two pouches (a plate fits a pouch turned on its side). Plates in any part
  of the rig are to hand for the Insert Armour Plate key.
- When weight refuses an item, the screen says where and by how much, for example "the
  rig's Ammunition section is full by weight: 27.5 + 4.5 kg, at most 30 kg", instead of
  "container weight limit exceeded".

## What changed in 0.19.8

- **Heals go to the most hurt part first.** Before, a heal was split over every part that
  is not black by what each missed. Once a part was black, the spread damage had hurt every
  part, so a small perk heal (Gambler gives 4 to 8 HP) became +0 or +1 on five parts and
  looked like nothing. Now the most hurt part (by share of its maximum) is filled first,
  then the next, so every heal shows. Black parts still need a medic bag.

## What changed in 0.19.7

- **What you bring has its own window in the menu.** With the new deployables the "Bring into
  every heist" list no longer fitted under the backpack (with the Large Backpack the bottom
  was cut off). In the menu it is now in the middle of the screen, where the health window
  is in a heist, and the items are two to a row.
- If a window is ever taller than the screen (a large "Inventory screen size", more items),
  the screen is drawn smaller until it fits, until you open it again.

## What changed in 0.19.6

- **Every deployable of the game is an inventory item now.** New: Trip Mine (1x1, stacks of
  3), ECM Jammer (1x2), Spy Camera (1x1, stacks of 2), Sentry Gun and Suppressed Sentry Gun
  (3x2), Throwable Case (2x2) and Armor Kit (2x2). Bring them from the menu like the others
  (prices: trip mine $1,500, spy camera $3,000, armor kit $6,000, ECM $8,000, throwable case
  $10,000, sentry guns $15,000). A deployable your game does not have is not offered.
- They are placed like the game places them: trip mines, ECMs and spy cameras on the wall or
  floor you look at, sentry guns and the throwable case put down like a bag, and the armor
  kit is used on yourself.
- **Sentry guns:** placing one costs no ammunition while the ammunition system is on (your
  rounds are inventory items). Picking one up puts it back into your rig, pockets or
  backpack; with no room it cannot be picked up (a hint says so).
- **What you place is what you carry**, as for ammo bags: a trip mine or sentry gun chosen in
  the game's loadout but not carried cannot be placed. Bring them in the menu. Deployables
  from other mods stay the game's.
- The deployable list in the inventory screen shows only the kinds you carry, and the test
  spawner shows its deployables in three columns.

## What changed in 0.19.5

- **Drag loose rounds onto a magazine to load it.** In the inventory screen, pick up a stack
  of loose rounds and let go on a magazine of the same weapon. The magazine lights up green
  when the rounds fit, red when they do not (another weapon's rounds, or a full magazine).
  - **In a heist** your character loads one round at a time (the "Round loading time"
    option, 0.25 s by default). It goes on after you close the screen, until the magazine
    is full or the stack runs out. Anything other than moving stops it: shooting, aiming,
    reloading, melee, throwing, interacting, switching weapons or the mouse wheel. Moving,
    sprinting, jumping and crouching do not.
  - **In the menu** the magazine is loaded at once.
  - The new rounds go on top with their own bullets, so dropping armour-piercing rounds on
    a half-empty standard magazine makes the next shots armour piercing.
  - The weapon is not put away while loading, so you can shoot at once (that stops it).

## What changed in 0.19.4

- **Picking up a dropped magazine works.** Aim at it and hold the interact key (F) for one
  second, like the game's own pickups. Your weapon is no longer put away first. The weapon
  switch is changed by other mods (restoration-mod has its own), and waiting for it could
  keep the pickup from ever starting.
- **The pickup hint goes away** when you look away from the magazine, pick it up, or aim at
  something the game itself can interact with (that comes first).
- **F does not also shout** while you aim at a dropped magazine.
- If a pickup fails, the log says why ("[PDTI AMMO] a dropped magazine could not be picked
  up: ...").

## What changed in 0.19.3

- **Magazines really fall now.** The game itself has a `drop_magazine_object` function, so
  0.19.2 took it for a magazine-drop mod and left the drop to it, but it drops nothing for
  your own gun. Now, whenever that drop (or a mod's) drops nothing, this mod drops the
  magazine itself.
- **Magazines past the game's limit on the floor are still picked up.** When the floor
  limit is reached, the game removes the oldest magazine and rebuilds its list. The mod used
  to count new magazines by the list's length, so from then on it recorded none and also
  kept them in the inventory. It now notes each magazine as the game registers it.
- **The option sliders give whole numbers.** Dragging a slider with the mouse ignored its
  step (6.5 magazine boxes). Every slider now snaps to its step, shows the snapped value,
  and whole-number settings (magazine boxes, font size, distances) show no decimals.

## What changed in 0.19.2

- **Magazines fall to the floor without another mod.** When no magazine-drop mod (such as
  "Drop My Mag") is installed, the mod drops a copy of the gun's magazine itself, the way the
  game drops other players' magazines. You pick it up as before. An empty magazine shows no
  rounds. If the game has not loaded the magazine or its collision box, nothing is spawned
  (that would crash the game): the magazine stays in the inventory and the log says why. With
  a magazine-drop mod installed, that mod's drop is used.
- **The fast reload drops the magazine** (since 0.19.1, whatever the "Dropped magazines"
  option says), and now it really falls.
- **A gun without a magazine reloads faster.** After you take the magazine out (or it fell
  and the reload stopped), the next reload skips the taking-out part: it is 1/0.7 (about 43%)
  faster, and nothing is dropped.
- **Armour piercing hits hardest.** Damage: armour piercing x1.3 (was x0.85), hollow points
  x1.1 (was x1.3). Hollow points still make every arm or leg hit a critical hit and never
  pierce plates; armour piercing still pierces and kicks harder.

## What changed in 0.19.1

- **The mouse wheel works.** The game does not always pass the wheel on as "switch
  weapon", so the mod now reads the wheel from the mouse itself. A key bound to "switch
  weapon" still switches weapons, and the wheel does nothing while you type in the chat or
  have a menu open.
- **Full magazines first, empty ones last.** Reloads, the wheel and the ammo panel go
  through your magazines from the fullest to the emptiest (by how full they are, so a full
  compact magazine comes before a half-full drum). Equally full magazines keep grid order:
  pockets first, then the rig, each read from the top left.
- **Dropped magazines need a magazine-drop mod.** The game itself only drops magazines for
  other players. With a mod such as "Drop My Mag", magazines fall to the floor and you can
  pick them up. Without one, nothing falls, and every old magazine goes back into the
  inventory. The log says at the start of a heist which case you are in.
- **The fast reload no longer loses the magazine.** Tapping R twice (or three times with
  akimbo) drops the old magazine whatever the "Dropped magazines" option says. If nothing
  can fall (no magazine-drop mod), the magazine is kept instead of disappearing.
- **The ammo panel logs why it cannot show.** If another HUD mod removes the game's player
  HUD panel, or drawing fails, the log has a line starting with "[PDTI AMMO] the ammunition
  panel cannot be shown".

## What changed in 0.19.0

- **The mouse wheel chooses the next magazine.**
  - With a weapon that is fed from magazines, the wheel no longer switches weapons. Keys
    1 and 2 still do.
  - Scrolling goes through the magazine in the gun and then your magazines in the rig and
    pockets, in grid order.
  - The ammo panel opens for 2 s and marks the choice with a yellow line. If the chosen
    magazine is further down than the panel's boxes, it takes the last box.
  - A reload loads the chosen magazine. A chosen magazine even goes into a full gun, for
    example to swap standard rounds for hollow points.
  - After a reload, the choice goes back to the first magazine with rounds in grid order.
- **Taking the magazine out.**
  - Scroll to the magazine in the gun (the panel says "R: TAKE OUT") and press R.
  - The reload animation runs until the magazine leaves the gun, then stops.
  - The magazine goes into the rig, the pockets or the backpack with its rounds, and the
    gun has no magazine, only a round in the chamber if it had one.
  - Akimbo: both magazines come out.
  - If there is no room anywhere, nothing happens and a hint says why.
  - Sprinting or anything else that interrupts the reload before the magazine is out
    leaves it in the gun.
- **The wheel is blocked during a reload.** It neither changes the choice nor switches the
  weapon (switching used to cancel the reload).
- The option **Mouse wheel chooses the magazine** turns this off.
- **ISSR leftovers removed.**
  - The options **Extra magazines** (`max_extra_mags`) and **Most ammunition carried**
    (`ammo_max`) are gone.
  - The game's ammunition maximum is now the normal ammunition: the magazine in the gun,
    the weapon's magazines, and anything more you chose to bring. There is no 125% any
    more.
  - Ammo boxes and dropped magazines are limited only by the room in your inventory. A
    dropped magazine can also go into the backpack.
  - Weapons loaded round by round (launchers, bows) keep the game's maximum.
  - An ammo bag still refills you up to your normal number of magazines; it doesn't fill
    your backpack with new ones. Its share is measured against the normal ammunition, as
    in the game.

## What changed in 0.18.10

- **Fixed: heavy armour "broken" at the start of a heist.**
  - The log showed `[PDTI ARMOUR] ICTV broken` in the first frame of a heist.
  - If the armour read 0 once before the game had filled it, the vest was marked broken.
    Its regeneration then stayed off for the whole heist.
  - Now a vest only breaks after it has been seen with armour in it during this heist. A
    vest with no armour at all (maximum 0) never breaks and gives no broken-vest reduction.
- **The crash at a heist start was not this mod.**
  - It happened while the game loaded the heist's asset packages (`load_packages`,
    `PackageManager:load`), which is a C++ exception in the engine.
  - This mod's heist code runs later (`GameSetup.init_finalize`), and it loads no packages
    or assets.

## What changed in 0.18.9

- **Larger boxes on the inventory screen.**
  - Cells are 36×32 (they were 30×30), and the windows are 320 wide (they were 290).
  - Buttons, rows and lines are larger too.
  - Labels in the cells have two short lines (for example "30" over "HP+", or "PRI" over
    "120").
  - Text that still doesn't fit gets a smaller font instead of being cut off.
  - The armour line in the health window wraps onto two lines.
  - The size can be changed: **Inventory screen size** in the options (0.7 to 1.5).
- **Repeated clicks work without moving the mouse.**
  - Before, a second click on the same button (`+` three times, for example) did nothing
    until the mouse moved.
  - The cause: BeardLib only takes a click on the item it has highlighted, and every
    click redraws the screen, which removes the highlight.
  - Now, after each redraw, the screen tells BeardLib on its next update where the mouse
    is, so the new button under it is highlighted again.
- **Ctrl+click fills a magazine.** In the menu's "+Mag" editor (assault rifles and SMGs):
  - Ctrl+click `+` on a bullet fills the rest of the magazine with that bullet.
  - Ctrl+click `-` takes that bullet out completely.
  - A plain click still changes it by 5, or by 1 for magazines under 10 rounds.
- **An options page:** Options → Mod Options → Tactical Inventory. See
  [Settings](#settings).

## What changed in 0.18.8

- **Heavy armour works differently from light armour.**
  - **Light armour** (Two-piece Suit up to the Heavy Ballistic Vest) is as in the game: it
    regenerates by itself, and once broken it protects nothing.
  - **Heavy armour** (Flak Jacket, Combined Tactical Vest, ICTV) does **not** regenerate once
    it is broken. You insert a new **armour plate** to fill it again.
  - Even broken, heavy armour still takes part of the damage to every body part except the
    head: Flak Jacket −10%, Combined Tactical Vest −18%, ICTV −25%.
  - Perk decks and skills that give armour back (Anarchist, Armorer, kills that restore armour,
    the armour bag) still work. Only the game's own regeneration timer, and the refill on a
    revive, are blocked.
- **Armour plates.** The old Armor Repair Kit item is now the **Armour Plate**: 2x1, 1.2 kg,
  $6,000.
  - Bring plates from the menu's Bring list.
  - Keep them in the rig or the pockets; a plate in the backpack must be moved first.
  - Bind the **Insert Armour Plate** key in the mod's keybinds.
  - Inserting takes 3 s and slows you to 60%. Firing, reloading or going down cancels it, and
    you keep the plate.
  - A used plate is paid again after the heist, like everything else you use up.
- **Finer colours for body parts:**
  - green at full;
  - dark green above 75%;
  - yellow above 50%;
  - orange above 25%;
  - red down to 0;
  - black at 0.
- The health window shows your armour: light or heavy, broken, or inserting a plate.

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
- **Everything costs money, deployables included.** First aid kit $4,000, doctor bag $35,000 (0.52.0; was $12,000),
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
| Hollow point (HP) | x1.1 | never pierces (the AP skill does not apply) | nothing | every hit on an arm or a leg is a critical hit |
| Armour piercing (AP) | x1.3 | always pierces | enemies and shields | less stable: recoil x1.5, building up to x2.4 in full auto |

- **In the menu** (the Deployable slot), for an assault rifle or SMG:
  - **Gun** picks the size and bullets of the magazine you start with in the gun.
  - **+Mag** picks what the `+` of the magazine row adds.
  - Loose rounds are brought by bullet type (STD / HP / AP).
  - Example: a drum of hollow points in the gun, and the rig full of compact AP magazines.
- **Reloads take magazines in grid order**, the order you put them in: pockets first, then
  the rig, each read from the top left. The first magazine with rounds is loaded. This
  replaces "fullest first" for every magazine weapon. (0.19.1: the fullest first again,
  grid order only between equally full magazines.)
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
| Medical | 8x2 kits and medic bags, 2 pouches 1x3 for magazines, loose rounds and armour plates | once per heist: SPACE while down gets you up, uses a medic bag |
| Assault | 7x3 magazines, loose rounds and armour plates, 6x2 ammo bags | |
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

-- Weapons, parts and build templates
PDTI.Armory.Weapons()                 -- the weapons you own, with where they are
PDTI.Armory.Buy(weapon_id)            -- buys one of today's weapons
PDTI.Armory.TodayPrice(weapon_id)
PDTI.Parts.ForWeapon(weapon_id)       -- the parts for sale for a weapon
PDTI.Parts.Buy(weapon_id, part_id)    -- buys a part (it goes into the locker)
PDTI.Parts.Fit(part_container, part_id, weapon_container, weapon_id)
PDTI.Parts.TakeOff(weapon_container, weapon_id, part_id)
PDTI.Parts.ApplyBuild(weapon_container, weapon_id, part_ids)
PDTI.Templates.All()                  -- the build templates you have
PDTI.Templates.Save(weapon_data)       -- saves a weapon's build as a template
PDTI.Templates.Apply(id, container, weapon_id)
PDTI.Templates.Delete(id)
PDTI.Templates.Describe(template)

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

**Lasting damage (0.48.0):** the parts keep what a heist left them (ended down, in custody or
left: every part at 0, the head at 1 HP). Heal at home for $15,000: Dallas's menu in the
safehouse, or the inventory screen's Health tab.

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
  goes on at 75% to the torso. When the torso is black (or the damage was on the torso), it
  goes to the head instead, so with a black torso hits on black parts drain the head until
  you go down. The rate is `Body.EFFECTS.spread_damage`.
- **Going down:**
  - When your head reaches 0, you go down. A deadly fall or the game forcing you into bleed-out
    does the same.
  - When you are revived, your head has 1 HP. Every other part stays as it was, and black parts
    stay black.
- **Healing:**
  - A first aid kit and every healing skill heal only the parts that are not black.
  - Every heal (a first aid kit, and perk decks and skills such as Sociopath, Gambler,
    Grinder, Muscle and Hostage Taker) goes to one part at a time: the most hurt part that
    is not black (the lowest share of its own maximum) is filled first, then the next.
  - A medic bag heals every part to full, black ones included. So does getting up with the
    medical rig's medic bag.
- **Where you see it:**
  - The HUD shows a small body figure above the health ring: green at full, dark green above
    75%, yellow above 50%, orange above 25%, red, and black at 0.
  - In a heist the inventory screen has a health window: every part with its HP and its
    maximum, coloured the same way, plus the effects of the black parts. The speed line
    shows the leg penalty.
- **Turning it off:** **Health per body part** in the [settings](#settings) (or
  `"body_parts": false` in `issr_reload_settings.txt`) gives the game's single health pool.

## Skills

The skill rework follows `SKILLS_REWORK_SPEC.md`, one branch group per release. It is
**vanilla only**: with restoration-mod loaded its skills stay as they are.

How it works (`lua/skills.lua`):

- The game keeps the skills you own in your save, so the skill tree is not rewritten. The mod
  reads what you own (`managers.skilltree:skill_step`: basic or ace) and gives the new effect
  itself.
- A vanilla upgrade that a rework replaces is switched off where the game reads it
  (`PlayerManager:upgrade_value` / `has_category_upgrade`), only while that rework applies.
- The skill texts in the tree are replaced.
- Each rework needs its PDTI system: with **Health per body part** off, the Medic skills are
  the game's again.

### Mastermind: Medic

| Skill | Basic | Ace |
|---|---|---|
| Combat Medic | vanilla (damage reduction while reviving) | your head heals to full when you revive someone or get revived (replaces +30% health for the one you revive) |
| Quick Fix | first aid kits deploy 50% faster, only while your armour is broken (light: until it regenerates; heavy: until a plate) | overheal: a kit's healing past a part's max is kept, up to +25% of that part; no decay; lost first when the part is hit |
| Painkillers | a black part passes on 50% (not 75%) | a part (not the head) going black has its penalties suspended for 40 s |
| Uppers | first aid kits stack 3 to a slot | vanilla auto-revive (5 m), and it heals your head to full |
| Combat Doctor | the doctor bag buff, weak: 60 s, half values | the full buff: 60 s per black part healed, limb effects x2 for both limbs; +2 doctor bag charges |
| Inspire | vanilla | vanilla |

### Enforcer: Ammo Specialist

Needs the ammo system; with it off the skills are the game's. **Bag path**: Bulletstorm and
Extra Lead (basic or ace) mean you can't pick up standard ammo boxes; spoils, throwables
and arrows you can.

| Skill | Basic | Ace |
|---|---|---|
| Scavenger | boxes from +50% (the game's), magazines on the floor from +50% (3.75 m), ammo bags taken 50% faster | reload +15% (replaces the extra box drop) |
| Bulletstorm | Hot Swap: taking from an ammo bag reloads the gun in your hands with your fullest magazine | Clean Swap: a reload within 3 m of one of your bags (with ammo left) puts the old magazine back full; replaces the no-ammo-cost window |
| Spoils (Portable Saw) | every 10th special you kill (one counter, a new one each heist) drops its item instead of ammo: Medic FAK, Shield armour plate, Taser 75-round magazine of HP, Marshal sniper 30-round magazine of AP, Cloaker throwable, Bulldozer ammo bag with 1 use; police snipers nothing. Without an AR/SMG the rounds come loose | Trophy: a melee kill on a special always drops it (the counter stays) |
| Extra Lead | +2 uses per ammo bag | Reserve Charge: your own bag keeps 1 use; you can take it only with no loaded magazine left for the gun in your hands (teammates can take it) |
| Speed Loader (Saw Massacre) | packing 3x faster; tube shotguns load 25% faster | Auto-load: 3 kills with one shot (an HE blast counts, one shell is one shot) pack the emptiest magazine in your rig from your loose rounds |
| Fully Loaded | Ammo Pouch: a 2x2 grid for loose rounds only; rounds go there first | On the Move: holding R packs from the pouch with the gun in hand (sprint works); shooting, aiming or reloading stops it |

The spoils lie where the enemy fell, as an ammo box with a different outline; walk over it.
Without the room for the item it stays and a hint says why. Without Fully Loaded what was in
the pouch moves to the backpack (when the inventory opens or a heist starts).

**Combat Doctor buff.** A doctor bag charge that heals at least one black arm, leg or the
torso. A new one replaces the running buff. The health window shows it with its time left.

| Healed | Effect | Ace (one / both limbs) | Basic |
|---|---|---|---|
| Torso | Stamina (max and regeneration) | +50% | +25% |
| Torso | Calm (screen shake) | none | half |
| Torso | Shrug off (tasers, flashbangs) | immune | half of the tases ignored, flashes half as long |
| Torso | Focus (crit chance) | +10% | +5% |
| Legs | Second wind (the load's slowdown) | -25% / -50% | -12.5% |
| Legs | Steady legs (melee push) | half / none | 75% |
| Arms | Steady aim (recoil, spread) | -15% / -30% | -7.5% |
| Arms | Fast hands (reload, round packing) | +15% / +30% | +7.5% |
| Arms | Interaction speed | +12.5% / +25% | +6.25% |

### Ghost: Silent Killer

Needs the ammo system. **HP** = hollow points; **HE** = the LMG's HE round. Sure crits
(natural prey): HP on limbs and (with Optical Illusions) cloakers, HE on bulldozers and
turrets.

| Skill | Basic | Ace |
|---|---|---|
| Second Wind | vanilla (speed when the armour breaks) + Momentum: a sure crit gives +10% speed for 3 s | a melee kill packs loose rounds of your magazine's special kind into the gun until it is full (replaces the crew speed) |
| Optical Illusions | HP always crits cloakers, on any part | a crit kill can't be saved by a medic (replaces the concealment bonuses) |
| The Professional | Concussive: HE stuns last 4.5 s instead of 3 | stunned enemies take +20% damage from every source (replaces the suppressor bonuses) |
| Low Blow | an HP hit on an arm or a leg heals your more hurt arm or leg by 2% (not a black one) | a medic killed from behind: enemies within 10 m are sick for 4 s (stand still, can't shoot) (replaces the concealment crit) |
| High Value Target | Shrapnel: HE blast 78 cm instead of 60 | Ignition: for 2 s after an HE sure crit, your HE hits set enemies on fire for 3 s (replaces the marked damage) |
| Unseen Strike | Trophy Ammo: a crit kill on natural prey drops 1 round of that kind (walk over it) | every hit with special rounds adds 1 to your next ammo box, up to 20; damage that gets through clears them; Bulletstorm and Extra Lead can take them (the box stays) |

### Technician: Surefire, Body Expertise

Needs the ammo system. AP = armour piercing rounds and the LMG's penetrator. Values as the
health window shows them.

| Skill | Basic | Ace |
|---|---|---|
| Surefire | Stacked Barrier: +10 per AP headshot, up to 50; soaks damage before armour and health; fades 3 s after the last hit that fed it, then 10 s of cooldown (replaces +15 magazine and the AP ace) | up to 60, fades after 4 s, 9 s cooldown |
| Body Expertise | vanilla + AP body shots with automatic weapons add 3 | vanilla + 9 |

The health window shows "Barrier: N (s left)" or its cooldown.

### Ghost: Shinobi, Artful Dodger

Skills not listed here are vanilla (ECM durations are scaled by the core rule R3).

| Skill | Basic | Ace |
|---|---|---|
| Cleaner | vanilla | vanilla + the body bag case takes 2 cells (2x1) instead of 4; you can run with a bagged body, at 70% of the run speed (walking with it stays 50%) (replaces +1 case) |
| ECM Specialist | ECM jammers stack 2 to a cell (replaces +1 ECM) | vanilla |
| Inner Pockets | vanilla | vanilla + 2 more pocket cells: the pockets are 2x3 and hold 6 kg instead of 4, with any armour |
| Sneaky Bastard | dodge by your speed, no cap: 0 standing still, 10% at the base sprint speed, more above it (replaces the concealment dodge) | 10% already at the base running speed (about 16% at the base sprint speed) |

Cleaner's items and ECM Specialist need the deployables-as-items system, Sneaky Bastard the
weight system. Your real speed counts, so weight, black legs and loot keep you from the
maximum.

### Fugitive: Berserker, Frenzy

Both need **Health per body part**.

| Skill | Basic | Ace |
|---|---|---|
| Berserker | melee damage +10% per black arm, leg or body, up to +50% (the head does not count) (replaces the low-health scaling) | the bonus also applies to bullets (enemies and turrets) |
| Frenzy | both arms and both legs start black and hold at most 1 HP; the rest of their health is gone. You keep the 10% less health damage and the slower healing (replaces the health cap) | the body too, and the health they lost goes to the head (the health stays the same in total). The damage reduction stays 10% (replaces the ace's 25%) |

Frenzy parts follow the usual rules:
- a first aid kit does not heal them;
- a doctor bag fills them to 1 HP, and they count as healed black parts for Combat Doctor;
- a hit on a black part sends 75% to the body, then the head.

Black legs mean no sprinting and black arms mean more recoil until a doctor bag fills them.
After custody they start black again.

### Perk deck: Yakuza

Needs **Health per body part**. The bonuses grow with the number of black arms and legs (the
head and the body do not count), not with missing health.

| Card | Vanilla | Here |
|---|---|---|
| 1 | armour recovers up to 20% faster at low health | up to 20% faster: 5% per black limb |
| 3 | up to 20% faster movement at low health | up to 20% faster: 5% per black limb |
| 5 | armour up to 40% | up to 40%: 10% per black limb |
| 7 | armour up to 60% | up to 60%: 15% per black limb |
| 9 | the low-health range doubled | the full bonus at 2 black limbs instead of 4 |

A limb that is black under Painkillers' suspension counts. A doctor bag that fills a limb takes
its share away. With Frenzy your limbs start black, so the deck starts at its full bonus.

### Extra Heist Info

With Extra Heist Info's buffs on, its buff bar also shows:

| Buff | Shows |
|---|---|
| Barrier | Stacked Barrier's absorption (screen units) |
| Barrier (cooldown colour) | the barrier's cooldown |
| Doctor | Doctor's orders (Combat Doctor) time left |
| Pain | the longest Painkillers suspension left |
| Overheal | the overheal you hold (Quick Fix ace) |
| Momentum | Second Wind's Momentum |
| Ignite | High Value Target ace's fire window |

EHI's own **Yakuza** and **Berserker** buffs show the reworked values (black limbs, black
parts). The dodge buff already includes Sneaky Bastard's speed dodge. The icons are the
skills' own. The buffs follow EHI's colour and position settings.

## Armour

| Armour | Kind | Once broken |
|---|---|---|
| Two-piece Suit, Lightweight Ballistic Vest, Ballistic Vest, Heavy Ballistic Vest | light | regenerates as in the game, protects nothing until then |
| Flak Jacket | heavy | no regeneration; body parts (not the head) take 90% |
| Combined Tactical Vest | heavy | no regeneration; body parts take 82% |
| ICTV | heavy | no regeneration; body parts take 75% |

- **Plates:**
  - The **Insert Armour Plate** key (bind it in the mod's keybinds) puts in an Armour Plate
    from the rig or the pockets.
  - It takes 3 s and slows you to 60%. Firing, reloading or going down cancels it, and you
    keep the plate.
  - The armour is full again, and it regenerates normally until it breaks again.
- **Perks:**
  - Anything a perk deck or skill gives back still works on broken heavy armour.
  - The game's regeneration timer stays off until a plate goes in. A revive does not refill
    broken heavy armour either.
- **Values:** in `Armour.HEAVY`, `Armour.PLATE_TIME` and `Armour.PLATE_SPEED`
  (`lua/armour.lua`).
- **Turning it off:** **Heavy armour plates** in the [settings](#settings) (or
  `"heavy_armour": false` in `issr_reload_settings.txt`) gives the game's armour.

## Settings

Options → Mod Options → Tactical Inventory. Each change is saved straight away into
`issr_settings.txt` and `issr_reload_settings.txt` in the `mods/saves` folder, the same files
as before, so you can still edit them by hand.

| Section | Setting | Key | Notes |
|---|---|---|---|
| General | Ammunition system | `enabled` | Off: the game's own ammunition. |
| General | Inventory screen size | `ui_scale` | 0.7 to 1.5. Applies the next time the screen opens. |
| General | Names on pictures | `item_picture_names` | On: a pictured item's name in its corner, and the weapon's name and weight over its faint picture in PRI / SEC. Off: the picture alone (full in PRI / SEC). |
| General | Pictures of weapons and parts | `item_pictures` | On: the game's pictures in the cells, PRI / SEC, a weapon's view and the market. Off: names on colours only. |
| Health and armour | Health per body part | `body_parts` | From the next heist. |
| Health and armour | Heavy armour plates | `heavy_armour` | From the next heist. |
| Reloading | Dropped magazines | `drop_mode` | Never, only empty magazines (default), or always. A fast reload always drops. |
| Reloading | Mouse wheel chooses the magazine | `wheel_choose` | Off: the wheel switches weapons as in the game. |
| Reloading | Round loading time | `round_interval` | Seconds per round. |
| Reloading | Reload hold time | `hold_time` | Holding the reload key longer than this counts as a hold. |
| Reloading | Ammo bags refill magazines | `unblock_bag` | |
| Reloading | Akimbo mouse buttons | `akimbo_buttons` | |
| Ammunition HUD | Always show, next magazine, loose rounds, calibre, "more", boxes, font size, position | `overlay_always`, `show_mags`, `show_loose`, `show_ammo_type`, `show_more`, `max_boxes`, `font_size`, `pad_right`, `pad_bottom` | The HUD is redrawn at once. |

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
- The **mouse wheel** chooses which magazine the next reload loads. The ammo panel marks it
  with a yellow line.
- Scrolling to the **magazine in the gun** and pressing R takes it out: the reload stops
  when the magazine is out, and the gun is left without one.
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
  give standard loose rounds only, up to two stacks (200 rounds) per weapon; with both guns
  there, boxes stay on the floor.
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

Every bag rolls a **quality** the first time you pick it up (0.28.0, `lua/loot_quality.lua`; 0.35.0-0.35.2 rolled at the heist start, undone in 0.35.3):

| Quality | Chance | Value | Modifiers |
| --- | --- | --- | --- |
| Standard | 80% | x1 | none |
| High quality | 17% | x2 | 1 |
| Exceptional | 3% | x4 | 2 (different) |

The modifiers are Runner, Nimble, Light, Compact, Discreet, Balanced, Quick hands, Padded and
Stackable (see "What changed in 0.28.0"). A thrown bag keeps its roll on the bag in the world,
so picking it up again gives the same bag. Logged: `[PDTI LOOT] <carry id> rolled <quality>
(<modifiers>)`.

(The game's "body bags" are something else: they are for carrying corpses.)

## The safehouse

The safehouse (the game's own, with its rooms and coins) is the base of the loot economy.

- **Captured loot** (0.29.0): a won job captures every bag the crew secured and every bag in
  your inventory. On the end screen you choose for each bag: **Stash** it, or **Sell now** for
  half its value. The game pays no money for bags any more.
- **The stash** (0.29.0) holds 12 bags and keeps their quality. A bag in it can be sold later.
- **Your base** (0.30.0): in the safehouse the inventory key opens the menu's whole screen
  (what you bring, rig, backpack, Captured, Stash), and the option "Start in the safehouse"
  takes you there when the game starts and after every job you finish offline.
- **Duke's Story Line** (0.43.0): talking to Duke offers the game's Story Line first; backing
  out of it brings you back to the safehouse.
- **Weapon insurance** (0.45.0): insure a weapon in its view (right-click it) for 30% of its
  built price; lost, it is back in your locker 10 real minutes after the heist. Duke's room makes
  it cheaper and faster (0.45.1: tier 2 costs 20%; tier 3 also brings it back in 5 minutes).
  Houston (0.53.0) sells it too: his room's menu lists your insured and uninsured weapons,
  with Insure all and a button for each of the 5 dearest uninsured ones.
- **Weapon condition** (0.47.0): weapons wear per round fired in a heist (rifles 100% -> 50% in
  2,500 rounds), jam below 50% (up to 1 shot in 10 at 0%; the Clear Jam key racks the gun in
  1 s), and are repaired in their view at home (20% of the built price from 0%). A worn gun
  sells for less; the free weapons never wear. Rust (0.50.0) repairs them too: his room's menu
  lists your worn weapons, with Repair all and a button for each of the 5 most worn.
- **Weapon skins** (0.49.0): Sydney (her room's menu, **Weapon skins**) puts the skins and
  colours you own on your weapons, any number of guns per skin, your best copy (StatBoost
  first). A legendary skin's own parts are free and lock the gun; yours come off. At home only;
  a skin sold on Steam comes off at the menu.

Planned: a market with daily prices and contracts. The safehouse room bonuses came in 0.31.0.

## Online

PDTI players play only with PDTI players (0.46.0). The game marks every lobby with its build key;
PDTI adds `_pdti` to it, so PDTI and vanilla lobbies never see each other (the lobby search, the
friends' list, quickplay and invites all use the key; restoration-mod keeps its players apart the
same way, and with it PDTI's key goes on top of restoration's). Any PDTI version plays with any
other. A host also checks every player who joins: PDTI says hello through SuperBLT's networking,
and a player whose game has not after 15 s (counted while they can talk) is removed with the
game's kick. A client leaves a lobby whose host never answers; in a heist it only warns. The log
shows the key: `[PDTI LOBBY] lobby key (NetworkMatchMakingSTEAM): payday2_..._pdti`.

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

**Concealment (0.22.0):** every `CONCEAL_STEP` (3) kg over `FREE_WEIGHT` costs a point of
concealment: 30 kg is -5, 60 kg is -15. The points are added through the game's own
`BlackMarketManager:visibility_modifiers`, so the stealth detection, the detection risk
that skills read and the menu's concealment all count them (`lua/skill_rules.lua`).

## UI status

The screen is two small windows at the edges of the screen, so the middle stays free. The
left one shows the loadout, the pockets and the rig, the deployable and the controls; the
right one the backpack, the loose rounds and magazines and the test spawner. There is
drag and drop: press on an item, move it and let go over a cell.

## Not yet implemented

- Multiplayer synchronization and host authority (0.46.0 only keeps PDTI players among
  themselves).
- Backpack/rig player models and access animations.
- Item effects for medical and utility items (the item-use API is there, the effects are
  not).
- The loot is still counted in bags; the individual valuables are not items yet.
- The rest of the safehouse (planned): spots in the safehouse that open the stash and the
  market, and a market with daily prices and contracts (the room bonuses came in 0.31.0). Small valuables stay the game's for now.

## Testing

Run `PDTI.RunSelfTests()` after the mod loads (20 model checks). Offline:

```
texlua tests/run_all.lua
```

That runs every suite, each in its own process:

| Suite | Checks | What it covers |
|---|---|---|
| `run_tests.lua` | 21 | the inventory model: rollback on failed saves, save recovery, item use |
| `ui_tests.lua` | 223 | the weapons market tab (0.42.0: a Primary and a Secondary page with their counts, a button per type in order (rifles, shotguns, LMGs, akimbo, special; pistols, SMGs, shotguns), only the types a page has, an LMG the game also calls an SMG with the LMGs, akimbo named first or second with the akimbo, a type's list alone with its name and count, the pick following the page and type, a new page on its first type; a type's list scrolls, a row's today / normal / for sale, a click picks it, Buy pays, none left refused with the reason, nothing overlaps, back to Loot), the inventory's Locker tab (its count, the 12x20 locker with 8 rows shown without the weapon slots, a weapon named in its cell; 0.51.0: the rows line, Down and Up, drawn in the same place, not past the end or before the start, the mouse wheel over it (taken), while dragging (the preview again), not over the locker or no cell (left to the game), no wheel without the game's ids), the weapon slots PRI and SEC in the left window (the free AMCAR a real weapon in PRI, dragged into the backpack at its 4x2 and back onto PRI grabbed by a middle cell, an empty slot named so (no weapon, in either slot); every redraw applying the slots to your hands; a pistol dragged by its second cell: red over PRI, green over SEC as one cell, the SEC box lit; dropped and shown there; the game's secondary following as the screen redraws; dragged off into the backpack at its own size; click and click; a secondary refused on PRI; Ctrl+click on SEC back to the locker and from the locker onto SEC, with the messages; nothing overlaps, no price graph left from the market, it fits 720p), the price list kept by a redraw (not doubled, made again when its rows change, gone when the market closes), the controls kept off while the market is open (turned on by something else: off again, on when it closes), the market's price list (every loot type but vehicles and small loot, it scrolls, a row's now and real), the 7-day graph (7 bars, today last, a click shows another type, nothing overlaps), no market tab in the inventory, the market opened on its own (the inventory's windows empty, Close, the inventory normal after it), the market (offers with Accept, Accept makes a contract, Deliver refused without the bags with the reason, delivered with them, a busy market fits, lines readable), Clover's loot slots drawn next to the medium backpack (every rig, layout clean), the Room bonuses tab (picking, a bonus not made yet, every combination with the biggest bonuses fits 720p), the inventory windows (the bring list in the middle in the menu, its Captured and Stash tabs, the end screen's captured loot window and its S/X keys, two items to a row, the health window in a heist, drawn smaller when the screen is too low) against a fake BeardLib MenuUI, layout, overlap, fit, text that shrinks to fit its box, the re-highlight after a redraw (a second click without moving the mouse); 0.44.1: the price list dearest first, the graph on the first row |
| `hooks_tests.lua` | 28 | the controls kept off every frame while the screen is open, the hook scripts, mod.txt and the heist start; 0.45.0: the insurance looks every frame (the safehouse), not while paused |
| `ammo_tests.lua` | 49 | the ammunition system against a fake game: supply, reload, pickup, ammo bag, packing |
| `install_tests.lua` | 16 | the hooks go in when the game loads its weapon classes late |
| `loot_tests.lua` | 32 | the loot bags that follow the game's carry, nothing asked in the menu |
| `safehouse_tests.lua` | 203 | the armory looks at the main menu (a heist left unfinished), the start dialog of the mod's own save is asked for there, the weapons follow the slots once per player unit (the heist begins, after custody), Scarface's room menu has Market (opens the market; no other room; not with the loot system off), Duke's room menu has Story Line first and picked (before Upgrade and Close; leaves the game's way, marked for the way back; no other room; not online), the Story Line trip (planned on the way back, not in the first frame, the story_missions page opened offline, no trip or time limit on it or a heist's contract, home from the first page, the page not opening: tried twice then told, the page failing, with the option off), the laptop (exit_to_crimenet: to crime.net marked for the way back, the game's exit not run, offline only, not in a heist, the way out failing, every other object logged once), the Contract Broker trip (opened on crime.net after half a second, not again after backing out, no time limit, home from the first page, the option off, crime.net opened once if it does not come, then told once, a dialog first, a long dialog, the broker not opening), the safehouse as your base: it is the menu there (saved, the whole screen, no restock), the heist systems leave the inventory alone (ammunition, loot, deployables, plates), the way there at game start and after an offline job (at once, under a black screen that a dialog takes away, and every case where you stay in the menu), the safehouse's briefing passed for you (only on the mod's trips, offline, with the option on), the hooks on the main menu, the briefing and the end screen, the armory opening the inventory screen (the game's weapon menu when it cannot open, and in the raid), a waiting raid offered first (Defend offline, Ignore on to the safehouse, Back, the game's own menus untouched), the rooms' menus on the heisters (the heister-to-room mapping, Upgrade with the game's purchase and a save, not enough coins, the top tier, Wolf's Open inventory on the next frame, the daily side job and its hint, the raid, no data, the list of heisters), Chains' room (its zone around Chains, not Wolf's floor below, interact at nothing leaves for the menu inventory, at something, outside or with the screen open is the game's, the hint once per entry, his usual spot when he is not found), the menu inventory trip (not in the menu's first frame, the page opens, no time limit inside it even with a dialog, a page that does not open: tried again once, then you stay and are told once, back to the safehouse from the first page, with the option off, a dialog first, the page or the way out failing), the weapon racks being the game's, the arrival hint, the probe; 0.45.0: the menu's update looks at the insurance every frame, also with no trip waiting |
| `market_tests.lua` | 84 | mission items and loot the escape does not secure left out of the price list, encoded bag values (the game's get_value first), the default value for loot without one, people and entries without a bag type left out, the price list (base values, dearest today first since 0.44.1 (today's price, not the real one; the same price by name), small loot and vehicles left out, now with today's change, stashed counts, one row for two ids of one name), the 7-day history (dates, past drift, sales of past days from the log, today live also without a log), the sales log (kept 20 days, saved, bad entries dropped), day numbers, the drift (+-20%, the same all day, changing by day and type), saturation (-8% a sale, +4% a day, never below 40%), sell and sell-now at the market price, offers (3 a day, the same all day, a month of them keep to their level), accept (leaves the offers, not twice, due date, a fourth refused, a new day refills, run-out contracts dropped), deliver (refused with the count, quality and type checked, the cheapest bags, pays value x multiplier, coins, done), the High roll (used on the next Standard pickup only), save and load, bad data made safe, Ethan & Hila (4 offers, the featured type +25%) |
| `armory_tests.lua` | 177 | the weapons catalog (unlocked only, not enemies', primaries first), today's price (+-30%, the 5/7 example), the daily stock (0-3, a new day, none left), buying (a weapon item in the locker as the game builds it, its size and weight, paid, no money, locked, in a heist, a full locker refused before paying), the free AMCAR and Chimano 88 given as real items when you own none of a kind (marked free, dragged off into the backpack, no second one while you own one, the game still gets an AMCAR for an empty slot, again after a death or a left heist, not after you threw your own away (noted in the file; an older file owes none), never in a heist or with restoration-mod, not when the game does not know the weapon, their numbers saved), in a heist (the locker stays at home, a slot's weapon to the backpack and back, the last weapon may leave your hands too, the loadout's weapon is the slot's item and an empty slot weighs nothing so a packed weapon counts once; in the menu a slot may be emptied), the player's hands following the slots (nothing to change, a weapon taken out removed and deleted with its HUD ammo cleared, its magazine out of its magazine slot and the other weapon held, one put back added holstered with its blueprint, an empty SEC at spawn, both empty: no weapon in your hands (the pistol kept as a hidden, empty stand-in that Pick Up Weapons will not drop, its magazine out of the slot, nothing more the next time, gone when a weapon goes into a slot, the safehouse too, a real Chimano 88 not taken for it, a Chimano 88 stand-in when only a primary is left, else the primary), additions before removals; with the stand-in in hand no firing, reloading, fire mode, gadget, inspecting, bipod, underbarrel or aiming (aiming ends), melee still works, kept hidden after the game's update, no ammunition from boxes or bags, a weapon already gone not read, a real weapon unchanged; a rifle picked up with no weapon in your hands replaces the stand-in at once, a weapon the game cannot spawn leaves the one you hold, no player), weapons packed on the briefing screen counted when the heist fails or is left, picked-up weapons with Pick Up Weapons (the hook put in place at spawn, nothing changed without that mod's data or outside a heist or with no grid weapons, an enemy's weapon becomes the slot's weapon even if not unlocked with the parts the game built or its default parts, yours left on the ground and given back as the same item when picked up again, two of one model told apart by their parts or by their kind, an enemy's weapon of your model is a new one, an enemy's weapon swapped for another is gone, a slot's weapon that was not in your hands is not lost, the screen redrawn, the factory it was built with, the weapon replaced never touched once the game deleted it nor one already gone; won: what you carry is yours once, in its slot or the locker, not unlocked or packed to the locker, already there not added twice, no room waits, kept in the file; what you left on the ground is lost; failed or left: nothing picked up kept), a 4x2 rifle taking the one cell of a weapon slot and its own 4x2 again in the locker, the sizes by class (the minigun 5x2), the armory file (today's purchases, broken data made safe, unreadable), the file names on the mod's own save, the hands (a primary only in the primary hand, one weapon to a hand, a locked weapon refused, not checked while reading the save), the game's slots following the hands (the defaults when empty, slot 1 only, the menu scene and outfit told, nothing written when nothing changed, a slot not equipped or another weapon or factory written again, again after the game reads its save, not in a heist where not even the plan is read), in a heist the locker and hands do not change and weigh nothing, a packed weapon weighs, Ctrl+click to its hand and back, death (the weapons brought, won keeps all, failed is noted and taken out at the menu, the locker kept, the defaults again, a left heist, the safehouse), a build's price, the game's weapon screen (no buying, modding or selling weapons, a mask still sells), no restart (the menu, the votes, the fail screen leaves the job), the magazine in a weapon goes with it (a new weapon's full one in its box, into the locker and back the same magazine and weight, another weapon's own, another kind's refused, no weapon no magazine, taken out by hand stays out and is no weapon's, put back is its own, two of one model each its own, thrown away gone with it, an older save's box magazines into their weapons), in a heist each unit knows its item (read before the game deletes it, the same model swapped, loaded from its own item, read when taken out and before it becomes the stand-in, the stand-in never again) |
| `parts_tests.lua` | 212 | weapon parts as grid items: the market's list for a weapon (not its own parts, not a DLC part you don't own but one you do, not hidden, achievement, never-dropping or ammunition parts, not an assault rifle's magazine parts but a pistol's, by type then price), a part's price (the game's for that weapon, infamous dearer, each part's own change of the day), its size and weight by type, Buy (into the locker, paid, refused: not for sale, no money, in a heist, a full locker before paying, paid back if it could not be put in); fitting (onto the AMCAR in PRI and its game slot, the old sight off into the locker, the weapon's own part just goes, a skin's part just goes, not a part it does not take, not one it has, a forbidden grip comes off, then the stock blocks it, heavier with a tactical stock, no room: nothing changes, in a heist a sight but not a magazine, a locker weapon's slot unchanged, a pistol's extended magazine resizes the magazine it keeps); taking off (its own part comes back, a laser just comes off, not its own part, not one it lacks, not a skin's, no room, off a backpack weapon stays in the backpack); selling (not a free weapon, half of today's price with its parts, a part half, nothing in a heist, its magazine paid back, from your hands its box magazine too and the game slot follows); death (carried parts lost, the locker's kept, a win keeps them); the screen (a part over PRI lights it, red over SEC with the reason, the drop fits, a locker weapon lights whole, refused with the part named, a part over a part is no fit, Inspect not for other items or in a heist, which weapons a part fits, a part's cell label, Shift+click Inspect without picking up, a held item let go, Close, Take off, Sell twice, a free weapon's and a skin's part, a press with Shift, a part's Inspect, the market's parts list, Buy part, the list gone on the Loot tab); the weapon view (0.38.1: slot names, every part on it in the slots' order with the rest by slot name, its free slots in that order, the CAR-4 with only its own, weight and concealment, a fitted part first with Take off, no free slot left, the count, the AMCAR's parts with a named standard one marked and a skin's part kept on, none with Take off, a 22-part weapon fits 720p, a right click on a weapon and on a part opens their views, anything else, outside the cells and while dragging left alone, the left button still picks up); the slots (0.38.2: a slot per part and an empty one per kind for sale in order, an empty slot sorted against itself, off onto a cell turned, said so, not onto a taken cell, the pockets or a weapon slot, another part that comes off goes next to the weapon, no room for it: nothing comes off; the slot drag: a press drags your part out, the status, a green preview with its size, turned, red on a taken cell and the pockets, let go outside, in the window or on a slot it stays on, on a taken cell it stays on with why, on a free cell it comes off there, not the weapon's own, not an empty slot, not a gone weapon; a part over its slot green, over another red with where it goes, a gone weapon's slot nothing, let go there it stays, on its slot fitted, a blocked one red with the blocker, not a part red; Ctrl+click off next to the weapon, not the weapon's own, not an empty slot, not while holding or dragging; picking up ends a slot drag and the other way round, closing ends it; the screen: the CAR-4's boxes, no Take off, the help, three a row, colours, the count, a plain click says how, Ctrl+click off, the view says so, a press drags out with the box lifted, let go on a locker cell, the slot lit green and another red, let go on its slot fitted, Ctrl+press off, a right press left alone, the weapon's own not dragged, the middle window is the inventory, the mouse over a box finds its slot, the AMCAR's 9 slots, an empty slot darker, a 22-part weapon's 25 slots fit 720p); the gun in your hands (0.38.3: in the safehouse the guns made at spawn are kept and learn their builds, a sight fitted to the AMCAR in PRI makes the gun again with it at once, it knows its build, nothing again, taken off it is made again with its own sight, the pistol never made again, a locker weapon's change makes nothing again, in a heist a gun this mod made with another build is made again, one the game made is taken as it is); 0.44.0: a dragged part marks green the weapons that take it (PRI and the locker, every cell of each, not one that does not take it; marked once while the mouse moves; gone when let go; one with a part of its kind on still marked; nothing for an item that is not a part), the game's own mods into the locker (none on the game's own save, said once; none in a heist; each its own item with its global value and uid; gone from the game's inventory; ammunition, no part or no black market entry stay; the progress saved once and told; nothing twice; a new drop at the next menu; a full locker: they wait and you are told; a small place takes a sight while a grip waits; refused after leaving the game's inventory: given back) |
| `pictures_tests.lua` | 88 | pictures (0.40.0; names on pictures off in 0.40.1: on by default, the AMCAR and a part in the grid picture alone, PRI the picture alone at full strength, a bandage and the Chimano keep their names, the weapon view keeps its text, saved with the others): the paths (a weapon's from the game's function, none for one the game lacks, looked up once and said once in the log, a part's from its DLC's folder or the game's own, none for an unknown part, an item's, nothing else's, on by default, the setting off, no DB or a failing game function: none); the loading (no loader: at once, asked once, drawn when it came, one the game had at once, a failing loader at once, given back with each index, asked again after); the geometry (a 4x2 rifle: 8 pieces in their cells and the picture, the shape kept, centred, following on past the gaps, from edge to edge; turned: the whole picture in each cell, turned, one centre, its unturned size; one cell; a square on a 4x1 item only in the middle cells; no size: nothing); the screen (not drawn before the pictures came, one redraw for all, an AMCAR in the locker across all its cells over the colour and under the text, its name top-left, PRI whole and centred, faint under the centred text, the windows keep no size probe, the Chimano with none the old look, a bandage none, a DLC part's; the drop preview above it, a picture that comes while dragging waits; each size read once, one the game had drawn at once with no redraw more, a redraw dropped while closed does not block the next; turned in the locker, the pieces meeting; the weapon view's picture in the middle of its slots, 120 high and centred, the laser's slot box after it came, its picture in the box, a standard part's and an empty box none; a part's view; the Chimano's view no gap; 22 parts with the picture fit 720p; closing: the pictures go, then every texture back, the next opening asks again; the market's picked weapon, none for the Chimano (on the Secondary page) with no gap, the page kept when the market opens again; the setting off: none anywhere, nor in the market; saved with the others; no undocumented MenuUI parameters) |
| `template_tests.lua` | 46 | gun build templates (0.41.0): saving a build (named after the weapon, numbered, the weapon's own parts left out, none without parts), applying it (the parts you own and the weapon takes, the parts that come off as items, what is left out and why), deleting, the file per profile (a broken one ignored), at home only, the weapon view's Save, Apply and Del |
| `hotmod_tests.lua` | 112 | hot modding (0.39.0): the times by part; at home (the menu and the safehouse at once, the gun in your hands made again, no note); in a heist (what you carry noted at the spawn with the builds, a sight 3 s and what stops it said, nothing changes before, one change at a time and nothing off meanwhile, a third of the way, done: on, its item gone, the gun made again, the status; no magazine on or off, nothing from or onto a locker weapon, nothing sold; stopped by shooting and switching, not by moving, carrying, an unknown state or a click with the screen open, stopped by going down and none starts down, on or off; before the mask is on it goes on; the screen redrawn each second, not while dragging; off onto a taken cell refused, nothing into the locker, a free cell, its cell taken meanwhile next to the weapon, a cell turned; off with no cell next to the weapon never the locker; a part moved meanwhile still fitted, thrown away not, a packed weapon modded, a weapon thrown away nothing off); death (failed: the weapon, a part fitted there and one thrown away lost, the locker kept, nothing noted; a part taken off there no item; a left heist); a win (noted: the build, what is gone, the part taken off; at the menu the build, its weight, the item gone, the part where it was, the laser lost, the rest as it was, the game's weapon, nothing left, a new uid above; no room: the locker, else it waits in the file and comes the next menu; the next day of a heist begins with it and notes anew, then lost; a respawn keeps the first note; no spawn: nothing; nothing to do: nothing written; a part already there not twice; a crash's note replaced; the file's broken entries left out, a new uid above a waiting part's); the screen in a heist (no middle window, the health window, a right click opens the view and the health window steps aside, no Sell, the heist line, the magazine "(at home)", a part dropped on the weapon goes on in time, the slot's percentage, another part waits over the weapon and stays, a slot of yours not dragged out and an empty slot waits meanwhile, Ctrl+click off in time, a part on its slot in time, a slot dragged onto a cell in time, another weapon's view does not show the change, closed: the health window back, the locker not looked into, the weapon looked at gone: no market) |
| `save_slot_tests.lua` | 19 | the mod's own save (slot 86 for progress and its backup on Windows, the settings slot kept, once per load, the game's own slot elsewhere), the start dialog (only on the mod's save, once, level 100 the game's way one level at a time, 120 coins, both monies, the game saves, written down; start fresh; a save already played or infamous; progress not read yet; a failing level-up) |
| `stash_tests.lua` | 58 | a mixed stack captured bag by bag with its own quality, the stash: the end screen waits for the choice (and does not when the window cannot open), a won job captures secured and inventory bags (not small loot or vehicles), custody, a lost job, days of a job, the game pays nothing for bags, stash or sell now at 50%, sell from the stash, 12 bags of room, Compact and Stackable space, the file |
| `loot_quality_tests.lua` | 81 | rolled on the first pickup (none before), a thrown bag picked up again keeps its roll without a hint, a new High roll hints, mixed stacks (any quality of the same loot rides on a Stackable bag, not another loot, tooltip, each roll counted, Light riders, taking off / removing the last one, gathering singles when stored or put away from the hands, old stacks keep their copies, a stack does not ride on another), fewer hints (none for a bag held before, aim hint only High+ and once per bag), the highlight mark and material refresh, the sight ray (stops 30 cm short, aims 25 cm up, ignores the bag, no ray up close), Stackable pickups onto a stack with no free place (allowed, onto the stack, hands free, nothing lost; not for other or unrolled bags; also while carrying), the stack key, bags rolled at the heist start and when they appear (once; not people), seen (in front, near, not through a wall, not behind or 30 m away), no outline without Duke, Duke tier 2 outlines seen High/Exceptional bags (not Standard, not unseen) and says nothing when aimed at, a picked-up bag keeps its level roll, tier 3 aim hint (once a while, only seen bags) and the first Standard pickup rerolled (only the first, again next heist, never a bag held before, not at tier 2), the scan's pace and the loot tick running it, bag quality: outline of a thrown bag, pickup hint, 80/17/3 roll, no re-roll, kept through a throw and pickup, every modifier on and off, stacks of 4 and taking a bag off one, off with restoration-mod |
| `deployable_tests.lua` | 83 | count, first found, own pick, X cycle, blocking, placement, HUD line, carry weight |
| `feed_tests.lua` | 74 | loose-fed weapons, magazines never created, the HUD refresh |
| `speed_tests.lua` | 39 | the Laser Chronometer weighs nothing; loot, armour and weapon weight on the speed |
| `drag_tests.lua` | 37 | drag and drop, the fill order, ammunition weight |
| `reload_tests.lua` | 32 | double tap (the magazine kept when none can fall), the swap when there is no room, slot colours |
| `gear_tests.lua` | 77 | rig sections, plates in the ammunition slots, no weight cap in the rig (shells fill every slot, kits fill the medical part), the backpack's cap and its refusal saying where and how much, backpacks, their speed, enemy focus, getting up, magazine sizes, old saves |
| `plan_tests.lua` | 55 | menu plan, per-profile inventories, every heist starting from the plan, ammunition kept by its weapon (another weapon in a slot changes none of it, the old weapon back has all of it, a kind's size from the weapon in hand or one of yours, an unknown weapon's left alone) |
| `menu_tests.lua` | 26 | the Deployable slot opens the inventory, the briefing is the menu, stacks of 100 |
| `akimbo_tests.lua` | 54 | akimbo: half-size magazines, one per gun, 1/2/3 taps, no room, packing, HUD; weapon order and error clean-up of `ForEachWeapon` |
| `gun_slot_tests.lua` | 80 | the magazine in the gun in the weapon's slot: out, in, reloads, akimbo halves, a weapon swapped in the heist (its own magazine in the slot, the old gun's gone with it, the same model again, a shell-by-shell shotgun none, the gun's own kept; the armory's stand-in is no gun to it), the screen, the gun's magazine going with its weapon (read with its rounds and weight, put back the same and no free rounds, size and bullets, emptied stays empty, never settled keeps the game's, not loaded twice, the chamber, a shotgun's shells, akimbo both and one, at most two, only the gun's own kind in its box, labels by weapon, a heist's chosen ammunition first, your weapon at the start emptied or holding one) |
| `recoil_tests.lua` | 14 | AP recoil: x1.5 per shot, the full-auto build-up and its x2.4 cap, a pause resets it, fast taps count, the rate of fire, mixed magazines, other bullets and weapons untouched |
| `hook_chain_tests.lua` | 8 | two parts of the mod on one game function: no re-wrapping over 100 frames, recoil applied once per part, re-wrapped once after another mod replaces it |
| `bag_price_tests.lua` | 58 | boxes give standard rounds only, bags refill magazines with their own bullets and add new ones of the menu choice, nearly empty bags, prices by size and bullet, `+` pays and `-` pays back (never more than paid), deployable prices, refused without money, the restock of rounds, items and throwables used (capped by the plan), the menu lines; 0.52.0: the doctor bag at $35,000 |
| `ammo_conservation_tests.lua` | 13 | 40 random heists (rifle, akimbo SMGs): special rounds never appear out of nowhere; old vs new load helpers on 400 random loads; the gun slot follows the gun |
| `armour_tests.lua` | 49 | light armour as the game, heavy armour: no regeneration once broken, no refill on revive, perks still give armour, broken-vest reduction per vest (head exempt, spread hits, AP through the last armour), plates (refusals, cancel by firing, 3 s, one used, speed 0.6), the setting off, the colour thresholds, no false "broken" when the vest reads 0 before it was filled or has no armour |
| `body_tests.lua` | 60 | health per body part: where hits land, black parts and the 75% spill to the torso, head down and revive at 1 HP, first aid kit vs medic bag, heals to the most hurt part first (one part at a time, also with a black part), arm/leg/body effects, deadly falls, Frenzy, turned off, the open screen refreshed on a hit |
| `akimbo_buttons_tests.lua` | 36 | akimbo: left button = left gun, right button = right gun, no aiming, own magazines, single fire, turned off, a black arm cannot fire its gun |
| `typed_ammo_tests.lua` | 144 | AR/SMG sizes and bullets, mixed magazines shot by shot, the weapon slots, colours, the dev spawner, the menu plan, the UI (loose rounds labelled by weapon), Ctrl+click fill and empty, another weapon keeps the first one's magazines (its gun's into the inventory, back into the gun when it returns) |
| `options_tests.lua` | 29 | sliders snapped to their step and shown without decimals, the settings saved into the right file and read back, the options page with a fake MenuHelper (every setting, its text, its order), the callbacks (toggles, choices, sliders rounded and clamped), the HUD redrawn, the screen size, the ISSR leftovers gone |
| `wheel_tests.lua` | 81 | picking a magazine up (the hint once, the 1 s hold without holstering, the hint removed when you look away, the game's interaction first, F not shouting), the fallback when the existing drop drops nothing, the floor limit, the mod's own magazine drop (spawned only when loaded, the collision box, once per reload, the pickup record), the faster reload without a magazine, the wheel (read from the mouse, a switch-weapon key still switches, not in the chat): the choice list, the fullest first and empty last, the fast reload dropping whatever the mode, the HUD problem logged, up and down, wrapping round, blocked during a reload, turned off; the chosen magazine loaded, even into a full gun; taking the magazine out (stops when it leaves the gun, into the inventory with its rounds, no spare needed, no floor drop, interrupted, no room, a magazine not in the slot yet synced then taken out, the slot holding another magazine named as the reason, akimbo); the panel's order and mark; the normal ammunition maximum; boxes limited by room |
| `load_tests.lua` | 24 | loose rounds dropped on a magazine: the green/red preview, round by round in a heist (one per round time, bullets on top), moving does not stop it, shooting, reloading, aiming, melee, interact, switching and throwing stop it, until full, until the stack runs out, another weapon's rounds refused, all at once in the menu |
| `shell_tests.lua` | 64 | shotgun shells: the families (rifle rounds and shells never mix), the shells a gun takes from its part list, the game's own values per shell (slug, dragon's breath, HE) captured without touching the real blueprint or the ammunition count, recapture, mixed box magazines shot by shot, tubes (last in fires first, the wheel, the fallback, the game's reload), prices, the menu plan |
| `lmg_ammo_tests.lua` | 54 | LMG rounds: the family, HE (low damage, the game's explosive bullet with a 60 cm blast, the weapon's own bullet back after), penetrators (plates, enemies, shields, walls; the kick from the shoulder and on the bipod), mixed belts shot by shot, HE critical hits (the player's roll, always on bulldozers by name or tag and on turrets, not rolled twice, only your own HE blasts, the mark cleared after an error), the HE stun (a chance, the blast's position, not dead enemies, civilians, bulldozers or turrets, not other explosions), the HE crit rolled by the mod (never the game's roll without the damage, which crashed the game), a failed roll, no crit chance, a weapon that cannot crit, x4 on bulldozers and turrets before the crit, every blast stuns people and stays weak against them |
| `bag_box_tests.lua` | 23 | restoration-mod's ammo bag and box code: a bag never gains uses (shells above the game's maximum, again and again), what it gives below it, the ammo ratio; boxes up to two stacks per weapon, both full: the box stays (even with grenades to fill), throwables and arrows left to the game, boxes again after shooting, every bullet kind counted |
| `core_rules_tests.lua` | 37 | the skill rework's core rules: a black part's damage at 75% to the torso, with a black torso to the head (hits on the torso too), down when the head is gone, explosions; first aid kits never heal black parts; ECM durations halved once, not with restoration-mod; 1 concealment point per 3 kg over 15 kg through the game's visibility modifier, not twice, off with the weight penalty; boxes at two stacks; deployable quantity upgrades ignored; 0.22.1: vanilla only, a failed weight read keeps the last penalty, the menu's detection meter redrawn, the throwable count not asked for while the player spawns |
| `medic_tests.lua` | 83 | the skill frame (switched-off upgrades, restoration-mod and body parts off keep the game's skills, the texts) and the Medic branch: Combat Medic head on revive and reviving (not freeing, not someone else's), Quick Fix deploy only with broken armour (light, heavy until a plate), overheal (kept, capped, lost first, only from a kit, gone next heist), Painkillers 50% spill and 40 s suspension (not the head), Uppers stack and the auto-revive head, the Combat Doctor buff (count, duration, groups, one or both limbs, basic values, replaced not stacked, ends, every effect) |
| `ammo_specialist_tests.lua` | 113 | the Ammo Specialist branch: two wraps of one function, upgrade levels (the bag's +2 uses, no Bulletstorm window), Scavenger ranges, bag timer and reload, Hot Swap, Clean Swap (your bag only, within 3 m, with ammo; the next magazine taken first), Spoils (the 10th special, snipers and cops not counted, every item, Trophy, no room, teammates, loose rounds without an AR/SMG), the one-use bag (host and client), Reserve Charge, R8, Speed Loader (composed with fast hands, tubes, Auto-load: 3 kills of one shot, an HE blast, the window), the pouch (loose rounds only, filled first, packing from it in hand, emptied without the skill), ammo off and restoration-mod keep the game's skills; 0.44.0: the first refused box of a heist says why (which skill), once a heist |
| `unarmed_box_tests.lua` | 19 | 0.44.0: into a heist with no weapon (the stand-in): a box stays and the log says why, once, a box read once; an enemy's Compact-5 picked up (Pick Up Weapons): in your hands, managed, boxes give it loose rounds; then a CAR-4: boxes give the gun in hand rounds; Bulletstorm: the box stays and the hint says why; a gun at the box limit: not logged; the reason for each gun (room and pickup, not the player's, no gun) |
| `insurance_tests.lua` | 106 | 0.45.0: insuring (30% of the weapon and its parts, paid, told; for its build; not twice, not a free weapon, only weapons, not without the money, not in a heist; kept; broken entries dropped), a failed heist (both gone at the menu, the insured one due 10 min after the heist ended, not at the menu's time; the clock-time line; the uninsured lost; not at 9:59, at 10:00 in the locker with the insured build, a new uid, no magazine; used up; the hint; saved; the next uid its own), an abandoned heist, left on the ground and thrown away in a won heist (once), a win keeps it and a later loss still claims, a full locker (waits, said, logged once, comes with room), due in a heist (home first), the safehouse tick (once a second), cancelled and paid back (a part fitted or taken off at home with the note and new price, Cancel, sold with the text, thrown away at home within a second and at the menu, a weapon a win lost not swept, the same build kept, a build changed another way swept with the note), a template applied, a part fitted in a heist (insured there, cancelled at home after the win), lost with another build (the price back), the briefing (nothing comes), the screen (the mark in PRI and on the locker item's top-right cell only, insured line and Cancel, paid back and said, Insure, a click insures, a free weapon's line, the note after a change, 22 parts insured fits 720p, the Locker tab and the market's Weapons tab lines, redrawn when it comes, documented MenuUI parameters), Duke (0.45.1: tier 2 20% and still 10 min, paid so; tier 3 still 20% and back in 5 min; seconds); Houston (0.53.0): the lists (free weapons in neither, uninsured dearest first not by name or order owned, insured by name), Insure all (nothing to insure, not in a heist, short of money: nothing and the total, one payment, every weapon, said, logged, saved, the build kept), one insured alone written at once, his menu (none insured, the uninsured named with "and N more", Insure all with the total, 5 buttons dearest first, the room's own lines, a button insures with the hint, the insured named, a weapon on its way back, Insure all from the menu, all insured: no buttons, not in another room, the armory off) |
| `wear_tests.lua` | 119 | 0.47.0: rounds to 50% per class (rifles 2,500, pistols, akimbo pistols and snipers 3,500, LMGs 1,500, the minigun 1,000, others 2,500), the jam chance (none at 50% and above, 1 in 20 at 25%, 1 in 10 at 0%, clamped) and its text, a missing or broken condition is 100%, a free weapon always 100%; wearing (nothing at the menu or in the safehouse, 100 rifle rounds 2%, the first shot writes the file and the next 30 s wait, a shot the game did not fire, the free Chimano, a gun not yours, an akimbo second gun wears its pair; on the weapon at the menu after a win and after loading, the heist's memory emptied; quit in a heist; failed and insured: back at the condition lost; the next day goes on from the wear written); the file (wear by uid clamped, nonsense dropped; captured and returning weapons keep it; on disk; a flush with nothing new; Apply not final keeps a weapon to come, final drops it); jams (never at 50% or above, the roll below, the automatic fire stops, the hint names the key even right after another, written at once; may not start shooting, another gun may; the trigger clicks once and the hint, the game's own check still runs; an akimbo second gun stops the pair; not twice; none at home or the next day; the 2 s between hints); Clear Jam (starts, not twice, half a second, 1 s clears and it shoots, a fine gun is said, switching weapons or reloading stops it and says so at once); the lookups cached per uid (none per shot); the game's fire result passed on; repair (none needed when new, 10% of the built price at 50%, 20% at 0%, not in a heist, not without the money, paid and 100%, not a free weapon, no such weapon, the armory off: no repair and no wear); a gun at 0% sells for half; the screen (no bar at 100%, the bar in PRI as long as the condition, not on the free Chimano, on the locker item's first cell only, the condition line and Repair button, fits 720p, a click repairs, then no button, a free weapon's view has neither, documented MenuUI parameters); Rust (0.50.0): the worn list (worst first, then by name, free and full ones out, condition and price), Repair all (not in a heist, short of money: nothing and the total, one payment, every weapon 100%, said and logged, armory off), his menu (nothing worn: said, no buttons; the worn line, 5 named and "and N more"; Repair all with the total; 5 weapon buttons worst first; the room's own lines; a weapon's button repairs it with the hint; Repair all from the menu; not in another room; the armory off) |
| `lasting_tests.lua` | 57 | 0.48.0: a new save full and not hurt; standing at the end the parts are kept (a black leg, the body's spill, logged) and saved; the menu shows them (no owner), the summary; the next heist starts with them (black stays black, the game's health is their sum); back from custody in the heist a fresh body, ended standing so full again; ended in custody: every part 0, the head 1 HP, logged, the next heist so; ended bleeding out unhurt: the same; a black head at the end counts as down; in a heist the file is marked (written); a heist left: down (written), logged; the next day of a heist goes on; a saved black head starts at 1 HP; a skill's black part (Frenzy) and the carried damage both; the safehouse (shows the damage, not marked, its end saves nothing, the screen never overwrites a live body); Dallas's menu (Heal everything at $15,000, what is hurt, not in another room, healed: paid, every part and your character full, the hint, written; not hurt: no button, said; not enough money; not in a heist); the file (clamped, nonsense full, nothing: full; its name, own save or old style); off: nothing; the menu's Health tab (marked hurt, the figure, the button under it, the line, fits 720p, no health window at home, a click heals, paid, said, then not hurt and no button, documented MenuUI parameters) |
| `skins_tests.lua` | 83 | 0.49.0: what you own (the AMCAR's skins by name, one row each: the unlockable and an unlocked colour too, not a colour you lack; your best copy, a StatBoost first, a better one wins; legendary and locked marked; the Chimano's; labels; no Steam inventory: only what the game unlocked); a plain skin (worn, the copy's fields, the game's slot wears it, not locked, the price unchanged; again, not owned, not a weapon, no such weapon: no; any number of guns; a fitted part stays; a colour: its index and the default pattern; removed, again: no; logged); legendary (no room: nothing changes, said; its own parts, said, yours next to it, free in the price and the sale, locked against a part, a build and a fit, locked in the game's slot; a plain skin over it: the weapon's own parts; removed: own parts, unlocked; an unlocked legendary takes parts, removed it keeps them; its own parts free in the sale even if the game sells them); at home only (a heist: no change, no sweep; the armory off); in your hands (the same: not made again; a skin or colour: made again wearing it, the build key; removed: made again bare); a skin sold (no Steam inventory or all owned: nothing; sold: off at the menu with the weapon's own parts, logged; colours and unlockables stay; a colour no longer unlocked, a DLC not owned: off); the files (insured: comes back with its skin; the file keeps the skins of returns and captured, only true is a StatBoost); Sydney (her button, not in another room, the screen: your weapons, hands first, the side windows empty, its skins, a click, on it, fits 720p, Remove, none owned: said, Back, pages and back, fits 720p, Close, the inventory screen as before; the armory off: no button) |
| `lobby_tests.lua` | 76 | 0.46.0: the lobby key (the game's key gets _pdti, logged, not twice; a new lobby marked PDTI not vanilla; the search, the friends' list and an invite PDTI only; another mod's later key suffixed again before each of the four; Epic too; a non-key left alone; no Epic class; hooks_net.lua installs once; mod.txt's three hooks; the receive hook), the host (hello to everyone, a PDTI player known and answered, the same version unsaid, resent every 2 s to who has not answered, kept at 14 s, removed at 15 s with the game's kick after the lobby's chat line, logged, once; no clock while loading, not verified or not in, then 15 s, a drop-in; the clock again after loading; a player who left forgotten, the next one in the slot checked afresh, also between two looks, a hello from the new one; another version said once to you only, kept; no answer to "I know you"; an odd sender; an empty hello), a client (hello to the host, the host's answer keeps you, other players ignored, the host's hello answered; a silent host: kept at 14 s, hello every 2 s, left at 15 s in the lobby with the dialog, logged, once, no more hellos, another host afresh; in a heist a warning once, no leaving, no more hellos; still loading; the host not verified), no checks (offline, no SuperBLT networking logged once, networking that cannot send, no session), the timer (started by a join and by entering a lobby, the game's returns passed on, once, every second while there is a session, stopped without, a failed look logged, no DelayedCalls) |
| `silent_killer_tests.lua` | 71 | Momentum (HP limb, HE dozer and turret; not a body hit, a standard round or a cop), Second Wind ace (a melee kill fills the HP magazine; not standard, not without the kill), Optical Illusions (cloaker crits, the medic blocked only for a crit kill), The Professional (4.5 s, +20% only while stunned), Low Blow (the more hurt arm or leg, not black, not a body hit, body parts off; the medic from behind: within 10 m, not civilians, not from the front, 4 s), High Value Target (78 cm, fire within 2 s of a sure crit), Unseen Strike (dropped rounds, storing up to 20, damage clears, the box, R8), ammo off and restoration-mod |
| `barrier_tests.lua` | 42 | Surefire (10 per AP headshot, cap 50 / 60, fade 3 / 4 s, cooldown 10 / 9 s, not HP, standard or civilians, penetrator counts), Body Expertise (3 / 9, only in vanilla's automatic scope, cap alone), the soak (before armour, after the game's own reductions, the rest goes on, used up without cooldown), the health window line, ammo off and restoration-mod |
| `ghost_skills_tests.lua` | 43 | Cleaner (the case 2x2 / 2x1, deployables off, running with a body at 70%, walking 50%, other bags), ECM Specialist (stack 2, deployables off, a stack split when the skill is gone), Inner Pockets (2x3 / 6 kg, big while the skills are unknown, the third row and a regrown case moved, nothing overlaps), Sneaky Bastard (0 / 5 / 10% by speed, no cap above it, broken speed readings, the ace at run speed and above, the concealment dodge off, the menu stats, weight off), restoration-mod |
| `brawler_tests.lua` | 43 | Frenzy (black limbs at 1 HP, the game's health is the sum, no suspension, the spill, first aid kit and doctor bag, Combat Doctor sees them, black again after a hit and after custody; the ace: the body, the head holds the rest, 75% of body hits, headshots whole, down and revive; the health cap and the ace's reduction off), Berserker (+10% per black part to +50%, the head not counted, bullets and turrets with the ace, not others' hits, with Frenzy, the low-health scaling off), body parts off and restoration-mod |
| `perks_tests.lua` | 149 | Jacket (the charge x1.5 never past full, a kill heals the most hurt non-black part by 15% only at tier 3, not a hit, not another player's kill, nothing when all are full), Dallas (a doctor bag placed gives the revive back once, two revives at tier 3, nothing without the pick), Sangres (a first aid kit gets you up, a doctor bag does not, it heals like a kit once, the kit's time halved at tier 3, only with the medical rig), Rust (one more use from the rig only, the refill key: both guns, uses left on the item, full ammunition takes nothing, an empty bag is gone, the placed bag's uses), Houston (half and all of the rig's weight hidden from concealment, a given weight untouched, only with the general rig), Clover (2x2 and 2x4 slots, loot bags only and first, the view model, another backpack moves the bags, no room refuses), Joy (hacks 75%, a later multiplier keeps it, not twice, not drills or saws, the keycard once per heist), the safehouse room bonuses: the table (two rooms per piece, no room twice), picking (tier 1 refused with why, another piece's room, not made yet, no bonus refits the items), a saved choice that cannot count now, room tiers (the saved tier counts before the safehouse loads, never lowered, the game's set_room_tier remembered, a safehouse with no data not asked), each rig and backpack bonus (sizes, speed, weight, slowdown, focus; the game's definitions untouched), Bonnie's chances and rolls, Scarface's sell-now, the vault, John Wick's and Jiro's plates, Sydney's regeneration and Jimmy's half damage (light armour only, once per break); 0.45.0: Duke's insurance (30%/10 min below tier 2; 0.45.1: 20%/10 min at 2, 20%/5 min at 3; his room's lines; it replaces the not-made check) |
| `yakuza_ehi_tests.lua` | 49 | Yakuza (no bonus with nothing black or at low health alone, a quarter per black limb, the body not counted, card 9 at 2 limbs, a doctor bag takes it away, suspended black counts, Frenzy, other categories untouched, body parts off and restoration-mod), EHI (registered on BuffsInit, the definitions and icons, barrier gauge and its cooldown, Doctor's orders set again on a new buff, the longest Painkillers suspension, overheal amount updated, Momentum and Ignite, timers left to EHI, removed when over, throttle, no EHI bar; EHI's Yakuza and Berserker with the reworked values and their fallbacks) |
| `deployables_new_tests.lua` | 33 | a trip mine from the inventory as a shaped charge on a safe, the new deployables: items with a placement function and a price, offered in the menu only when the game has them; trip mine, ECM and spy camera checked on the wall, the throwable case like a bag, the sentry guns with the game's slot and unit (normal 1, suppressed 2), the armor kit without a spot; a client's sentry taken out when the host places it; no sentry ammo cost; a picked-up sentry back into the inventory, refused with no room; another mod's turret left to the game |

3786 checks in total. These are code-level tests, not substitutes for in-game testing on a
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
