extends MeshInstance3D


### HP of the player.
@export var _HP_MAX = 15
@export var _CURRENT_HP=15
@export var _START_HP = 15

### Force
##Force that will be used to damage
@export var _FORCE = 1

### Agility of the player.
@export var _AGILITY = 1
@export var _REGEN_DODGE = 0.5

### Dodge charge: regenerates at _REGEN_DODGE units/sec, dodge fires (and
## consumes the charge) once it reaches _DODGE_COST.
@export var _DODGE_MAX = 1.0
@export var _CURRENT_DODGE = 0.0
### How much of the dodge charge a dodge consumes. Defaults to _DODGE_MAX so
## behavior is unchanged (must be full to fire) until tuned in the Inspector.
@export var _DODGE_COST = 1.0

### How close (in px) an enemy action must be to this unit's hitbox for a
## dodge to nullify it. Also sizes the DodgeZone visual in main_scene.tscn.
@export var _DODGE_RANGE = 40.0

### Speed of the player.
@export var _SPEED = 350
@export var _REGEN_ATK = 0.5

### ATK charge
## regenerates at _REGEN_ATK units/sec, attack fires (and consumes the charge) once it reaches its own action cost.
@export var _ATK_MAX = 1.0
@export var _CURRENT_ATK = 0.0
### Per-action ATK costs. Defaults to _ATK_MAX so behavior is unchanged
## (must be full to fire, fully consumed) until tuned in the Inspector -
## a cheaper action can then fire before the bar is completely full and
## leaves the remainder banked instead of resetting to 0.
@export var _FAST_COST = 1.0
@export var _PARRY_COST = 1.0


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	_CURRENT_HP = _HP_MAX


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	_CURRENT_ATK = min(_CURRENT_ATK + _REGEN_ATK * delta, _ATK_MAX)
	_CURRENT_DODGE = min(_CURRENT_DODGE + _REGEN_DODGE * delta, _DODGE_MAX)


func _take_damage(damage: float):
	if damage > 0:
		_CURRENT_HP -= damage
		if _CURRENT_HP <= 0:
			print ("You Died ! ")


func _is_atk_ready(cost: float) -> bool:
	return _CURRENT_ATK >= cost


func _consume_atk(cost: float) -> void:
	_CURRENT_ATK -= cost


func _is_dodge_ready(cost: float) -> bool:
	return _CURRENT_DODGE >= cost


func _consume_dodge(cost: float) -> void:
	_CURRENT_DODGE -= cost
