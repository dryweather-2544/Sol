class_name HullSilhouette
extends RefCounted
## Half-width of a hull seen from above, one value per slice along z (ship-local metres). Lets ShipHullCollision follow a hull
## that is not a straight box, so nobody bumps into an invisible wall beside a narrow part.

var front_z := 0.0
var slice_length := 0.5
var half_widths := PackedFloat32Array()


func half_width_at(z: float) -> float:
	if half_widths.is_empty():
		return 0.0
	return half_widths[clampi(int((z - front_z) / slice_length), 0, half_widths.size() - 1)]


## Builds it from points in ship-local space: per slice, the 95th percentile of |x| among points between low_y and high_y (so thin
## antennas and masts do not widen the wall), widened by one neighbouring slice each way and by `margin`.
static func from_points(points: PackedVector3Array, first_z: float, last_z: float, low_y: float, high_y: float, slice: float = 0.5, margin: float = 0.05) -> HullSilhouette:
	var silhouette := HullSilhouette.new()
	silhouette.front_z = first_z
	silhouette.slice_length = slice
	var slice_count := maxi(1, ceili((last_z - first_z) / slice))
	var per_slice: Array = []
	per_slice.resize(slice_count)
	for index in slice_count:
		per_slice[index] = [] # plain Arrays: a PackedFloat32Array stored in an Array would be copied on every access
	for point in points:
		if point.y < low_y or point.y > high_y:
			continue
		var index := int((point.z - first_z) / slice)
		if index >= 0 and index < slice_count:
			(per_slice[index] as Array).append(absf(point.x))
	var raw := PackedFloat32Array()
	raw.resize(slice_count)
	for index in slice_count:
		var values: Array = per_slice[index]
		values.sort()
		raw[index] = values[int(values.size() * 0.95)] if values.size() > 0 else 0.0
	silhouette.half_widths.resize(slice_count)
	for index in slice_count:
		var widest := raw[index]
		if index > 0:
			widest = maxf(widest, raw[index - 1])
		if index < slice_count - 1:
			widest = maxf(widest, raw[index + 1])
		silhouette.half_widths[index] = widest + margin
	return silhouette
