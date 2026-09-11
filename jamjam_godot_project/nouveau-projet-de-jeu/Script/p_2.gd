extends MeshInstance3D

@export var _STATS: UnitStats

### Runtime charge pools - start/regen/max/cost all come from _STATS; these
### are the only per-instance mutable values, so they stay on the node
### instead of the (potentially shared) UnitStats resource.
@export var _CURRENT_HP = 15
@export var _CURRENT_ATK = 0.0
@export var _CURRENT_DODGE = 0.0


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	_CURRENT_HP = minf(_STATS._START_HP, _STATS._HP_MAX)


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	_CURRENT_ATK = min(_CURRENT_ATK + _STATS._REGEN_ATK * delta, _STATS._ATK_MAX)
	_CURRENT_DODGE = min(_CURRENT_DODGE + _STATS._REGEN_DODGE * delta, _STATS._DODGE_MAX)


func _take_damage(damage: float):
	if damage > 0:
		_CURRENT_HP -= damage
		if _CURRENT_HP <= 0:
			print ("It Died ! ")


func _is_atk_ready(cost: float) -> bool:
	return _CURRENT_ATK >= cost


func _consume_atk(cost: float) -> void:
	_CURRENT_ATK -= cost


func _is_dodge_ready(cost: float) -> bool:
	return _CURRENT_DODGE >= cost


func _consume_dodge(cost: float) -> void:
	_CURRENT_DODGE -= cost
