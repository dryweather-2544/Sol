# N14 terrain save migration

`TerrainProfile.generation_revision` records the height-field revision. Aurelia, Cinder and Verdant are
revision 1 because they changed from the legacy generic noise stack to recovered Rodina grammars.

`SaveGame.capture` writes the revision in `world.terrain_revision`. On restore, if the save is older than
the current body revision and the ship was landed or below the new surface, the ship is placed 2.1 m above
the surface along its previous radial direction, velocity/spin are cleared, and `landed` is cleared so the
normal contact resolver can settle it.

This is a **ship position migration**, not a complete world-state migration: POIs/outposts have not been
re-mapped, and the save is still version 11 because the new key is optional. A full POI migration is
required before claiming save compatibility for every surface location.

Test: `tests/unit/save_roundtrip_test.gd::test_old_terrain_revision_reseats_a_landed_ship`. The test uses a
flat patch and accepts a 0.3 m tolerance because the ship's support plane is resolved after restore.
