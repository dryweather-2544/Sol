class_name SeedRng
extends RefCounted
## Small deterministic random number generator (xorshift32 state, mixed output).
## Same seed -> same sequence on every machine and Godot version. Never use randf() for
## world content; make one SeedRng per thing being generated.

const SeedHashScript := preload("res://src/core/seed_hash.gd")

var _state: int


func _init(seed_value: int) -> void:
	_state = SeedHashScript.mix32(seed_value)
	if _state == 0:
		_state = 0x6D2B79F5 # xorshift must never be all zeros


func next_u32() -> int:
	var value := _state
	value ^= (value << 13) & SeedHashScript.MASK_32
	value ^= value >> 17
	value ^= (value << 5) & SeedHashScript.MASK_32
	_state = value
	return SeedHashScript.mix32(value)


## Float in [0, 1).
func next_float() -> float:
	return float(next_u32()) / 4294967296.0


## Integer in [minimum, maximum], both included.
func next_int_in_range(minimum: int, maximum: int) -> int:
	assert(maximum >= minimum, "SeedRng.next_int_in_range: maximum below minimum")
	return minimum + int(next_u32() % (maximum - minimum + 1))
