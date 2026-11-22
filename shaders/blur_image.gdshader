shader_type canvas_item;

// blur_amount: 1.0 = maximal verzogen und verschmiert, 0.0 = gestochen scharfes Originalbild
uniform float blur_amount : hint_range(0.0, 1.0) = 0.0;
uniform float distortion_intensity : hint_range(0.0, 2.0) = 0.9;

vec2 hash2(vec2 p) {
	p = vec2(dot(p, vec2(127.1, 311.7)), dot(p, vec2(269.5, 183.3)));
	return -1.0 + 2.0 * fract(sin(p) * 43758.5453123);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	
	return mix(mix(dot(hash2(i + vec2(0.0, 0.0)), f - vec2(0.0, 0.0)),
	               dot(hash2(i + vec2(1.0, 0.0)), f - vec2(1.0, 0.0)), u.x),
	           mix(dot(hash2(i + vec2(0.0, 1.0)), f - vec2(0.0, 1.0)),
	               dot(hash2(i + vec2(1.0, 1.0)), f - vec2(1.0, 1.0)), u.x), u.y);
}

// Stroemungsfeld fuer weiche, wirbelnde Wischfinger-Verzerrungen
vec2 curl_noise(vec2 p) {
	const float eps = 0.02;
	float n1 = noise(vec2(p.x, p.y + eps));
	float n2 = noise(vec2(p.x, p.y - eps));
	float n3 = noise(vec2(p.x + eps, p.y));
	float n4 = noise(vec2(p.x - eps, p.y));
	float a = (n1 - n2) / (2.0 * eps);
	float b = (n3 - n4) / (2.0 * eps);
	return vec2(a, -b);
}

// Photoshop Verfluessigen Wirbelpinsel an festgelegten Koordinaten
vec2 apply_swirl(vec2 uv, vec2 center, float radius, float angle_rad) {
	vec2 diff = (uv - center) * vec2(1.777778, 1.0); // 16:9 Entzerrung fuer runde Pinsel
	float d = length(diff);
	if (d < radius && radius > 0.0001) {
		float factor = 1.0 - (d / radius);
		factor = factor * factor * (3.0 - 2.0 * factor); // Hermite Kurve
		float theta = angle_rad * factor;
		float cos_t = cos(theta);
		float sin_t = sin(theta);
		vec2 rot = vec2(diff.x * cos_t - diff.y * sin_t, diff.x * sin_t + diff.y * cos_t);
		return center + rot / vec2(1.777778, 1.0);
	}
	return uv;
}

void fragment() {
	if (blur_amount <= 0.001) {
		COLOR = texture(TEXTURE, UV);
		return;
	}
	
	// Nichtlineare Kurve fuer einen natuerlichen Aufloesungsverlauf
	float amt = blur_amount;
	float curve = amt * amt * (3.0 - 2.0 * amt);
	
	vec2 uv = UV;
	
	// 1. Mehrere Verfluessigen-Wirbelpinsel ueber die 16:9 Flaeche verteilt
	uv = apply_swirl(uv, vec2(0.32, 0.36), 0.44, 3.2 * curve);
	uv = apply_swirl(uv, vec2(0.68, 0.40), 0.48, -3.5 * curve);
	uv = apply_swirl(uv, vec2(0.50, 0.64), 0.40, 2.7 * curve);
	uv = apply_swirl(uv, vec2(0.20, 0.72), 0.35, -2.4 * curve);
	uv = apply_swirl(uv, vec2(0.82, 0.68), 0.36, 2.9 * curve);
	
	// 2. Breitflaechige Photoshop Wischfinger-Pinselstriche
	vec2 aspect_uv = uv * vec2(1.777778, 1.0);
	vec2 curl1 = curl_noise(aspect_uv * 2.6 + vec2(1.2, 3.4));
	vec2 curl2 = curl_noise(aspect_uv * 5.4 + curl1 * 1.3);
	
	// Smudge-Vektor fuer das Ziehen von Farbschlieren
	vec2 smudge_vector = (curl1 * 0.18 + curl2 * 0.09) * distortion_intensity * curve;
	vec2 distorted_uv = clamp(uv + smudge_vector, vec2(0.001), vec2(0.999));
	
	// 3. Echte Farbwischspur entlang der Bewegung des Wischfingers
	const int SAMPLES = 5;
	vec4 col_accum = vec4(0.0);
	float weight_accum = 0.0;
	
	for (int i = 0; i < SAMPLES; i++) {
		float t = float(i) / float(SAMPLES - 1) - 0.5;
		vec2 sample_pos = clamp(distorted_uv + smudge_vector * t * 0.85, vec2(0.001), vec2(0.999));
		float w = 1.0 - abs(t) * 0.5;
		col_accum += texture(TEXTURE, sample_pos) * w;
		weight_accum += w;
	}
	
	COLOR = col_accum / weight_accum;
}
