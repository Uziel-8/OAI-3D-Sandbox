// PS1/PSX post-processing: colour-depth reduction + ordered (Bayer-ish) dithering.
// Adapted from https://godotshaders.com/shader/ps1-psx-postprocessing/ for Godot 4.7.
//
// Apply as a ShaderMaterial on the SubViewportContainer that wraps the 3D scene:
//   SubViewportContainer (this material, stretch = on) -> SubViewport -> your level.
shader_type canvas_item;

render_mode unshaded;

#define MAXCOLORS 16

uniform bool enabled = true;
uniform bool dithering = true;
uniform int colors : hint_range(1, MAXCOLORS) = 12;
uniform int dither_size : hint_range(1, 8) = 1;

float dithering_pattern(ivec2 fragcoord) {
	const float pattern[16] = {
		0.00, 0.50, 0.10, 0.65,
		0.75, 0.25, 0.90, 0.35,
		0.20, 0.70, 0.05, 0.50,
		0.95, 0.40, 0.80, 0.30
	};

	int x = fragcoord.x % 4;
	int y = fragcoord.y % 4;

	return pattern[y * 4 + x];
}

// Snaps one channel to the nearest palette step, letting `dither` decide which way
// borderline pixels round. Closed form of the original's search loop: it does not
// depend on MAXCOLORS and cannot divide by zero when `colors` is 1.
float reduce_color(float raw, float dither, int depth) {
	float levels = float(max(depth, 1));
	float scaled = clamp(raw, 0.0, 1.0) * levels;

	float step_index = ceil(scaled) - 1.0;
	float frac = scaled - step_index;
	float chosen = frac <= dither * 0.999 ? step_index : step_index + 1.0;

	return clamp(chosen / levels, 0.0, 1.0);
}

void fragment() {
	// UV, not SCREEN_UV: TEXTURE is the SubViewport's own texture, so it must be
	// sampled in the container's local space. SCREEN_UV only lines up by accident
	// when the container happens to cover the whole window.
	vec4 raw = texture(TEXTURE, UV);

	if (enabled) {
		ivec2 cell = ivec2(FRAGCOORD.xy / float(dither_size));

		float dithering_value = 1.0;
		if (dithering) {
			dithering_value = dithering_pattern(cell);
		}
		float threshold = (dithering_value - 0.5) * dithering_value + 0.5;

		COLOR.r = reduce_color(raw.r, threshold, colors - 1);
		COLOR.g = reduce_color(raw.g, threshold, colors - 1);
		COLOR.b = reduce_color(raw.b, threshold, colors - 1);
		COLOR.a = raw.a;
	} else {
		COLOR = raw;
	}
}
