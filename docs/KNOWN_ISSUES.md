# Known issues (Sol)

## Other planets cannot be reached (noted 2026-10-21)
- Flying toward another planet, the ship slows down as it gets near. Cause not investigated yet.
- Reported by the owner; no work done on it. Start by checking planet gravity/drag/atmosphere-speed limits and the
  warp or cruise speed caps that apply near a planet body (and whether they apply to planets other than the one flown from).

## Terrain streaming: small hitches while flying fast (noted 2026-10-21)
- Chunk queue now drains and eviction is gradual, but slight hitching remains.
- The `terrain:` log shows show/hide at about 4-10 ms per pass in steady state; the `frames:` line (added) shows the
  longest frame and the number of frames over 25 ms so the hitch can be tied to a cause (draw calls from ~1,500 shown
  chunks, show/hide, GPU wait or something else).
