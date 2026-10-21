# Ship Scale Audit — Rodina's Large Interior / Small Exterior

**Status:** Source-based audit and proposed direction; no gameplay code changed by this note.
**Baseline reviewed:** Sol `n13-graphics-port`, commit `8d4abe2de48bd9372c8f7074094f546c8f60b93c`.
**Reference:** The recovered Rodina 1.6.2 Lua scripts and the existing `research/rodina-starfall-reference/03_INTERIORS_AND_AIRLOCKS.md`.

## Finding

The likely key is not simply a bigger ship model. Rodina declares the player ship's exterior model, walkable interior map and boarding/airlock map as separate assets:

- `Scripts/DataGameplay/EGDataShipPlayer.lua`: `EGShipPlayer.Path = "Ship1.ShipOpen.egm"`
- Same file: `EGShipPlayer.InteriorPath = "DefaultMap.egi"`
- Same file: `EGShipPlayer.EntrancePath = "Airlock.egi"`

The existing interior research documents the interior as a separate engine-created `Interior` entity, loaded from the `.egi` map; the player is parented into that interior, and their saved orientation is expressed in interior-local coordinates. The walkway uses the interior root transform. In other words, the original setup is not one walkable room mesh forced to match the exterior hull's mesh bounds.

**What the scripts do not prove:** They do not give us a reliable numeric ratio between the exterior mesh and the interior map. The player's `DefaultMap.egi` is a binary serialization, and the script-only GitHub copy does not include the actual `.egm` ship model or complete map assets. The recovered local installation must be inspected to measure exact extents and compare screenshots. Do not invent a Rodina interior/exterior scale factor from Lua alone.

## What Sol currently does

Relevant files:

- `src/flight/ship_exterior.gd` — code-built visible hull and exterior parts.
- `src/flight/ship_visuals.gd` — interior/exterior visibility and geometry build.
- `src/interior/interior_layout.gd` — authoritative room rectangles, doors, seats, stations and interactions.
- `src/interior/interior_body.gd` — on-foot movement/walkability in ship-local coordinates.
- `src/interior/ship_hull_collision.gd` — exterior hull collision.
- `docs/SHIP_EXTERIOR.md` — exterior design and dimensional checks.

Current authored extents from the code:

- The pressure hull runs approximately `z = -9.25` to `z = +10.86`: about **20.1 m** long, excluding any extra reach from appendages.
- The hull chine reaches about `x = ±3.75`: about **7.5 m** across the pressure hull. Engine pods extend the complete vehicle's total width beyond the hull.
- Sol's layout has cabin, engineering and cargo rooms each **11 m wide** (half-width 5.5 m), and its turret room is **8 m wide**. Cockpit and airlock are narrower transition spaces that fit inside the pressure hull.
- The interior's room chain runs roughly from `z = -7 m` to `z = +10.6 m`: about **17.6 m** long. That is only about **87.5% of the pressure hull's 20.1 m longitudinal span**. The interior is therefore not larger than the hull along its length in the current layout; only the main room widths exceed the hull width.

That means Sol's existing pocket spaces are wider than the visible pressure hull—11 m versus 7.5 m, around 1.47×—but the interior is not currently a wildly larger, independent floor plan. Numerically, its main corridor/room chain is shorter than the exterior hull, not much longer. This is a concrete reason the current implementation will not yet create Rodina's strong 'small outside, much bigger inside' impression.

### The current pocket mechanism

`ShipVisuals._ready()` creates a child node named `Pocket` and sends meshes for designated pocket rooms to it. It does not apply an enlarged transform to that node.

When the camera is inside a pocket room, `set_camera_place()` shows the pocket geometry and hides the hull nodes. The pocket layout and the normal visible interior use the same `InteriorLayout` data and ship-local metre coordinates; `InteriorBody` navigates those same room rectangles. This is a useful first approximation: the player can see a room that extends beyond the small hull without seeing the hull around it.

But it does not by itself create a much larger room. Simply scaling the `Pocket` visual node would misalign the visuals with the walking, door portals, interaction points, crew stations and player coordinates unless those systems use a matching coordinate mapping too.

## Proposed direction

Aim for **a small, compact exterior with a genuinely roomier interior volume**, while preserving a coherent entrance and airlock. Do not just scale the entire ship or its cockpit.

### Phase A — measure Rodina first

On the Mac with the recovered local Rodina installation:

1. Locate the actual `Ship1.ShipOpen.egm`, `DefaultMap.egi` and `Airlock.egi` files that correspond to the extracted 1.6.2 scripts.
2. Inspect the exterior mesh's bounds in a suitable viewer/converter or through a safe asset-inspection tool. Inspect the binary map with the existing research notes as a guide; do not assume its undocumented binary fields are fully understood.
3. Record the outer hull bounds and the walkable interior bounds in the same units if possible. Take matching screenshots from outside, at the hatch, in the corridor, and in the widest rooms.
4. Measure the transition: which parts physically line up (cockpit/entrance/airlock) and where the interior is permitted to exceed the visible shell.

If those assets aren't accessible or cannot be interpreted confidently, record that limit and use measured screenshots as a weaker reference instead of inventing exact numbers.

### Phase B — remodel the interior as an independent space

After measuring Rodina, adjust the Sol interior layout—not merely its rendered mesh—to create the desired size difference.

- Keep the cockpit and the outer airlock/boarding threshold aligned with the visible exterior and ramp.
- Expand the pocket rooms and, if needed, add length or a wider interior corridor after the cockpit threshold. Keep doors between rooms continuous and centred.
- Make the room rectangles the authoritative source for walking/collision. Update all linked portals, wall positions, floor/ceiling slabs, interact points, crew station coordinates, gunner/pilot seats and any room-based hazards or navigation that depend on layout coordinates.
- If a separate scale/coordinate transform is used instead of authoring larger room coordinates directly, define it explicitly and use it consistently for both directions: player/world positions to interior positions, and back. The visual mesh must never be on a different map from the walkable logic.
- Do not scale the entire `ShipVisuals` node: that would enlarge the outside model and affect the ramp, landing gear, engines, collision, camera and weapon offsets—the opposite of the goal.
- Preserve current gameplay systems and saved position semantics. Audit save/load before changing the coordinate layout so existing saves do not drop the player into walls or outside rooms.

### Phase C — visibility and seamless-feeling transitions

Sol already toggles between hull-visible and pocket-visible views. Test the exact threshold at the cockpit door and airlock/interior door. Avoid a one-frame flash of the full exterior hull, visual gaps, or a camera snap as the player steps over the room boundary. Outside the ship, the actual exterior should remain small. Inside pocket rooms, the interior wall surfaces should occlude the outside hull consistently.

Also test the ramp from the ground and from inside the airlock, because the airlock is intentionally not a pocket room and is the bridge between the independent spaces.

## Required regression checks

- Walk from cockpit to each expanded room, through every door, and back without getting blocked by layout or wall disagreement.
- Verify standing spots and interaction radii at every panel, seat, and crew station.
- Open/close all doors and operate the airlock/ramp from both sides.
- Check crew movement, room hazards, fire/smoke and station interaction in expanded rooms.
- Verify hull collision and on-foot collision outside the ship; no invisible oversized collision volume should follow the pocket interior.
- Save while inside each room and reload; the player must return to the intended position.
- Confirm the hull, cockpit canopy, ramp, engine pods, landing gear, turret, muzzle points and camera framing are still correct in exterior views.
- Run all existing headless tests and add assertions for layout extents, passable portals, pocket visibility and save/load positions.

## Conclusion

Sol already has a pocket-room visibility trick, but its actual interior layout remains close to the exterior scale. Rodina's recovered scripts prove that the exterior model and interior map are separate assets; they do not, by themselves, prove the exact scale ratio. Measure the recovered local assets first, then make the room layout and all of its gameplay coordinates larger while leaving the exterior hull compact.

Do not copy Rodina's proprietary model or map assets into Sol unless redistribution rights are confirmed. The port should reproduce the behaviour and measured proportions in Sol's own implementation.
