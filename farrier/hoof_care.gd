extends RefCounted
## What each pony's hooves have had done and when, and when they need it again, plus the mod's
## settings.
##
## Saved in the world save (Mods.state("mare_care").hooves):
##   {pony_id: {leg: {"picked": day, "trimmed": day, "oiled": day, "shod": day, "shoe": style}}}
## Days are in-game days (TimeOfDay.day + hours / 24). A hoof with no record has never been done.
##
## The settings live in settings.cfg in the mod's data folder (Mods.data_folder("mare_care")). The
## Settings > Mare Care page edits them; the file can be edited by hand too (applies on restart).
##   [upkeep]
##   hooves_get_dirty=true   false: hooves never need picking, trimming, oiling or shoe resets
##   spa_care=true    Aloe and Lotus's spa also cleans a client's hooves (farrier/spa_care.gd)
##   pick_days=7.0    how long until a cleaned hoof is dirty again
##   trim_days=7.0    trim and rasp again
##   shoe_days=7.0    reset the shoes (re-nail them)
##   oil_days=7.0     oil again
## 0 turns that job's upkeep off: once done, it stays done.
##   [pay]
##   enabled=true     some mares pay in bits for hoof care (never a wife)
##   [hooves]
##   model="original" the hoof model: "original" (the game's own), "heart", "cushion", "arch" or "rings" (line-art
##                    hooves), "mitty" or "mitty_v2" (hooves built into the body, by Mitty; v2 has puffy frogs)
##   show_frog=true   the frog on the underside of a lifted hoof (heart, cushion, arch, rings)
##   [extras]
##   hoof_licking=false   lick her lifted hooves clean until they sparkle (off unless switched on)
##   [brushing]
##   sparkle=true     a freshly brushed mane or tail sparkles
##   sparkle_minutes=10.0   for how long
##   hoof_sparkle=true      an oiled or licked-clean hoof sparkles
##   hoof_sparkle_minutes=5.0   for how long

const SETTINGS := "settings.cfg"
const JOBS := ["pick", "trim", "shoe", "oil"]
const DEFAULT_DAYS := 7.0
const STAMP := {"pick": "picked", "trim": "trimmed", "shoe": "shod", "oil": "oiled"}
const MODELS := ["original", "heart", "cushion", "arch", "rings", "mitty", "mitty_v2"]
const DEFAULT_MODEL := "original"
const DEFAULT_SPARKLE_MINUTES := 10.0
const DEFAULT_HOOF_SPARKLE_MINUTES := 5.0

static var _days := {}
static var dirt_enabled := true
static var spa_care := true
static var pay_enabled := true
static var show_frog := true
static var hoof_model := DEFAULT_MODEL
static var sparkle_on := true
## Licking her hooves clean: off unless the player switches it on.
static var lick_enabled := false
static var sparkle_minutes := DEFAULT_SPARKLE_MINUTES
static var hoof_sparkle_on := true
static var hoof_sparkle_minutes := DEFAULT_HOOF_SPARKLE_MINUTES


static func _path(mod_id: String) -> String:
	return Mods.data_folder(mod_id).path_join(SETTINGS)


static func load_settings(mod_id: String) -> void:
	var path := _path(mod_id)
	var config := ConfigFile.new()
	var loaded := config.load(path) == OK
	for job: String in JOBS:
		_days[job] = maxf(0.0, float(config.get_value("upkeep", job + "_days", DEFAULT_DAYS)))
	dirt_enabled = bool(config.get_value("upkeep", "hooves_get_dirty", true))
	spa_care = bool(config.get_value("upkeep", "spa_care", true))
	pay_enabled = bool(config.get_value("pay", "enabled", true))
	show_frog = bool(config.get_value("hooves", "show_frog", true))
	var model := str(config.get_value("hooves", "model", DEFAULT_MODEL))
	hoof_model = model if model in MODELS else DEFAULT_MODEL
	sparkle_on = bool(config.get_value("brushing", "sparkle", true))
	lick_enabled = bool(config.get_value("extras", "hoof_licking", false))
	sparkle_minutes = clampf(float(config.get_value("brushing", "sparkle_minutes", DEFAULT_SPARKLE_MINUTES)), 1.0, 60.0)
	hoof_sparkle_on = bool(config.get_value("brushing", "hoof_sparkle", true))
	hoof_sparkle_minutes = clampf(float(config.get_value("brushing", "hoof_sparkle_minutes", DEFAULT_HOOF_SPARKLE_MINUTES)), 1.0, 60.0)
	if not loaded:
		save_settings(mod_id)
	print("[mare_care] settings: hooves get dirty %s, upkeep days %s, pay %s, hoof model %s, frog %s, sparkle %s (%s min)  (%s)" % [
		dirt_enabled, str(_days), pay_enabled, hoof_model, show_frog, sparkle_on, sparkle_minutes, ProjectSettings.globalize_path(path)])


## Writes every setting back to settings.cfg.
static func save_settings(mod_id: String) -> void:
	var config := ConfigFile.new()
	for job: String in JOBS:
		config.set_value("upkeep", job + "_days", days(job))
	config.set_value("upkeep", "hooves_get_dirty", dirt_enabled)
	config.set_value("upkeep", "spa_care", spa_care)
	config.set_value("pay", "enabled", pay_enabled)
	config.set_value("hooves", "model", hoof_model)
	config.set_value("hooves", "show_frog", show_frog)
	config.set_value("brushing", "sparkle", sparkle_on)
	config.set_value("extras", "hoof_licking", lick_enabled)
	config.set_value("brushing", "sparkle_minutes", sparkle_minutes)
	config.set_value("brushing", "hoof_sparkle", hoof_sparkle_on)
	config.set_value("brushing", "hoof_sparkle_minutes", hoof_sparkle_minutes)
	config.save(_path(mod_id))


static func reset_settings(mod_id: String) -> void:
	for job: String in JOBS:
		_days[job] = DEFAULT_DAYS
	dirt_enabled = true
	spa_care = true
	pay_enabled = true
	show_frog = true
	hoof_model = DEFAULT_MODEL
	sparkle_on = true
	lick_enabled = false
	sparkle_minutes = DEFAULT_SPARKLE_MINUTES
	hoof_sparkle_on = true
	hoof_sparkle_minutes = DEFAULT_HOOF_SPARKLE_MINUTES
	save_settings(mod_id)


static func set_days(job: String, value: float) -> void:
	_days[job] = maxf(0.0, value)


static func days(job: String) -> float:
	return float(_days.get(job, DEFAULT_DAYS))


## True when the hoof model draws its own underside as pieces on the hoof (Detailed, Soft). The
## Original and Mitty's models have none: Mitty's hooves are part of the body mesh itself.
static func underside() -> bool:
	return hoof_model in ["heart", "cushion", "arch", "rings"]


static func now() -> float:
	var time: Node = Engine.get_main_loop().root.get_node_or_null("/root/TimeOfDay") if Engine.get_main_loop() is SceneTree else null
	return float(time.get("day")) + float(time.get("hours")) / 24.0 if time != null else 0.0


static func hooves(mod_id: String, pony_id: String) -> Dictionary:
	var state := Mods.state(mod_id)
	if not state.get("hooves") is Dictionary: state["hooves"] = {}
	var all: Dictionary = state["hooves"]
	if not all.get(pony_id) is Dictionary: all[pony_id] = {}
	return all[pony_id]


static func hoof(mod_id: String, pony_id: String, leg: String) -> Dictionary:
	var all := hooves(mod_id, pony_id)
	if not all.get(leg) is Dictionary: all[leg] = {}
	return all[leg]


## True when `job` is due on this hoof: never done, or done longer ago than its upkeep.
## "shoe" is due only for a shod hoof (its shoe has worked loose); a bare hoof is never due.
static func due(record: Dictionary, job: String) -> bool:
	if not dirt_enabled: return false
	var stamp: String = STAMP[job]
	if job == "shoe" and str(record.get("shoe", "")).is_empty(): return false
	if not record.has(stamp): return true
	var every := days(job)
	return every > 0.0 and now() - float(record[stamp]) >= every


static func mark(mod_id: String, record: Dictionary, job: String) -> void:
	record[STAMP[job]] = now()
	Mods.save_changed()
