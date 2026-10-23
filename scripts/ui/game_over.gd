class_name GameOver
extends CanvasLayer
## WASTED / BUSTED: time slows, the picture drains and darkens under the big word, then the player comes
## round at the hospital (wasted) or walks out of the police station (busted), a little poorer.

const FEE := 100

var _root: Control
var _shade: ColorRect
var _label: Label
var _sub: Label
var running := false


func _ready() -> void:
	layer = 40
	process_mode = Node.PROCESS_MODE_ALWAYS
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.visible = false
	add_child(_root)
	_shade = ColorRect.new()
	_shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_shade.color = Color(0, 0, 0, 0)
	_shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sm := ShaderMaterial.new()
	var sh := Shader.new()
	# desaturate and darken what is behind (screen texture), fading in with alpha
	sh.code = """shader_type canvas_item;
uniform sampler2D screen: hint_screen_texture, filter_linear;
uniform float amount = 0.0;
void fragment() {
	vec3 c = texture(screen, SCREEN_UV).rgb;
	float g = dot(c, vec3(0.3, 0.59, 0.11));
	vec3 d = mix(c, vec3(g) * vec3(1.0, 0.95, 0.9), amount) * mix(1.0, 0.55, amount);
	COLOR = vec4(d, 1.0);
}"""
	sm.shader = sh
	_shade.material = sm
	_root.add_child(_shade)
	_label = UITheme.label("", 120, UITheme.heading, UITheme.CORAL)
	_label.set_anchors_preset(Control.PRESET_CENTER)
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.size = Vector2(900, 170)
	_label.position = Vector2(-450, -110)
	_root.add_child(_label)
	_sub = UITheme.label("", 22, UITheme.body_bold, UITheme.PAPER)
	_sub.set_anchors_preset(Control.PRESET_CENTER)
	_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_sub.size = Vector2(900, 40)
	_sub.position = Vector2(-450, 60)
	_root.add_child(_sub)


## kind: "wasted" or "busted". `respawn` is called (with the screen black) to move the player.
func play(kind: String, respawn: Callable) -> void:
	if running:
		return
	running = true
	_root.visible = true
	_label.text = kind.to_upper()
	_label.add_theme_color_override("font_color", UITheme.CORAL if kind == "wasted" else Color(0.45, 0.65, 1.0))
	_label.modulate.a = 0.0
	var fee := mini(FEE, Game.money)
	_sub.text = ("Hospital bill $%d" if kind == "wasted" else "Fine $%d. Weapons confiscated.") % fee
	_sub.modulate.a = 0.0
	var mat := _shade.material as ShaderMaterial
	Engine.time_scale = 0.35
	var tw := create_tween()
	tw.set_ignore_time_scale(true)
	tw.tween_method(func(a: float): mat.set_shader_parameter("amount", a), 0.0, 1.0, 1.2)
	tw.parallel().tween_property(_label, "modulate:a", 1.0, 0.6).set_delay(0.5)
	tw.tween_property(_sub, "modulate:a", 1.0, 0.5)
	tw.tween_interval(2.4)
	var black := ColorRect.new()
	black.set_anchors_preset(Control.PRESET_FULL_RECT)
	black.color = Color(0, 0, 0, 0)
	black.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(black)
	tw.tween_property(black, "color:a", 1.0, 0.8)
	tw.tween_callback(func():
		Engine.time_scale = 1.0
		Game.money -= fee
		respawn.call()
		mat.set_shader_parameter("amount", 0.0)
		_label.modulate.a = 0.0
		_sub.modulate.a = 0.0)
	tw.tween_interval(0.8)
	tw.tween_property(black, "color:a", 0.0, 1.0)
	tw.tween_callback(func():
		black.queue_free()
		_root.visible = false
		running = false)
