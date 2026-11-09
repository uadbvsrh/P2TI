# PAYDAY 2: Tactical Inventory

Tactical Inventory turns PAYDAY 2's loadout into an extraction-shooter inventory: what you
carry is what you have. Backpacks, rigs and pockets have room and weight limits, and every
magazine, round, medkit and bag of loot takes a place in them.

## Vision

In vanilla PAYDAY 2 a loadout is a list of numbers that refills itself. This mod makes every
heist a supply decision:
- **What do you bring?**
- **Where do you carry it?**
- **What can you afford to lose?**

Ammunition, gear and health become limited and physical, and they cost money. Preparation
matters, and so do mistakes. The goal is the tension of an extraction shooter without losing
PAYDAY's pace: heists stay fast, but running dry, getting hurt and burning through gear all
have consequences.

## Goals

- **A physical inventory.**
  - Grid backpacks, tactical rigs and quick-access pockets.
  - Items have a size and a weight. You arrange them, rotate them and choose where they go.
- **The inventory is the supply.**
  - Magazines and loose rounds are real items. You reload from the magazines you carry, and
    you fill them round by round.
  - Magazine sizes and bullet types (standard, hollow point, armour piercing) change how a
    weapon fights.
- **Gear follows what you carry.**
  - Deployables are items: what you carry is what you can place.
  - Loot bags take up space like everything else.
- **Weight matters.** A heavy loadout is slower. Packing light and packing for every case are
  both real choices.
- **Health per body part.**
  - Wounds land somewhere, and each injured part has its own effect:
    - a hurt arm makes you shoot worse;
    - a hurt leg slows you down;
    - a hit to the head can drop you.
  - A medkit and a doctor bag do not heal the same things.
- **An economy.**
  - Your loadout is bought with your spending cash.
  - What a heist uses up has to be bought again before the next one.
- **Planning in the menu.** You choose what goes into every heist before it starts. The
  heist itself is where you live with that choice.

## Direction

- Loot as items: small valuables you carry, and bags of varying rarity.
- Real effects for medical and utility items.
- Multiplayer synchronisation.
- Visible backpacks and rigs on the player model.
 - **Tunable.** Prices, sizes, weights and effects live in plain tables, so balance changes are one-line edits.
## Requirements and installation

- SuperBLT, plus BeardLib for the inventory screen.
- Extract the `Payday2TacticalInventory` folder into `PAYDAY 2/mods/`.

## More

- [`docs/GUIDE.md`](docs/GUIDE.md) covers every system in detail, the public API, the tests,
  and what changed in each release.
- [`CHANGELOG.md`](CHANGELOG.md) has technical notes per release.
- [`docs/INVENTORY_UI_SPEC.md`](docs/INVENTORY_UI_SPEC.md) is the specification of the inventory screen.
- [Special thanks to guy that created ISSR](https://github.com/mafph/PD2-InsurgencySandstormStyleReloadForNQR/releases/tag/v1.1), i based my magazine system on his mod
- This mod is completely vibe-coded, btw
