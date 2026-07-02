# class_template.gd — 职业模板 Resource
# 定义角色的攻击模式、范围、索敌逻辑、职业特性
class_name ClassTemplate
extends Resource

## 职业ID
@export var class_id: String = ""

## 职业名称
@export var job_name: String = ""

## 主羁绊国家代号（nation_a~nation_f）
@export var class_group: String = ""

## 职业小分支
@export var subclass_id: String = ""

## 六维小羁绊标签
@export var stat_tags: Array[String] = []

## 阵营小羁绊标签
@export var alignment_tags: Array[String] = []

## 部署消耗 DP
@export var deploy_cost: int = 10

## --- 攻击模式 ---
enum AttackMode {
	MELEE_SINGLE,     ## 近战单体
	RANGED_SINGLE,    ## 远程单体
	MAGIC_AOE,        ## 魔法范围
	HEAL,             ## 治疗
	PIERCING_LINE     ## 穿透直线
}
@export var attack_mode: AttackMode = AttackMode.MELEE_SINGLE

## 目标类型（位掩码）
enum TargetType {
	GROUND = 1,
	AIR    = 2,
	BOTH   = 3
}
@export var target_type: int = TargetType.GROUND

## --- 攻击范围 ---
enum RangeShape {
	CIRCLE,      ## 圆形
	FAN,         ## 扇形
	LINE,        ## 直线
	GLOBAL,      ## 全图
	AREA         ## 矩形区域
}
@export var range_shape: RangeShape = RangeShape.CIRCLE

## 攻击范围半径（格子数）
@export var attack_range: float = 1.5

## 索敌范围半径（格子数）
@export var search_range: float = 5.0

## --- 属性 ---
@export var base_hp: int = 100
@export var base_atk: int = 15
@export var base_def: int = 5
@export var attack_speed: float = 1.0       ## 每秒攻击次数
@export var move_speed: float = 2.0         ## 行进速度（格/秒）
@export var collision_radius: float = 12.0  ## 地面圆形碰撞半径（像素）

## --- 状态修正 ---
## 驻扎状态下的属性修正
@export var stance_defense_bonus: float = 1.5    ## 防御倍率
@export var stance_range_bonus: float = 1.5      ## 攻击范围倍率
@export var stance_can_move: bool = false        ## 驻扎时是否可移动
@export var stance_is_rooted: bool = true        ## 驻扎时是否定身

## 行进状态下的属性修正
@export var march_move_speed_bonus: float = 1.5  ## 移动速度倍率
@export var march_attack_penalty: float = 0.5    ## 攻击力倍率

## --- 索敌优先级 ---
enum TargetPriority {
	NEAREST,        ## 最近
	LOWEST_HP,      ## 最低血量
	HIGHEST_ATK,    ## 最高攻击力
	FARTHEST,       ## 最远
	RANDOM          ## 随机
}
@export var target_priority: TargetPriority = TargetPriority.NEAREST

## 技能列表（技能ID数组）
@export var skill_ids: Array = []


## 返回攻击间隔（秒）
func get_attack_speed_interval() -> float:
	"""返回攻击间隔（秒）"""
	if attack_speed <= 0:
		return 999.0
	return 1.0 / attack_speed
