# ResourceManager.gd — 部署资源管理
# 负责部署点数的增长、消耗、查询
extends Node

const M = "Resource"

signal dp_changed(current_dp: int, max_dp: int)

## 部署资源（Deployment Points）
var current_dp: int = 0
var max_dp: int = 100
var base_max_dp: int = 100
var dp_regen_rate: float = 1.0      # 每秒恢复DP
var dp_regen_timer: float = 0.0
var dp_regen_enabled: bool = true


func _process(delta: float) -> void:
	if not dp_regen_enabled:
		return
	# 准备阶段不自然增长（部署阶段 DP 固定）
	if BattleManager.state == BattleManager.BattleState.PREPARING:
		return
	if current_dp < max_dp:
		dp_regen_timer += delta
		while dp_regen_timer >= 1.0 / dp_regen_rate:
			dp_regen_timer -= 1.0 / dp_regen_rate
			current_dp = min(current_dp + 1, max_dp)
			dp_changed.emit(current_dp, max_dp)


func can_afford(cost: int) -> bool:
	"""检查是否有足够的DP"""
	return current_dp >= cost


func spend(cost: int) -> bool:
	"""消耗DP，返回是否成功"""
	if current_dp >= cost:
		current_dp -= cost
		dp_changed.emit(current_dp, max_dp)
		return true
	return false


func refund(amount: int) -> void:
	"""退还DP（撤退时）"""
	current_dp = min(current_dp + amount, max_dp)
	dp_changed.emit(current_dp, max_dp)


func reset_dp(initial: int = 20, max_val: int = 100) -> void:
	"""重置DP（新战斗开始时）"""
	current_dp = initial
	base_max_dp = max_val
	max_dp = max_val
	dp_regen_timer = 0.0
	dp_regen_enabled = true
	dp_changed.emit(current_dp, max_dp)


func set_regen_enabled(enabled: bool) -> void:
	dp_regen_enabled = enabled


func apply_synergy_modifiers(modifiers: Dictionary) -> void:
	"""应用羁绊带来的固定资源修正"""
	var max_dp_bonus := int(round(float(modifiers.get("max_dp_bonus", 0.0))))
	var next_max_dp := maxi(1, base_max_dp + max_dp_bonus)
	if next_max_dp == max_dp:
		return
	max_dp = next_max_dp
	current_dp = mini(current_dp, max_dp)
	dp_changed.emit(current_dp, max_dp)
