class_name ChunkKey
extends RefCounted
## A terrain chunk id packed into one int: cube face (0..5), quadtree level, and the chunk's
## column/row on that face at that level. Level 0 = whole face; each level halves the edge.

const FACE_SHIFT := 55
const LEVEL_SHIFT := 50
const COLUMN_SHIFT := 25
const COORD_MASK := 0x1FFFFFF


static func make(face: int, level: int, column: int, row: int) -> int:
	return (face << FACE_SHIFT) | (level << LEVEL_SHIFT) | (column << COLUMN_SHIFT) | row


static func face_of(key: int) -> int:
	return (key >> FACE_SHIFT) & 7


static func level_of(key: int) -> int:
	return (key >> LEVEL_SHIFT) & 31


static func column_of(key: int) -> int:
	return (key >> COLUMN_SHIFT) & COORD_MASK


static func row_of(key: int) -> int:
	return key & COORD_MASK


static func parent_of(key: int) -> int:
	return make(face_of(key), level_of(key) - 1, column_of(key) >> 1, row_of(key) >> 1)


static func child_of(key: int, child_column: int, child_row: int) -> int:
	return make(face_of(key), level_of(key) + 1, column_of(key) * 2 + child_column, row_of(key) * 2 + child_row)


## True when ancestor_key's area contains descendant_key's (and they are different keys).
static func is_ancestor(ancestor_key: int, descendant_key: int) -> bool:
	var level_difference := level_of(descendant_key) - level_of(ancestor_key)
	if level_difference <= 0 or face_of(ancestor_key) != face_of(descendant_key):
		return false
	return (column_of(descendant_key) >> level_difference) == column_of(ancestor_key) and (row_of(descendant_key) >> level_difference) == row_of(ancestor_key)
