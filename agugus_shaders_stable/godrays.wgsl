// ============================================================================
// Agugus Shaders (Stable) — post: godrays. A screen-space march toward the
// sun or moon, counting the sky it sees through, with the pack's underwater
// colour over it. Off by default.
// ============================================================================

fn post(input: PostInput) -> vec4<f32> {
    if !godrays || frame.dimension != 0 || input.depth == 0.0 {
        return input.color;
    }
    let cols = sky_cols();

    // Whichever body is in front of the camera casts the rays.
    let sun_view = (frame.view * vec4<f32>(frame.sun_direction, 0.0)).xyz;
    var light_dir = frame.sun_direction;
    var light_color: vec3<f32>;
    if sun_view.z < 0.0 {
        let glare = vec3<f32>(0.8, 0.55, 0.2);
        light_color = cols.direct * vec3<f32>(day_strength() / 5.0) + to_linear(glare) * vec3<f32>(dusk_strength() + dawn_strength());
    } else {
        light_dir = -frame.sun_direction;   // the moon, opposite the sun
        light_color = cols.direct * vec3<f32>(night_strength() / 4.0) + vec3<f32>(0.6, 0.7, 1.0) * 0.2;
    }

    // The body's position on screen.
    let far_view = (frame.view * vec4<f32>(light_dir * 1000.0, 1.0)).xyz;
    let far_clip = frame.projection * vec4<f32>(far_view, 1.0);
    if far_clip.w <= 0.0 {
        return input.color;
    }
    let ndc = far_clip.xy / vec2<f32>(far_clip.w);
    let light_screen = vec2<f32>(ndc.x * 0.5 + 0.5, 0.5 - ndc.y * 0.5);

    var falloff = distance(light_screen, input.uv);
    if falloff > 1.0 {
        return input.color;
    }
    falloff = 1.0 - falloff;
    light_color = light_color * vec3<f32>(pow(falloff, 3.0));

    let quality = 4;
    let step_v = (light_screen - input.uv) / vec2<f32>(f32(quality));
    var expected = input.uv + step_v * vec2<f32>(bayer8(input.pixel));
    var light_factor = 0.0;
    for (var i = 1; i <= quality; i++) {
        // Sky pixels (reversed depth 0) let the light through.
        if depth_at(expected) < 0.0001 {
            light_factor = light_factor + 1.0;
        }
        expected = expected + step_v;
    }
    let settings_factor = 0.7 / f32(quality) * godrays_strength;

    var scattering = light_color * vec3<f32>(light_factor * settings_factor);
    // The pack's underwater colour over the rays.
    let position = recon_world(input.uv, input.depth);
    scattering = underwater_tint(length(position), scattering, cols);
    scattering = scattering * (1.0 - max(frame.darkness, frame.blindness));

    return vec4<f32>(input.color.rgb + scattering, 1.0);
}
