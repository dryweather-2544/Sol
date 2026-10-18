"""Recompute every golden number in tests/unit/seed_hash_test.gd with plain big-integer maths
(no split multiply, no GDScript) and fail if the test file does not contain it.

Run:  python3 -I tools/check_seed_goldens.py
This guards against hand-typed or stale golden values. It does NOT execute GDScript; the real
GDScript check is tools/run_tests.sh on a machine with Godot.
"""
import pathlib
import re
import sys

M = 0xFFFFFFFF


def mix32(h):
    h &= M
    h ^= h >> 16
    h = (h * 0x85EBCA6B) & M
    h ^= h >> 13
    h = (h * 0xC2B2AE35) & M
    h ^= h >> 16
    return h


def combine(a, b):
    return mix32(((mix32(a) ^ (b & M)) + 0x9E3779B9) & M)


def string_hash(text):
    h = 0x811C9DC5
    for byte in text.encode("utf-8"):
        h = ((h ^ byte) * 0x01000193) & M
    return h


def derive(parent, label):
    return combine(parent, string_hash(label))


def derive_indexed(parent, label, index):
    return combine(derive(parent, label), index)


class Rng:
    def __init__(self, seed):
        self.state = mix32(seed) or 0x6D2B79F5

    def next_u32(self):
        x = self.state
        x ^= (x << 13) & M
        x ^= x >> 17
        x ^= (x << 5) & M
        self.state = x
        return mix32(x)


rng = Rng(12345)
rng_values = [rng.next_u32() for _ in range(4)]
chain_written_out = combine(combine(combine(42, string_hash("earth")), string_hash("poi")), 7)
stray_zero_step = combine(combine(combine(combine(42, string_hash("earth")), 0), string_hash("poi")), 7)

goldens = {
    "mix32(1)": mix32(1),
    "mix32(0xFFFFFFFF)": mix32(M),
    "combine(1,2)": combine(1, 2),
    "combine(2,1)": combine(2, 1),
    "string_hash('')": string_hash(""),
    "string_hash('a')": string_hash("a"),
    "string_hash('planet')": string_hash("planet"),
    "rng[0]": rng_values[0], "rng[1]": rng_values[1], "rng[2]": rng_values[2], "rng[3]": rng_values[3],
    "derive(42,'earth')": derive(42, "earth"),
    "chain written out": chain_written_out,
    "stray-zero-step variant": stray_zero_step,
    "multiply 123456789*987654321 mod 2^32": (123456789 * 987654321) & M,
}

# Structural facts the tests rely on.
assert derive_indexed(derive(42, "earth"), "poi", 7) == chain_written_out, "helpers must equal the documented chain"
assert stray_zero_step != chain_written_out, "stray-step variant must differ from the chain"
assert mix32(0x100000001) == mix32(1)

test_text = pathlib.Path(__file__).resolve().parent.parent.joinpath("tests/unit/seed_hash_test.gd").read_text()
numbers_in_test = {int(n) for n in re.findall(r"\b\d{4,}\b", test_text)}
bad = False
for name, value in goldens.items():
    present = value in numbers_in_test
    print(f"{'ok     ' if present else 'MISSING'} {name:42s} {value}")
    bad |= not present
# Numbers that appear in the test as INPUTS (seeds, operands, loop bounds), not expected results.
known_inputs = {12345, 123456789, 987654321, 4294967296, 1000}
stale = sorted(n for n in numbers_in_test if n not in set(goldens.values()) and n not in known_inputs)
for n in stale:
    print(f"STALE/UNKNOWN number in test file: {n}")
    bad = True
print("RESULT:", "FAILED" if bad else "all goldens in the test file match an independent recomputation")
sys.exit(1 if bad else 0)
