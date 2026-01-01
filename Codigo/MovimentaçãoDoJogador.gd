extends CharacterBody2D

# --- SINAIS ---
signal state_changed(previous_state: State, new_state: State)

# --- MÁQUINA DE ESTADOS ---
enum State { IDLE, RUN, AIR, WALL_SLIDE, WALL_JUMPING, DASH }
var current_state: State = State.AIR

# --- CONFIGURAÇÕES (Estilo Hollow Knight) ---
@export_group("Movimento")
@export var move_speed: float = 500.0
@export var acceleration: float = 0.0 # Zero para movimento instantâneo (Snappy)

@export_group("Pulo e Gravidade")
@export var gravity_strength: float = 2000.0 
@export var terminal_velocity: float = 1200.0
@export var jump_force: float = -800.0
@export var jump_cut_multiplier: float = 0.5 
@export var double_jump_multiplier: float = 0.9
@export var max_air_jumps: int = 1

@export_group("Mecânicas de Parede")
@export var wall_slide_speed: float = 300.0
@export var wall_jump_force: Vector2 = Vector2(700.0, -850.0)
@export var wall_jump_lock_time: float = 0.16 

@export_group("Dash")
@export var dash_velocity: float = 1300.0
@export var dash_duration: float = 0.15
@export var dash_cooldown: float = 0.6 

@export_group("Timings")
@export var coyote_time: float = 0.1 
@export var jump_buffer_time: float = 0.1

# --- VARIÁVEIS INTERNAS ---
var air_jumps_left: int = 0
var input_axis: float = 0.0
var facing_direction: int = 1 # 1 = Direita, -1 = Esquerda

# Timers
var t_jump_buffer: float = 0.0
var t_coyote: float = 0.0
var t_dash_dur: float = 0.0
var t_dash_cd: float = 0.0
var t_wall_lock: float = 0.0

# Dash e Wall
var dash_queued: bool = false
var dash_direction: Vector2 = Vector2.ZERO

@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D

func _ready() -> void:
	air_jumps_left = max_air_jumps

func _physics_process(delta: float) -> void:
	# 1. Atualizar Timers
	_update_timers(delta)
	
	# 2. Ler Input (Bloqueado se estiver travado pelo Wall Jump)
	input_axis = Input.get_axis("esquerda", "direita")
	if t_wall_lock > 0:
		input_axis = 0 

	# 3. Gerenciar Orientação (Flip)
	# Apenas vira se houver input E não estiver travado em animações de parede
	if input_axis != 0 and current_state != State.WALL_JUMPING and current_state != State.WALL_SLIDE:
		facing_direction = int(sign(input_axis))
		_flip_sprite(facing_direction == -1)

	# 4. Máquina de Estados
	match current_state:
		State.IDLE:
			_state_idle(delta)
		State.RUN:
			_state_run(delta)
		State.AIR:
			_state_air(delta)
		State.WALL_SLIDE:
			_state_wall_slide(delta)
		State.WALL_JUMPING:
			_state_wall_jumping(delta)
		State.DASH:
			_state_dash(delta)

	# 5. Processar Pulo e Dash
	_handle_jump_input()
	
	move_and_slide()
	
	# 6. Atualizar Animações (Separado para organização)
	_update_anim()

# ==============================================================================
# LÓGICA DE ESTADOS
# ==============================================================================

func _state_idle(_delta: float) -> void:
	velocity.y = 0.0 
	velocity.x = 0.0
	
	if input_axis != 0:
		_change_state(State.RUN)
	elif not is_on_floor():
		_change_state(State.AIR)
		t_coyote = coyote_time
		
	_check_dash_input()

func _state_run(_delta: float) -> void:
	velocity.y = 0.0
	velocity.x = input_axis * move_speed 
	
	if input_axis == 0:
		_change_state(State.IDLE)
	elif not is_on_floor():
		_change_state(State.AIR)
		t_coyote = coyote_time
		
	_check_dash_input()

func _state_air(delta: float) -> void:
	velocity.y += gravity_strength * delta
	velocity.y = min(velocity.y, terminal_velocity)
	velocity.x = input_axis * move_speed
	
	if is_on_floor():
		_change_state(State.IDLE)
	
	# Detectar Wall Slide
	elif is_on_wall() and velocity.y > 0:
		var wall_normal_x = get_wall_normal().x
		# Entra se estiver caindo e empurrando contra a parede
		if sign(input_axis) == -sign(wall_normal_x):
			_change_state(State.WALL_SLIDE)
			
	_check_dash_input()

func _state_wall_slide(_delta: float) -> void:
	var wall_normal = get_wall_normal()
	
	# Força física leve contra a parede para não "desgrudar"
	velocity.x = -wall_normal.x * 50.0
	velocity.y = wall_slide_speed
	
	# Visual: Personagem olha para a parede enquanto desliza (Estilo HK)
	# wall_normal.x é 1 (parede a esquerda) ou -1 (parede a direita).
	# Para olhar para a parede, facing direction deve ser oposto a normal.
	facing_direction = int(-wall_normal.x)
	_flip_sprite(facing_direction == -1)
	
	if is_on_floor():
		_change_state(State.IDLE)
	# Se soltar o input contra a parede, cai
	elif sign(input_axis) != -sign(wall_normal.x):
		_change_state(State.AIR)
		
	_check_dash_input()

func _state_wall_jumping(delta: float) -> void:
	velocity.y += gravity_strength * delta
	# Atrito aéreo alto para recuperar controle rápido
	velocity.x = move_toward(velocity.x, 0, 500.0 * delta)
	
	if t_wall_lock <= 0:
		_change_state(State.AIR)
		
	_check_dash_input()

func _state_dash(_delta: float) -> void:
	velocity.y = 0.0
	velocity.x = dash_direction.x * dash_velocity
	
	if t_dash_dur <= 0:
		velocity.x = dash_direction.x * move_speed * 0.5
		_change_state(State.AIR)

# ==============================================================================
# INPUT E AÇÕES
# ==============================================================================

func _check_dash_input() -> void:
	if Input.is_action_just_pressed("dash") and t_dash_cd <= 0:
		dash_queued = true
		_perform_dash()

func _handle_jump_input() -> void:
	if Input.is_action_just_pressed("pular"):
		t_jump_buffer = jump_buffer_time

	if Input.is_action_just_released("pular") and velocity.y < 0:
		velocity.y *= jump_cut_multiplier

	if t_jump_buffer > 0:
		# 1. Pulo Normal / Coyote
		if is_on_floor() or t_coyote > 0:
			velocity.y = jump_force
			t_jump_buffer = 0
			t_coyote = 0
			_change_state(State.AIR)
		
		# 2. Wall Jump
		elif current_state == State.WALL_SLIDE or (is_on_wall() and not is_on_floor()):
			var wall_normal = get_wall_normal()
			var jump_dir = int(wall_normal.x) 
			
			velocity.x = jump_dir * wall_jump_force.x
			velocity.y = wall_jump_force.y
			
			t_wall_lock = wall_jump_lock_time
			facing_direction = jump_dir
			_flip_sprite(facing_direction == -1)
			
			t_jump_buffer = 0
			_change_state(State.WALL_JUMPING)
			
		# 3. Pulo Duplo
		elif current_state == State.AIR and air_jumps_left > 0:
			velocity.y = jump_force * double_jump_multiplier
			air_jumps_left -= 1
			t_jump_buffer = 0

func _perform_dash() -> void:
	if dash_queued:
		dash_queued = false
		t_dash_dur = dash_duration
		t_dash_cd = dash_cooldown
		
		var dash_x = sign(input_axis) if input_axis != 0 else facing_direction
		dash_direction = Vector2(dash_x, 0)
		
		if input_axis != 0:
			facing_direction = int(dash_x)
			_flip_sprite(facing_direction == -1)
			
		_change_state(State.DASH)

func _update_timers(delta: float) -> void:
	if t_jump_buffer > 0: t_jump_buffer -= delta
	if t_coyote > 0: t_coyote -= delta
	if t_dash_dur > 0: t_dash_dur -= delta
	if t_dash_cd > 0: t_dash_cd -= delta
	if t_wall_lock > 0: t_wall_lock -= delta

# ==============================================================================
# SISTEMA DE ANIMAÇÃO (Corrigido e Organizado)
# ==============================================================================
func _update_anim() -> void:
	if not sprite: return
	
	var anim_name = "idle" # Animação padrão
	
	match current_state:
		State.RUN:
			anim_name = "run"
			
		State.DASH:
			anim_name = "dash"
			
		State.WALL_SLIDE:
			anim_name = "wall_slide"
			
		State.WALL_JUMPING:
			anim_name = "wall_jump"
			
		State.AIR:
			if velocity.y < 0:
				anim_name = "jump_up"   # Subindo
			else:
				anim_name = "jump_down" # Caindo
				
		State.IDLE:
			# Lógica de olhar para cima/baixo (Só funciona parado)
			if Input.is_action_pressed("cima"):
				anim_name = "look_up"
			elif Input.is_action_pressed("baixo"):
				anim_name = "look_down"
			else:
				anim_name = "idle"

	# Tocar animação com segurança (evita crash se faltar nome)
	if sprite.sprite_frames.has_animation(anim_name):
		if sprite.animation != anim_name:
			sprite.play(anim_name)
	else:
		# Fallback: Se não tiver "wall_jump", usa "jump_up"
		if anim_name == "wall_jump" and sprite.sprite_frames.has_animation("jump_up"):
			sprite.play("jump_up")
		# Fallback: Se não tiver "look_up", usa "idle"
		elif sprite.sprite_frames.has_animation("idle"):
			sprite.play("idle")

func _flip_sprite(flip: bool) -> void:
	if sprite:
		sprite.flip_h = flip

func _change_state(new_state: State) -> void:
	if current_state == new_state: return
	emit_signal("state_changed", current_state, new_state)
	
	# Resets de Habilidades (Refresh quando toca chão ou parede)
	if new_state == State.IDLE or new_state == State.WALL_SLIDE:
		air_jumps_left = max_air_jumps
		t_dash_cd = 0.0
		
	current_state = new_state
