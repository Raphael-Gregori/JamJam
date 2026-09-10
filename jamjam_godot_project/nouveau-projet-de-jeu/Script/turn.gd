extends Control

## 3-lane combat prototype: player actions scroll left->right, enemy actions
## scroll right->left, and hitting the opposite edge resolves damage.
## All logic lives in this single script, but the visuals (lanes, hitbox
## markers, selector, HP bars, spawned actions) are real Control nodes in
## the scene tree, positioned/tinted by this script rather than hand-drawn.

# Data for each spawnable action. Add more entries here to add new action
# types without touching any other logic.
const ACTION_TYPES := {
	"fast": {
		"name": "Fast Strike",
		"color": Color(0.95, 0.85, 0.2),
		"radius": 12.0,
	},
	"defense": {
		"name": "Defense",
		"color": Color(0.25, 0.6, 0.95),
		"radius": 12.0,
	},
}

# --- Tunables (editable from the Inspector) ---
@export var lane_count := 3
### horizontal gap between the screen edge and the hitbox zones
@export var lane_margin := 60.0
### thickness of each lane row / hitbox marker
@export var lane_height := 24.0
@export var lane_area_top_ratio := 0.158 ## # lane rows occupy this vertical band of the viewport...
@export var lane_area_bottom_ratio := 0.566 ## # ...from top_ratio to bottom_ratio (0 = top, 1 = bottom)

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
@onready var player_atk_bar: ProgressBar = $P1_ATK_Regen
@onready var enemy_atk_bar: ProgressBar = $P2_ATK_Regen
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
# Countdown timers driving the brief flash on a hitbox marker when it's hit.
var player_flash_t := 0.0
var enemy_flash_t := 0.0


func _ready() -> void:
	player_unit = get_node(player_unit_path)
	enemy_unit = get_node(enemy_unit_path)

	_init_layout()
	
	# p_1.gd/p_2.gd already reset _CURRENT_HP to _HP_MAX in their own _ready();
	# P1/P2 are earlier siblings of CombatHUD so theirs has already run by now.
	player_hp_bar.max_value = player_unit._HP_MAX
	enemy_hp_bar.max_value = enemy_unit._HP_MAX
	player_hp_bar.value = player_unit._CURRENT_HP
	enemy_hp_bar.value = enemy_unit._CURRENT_HP
	player_atk_bar.max_value = player_unit._ATK_MAX
	enemy_atk_bar.max_value = enemy_unit._ATK_MAX
	player_atk_bar.value = player_unit._CURRENT_ATK
	enemy_atk_bar.value = enemy_unit._CURRENT_ATK
	result_label.visible = false

# Lay out the 3 lanes and the two edge thresholds from the current viewport size,
# then push those positions/sizes onto the actual lane/hitbox nodes.
func _init_layout() -> void:
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


# combat_action_fast spawns a Fast Strike, combat_parry spawns a Defense, both
# on whichever lane is currently selected (see _update_selected_lane) and
# both gated by the same ATK charge (see p_1.gd/p_2.gd) - a parry costs a
# strike's worth of charge just like an attack does.
func _unhandled_input(event: InputEvent) -> void:
	if not combat_active:
		return
	if event.is_action_pressed("combat_action_fast"):
		if player_unit._is_atk_ready():
			player_unit._consume_atk()
			_spawn_action(selected_lane, "player", "fast")
	elif event.is_action_pressed("combat_parry"):
		if player_unit._is_atk_ready():
			player_unit._consume_atk()
			_spawn_action(selected_lane, "player", "defense")


# Hold-based lane select: Z (lane_select_up) pins the selector to the top
# lane, S (lane_select_down) to the bottom lane; releasing both rests on
# the middle lane. Polled every frame instead of on key-press events so
# the selection tracks whichever key is currently held.
func _update_selected_lane() -> void:
	var new_lane := 1
	if Input.is_action_pressed("lane_select_up"):
		new_lane = 0
	elif Input.is_action_pressed("lane_select_down"):
		new_lane = lane_count - 1
	if new_lane != selected_lane:
		selected_lane = new_lane
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

	# Speed/damage come from the acting unit's own stat block, not the action type.
	var unit: MeshInstance3D = player_unit if side == "player" else enemy_unit
	# A Defense only ever travels from its own edge to the middle of the lane
	# (see _resolve_defenses) instead of all the way to the opposite edge.
	var target_x: float = (left_edge_x + right_edge_x) * 0.5 if type_key == "defense" \
		else (right_edge_x if side == "player" else left_edge_x)
	var dict_stats := {
		"lane": lane,
		"side": side,
		"type_key": type_key,
		"type": type,
		"speed": unit._SPEED,
		"damage": unit._FORCE,
		"x": left_edge_x if side == "player" else right_edge_x,
		"target_x": target_x,
		"node": node,
	}
	_update_action_node_position(dict_stats)
	actions.append(dict_stats)


func _update_action_node_position(dict_stats: Dictionary) -> void:
	var node: ColorRect = dict_stats["node"]
	var d: float = node.size.x
	node.position = Vector2(dict_stats["x"] - d * 0.5, lane_ys[dict_stats["lane"]] - d * 0.5)


func _process(delta: float) -> void:
	if combat_active:
		_update_selected_lane()
		_update_enemy_spawner(delta)
		_update_actions(delta)
		player_flash_t = max(player_flash_t - delta, 0.0)
		enemy_flash_t = max(enemy_flash_t - delta, 0.0)
	player_atk_bar.value = player_unit._CURRENT_ATK
	enemy_atk_bar.value = enemy_unit._CURRENT_ATK
	# Multiplies the authored hitbox color towards white while its flash timer is active.
	player_hitbox.modulate = Color(1, 1, 1).lerp(Color(2.5, 2.5, 2.5), player_flash_t / 0.15)
	enemy_hitbox.modulate = Color(1, 1, 1).lerp(Color(2.5, 2.5, 2.5), enemy_flash_t / 0.15)


# Regen-driven enemy AI: the instant the enemy's own ATK charge is full it
# acts automatically, from a random lane (there is no enemy lane-select
# mechanic) and randomly choosing between a Fast Strike and a Defense, just
# like the player can - consuming its charge either way.
func _update_enemy_spawner(_delta: float) -> void:
	if not enemy_unit._is_atk_ready():
		return
	enemy_unit._consume_atk()
	var lane := randi() % lane_count
	var type_key: String = ["fast", "defense"][randi() % 2]
	_spawn_action(lane, "enemy", type_key)


# Moves every action (clamped to its own target_x - the opposite edge for a
# Fast Strike, the lane's midpoint for a Defense) and resolves hits by
# comparing x against that target. A Defense that reaches its target without
# having intercepted anything (see _resolve_defenses) just disappears there,
# since it isn't the one that deals damage.
func _update_actions(delta: float) -> void:
	for dict_actions in actions:
		var speed: float = dict_actions["speed"]
		## Check if it's player ...
		if dict_actions["side"] == "player":
			dict_actions["x"] = min(dict_actions["x"] + speed * delta, dict_actions["target_x"])
		## ... or enemy
		else:
			dict_actions["x"] = max(dict_actions["x"] - speed * delta, dict_actions["target_x"])
		_update_action_node_position(dict_actions)

	_resolve_defenses()

	var i := actions.size() - 1
	while i >= 0:
		var dict_actions: Dictionary = actions[i]
		if dict_actions["x"] == dict_actions["target_x"]:
			if dict_actions["type_key"] != "defense":
				_resolve_hit(dict_actions)
			dict_actions["node"].queue_free()
			actions.remove_at(i)
		i -= 1


# A Defense marker (either side can spawn one) intercepts the first
# same-lane opposing action that has reached or passed it at any point along
# its short trip to the midpoint, nullifying both with no damage dealt. If
# nothing crosses it in time, the marker itself vanishes on arrival (see
# _update_actions) instead of lingering as a standing wall.
func _resolve_defenses() -> void:
	var consumed: Array[int] = []
	for i in actions.size():
		var defense: Dictionary = actions[i]
		if consumed.has(i) or defense["type_key"] != "defense":
			continue
		# A player defense moves left-to-right (rising x) so it's crossed once
		# the opposing action's x has dropped to or below it; an enemy defense
		# moves right-to-left (falling x) so it's crossed the other way round.
		var opposing_side: String = "enemy" if defense["side"] == "player" else "player"
		for j in actions.size():
			if i == j or consumed.has(j):
				continue
			var opposing_action: Dictionary = actions[j]
			if opposing_action["side"] != opposing_side or opposing_action["lane"] != defense["lane"]:
				continue
			var crossed: bool = opposing_action["x"] <= defense["x"] if defense["side"] == "player" \
				else opposing_action["x"] >= defense["x"]
			if crossed:
				consumed.append(i)
				consumed.append(j)
				break

	consumed.sort()
	consumed.reverse()
	for idx in consumed:
		actions[idx]["node"].queue_free()
		actions.remove_at(idx)


# Applies damage via the unit's own _take_damage() and triggers the hitbox
# flash. Player actions damage the enemy (reached the right/enemy edge) and
# vice versa. HP bars read back from the unit after damage so they never
# drift from the stat block that actually owns the value.
func _resolve_hit(dict_stats: Dictionary) -> void:
	var damage: int = dict_stats["damage"]
	if dict_stats["side"] == "player":
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
