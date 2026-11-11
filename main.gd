extends Node
## Mare Care: new ways to look after your mare.
##
## Each kind of care is its own child node:
##   Brushing (brushing/): mane, tail and coat brushes, built on modChad's Grooming mod; a freshly
##     brushed mane or tail sparkles.
##   SettingsTab (ui/): Mare Care's page in Settings (hoof model, upkeep, payment, sparkle).
##   Farrier (farrier/): hoof pick, nippers and rasp, horseshoes and hoof oil. Shoes (farrier/shoes.gd)
##     keeps every shod pony's shoes on her hooves.
## Still to come: tooth brushing and bathing.

const ID := "mare_care"
const BRUSHING := preload("res://mods/mare_care/brushing/brushing.gd")
const SHOES := preload("res://mods/mare_care/farrier/shoes.gd")
const FARRIER := preload("res://mods/mare_care/farrier/farrier.gd")
const CARE := preload("res://mods/mare_care/farrier/hoof_care.gd")
const SETTINGS_TAB := preload("res://mods/mare_care/ui/settings_tab.gd")
const SPA_CARE := preload("res://mods/mare_care/farrier/spa_care.gd")
const BODY_HOOVES := preload("res://mods/mare_care/farrier/body_hooves.gd")


func _ready() -> void:
	add_to_group("mare_care_mod")
	CARE.load_settings(ID)
	# Body hoof models change the shared body mesh, so they go in before any pony is built.
	BODY_HOOVES.apply(CARE.hoof_model, CARE.show_frog)
	_add("Brushing", BRUSHING)
	_add("Shoes", SHOES)
	_add("Farrier", FARRIER)
	_add("SpaCare", SPA_CARE)
	_add("SettingsTab", SETTINGS_TAB)


func _add(node_name: String, script: Script) -> Node:
	var node: Node = script.new()
	node.name = node_name
	node.set("mod_id", ID)
	add_child(node)
	return node
