// ============================================================================
// Agugus Shaders (Stable) — material stage.
// The pack's light mix over every terrain surface, and fancy water: the
// colour the pack paints over the biome's, wave normals, fresnel and the
// sky's reflection (this line has no water mirror; the reflections option
// is Off or Sky). The 0.1 MaterialInput has no normal field, so the
// surface normal
// comes from the position's screen derivatives, and no fluid field, so water
// is told from glass by the biome tint vanilla multiplies water by. The
// engine alpha-tests and fogs the returned colour with vanilla's fog.
// ============================================================================

// The surface's normal from its screen derivatives.
fn facet_normal(position: vec3<f32>) -> vec3<f32> {
    let t1 = dpdx(position);
    let t2 = dpdy(position);
    var n = normalize(cross(t1, t2));
    // Face the camera.
    if dot(n, position) > 0.0 {
        n = -n;
    }
    return n;
}

// Water, not glass: vanilla tints water with the biome's water colour and
// leaves glass near-white.
fn is_water(input: MaterialInput) -> bool {
    let t = input.tint.rgb;
    return input.translucent && (max(t.r, max(t.g, t.b)) - min(t.r, min(t.g, t.b)) > 0.05);
}

// The water colour the pack paints over the biome's: the brightened
// albedo, then the pack's colour mixed into the biome's.
fn water_base(input: MaterialInput, mixed: vec3<f32>) -> vec4<f32> {
    var c = vec4<f32>(to_linear(input.albedo.rgb) + vec3<f32>(0.5), 1.0);
    c = vec4<f32>(c.rgb * mixed, c.a);
    let water_col = f_water();
    let biome = input.tint.rgb;
    let vertex_color = to_linear(mix_preserve_c1lum(water_col, biome, f_biome_water()));
    return vec4<f32>(c.rgb * vertex_color, f_water_alpha());
}

// Layered wave normals over the water's up normal (water faces up, so its
// frame is the world's).
fn get_water_normal(world_xz: vec2<f32>, base: vec3<f32>) -> vec3<f32> {
    var n = noise_water(world_xz) * 1.2;
    n = n + noise_water(world_xz * 0.7 + vec2<f32>(frame.time * 0.8)) * 0.8;
    n = n + noise_water(world_xz * 1.5 + vec2<f32>(frame.time * 1.5)) * 0.4;
    let steepness = 1.0 - (n.x * n.x + n.y * n.y) * 0.3;
    var water_normal = normalize(vec3<f32>(n.x * 1.2, n.y * 1.2, max(steepness, 0.15)));
    // The water's frame: the normal is up, so lift the noise into it.
    let tangent = vec3<f32>(1.0, 0.0, 0.0);
    let bitangent = vec3<f32>(0.0, 0.0, 1.0);
    return normalize(tangent * water_normal.x + bitangent * water_normal.y + base * water_normal.z);
}

// The schlick fresnel.
fn schlick(v: vec3<f32>, n: vec3<f32>) -> f32 {
    let r = 0.07;
    let theta = clamp(1.0 - dot(-v, n), 0.0, 1.0);
    return r + (1.0 - r) * pow(theta, 5.0);
}

fn material(input: MaterialInput) -> Surface {
    let cols = sky_cols();
    let position = input.position;
    let normal_a = facet_normal(position);

    // The pack light. This line has no [[materials]], so every face uses its
    // own normal and the small plants keep a little more shape.
    let mixed = mixed_lights(input.light, normal_a, cols);

    var lit: vec4<f32>;
    if input.translucent {
        var color: vec3<f32>;
        var alpha: f32;
        if fancy_water && is_water(input) {
            var base = water_base(input, mixed);
            let view_dir = normalize(position);

            if reflections != 0u && base.a > 0.0 {
                let world_normal = normal_a;
                var water_normal = world_normal;
                water_normal = get_water_normal(position.xz + frame.camera_position.xz, world_normal);

                let reflected = reflect(view_dir, water_normal);
                let glare_dist = dot(reflected, frame.sun_direction);
                let fresnel = schlick(view_dir, water_normal) * input.light.y;

                if world_normal.y > -0.02 {
                    var reflection: vec3<f32>;
                    // The sky's reflection (this line has no water mirror).
                    let glare = get_sun_glare(glare_dist, cols.glare) * 0.85;
                    reflection = get_sky(reflected, glare, cols);
                    if reflect_sun && world_normal.y > 0.01 {
                        reflection = reflection + round_sun(glare_dist) * 2.5 * outdoors();
                    }
                    base = vec4<f32>(mix(base.rgb, reflection, vec3<f32>(fresnel * 0.9)), base.a);
                }
            }
            color = base.rgb;
            alpha = base.a;
        } else {
            // Plain translucent (glass): albedo, tint and the pack light.
            color = to_linear(input.albedo.rgb) * input.tint.rgb * mixed;
            alpha = input.albedo.a * input.tint.a;
        }
        lit = vec4<f32>(color, alpha);
    } else {
        var color = to_linear(input.albedo.rgb) * input.tint.rgb * mixed;
        lit = vec4<f32>(color, input.albedo.a);
    }

    // Back to display values for the gamma line's frame; the engine's own
    // alpha test and fog follow.
    return Surface(vec4<f32>(pow(max(lit.rgb, vec3<f32>(0.0)), vec3<f32>(1.0 / 2.2)), lit.a));
}
