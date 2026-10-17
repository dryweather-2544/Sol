class_name FlightEnvironment
extends RefCounted
## What the world does to a ship this tick. Empty space for now; M1 adds planet gravity,
## atmosphere and terrain queries.

var gravity := Vector3.ZERO
