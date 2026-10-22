class_name Soundtrack
extends RefCounted
## Sol's music as data: res://data/music/soundtrack.json lists the tracks (file, level, loop, licence) and the
## contexts (which tracks may play where, how long the silences are, which contexts let a playing piece carry on).
## No gameplay script names a track; change the soundtrack by editing the JSON. Missing or broken files are
## skipped with one warning each, so a bad entry means silence there, never an error.

const DEFAULT_PATH := "res://data/music/soundtrack.json"

var tracks := {}    # id -> Dictionary
var contexts := {}  # name -> Dictionary
var rules := {}
var cues := {}
var root := "res://assets/sol/audio/mus/"
var load_error := ""
var _streams := {}  # id -> AudioStream
var _missing := {}  # id -> true


static func load_default() -> Soundtrack:
	return from_file(DEFAULT_PATH)


static func from_file(path: String) -> Soundtrack:
	var soundtrack := Soundtrack.new()
	var text := FileAccess.get_file_as_string(path)
	if text == "":
		soundtrack.load_error = "soundtrack file %s is missing or empty" % path
		push_warning(soundtrack.load_error)
		return soundtrack
	soundtrack.load_from_text(text)
	return soundtrack


## Parses the JSON. A broken file leaves an empty soundtrack (music simply stays silent) and sets load_error.
func load_from_text(text: String) -> void:
	var parsed = JSON.parse_string(text)
	if not (parsed is Dictionary):
		load_error = "soundtrack JSON could not be parsed"
		push_warning(load_error)
		return
	tracks = parsed.get("tracks", {})
	contexts = parsed.get("contexts", {})
	rules = parsed.get("rules", {})
	cues = parsed.get("cues", {})
	root = String(parsed.get("root", root))


func rule(name: String, fallback: Variant) -> Variant:
	return rules.get(name, fallback)


func context(name: String) -> Dictionary:
	return contexts.get(name, {})


## Whether a piece that started under `previous` may carry on when `next` takes over.
func keeps(next: String, previous: String) -> bool:
	if next == previous:
		return true
	return previous in context(next).get("keeps", [])


func track_db(track_id: String) -> float:
	return float(tracks.get(track_id, {}).get("db", 0.0))


func is_loop(track_id: String) -> bool:
	return bool(tracks.get(track_id, {}).get("loop", false))


func file_path(track_id: String) -> String:
	if not tracks.has(track_id):
		return ""
	return root + String(tracks[track_id].get("file", ""))


## The stream for a track, or null (unknown id, missing or unimported file). Cached; failures warn once.
func stream(track_id: String) -> AudioStream:
	if _streams.has(track_id):
		return _streams[track_id]
	if _missing.has(track_id):
		return null
	var path := file_path(track_id)
	var loaded: Resource = null
	if path != "" and ResourceLoader.exists(path):
		loaded = ResourceLoader.load(path)
	if not (loaded is AudioStream) or (loaded as AudioStream).get_length() <= 0.0:
		_missing[track_id] = true
		AssetLibrary.warn_once("music:" + track_id, "music track '%s' has no playable file at '%s' (skipped)" % [track_id, path])
		return null
	var music := (loaded as AudioStream).duplicate() as AudioStream
	_set_loop(music, is_loop(track_id))
	_streams[track_id] = music
	return music


## Length in seconds of the file (0 if it cannot be loaded).
func length(track_id: String) -> float:
	var music := stream(track_id)
	return music.get_length() if music != null else 0.0


func is_playable(track_id: String) -> bool:
	return stream(track_id) != null


## Pool entries of a context with their weights for this planet (body_weights multiply them; a body may add tracks).
func weighted_pool(context_name: String, body_id: StringName = &"") -> Array[Dictionary]:
	var context_data := context(context_name)
	var result: Array[Dictionary] = []
	var multipliers: Dictionary = context_data.get("body_weights", {}).get(String(body_id), {})
	var seen := {}
	for entry: Dictionary in context_data.get("pool", []):
		var track_id := String(entry.get("track", ""))
		var weighted := entry.duplicate()
		weighted["weight"] = float(entry.get("weight", 1.0)) * float(multipliers.get(track_id, 1.0))
		result.append(weighted)
		seen[track_id] = true
	for track_id: String in multipliers:
		if not seen.has(track_id) and tracks.has(track_id):
			result.append({"track": track_id, "weight": float(multipliers[track_id])})
	return result


## Weighted random choice from a context's pool. Never `exclude` (the piece playing now). Tracks in `recent`
## (newest last) are avoided while anything else is playable; if everything was played recently, the least recent wins.
func pick(context_name: String, recent: Array, exclude: Array, rng: RandomNumberGenerator, body_id: StringName = &"") -> Dictionary:
	var candidates: Array[Dictionary] = []
	for entry in weighted_pool(context_name, body_id):
		var track_id := String(entry["track"])
		if track_id in exclude or float(entry["weight"]) <= 0.0 or not is_playable(track_id):
			continue
		candidates.append(entry)
	if candidates.is_empty():
		return {}
	var fresh := candidates.filter(func(entry: Dictionary) -> bool: return not (String(entry["track"]) in recent))
	if fresh.is_empty():
		var oldest: Dictionary = candidates[0]
		for entry in candidates:
			if recent.find(String(entry["track"])) < recent.find(String(oldest["track"])):
				oldest = entry
		return oldest
	var total := 0.0
	for entry in fresh:
		total += float(entry["weight"])
	var roll := rng.randf() * total
	for entry in fresh:
		roll -= float(entry["weight"])
		if roll <= 0.0:
			return entry
	return fresh.back()


## Every problem with the data: unknown track ids in pools, keeps naming unknown contexts, missing files.
func validation_errors(check_files: bool = true) -> Array[String]:
	var errors: Array[String] = []
	if load_error != "":
		errors.append(load_error)
	for context_name: String in contexts:
		var context_data: Dictionary = contexts[context_name]
		for entry: Dictionary in context_data.get("pool", []):
			if not tracks.has(String(entry.get("track", ""))):
				errors.append("context %s uses unknown track %s" % [context_name, entry.get("track", "")])
		for kept in context_data.get("keeps", []):
			if not contexts.has(String(kept)):
				errors.append("context %s keeps unknown context %s" % [context_name, kept])
		for body_id in context_data.get("body_weights", {}):
			for track_id in context_data["body_weights"][body_id]:
				if not tracks.has(String(track_id)):
					errors.append("context %s body %s weights unknown track %s" % [context_name, body_id, track_id])
	for cue_name in cues:
		if not tracks.has(String(cues[cue_name].get("track", ""))):
			errors.append("cue %s uses unknown track" % cue_name)
	if check_files:
		for track_id: String in tracks:
			if not is_playable(track_id):
				errors.append("track %s has no playable file" % track_id)
	return errors


static func _set_loop(music: AudioStream, looped: bool) -> void:
	if music is AudioStreamOggVorbis:
		(music as AudioStreamOggVorbis).loop = looped
	elif music is AudioStreamMP3:
		(music as AudioStreamMP3).loop = looped
	elif music is AudioStreamWAV:
		(music as AudioStreamWAV).loop_mode = AudioStreamWAV.LOOP_FORWARD if looped else AudioStreamWAV.LOOP_DISABLED
