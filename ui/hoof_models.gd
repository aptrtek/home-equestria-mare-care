extends RefCounted
## The hoof models the settings page offers, in the order it shows them. To list another one, add
## an entry here with a thumbnail (ui/thumbs/) and teach farrier/shoes.gd to draw it; the page, the
## saved setting (settings.cfg [hooves] model) and the thumbnails are all driven by this list.

const MODELS: Array[Dictionary] = [
	{
		"id": "original",
		"name": "Original",
		"text": "The game's own hoof: a plain, smooth sole.",
		"thumb": "res://mods/mare_care/ui/thumbs/hoof_original.png",
	},
	{
		"id": "detailed",
		"name": "Detailed",
		"text": "A hoof with a proper underside: the wall's rim, a darker sole and the frog. Shoes sit on the rim.",
		"thumb": "res://mods/mare_care/ui/thumbs/hoof_detailed.png",
	},
]


static func find(id: String) -> Dictionary:
	for model: Dictionary in MODELS:
		if str(model.id) == id: return model
	return MODELS[0]
