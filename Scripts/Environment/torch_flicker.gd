extends OmniLight3D
class_name TorchFlicker

## Makes this light flicker like a torch: a slow smooth noise drift for the
## main flame sway, fine jitter for candle-like judder, and occasional
## darker dips to mimic gusts of wind. Reads light_energy/omni_range/
## light_color at _ready() as the flame's resting values, so just tune those
## on the light itself and drop this script on.

@export var _base_energy: float = 1.0
@export var _base_range: float = 5.0
@export var energy_flicker: float = 0.5
@export var range_flicker: float = 0.3
@export var flicker_speed: float = 1.8
@export var jitter_amount: float = 0.15
@export_range(0.0, 1.0) var gust_chance_per_second: float = 0.25
@export var gust_strength: float = 0.6
@export var gust_duration: float = 0.25
@export var color_flicker: bool = true
@export var cool_color: Color = Color(0.85, 0.5, 0.2)
@export var hot_color: Color = Color(1.0, 0.78, 0.4)

var _noise := FastNoiseLite.new()
var _time: float = 0.0
var _gust_check_timer: float = 0.0
var _gust_amount: float = 0.0


func _ready() -> void:
	_base_energy = light_energy
	_base_range = omni_range
	_noise.seed = randi()
	_noise.frequency = 1.0
	_time = randf() * 1000.0 # desync multiple torches using this script


func _process(delta: float) -> void:
	_time += delta * flicker_speed

	var wave := _noise.get_noise_1d(_time)
	var jitter := (randf() * 2.0 - 1.0) * jitter_amount

	_gust_check_timer -= delta
	if _gust_check_timer <= 0.0:
		_gust_check_timer = 1.0
		if randf() < gust_chance_per_second:
			_gust_amount = gust_strength
	_gust_amount = move_toward(_gust_amount, 0.0, delta / max(gust_duration, 0.01))

	var flicker := wave + jitter - _gust_amount
	light_energy = max(_base_energy + flicker * energy_flicker, 0.0)
	omni_range = max(_base_range + flicker * range_flicker, 0.1)

	if color_flicker:
		var heat = clamp((wave + 1.0) * 0.5, 0.0, 1.0)
		light_color = cool_color.lerp(hot_color, heat)
