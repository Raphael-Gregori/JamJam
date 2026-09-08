extends Control

## 3-lane combat prototype: player actions scroll left->right, enemy actions
## scroll right->left, and hitting the opposite edge resolves damage.
## All logic lives in this single script, but the visuals (lanes, hitbox
## markers, selector, HP bars, spawned actions) are real Control nodes in
## the scene tree, positioned/tinted by this script rather than hand-drawn.

# Data for each spawnable action. Add more entries here to add new action
# types without touching any other logic.

# TODO : Rewire the spped and damage to the script p1 and p2
const ACTION_TYPES := {
	"fast": {
		"name": "Fast Strike",
		"speed": 500.0,
		"damage": 1,
		"color": Color(0.95, 0.85, 0.2),
		"radius": 12.0,
	},
	"heavy": {
		"name": "Heavy Strike",
		"speed": 200.0,
		"damage": 2,
		"color": Color(0.9, 0.2, 0.2),
		"radius": 20.0,
	},
}

# --- Tunables (editable from the Inspector) ---
@export var enemy_spawn_interval := 5
@export var lane_count := 3
### horizontal gap between the screen edge and the hitbox zones
@export var lane_margin := 60.0 
### thickness of each lane row / hitbox marker
@export var lane_height := 24.0 
@export var lane_area_top_ratio := 0.158 ### lane rows occupy this vertical band of the viewport...
@export var lane_area_bottom_ratio := 0.566 ### ...from top_ratio to bottom_ratio (0 = top, 1 = bottom)

### The 3D unit stat blocks this combat overlay reports damage to - repoint
### these in the Inspector if P1/P2 ever move elsewhere in the tree. Resolved
### to actual node references in _ready(); HP is read/written on them
### directly, never mirrored into a local variable.
@export var player_unit_path: NodePath = NodePath("../../P1")
@export var enemy_unit_path: NodePath = NodePath("../../P2")
var player_unit: MeshInstance3D
var enemy_unit: MeshInstance3D

# Lane visuals authored directly in main_scene.tscn (under CombatHUD/Root) -
# this script only repositions/resizes/tints them, their base color/style is
# whatever's set on the node in the editor.
@onready var lane_rects: Array[ColorRect] = [$Lane0, $Lane1, $Lane2]
@onready var lane_selector: ColorRect = $LaneSelector
@onready var player_hitbox: ColorRect = $PlayerHitbox
@onready var enemy_hitbox: ColorRect = $EnemyHitbox
@onready var actions_layer: Control = $ActionsLayer
@onready var player_hp_bar: ProgressBar = $PlayerHPBar
@onready var enemy_hp_bar: ProgressBar = $EnemyHPBar
@onready var result_label: Label = $ResultLabel

# Y position of each lane, computed once in _ready() from the viewport size.
var lane_ys: Array[float] = []
# X thresholds: player actions resolve at right_edge_x, enemy actions at left_edge_x.
var left_edge_x := 0.0
var right_edge_x := 0.0

var selected_lane := 1
var combat_active := true

# Actions currently scrolling: {lane, side, type, x, node}. "node" is the
# actual ColorRect representing this action on screen; "x" is its logical
# center position, kept separately since the node is positioned top-left.
var actions: Array[Dictionary] = []
var spawn_elapsed := 0.0
# Countdown timers driving the brief flash on a hitbox marker when it's hit.
var player_flash_t := 0.0
var enemy_flash_t := 0.0


func _ready() -> void:
	player_unit = get_node(player_unit_path)
	enemy_unit = get_node(enemy_unit_path)

	# Lay out the 3 lanes and the two edge thresholds from the current viewport size,
	# then push those positions/sizes onto the actual lane/hitbox nodes.
	var viewport_size := get_viewport_rect().size
	left_edge_x = lane_margin
	right_edge_x = viewport_size.x - lane_margin

	lane_ys.clear()
	var top := viewport_size.y * lane_area_top_ratio
	var bottom := viewport_size.y * lane_area_bottom_ratio
	for i in lane_count:
		var t := float(i) / float(max(lane_count - 1, 1))
		lane_ys.append(lerp(top, bottom, t))

	for i in lane_count:
		lane_rects[i].position = Vector2(left_edge_x, lane_ys[i] - lane_height * 0.5)
		lane_rects[i].size = Vector2(right_edge_x - left_edge_x, lane_height)

	var edge_top: float = lane_ys[0] - lane_height
	var edge_bottom: float = lane_ys[lane_count - 1] + lane_height
	player_hitbox.position = Vector2(left_edge_x - 4.0, edge_top)
	player_hitbox.size = Vector2(6.0, edge_bottom - edge_top)
	enemy_hitbox.position = Vector2(right_edge_x - 2.0, edge_top)
	enemy_hitbox.size = Vector2(6.0, edge_bottom - edge_top)

	_update_lane_selector_position()
	_update_lane_highlight()

	# p_1.gd/p_2.gd already reset _CURRENT_HP to _HP_MAX in their own _ready();
	# P1/P2 are earlier siblings of CombatHUD so theirs has already run by now.
	player_hp_bar.max_value = player_unit._HP_MAX
	enemy_hp_bar.max_value = enemy_unit._HP_MAX
	player_hp_bar.value = player_unit._CURRENT_HP
	enemy_hp_bar.value = enemy_unit._CURRENT_HP
	result_label.visible = false


# Select-lane-then-confirm input scheme: W/S move the lane selector,
# J/K spawn a Fast/Heavy Strike on whichever lane is currently selected.
func _unhandled_input(event: InputEvent) -> void:
	if not combat_active:
		return
	if event.is_action_pressed("lane_select_up"):
		_select_lane(-1)
	elif event.is_action_pressed("lane_select_down"):
		_select_lane(1)
	elif event.is_action_pressed("combat_action_fast"):
		_spawn_action(selected_lane, "player", "fast")
	elif event.is_action_pressed("combat_action_heavy"):
		_spawn_action(selected_lane, "player", "heavy")


func _select_lane(delta: int) -> void:
	# wrapi loops the selection back around instead of stopping at lane 0/2.
	selected_lane = wrapi(selected_lane + delta, 0, lane_count)
	_update_lane_selector_position()
	_update_lane_highlight()


func _update_lane_selector_position() -> void:
	var y: float = lane_ys[selected_lane]
	lane_selector.position = Vector2(left_edge_x - 16.0, y - lane_selector.size.y * 0.5)


# Brightens the selected lane's row via modulate, leaving its authored base
# color (set in the editor) untouched.
func _update_lane_highlight() -> void:
	for i in lane_count:
		lane_rects[i].modulate = Color(1.6, 1.6, 1.6) if i == selected_lane else Color(1, 1, 1)


# Creates the on-screen ColorRect for one action and registers its tracking data.
func _spawn_action(lane: int, side: String, type_key: String) -> void:
	var type: Dictionary = ACTION_TYPES[type_key]
	var d: float = type["radius"] * 2.0

	var node := ColorRect.new()
	node.size = Vector2(d, d)
	node.color = type["color"]
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	actions_layer.add_child(node)

	var a := {
		"lane": lane,
		"side": side,
		"type": type,
		"x": left_edge_x if side == "player" else right_edge_x,
		"node": node,
	}
	_update_action_node_position(a)
	actions.append(a)


func _update_action_node_position(a: Dictionary) -> void:
	var node: ColorRect = a["node"]
	var d: float = node.size.x
	node.position = Vector2(a["x"] - d * 0.5, lane_ys[a["lane"]] - d * 0.5)


func _process(delta: float) -> void:
	if combat_active:
		_update_enemy_spawner(delta)
		_update_actions(delta)
		player_flash_t = max(player_flash_t - delta, 0.0)
		enemy_flash_t = max(enemy_flash_t - delta, 0.0)
	# Multiplies the authored hitbox color towards white while its flash timer is active.
	player_hitbox.modulate = Color(1, 1, 1).lerp(Color(2.5, 2.5, 2.5), player_flash_t / 0.15)
	enemy_hitbox.modulate = Color(1, 1, 1).lerp(Color(2.5, 2.5, 2.5), enemy_flash_t / 0.15)


# Simple fixed-interval enemy AI: every enemy_spawn_interval seconds, spawn a
# random action type on a random lane, starting from the right edge.
func _update_enemy_spawner(delta: float) -> void:
	spawn_elapsed += delta
	if spawn_elapsed < enemy_spawn_interval:
		return
	spawn_elapsed = 0.0
	var lane := randi() % lane_count
	var type_key: String = ["fast", "heavy"][randi() % 2]
	_spawn_action(lane, "enemy", type_key)


# Moves every action and resolves hits by comparing x against a fixed edge
# threshold - no collision/physics needed since same-lane actions never
# interact with each other, only with their own opposite edge.
func _update_actions(delta: float) -> void:
	var i := actions.size() - 1
	while i >= 0:
		var a: Dictionary = actions[i]
		var speed: float = a["type"]["speed"]
		if a["side"] == "player":
			a["x"] += speed * delta
		else:
			a["x"] -= speed * delta
		_update_action_node_position(a)

		var hit: bool = (a["side"] == "player" and a["x"] >= right_edge_x) \
			or (a["side"] == "enemy" and a["x"] <= left_edge_x)
		if hit:
			_resolve_hit(a)
			a["node"].queue_free()
			actions.remove_at(i)
		i -= 1


# Applies damage via the unit's own _take_damage() and triggers the hitbox
# flash. Player actions damage the enemy (reached the right/enemy edge) and
# vice versa. HP bars read back from the unit after damage so they never
# drift from the stat block that actually owns the value.
func _resolve_hit(a: Dictionary) -> void:
	var damage: int = a["type"]["damage"]
	if a["side"] == "player":
		enemy_unit._take_damage(damage)
		enemy_hp_bar.value = enemy_unit._CURRENT_HP
		enemy_flash_t = 0.15
		if enemy_unit._CURRENT_HP <= 0:
			_end_combat("It died")
	else:
		player_unit._take_damage(damage)
		player_hp_bar.value = player_unit._CURRENT_HP
		player_flash_t = 0.15
		if player_unit._CURRENT_HP <= 0:
			_end_combat("Defeat... t'es nuuuuuuuul")


func _end_combat(text: String) -> void:
	# Freezes input/spawning (via combat_active) and shows the result.
	combat_active = false
	result_label.text = text
	result_label.visible = true
