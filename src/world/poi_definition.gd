class_name PoiDefinition
extends RefCounted
## The kinds of point of interest and their rules. Placeholder-visual types for M5.
## WRECK, BEACON and OUTPOST are the large sites planned per lattice cell. PROBE, DEPOSIT and ANOMALY are small
## "minor" sites with no marker beam: the scanner (PoiScanner) is how they are found. They are appended to the enum,
## so the numbers of the original three never change.

enum Type { WRECK, BEACON, OUTPOST, PROBE, DEPOSIT, ANOMALY }

## Only the large types take part in the per-cell type roll (changing this would move every POI on every world).
const TYPE_WEIGHTS := {Type.WRECK: 5, Type.BEACON: 3, Type.OUTPOST: 2}
const MINOR_TYPE_WEIGHTS := {Type.PROBE: 3, Type.DEPOSIT: 4, Type.ANOMALY: 2}
## How close (metres) a person on foot must get to discover it (scaled from Rodina's 100 m, PRC-05).
const DISCOVER_RADIUS := 120.0
## Visible light beam height by type (0 = none: wrecks and minor sites must be found by scanning, flying or walking over them).
const BEAM_HEIGHT := {Type.WRECK: 0.0, Type.BEACON: 600.0, Type.OUTPOST: 300.0, Type.PROBE: 0.0, Type.DEPOSIT: 0.0, Type.ANOMALY: 0.0}
const BEAM_COLOR := {Type.WRECK: Color(1.0, 0.5, 0.2), Type.BEACON: Color(0.3, 0.8, 1.0), Type.OUTPOST: Color(0.4, 1.0, 0.5),
	Type.PROBE: Color(0.6, 0.8, 1.0), Type.DEPOSIT: Color(0.9, 0.7, 0.3), Type.ANOMALY: Color(0.8, 0.5, 1.0)}
const TYPE_NAMES := {Type.WRECK: "Wreck", Type.BEACON: "Beacon", Type.OUTPOST: "Outpost",
	Type.PROBE: "Research Probe", Type.DEPOSIT: "Mineral Deposit", Type.ANOMALY: "Anomaly"}
## What the scanner can tell about an undiscovered site from far away: only a class of signal.
const SIGNAL_NAMES := {Type.WRECK: "Metallic debris", Type.BEACON: "Transmission", Type.OUTPOST: "Powered structure",
	Type.PROBE: "Faint telemetry", Type.DEPOSIT: "Dense mineral reading", Type.ANOMALY: "Unclassified energy"}
## The prompt shown next to the interactable part of a site, and the start of the message when it pays out.
const ACTION_PROMPTS := {Type.WRECK: "F: open crate", Type.BEACON: "F: open crate", Type.OUTPOST: "F: open crate",
	Type.PROBE: "F: download probe data", Type.DEPOSIT: "F: survey the deposit", Type.ANOMALY: "F: record the anomaly"}
const RESULT_LABELS := {Type.WRECK: "Found", Type.BEACON: "Found", Type.OUTPOST: "Found",
	Type.PROBE: "Probe data recovered", Type.DEPOSIT: "Deposit surveyed", Type.ANOMALY: "Anomaly recorded"}

const PROBE_FINDINGS := [
	"Its sensor log ends mid-sweep: a survey of this region's magnetic field, never transmitted.",
	"The probe's last entry is a descent profile. Its parachute never opened.",
	"A drift-corrected atmosphere sample, sealed and still readable.",
	"Telemetry for a long-period orbit survey. The relay it was meant to reach no longer exists.",
]
const DEPOSIT_FINDINGS := [
	"Surface survey: dense iron-nickel ore under a thin crust.",
	"Core sample shows layered silicates with a rich metallic seam.",
	"Reflectivity and density readings suggest a shallow, workable lode.",
	"Mixed ore body; the metal fraction is high enough to be worth cutting.",
]
const ANOMALY_FINDINGS := [
	"The ground here holds a regular lattice no natural process should make.",
	"Instruments register a standing field that does not decay. The source is not visible.",
	"Crystal growth in a perfect ring, and the rock beneath it is warmer than the air.",
	"The readings pulse with a period of exactly 11 seconds and no known cause.",
]


static func pick_type(roll: float) -> int:
	var total := 0
	for weight in TYPE_WEIGHTS.values():
		total += weight
	var target := roll * total
	var running := 0.0
	for type in TYPE_WEIGHTS:
		running += TYPE_WEIGHTS[type]
		if target < running:
			return type
	return Type.WRECK


static func pick_minor_type(roll: float) -> int:
	var total := 0
	for weight in MINOR_TYPE_WEIGHTS.values():
		total += weight
	var target := roll * total
	var running := 0.0
	for type in MINOR_TYPE_WEIGHTS:
		running += MINOR_TYPE_WEIGHTS[type]
		if target < running:
			return type
	return Type.DEPOSIT


static func is_minor(type: int) -> bool:
	return MINOR_TYPE_WEIGHTS.has(type)


## The line of research text for a site, fixed by its seed (so the log can show it again after loading). "" for large sites.
static func finding_text(type: int, poi_seed: int) -> String:
	var pool: Array
	match type:
		Type.PROBE: pool = PROBE_FINDINGS
		Type.DEPOSIT: pool = DEPOSIT_FINDINGS
		Type.ANOMALY: pool = ANOMALY_FINDINGS
		_: return ""
	return pool[(poi_seed & 0x7FFFFFFF) % pool.size()]
