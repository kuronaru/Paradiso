# afk_tower_manager.gd — AFK爬塔自动战斗逻辑
# 与自走棋战斗完全隔离，只运行轻量的英雄/敌人交替动作和切敌流程。
class_name AfkTowerManager
extends Node

signal state_changed(state: Dictionary)
signal enemy_defeated(enemy_name: String, floor: int, enemy_index: int)
signal floor_changed(floor: int)

const ENEMIES_PER_FLOOR := 3
const HERO_ATTACK_INTERVAL := 1.6
const ENEMY_ACTION_INTERVAL := 1.0
const CLICK_ATTACK_SPEED_MULTIPLIER := 1.5
const CLICK_BOOST_DURATION := 1.2
const ENEMY_NAMES := ["巡塔卫兵", "沉默术士", "结界守卫", "塔心幻影"]

var current_floor: int = 1
var current_enemy_index: int = 0
var defeated_enemy_count: int = 0

var enemy_name: String = ""
var enemy_hp: float = 0.0
var enemy_max_hp: float = 1.0
var combat_turn: String = "hero"
var turn_timer: float = HERO_ATTACK_INTERVAL
var click_boost_timer: float = 0.0
var status_text: String = "英雄小队准备攻击"

var party_data: Array = []
var team_attack: int = 1
var running: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


## 运行自动战斗计时。
func _process(delta: float) -> void:
	if not running or enemy_hp <= 0.0:
		return

	if click_boost_timer > 0.0:
		click_boost_timer = maxf(0.0, click_boost_timer - delta)

	var speed_multiplier: float = CLICK_ATTACK_SPEED_MULTIPLIER if combat_turn == "hero" and click_boost_timer > 0.0 else 1.0
	turn_timer -= delta * speed_multiplier
	if turn_timer <= 0.0:
		if combat_turn == "hero":
			_perform_hero_attack()
		else:
			_perform_enemy_action()

	_emit_state()


## 设置当前AFK小队。
func configure_party(next_party: Array) -> void:
	party_data.clear()
	for card in next_party:
		if card is Dictionary:
			party_data.append((card as Dictionary).duplicate(true))
	team_attack = maxi(1, CombatPowerCalculator.calculate_team_attack(party_data))
	_emit_state()


## 开始或重置自动战斗。
func start_battle(floor: int = 1, enemy_index: int = 0) -> void:
	current_floor = maxi(1, floor)
	current_enemy_index = clampi(enemy_index, 0, ENEMIES_PER_FLOOR - 1)
	defeated_enemy_count = 0
	running = true
	_spawn_current_enemy()


## 点击鼓舞，短暂提高英雄攻击频率。
func apply_click_boost() -> void:
	click_boost_timer = CLICK_BOOST_DURATION
	status_text = "点击鼓舞：英雄攻击频率 +50%"
	_emit_state()


## 重新计算小队攻击力。
func refresh_team_attack() -> void:
	team_attack = maxi(1, CombatPowerCalculator.calculate_team_attack(party_data))
	_emit_state()


## 获取当前状态快照。
func get_state() -> Dictionary:
	return {
		"current_floor": current_floor,
		"current_enemy_index": current_enemy_index,
		"enemies_per_floor": ENEMIES_PER_FLOOR,
		"defeated_enemy_count": defeated_enemy_count,
		"enemy_name": enemy_name,
		"enemy_hp": enemy_hp,
		"enemy_max_hp": enemy_max_hp,
		"combat_turn": combat_turn,
		"turn_timer": turn_timer,
		"click_boost_timer": click_boost_timer,
		"status_text": status_text,
		"team_attack": team_attack,
		"required_attack": CombatPowerCalculator.get_required_attack(current_floor),
		"preview_reward_gold": CombatPowerCalculator.get_preview_reward_gold(current_floor),
		"running": running
	}


## 生成当前敌人。
func _spawn_current_enemy() -> void:
	enemy_name = ENEMY_NAMES[current_enemy_index % ENEMY_NAMES.size()]
	enemy_max_hp = float(_get_enemy_max_hp(current_floor, current_enemy_index))
	enemy_hp = enemy_max_hp
	combat_turn = "hero"
	turn_timer = HERO_ATTACK_INTERVAL
	status_text = "英雄小队准备攻击"
	_emit_state()


## 英雄出手，敌人受到伤害。
func _perform_hero_attack() -> void:
	var damage: int = maxi(1, team_attack)
	enemy_hp = maxf(0.0, enemy_hp - float(damage))
	if enemy_hp <= 0.0:
		status_text = "英雄小队造成 %d 伤害，击败 %s" % [damage, enemy_name]
		_advance_to_next_enemy()
		return

	combat_turn = "enemy"
	turn_timer = ENEMY_ACTION_INTERVAL
	status_text = "英雄小队造成 %d 伤害" % damage


## 敌人出手只播放动作，不造成伤害。
func _perform_enemy_action() -> void:
	combat_turn = "hero"
	turn_timer = HERO_ATTACK_INTERVAL
	status_text = "%s 发动攻击，但未造成伤害" % enemy_name


## 击败敌人后自动进入下一个敌人。
func _advance_to_next_enemy() -> void:
	defeated_enemy_count += 1
	enemy_defeated.emit(enemy_name, current_floor, current_enemy_index)
	current_enemy_index += 1
	if current_enemy_index >= ENEMIES_PER_FLOOR:
		current_enemy_index = 0
		current_floor += 1
		floor_changed.emit(current_floor)
	call_deferred("_spawn_current_enemy")


## 当前敌人血量。
func _get_enemy_max_hp(floor: int, enemy_index: int) -> int:
	var floor_scale := 1.0 + float(maxi(0, floor - 1)) * 0.35
	var index_scale := 1.0 + float(enemy_index) * 0.25
	return int(round(220.0 * floor_scale * index_scale))


func _emit_state() -> void:
	state_changed.emit(get_state())
