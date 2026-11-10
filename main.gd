extends Node
## Mare Care: new ways to look after your mare.
##
## This first piece is brushing (brushing/), built on modChad's Grooming mod: a mane & tail brush
## and a coat brush, and a freshly brushed mane or tail sparkles. Still to come: farrier work
## (hoof care and shoes), tooth brushing and bathing, each its own child node like Brushing.

const ID := "mare_care"
const BRUSHING := preload("res://mods/mare_care/brushing/brushing.gd")


func _ready() -> void:
	add_to_group("mare_care_mod")
	var brushing: Node = BRUSHING.new()
	brushing.name = "Brushing"
	brushing.set("mod_id", ID)
	add_child(brushing)
