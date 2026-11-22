extends TileMap

const SOURCE_ID = 1
const BRICK_ATLAS = Vector2i(7, 0)
const DARK_ATLAS = Vector2i(13, 4)

func _ready():
	# Clean up any BottomBricks child if previously added
	var bb = get_node_or_null("BottomBricks")
	if bb:
		bb.queue_free()
		
	if scale == Vector2.ONE:
		scale = Vector2(4, 4)
		
	_update_layout()
	get_tree().root.size_changed.connect(_update_layout)

func _update_layout():
	if scale == Vector2.ONE:
		scale = Vector2(4, 4)
	var vp_size = get_viewport_rect().size
	var s = scale.x if scale.x > 1.0 else 4.0
	var tile_screen_px = 16.0 * s # 64 px at scale 4
	var cols = int(ceil(vp_size.x / tile_screen_px)) + 4
	var rows = int(ceil(vp_size.y / tile_screen_px)) + 2
	
	# Minimum 36 columns and 17 rows
	cols = max(cols, 36)
	rows = max(rows, 17)
	
	clear()
	
	for x in range(cols):
		# Top brick row at y = 0 (screen y = 0.0)
		set_cell(0, Vector2i(x, 0), SOURCE_ID, BRICK_ATLAS)
		
		# Dark pattern tiles between y = 1 and y = 15 (screen y = 64.0 to 1024.0)
		for y in range(1, 16):
			set_cell(0, Vector2i(x, y), SOURCE_ID, DARK_ATLAS)
			
		# Bottom brick row starting at row 16 (screen y = 1024.0).
		# This aligns with all other screens (StartMenu, MainBoard, CharacterSelect, IntroSequence, etc.)
		# and continues downwards if the viewport is taller than 1080 (e.g. 16:10 or 1200+).
		for y in range(16, rows):
			set_cell(0, Vector2i(x, y), SOURCE_ID, BRICK_ATLAS)
