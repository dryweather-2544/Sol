extends "res://tests/test_case.gd"
## Checks assumptions the architecture depends on (docs/ARCHITECTURE.md section 0).


func test_float_is_64_bit() -> void:
	# A 32-bit float near 6,000,000 can only step in 0.5 m increments, so this would be
	# off by up to 0.5. A 64-bit float keeps it to ~1e-10.
	var far_value: float = 6000000.0
	var recovered_millimeter: float = far_value + 0.001 - far_value
	assert_near(recovered_millimeter, 0.001, 1e-6, "GDScript float should be 64-bit")


func test_vector3_is_32_bit_in_this_build() -> void:
	# Documents why WorldPos exists. If this fails, the build is double-precision and the
	# architecture's precision section should be revisited.
	var far_vector := Vector3(6000000.0, 0.0, 0.0) + Vector3(0.001, 0.0, 0.0)
	assert_true(absf(far_vector.x - 6000000.001) > 1e-4, "Vector3 should lose the millimetre at 6,000 km (standard build)")


func test_int_holds_values_above_32_bits() -> void:
	var above_32_bits: int = 0xFFFFFFFF << 8
	assert_eq(above_32_bits, 1099511627520, "ints are 64-bit (needed for the masked 32-bit hash math)")
