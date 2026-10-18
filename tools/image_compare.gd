extends SceneTree
## N9 picture metrics (runs headless; only reads PNG files):
##   godot --headless --path . -s res://tools/image_compare.gd -- name=on.png,off.png[,baseline.png] ...
## For each named pair prints one VISUAL line: how different the asset-on picture is from asset-off (the asset is on screen if this is at
## least 2/255), how different asset-off is from a baseline picture if given (the kill switch restores the old look if at most 1/255),
## the share of near-black pixels, the mean luminance, and the number of magenta pixels (a missing texture draws magenta).
## Differences are the mean absolute channel difference in 0..255 over a sampled grid (every 3rd pixel).

const STRIDE := 3


func _initialize() -> void:
	var failures := 0
	for argument in OS.get_cmdline_user_args():
		var name_and_files := argument.split("=", true, 1)
		if name_and_files.size() != 2:
			continue
		var files := name_and_files[1].split(",")
		var on_image := Image.load_from_file(files[0])
		var off_image := Image.load_from_file(files[1]) if files.size() > 1 else null
		var baseline_image := Image.load_from_file(files[2]) if files.size() > 2 else null
		if on_image == null:
			print("VISUAL FAIL %s could not read %s" % [name_and_files[0], files[0]])
			failures += 1
			continue
		var statistics := _statistics(on_image)
		var used_difference := _mean_difference(on_image, off_image) if off_image != null else -1.0
		var reversible_difference := _mean_difference(off_image, baseline_image) if off_image != null and baseline_image != null else -1.0
		var verdicts: Array[String] = []
		if used_difference >= 0.0 and used_difference < 2.0:
			verdicts.append("asset not visible (on vs off differs by only %.2f/255)" % used_difference)
		if reversible_difference > 1.0:
			verdicts.append("switch-off does not restore the baseline (%.2f/255)" % reversible_difference)
		if statistics["dark_share"] > 0.35:
			verdicts.append("%.0f %% of pixels are near-black" % (statistics["dark_share"] * 100.0))
		if statistics["mean_luminance"] < 0.08 or statistics["mean_luminance"] > 0.70:
			verdicts.append("mean luminance %.2f outside 0.08-0.70" % statistics["mean_luminance"])
		if statistics["magenta"] > 0:
			verdicts.append("%d magenta pixels (missing texture?)" % statistics["magenta"])
		if not verdicts.is_empty():
			failures += 1
		print("VISUAL %s %s used_diff=%.2f reversible_diff=%s dark=%.1f%% lum=%.3f magenta=%d%s" % ["PASS" if verdicts.is_empty() else "CHECK", name_and_files[0], used_difference,
			("%.2f" % reversible_difference) if reversible_difference >= 0.0 else "n/a", statistics["dark_share"] * 100.0, statistics["mean_luminance"], statistics["magenta"],
			"" if verdicts.is_empty() else "  <- " + "; ".join(verdicts)])
	print("VISUAL SUMMARY: %d to look at" % failures)
	quit(0)


func _statistics(image: Image) -> Dictionary:
	var sampled := 0
	var dark := 0
	var magenta := 0
	var luminance_total := 0.0
	for y in range(0, image.get_height(), STRIDE):
		for x in range(0, image.get_width(), STRIDE):
			var pixel := image.get_pixel(x, y)
			var luminance := 0.2126 * pixel.r + 0.7152 * pixel.g + 0.0722 * pixel.b
			sampled += 1
			luminance_total += luminance
			if luminance < 2.0 / 255.0:
				dark += 1
			if pixel.r > 0.9 and pixel.b > 0.9 and pixel.g < 0.1:
				magenta += 1
	return {"dark_share": float(dark) / maxf(sampled, 1), "mean_luminance": luminance_total / maxf(sampled, 1), "magenta": magenta}


func _mean_difference(first: Image, second: Image) -> float:
	if first.get_size() != second.get_size():
		return 255.0
	var sampled := 0
	var total := 0.0
	for y in range(0, first.get_height(), STRIDE):
		for x in range(0, first.get_width(), STRIDE):
			var a := first.get_pixel(x, y)
			var b := second.get_pixel(x, y)
			total += (absf(a.r - b.r) + absf(a.g - b.g) + absf(a.b - b.b)) / 3.0
			sampled += 1
	return total / maxf(sampled, 1) * 255.0
