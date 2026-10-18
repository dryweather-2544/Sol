"""Independent Python mirror of src/core/seed_hash.gd.

Used only to produce/cross-check golden values for tests/unit/seed_hash_test.gd.
If the GDScript and this file ever disagree, one of them has a bug; the golden
values in the test file are the contract.
"""
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
        h ^= byte
        h = (h * 0x01000193) & M
    return h


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


if __name__ == "__main__":
    print("mix32(0)", mix32(0))
    print("mix32(1)", mix32(1))
    print("mix32(0xFFFFFFFF)", mix32(0xFFFFFFFF))
    print("combine(1,2)", combine(1, 2))
    print("combine(2,1)", combine(2, 1))
    print("string_hash('')", string_hash(""))
    print("string_hash('a')", string_hash("a"))
    print("string_hash('planet')", string_hash("planet"))
    r = Rng(12345)
    print("rng(12345)", [r.next_u32() for _ in range(4)])
    chain = combine(combine(combine(42, string_hash("earth")), string_hash("poi")), 7)
    print("chain", chain)
