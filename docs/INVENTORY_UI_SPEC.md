# Tactical Inventory UI specification

## Goal
A pre-heist inventory screen and an in-heist quick-access view. The UI must render
`PDTI.GetInventoryViewModel()` and invoke public inventory functions; it must never
edit the saved state tables directly.

## Main inventory screen
- Left column: character silhouette, backpack slot, tactical-rig slot.
- Center: selected container grid with square cells and item footprints.
- Right column: item details, weight, category and action controls.
- Bottom strip: pockets / rig / backpack tabs and total carried weight.
- Top row: player name, loadout name and save/close actions.

## Grid behavior
- Zero-based coordinates map to cells.
- Item rectangles use registered `w`/`h`; rotated items swap dimensions.
- Invalid drop targets show a rejected state and do not call `MoveItem`.
- Valid drops call `PDTI.MoveItem(from, instance_id, to, x, y, rotated)`.
- UI reads are snapshots; all writes go through the public API.

## Quick access
- Pockets and rig are the only quick-access containers in the first iteration.
- `PDTI.GetQuickAccess()` supplies the entries.
- A quick-access action must eventually route through a registered item-use handler.
  Do not consume an item merely because the UI button was clicked until the gameplay
  effect has succeeded.

## Magazine presentation
- Show each weapon's magazine supply as individual magazine entries, with current rounds
  and capacity, using `PDTI.Ammo.GetSupplySummary()`.
- These entries are informational. The magazines themselves are ordinary inventory items:
  pick one up and click a cell to move it, exactly like any other item.
- Moving a magazine between the rig, the pockets and the backpack changes what a reload
  can use immediately; there is no second list that has to be kept in step.

## Input and lifecycle
- The screen should pause only when the game mode permits it.
- Mouse/controller navigation should be supported.
- Closing the screen must not alter inventory state.
- UI should refresh its view model after each successful inventory API call.
- Multiplayer UI should be host-authoritative; clients request moves rather than
  mutating shared state.

## Implementation order
1. Build and render static container grids.
2. Add item icons, labels and hover details.
3. Add drag/drop and rotation.
4. Add equipment selection and validation.
5. Add quick-access controls.
6. Add ISSR magazine readout.
7. Add controller navigation and localization.


## 0.3.0 interaction-controller contract

The UI controller is implemented in `lua/ui_model.lua` and is renderer-agnostic.
It exposes:

- `PDTI.GetUIState()` — current visibility, selected container/item, revision and view model.
- `PDTI.SetUIVisible(bool)` — update visibility state.
- `PDTI.SelectContainer(name)` / `PDTI.SelectItem(instance_id)`.
- `PDTI.RequestMove(...)` — validated move request.
- `PDTI.RequestRotate(container, instance_id)`.
- `PDTI.RequestEquip(kind, equipment_id)`.
- `PDTI.RequestAutoArrange(container, allow_rotation)`.
- `PDTI.RefreshUI()` — increment the revision and return a fresh model.

`PDTI.GetOccupancyMap(container)` returns a row-major cell matrix containing `false`
for empty cells or the occupying item instance ID. The actual game GUI is not included
in 0.3.0; this module is the stable command/data boundary for that renderer.

## Loose ammunition and deployables (0.6.0)

The side column of the screen carries three blocks, in this order:

1. **Supplies** - one button per registered item, click to add one unit to the selected
   container. Items the mod manages (magazines, loose ammunition, loot bags) have no
   button: they come from the game.
2. **Magazines** - one line per magazine supply with the rounds of every magazine that is
   to hand (rig and pockets) and the number of loose rounds of that supply.
3. **Deployable** - one button per deployable item, showing how many are to hand (rig and
   pockets) and which one is picked. Clicking a button picks that deployable. The button
   "Use the game's deployable" clears the pick, so the game places deployables again.

While the screen is open the deployable key (G) picks the item that is held as the
deployable. Outside the screen the same key places the picked deployable.

The bottom rows show the weight of every container, the current speed factor, the picked
deployable with its count and the total number of loose rounds.
