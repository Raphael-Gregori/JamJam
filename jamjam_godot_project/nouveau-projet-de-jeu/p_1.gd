extends MeshInstance3D


### HP of the player.
@export var _HP_MAX = 15
@export var _CURRENT_HP=15
@export var _START_HP = 15

### Force that will be used to damage
@export var _FORCE = 1

### Agility of the player.
@export var _AGILITY = 1
@export var _REGEN_DODGE = 0.5

### Speed of the player.
@export var _SPEED = 1
@export var _REGEN_ATK = 0.5


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	_CURRENT_HP = _HP_MAX


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass


func _take_damage(damage: float):
	if damage > 0:
		_CURRENT_HP -= damage
		if _CURRENT_HP <= 0:
			print ("You Died ! ")
