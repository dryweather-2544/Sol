extends "res://tests/test_case.gd"
## The rodina style uses Rodina's HUD fonts (Scripts/Render/MenuFonts.lua); the sol style leaves the labels alone.


func test_rodina_hud_fonts_load_with_rodina_sizes_and_colours() -> void:
	VisualStyle.set_active(VisualStyle.RODINA)
	var warning := VisualStyle.hud_font(&"warning")
	assert_true(warning["font"] is Font, "Audiowide loads")
	assert_eq(warning["size"], 24)
	assert_true((warning["color"] as Color).is_equal_approx(Color(1, 0.25, 0.25)), "WarningFont red")
	for role in VisualStyle.RODINA_HUD_FONTS:
		assert_true(VisualStyle.hud_font(role)["font"] is Font, "%s font file is present" % role)
	VisualStyle.set_active(VisualStyle.SOL)
	assert_true(VisualStyle.hud_font(&"warning").is_empty(), "sol: no override")
	VisualStyle.set_active(VisualStyle.RODINA)
