class_name RodinaNoise
extends RefCounted
## Port of the planet noise in Rodina's Shaders/_perlin.h: Ken Perlin's improved noise (his public
## reference permutation table and 16-entry gradient set), seeded by adding the seed to the
## coordinate, plus FractalPerlin (normalised to 0..1), FractalPerlinDerivative (analytic
## derivative, used for domain warps) and SpecialPerlin (derivative-damped octaves).
## Same algorithm and constants; evaluated in 64-bit here instead of HLSL float32.

const PERMUTATIONS := [151,160,137,91,90,15,
	131,13,201,95,96,53,194,233,7,225,140,36,103,30,69,142,8,99,37,240,21,10,23,
	190,6,148,247,120,234,75,0,26,197,62,94,252,219,203,117,35,11,32,57,177,33,
	88,237,149,56,87,174,20,125,136,171,168,68,175,74,165,71,134,139,48,27,166,
	77,146,158,231,83,111,229,122,60,211,133,230,220,105,92,41,55,46,245,40,244,
	102,143,54,65,25,63,161,1,216,80,73,209,76,132,187,208,89,18,169,200,196,
	135,130,116,188,159,86,164,100,109,198,173,186,3,64,52,217,226,250,124,123,
	5,202,38,147,118,126,255,82,85,212,207,206,59,227,47,16,58,17,182,189,28,42,
	223,183,170,213,119,248,152,2,44,154,163,70,221,153,101,155,167,43,172,9,
	129,22,39,253,19,98,108,110,79,113,224,232,178,185,112,104,218,246,97,228,
	251,34,242,193,238,210,144,12,191,179,162,241,81,51,145,235,249,14,239,107,
	49,192,214,31,181,199,106,157,184,84,204,176,115,121,50,45,127,4,150,254,
	138,236,205,93,222,114,67,29,24,72,243,141,128,195,78,66,215,61,156,180]
const GRADIENTS := [
	Vector3(1, 1, 0), Vector3(-1, 1, 0), Vector3(1, -1, 0), Vector3(-1, -1, 0),
	Vector3(1, 0, 1), Vector3(-1, 0, 1), Vector3(1, 0, -1), Vector3(-1, 0, -1),
	Vector3(0, 1, 1), Vector3(0, -1, 1), Vector3(0, 1, -1), Vector3(0, -1, -1),
	Vector3(1, 1, 0), Vector3(0, -1, 1), Vector3(-1, 1, 0), Vector3(0, -1, -1)]

static var _perm := PackedInt32Array(PERMUTATIONS)


static func _p(index: int) -> int:
	return _perm[index & 255]


static func _grad(hash_value: int, x: float, y: float, z: float) -> float:
	var g: Vector3 = GRADIENTS[hash_value & 15]
	return g.x * x + g.y * y + g.z * z


## _perlin.h PerlinNoise: roughly -1..1.
static func perlin(px: float, py: float, pz: float) -> float:
	var fx := floorf(px)
	var fy := floorf(py)
	var fz := floorf(pz)
	var xi := posmod(int(fx), 256)
	var yi := posmod(int(fy), 256)
	var zi := posmod(int(fz), 256)
	var x := px - fx
	var y := py - fy
	var z := pz - fz
	var u := x * x * x * (x * (x * 6.0 - 15.0) + 10.0)
	var v := y * y * y * (y * (y * 6.0 - 15.0) + 10.0)
	var w := z * z * z * (z * (z * 6.0 - 15.0) + 10.0)
	var a := _p(xi) + yi
	var aa := _p(a) + zi
	var ab := _p(a + 1) + zi
	var b := _p(xi + 1) + yi
	var ba := _p(b) + zi
	var bb := _p(b + 1) + zi
	return lerpf(
		lerpf(lerpf(_grad(_p(aa), x, y, z), _grad(_p(ba), x - 1.0, y, z), u),
			lerpf(_grad(_p(ab), x, y - 1.0, z), _grad(_p(bb), x - 1.0, y - 1.0, z), u), v),
		lerpf(lerpf(_grad(_p(aa + 1), x, y, z - 1.0), _grad(_p(ba + 1), x - 1.0, y, z - 1.0), u),
			lerpf(_grad(_p(ab + 1), x, y - 1.0, z - 1.0), _grad(_p(bb + 1), x - 1.0, y - 1.0, z - 1.0), u), v),
		w)


## _perlin.h PerlinAndDerivative: Vector4(d/dx, d/dy, d/dz, value).
static func perlin_and_derivative(px: float, py: float, pz: float) -> Vector4:
	var fx := floorf(px)
	var fy := floorf(py)
	var fz := floorf(pz)
	var xi := posmod(int(fx), 256)
	var yi := posmod(int(fy), 256)
	var zi := posmod(int(fz), 256)
	var x := px - fx
	var y := py - fy
	var z := pz - fz
	var du := x * x * (x * (x * 30.0 - 60.0) + 30.0)
	var dv := y * y * (y * (y * 30.0 - 60.0) + 30.0)
	var dw := z * z * (z * (z * 30.0 - 60.0) + 30.0)
	var u := x * x * x * (x * (x * 6.0 - 15.0) + 10.0)
	var v := y * y * y * (y * (y * 6.0 - 15.0) + 10.0)
	var w := z * z * z * (z * (z * 6.0 - 15.0) + 10.0)
	var a := _grad(_p(_p(_p(xi) + yi) + zi), x, y, z)
	var b := _grad(_p(_p(_p(xi + 1) + yi) + zi), x - 1.0, y, z)
	var c := _grad(_p(_p(_p(xi) + yi + 1) + zi), x, y - 1.0, z)
	var d := _grad(_p(_p(_p(xi + 1) + yi + 1) + zi), x - 1.0, y - 1.0, z)
	var e := _grad(_p(_p(_p(xi) + yi) + zi + 1), x, y, z - 1.0)
	var f := _grad(_p(_p(_p(xi + 1) + yi) + zi + 1), x - 1.0, y, z - 1.0)
	var g := _grad(_p(_p(_p(xi) + yi + 1) + zi + 1), x, y - 1.0, z - 1.0)
	var h := _grad(_p(_p(_p(xi + 1) + yi + 1) + zi + 1), x - 1.0, y - 1.0, z - 1.0)
	var k1 := b - a
	var k2 := c - a
	var k3 := e - a
	var k4 := a - b - c + d
	var k5 := a - c - e + g
	var k6 := a - b - e + f
	var k7 := -a + b + c - d + e - f - g + h
	return Vector4(
		du * (k1 + k4 * v + k6 * w + k7 * v * w),
		dv * (k2 + k4 * u + k5 * w + k7 * w * u),
		dw * (k3 + k5 * v + k6 * u + k7 * u * v),
		a + k1 * u + k2 * v + k3 * w + k4 * u * v + k5 * v * w + k6 * w * u + k7 * u * v * w)


## _perlin.h FractalPerlin, normalised to 0..1 (FindAnalogue(noise, -range, range, 0, 1)).
static func fractal(seed: float, p: Vector3, mult_change: float, octave_base: float, octave_change: float, octaves: int) -> float:
	var frequency := octave_base
	var noise := 0.0
	var range_sum := 0.0
	var mult := 1.0
	for octave in octaves:
		noise += mult * perlin(seed + p.x * frequency, seed + p.y * frequency, seed + p.z * frequency)
		range_sum += mult
		frequency *= octave_change
		mult *= mult_change
	if range_sum <= 0.0:
		return 0.5
	return clampf((noise + range_sum) / (2.0 * range_sum), 0.0, 1.0)


## _perlin.h FractalPerlinDerivative: summed (derivative xyz, value w), not normalised.
static func fractal_derivative(seed: float, p: Vector3, mult_change: float, octave_base: float, octave_change: float, octaves: int) -> Vector4:
	var frequency := octave_base
	var total := Vector4.ZERO
	var mult := 1.0
	for octave in octaves:
		total += mult * perlin_and_derivative(seed + p.x * frequency, seed + p.y * frequency, seed + p.z * frequency)
		frequency *= octave_change
		mult *= mult_change
	return total


## _perlin.h SpecialPerlin: each octave damped by the running derivative (x and z only, as in the
## shipped shader), normalised to 0..1.
static func special(seed: float, p: Vector3, mult_change: float, octave_base: float, octave_change: float, octaves: int) -> float:
	var frequency := octave_base
	var noise := 0.0
	var range_sum := 0.0
	var mult := 1.0
	var dx := 0.0
	var dz := 0.0
	for octave in octaves:
		var nd := perlin_and_derivative(seed + p.x * frequency, seed + p.y * frequency, seed + p.z * frequency)
		dx += nd.x
		dz += nd.z
		noise += mult * nd.w / (1.0 + dx * dx + dz * dz)
		range_sum += mult
		frequency *= octave_change
		mult *= mult_change
	if range_sum <= 0.0:
		return 0.5
	return clampf((noise + range_sum) / (2.0 * range_sum), 0.0, 1.0)
