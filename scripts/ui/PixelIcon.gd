class_name PixelIcon
extends TextureRect

## Standardisierte Größen der Pixel-Art Icon Design Library (verhindert Layout-Shifts bei Icon-Wechseln)
const SIZE_S := Vector2(18, 18)
const SIZE_M := Vector2(26, 26)
const SIZE_L := Vector2(40, 40)

const SIZES := {
	"S": SIZE_S,
	"M": SIZE_M,
	"L": SIZE_L
}

static var _texture_cache: Dictionary = {}

@export var icon_name: String = "star":
	set(value):
		icon_name = value
		_apply_icon()

@export_enum("S", "M", "L") var size_preset: String = "M":
	set(value):
		size_preset = value
		_apply_size()

func _init(p_icon_name: String = "", p_size_preset: String = "M", p_tint: Color = Color.WHITE):
	expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	size_flags_vertical = Control.SIZE_SHRINK_CENTER
	modulate = p_tint
	size_preset = p_size_preset
	_apply_size()
	if p_icon_name != "":
		icon_name = p_icon_name
		_apply_icon()

func _ready():
	_apply_size()
	_apply_icon()

func set_icon(new_icon_name: String, new_tint: Color = Color.WHITE):
	icon_name = new_icon_name
	modulate = new_tint
	_apply_icon()

func _apply_size():
	var target_size: Vector2 = SIZES.get(size_preset, SIZE_M)
	custom_minimum_size = target_size
	size = target_size

func _apply_icon():
	if icon_name == "":
		texture = null
		return
	texture = get_icon_texture(icon_name)

static func get_size_px(preset: String = "M") -> Vector2:
	return SIZES.get(preset, SIZE_M)

static func get_icon_texture(p_name: String) -> Texture2D:
	if _texture_cache.has(p_name):
		return _texture_cache[p_name]
		
	var svg_path = "res://assets/ui/icons/pixel/%s.svg" % p_name
	if FileAccess.file_exists(svg_path):
		var svg_str = FileAccess.get_file_as_string(svg_path)
		if svg_str != "":
			var img = Image.new()
			var err = img.load_svg_from_string(svg_str, 1.0)
			if err == OK:
				var tex = ImageTexture.create_from_image(img)
				_texture_cache[p_name] = tex
				return tex
				
	if ResourceLoader.exists(svg_path):
		var loaded = load(svg_path)
		if loaded is Texture2D:
			_texture_cache[p_name] = loaded
			return loaded
			
	return null

static func create(p_icon_name: String, p_size_preset: String = "M", p_tint: Color = Color.WHITE) -> PixelIcon:
	return PixelIcon.new(p_icon_name, p_size_preset, p_tint)

static func create_stat_chip(p_icon_name: String, text_val: String, p_size_preset: String = "S", font_size: int = 16, font_color: Color = Color.WHITE) -> HBoxContainer:
	var hbox = HBoxContainer.new()
	hbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	hbox.add_theme_constant_override("separation", 5)
	
	var ic = create(p_icon_name, p_size_preset)
	hbox.add_child(ic)
	
	var lbl = Label.new()
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lbl.text = text_val
	lbl.add_theme_font_size_override("font_size", font_size)
	lbl.add_theme_color_override("font_color", font_color)
	lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	lbl.add_theme_constant_override("outline_size", 3)
	hbox.add_child(lbl)
	return hbox

## Fügt BBCode-Text mit eingebetteten [icon=name] oder [icon=name:S/M/L]-Tags in ein RichTextLabel ein.
static func append_rich_line(rtl: RichTextLabel, bbcode_line: String, default_size_preset: String = "S"):
	if rtl == null:
		return
	var regex = RegEx.new()
	regex.compile("\\[icon=([a-zA-Z0-9_]+)(?::([SML]))?\\]")
	var last_idx = 0
	for m in regex.search_all(bbcode_line):
		var start_idx = m.get_start()
		if start_idx > last_idx:
			rtl.append_text(bbcode_line.substr(last_idx, start_idx - last_idx))
		var ic_name = m.get_string(1)
		var sz_key = m.get_string(2) if m.get_string(2) != "" else default_size_preset
		var sz = get_size_px(sz_key)
		var tex = get_icon_texture(ic_name)
		if tex != null:
			rtl.add_image(tex, int(sz.x), int(sz.y), Color.WHITE, INLINE_ALIGNMENT_CENTER)
		last_idx = m.get_end()
	if last_idx < bbcode_line.length():
		rtl.append_text(bbcode_line.substr(last_idx))
	rtl.append_text("\n")
	rtl.scroll_to_line(rtl.get_line_count())
