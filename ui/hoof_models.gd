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
		"id": "heart",
		"name": "Heart",
		"text": "A fat heart-shaped frog on a plain sole, built into the body. Shoes sit on it.",
		"thumb": "res://mods/mare_care/ui/thumbs/hoof_heart.png",
	},
	{
		"id": "cushion",
		"name": "Cushion",
		"text": "A heart-shaped frog and a single rim line round the toe and sides. Shoes sit on it.",
		"thumb": "res://mods/mare_care/ui/thumbs/hoof_cushion.png",
	},
	{
		"id": "arch",
		"name": "Arch",
		"text": "A rim drawn as two lines, open and squared off at the heel, with a bean-shaped frog. Shoes sit on it.",
		"thumb": "res://mods/mare_care/ui/thumbs/hoof_arch.png",
	},
	{
		"id": "rings",
		"name": "Rings",
		"text": "Two concentric rings and a thin cleft slit, drawn like a sketch. Shoes sit on it.",
		"thumb": "res://mods/mare_care/ui/thumbs/hoof_rings.png",
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
