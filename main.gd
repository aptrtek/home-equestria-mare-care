extends Node
## Mare Care: new ways to look after your mare.
##
## Each kind of care is its own child node:
##   Brushing (brushing/): mane, tail and coat brushes, built on modChad's Grooming mod; a freshly
##     brushed mane or tail sparkles.
##   Farrier (farrier/): hoof pick, nippers and rasp, horseshoes and hoof oil. Shoes (farrier/shoes.gd)
##     keeps every shod pony's shoes on her hooves.
## Still to come: tooth brushing and bathing.

const ID := "mare_care"
const BRUSHING := preload("res://mods/mare_care/brushing/brushing.gd")
const SHOES := preload("res://mods/mare_care/farrier/shoes.gd")
const FARRIER := preload("res://mods/mare_care/farrier/farrier.gd")
const CARE := preload("res://mods/mare_care/farrier/hoof_care.gd")


func _ready() -> void:
	add_to_group("mare_care_mod")
	CARE.load_settings(ID)
	_add("Brushing", BRUSHING)
	_add("Shoes", SHOES)
	_add("Farrier", FARRIER)


func _add(node_name: String, script: Script) -> Node:
	var node: Node = script.new()
	node.name = node_name
	node.set("mod_id", ID)
	add_child(node)
	return node
