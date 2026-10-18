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


func test_derive_is_exactly_combine_of_parent_and_label_hash() -> void:
	var planet_seed: int = SeedHashScript.derive(42, "earth")
	assert_eq(planet_seed, SeedHashScript.combine(42, SeedHashScript.string_hash("earth")), "derive must add no hidden steps")
	assert_eq(planet_seed, 2408887855, "golden: derive(42, \"earth\")")


func test_seed_chain_golden_value() -> void:
	# world 42 -> planet "earth" -> 7th "poi". This is the chain written in docs/ARCHITECTURE.md.
	var chain_written_out: int = SeedHashScript.combine(SeedHashScript.combine(SeedHashScript.combine(42, SeedHashScript.string_hash("earth")), SeedHashScript.string_hash("poi")), 7)
	assert_eq(chain_written_out, 1319536956, "chain written out with combine/string_hash")
	var chain_via_helpers: int = SeedHashScript.derive_indexed(SeedHashScript.derive(42, "earth"), "poi", 7)
	assert_eq(chain_via_helpers, 1319536956, "chain built with derive/derive_indexed")
	assert_eq(chain_via_helpers, chain_written_out, "helpers must equal the written-out chain")


func test_indexed_derivation_depends_on_index_and_label() -> void:
	var planet_seed: int = SeedHashScript.derive(42, "earth")
	assert_true(SeedHashScript.derive_indexed(planet_seed, "poi", 0) != SeedHashScript.derive_indexed(planet_seed, "poi", 1), "index changes the seed")
	assert_true(SeedHashScript.derive_indexed(planet_seed, "poi", 3) != SeedHashScript.derive_indexed(planet_seed, "loot", 3), "label changes the seed")
	assert_eq(SeedHashScript.derive_indexed(planet_seed, "poi", 0), SeedHashScript.combine(SeedHashScript.derive(planet_seed, "poi"), 0), "index 0 is a real step, not 'no index'")


func test_regression_stray_index_zero_step_is_not_the_chain() -> void:
	# The original bug: derive() always folded in index 0, so the old derive(derive(42,"earth"),"poi",7)
	# was combine(combine(combine(combine(42,h_earth),0),h_poi),7) = 1190027475, NOT the chain.
	var with_stray_zero_step: int = SeedHashScript.combine(SeedHashScript.combine(SeedHashScript.combine(SeedHashScript.combine(42, SeedHashScript.string_hash("earth")), 0), SeedHashScript.string_hash("poi")), 7)
	assert_eq(with_stray_zero_step, 1190027475, "golden for the stray-step variant (documents the old bug)")
	assert_true(SeedHashScript.derive_indexed(SeedHashScript.derive(42, "earth"), "poi", 7) != with_stray_zero_step, "new helpers must not reintroduce the stray step")


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
