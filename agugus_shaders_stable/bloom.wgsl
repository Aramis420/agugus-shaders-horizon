// ============================================================================
// Agugus Shaders (Stable) — post: bloom. One pass: two rings of taps on the
// picture, averaged, gated by a luminance curve, edge-faded and mixed in —
// this line has no post output targets for a multi-octave pyramid.
// ============================================================================

fn post(input: PostInput) -> vec4<f32> {
    if !bloom {
        return input.color;
    }

    // Two rings of samples, scaled with the picture's height so it looks the
    // same at any resolution.
    let base = frame.resolution.y / 720.0 / frame.resolution;
    var sum = vec3<f32>(0.0);

    // The inner ring, ~4 texels.
    for (var i = 0; i < 6; i++) {
        let angle = f32(i) * 1.0471976;
        let offset = vec2<f32>(cos(angle), sin(angle)) * 4.0 * base;
        sum = sum + textureSampleLevel(previous, linear_sampler, input.uv + offset, 0.0).rgb;
    }
    // The outer ring, ~14 texels.
    for (var i = 0; i < 8; i++) {
        let angle = f32(i) * 0.7853982;
        let offset = vec2<f32>(cos(angle), sin(angle)) * 14.0 * base;
        sum = sum + textureSampleLevel(previous, linear_sampler, input.uv + offset, 0.0).rgb;
    }
    let final_bloom = sum / 14.0;

    var bloom_factor = pow(get_luminance(final_bloom), bloom_curve);
    bloom_factor = bloom_factor + 0.2 * frame.rain * outdoors();
    let edge_fade = smoothstep(vec2<f32>(0.02), vec2<f32>(0.05), input.uv) * (vec2<f32>(1.0) - smoothstep(vec2<f32>(0.95), vec2<f32>(0.98), input.uv));
    bloom_factor = bloom_factor * edge_fade.x * edge_fade.y;

    return vec4<f32>(mix(input.color.rgb, final_bloom, vec3<f32>(bloom_factor * bloom_strength)), 1.0);
}
