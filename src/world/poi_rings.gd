class_name PoiRings
extends RefCounted
## Distance rings with hysteresis (enter closer than the first number, leave beyond the second),
## scaled up from Rodina's 10 km / 3.5 km / 100 m (PRC-05): so a POI at the edge of a ring does not
## flicker in and out as the player jitters across the line.

enum Ring { NONE, PROXY, CONTENT, DETAIL }

const PROXY_ENTER := 12000.0
const PROXY_EXIT := 15000.0
const CONTENT_ENTER := 4000.0
const CONTENT_EXIT := 6000.0
const DETAIL_ENTER := 1500.0
const DETAIL_EXIT := 2500.0


## The ring a POI should be in, given its distance and the ring it was in last time.
static func update_ring(distance_metres: float, previous: int) -> int:
	var ring: int = previous
	# Move inward as far as the distance allows...
	if ring < Ring.PROXY and distance_metres < PROXY_ENTER:
		ring = Ring.PROXY
	if ring < Ring.CONTENT and distance_metres < CONTENT_ENTER:
		ring = Ring.CONTENT
	if ring < Ring.DETAIL and distance_metres < DETAIL_ENTER:
		ring = Ring.DETAIL
	# ...and outward only past the (larger) exit distance.
	if ring >= Ring.DETAIL and distance_metres > DETAIL_EXIT:
		ring = Ring.CONTENT
	if ring >= Ring.CONTENT and distance_metres > CONTENT_EXIT:
		ring = Ring.PROXY
	if ring >= Ring.PROXY and distance_metres > PROXY_EXIT:
		ring = Ring.NONE
	return ring
