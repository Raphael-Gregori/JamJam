extends Resource
class_name UnitStats

## Force
##Force that will be used to damage
@export var _FORCE = 1
@export var _defense_range = 0.05
## Agility of the unit.
@export var _AGILITY = 1
## Speed of the unit.
## it influences the regen of the PA gauge, the PA gauge MAX
## and the speed of your actions on the line
@export var _SPEED = 1
## Actions Speed of the unit.
## it affects directly the speed of the action on the line
@export var _SPEED_OF_ACTIONS = 20

## HP of the player.
@export var _HP_MAX = 15
@export var _PA_REGEN = 0.05
var _START_HP

## FIXME : verify the linking of this variable
@export var _DODGE_MAX = 1.0
## TODO : debug this 
@export var _DODGE_COST = 1.0

## How close (in px) an enemy action must be to this unit's hitbox for a
## dodge to nullify it. Also sizes the DodgeZone visual in main_scene.tscn.
@export var _DODGE_RANGE = 40.0




@export var _PA_MAX = 0.2

### Per-action ATK costs. Defaults to _PA_MAX so behavior is unchanged
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
