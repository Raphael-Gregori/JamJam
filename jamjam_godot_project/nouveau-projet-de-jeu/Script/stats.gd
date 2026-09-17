extends Resource
class_name UnitStats

## Force
##Force that will be used to damage
@export var _FORCE = 1
@export var _defense_range = 0.05
## Agility of the unit.
@export var _AGILITY = 1
## Speed of the unit.
## it change the regen of the dodge regeneration
@export var _SPEED = 350

## HP of the player.
@export var _HP_MAX = 15
@export var _REGEN_ATK = 0.5
var _START_HP

## Dodge charge: regenerates at _REGEN_DODGE units/sec, dodge fires (and
## consumes the charge) once it reaches _DODGE_COST.
@export var _DODGE_MAX = 1.0
## How much of the dodge charge a dodge consumes. Defaults to _DODGE_MAX so
## behavior is unchanged (must be full to fire) until tuned in the Inspector.
@export var _DODGE_COST = 1.0

## How close (in px) an enemy action must be to this unit's hitbox for a
## dodge to nullify it. Also sizes the DodgeZone visual in main_scene.tscn.
@export var _DODGE_RANGE = 40.0



## ATK charge
## regenerates at _REGEN_ATK units/sec, attack fires (and consumes the charge) once it reaches its own action cost.
@export var _ATK_MAX = 1.0

### Per-action ATK costs. Defaults to _ATK_MAX so behavior is unchanged
## :(must be full to fire, fully consumed) until tuned in the Inspector -
## a cheaper action can then fire before the bar is completely full and
## leaves the remainder banked instead of resetting to 0.
@export var _FAST_COST = 1.0
@export var _PARRY_COST = 1.0




const _REGEN_DODGE_PER_SPEED = 1.0 / 700.0
### Dodge regen is derived from _SPEED (rather than tuned independently) so a
## unit's mobility stat drives both its movement and how fast it can dodge
## again. Tune dodge regen per-unit via _SPEED, not this constant.
var _REGEN_DODGE: float:
	get: return _SPEED * _REGEN_DODGE_PER_SPEED
