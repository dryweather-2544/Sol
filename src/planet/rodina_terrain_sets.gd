class_name RodinaTerrainSets
extends RefCounted
## Rodina's terrain material sets (Scripts/Data/EGEditorData.lua `PlanetTerrains`, selected per world by PlanetTerrainName in
## EGDataPlanets.lua): for each world, the ordered TerrainFeature list that RodinaTerrain.fx composites (first feature takes its
## share of the surface, later ones take what is left). Only the colour and gating fields are kept; the texture tiers are not
## ported. Generated from the Lua by a one-off script; the numbers are exact, not tuned.
##
## Units as authored: height_* in metres above the planet radius (the editor's -10000 and below mean "disabled"); latitude_* and
## normal_* in DEGREES (RodinaTerrain.fx compares radians; the engine converts, which is inferred); height_noise in metres,
## latitude_noise in degrees. features_used = the editor's FeatureMult1..4 (an unused mask channel counts as 1).
## PROPRIETARY Rodina data: keep this file out of any public remote.

## Metres per repeat of the altitude/latitude noise (PerlinMap) per set.
const NOISE_SCALES := {
	1: Vector2(50000.0, 10000000.0), # PerunTerrain
	2: Vector2(50000.0, 10000000.0), # JariloTerrain
	3: Vector2(50000.0, 10000000.0), # VelesTerrain
	4: Vector2(50000.0, 10000000.0), # MorenaTerrain
	5: Vector2(1000.0, 1000000.0), # AsteroidTerrain
}

const SETS := {
	1: [ # PerunTerrain (TerrainProfile.Grammar.PERUN)
		{"name": "MountainSide", "diffuse": Color(0.79901957511902, 0.5914312005043, 0.5914312005043), "blend_ground": 0.62000000476837, "blend_space": 0.61000001430511,
			"height_edge": -10000.0, "height_fade": 0.0, "height_noise": 1000.0, "latitude_edge": 0.0, "latitude_fade": 0.0, "latitude_noise": 0.0,
			"normal_edge": 49.700000762939, "normal_fade": -10.10000038147,
			"features_edge": Vector4(0.0, 0.0, 0.11000000685453, 0.49000000953674), "features_fade": Vector4(0.0, 0.0, 0.030000001192093, -0.050000000745058), "features_used": [false, false, true, true]},
		{"name": "Mountains", "diffuse": Color(0.029411792755127, 0.026850491762161, 0.0076413000933826), "blend_ground": 0.69999998807907, "blend_space": 0.0,
			"height_edge": -10000.0, "height_fade": 0.0, "height_noise": 1000.0, "latitude_edge": 0.0, "latitude_fade": 0.0, "latitude_noise": 0.0,
			"normal_edge": 90.0, "normal_fade": 0.0,
			"features_edge": Vector4(0.0, 0.0, 0.10999999940395, 0.46000000834465), "features_fade": Vector4(0.0, 0.0, 0.029999999329448, -0.050000000745058), "features_used": [false, false, true, true]},
		{"name": "Dunes", "diffuse": Color(9.9999999747524e-07, 7.9545287690053e-07, 0.0), "blend_ground": 0.5, "blend_space": 0.0,
			"height_edge": -10000.0, "height_fade": 0.0, "height_noise": 1000.0, "latitude_edge": 0.0, "latitude_fade": 0.0, "latitude_noise": 0.0,
			"normal_edge": 35.200000762939, "normal_fade": -5.1000003814697,
			"features_edge": Vector4(0.0, 0.0, 0.0, 0.0), "features_fade": Vector4(0.0, 0.0, 0.0, 0.0), "features_used": [false, false, false, false]},
		{"name": "BaseA", "diffuse": Color(0.50748813152313, 0.28917002677917, 0.21318434178829), "blend_ground": 0.0, "blend_space": 0.0,
			"height_edge": -10000.0, "height_fade": 0.0, "height_noise": 1000.0, "latitude_edge": 0.0, "latitude_fade": 0.0, "latitude_noise": 0.0,
			"normal_edge": 90.0, "normal_fade": 0.0,
			"features_edge": Vector4(0.0, 0.18000000715256, 0.0, 0.0), "features_fade": Vector4(0.0, 0.030000001192093, 0.0, 0.0), "features_used": [true, true, false, false]},
		{"name": "Dunes", "diffuse": Color(0.56292152404785, 0.52842235565186, 0.48522564768791), "blend_ground": 0.10000000149012, "blend_space": 0.0,
			"height_edge": -10000.0, "height_fade": 0.0, "height_noise": 1000.0, "latitude_edge": 0.0, "latitude_fade": 0.0, "latitude_noise": 0.0,
			"normal_edge": 90.0, "normal_fade": 0.0,
			"features_edge": Vector4(0.0, 0.0, 0.0, 0.0), "features_fade": Vector4(0.0, 0.0, 0.0, 0.0), "features_used": [false, false, false, false]},
	],
	2: [ # JariloTerrain (TerrainProfile.Grammar.JARILO)
		{"name": "PolarIceCaps", "diffuse": Color(0.89215385913849, 0.89215683937073, 0.89214789867401), "blend_ground": 1.0, "blend_space": 1.0,
			"height_edge": 9500.0, "height_fade": 500.0, "height_noise": 0.0, "latitude_edge": 73.25, "latitude_fade": 0.15000000596046, "latitude_noise": 15.0,
			"normal_edge": 58.275001525879, "normal_fade": 2.0,
			"features_edge": Vector4(0.030000001192093, 0.059999998658895, 0.13000001013279, 0.0), "features_fade": Vector4(0.019999999552965, 0.0049999989569187, 0.025000000372529, 0.0), "features_used": [false, false, true, false]},
		{"name": "Snowcaps", "diffuse": Color(0.72899866104126, 0.72900003194809, 0.72899264097214), "blend_ground": 1.0, "blend_space": 0.75000005960464,
			"height_edge": 21500.0, "height_fade": 500.0, "height_noise": 20000.0, "latitude_edge": 0.0, "latitude_fade": 0.0, "latitude_noise": 0.0,
			"normal_edge": 44.200000762939, "normal_fade": 3.0,
			"features_edge": Vector4(-1.0, 0.20000000298023, -1.0, -1.0), "features_fade": Vector4(0.0, 0.030000001192093, 0.0, 0.0), "features_used": [false, false, false, false]},
		{"name": "Mountains", "diffuse": Color(0.57702648639679, 0.53881227970123, 0.46091583371162), "blend_ground": 0.10000000149012, "blend_space": 0.0,
			"height_edge": -1000000.0, "height_fade": 0.0, "height_noise": 1000.0, "latitude_edge": -1.5707963705063, "latitude_fade": 0.0, "latitude_noise": 0.39269909262657,
			"normal_edge": 30.0, "normal_fade": 5.0,
			"features_edge": Vector4(0.0, 0.0, 0.059999998658895, 0.0), "features_fade": Vector4(0.0, 0.0, 0.0049999998882413, 0.0), "features_used": [false, false, true, false]},
		{"name": "Dunes", "diffuse": Color(0.78833377361298, 0.71734595298767, 0.60640442371368), "blend_ground": 0.5, "blend_space": 0.40000000596046,
			"height_edge": -100000.0, "height_fade": 0.0, "height_noise": 1000.0, "latitude_edge": -1.0, "latitude_fade": 0.0, "latitude_noise": 0.39269909262657,
			"normal_edge": 90.0, "normal_fade": 0.0,
			"features_edge": Vector4(0.0, 0.057499997317791, 0.075000002980232, 0.0), "features_fade": Vector4(0.0, -0.0070000002160668, -0.0099999997764826, 0.0), "features_used": [false, true, true, false]},
		{"name": "BaseB", "diffuse": Color(0.71449190378189, 0.63486605882645, 0.51604717969894), "blend_ground": 0.0, "blend_space": 0.0,
			"height_edge": -10000.0, "height_fade": 0.0, "height_noise": 1000.0, "latitude_edge": -1.0, "latitude_fade": 0.0, "latitude_noise": 0.39269909262657,
			"normal_edge": 25.0, "normal_fade": 6.1500000953674,
			"features_edge": Vector4(0.0, 0.0, 0.0, 0.0), "features_fade": Vector4(0.0, 0.0, 0.0, 0.0), "features_used": [false, false, false, false]},
		{"name": "", "diffuse": Color(9.9999999747524e-07, 9.9999601843592e-07, 9.9998999303352e-07), "blend_ground": 0.30000001192093, "blend_space": 0.0,
			"height_edge": -100000.0, "height_fade": 0.0, "height_noise": 1000.0, "latitude_edge": -1.5707963705063, "latitude_fade": 0.0, "latitude_noise": 0.39269909262657,
			"normal_edge": 90.0, "normal_fade": 0.0,
			"features_edge": Vector4(-0.0099999997764826, -0.0099999997764826, -0.0099999997764826, -0.0099999997764826), "features_fade": Vector4(0.0, 0.0, 0.0, 0.0), "features_used": [false, false, false, false]},
	],
	3: [ # VelesTerrain (TerrainProfile.Grammar.VELES)
		{"name": "Mountains", "diffuse": Color(9.9999374469917e-07, 9.9999999747524e-07, 9.9998999303352e-07), "blend_ground": 0.5, "blend_space": 0.0,
			"height_edge": -10000.0, "height_fade": 0.0, "height_noise": 1000.0, "latitude_edge": 0.0, "latitude_fade": 0.0, "latitude_noise": 0.0,
			"normal_edge": 40.0, "normal_fade": 5.0,
			"features_edge": Vector4(0.0, 0.60000002384186, 0.0, 0.0), "features_fade": Vector4(0.0, 0.050000000745058, 0.0, 0.0), "features_used": [false, true, false, false]},
		{"name": "Mountains", "diffuse": Color(0.89705884456635, 0.88894814252853, 0.87507212162018), "blend_ground": 0.0, "blend_space": 0.0,
			"height_edge": -10000.0, "height_fade": 0.0, "height_noise": 1000.0, "latitude_edge": 0.0, "latitude_fade": 0.0, "latitude_noise": 0.0,
			"normal_edge": 90.000007629395, "normal_fade": 0.0,
			"features_edge": Vector4(0.0, 0.60000002384186, 0.0, 0.0), "features_fade": Vector4(0.0, 0.050000000745058, 0.0, 0.0), "features_used": [false, true, false, false]},
		{"name": "Mountains", "diffuse": Color(-0.059000004082918, -0.039000000804663, -0.075000002980232), "blend_ground": 1.0, "blend_space": 0.0,
			"height_edge": -10000.0, "height_fade": 0.0, "height_noise": 1000.0, "latitude_edge": 0.0, "latitude_fade": 0.0, "latitude_noise": 0.0,
			"normal_edge": 33.700000762939, "normal_fade": -10.0,
			"features_edge": Vector4(0.95999997854233, 0.0, 0.0, 0.0), "features_fade": Vector4(-0.003000000026077, 0.0, 0.0, 0.0), "features_used": [true, false, false, false]},
		{"name": "Mountains", "diffuse": Color(-3.4830350875854, -3.483015537262, -3.4830002784729), "blend_ground": 0.080000005662441, "blend_space": 0.0,
			"height_edge": -10000.0, "height_fade": 0.0, "height_noise": 1000.0, "latitude_edge": 0.0, "latitude_fade": 0.0, "latitude_noise": 0.0,
			"normal_edge": 40.0, "normal_fade": -20.10000038147,
			"features_edge": Vector4(0.0, 0.0, 0.0, 0.0), "features_fade": Vector4(0.0, 0.0, 0.0, 0.0), "features_used": [false, false, false, false]},
		{"name": "Mountains", "diffuse": Color(0.7843137383461, 0.58891373872757, 0.36908879876137), "blend_ground": 0.0, "blend_space": 0.0,
			"height_edge": -10000.0, "height_fade": 0.0, "height_noise": 1000.0, "latitude_edge": 0.0, "latitude_fade": 0.0, "latitude_noise": 0.0,
			"normal_edge": 90.000007629395, "normal_fade": 0.0,
			"features_edge": Vector4(0.0, 0.0, 0.0, 0.0), "features_fade": Vector4(0.0, 0.0, 0.0, 0.0), "features_used": [false, false, false, false]},
	],
	4: [ # MorenaTerrain (TerrainProfile.Grammar.MORENA)
		{"name": "Dunes", "diffuse": Color(1.0, 0.99999690055847, 0.99998998641968), "blend_ground": 0.0, "blend_space": 0.0,
			"height_edge": -10000.0, "height_fade": 0.0, "height_noise": 1000.0, "latitude_edge": 0.0, "latitude_fade": 0.0, "latitude_noise": 0.0,
			"normal_edge": 90.000007629395, "normal_fade": 0.0,
			"features_edge": Vector4(0.0, 0.0, 0.0, 0.050000000745058), "features_fade": Vector4(0.0, 0.0, 0.0, 0.030000001192093), "features_used": [false, false, false, true]},
		{"name": "BigCrackFloor", "diffuse": Color(0.0, 0.45884916186333, 1.2000000476837), "blend_ground": 0.64999997615814, "blend_space": 0.0,
			"height_edge": -10000.0, "height_fade": 0.0, "height_noise": 1000.0, "latitude_edge": 0.0, "latitude_fade": 0.0, "latitude_noise": 0.0,
			"normal_edge": 90.000007629395, "normal_fade": 0.0,
			"features_edge": Vector4(0.0, 0.65000003576279, 0.0, 0.0), "features_fade": Vector4(0.0, 0.030000001192093, 0.0, 0.0), "features_used": [false, true, false, false]},
		{"name": "CliffWall", "diffuse": Color(0.0, 0.4584019780159, 1.2000000476837), "blend_ground": 0.63999998569489, "blend_space": 0.0,
			"height_edge": -10000.0, "height_fade": 0.0, "height_noise": 1000.0, "latitude_edge": 0.0, "latitude_fade": 0.0, "latitude_noise": 0.0,
			"normal_edge": 34.0, "normal_fade": -8.7000007629395,
			"features_edge": Vector4(0.0, 0.0, 0.0, 0.0), "features_fade": Vector4(0.0, 0.0, 0.0, 0.0), "features_used": [false, false, false, false]},
		{"name": "Mountain", "diffuse": Color(0.99998998641968, 0.99999368190765, 1.0), "blend_ground": 0.0, "blend_space": 0.0,
			"height_edge": -10000.0, "height_fade": 0.0, "height_noise": 1000.0, "latitude_edge": 0.0, "latitude_fade": 0.0, "latitude_noise": 0.0,
			"normal_edge": 90.000007629395, "normal_fade": 0.0,
			"features_edge": Vector4(0.0, 0.0, 0.029999999329448, 0.0), "features_fade": Vector4(0.0, 0.0, 0.010000000707805, 0.0), "features_used": [false, false, true, false]},
		{"name": "Snow", "diffuse": Color(0.9180001616478, 1.059025645256, 1.2000000476837), "blend_ground": 0.0, "blend_space": 0.0,
			"height_edge": -10000.0, "height_fade": 0.0, "height_noise": 1000.0, "latitude_edge": 0.0, "latitude_fade": 0.0, "latitude_noise": 0.0,
			"normal_edge": 90.000007629395, "normal_fade": 0.0,
			"features_edge": Vector4(0.0, 0.0, 0.0, 0.0), "features_fade": Vector4(0.0, 0.0, 0.0, 0.0), "features_used": [false, false, false, false]},
	],
	5: [ # AsteroidTerrain (TerrainProfile.Grammar.ASTEROID)
		{"name": "MountainSlope", "diffuse": Color(9.9999999747524e-07, 8.4640242903333e-07, 6.1274511153897e-07), "blend_ground": 0.25, "blend_space": 0.25,
			"height_edge": -10000.0, "height_fade": 0.0, "height_noise": 0.0, "latitude_edge": 0.0, "latitude_fade": 0.0, "latitude_noise": 0.0,
			"normal_edge": 21.400001525879, "normal_fade": 5.7000002861023,
			"features_edge": Vector4(0.0, 0.0, 0.25, 0.83000004291534), "features_fade": Vector4(0.0, 0.0, 0.080000005662441, -0.040000002831221), "features_used": [false, false, true, false]},
		{"name": "MountainFlat", "diffuse": Color(0.27450978755951, 0.23239460587502, 0.16955016553402), "blend_ground": 0.060000002384186, "blend_space": 0.22000001370907,
			"height_edge": -10000.0, "height_fade": 0.0, "height_noise": 0.0, "latitude_edge": 0.0, "latitude_fade": 0.0, "latitude_noise": 0.0,
			"normal_edge": 90.0, "normal_fade": 0.0,
			"features_edge": Vector4(0.0, 0.0, 0.25, 0.0), "features_fade": Vector4(0.0, 0.0, 0.080000005662441, 0.0), "features_used": [false, false, true, false]},
		{"name": "Mountains", "diffuse": Color(0.21300001442432, 0.18926239013672, 0.15384085476398), "blend_ground": 0.5, "blend_space": 0.40000000596046,
			"height_edge": -10000.0, "height_fade": 0.0, "height_noise": 0.0, "latitude_edge": 0.0, "latitude_fade": 0.0, "latitude_noise": 0.0,
			"normal_edge": 90.000007629395, "normal_fade": 0.0,
			"features_edge": Vector4(0.0, 0.0, 0.0, 0.0), "features_fade": Vector4(0.0, 0.0, 0.0, 0.0), "features_used": [false, false, false, false]},
	],
}


static func features_for(grammar: int) -> Array:
	return SETS.get(grammar, [])


static func noise_scales_for(grammar: int) -> Vector2:
	return NOISE_SCALES.get(grammar, Vector2(50000.0, 10000000.0))
