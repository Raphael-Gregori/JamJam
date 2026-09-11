extends Resource
class_name UnitStats


### HP of the player.
@export var _HP_MAX = 15
@export var _REGEN_ATK = 0.5
@export var _START_HP = 15

### Dodge charge: regenerates at _REGEN_DODGE units/sec, dodge fires (and
## consumes the charge) once it reaches _DODGE_COST.
@export var _DODGE_MAX = 1.0
### How much of the dodge charge a dodge consumes. Defaults to _DODGE_MAX so
## behavior is unchanged (must be full to fire) until tuned in the Inspector.
@export var _DODGE_COST = 1.0

### How close (in px) an enemy action must be to this unit's hitbox for a
## dodge to nullify it. Also sizes the DodgeZone visual in main_scene.tscn.
@export var _DODGE_RANGE = 40.0

### Force
##Force that will be used to damage
@export var _FORCE = 1

### Speed of the unit.
@export var _SPEED = 350

### ATK charge
## regenerates at _REGEN_ATK units/sec, attack fires (and consumes the charge) once it reaches its own action cost.
@export var _ATK_MAX = 1.0

### Per-action ATK costs. Defaults to _ATK_MAX so behavior is unchanged
## (must be full to fire, fully consumed) until tuned in the Inspector -
## a cheaper action can then fire before the bar is completely full and
## leaves the remainder banked instead of resetting to 0.
@export var _FAST_COST = 1.0
@export var _PARRY_COST = 1.0

### Agility of the unit.
@export var _AGILITY = 1
@export var _REGEN_DODGE = 0.5
