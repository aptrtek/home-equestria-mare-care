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
		"text": "A soft, pillow-shaped frog that follows the curve of the toe, with a cleft between its heel lobes. Shoes sit on it.",
		"thumb": "res://mods/mare_care/ui/thumbs/hoof_heart.png",
	},
	{
		"id": "cushion",
		"name": "Cushion",
		"text": "Like Heart, but a smaller, softer pillow in a deeper dished sole. Shoes sit on it.",
		"thumb": "res://mods/mare_care/ui/thumbs/hoof_cushion.png",
	},
	{
		"id": "arch",
		"name": "Arch",
		"text": "A rim in two soft steps round the toe and sides, fading out toward the heel, and a small frog. Shoes sit on it.",
		"thumb": "res://mods/mare_care/ui/thumbs/hoof_arch.png",
	},
	{
		"id": "rings",
		"name": "Rings",
		"text": "Soft concentric rings and a small cleft. Shoes sit on it.",
		"thumb": "res://mods/mare_care/ui/thumbs/hoof_rings.png",
	},
	{
		"id": "mitty",
		"name": "Mitty's",
		"text": "Hooves modelled into the body itself, by Mitty. Shoes sit on them.",
		"thumb": "res://mods/mare_care/ui/thumbs/hoof_mitty.png",
	},
	{
		"id": "mitty_v2",
		"name": "Mitty's v2",
		"text": "Mitty's second hooves, with big puffy frogs that bulge out of the sole. Shoes sit on them.",
		"thumb": "res://mods/mare_care/ui/thumbs/hoof_mitty_v2.png",
	},
]


static func find(id: String) -> Dictionary:
	for model: Dictionary in MODELS:
		if str(model.id) == id: return model
	return MODELS[0]
