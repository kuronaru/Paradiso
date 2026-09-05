# class_template.gd — 职业模板 Resource
# 定义角色的攻击模式、范围、索敌逻辑、职业特性
class_name ClassTemplate
extends Resource

## 职业ID
@export var class_id: String = ""

## 职业名称
@export var job_name: String = ""

## 主羁绊临时代号（当前仍沿用 class_group 字段）
@export var class_group: String = ""

## 职业小分支
@export var subclass_id: String = ""
@export var visual_id: String = ""

## 六维小羁绊标签
@export var stat_tags: Array[String] = []

## 阵营小羁绊标签
@export var alignment_tags: Array[String] = []

## 特性小羁绊标签（FLYING / SUPPORT / SHAPESHIFTER；ADVANCED 由星级动态判定）
@export var trait_tags: Array[String] = []

## 自走棋英雄骨架：固定等阶、当前模式羁绊与特质。
@export var trait_tier: int = 1
@export var autochess_synergy_ids: Array[String] = []
@export var auto_trait_ids: Array[String] = []

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
@export var collision_radius: float = 12.0  ## 地面圆形碰撞参考半径；英雄会按当前格宽缩放

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
	RANDOM,         ## 随机
	HIGHEST_HP,     ## 最高当前生命
	LOWEST_HP_RATIO,        ## 最低生命比例
	HIGHEST_HP_RATIO,       ## 最高生命比例
	LOWEST_MAX_HP,          ## 最低最大生命
	HIGHEST_MAX_HP,         ## 最高最大生命
	LOWEST_MISSING_HP,      ## 最少已损生命
	HIGHEST_MISSING_HP,     ## 最多已损生命
	LOWEST_ATK,             ## 最低攻击力
	LOWEST_DEF,             ## 最低防御力
	HIGHEST_DEF,            ## 最高防御力
	LOWEST_ATTACK_SPEED,    ## 最低攻速
	HIGHEST_ATTACK_SPEED,   ## 最高攻速
	LOWEST_MOVE_SPEED,      ## 最低移速
	HIGHEST_MOVE_SPEED,     ## 最高移速
	LOWEST_ATTACK_RANGE,    ## 最低攻击范围
	HIGHEST_ATTACK_RANGE,   ## 最高攻击范围
	LOWEST_SEARCH_RANGE,    ## 最低索敌范围
	HIGHEST_SEARCH_RANGE,   ## 最高索敌范围
	LOWEST_LEVEL,           ## 最低等级
	HIGHEST_LEVEL,          ## 最高等级
	LOWEST_STAR_LEVEL,      ## 最低星级
	HIGHEST_STAR_LEVEL,     ## 最高星级
	GROUND_FIRST,           ## 优先地面单位
	AIRBORNE_FIRST          ## 优先空中单位
}
@export var target_priority: TargetPriority = TargetPriority.NEAREST

## 顺序与 TargetPriority 严格一致；旧枚举值 0..4 保持不变。
const TARGET_PRIORITY_KEYS := [
	"nearest", "lowest_hp", "highest_attack", "farthest", "random",
	"highest_hp", "lowest_hp_ratio", "highest_hp_ratio",
	"lowest_max_hp", "highest_max_hp", "lowest_missing_hp", "highest_missing_hp",
	"lowest_attack", "lowest_defense", "highest_defense",
	"lowest_attack_speed", "highest_attack_speed", "lowest_move_speed", "highest_move_speed",
	"lowest_attack_range", "highest_attack_range", "lowest_search_range", "highest_search_range",
	"lowest_level", "highest_level", "lowest_star_level", "highest_star_level",
	"ground_first", "airborne_first",
]

const TARGET_PRIORITY_DISPLAY_NAMES := [
	"最近", "最低当前生命", "最高攻击", "最远", "随机",
	"最高当前生命", "最低生命比例", "最高生命比例",
	"最低最大生命", "最高最大生命", "最少已损生命", "最多已损生命",
	"最低攻击", "最低防御", "最高防御",
	"最低攻速", "最高攻速", "最低移速", "最高移速",
	"最低攻击范围", "最高攻击范围", "最低索敌范围", "最高索敌范围",
	"最低等级", "最高等级", "最低星级", "最高星级",
	"地面优先", "空中优先",
]

const TARGET_PRIORITY_ALIASES := {
	"lowest_current_hp": "lowest_hp",
	"highest_current_hp": "highest_hp",
	"lowest_atk": "lowest_attack",
	"highest_atk": "highest_attack",
	"lowest_def": "lowest_defense",
	"highest_def": "highest_defense",
	"lowest_star": "lowest_star_level",
	"highest_star": "highest_star_level",
	"least_injured": "lowest_missing_hp",
	"most_injured": "highest_missing_hp",
	"grounded_first": "ground_first",
	"air_first": "airborne_first",
}

## 技能列表（技能ID数组）
@export var skill_ids: Array = []


## 返回攻击间隔（秒）
func get_attack_speed_interval() -> float:
	"""返回攻击间隔（秒）"""
	if attack_speed <= 0:
		return 999.0
	return 1.0 / attack_speed


## 将数据文件中的写法归一化为公开键，未知值安全回退到最近。
static func normalize_target_priority_key(value: String) -> String:
	var key := value.strip_edges().to_lower().replace("-", "_").replace(" ", "_")
	key = str(TARGET_PRIORITY_ALIASES.get(key, key))
	return key if key in TARGET_PRIORITY_KEYS else "nearest"


## 将数据键转为枚举值。
static func target_priority_from_key(value: String) -> int:
	return TARGET_PRIORITY_KEYS.find(normalize_target_priority_key(value))


## 将枚举值转为统一数据键。
static func target_priority_key(value: int) -> String:
	if value < 0 or value >= TARGET_PRIORITY_KEYS.size():
		return "nearest"
	return str(TARGET_PRIORITY_KEYS[value])


## 返回界面使用的索敌优先级名称。
static func target_priority_display_name(value: int) -> String:
	if value < 0 or value >= TARGET_PRIORITY_DISPLAY_NAMES.size():
		return "未知"
	return str(TARGET_PRIORITY_DISPLAY_NAMES[value])
