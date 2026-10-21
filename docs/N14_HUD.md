# N14 compact Rodina HUD

The N13 graphics port changed HUD fonts but still showed the full developer overlay in Rodina style.
`DebugOverlay` now switches to a compact HUD while Rodina style is active and the game is not paused:

- top-centre gear tab (`PRECISION`, `COMBAT SPEED`, `CRUISE SPEED`, `WARP`);
- bottom-centre hull/fuel/speed for seated flight, or O2/jetpack/health outside/interior;
- smaller prompt/objective text;
- source HUD font roles are still applied through `VisualStyle.hud_font`.

The detailed overlay remains for Sol style and paused/debug states. Capture: `/tmp/n14_hud_check/cruise_1s.jpg`.
The N13 engine flame cone plus the owner-requested pixel layer are visible in the same frame.
