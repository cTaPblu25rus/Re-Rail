// Земля RE-RAIL: трава, грязь, гравийная насыпь, шпалы и рельсы — всё в шейдере,
// попиксельно в мировых координатах (без тысяч тайлов и без генерации текстур на CPU).
shader_type canvas_item;

uniform sampler2D noise : repeat_enable, filter_nearest;
uniform float rail_y = 0.0;
uniform vec3 grass_a = vec3(0.16, 0.22, 0.10);
uniform vec3 grass_b = vec3(0.28, 0.30, 0.14);
uniform vec3 dirt_a = vec3(0.22, 0.18, 0.13);
uniform vec3 dirt_b = vec3(0.30, 0.25, 0.18);

varying vec2 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
}

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void fragment() {
	vec2 p = floor(wpos);
	float n1 = texture(noise, p / 256.0).r;
	float n2 = texture(noise, p / 48.0 + 0.37).r;
	float h = hash(p);

	// трава ↔ сухая земля
	vec3 grass = mix(grass_a, grass_b, n2);
	vec3 dirt = mix(dirt_a, dirt_b, n2);
	vec3 col = mix(grass, dirt, smoothstep(0.5, 0.75, n1) * 0.7);
	col *= 0.9 + 0.2 * h;
	// травинки: светлые вертикальные штрихи
	if (hash(vec2(p.x, floor(p.y / 3.0))) > 0.86) col *= 1.25;

	float dy = p.y - rail_y;
	float ady = abs(dy);
	// насыпь из щебня
	if (ady < 26.0 - 4.0 * n2) {
		col = mix(vec3(0.24, 0.23, 0.22), vec3(0.38, 0.36, 0.33), h);
		if (h > 0.93) col = vec3(0.30, 0.20, 0.14); // ржавые крошки
	}
	// шпалы
	if (ady < 15.0 && mod(p.x, 13.0) < 6.0) {
		col = mix(vec3(0.20, 0.13, 0.08), vec3(0.30, 0.20, 0.12), h * 0.6 + n2 * 0.4);
		if (mod(p.x, 13.0) < 1.0) col *= 0.7;
	}
	// рельсы
	if (abs(dy - 8.0) < 1.5 || abs(dy + 8.0) < 1.5) {
		col = vec3(0.36, 0.34, 0.33);
		if (abs(dy - 8.0) < 0.5 || abs(dy + 8.0) < 0.5) col = vec3(0.62, 0.58, 0.54);
	}
	COLOR = vec4(col, 1.0);
}
