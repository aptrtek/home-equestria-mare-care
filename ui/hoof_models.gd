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
		"text": "A hoof with a proper underside, built into the body: the wall's rim, a recessed sole and the frog. Shoes sit on the rim.",
		"thumb": "res://mods/mare_care/ui/thumbs/hoof_detailed.png",
	},
	{
		"id": "soft",
		"name": "Soft",
		"text": "A smooth, cartoon-style underside, built into the body: a thick rounded lip that tapers to points at the heels, around a glossy dished sole and a soft, puffy frog. Shoes sit on the rim.",
		"thumb": "res://mods/mare_care/ui/thumbs/hoof_soft.png",
	},
	{
		"id": "mitty",
		"name": "Mitty's",
		"text": "Hooves modelled into the body itself, by Mitty. Shoes sit on them.",
		"thumb": "res://mods/mare_care/ui/thumbs/hoof_mitty.png",
	},
]


static func find(id: String) -> Dictionary:
	for model: Dictionary in MODELS:
		if str(model.id) == id: return model
	return MODELS[0]
