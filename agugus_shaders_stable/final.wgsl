// ============================================================================
// Agugus Shaders (Stable) — post: the grade, the last pass. Exposure, the
// tonemap operator, the gamma encode, then CAS sharpening, vibrance,
// saturation, contrast, film grain, vignette and the final dither.
// The chain arrives in linear light; this pass encodes and ends the frame.
// ============================================================================

// One pixel through the grade: exposure, the operator, then gamma — except
// the ACES-slow operator, which ends in display values.
fn tonemap_pixel(c: vec3<f32>) -> vec3<f32> {
    let mapped = apply_tonemap(c * vec3<f32>(exposure));
    if tonemap_operator == 2u {
        return mapped;
    }
    return pow(mapped, vec3<f32>(1.0 / 2.2));
}

fn post(input: PostInput) -> vec4<f32> {
    var color = tonemap_pixel(input.color.rgb);

    // CAS sharpening on the tonemapped picture: the neighbours
    // come from the chain's picture, mapped the same way.
    if image_sharpening {
        let inv = 1.0 / frame.resolution;
        let uv = input.uv;

        let e = color;
        let a = tonemap_pixel(textureSampleLevel(previous, linear_sampler, uv + vec2<f32>(-inv.x, -inv.y), 0.0).rgb);
        let b = tonemap_pixel(textureSampleLevel(previous, linear_sampler, uv + vec2<f32>(0.0, -inv.y), 0.0).rgb);
        let c = tonemap_pixel(textureSampleLevel(previous, linear_sampler, uv + vec2<f32>(inv.x, -inv.y), 0.0).rgb);
        let d = tonemap_pixel(textureSampleLevel(previous, linear_sampler, uv + vec2<f32>(-inv.x, 0.0), 0.0).rgb);
        let f = tonemap_pixel(textureSampleLevel(previous, linear_sampler, uv + vec2<f32>(inv.x, 0.0), 0.0).rgb);
        let g = tonemap_pixel(textureSampleLevel(previous, linear_sampler, uv + vec2<f32>(-inv.x, inv.y), 0.0).rgb);
        let h = tonemap_pixel(textureSampleLevel(previous, linear_sampler, uv + vec2<f32>(0.0, inv.y), 0.0).rgb);
        let i = tonemap_pixel(textureSampleLevel(previous, linear_sampler, uv + vec2<f32>(inv.x, inv.y), 0.0).rgb);

        var mn = min(min(min(d, e), min(f, b)), h);
        mn = mn + min(min(min(mn, a), min(g, c)), i);

        var mx = max(max(max(d, e), max(f, b)), h);
        mx = mx + max(max(max(mx, a), max(g, c)), i);

        let rcp_mx = vec3<f32>(1.0) / max(mx, vec3<f32>(1e-6));
        var amp = clamp(min(mn, vec3<f32>(2.0) - mx) * rcp_mx, vec3<f32>(0.0), vec3<f32>(1.0));
        amp = inverseSqrt(amp) * 1.1;
        let peak = 9.5 - 2.5 * sharpening;
        let w = -vec3<f32>(1.0) / (amp * vec3<f32>(peak));
        let rcp_weight = vec3<f32>(1.0) / (vec3<f32>(1.0) + w * vec3<f32>(4.0));

        let window = (b + d) + (f + h);
        color = clamp((window * w + e) * rcp_weight, vec3<f32>(0.0), vec3<f32>(1.0));
    }

    color = apply_vibrance(color, vibrance);
    color = apply_saturation(color, saturation);
    color = apply_contrast(color, contrast);
    color = max(color, vec3<f32>(0.0));

    if film_grain {
        // Value noise drifting with the frame counter.
        var grain_pos = input.pixel + vec2<f32>(fract(f32(frame.frame_index) / 4.14159) * 234.0, -fract(f32(frame.frame_index) / 5.49382) * 567.0);
        let grain = vnoise(grain_pos / 4.0) - 0.5;
        color = color + vec3<f32>(grain * film_grain_strength);
    }

    if vignette_opacity > 0.0 {
        var pos = (input.uv - vec2<f32>(0.5)) * vec2<f32>(vignette_opacity);
        var strength = pos.x * pos.x + pos.y * pos.y;
        strength = pow(strength, 2.0 - 0.75);   // the falloff's shape (0.75)
        color = color * (1.0 - min(strength, 1.0));
    }

    // The final bayer dither, in display values.
    color = color + vec3<f32>((bayer8(input.pixel) - 0.5) / 255.0);

    // The gamma line's frame: display values, written as they are.
    return vec4<f32>(clamp(color, vec3<f32>(0.0), vec3<f32>(1.0)), 1.0);
}
