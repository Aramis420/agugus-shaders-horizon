// ============================================================================
// Agugus Shaders (Stable) — sky stage.
// The two-colour gradient and the sun glare. This line of the API always
// draws vanilla's sun, moon, stars and clouds over the stage's result, and
// the sun disc itself is vanilla's too.
// The stage works in linear light and encodes on the way out, as the gamma
// line expects display values from its stages.
// ============================================================================

fn sky(input: SkyInput) -> vec4<f32> {
    let cols = sky_cols();
    let view_dir = input.direction;
    let glare_dist = dot(view_dir, frame.sun_direction);
    let glare = get_sun_glare(glare_dist, cols.glare);

    var color = get_sky(view_dir, glare, cols);

    // Back to display values for the gamma line's frame.
    color = pow(max(color, vec3<f32>(0.0)), vec3<f32>(1.0 / 2.2));
    return vec4<f32>(color, 1.0);
}
