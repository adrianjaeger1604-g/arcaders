shader_type canvas_item;

uniform vec4 stroke_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float stroke_width = 1.0;
uniform float speed = 3.0;
uniform float min_opacity = 0.0;
uniform float max_opacity = 0.2;

void fragment() {
	// Virtueller Rand um Clipping zu vermeiden
	vec2 center = vec2(0.5, 0.5);
	vec2 uv = (UV - center) * 1.1 + center;

	vec4 orig_color = vec4(0.0);
	if (uv.x >= 0.0 && uv.x <= 1.0 && uv.y >= 0.0 && uv.y <= 1.0) {
		orig_color = texture(TEXTURE, uv);
	}

	vec4 final_color = orig_color;

	// Suche nur dann, wenn der aktuelle Pixel transparent ist (wir sind außerhalb der Figur)
	if (orig_color.a == 0.0) {
		float alpha_sum = 0.0;
		for (float x = -stroke_width; x <= stroke_width; x += 1.0) {
			for (float y = -stroke_width; y <= stroke_width; y += 1.0) {
				vec2 offset = vec2(x, y);
				// Wir prüfen ob der Punkt innerhalb des gewünschten Radius liegt
				if (length(offset) > stroke_width) continue;
				if (x == 0.0 && y == 0.0) continue;

				vec2 sample_uv = uv + offset * TEXTURE_PIXEL_SIZE * 1.1;

				if (sample_uv.x >= 0.0 && sample_uv.x <= 1.0 && sample_uv.y >= 0.0 && sample_uv.y <= 1.0) {
					alpha_sum += texture(TEXTURE, sample_uv).a;
				}
			}
		}

		// Wenn mindestens ein benachbarter Pixel des Sprites ausgefüllt ist, male den Umriss
		if (alpha_sum > 0.0) {
			float pulse = (sin(TIME * speed) + 1.0) / 2.0; // weich von 0.0 bis 1.0
			float current_alpha = mix(min_opacity, max_opacity, pulse);
			final_color = vec4(stroke_color.rgb, stroke_color.a * current_alpha);
		}
	}

	COLOR = final_color;
}
