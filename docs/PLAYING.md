# Playing Sol

Run it: open the project in Godot 4.7.2 and press F5, or
`~/Downloads/Godot.app/Contents/MacOS/Godot --path ~/Documents/Sol`.
Press **Esc** any time for the pause menu (save/load/settings). Click the window to capture the mouse again.

## Controls

| Where | Keys |
|---|---|
| Flying | **W/S** thrust forward/back, **A/D** strafe, **Space/C** up/down, **mouse** (or arrow keys) pitch and yaw, **Q/E** roll, **Shift** boost, **X** brake, **[ ]** gear down/up (DOCK / COMBAT / CRUISE), **V** cockpit view, **click or Ctrl** fire |
| Walking (inside or outside) | **WASD** move, **Shift** run, **Space** jump (outside; hold in the air for the jetpack), **mouse** look, **click or Ctrl** fire the pistol (outside) |
| Anywhere | **F** use (stand up, sit, door panels, repair panel, open crates), **Tab** inventory, **T** cycle nav target, **F5/F9** quicksave/quickload, **Esc** menu |

## The loop

1. You start in orbit, 300 km above Aurelia, in cruise gear. Point the nose at the planet (mouse), hold **W**.
   The ship slows itself near the ground. Below 400 m it eases itself upright; land belly-down, gently
   (touchdown over about 15 m/s damages the hull).
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
