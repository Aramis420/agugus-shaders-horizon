// ============================================================================
// Agugus Shaders (Stable) — post: SSAO. Eight poisson samples against the
// depth with a screen-derivative normal — this line has no surface record to
// read, so the derivative normal is the pack's approach. Off by default.
// ============================================================================

var<private> POISSON: array<vec2<f32>, 8> = array<vec2<f32>, 8>(
    vec2<f32>(-0.11995088205640914, 0.719751341508128),
    vec2<f32>(0.317022622719358, 0.22113273160666158),
    vec2<f32>(-0.26403670704884585, -0.3332036575870605),
    vec2<f32>(-0.4956967808947522, 0.1440260614790989),
    vec2<f32>(-0.2515255173617287, 0.4485353371596208),
    vec2<f32>(0.44577086115163955, 0.4954141319381722),
    vec2<f32>(0.18920463723666625, 0.7216180893153676),
    vec2<f32>(0.05891867438075504, -0.16082515533796937)
);

fn post(input: PostInput) -> vec4<f32> {
    if !ssao || input.depth == 0.0 {
        return input.color;
    }

    let position = recon_world(input.uv, input.depth);
    let view_pos = (frame.view * vec4<f32>(position, 1.0)).xyz;

    // A screen-derivative normal: smooth and soft.
    let view_z = -view_pos.z;
    let dx = dpdx(view_z);
    let dy = dpdy(view_z);
    let normal = normalize(vec3<f32>(dx, dy, max(0.1, 1.0 - dx * dx - dy * dy)));

    var factor = 0.0;
    var hits = 0.0;
    let dither = bayer8(input.pixel) * TAU;

    for (var i = 0; i < 8; i++) {
        let depth_bias = 0.00015;
        var sample_v = vec3<f32>(rotate2(POISSON[i], dither) * ssao_scale, depth_bias);
        let flip = sign(dot(normal, sample_v));
        sample_v = sample_v * vec3<f32>(flip);
        sample_v = sample_v + normal * 0.05 + view_pos;

        let clip = frame.projection * vec4<f32>(sample_v, 1.0);
        let sc = clip.xyz / vec3<f32>(clip.w);
        let sample_uv = vec2<f32>(sc.x * 0.5 + 0.5, 0.5 - sc.y * 0.5);
        if sample_uv.x < 0.0 || sample_uv.x > 1.0 || sample_uv.y < 0.0 || sample_uv.y > 1.0 {
            continue;
        }

        let real_depth = depth_at(sample_uv);
        if real_depth < 0.0001 {
            continue;   // the sky: nothing to occlude against
        }
        // Reversed depth: the sample is occluded when the surface at its pixel
        // is nearer the camera than the sample is.
        if sc.z < real_depth - 1e-5 {
            factor = factor + 1.0;
        }
        hits = hits + 1.0;
    }

    factor = factor / select(hits, 1.0, hits == 0.0);

    // Pastel lighten factor to keep it soft and gentle :3
    let amount = factor * ssao_strength * 1.67;   // 0.5 at the default 0.3
    return vec4<f32>(mix(input.color.rgb, vec3<f32>(1.0, 0.9, 0.95), vec3<f32>(min(amount, 1.0))), 1.0);
}
