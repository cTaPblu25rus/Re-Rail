// Ядовитый туман RE-RAIL. Два слоя:
//  lit = false — мутная зеленоватая пелена (не зависит от света): мир всегда в дымке;
//  lit = true  — аддитивный слой, который подсвечивают лампы и фонарь: лучи «видны» в тумане.
shader_type canvas_item;
render_mode blend_mix;

uniform sampler2D noise : repeat_enable, filter_nearest;
uniform vec4 fog_color : source_color = vec4(0.45, 0.62, 0.52, 1.0);
uniform float density = 0.5;
uniform float drift = 7.0;
uniform float pixel = 2.0;

varying vec2 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
}

void fragment() {
	vec2 p = floor(wpos / pixel) * pixel;
	vec2 uv1 = (p + vec2(TIME * drift, TIME * 1.5)) / vec2(380.0, 240.0);
	vec2 uv2 = (p + vec2(-TIME * drift * 0.7, -TIME * 2.5)) / vec2(170.0, 130.0);
	float n = texture(noise, uv1).r * 0.65 + texture(noise, uv2).r * 0.35;
	float a = smoothstep(0.25, 0.85, n) * density;
	a = floor(a * 7.0) / 7.0; // ступенчатые пиксельные клубы
	COLOR = vec4(fog_color.rgb, a);
}
