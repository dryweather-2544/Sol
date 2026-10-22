# Playing Sol

Run it: open the project in Godot 4.7.2 and press F5, or
`~/Downloads/Godot.app/Contents/MacOS/Godot --path ~/Documents/Sol`.
Press **Esc** any time for the pause menu (save/load/settings). Click the window to capture the mouse again.

## Controls

| Where | Keys |
|---|---|
| Flying | **W/S** thrust forward/back, **A/D** strafe, **Space/C** up/down, **mouse** (or arrow keys) pitch and yaw, **Q/E** roll, **Shift** boost, **X** brake, **right mouse (or Z) + W/S** change gear like Rodina's clutch: hold the clutch (the drive disconnects and you coast), tap **W** to shift up or **S** to shift down, release to commit; a refused shift grinds. **[ ]** still shift directly (DOCK / COMBAT / CRUISE / WARP), **V** cockpit view, **click or Ctrl** fire |
| Walking (inside or outside) | **WASD** move, **Shift** run, **Space** jump (outside; hold in the air for the jetpack), **mouse** look, **click or Ctrl** fire the pistol (outside) |
| Captain's orders | **R** engineer: fix everything (press again to cancel), **G** gunner: man the turret, **P** cycle the reactor's power split (balanced / engines / weapons) |
| Anywhere | **F** use (stand up, sit, door panels, repair panel, open crates), **Tab** inventory, **N** scanner pulse (flying, inside or on foot), **J** exploration log, **T** cycle nav target, **F5/F9** quicksave/quickload, **Esc** menu |

## The loop

1. You start in orbit, 300 km above Aurelia, in CRUISE gear. Point the nose at the planet (mouse), hold **W**.
   The ship flies like Rodina's: it keeps its speed and its spin when you let go (only the air slows a spin), and
   it feels the planet's pull. Enter the air no faster than about 4 km/s nose-down or the hull burns ("STEEP
   REENTRY"). **[ ]** change gear; the HUD shows the gear and its top speed:
   - **PRECISION** - up to 30 m/s (12 m/s up/down): for landing, take-off, hovering and moving around structures.
     Let go and it stops and hovers by itself. Touch down belly-down below about 15 m/s.
   - **COMBAT** - up to 500 m/s, very quick to respond, keeps its momentum when you let go and falls if you do not
     hold it up (Rodina's combat gear). **X** brakes.
   - **CRUISE** - 5 km/s near the ground rising to 10 km/s in the upper air, then faster and faster with distance
     above it (hundreds of km/s a few thousand km out). To leave a planet, point the nose up and hold **W**: about
     20 s to space (with **Space** alone it is three times slower, up/down thrust is only 30% in cruise).
   Your gear choice is kept: if it is not available (an empty tank allows combat at most) it comes back by itself.
   In the air the ship eases its *roll* level (never its pitch); turn that off or down in Settings, "Ship horizon
   levelling".
2. When the HUD says LANDED, press **F** to stand up. Walk to the cabin's rear (the airlock): panels glow green
   next to each door; **F** at a panel toggles the door. Inner door first, step in, close it, then the outer door
   (this also lowers the ramp). Walk down the ramp onto the ground.
3. Explore. Beams of light mark beacons and outposts; wrecks have no beam (fly low). Get within 120 m of a
   point of interest on foot to discover it. Orange crates hold items (**F**).
4. To fly again: walk back up the ramp, close the outer door at its panel, open the inner door, walk to the
   cockpit and sit in the pilot seat (**F** near it). The ship secures itself for takeoff, then lift off with **Space**.
5. The objective line (green, bottom left) tells you what to do next; the story gates open-space travel behind
   a Warp coil from an outpost's guards.

## What to check when you play (please report anything that feels off)

- Is flight controllable? Mouse sensitivity, camera lag, how fast the ship turns/accelerates.
- Does the landing assist help or fight you? Is touchdown forgiving enough?
- Walking speed, jump, jetpack, interior size: right or off?
- Can you finish the whole loop (land, exit, walk, return, sit, take off) without a debug key?
- Do the guard ships/drones at outposts feel fair? (They are not tuned.)
- Anything that looks wrong: floating props, holes in terrain, flicker, wrong lighting.
- Sound: engine/wind/doors/footsteps all exist but nobody has heard them yet.

## The ship (since phase 2)

The ship has six rooms: cockpit, cabin, engineering, turret room, cargo, airlock; every door has a panel (**F**). Two crew live aboard:
Mara (engineer, orange) and Kit (gunner, red). In engineering: the **reactor panel** sets how much power engines / weapons / life support may draw
(heat builds with draw; a hot core trips and restarts by itself once cool, or from the panel), the **extinguisher locker** gives you 6 sprays (**F** in a
burning room), the **engine station** takes spare parts. Damage hurts engines / weapons / reactor / life support separately and can start fires; closed
doors contain fire, low room air drains your suit. The overlay shows power, subsystem health, crew goals and fire alerts.

## The Mayday errand (objectives 4-7)

After you install the Warp coil, a distress call from Selene: fly there and land. A raider ambushes you on arrival (it burns out your engine coupling
and starts a fire in engineering). Land, walk to the beacon ~6 km away, open its crate for an **engine coupling**, install it at the engine station
(**F**), and fly back to orbit above Aurelia. Nobody has played this yet: please report anything unfair or confusing.
