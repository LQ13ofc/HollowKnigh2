extends Camera2D

# --- CONFIGURAÇÕES DE FEEL ---
@export_group("Antecipação Horizontal (Look Ahead)")
@export var look_ahead_dist: float = 100.0  # Distância que a câmera avança
@export var look_ahead_speed: float = 2.0   # Velocidade de transição (menor = mais lento)

@export_group("Espiar Vertical (Peeking)")
@export var look_vertical_dist: float = 150.0 # Distância para cima/baixo
@export var peek_delay: float = 0.5         # Tempo segurando para ativar
@export var return_speed: float = 5.0       # Velocidade para voltar ao centro

# --- VARIÁVEIS INTERNAS ---
var target_offset: Vector2 = Vector2.ZERO
var peek_timer: float = 0.0
@onready var player: CharacterBody2D = get_parent()

func _ready() -> void:
	# Força a câmera a usar a atualização de física para evitar tremor
	process_callback = Camera2D.CAMERA2D_PROCESS_PHYSICS
	position_smoothing_enabled = true
	# Define uma velocidade de arrasto base da Godot (suavização nativa)
	position_smoothing_speed = 7.0 

func _physics_process(delta: float) -> void:
	if not player: return

	# 1. ANTECIPAÇÃO HORIZONTAL
	# Só move a câmera se o jogador estiver realmente correndo
	if abs(player.velocity.x) > 20.0:
		# Define o alvo baseado na direção do input do jogador
		# Usamos sign(velocity) para garantir que olhe para onde o personagem vai
		target_offset.x = sign(player.velocity.x) * look_ahead_dist
	else:
		# Se parar, volta o foco horizontal para o centro devagar
		target_offset.x = 0.0
	
	# 2. ESPIAR VERTICAL (Peeking)
	# Apenas se estiver no chão e praticamente parado
	if player.is_on_floor() and abs(player.velocity.x) < 10.0:
		var y_axis = Input.get_axis("cima", "baixo") # Certifique-se que criou esses inputs
		
		if y_axis != 0:
			peek_timer += delta
			if peek_timer > peek_delay:
				# Define o alvo vertical (multiplicamos por y_axis para saber se é cima ou baixo)
				target_offset.y = y_axis * look_vertical_dist
		else:
			peek_timer = 0.0
			target_offset.y = 0.0
	else:
		# Se pulou ou correu, reseta imediatamente o olhar vertical
		peek_timer = 0.0
		target_offset.y = 0.0
	
	# 3. APLICAÇÃO DO MOVIMENTO (Suave e Sem Tremor)
	# Usamos move_toward para x (linear e estável) e lerp para y (mais orgânico)
	
	# Horizontal: Interpolação suave
	offset.x = lerp(offset.x, target_offset.x, look_ahead_speed * delta)
	
	# Vertical: Interpolação rápida para voltar, suave para ir
	offset.y = lerp(offset.y, target_offset.y, return_speed * delta)
