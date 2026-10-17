extends "res://tests/test_case.gd"
## Golden values come from tools/seed_hash_reference.py (an independent Python implementation).
## mix32(1) and string_hash("a") also match published murmur3 / FNV-1a reference values.
## DO NOT change these numbers to make a test pass: they are what keeps saved worlds stable.

const SeedHashScript := preload("res://src/core/seed_hash.gd")
const SeedRngScript := preload("res://src/core/seed_rng.gd")


func test_multiply_32_never_overflows_and_wraps_correctly() -> void:
	assert_eq(SeedHashScript.multiply_32(0xFFFFFFFF, 0xFFFFFFFF), 1, "(2^32-1)^2 mod 2^32 = 1")
	assert_eq(SeedHashScript.multiply_32(0x80000000, 2), 0)
	assert_eq(SeedHashScript.multiply_32(123456789, 987654321), 4227814277, "123456789*987654321 mod 2^32")
	assert_eq(SeedHashScript.multiply_32(0, 0xFFFFFFFF), 0)


func test_mix32_golden_values() -> void:
	assert_eq(SeedHashScript.mix32(0), 0)
	assert_eq(SeedHashScript.mix32(1), 1364076727)
	assert_eq(SeedHashScript.mix32(0xFFFFFFFF), 2180083513)


func test_mix32_ignores_bits_above_32() -> void:
	assert_eq(SeedHashScript.mix32(0x100000001), SeedHashScript.mix32(1))


func test_combine_golden_values_and_order_matters() -> void:
	assert_eq(SeedHashScript.combine(1, 2), 1087478223)
	assert_eq(SeedHashScript.combine(2, 1), 396144453)


func test_string_hash_golden_values() -> void:
	assert_eq(SeedHashScript.string_hash(""), 2166136261)
	assert_eq(SeedHashScript.string_hash("a"), 3826002220)
	assert_eq(SeedHashScript.string_hash("planet"), 2224108531)


func test_rng_golden_sequence() -> void:
	var rng = SeedRngScript.new(12345)
	assert_eq(rng.next_u32(), 2343202583)
	assert_eq(rng.next_u32(), 3817749554)
	assert_eq(rng.next_u32(), 2273380766)
	assert_eq(rng.next_u32(), 1355978862)


func test_seed_chain_golden_value() -> void:
	var chain: int = SeedHashScript.combine(SeedHashScript.combine(SeedHashScript.combine(42, SeedHashScript.string_hash("earth")), SeedHashScript.string_hash("poi")), 7)
	assert_eq(chain, 1319536956)
	assert_eq(SeedHashScript.derive(SeedHashScript.derive(42, "earth"), "poi", 7), chain)


func test_same_seed_gives_same_sequence_every_time() -> void:
	for attempt in 100:
		var first_run = SeedRngScript.new(777)
		var second_run = SeedRngScript.new(777)
		for step in 10:
			assert_eq(first_run.next_u32(), second_run.next_u32())


func test_float_and_range_helpers_stay_in_bounds() -> void:
	var rng = SeedRngScript.new(99)
	for step in 1000:
		var unit_float: float = rng.next_float()
		assert_true(unit_float >= 0.0 and unit_float < 1.0, "float in [0,1)")
		var dice: int = rng.next_int_in_range(1, 6)
		assert_true(dice >= 1 and dice <= 6, "int in [1,6]")
