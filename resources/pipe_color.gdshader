shader_type canvas_item;

uniform vec4 team_color : source_color = vec4(0.2, 0.8, 0.2, 1.0);

void fragment() {
	vec4 tex = texture(TEXTURE, UV);
	if (tex.a > 0.05) {
		// Schwarze Konturen beibehalten
		if (tex.r < 0.05 && tex.g < 0.05 && tex.b < 0.05) {
			COLOR = tex;
		} else {
			// Unterscheidung zwischen Lichtkante (hell) und Röhrenkörper (Schatten)
			if (tex.g > 0.74) {
				// Glanzkante / Highlight
				vec3 hl = clamp(mix(team_color.rgb, vec3(1.0), 0.28), 0.0, 1.0);
				COLOR = vec4(hl, tex.a);
			} else {
				// Röhrenkörper / Schatten
				vec3 sh = clamp(team_color.rgb * 0.72, 0.0, 1.0);
				COLOR = vec4(sh, tex.a);
			}
		}
	} else {
		COLOR = tex;
	}
}
