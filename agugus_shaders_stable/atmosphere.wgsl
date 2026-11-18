// ============================================================================
// Agugus Shaders (Stable) — post: atmosphere. The engine already lays
// vanilla's fog over the material stage's result, so this pass adds the
// pack's own extras on top:
// the height-gated atmospheric mist, the border fade toward the sky, the
// underwater colour treatment, and — where the [sky] stage cannot reach —
// the End's sky, repainted over the sky pixels. Everything runs in linear
// light; the chain continues linear and the last pass encodes.
// ============================================================================

fn post(input: PostInput) -> vec4<f32> {
    var color = to_linear(input.color.rgb);

    // The End's sky with its two aurora tones: this line's [sky]
    // stage serves the Overworld's dome, so the End is painted here.
    if frame.dimension == 1 && input.depth == 0.0 {
        let dir = recon_ray(input.uv);
        let sky_t = end_sky_color();
        let up_dot = dir.y;
        let far = dir * 1000.0;
        let rot1 = rotate2(far.xz, frame.time * 0.015);
        let rot2 = rotate2(far.xz, -frame.time * 0.005);
        let noise1 = fbm2(rot1 * 140.0, 2) * (1.0 - abs(up_dot));
        let noise2 = fbm2(rot2 * 260.0, 2) * (1.0 - abs(up_dot));
        let glow = end_aurora1() * noise1 + end_aurora2() * noise2;

        var end_sky = sky_t + glow * vec3<f32>(fogify(up_dot + 0.3, 0.06));
        end_sky = end_sky * max(1.0 - fogify(max(up_dot + 0.35, 0.0), 0.025), 0.02);
        return vec4<f32>(end_sky, 1.0);   // linear on into the chain
    }

    if input.depth == 0.0 {
        // Sky pixels: nothing to fog toward themselves.
        return vec4<f32>(color, 1.0);
    }

    let cols = sky_cols();
    let position = recon_world(input.uv, input.depth);
    let dist = length(position);
    let world_pos = position + frame.camera_position;
    let view_dir = normalize(position);
    let sky_color = sky_fog_color(view_dir, cols);

    // The pack's atmospheric mist (the engine's vanilla fog is already under
    // the material stage's result).
    if frame.dimension == 0 && frame.eye_in == 0u {
        color = get_atm_fog(dist, color, world_pos, sky_color);
    }
    // The border fade toward the sky.
    color = get_border_fog(dist / frame.far, color, sky_color);
    // The underwater colour treatment.
    color = underwater_tint(dist, color, cols);
    // Blindness and darkness.
    color = get_blindness_fog(dist, color);

    return vec4<f32>(color, 1.0);
}
