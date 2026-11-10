extends Node
## Mare Care's page in the game's Settings, next to the other add-on pages (Unfplap does the same).
##
## The game builds its settings page from its own tables, so a mod adds a page by reaching into the
## page when it opens: a button in the sidebar, a panel in the content area, and a few lines to keep
## the native tabs and any other add-on's panel from showing at the same time. Every step checks
## that the page still looks the way this expects, and skips cleanly if it does not.
##
## The page edits the same settings the mod reads (farrier/hoof_care.gd): the hoof model with a
## thumbnail of each, how often hooves need care again, payment, and the brushing sparkle. Changes
## apply at once and are saved to settings.cfg a moment later.

const STYLE := preload("res://world/ui/menu_style.gd")
const CARE := preload("res://mods/mare_care/farrier/hoof_care.gd")
const HOOF_MODELS := preload("res://mods/mare_care/ui/hoof_models.gd")
const PAGE_PATH := "res://world/ui/settings_page.gd"
## The page's own content areas; anything else in its content box is another add-on's panel.
const NATIVE := ["_scroll", "provider", "prompts", "feedback_notes", "controls_map"]
const TITLE := "Mare Care"
const ICON_KIND := "horseshoe"
const SAVE_DELAY := 0.5
const UPKEEP := [
	["pick", "Hooves get dirty after", "Stones and dirt build up again this long after a hoof was cleaned out."],
	["trim", "Hooves need trimming after", "How long a trim lasts."],
	["shoe", "Shoes work loose after", "How long before a shoe needs its nails reset."],
	["oil", "Hooves need oil after", "How long the oil lasts."],
]

var mod_id := "mare_care"
## One entry per settings page that was injected: {page, button, ui, extra: [nodes], refs: {}}.
var _entries: Array = []
var _guard := false
var _save_pending := false


func _ready() -> void:
	Mods.on_node(PAGE_PATH, _on_page)


func _exit_tree() -> void:
	for entry: Dictionary in _entries:
		for key: String in ["ui", "button"]:
			if is_instance_valid(entry[key]): (entry[key] as Node).queue_free()
		for node: Variant in entry.extra:
			if is_instance_valid(node): (node as Node).queue_free()
		if is_instance_valid(entry.page):
			(entry.page as Node).remove_meta("mare_care_tab")
	_entries.clear()
	if _save_pending: CARE.save_settings(mod_id)


# ---------------------------------------------------------------- injecting into the page

func _on_page(page: Node) -> void:
	if not is_instance_valid(page) or page.has_meta("mare_care_tab") or page.has_meta("mare_care_pending"):
		return
	page.set_meta("mare_care_pending", true)
	_inject.call_deferred(page)


func _inject(page: Node) -> void:
	for attempt: int in 10:
		if not is_instance_valid(page): return
		if page.has_meta("mare_care_tab"):
			page.remove_meta("mare_care_pending")
			return
		var parts := _parts(page)
		if not parts.is_empty():
			page.remove_meta("mare_care_pending")
			_inject_now(page, parts)
			return
		await get_tree().process_frame
	if is_instance_valid(page): page.remove_meta("mare_care_pending")
	print("[mare_care] settings page: internals unavailable; skipped")


## The pieces of the page this needs, or {} while it is not built or has changed shape.
func _parts(page: Node) -> Dictionary:
	var side_scroll: Variant = page.get("_side_scroll")
	var content: Variant = page.get("_content")
	var tabs: Variant = page.get("_tabs")
	var title: Variant = page.get("_tab_title")
	var icon: Variant = page.get("_tab_icon")
	if not (side_scroll is ScrollContainer and content is VBoxContainer and tabs is Array and title is Label and icon is Control):
		return {}
	if not page.has_method("_button") or not page.has_method("_redraw"): return {}
	if (side_scroll as ScrollContainer).get_child_count() == 0: return {}
	var side: Variant = (side_scroll as ScrollContainer).get_child(0)
	if not side is VBoxContainer: return {}
	return {"side": side, "content": content, "tabs": tabs, "title": title, "icon": icon}


func _inject_now(page: Node, parts: Dictionary) -> void:
	var side: VBoxContainer = parts.side
	var content: VBoxContainer = parts.content
	var font := int(page.get("font_size"))
	if font <= 0: font = 20
	var extra: Array = []
	# One "Add-ons" caption above every add-on page: reuse the one another add-on already added.
	var has_caption := false
	for child: Node in side.get_children():
		if child is Label and (child as Label).text == "ADD-ONS": has_caption = true
	if not has_caption:
		var gap := Control.new(); gap.custom_minimum_size.y = 6
		side.add_child(gap); extra.append(gap)
		var caption := STYLE.label("ADD-ONS", "Faint", maxi(12, font - 7))
		caption.add_theme_constant_override("line_spacing", 0)
		side.add_child(caption); extra.append(caption)
	var button: Button = page.call("_button", side, TITLE, _show.bind(page))
	button.theme_type_variation = "Tab"
	button.toggle_mode = true
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.custom_minimum_size = Vector2(0, font * 2.05)
	button.add_theme_font_size_override("font_size", font - 2)
	button.expand_icon = false
	if page.has_method("_icon_texture"): button.icon = page.call("_icon_texture", ICON_KIND)
	var ui := ScrollContainer.new()
	ui.name = "MareCareSettings"
	ui.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	ui.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ui.size_flags_vertical = Control.SIZE_EXPAND_FILL
	ui.follow_focus = true
	ui.visible = false
	content.add_child(ui)
	var holder := MarginContainer.new()
	holder.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for side_name: String in ["left", "top", "right", "bottom"]:
		holder.add_theme_constant_override("margin_" + side_name, 6)
	ui.add_child(holder)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 10)
	holder.add_child(list)
	var entry := {"page": page, "button": button, "ui": ui, "list": list, "extra": extra, "font": font, "refs": {}}
	_entries.append(entry)
	_build(entry)
	# Choosing a native tab, or another add-on's page, puts this one away.
	for tab: Variant in parts.tabs:
		if tab is Button: (tab as Button).pressed.connect(_hide.bind(page))
	for key: String in NATIVE:
		var native: Variant = page.get(key)
		if native is CanvasItem: (native as CanvasItem).visibility_changed.connect(_native_shown.bind(page))
	for child: Node in content.get_children(): _watch_other(child, page)
	content.child_entered_tree.connect(_watch_other.bind(page))
	page.set_meta("mare_care_tab", true)
	print("[mare_care] settings page added")


## Another add-on's panel in the content box: when it shows, this page hides.
func _watch_other(child: Node, page: Node) -> void:
	if not child is Control or not is_instance_valid(page): return
	if str(child.name) == "MareCareSettings" or _is_native(page, child): return
	(child as Control).visibility_changed.connect(func() -> void:
		if is_instance_valid(child) and (child as Control).visible: _hide(page))


func _entry_for(page: Node) -> Dictionary:
	for entry: Dictionary in _entries:
		if entry.page == page: return entry
	return {}


func _show(page: Node) -> void:
	var entry := _entry_for(page)
	if entry.is_empty(): return
	var parts := _parts(page)
	if parts.is_empty(): return
	_guard = true
	for key: String in NATIVE:
		var native: Variant = page.get(key)
		if native is CanvasItem: (native as CanvasItem).visible = false
	for child: Node in (parts.content as VBoxContainer).get_children():
		if child is Control and child != entry.ui and not _is_native(page, child): (child as Control).visible = false
	for sibling: Node in (parts.side as VBoxContainer).get_children():
		if sibling is Button and sibling != entry.button: (sibling as Button).set_pressed_no_signal(false)
	(entry.ui as Control).visible = true
	(parts.title as Label).text = TITLE
	(parts.icon as Control).set("kind", ICON_KIND)
	for tab: Variant in parts.tabs:
		if tab is Button: (tab as Button).set_pressed_no_signal(false)
	(entry.button as Button).set_pressed_no_signal(true)
	page.call("_redraw")
	_guard = false


func _is_native(page: Node, node: Node) -> bool:
	for key: String in NATIVE:
		if page.get(key) == node: return true
	return false


func _hide(page: Node) -> void:
	if _guard: return
	var entry := _entry_for(page)
	if entry.is_empty(): return
	if is_instance_valid(entry.ui): (entry.ui as Control).visible = false
	if is_instance_valid(entry.button): (entry.button as Button).set_pressed_no_signal(false)


func _native_shown(page: Node) -> void:
	if _guard: return
	var entry := _entry_for(page)
	if entry.is_empty() or not is_instance_valid(entry.ui) or not (entry.ui as Control).visible: return
	for key: String in NATIVE:
		var native: Variant = page.get(key)
		if native is CanvasItem and (native as CanvasItem).visible:
			_hide(page)
			return


# ---------------------------------------------------------------- the page's contents

func _build(entry: Dictionary) -> void:
	var list: VBoxContainer = entry.list
	for child: Node in list.get_children(): child.queue_free()
	entry.refs = {}
	var font: int = entry.font
	_note(entry, "Changes apply right away and are saved for next time. Hooves show their underside while a pony has one lifted for the farrier.")

	_heading(list, "Hooves", font)
	_model_chooser(entry)
	_toggle_row(entry, "Show the frog", "The V-shaped pad on a lifted hoof's underside. Detailed model only.", CARE.show_frog,
		_on_frog.bind(entry), "frog")

	_heading(list, "Care upkeep", font)
	_toggle_row(entry, "Hooves get dirty", "Off: hooves never need picking, trimming or oiling and shoes never work loose. The tools, shoes, jewellery and hoof models all still work.", CARE.dirt_enabled,
		_on_dirt.bind(entry), "dirt")
	_toggle_row(entry, "The spa cares for hooves", "Mares who finish a visit to Aloe and Lotus's spa have their hooves cleaned, trimmed and oiled, whoever did the work.", CARE.spa_care,
		_on_spa_care.bind(entry), "spa")
	for job: Array in UPKEEP:
		_slider_row(entry, str(job[1]), str(job[2]), 0.0, 30.0, 1.0, CARE.days(str(job[0])),
			_describe_days, _on_days.bind(str(job[0]), entry), "days_" + str(job[0]))
	_note(entry, "These are in-game days. When a job comes due the hint on her leg says so, and a shoe that is due sits a little crooked until it is reset. Never again means once done, it stays done.")

	_heading(list, "Payment", font)
	_toggle_row(entry, "Mares pay for hoof care", "Some mares pay in bits for the jobs a hoof needed. Never your wife.", CARE.pay_enabled,
		_on_pay.bind(entry), "pay")

	_heading(list, "Brushing", font)
	_toggle_row(entry, "Sparkle after brushing", "A freshly brushed mane or tail sparkles for a while.", CARE.sparkle_on,
		_on_sparkle.bind(entry), "sparkle")
	_slider_row(entry, "How long it sparkles", "", 1.0, 30.0, 1.0, CARE.sparkle_minutes,
		_describe_minutes, _on_sparkle_minutes.bind(entry), "sparkle_minutes")

	var reset := Button.new()
	reset.text = "Reset to defaults"
	reset.add_theme_font_size_override("font_size", font)
	reset.custom_minimum_size = Vector2(font * 9.0, font * 1.9)
	reset.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	reset.pressed.connect(func() -> void:
		CARE.reset_settings(mod_id)
		_apply()
		_build(entry))
	list.add_child(reset)
	_sync(entry)


func _model_chooser(entry: Dictionary) -> void:
	var font: int = entry.font
	var inner := _card(entry)
	inner.add_child(_title_block("Hoof model", "How a hoof looks from below. Pick one to see it on the next lifted hoof.", font))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	inner.add_child(row)
	var buttons := {}
	for model: Dictionary in HOOF_MODELS.MODELS:
		var button := Button.new()
		button.toggle_mode = true
		button.text = str(model.name)
		button.add_theme_font_size_override("font_size", font)
		button.custom_minimum_size = Vector2(font * 10.5, font * 9.4)
		button.expand_icon = true
		button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		button.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
		button.add_theme_constant_override("icon_max_width", int(font * 10))
		button.add_theme_constant_override("h_separation", 0)
		var path := str(model.thumb)
		if ResourceLoader.exists(path): button.icon = load(path) as Texture2D
		button.pressed.connect(_choose_model.bind(entry, str(model.id)))
		row.add_child(button)
		buttons[str(model.id)] = button
	var about := STYLE.label("", "Muted", font - 4)
	about.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	inner.add_child(about)
	entry.refs.models = buttons
	entry.refs.about = about


func _on_frog(on: bool, entry: Dictionary) -> void:
	CARE.show_frog = on
	_changed(entry)


func _on_dirt(on: bool, entry: Dictionary) -> void:
	CARE.dirt_enabled = on
	_changed(entry)


func _on_spa_care(on: bool, entry: Dictionary) -> void:
	CARE.spa_care = on
	_changed(entry)


func _on_pay(on: bool, entry: Dictionary) -> void:
	CARE.pay_enabled = on
	_changed(entry)


func _on_sparkle(on: bool, entry: Dictionary) -> void:
	CARE.sparkle_on = on
	_changed(entry)


func _on_sparkle_minutes(value: float, entry: Dictionary) -> void:
	CARE.sparkle_minutes = value
	_changed(entry)


func _on_days(value: float, job: String, entry: Dictionary) -> void:
	CARE.set_days(job, value)
	_changed(entry)


func _describe_days(value: float) -> String:
	if value < 0.5: return "Never again"
	return "every day" if value < 1.5 else "every %d days" % int(value)


func _describe_minutes(value: float) -> String:
	return "%d minute%s" % [int(value), "" if int(value) == 1 else "s"]


func _choose_model(entry: Dictionary, id: String) -> void:
	if CARE.hoof_model == id:
		_sync(entry)
		return
	CARE.hoof_model = id
	_changed(entry)


## After any change: apply it, save it a moment later, bring the page's own state in line.
func _changed(entry: Dictionary) -> void:
	_apply()
	_save_soon()
	_sync(entry)
	if is_instance_valid(entry.page): entry.page.call("_redraw")


## Shows the new settings on ponies that are in the world.
func _apply() -> void:
	var shoes := get_parent().get_node_or_null("Shoes") if get_parent() != null else null
	if shoes != null and shoes.has_method("refresh_all"): shoes.call("refresh_all")


func _sync(entry: Dictionary) -> void:
	var refs: Dictionary = entry.refs
	if refs.has("models"):
		for id: String in refs.models:
			(refs.models[id] as Button).set_pressed_no_signal(id == CARE.hoof_model)
		(refs.about as Label).text = "%s: %s" % [str(HOOF_MODELS.find(CARE.hoof_model).name), str(HOOF_MODELS.find(CARE.hoof_model).text)]
	for job: Array in UPKEEP:
		var key := "days_" + str(job[0])
		if refs.has(key): (refs[key] as HSlider).editable = CARE.dirt_enabled
	if refs.has("dirt"): (refs.dirt as CheckButton).set_pressed_no_signal(CARE.dirt_enabled)
	if refs.has("spa"):
		(refs.spa as CheckButton).disabled = not CARE.dirt_enabled
		(refs.spa as CheckButton).set_pressed_no_signal(CARE.spa_care)
	if refs.has("frog"):
		var frog: CheckButton = refs.frog
		frog.disabled = not CARE.detailed()
		frog.set_pressed_no_signal(CARE.show_frog)


func _save_soon() -> void:
	if _save_pending: return
	_save_pending = true
	get_tree().create_timer(SAVE_DELAY).timeout.connect(func() -> void:
		_save_pending = false
		CARE.save_settings(mod_id))


# ---------------------------------------------------------------- building blocks

## A row card in the page's own style, returning the box to fill.
func _card(entry: Dictionary) -> VBoxContainer:
	var card := PanelContainer.new()
	var idle: Variant = (entry.page as Node).get("_row_idle")
	if idle is StyleBox: card.add_theme_stylebox_override("panel", idle)
	else: card.add_theme_stylebox_override("panel", STYLE.rounded(STYLE.box(Color(1, 1, 1, 0.05), Color(1, 1, 1, 0.12), 1, 14, 14, 10)))
	(entry.list as VBoxContainer).add_child(card)
	var inner := VBoxContainer.new()
	inner.add_theme_constant_override("separation", 8)
	card.add_child(inner)
	return inner


func _title_block(title: String, note: String, font: int) -> Control:
	var texts := VBoxContainer.new()
	texts.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	texts.add_theme_constant_override("separation", 1)
	var name_label := STYLE.label(title, "", font)
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	texts.add_child(name_label)
	if not note.is_empty():
		var caption := STYLE.label(note, "Faint", font - 5)
		caption.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		texts.add_child(caption)
	return texts


func _heading(list: VBoxContainer, text: String, font: int) -> void:
	var gap := Control.new(); gap.custom_minimum_size.y = 4
	list.add_child(gap)
	list.add_child(STYLE.label(text, "Heading", font + 4))


func _note(entry: Dictionary, text: String) -> void:
	var font: int = entry.font
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", STYLE.rounded(STYLE.box(Color(STYLE.SKY, 0.07), Color(STYLE.SKY, 0.25), 1, 14, 14, 10)))
	(entry.list as VBoxContainer).add_child(card)
	var label := STYLE.label(text, "Muted", font - 4)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.add_child(label)


func _toggle_row(entry: Dictionary, title: String, note: String, value: bool, on_toggled: Callable, ref: String) -> void:
	var font: int = entry.font
	var inner := _card(entry)
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 12)
	inner.add_child(line)
	line.add_child(_title_block(title, note, font))
	var state := STYLE.label("On" if value else "Off", "Muted", font - 2)
	state.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	line.add_child(state)
	var toggle := CheckButton.new()
	toggle.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	toggle.focus_mode = Control.FOCUS_ALL
	toggle.set_pressed_no_signal(value)
	toggle.toggled.connect(func(on: bool) -> void:
		state.text = "On" if on else "Off"
		on_toggled.call(on))
	line.add_child(toggle)
	entry.refs[ref] = toggle


func _slider_row(entry: Dictionary, title: String, note: String, low: float, high: float, step: float, value: float, describe: Callable, on_changed: Callable, ref: String) -> void:
	var font: int = entry.font
	var inner := _card(entry)
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 12)
	inner.add_child(line)
	line.add_child(_title_block(title, note, font))
	var readout := STYLE.label(str(describe.call(value)), "Muted", font - 3)
	readout.custom_minimum_size.x = font * 7.0
	readout.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	readout.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	line.add_child(readout)
	var slider := HSlider.new()
	slider.min_value = low
	slider.max_value = high
	slider.step = step
	slider.set_value_no_signal(value)
	slider.custom_minimum_size = Vector2(font * 9.0, font * 1.6)
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	slider.focus_mode = Control.FOCUS_ALL
	slider.value_changed.connect(func(v: float) -> void:
		readout.text = str(describe.call(v))
		on_changed.call(v))
	line.add_child(slider)
	entry.refs[ref] = slider
