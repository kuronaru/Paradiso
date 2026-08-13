class_name AutoTraitCombatPassive
extends UnitPassive


func setup(p_hero: UnitBase, config: Dictionary = {}) -> void:
	super.setup(p_hero, config)
	passive_id = "auto_traits"
	display_name = "自走棋特质"
	if hero is HeroUnit and AutoTraitManager:
		modifiers = AutoTraitManager.get_combat_modifiers(hero as HeroUnit)


func before_deal_damage(context: Dictionary) -> void:
	if hero is HeroUnit and AutoTraitManager:
		AutoTraitManager.before_deal_damage(hero as HeroUnit, context)


func after_deal_damage(context: Dictionary) -> void:
	if hero is HeroUnit and AutoTraitManager:
		AutoTraitManager.after_deal_damage(hero as HeroUnit, context)


func after_skill_used(_context: Dictionary) -> void:
	if hero is HeroUnit and AutoTraitManager:
		AutoTraitManager.notify_skill_used(hero as HeroUnit)


func before_death(_context: Dictionary) -> void:
	if hero is HeroUnit and AutoTraitManager:
		AutoTraitManager.notify_self_defeated(hero as HeroUnit)
