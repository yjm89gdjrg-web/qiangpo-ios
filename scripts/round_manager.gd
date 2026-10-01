extends Node

## 单机爆破回合管理器：进攻方玩家下包，防守方机器人阻止/拆包
const PLANT_TIME := 2.5
const DEFUSE_TIME := 5.0
const BOMB_TIME := 35.0
const SITE_RADIUS := 3.2
const RESULT_DISPLAY_TIME := 3.0
const MAX_ROUNDS := 13

var phase := "寻找目标点"
var bomb_planted := false
var bomb_timer := 0.0
var action_timer := 0.0
var result := ""
var result_timer := 0.0
var site_name := "A点"
var site_position := Vector3.ZERO
var player: Node3D
var sites: Array[Node3D] = []
var t_score := 0
var ct_score := 0
var round_number := 1
const Audio = preload("res://scripts/hot_update/audio_manager.gd")
var sfx = Audio.new()

func _ready() -> void:
	sfx.attach(self)
	player = get_tree().get_first_node_in_group("player")
	for n in get_tree().get_nodes_in_group("bomb_site"):
		sites.append(n)
	if sites.size() > 0:
		site_position = sites[0].global_position
		site_name = sites[0].get_meta("site_name", "A点")
	phase = "前往 %s" % site_name

func _process(delta: float) -> void:
	if result != "":
		result_timer += delta
		if result_timer >= RESULT_DISPLAY_TIME:
			_next_round()
		return
	if action_timer > 0.0:
		action_timer = max(action_timer - delta, 0.0)
		if action_timer <= 0.0:
			bomb_planted = true
			bomb_timer = BOMB_TIME
			phase = "炸弹已安装！"
			sfx.play("plant")
		return
	if action_timer < 0.0:
		action_timer += delta
		if action_timer >= 0.0:
			bomb_planted = false
			ct_score += 1
			result = "CT 方胜利！炸弹已拆除 (%d:%d)" % [t_score, ct_score]
			phase = result
			sfx.play("switch", -4.0)
			result_timer = 0.0
		return
	if bomb_planted:
		bomb_timer -= delta
		phase = "炸弹倒计时 %.1f 秒" % max(bomb_timer, 0.0)
		if bomb_timer <= 0.0:
			t_score += 1
			result = "T 方胜利！目标已爆炸 (%d:%d)" % [t_score, ct_score]
			phase = result
			sfx.play("explode")
			result_timer = 0.0
			return
	if not bomb_planted and player and player.global_position.distance_to(site_position) <= SITE_RADIUS:
		phase = "在 %s 按 E 下包" % site_name

func try_plant() -> bool:
	if result != "" or bomb_planted or action_timer > 0.0 or not player:
		return false
	if player.global_position.distance_to(site_position) > SITE_RADIUS:
		return false
	action_timer = PLANT_TIME
	phase = "下包中 %.1f 秒" % PLANT_TIME
	return true

func try_defuse() -> bool:
	if result != "" or not bomb_planted or action_timer > 0.0:
		return false
	# 当前单机版先允许玩家在目标点完成拆包，后续可接防守方角色
	if player and player.global_position.distance_to(site_position) <= SITE_RADIUS:
		action_timer = -DEFUSE_TIME
		phase = "拆包中 %.1f 秒" % DEFUSE_TIME
		return true
	return false

func cancel_action() -> void:
	if action_timer != 0.0:
		action_timer = 0.0
		phase = "炸弹已安装！" if bomb_planted else "下包被打断"

func get_status() -> String:
	if result != "":
		return result
	if action_timer < 0.0:
		var left: float = abs(action_timer)
		if left <= 0.0:
			bomb_planted = false
			result = "防守方胜利！炸弹已拆除"
			return result
		return "%s | 拆包 %.1f" % [phase, left]
	if action_timer > 0.0:
		return "%s | %.1f" % [phase, action_timer]
	return phase

func _reset_round() -> void:
	# 重置回合状态
	bomb_planted = false
	bomb_timer = 0.0
	action_timer = 0.0
	result = ""
	result_timer = 0.0
	phase = "前往 %s" % site_name
	# 重置玩家
	if player and is_instance_valid(player):
		player.hp = 100
		player.position = Vector3(0, 1, 8)  # 玩家出生点
		player.reset_mobile_input()
	# 重置所有 bots
	for bot in get_tree().get_nodes_in_group("bot"):
		if bot.has_method("reset_for_round"):
			bot.reset_for_round()

func _next_round() -> void:
	if round_number >= MAX_ROUNDS:
		# 游戏结束
		var winner := "T" if t_score > ct_score else "CT"
		if t_score == ct_score:
			winner = "平局"
		phase = "游戏结束！%s 获胜 (%d:%d)" % [winner, t_score, ct_score]
		result = phase
		return
	round_number += 1
	_reset_round()
