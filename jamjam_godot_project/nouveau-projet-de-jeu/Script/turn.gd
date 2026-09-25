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
@onready var enemy_lane_selector: ColorRect = $EnemyLaneSelector
@onready var dodge_zone: ColorRect = $DodgeZone
@onready var enemy_dodge_zone: ColorRect = $EnemyDodgeZone
@onready var defense_line: ColorRect = $DefenseLine
@onready var enemy_defense_line: ColorRect = $EnemyDefenseLine
@onready var player_hitbox: ColorRect = $PlayerHitbox
@onready var enemy_hitbox: ColorRect = $EnemyHitbox
@onready var actions_layer: Control = $ActionsLayer
@onready var player_hp_bar: ProgressBar = $PlayerHPBar
@onready var enemy_hp_bar: ProgressBar = $EnemyHPBar
@onready var player_atk_bar: ProgressBar = $P1_ATK_Regen
@onready var enemy_atk_bar: ProgressBar = $P2_ATK_Regen
@onready var player_dodge_bar: ProgressBar = $P1_DODGE_Regen
@onready var enemy_dodge_bar: ProgressBar = $P2_DODGE_Regen
@onready var result_label: Label = $ResultLabel

# Y position of each lane, computed once in _ready() from the viewport size.
var lane_ys: Array[float] = []
# X thresholds: player actions resolve at right_edge_x, enemy actions at left_edge_x.
var left_edge_x := 0.0
var right_edge_x := 0.0

var selected_lane := 1
var enemy_selected_lane := 1
var enemy_human_controlled := true
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
	player_hp_bar.max_value = _hp_max(player_unit)
	enemy_hp_bar.max_value = _hp_max(enemy_unit)
	player_unit._CURRENT_HP = _hp_max(player_unit)
	enemy_unit._CURRENT_HP = _hp_max(enemy_unit)
	player_hp_bar.value = player_unit._CURRENT_HP
	enemy_hp_bar.value = enemy_unit._CURRENT_HP
	player_atk_bar.max_value = _pa_max(player_unit)
	enemy_atk_bar.max_value = _pa_max(enemy_unit)
	player_atk_bar.value = player_unit._CURRENT_ATK
	enemy_atk_bar.value = enemy_unit._CURRENT_ATK
	player_dodge_bar.max_value = _dodge_max(player_unit)
	enemy_dodge_bar.max_value = _dodge_max(enemy_unit)
	player_dodge_bar.value = player_unit._CURRENT_DODGE
	enemy_dodge_bar.value = enemy_unit._CURRENT_DODGE
	result_label.visible = false
	enemy_lane_selector.visible = enemy_human_controlled


	_debug_print_stats()
# --- Helpers: per-unit "final" stat values ---------------------------------
# One helper per _STATS value read anywhere in this file. Where a matching
# global_stats constant exists, the final value is global_stats's shared baseline + the
# unit's own _STATS bonus (tune both players at once via global_stats, or one
# unit's standout trait via its _STATS resource); otherwise it just exposes
# the raw _STATS value under a consistent name. Every call site in this file
# reads its stat through one of these instead of touching unit._STATS directly.
func _hp_max(unit: MeshInstance3D) -> float:
	return unit._STATS._HP_MAX + global_stats._CONST_BASE_HP

func _start_hp(unit: MeshInstance3D) -> float:
	return _hp_max(unit)

func _damage(unit: MeshInstance3D) -> float:
	return global_stats._CONST_DAMAGE +((unit._STATS._FORCE - 1) * global_stats._CONST_BASE_MOD_DAMAGE)

func _defense_zone(unit: MeshInstance3D) -> float:
	return global_stats._CONST_DEFENSE_ZONE + ((unit._STATS._FORCE - 1) * unit._STATS._defense_range)

# Same reach, in pixels. Shared by _spawn_action (where a Defense stops) and
# _init_layout (where DefenseLine/EnemyDefenseLine draw that same stop point).
func _defense_reach_px(unit: MeshInstance3D) -> float:
	return clampf(_defense_zone(unit), 0.0, 1.0) * (right_edge_x - left_edge_x)

func _speed(unit: MeshInstance3D) -> float:
	return unit._STATS._SPEED

func _actions_speed(unit: MeshInstance3D) -> float:
	return global_stats._CONST_SPEED_ACTIONS + ((_speed(unit) -1) * unit._STATS._SPEED_OF_ACTIONS)

func _pa_max(unit: MeshInstance3D) -> float:
	return global_stats._CONST_PA_GAUGE + ((unit._STATS._SPEED - 1) * unit._STATS._PA_MAX)

func _pa_regen(unit: MeshInstance3D) -> float:
	return global_stats._CONST_PA_REGEN + ((unit._STATS._SPEED - 1) * unit._STATS._PA_REGEN)

func _fast_cost(unit: MeshInstance3D) -> float:
	return unit._STATS._FAST_COST

func _parry_cost(unit: MeshInstance3D) -> float:
	return unit._STATS._PARRY_COST

func _agility(unit: MeshInstance3D) -> float:
	return unit._STATS._AGILITY

## TODO: the global constants should be unit stats based
func _dodge_range(unit: MeshInstance3D) -> float:
	return global_stats._CONST_DODGE_RANGE + ((unit._STATS._AGILITY - 1) * global_stats._CONST_BASE_MOD_DODGE_RANGE)

func _dodge_max(unit: MeshInstance3D) -> float:
	return global_stats._CONST_DODGE_MAX_GAUGE + ((unit._STATS._AGILITY - 1) * global_stats._CONST_BASE_MOD_DODGE_MAX_GAUGE)

func _dodge_regen(unit: MeshInstance3D) -> float:
	return global_stats._CONST_DODGE_BASE_REGEN + ((unit._STATS._AGILITY - 1) * global_stats._CONST_BASE_MOD_DODGE_REGEN)

func _dodge_cost(unit: MeshInstance3D) -> float:
	return unit._STATS._DODGE_COST


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
	# Shows the reach of a dodge (see player_unit._STATS._DODGE_RANGE/_resolve_dodge):
	# any enemy action still inside this band when combat_dodge is pressed
	# gets nullified. Sized from the player's own stat block (editable on the
	# P1 node's Inspector) rather than a fixed value here.
	dodge_zone.position = Vector2(left_edge_x, edge_top)
	dodge_zone.size = Vector2(_dodge_range(player_unit), edge_bottom - edge_top)
	# Mirrors dodge_zone for the enemy side, from _dodge_range(enemy_unit).
	enemy_dodge_zone.position = Vector2(right_edge_x - _dodge_range(enemy_unit), edge_top)
	enemy_dodge_zone.size = Vector2(_dodge_range(enemy_unit), edge_bottom - edge_top)
	# DefenseLine/EnemyDefenseLine mark the exact spot a Defense stops at
	# (_defense_reach_px) - a thin bar, not a zone, since it's one stopping
	# point rather than a range like dodge.
	defense_line.position = Vector2(left_edge_x + _defense_reach_px(player_unit) - 1.5, edge_top)
	defense_line.size = Vector2(3.0, edge_bottom - edge_top)
	enemy_defense_line.position = Vector2(right_edge_x - _defense_reach_px(enemy_unit) - 1.5, edge_top)
	enemy_defense_line.size = Vector2(3.0, edge_bottom - edge_top)
	player_hitbox.position = Vector2(left_edge_x - 4.0, edge_top)
	player_hitbox.size = Vector2(6.0, edge_bottom - edge_top)
	enemy_hitbox.position = Vector2(right_edge_x - 2.0, edge_top)
	enemy_hitbox.size = Vector2(6.0, edge_bottom - edge_top)

	_update_lane_selector_position()
	_update_enemy_lane_selector_position()
	_update_lane_highlight()


# combat_action_fast spawns a Fast Strike, combat_parry spawns a Defense -
# both on whichever lane is currently selected (see _update_selected_lane)
# and both drawn from the same ATK charge, but each at its own cost
# (_STATS._FAST_COST/_STATS._PARRY_COST, see stats.gd/UnitStats) rather than
# always requiring/draining a full bar - firing leaves any remainder banked
# instead of resetting to 0. combat_dodge instead acts across every lane at
# once, gated by its own separate dodge charge at _STATS._DODGE_COST - see
# _resolve_dodge.
# toggle_p2_control flips P2 between this same kind of manual control (via
# the mirrored P2_* actions) and the AI auto-spawner in _update_enemy_spawner.
func _unhandled_input(event: InputEvent) -> void:
	if not combat_active:
		return
	if event.is_action_pressed("toggle_p2_control"):
		enemy_human_controlled = not enemy_human_controlled
		enemy_lane_selector.visible = enemy_human_controlled
		return
	if event.is_action_pressed("combat_action_fast"):
		if player_unit._is_atk_ready(_fast_cost(player_unit)):
			player_unit._consume_atk(_fast_cost(player_unit))
			_spawn_action(selected_lane, "player", "fast")
	elif event.is_action_pressed("combat_parry"):
		if player_unit._is_atk_ready(_parry_cost(player_unit)):
			player_unit._consume_atk(_parry_cost(player_unit))
			_spawn_action(selected_lane, "player", "defense")
	elif event.is_action_pressed("combat_dodge"):
		if player_unit._is_dodge_ready(_dodge_cost(player_unit)):
			player_unit._consume_dodge(_dodge_cost(player_unit))
			_resolve_dodge()
	elif not enemy_human_controlled:
		return
	elif event.is_action_pressed("P2_combat_action_fast"):
		if enemy_unit._is_atk_ready(_fast_cost(enemy_unit)):
			enemy_unit._consume_atk(_fast_cost(enemy_unit))
			_spawn_action(enemy_selected_lane, "enemy", "fast")
	elif event.is_action_pressed("P2_combat_parry"):
		if enemy_unit._is_atk_ready(_parry_cost(enemy_unit)):
			enemy_unit._consume_atk(_parry_cost(enemy_unit))
			_spawn_action(enemy_selected_lane, "enemy", "defense")
	elif event.is_action_pressed("P2_combat_dodge"):
		if enemy_unit._is_dodge_ready(_dodge_cost(enemy_unit)):
			enemy_unit._consume_dodge(_dodge_cost(enemy_unit))
			_resolve_enemy_dodge()


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


# Mirrors _update_selected_lane/_update_lane_selector_position for a human-
# controlled P2 - see enemy_human_controlled/toggle_p2_control.
func _update_enemy_selected_lane() -> void:
	if not enemy_human_controlled:
		return
	var new_lane := 1
	if Input.is_action_pressed("P2_lane_select_up"):
		new_lane = 0
	elif Input.is_action_pressed("P2_lane_select_down"):
		new_lane = lane_count - 1
	if new_lane != enemy_selected_lane:
		enemy_selected_lane = new_lane
		_update_enemy_lane_selector_position()


func _update_enemy_lane_selector_position() -> void:
	var y: float = lane_ys[enemy_selected_lane]
	enemy_lane_selector.position = Vector2(right_edge_x + 6.0, y - enemy_lane_selector.size.y * 0.5)


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
	# Defense stops at _defense_reach_px() - same reach as the DefenseLine/
	# EnemyDefenseLine markers drawn in _init_layout, so they stay in sync.
	var target_x: float
	if type_key == "defense":
		var reach: float = _defense_reach_px(unit)
		target_x = left_edge_x + reach if side == "player" else right_edge_x - reach
	else:
		target_x = right_edge_x if side == "player" else left_edge_x
	var dict_stats := {
		"lane": lane,
		"side": side,
		"type_key": type_key,
		"type": type,
		"speed": _actions_speed(unit),
		"damage": _damage(unit),
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
		_update_enemy_selected_lane()
		_update_enemy_spawner(delta)
		_update_actions(delta)
		player_flash_t = max(player_flash_t - delta, 0.0)
		enemy_flash_t = max(enemy_flash_t - delta, 0.0)
	# Regen ticks here (global_stats base + unit _STATS) instead of in p_1.gd/p_2.gd's
	# own _process, so global_stats stays the single place to rebalance both units.
	player_unit._CURRENT_ATK = min(player_unit._CURRENT_ATK + _pa_regen(player_unit) * delta, _pa_max(player_unit))
	enemy_unit._CURRENT_ATK = min(enemy_unit._CURRENT_ATK + _pa_regen(enemy_unit) * delta, _pa_max(enemy_unit))
	player_unit._CURRENT_DODGE = min(player_unit._CURRENT_DODGE + _dodge_regen(player_unit) * delta, _dodge_max(player_unit))
	enemy_unit._CURRENT_DODGE = min(enemy_unit._CURRENT_DODGE + _dodge_regen(enemy_unit) * delta, _dodge_max(enemy_unit))
	player_atk_bar.value = player_unit._CURRENT_ATK
	enemy_atk_bar.value = enemy_unit._CURRENT_ATK
	player_dodge_bar.value = player_unit._CURRENT_DODGE
	enemy_dodge_bar.value = enemy_unit._CURRENT_DODGE
	# Multiplies the authored hitbox color towards white while its flash timer is active.
	player_hitbox.modulate = Color(1, 1, 1).lerp(Color(2.5, 2.5, 2.5), player_flash_t / 0.15)
	enemy_hitbox.modulate = Color(1, 1, 1).lerp(Color(2.5, 2.5, 2.5), enemy_flash_t / 0.15)


# Regen-driven enemy AI: randomly picks between a Fast Strike and a Defense,
# then acts automatically (from a random lane) as soon as the enemy's ATK
# charge covers that action's own cost (_STATS._FAST_COST/_STATS._PARRY_COST),
# just like the player can - consuming only that cost. Disabled while a
# human is playing P2 - see enemy_human_controlled.
func _update_enemy_spawner(_delta: float) -> void:
	if enemy_human_controlled:
		return
	var type_key: String = ["fast", "defense"][randi() % 2]
	var cost: float = _fast_cost(enemy_unit) if type_key == "fast" else _parry_cost(enemy_unit)
	if not enemy_unit._is_atk_ready(cost):
		return
	enemy_unit._consume_atk(cost)
	var lane := randi() % lane_count
	_spawn_action(lane, "enemy", type_key)


# Moves every action (clamped to its own target_x - the opposite edge for a
# Fast Strike, its caster's _defense_zone() reach for a Defense) and resolves
# hits by comparing x against that target. A Defense that reaches its target without
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
# its short trip to its _defense_zone() reach, nullifying both with no damage dealt. If
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
				#consumed.append(i)
				consumed.append(j)
				break

	consumed.sort()
	consumed.reverse()
	for idx in consumed:
		actions[idx]["node"].queue_free()
		actions.remove_at(idx)


# Instant, all-lane panic button: nullifies every enemy action (in any lane)
# that's currently within the player's own _DODGE_RANGE of their hitbox
# (left_edge_x), with no damage dealt - unlike a Defense, this only saves you
# if the strike is already right on top of you, not one still crossing the field.
func _resolve_dodge() -> void:
	var i := actions.size() - 1
	while i >= 0:
		var dict_actions: Dictionary = actions[i]
		if dict_actions["side"] == "enemy" and dict_actions["x"] - left_edge_x <= _dodge_range(player_unit):
			dict_actions["node"].queue_free()
			actions.remove_at(i)
		i -= 1


# Mirrors _resolve_dodge for a human-controlled P2: nullifies every player
# action within enemy_unit._STATS._DODGE_RANGE of the enemy's own edge (right_edge_x).
func _resolve_enemy_dodge() -> void:
	var i := actions.size() - 1
	while i >= 0:
		var dict_actions: Dictionary = actions[i]
		if dict_actions["side"] == "player" and right_edge_x - dict_actions["x"] <= _dodge_range(enemy_unit):
			dict_actions["node"].queue_free()
			actions.remove_at(i)
		i -= 1


# Applies damage via the unit's own _take_damage() and triggers the hitbox
# flash. Player actions damage the enemy (reached the right/enemy edge) and
# vice versa. HP bars read back from the unit after damage so they never
# drift from the stat block that actually owns the value.
func _resolve_hit(dict_stats: Dictionary) -> void:
	var damage: float = dict_stats["damage"]
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


# Debug-only: dumps each unit's tunable "final" stats (the maxima/costs set
# in the Inspector, not the live CURRENT_* charge pools) to the Output panel
# once at combat start, color-coded by category so they're easy to scan.
func _debug_print_stats() -> void:
	_debug_print_unit_stats("P1", player_unit, "6699ff")
	_debug_print_unit_stats("P2", enemy_unit, "ff6666")


func _debug_print_unit_stats(label: String, unit: MeshInstance3D, header_hex: String) -> void:
	print_rich("[b][color=#%s]── %s stats ──[/color][/b]" % [header_hex, label])
	print_rich("  [color=lime][b]HP[/b][/color]    HP_MAX=%s  START_HP=%s CURRENT_HP=%s" \
		% [_hp_max(unit), _start_hp(unit), unit._CURRENT_HP])
	print_rich("  [color=yellow][b]ATK[/b][/color]   DMG=%s DEF_ZONE=%s SPEED=%s  REGEN_PA=%s  PA_MAX=%s  FAST_COST=%s  PARRY_COST=%s SPEED_OF_ACTIONS=%s" \
		% [_damage(unit), _defense_zone(unit),_speed(unit), _pa_regen(unit), _pa_max(unit), _fast_cost(unit), _parry_cost(unit), _actions_speed(unit)])
	print_rich("  [color=aqua][b]DODGE[/b][/color] AGILITY=%s  REGEN_DODGE=%s  DODGE_MAX=%s  DODGE_RANGE=%s  DODGE_COST=%s" \
		% [_agility(unit), _dodge_regen(unit), _dodge_max(unit), _dodge_range(unit), _dodge_cost(unit)])
