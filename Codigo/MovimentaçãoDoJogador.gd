extends CharacterBody2D

# ==============================================================================
# ⚔️ HOLLOW KNIGHT FINAL - WALL JUMP FORTE & ANIMAÇÕES DE OLHAR

enum State { IDLE, RUN, AIR, WALL_JUMPING, DASH }
var current_state: State = State.AIR

# --- CONFIGURAÇÕES ---

@export_group("Movimento")
@export var move_speed: float = 500.0

@export_group("Pulo e Gravidade")
@export var gravity_strength: float = 2500.0
@export var terminal_velocity: float = 1200.0
@export var jump_power: float = -800.0
@export var jump_cut_multiplier: float = 0.5
@export var double_jump_multiplier: float = 1.1

@export_group("Wall Jump (FORTE)")
# Aumentei para 700 (lateral) e -850 (altura)
@export var wall_jump_force: Vector2 = Vector2(700.0, -850.0)
# Tempo de travamento curto para manter agilidade
@export var wall_jump_lock_time: float = 0.16

@export_group("Dash")
@export var dash_velocity: float = 1300.0
@export var dash_duration: float = 0.15
@export var dash_cooldown: float = 0.6

@export_group("Timings")
@export var coyote_time: float = 0.15
@export var jump_buffer: float = 0.1

# --- VARIÁVEIS INTERNAS ---
var air_jumps_left: int = 1
var t_jump_buffer: float = 0.0
var t_coyote: float = 0.0
var t_dash_dur: float = 0.0
var t_dash_cd: float = 0.0
var t_wall_lock: float = 0.0 

var dash_queued: bool = false
var input_axis: float = 0.0
var facing_direction: int = 1

@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D

# ==============================================================================
# PHYSICS PROCESS
# ==============================================================================

func _physics_process(delta: float) -> void:
	# 1. Atualiza Timers
	if t_jump_buffer > 0: t_jump_buffer -= delta
	if t_coyote > 0: t_coyote -= delta
	if t_dash_dur > 0: t_dash_dur -= delta
	if t_dash_cd > 0: t_dash_cd -= delta
	if t_wall_lock > 0: t_wall_lock -= delta

	# 2. Ler Input (Bloqueado durante Wall Jump Lock)
	input_axis = Input.get_axis("esquerda", "direita")
	
	if t_wall_lock > 0:
		input_axis = 0 

	# 3. Orientação do Sprite
	if input_axis != 0:
		facing_direction = int(sign(input_axis))
		_flip_sprite(facing_direction == -1)

	# 4. Máquina de Estados
	match current_state:
		State.IDLE, State.RUN:
			_state_ground(delta)
		State.AIR:
			_state_air(delta)
		State.WALL_JUMPING:
			_state_wall_jump_locked(delta)
		State.DASH:
			_state_dash(delta)

	# 5. Processa Ações
	_handle_jump()
	_handle_dash()
	
	move_and_slide()
	_update_anim()

# ==============================================================================
# LÓGICA DE ESTADOS
# ==============================================================================

func _state_ground(delta: float) -> void:
	velocity.y += gravity_strength * delta
	
	if input_axis != 0:
		velocity.x = input_axis * move_speed
		current_state = State.RUN
	else:
		velocity.x = 0.0
		current_state = State.IDLE
		
	if not is_on_floor():
		current_state = State.AIR
		t_coyote = coyote_time
	
	if is_on_floor():
		air_jumps_left = 1
		# Zera cooldown do dash ao tocar o chão
		if t_dash_cd > 0.1: 
			t_dash_cd = 0.0

func _state_air(delta: float) -> void:
	velocity.y += gravity_strength * delta
	velocity.y = min(velocity.y, terminal_velocity)
	
	velocity.x = input_axis * move_speed
	
	if is_on_floor():
		current_state = State.IDLE

func _state_wall_jump_locked(delta: float) -> void:
	velocity.y += gravity_strength * delta
	
	# Permite voltar para a parede rapidamente reduzindo a inércia lateral
	velocity.x = move_toward(velocity.x, 0, 5.0 * delta)

	if t_wall_lock <= 0:
		current_state = State.AIR 

func _state_dash(_delta: float) -> void:
	velocity.y = 0.0
	velocity.x = facing_direction * dash_velocity
	
	if t_dash_dur <= 0:
		velocity.x = 0
		current_state = State.AIR

# ==============================================================================
# PULO (COM RESET INFINITO NA PAREDE)
# ==============================================================================

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("dash") and t_dash_cd <= 0:
		dash_queued = true

func _handle_jump() -> void:
	if Input.is_action_just_pressed("pular"):
		t_jump_buffer = jump_buffer
	
	if t_jump_buffer > 0:
		# 1. Pulo do Chão
		if is_on_floor() or t_coyote > 0:
			velocity.y = jump_power
			_reset_jump_vars()
			current_state = State.AIR
			
		# 2. WALL JUMP (Reseta tudo)
		elif is_on_wall() and not is_on_floor():
			var wall_normal = get_wall_normal()
			var kick_dir = int(sign(wall_normal.x))
			
			# Aplica Força (Mais forte agora)
			velocity.x = kick_dir * wall_jump_force.x
			velocity.y = wall_jump_force.y
			
			# Reset de Habilidades
			air_jumps_left = 1
			t_dash_cd = 0.0
			
			# Trava controle brevemente
			t_wall_lock = wall_jump_lock_time
			current_state = State.WALL_JUMPING
			
			facing_direction = kick_dir
			_flip_sprite(facing_direction == -1)
			
			_reset_jump_vars()
			
		# 3. Pulo Duplo
		elif air_jumps_left > 0 and current_state == State.AIR:
			velocity.y = jump_power * double_jump_multiplier
			air_jumps_left -= 1
			_reset_jump_vars()

	# Pulo variável (Jump Cut)
	if Input.is_action_just_released("pular") and velocity.y < 0:
		velocity.y *= jump_cut_multiplier

func _reset_jump_vars() -> void:
	t_jump_buffer = 0.0
	t_coyote = 0.0

func _handle_dash() -> void:
	if dash_queued:
		dash_queued = false
		current_state = State.DASH
		t_dash_dur = dash_duration
		t_dash_cd = dash_cooldown
		if input_axis != 0: 
			facing_direction = int(sign(input_axis))

# ==============================================================================
# ANIMAÇÕES (AGORA COM OLHAR CIMA/BAIXO)
# ==============================================================================

func _update_anim() -> void:
	if not sprite: return
	var anim = "idle"
	
	match current_state:
		State.RUN: 
			anim = "andar"
		State.DASH: 
			anim = "dash"
		State.AIR, State.WALL_JUMPING: 
			anim = "pular" if velocity.y < 0 else "caindo"
		State.IDLE:
			# Lógica de olhar parada no chão
			if Input.is_action_pressed("cima"):
				anim = "olhar_cima"
			elif Input.is_action_pressed("baixo"):
				anim = "olhar_baixo"
			else:
				anim = "idle"
	
	# Só toca se a animação existir para evitar erros
	if sprite.sprite_frames.has_animation(anim):
		if sprite.animation != anim:
			sprite.play(anim)

func _flip_sprite(flip: bool) -> void:
	if sprite: sprite.flip_h = flip
