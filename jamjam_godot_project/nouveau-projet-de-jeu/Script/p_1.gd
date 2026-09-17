extends MeshInstance3D

@export var _STATS: UnitStats

### Runtime charge pools - start comes from _STATS; regen/max are ticked by
### turn.gd's _process (Global baseline + this unit's _STATS bonus). These
### are the only per-instance mutable values, so they stay on the node
### instead of the (potentially shared) UnitStats resource.
@onready var _CURRENT_HP
@export var _CURRENT_ATK = 0.0
@export var _CURRENT_DODGE = 0.0


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	_CURRENT_HP = _STATS._START_HP


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
