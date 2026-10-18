class_name SeedHash
extends RefCounted
## Stable 32-bit hashing and random numbers for procedural content.
##
## Everything here is masked to 32 bits after every multiply, so results never depend on how
## the engine handles 64-bit overflow (multiply_32 avoids overflow entirely), and never depend on Godot's own hash() or randf() (which
## may change between versions and would silently change saved worlds). The expected outputs
## are pinned in tests/unit/seed_hash_test.gd and mirrored in tools/seed_hash_reference.py.

const MASK_32 := 0xFFFFFFFF


## (first_value * second_value) mod 2^32, without ever exceeding 63 bits.
## A plain 32-bit by 32-bit multiply can reach 2^64 and overflow Godot's signed 64-bit int,
## so the first value is split into two 16-bit halves (each partial product stays below 2^48).
static func multiply_32(first_value: int, second_value: int) -> int:
	var low_half := first_value & 0xFFFF
	var high_half := (first_value >> 16) & 0xFFFF
	return (low_half * second_value + (((high_half * second_value) & 0xFFFF) << 16)) & MASK_32


## Murmur3 finalizer: spreads every input bit across the whole 32-bit result.
static func mix32(value: int) -> int:
	var hashed := value & MASK_32
	hashed ^= hashed >> 16
	hashed = multiply_32(hashed, 0x85EBCA6B)
	hashed ^= hashed >> 13
	hashed = multiply_32(hashed, 0xC2B2AE35)
	hashed ^= hashed >> 16
	return hashed


## Order-dependent combination: combine(a, b) != combine(b, a).
static func combine(first_value: int, second_value: int) -> int:
	return mix32(((mix32(first_value) ^ (second_value & MASK_32)) + 0x9E3779B9) & MASK_32)


## FNV-1a over the UTF-8 bytes of text. Used to turn names (planet ids, "poi") into numbers.
static func string_hash(text: String) -> int:
	var hashed := 0x811C9DC5
	for byte in text.to_utf8_buffer():
		hashed ^= byte
		hashed = multiply_32(hashed, 0x01000193)
	return hashed


## Child seed for a named thing: planet_seed = derive(world_seed, planet_id).
## Exactly combine(parent_seed, string_hash(label)) - no hidden extra steps.
static func derive(parent_seed: int, label: String) -> int:
	return combine(parent_seed, string_hash(label))


## Child seed for the Nth thing of a kind: poi_seed = derive_indexed(planet_seed, "poi", i).
## Exactly combine(derive(parent_seed, label), index).
## Kept separate from derive() on purpose: a derive() that always folded in an index (default 0)
## made derive(derive(a, x), y, i) differ from the documented chain by a stray combine(.., 0).
static func derive_indexed(parent_seed: int, label: String, index: int) -> int:
	return combine(derive(parent_seed, label), index)
