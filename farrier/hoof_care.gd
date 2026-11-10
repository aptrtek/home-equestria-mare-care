extends RefCounted
## What each pony's hooves have had done and when, and when they need it again.
##
## Saved in the world save (Mods.state("mare_care").hooves):
##   {pony_id: {leg: {"picked": day, "trimmed": day, "oiled": day, "shod": day, "shoe": style}}}
## Days are in-game days (TimeOfDay.day + hours / 24). A hoof with no record has never been done.
##
## How often each job comes due again is the player's choice: settings.cfg in the mod's data
## folder (Mods.data_folder("mare_care")), written with the defaults the first time:
##   [upkeep]
##   pick_days=7.0    clean the hoof out again
##   trim_days=7.0    trim and rasp again
##   shoe_days=7.0    reset the shoes (re-nail them)
##   oil_days=7.0     oil again
## 0 turns that job's upkeep off: once done, it stays done.
##   [pay]
##   enabled=true     some mares pay in bits for hoof care (never a wife)

const SETTINGS := "settings.cfg"
const JOBS := ["pick", "trim", "shoe", "oil"]
const DEFAULT_DAYS := 7.0
const STAMP := {"pick": "picked", "trim": "trimmed", "shoe": "shod", "oil": "oiled"}

static var _days := {}
static var pay_enabled := true


static func load_settings(mod_id: String) -> void:
	var path := Mods.data_folder(mod_id).path_join(SETTINGS)
	var config := ConfigFile.new()
	var loaded := config.load(path) == OK
	var changed := not loaded
	for job: String in JOBS:
		var key := job + "_days"
		if not config.has_section_key("upkeep", key):
			config.set_value("upkeep", key, DEFAULT_DAYS)
			changed = true
		_days[job] = maxf(0.0, float(config.get_value("upkeep", key, DEFAULT_DAYS)))
	if not config.has_section_key("pay", "enabled"):
		config.set_value("pay", "enabled", true)
		changed = true
	pay_enabled = bool(config.get_value("pay", "enabled", true))
	if changed:
		config.save(path)
	print("[mare_care] hoof upkeep (in-game days, 0 = never): %s  (%s)" % [str(_days), ProjectSettings.globalize_path(path)])


static func days(job: String) -> float:
	return float(_days.get(job, DEFAULT_DAYS))


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
	var stamp: String = STAMP[job]
	if job == "shoe" and str(record.get("shoe", "")).is_empty(): return false
	if not record.has(stamp): return true
	var every := days(job)
	return every > 0.0 and now() - float(record[stamp]) >= every


static func mark(mod_id: String, record: Dictionary, job: String) -> void:
	record[STAMP[job]] = now()
	Mods.save_changed()
