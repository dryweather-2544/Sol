class_name MusicDirector
extends Node
## Sol's adaptive music. Owned by AudioService (no autoload). Each frame it reads the game's real state (title menu,
## flight regime, frame, seat/inside/outside, enemy targets, hull, suit) into a snapshot, decides the music context
## and plays tracks from that context's pool in data/music/soundtrack.json (see Soundtrack).
##
## Behaviour:
## - A context change must hold for rules.dwell_s before it counts (menu, combat and a discovery count at once), so
##   altitude or regime flicker never restarts anything.
## - A playing piece carries on when the new context "keeps" the old one (deep space -> approach, atmosphere -> landed,
##   surface -> inside the ship ...); otherwise it fades out and the new context starts after its first gap.
## - Pieces finish naturally. Between pieces there is silence (gap_s), and a gap may end in more silence (start_chance).
## - Two music voices at most, crossfaded; the same track is never started while it is still sounding, and the last
##   rules.recent_history tracks are avoided while anything else in the pool can play.
## - Arriving at a planetary body for the first time this session plays the arrival cue once (event: WorldRuntime.frame_changed).
## - Strange finds (DiscoveryLog.poi_discovered: wreck, beacon, anomaly) start a one-piece "discovery" moment, with a cooldown.
## - Combat starts when an alive enemy target is within its engage range or hits the player; it holds rules.combat_hold_s
##   after the last sign of a fight, then fades into silence before normal music returns.
## The title page runs while the tree is paused, so this node always processes; the pause page only ducks the music.

signal context_changed(old_context: String, new_context: String)
signal track_started(track_id: String, context_name: String)
signal track_finished(track_id: String)

const BUS := &"Music"
const MENU := "menu"
const DEEP_SPACE := "deep_space"
const APPROACH := "approach"
const ATMOSPHERE := "atmosphere"
const ASCENT := "ascent"
const SURFACE := "surface"
const INTERIOR := "interior"
const DISCOVERY := "discovery"
const DANGER := "danger"
const COMBAT := "combat"
const ARRIVAL := "arrival"
## Contexts that are taken at once instead of waiting for dwell_s.
const IMMEDIATE := [MENU, COMBAT, DISCOVERY]
## Climb rate (m/s, smoothed) that flips the atmosphere context between descent and ascent.
const ASCENT_RATE := 40.0
const CLIMB_SMOOTHING_SECONDS := 1.5
## POI types that count as a strange find for the discovery moment (deposits and outposts do not).
const STRANGE_POI_TYPES := [PoiDefinition.Type.WRECK, PoiDefinition.Type.BEACON, PoiDefinition.Type.ANOMALY]
const DISCOVERY_TIMEOUT_SECONDS := 240.0
const GROUND_ENGAGE_RANGE := GroundEnemy.AGGRO_RANGE * 1.2
const SHIP_ENGAGE_RANGE := EnemyDirector.SHIP_ALERT_RANGE
const LOW_HULL := 0.25
const CRITICAL_OXYGEN := 0.10


class Voice extends RefCounted:
	var player := AudioStreamPlayer.new()
	var track_id := ""
	var context_name := ""
	var started_at := 0.0
	var offset := 0.0
	var length := 0.0
	var loop := false
	var gain := 0.0
	var target := 0.0
	var rate := 1.0
	var ending := false

	func is_active() -> bool:
		return track_id != ""

	func elapsed(clock: float) -> float:
		return clock - started_at + offset

	func clear() -> void:
		if player.is_inside_tree():
			player.stop()
		track_id = ""
		context_name = ""
		gain = 0.0
		target = 0.0
		ending = false


var soundtrack: Soundtrack
var session: GameSession
var ship: Ship
var menu: PauseMenu
var runtime: WorldRuntime
var rng := RandomNumberGenerator.new()
## The committed context ("" before the first frame).
var context := ""
var _pending := ""
var _pending_seconds := 0.0
var _clock := 0.0
var _voices: Array[Voice] = []
var _cue := Voice.new()
var _recent: Array[String] = []
var _next_start_at := INF
var _first_piece := true
var _combat_until := -INF
var _discovery_active := false
var _discovery_started := 0.0
var _discovery_ready_at := 0.0
var _arrived := {}
var _pending_arrival := false
var _ascending := false
var _climb_rate := 0.0
var _previous_altitude := INF
var _previous_hull := -1.0
var _previous_health := -1.0
var _pause_db := 0.0
var _context_db := 0.0
var _body_id: StringName = &""


func _init(music: Soundtrack = null) -> void:
	soundtrack = music if music != null else Soundtrack.load_default()
	rng.randomize()
	for index in 2:
		_voices.append(Voice.new())


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_ensure_bus()
	for voice: Voice in _all_voices():
		voice.player.bus = BUS
		voice.player.process_mode = Node.PROCESS_MODE_ALWAYS
		add_child(voice.player)
	if session != null:
		session.discovery_log.poi_discovered.connect(on_poi_discovered)
	if runtime != null:
		runtime.frame_changed.connect(on_frame_changed)
	resync_from_state()


func _process(delta: float) -> void:
	if session == null or ship == null:
		return
	step(delta, snapshot())


## The game state the music reacts to, read from the real systems (tests build these dictionaries by hand).
func snapshot() -> Dictionary:
	var title := false
	var paused := get_tree().paused if is_inside_tree() else false
	if menu != null and menu.visible:
		title = menu.page == PauseMenu.Page.TITLE or (menu.page == PauseMenu.Page.SETTINGS and context == MENU)
	var engaged := false
	var threat := false
	var player_position := session.player_world_position()
	for target in session.enemy_targets:
		if not target.is_alive():
			continue
		threat = true
		var engage_range := SHIP_ENGAGE_RANGE if target is ShipCombatant else GROUND_ENGAGE_RANGE
		if target.combat_position().distance_to(player_position) < engage_range:
			engaged = true
	var hull := ship.state.hull
	var health := session.suit.health
	# Being hit while enemies are about is a fight even beyond the engage range (a sniper, the ambush raider).
	if threat and ((_previous_hull >= 0.0 and hull < _previous_hull - 0.0001) or (_previous_health >= 0.0 and health < _previous_health - 0.0001)):
		engaged = true
	_previous_hull = hull
	_previous_health = health
	var frame: StringName = runtime.active_frame if runtime != null else &""
	var on_planet_frame := runtime != null and frame != StarSystem.SYSTEM_FRAME and runtime.system.bodies.has(frame) and not (runtime.system.bodies[frame] as BodyDef).is_star
	return {
		"menu_title": title,
		"paused": paused and not title,
		"mode": session.mode,
		"regime": ship.state.regime,
		"altitude": ship.state.altitude_above_ground,
		"planet_frame": on_planet_frame,
		"body": frame if on_planet_frame else &"",
		"engaged": engaged,
		"threat": threat,
		"low_hull": hull < LOW_HULL,
		"oxygen_critical": session.mode == GameSession.Mode.OUTSIDE and session.suit.oxygen <= CRITICAL_OXYGEN,
	}


## One tick of the director: decide the context, start/stop/fade pieces. Deterministic given the snapshot and rng.
func step(delta: float, state: Dictionary) -> void:
	_clock += delta
	_body_id = state.get("body", &"")
	_update_climb(delta, state)
	if state.get("engaged", false):
		_combat_until = _clock + float(soundtrack.rule("combat_hold_s", 10.0))
	if _discovery_active and (_clock - _discovery_started > DISCOVERY_TIMEOUT_SECONDS or _clock < _combat_until):
		_discovery_active = false
	var desired := classify(state)
	if not state.get("paused", false):
		_consider(desired, delta)
	_update_voices(delta)
	_update_arrival_cue()
	_maybe_start_piece()
	_apply_levels(delta, state.get("paused", false))


## The context the snapshot asks for, before dwell. Pure apart from the director's combat/discovery/ascent memory.
func classify(state: Dictionary) -> String:
	if state.get("menu_title", false):
		return MENU
	if _clock < _combat_until:
		return COMBAT
	if state.get("threat", false) or state.get("low_hull", false) or state.get("oxygen_critical", false):
		return DANGER
	if _discovery_active:
		return DISCOVERY
	var mode: int = state.get("mode", GameSession.Mode.SEATED)
	if mode == GameSession.Mode.INSIDE or mode == GameSession.Mode.SITTING:
		return INTERIOR
	if mode == GameSession.Mode.OUTSIDE:
		return SURFACE
	var regime: int = state.get("regime", FlightRegime.SPACE)
	if regime == FlightRegime.LANDED or regime == FlightRegime.NEAR_GROUND:
		return SURFACE
	if regime == FlightRegime.ENTERING or regime == FlightRegime.ATMOSPHERE:
		return ASCENT if _ascending else ATMOSPHERE
	if state.get("planet_frame", false):
		return APPROACH
	return DEEP_SPACE


## Ascent vs descent in the atmosphere: sticky, flipped only by a clear climb or dive. Coming up from the ground is an
## ascent; coming down from space is a descent.
func _update_climb(delta: float, state: Dictionary) -> void:
	var altitude: float = state.get("altitude", INF)
	var regime: int = state.get("regime", FlightRegime.SPACE)
	if is_finite(altitude) and is_finite(_previous_altitude) and delta > 0.0:
		var rate := (altitude - _previous_altitude) / delta
		_climb_rate = lerpf(_climb_rate, rate, clampf(delta / CLIMB_SMOOTHING_SECONDS, 0.0, 1.0))
	else:
		_climb_rate = 0.0
	_previous_altitude = altitude
	if regime == FlightRegime.LANDED or regime == FlightRegime.NEAR_GROUND:
		_ascending = true
	elif regime == FlightRegime.SPACE:
		_ascending = false
	elif _climb_rate > ASCENT_RATE:
		_ascending = true
	elif _climb_rate < -ASCENT_RATE:
		_ascending = false


func _consider(desired: String, delta: float) -> void:
	if desired == context:
		_pending = ""
		_pending_seconds = 0.0
		return
	# Leaving the menu or a fight is immediate too: the fight already waited combat_hold_s.
	var immediate := desired in IMMEDIATE or context in ["", MENU, COMBAT]
	if desired != _pending:
		_pending = desired
		_pending_seconds = 0.0
	else:
		_pending_seconds += delta
	if immediate or _pending_seconds >= float(soundtrack.rule("dwell_s", 6.0)):
		_commit(desired)


func _commit(new_context: String) -> void:
	var old_context := context
	context = new_context
	_pending = ""
	_pending_seconds = 0.0
	var data := soundtrack.context(new_context)
	var main := _main_voice()
	var kept := main != null and soundtrack.keeps(new_context, main.context_name)
	if main != null and not kept:
		var fade := float(data.get("fade_in_s", 3.0)) if new_context == COMBAT else float(soundtrack.context(old_context).get("fade_out_s", 4.0))
		_fade_out(main, fade)
		main = null
	if _cue.is_active() and new_context in [COMBAT, DANGER, MENU]:
		_fade_out(_cue, float(data.get("fade_in_s", 2.0)))
	if kept:
		main.context_name = new_context
	elif main == null:
		var gap: Array = soundtrack.rule("after_combat_gap_s", [15.0, 40.0]) if old_context == COMBAT and new_context != DANGER else data.get("first_gap_s", [0.0, 0.0])
		_next_start_at = _clock + _range(gap)
		_first_piece = true
	context_changed.emit(old_context, new_context)


func _update_voices(delta: float) -> void:
	for voice: Voice in _all_voices():
		if not voice.is_active():
			continue
		voice.gain = move_toward(voice.gain, voice.target, voice.rate * delta)
		if voice.ending and voice.gain <= 0.0001:
			_finish(voice)
			continue
		if voice.length <= 0.0:
			continue
		var elapsed := voice.elapsed(_clock)
		if voice.loop:
			var max_loops := int(soundtrack.rule("max_loops", 2))
			if not voice.ending and elapsed >= voice.length * max_loops - float(soundtrack.context(context).get("fade_out_s", 6.0)):
				_fade_out(voice, float(soundtrack.context(context).get("fade_out_s", 6.0)))
		elif elapsed >= voice.length:
			_finish(voice)


func _finish(voice: Voice) -> void:
	var finished_id := voice.track_id
	var was_main := not voice.ending and voice != _cue
	var was_cue := voice == _cue
	var ended_context := voice.context_name
	var interrupted := voice.ending
	voice.clear()
	track_finished.emit(finished_id)
	if was_cue:
		if interrupted:
			return # cut short by a fight or the menu: that context has already scheduled its own music
		_next_start_at = _clock + _range(soundtrack.cues.get("arrival", {}).get("then_gap_s", [6.0, 15.0]))
		_first_piece = false
		return
	if ended_context == DISCOVERY and _discovery_active:
		_discovery_active = false
	if was_main or _main_voice() == null and _next_start_at == INF:
		_next_start_at = _clock + _range(soundtrack.context(context).get("gap_s", [30.0, 90.0]))
		_first_piece = false


func _update_arrival_cue() -> void:
	if not _pending_arrival:
		return
	if context in [MENU, COMBAT, DANGER, ""]:
		_pending_arrival = false
		return
	var cue_data: Dictionary = soundtrack.cues.get("arrival", {})
	var main := _main_voice()
	if main != null:
		_fade_out(main, float(cue_data.get("duck_fade_s", 3.0)))
		return
	if _loudest_gain() > 0.15:
		return # wait for the outgoing piece to fade before the cue, so two pieces are never loud together
	_pending_arrival = false
	var track_id := String(cue_data.get("track", ""))
	if track_id == "" or not soundtrack.is_playable(track_id) or _is_sounding(track_id):
		return
	_start(_cue, track_id, ARRIVAL, 0.0, 1.5)
	_next_start_at = INF


func _maybe_start_piece() -> void:
	if context == "" or _clock < _next_start_at or _main_voice() != null or _cue.is_active() or _pending_arrival:
		return
	var data := soundtrack.context(context)
	if data.is_empty():
		_next_start_at = INF
		return
	if context == DISCOVERY and not _first_piece:
		return # one piece per discovery moment
	var chance := float(data.get("start_chance", 1.0))
	if rng.randf() > chance:
		_next_start_at = _clock + _range(data.get("gap_s", [30.0, 90.0]))
		_first_piece = false
		return
	var exclude: Array = []
	for voice: Voice in _all_voices():
		if voice.is_active():
			exclude.append(voice.track_id)
	var choice := {}
	if _first_piece and data.has("first") and not (String(data["first"]) in exclude) and soundtrack.is_playable(String(data["first"])) and not (String(data["first"]) in _recent):
		choice = {"track": String(data["first"])}
	else:
		choice = soundtrack.pick(context, _recent, exclude, rng, _body_id)
	if choice.is_empty():
		_next_start_at = _clock + _range(data.get("gap_s", [30.0, 90.0]))
		return
	var voice := _free_voice()
	_start(voice, String(choice["track"]), context, float(choice.get("start_s", 0.0)), float(data.get("fade_in_s", 4.0)))
	_next_start_at = INF
	_first_piece = false


func _start(voice: Voice, track_id: String, context_name: String, offset: float, fade_in: float) -> void:
	var music := soundtrack.stream(track_id)
	if music == null:
		return
	voice.track_id = track_id
	voice.context_name = context_name
	voice.length = music.get_length()
	voice.offset = clampf(offset, 0.0, maxf(voice.length - 1.0, 0.0))
	voice.loop = soundtrack.is_loop(track_id)
	voice.started_at = _clock
	voice.gain = 0.0 if fade_in > 0.0 else 1.0
	voice.target = 1.0
	voice.rate = 1.0 / maxf(fade_in, 0.01)
	voice.ending = false
	voice.player.stream = music
	voice.player.volume_db = -80.0
	if voice.player.is_inside_tree():
		voice.player.play(voice.offset)
	_recent.erase(track_id)
	_recent.append(track_id)
	while _recent.size() > int(soundtrack.rule("recent_history", 6)):
		_recent.pop_front()
	track_started.emit(track_id, context_name)


func _fade_out(voice: Voice, seconds: float) -> void:
	if not voice.is_active():
		return
	var rate := 1.0 / maxf(seconds, 0.01)
	if voice.ending:
		voice.rate = maxf(voice.rate, rate)
		return
	voice.ending = true
	voice.target = 0.0
	voice.rate = rate


## A voice for a new piece: an idle one, else the quieter fading one is cut (never more than two pieces at once).
func _free_voice() -> Voice:
	for voice: Voice in _voices:
		if not voice.is_active():
			return voice
	var quietest := _voices[0]
	for voice: Voice in _voices:
		if voice.gain < quietest.gain:
			quietest = voice
	_finish(quietest)
	return quietest


func _apply_levels(delta: float, paused: bool) -> void:
	_pause_db = move_toward(_pause_db, float(soundtrack.rule("pause_duck_db", -10.0)) if paused else 0.0, 20.0 * delta)
	var context_target := float(soundtrack.context(context).get("gain_db", 0.0))
	_context_db = move_toward(_context_db, context_target, 3.0 * delta)
	for voice: Voice in _all_voices():
		if not voice.is_active():
			continue
		var level := soundtrack.track_db(voice.track_id) + _context_db + _pause_db + linear_to_db(maxf(voice.gain, 0.0001))
		voice.player.volume_db = maxf(level, -80.0)


func _all_voices() -> Array[Voice]:
	var all: Array[Voice] = _voices.duplicate()
	all.append(_cue)
	return all


## The piece that belongs to the current context (not fading out, not the arrival cue), or null.
func _main_voice() -> Voice:
	for voice: Voice in _voices:
		if voice.is_active() and not voice.ending:
			return voice
	return null


func _loudest_gain() -> float:
	var loudest := 0.0
	for voice: Voice in _voices:
		if voice.is_active():
			loudest = maxf(loudest, voice.gain)
	return loudest


func _is_sounding(track_id: String) -> bool:
	for voice: Voice in _all_voices():
		if voice.is_active() and voice.track_id == track_id:
			return true
	return false


func _range(bounds: Array) -> float:
	if bounds.size() < 2:
		return float(bounds[0]) if bounds.size() == 1 else 0.0
	return rng.randf_range(float(bounds[0]), float(bounds[1]))


## WorldRuntime.frame_changed: the first arrival at each planetary body this session plays the arrival cue once.
func on_frame_changed(_old_frame: StringName, new_frame: StringName) -> void:
	if runtime == null or new_frame == StarSystem.SYSTEM_FRAME or not runtime.system.bodies.has(new_frame):
		return
	if (runtime.system.bodies[new_frame] as BodyDef).is_star:
		return
	note_arrival(new_frame)


## True when this is a genuinely new body (the cue is then queued). Landing again or re-entering the same world is not.
func note_arrival(body_id: StringName) -> bool:
	if _arrived.has(body_id):
		return false
	_arrived[body_id] = true
	_pending_arrival = true
	return true


## DiscoveryLog.poi_discovered: a strange find starts a one-piece discovery moment (after the existing sting).
func on_poi_discovered(instance: PoiInstance) -> void:
	note_discovery(instance.type)


func note_discovery(poi_type: int) -> bool:
	if not (poi_type in STRANGE_POI_TYPES) or _clock < _discovery_ready_at or context in [MENU, COMBAT, DANGER]:
		return false
	_discovery_active = true
	_discovery_started = _clock
	_discovery_ready_at = _clock + float(soundtrack.rule("discovery_cooldown_s", 360.0))
	return true


## After a save is loaded: forget fight and discovery memory, count the current world as visited. Music keeps playing.
func resync_from_state() -> void:
	_combat_until = -INF
	_discovery_active = false
	_pending_arrival = false
	_previous_hull = -1.0
	_previous_health = -1.0
	_previous_altitude = INF
	if runtime != null and runtime.active_frame != StarSystem.SYSTEM_FRAME:
		_arrived[runtime.active_frame] = true
	if ship != null:
		_ascending = ship.state.regime == FlightRegime.LANDED or ship.state.regime == FlightRegime.NEAR_GROUND


## Track ids sounding now (for tests and the debug overlay).
func playing_tracks() -> Array[String]:
	var ids: Array[String] = []
	for voice: Voice in _all_voices():
		if voice.is_active():
			ids.append(voice.track_id)
	return ids


func current_track() -> String:
	var main := _main_voice()
	return main.track_id if main != null else (_cue.track_id if _cue.is_active() else "")


func seconds_until_next_piece() -> float:
	return _next_start_at - _clock


func voice_gains() -> Array[float]:
	var gains: Array[float] = []
	for voice: Voice in _all_voices():
		if voice.is_active():
			gains.append(voice.gain)
	return gains


func _exit_tree() -> void:
	for voice: Voice in _all_voices():
		voice.clear()


static func _ensure_bus() -> void:
	if AudioServer.get_bus_index(BUS) == -1:
		AudioServer.add_bus()
		var index := AudioServer.bus_count - 1
		AudioServer.set_bus_name(index, BUS)
		AudioServer.set_bus_send(index, "Master")
