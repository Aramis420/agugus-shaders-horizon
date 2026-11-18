// ============================================================================
// Agugus Shaders (Stable) — shared helpers, for shader API 0.1.
// The colour schemes, the time-of-day windows, the pack light mix, the
// tonemap operators and the fog stack. This line of the API (Horizon stable
// v0.2.97 and its era) predates [[textures]], so every noise here is
// procedural; and its Frame has fog_start/fog_end, plain eye_light and no
// moon phase, light direction, temperature or wetness. The post chain works
// in linear light between its passes (the last pass encodes).
// ============================================================================

// ---- options ---------------------------------------------------------------

override color_scheme: u32 = 0u;              // Default, Vanilla, Choc v7, Visually Vibrant
override tonemap_operator: u32 = 0u;          // ACES Film, Reinhard-Jodie, ACES Slow, Hejl 2015
override exposure: f32 = 2.5;
override saturation: f32 = 1.2;
override vibrance: f32 = 1.2;
override contrast: f32 = 0.9;

override min_light_amount: f32 = 0.15;
override lm_falloff_curve: f32 = 1.6;
override lm_red: f32 = 0.0;
override lm_green: f32 = 0.0;
override lm_blue: f32 = 0.0;
override lm_flicker: bool = false;
override sunrise_ambient: f32 = 0.0;
override noon_ambient: f32 = 0.0;
override sunset_ambient: f32 = 0.0;
override night_ambient: f32 = 0.0;

override rain_sky_darkening: f32 = 0.33;
override rain_sky_desaturation: f32 = 0.5;

override fancy_water: bool = true;
override water_red: f32 = 0.0;
override water_green: f32 = 0.0;
override water_blue: f32 = 0.0;
override water_alpha: f32 = 0.0;
override biome_water_contribution: f32 = 0.0;
override water_normal_strength: f32 = 1.0;
override reflections: u32 = 1u;               // Off, Sky
override reflect_sun: bool = true;

override bloom: bool = true;
override bloom_strength: f32 = 0.4;
override bloom_curve: f32 = 0.3;

override godrays: bool = false;
override godrays_strength: f32 = 0.5;

override ssao: bool = false;
override ssao_strength: f32 = 0.3;
override ssao_scale: f32 = 0.5;

override film_grain: bool = false;
override film_grain_strength: f32 = 0.05;
override vignette_opacity: f32 = 0.0;
override image_sharpening: bool = false;
override sharpening: f32 = 0.2;

// ---- small math ------------------------------------------------------------

const PI: f32 = 3.141592653589793;
const TAU: f32 = 6.283185307179586;

// Fast sRGB -> linear (a polynomial, not the piecewise curve).
fn to_linear(srgb: vec3<f32>) -> vec3<f32> {
    return srgb * (srgb * (srgb * 0.305306011 + 0.682171111) + 0.012522878);
}

fn to_linear_s(srgb: f32) -> f32 {
    return srgb * (srgb * (srgb * 0.305306011 + 0.682171111) + 0.012522878);
}

fn get_luminance(color: vec3<f32>) -> f32 {
    return 0.299 * color.r + 0.587 * color.g + 0.114 * color.b;
}

fn apply_saturation(color: vec3<f32>, sat: f32) -> vec3<f32> {
    return mix(vec3<f32>(get_luminance(color)), color, sat);
}

fn apply_vibrance(color: vec3<f32>, intensity: f32) -> vec3<f32> {
    let mn = min(color.r, min(color.g, color.b));
    let mx = max(color.r, max(color.g, color.b));
    let sat = (1.0 - clamp(mx - mn, 0.0, 1.0)) * clamp(1.0 - mx, 0.0, 1.0) * get_luminance(color) * 5.0;
    let lightness = vec3<f32>((mn + mx) * 0.5);
    return mix(color, mix(lightness, color, intensity), sat);
}

fn apply_contrast(color: vec3<f32>, contrast: f32) -> vec3<f32> {
    return (color - 0.5) * contrast + 0.5;
}

fn mix_preserve_c1lum(c1: vec3<f32>, c2: vec3<f32>, weight: f32) -> vec3<f32> {
    let l1 = get_luminance(c1);
    var mixed = mix(c1, c2, weight);
    let l = get_luminance(mixed);
    mixed = mixed * (l1 / max(l, 1e-5));
    return mixed;
}

fn rotate2(p: vec2<f32>, angle: f32) -> vec2<f32> {
    let cos_t = cos(angle);
    let sin_t = sin(angle);
    return vec2<f32>(p.x * cos_t - p.y * sin_t, p.x * sin_t + p.y * cos_t);
}

// https://www.shadertoy.com/view/4ssfWM
fn bayer8(a: vec2<f32>) -> f32 {
    let b = vec2<u32>(a);
    let c = (b.x ^ b.y) << 1u;
    return f32((((c & 8u) | (b.y & 4u)) >> 2u)
             | (((c & 4u) | (b.y & 2u)) << 1u)
             | (((c & 2u) | (b.y & 1u)) << 4u)) / 64.0;
}

fn random2(coords: vec2<f32>) -> f32 {
    return fract(sin(dot(coords, vec2<f32>(12.9898, 78.233))) * 43758.5453);
}

// ---- procedural noise (this line has no [[textures]], so the pack's noise
// is computed in place) ------------------------------------------------------

fn hash2(p: vec2<f32>) -> f32 {
    return fract(sin(dot(p, vec2<f32>(127.1, 311.7))) * 43758.5453);
}

// Smooth value noise.
fn vnoise(p: vec2<f32>) -> f32 {
    let i = floor(p);
    let f = fract(p);
    var u = f * f * (vec2<f32>(3.0) - 2.0 * f);
    let a = hash2(i);
    let b = hash2(i + vec2<f32>(1.0, 0.0));
    let c = hash2(i + vec2<f32>(0.0, 1.0));
    let d = hash2(i + vec2<f32>(1.0));
    return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

// Fractal brownian motion: rotated octaves over the value noise.
fn fbm2(x: vec2<f32>, detail: i32) -> f32 {
    var v = 0.0;
    var a = 0.5;
    var p = x;
    let shift = vec2<f32>(100.0);
    let rot = mat2x2<f32>(cos(0.5), sin(0.5), -sin(0.5), cos(0.5));
    for (var i = 0; i < detail; i++) {
        v = v + a * vnoise(p);
        p = rot * p * 2.0 + shift;
        a = a * 0.5;
    }
    return v;
}

// Two drifting bands of value noise: the water's ripples.
fn noise_water(p: vec2<f32>) -> vec2<f32> {
    let c1 = p + vec2<f32>(frame.time * 0.2);
    let c2 = p - vec2<f32>(frame.time * 0.8);
    var n = vec2<f32>(vnoise(c1 / 24.0), vnoise(c1.yx / 24.0 + 17.0)) * 2.0 - 1.0;
    n = n * 0.05;
    n = n + (vec2<f32>(vnoise(c2 / 64.0), vnoise(c2.yx / 64.0 + 23.0)) * 2.0 - 1.0) * 0.1;
    return n * water_normal_strength;
}

// ---- time of day -----------------------------------------------------------

fn day_strength() -> f32 {
    let s = min(abs(sin(frame.day_time * TAU)) * 2.0, 1.0);
    return select(0.0, s, frame.day_time < 0.5);
}

fn night_strength() -> f32 {
    let s = min(abs(sin(frame.day_time * TAU)) * 2.0, 1.0);
    return select(0.0, s, frame.day_time >= 0.5);
}

fn dusk_strength() -> f32 {
    let free = 1.0 - night_strength() - day_strength();
    let evening = floor((frame.day_time * 3.0) % 2.0);
    return free * select(0.0, 1.0, evening == 1.0);
}

fn dawn_strength() -> f32 {
    let free = 1.0 - night_strength() - day_strength();
    let ss = dusk_strength();
    return free * select(1.0, 0.0, ss > 0.0);
}

// Whether the camera is outdoors; this line's Frame has plain eye light, so
// the step is hard rather than eased.
fn outdoors() -> f32 {
    return select(0.0, 1.0, frame.eye_light.y > 0.2);
}

// The dominant light: the sun by day, the moon by night.
fn sun_or_moon() -> vec3<f32> {
    return select(frame.moon_direction, frame.sun_direction, frame.sun_direction.y > 0.0);
}

// ---- colour schemes --------------------------------------------------------

fn scheme1(a: f32, b: f32, c: f32, d: f32) -> f32 {
    if color_scheme == 1u { return b; }
    if color_scheme == 2u { return c; }
    if color_scheme == 3u { return d; }
    return a;
}

fn scheme3(a: vec3<f32>, b: vec3<f32>, c: vec3<f32>, d: vec3<f32>) -> vec3<f32> {
    if color_scheme == 1u { return b; }
    if color_scheme == 2u { return c; }
    if color_scheme == 3u { return d; }
    return a;
}

fn f_lm() -> vec3<f32> {
    var base = scheme3(vec3<f32>(1.2, 0.9, 0.6), vec3<f32>(1.1, 0.9, 0.7), vec3<f32>(1.3, 0.9, 0.55), vec3<f32>(1.1, 0.9, 0.85));
    base = max(base + vec3<f32>(lm_red, lm_green, lm_blue), vec3<f32>(0.0));
    return base;
}

fn f_water() -> vec3<f32> {
    var base = scheme3(vec3<f32>(0.0, 0.35, 0.25), vec3<f32>(0.0, 0.35, 0.25), vec3<f32>(0.0, 0.1, 0.2), vec3<f32>(0.33, 0.2, 0.03));
    base = max(base + vec3<f32>(water_red, water_green, water_blue), vec3<f32>(0.0));
    return base;
}

fn f_water_alpha() -> f32 {
    return max(scheme1(0.4, 0.4, 0.6, 0.6) + water_alpha, 0.0);
}

fn f_biome_water() -> f32 {
    return clamp(scheme1(0.5, 0.5, 0.7, 0.7) + biome_water_contribution, 0.0, 1.0);
}

fn sun_direct_noon() -> vec3<f32> {
    var b = scheme3(vec3<f32>(1.2, 1.1, 1.0), vec3<f32>(1.05, 1.0, 1.0), vec3<f32>(1.2, 1.1, 0.95), vec3<f32>(1.0, 0.85, 0.7));
    return to_linear(vec3<f32>(b.r * 0.95, b.g * 0.9, b.b * 1.05));
}

fn sun_direct_sunrise() -> vec3<f32> {
    var b = scheme3(vec3<f32>(0.8, 0.6, 0.4), vec3<f32>(0.9, 0.73, 0.5), vec3<f32>(0.8, 0.55, 0.35), vec3<f32>(0.75, 0.5, 0.45));
    return to_linear(vec3<f32>(b.r * 1.1, b.g * 1.05, b.b * 0.9));
}

fn sun_direct_sunset() -> vec3<f32> {
    var b = scheme3(vec3<f32>(0.8, 0.5, 0.2), vec3<f32>(0.9, 0.73, 0.5), vec3<f32>(0.8, 0.55, 0.35), vec3<f32>(0.65, 0.45, 0.3));
    return to_linear(vec3<f32>(b.r * 1.05, b.g * 0.9, b.b * 1.1));
}

fn sun_direct_moon() -> vec3<f32> {
    var b = scheme3(vec3<f32>(0.4, 0.4, 0.5), vec3<f32>(0.4, 0.4, 0.5), vec3<f32>(0.2, 0.25, 0.35), vec3<f32>(0.35, 0.35, 0.5));
    return to_linear(vec3<f32>(b.r * 0.7, b.g * 0.75, b.b * 1.1));
}

fn sky_top_noon() -> vec3<f32> {
    var b = scheme3(vec3<f32>(0.2, 0.35, 0.7), vec3<f32>(0.25, 0.38, 0.7), vec3<f32>(0.2, 0.35, 0.55), vec3<f32>(0.3, 0.4, 0.7));
    return to_linear(vec3<f32>(b.r * 0.85, b.g * 0.9, b.b * 1.1));
}

fn sky_top_sunrise() -> vec3<f32> {
    var b = scheme3(vec3<f32>(0.0, 0.25, 0.5), vec3<f32>(0.22, 0.37, 0.67), vec3<f32>(0.1, 0.25, 0.4), vec3<f32>(0.23, 0.35, 0.6));
    return to_linear(vec3<f32>(b.r * 1.1, b.g * 1.05, b.b * 0.9));
}

fn sky_top_sunset() -> vec3<f32> {
    var b = scheme3(vec3<f32>(0.0, 0.15, 0.25), vec3<f32>(0.22, 0.37, 0.67), vec3<f32>(0.1, 0.25, 0.4), vec3<f32>(0.18, 0.22, 0.4));
    return to_linear(vec3<f32>(b.r * 1.05, b.g * 0.9, b.b * 1.1));
}

fn sky_top_night() -> vec3<f32> {
    var b = scheme3(vec3<f32>(0.0, 0.025, 0.075), vec3<f32>(0.0, 0.025, 0.075), vec3<f32>(0.0, 0.025, 0.075), vec3<f32>(0.0, 0.005, 0.05));
    return to_linear(vec3<f32>(b.r * 0.7, b.g * 0.8, b.b * 1.2));
}

fn sky_ground_noon() -> vec3<f32> {
    var b = scheme3(vec3<f32>(0.5, 0.55, 0.6), vec3<f32>(0.5, 0.55, 0.6), vec3<f32>(0.57, 0.6, 0.63), vec3<f32>(0.6, 0.63, 0.7));
    return to_linear(vec3<f32>(b.r * 0.9, b.g * 0.95, b.b * 1.1));
}

fn sky_ground_sunrise() -> vec3<f32> {
    var b = scheme3(vec3<f32>(0.5, 0.4, 0.4), vec3<f32>(0.47, 0.52, 0.55), vec3<f32>(0.42, 0.38, 0.45), vec3<f32>(0.5, 0.49, 0.55));
    return to_linear(vec3<f32>(b.r * 1.1, b.g * 1.05, b.b * 0.95));
}

fn sky_ground_sunset() -> vec3<f32> {
    var b = scheme3(vec3<f32>(0.3, 0.25, 0.25), vec3<f32>(0.47, 0.52, 0.55), vec3<f32>(0.42, 0.38, 0.45), vec3<f32>(0.4, 0.33, 0.35));
    return to_linear(vec3<f32>(b.r * 1.05, b.g * 0.95, b.b * 1.1));
}

fn sky_ground_night() -> vec3<f32> {
    var b = scheme3(vec3<f32>(0.15, 0.2, 0.25), vec3<f32>(0.07, 0.1, 0.13), vec3<f32>(0.17, 0.2, 0.25), vec3<f32>(0.09, 0.1, 0.16));
    return to_linear(vec3<f32>(b.r * 0.75, b.g * 0.85, b.b * 1.15));
}

fn sun_glare_color() -> vec3<f32> {
    var b = scheme3(vec3<f32>(0.8, 0.45, 0.0), vec3<f32>(0.75, 0.5, 0.0), vec3<f32>(0.7, 0.45, 0.0), vec3<f32>(0.7, 0.35, 0.0));
    return to_linear(vec3<f32>(b.r * 1.1, b.g * 1.1, b.b * 1.2));
}

fn nether_ambient() -> vec3<f32> {
    var b = scheme3(vec3<f32>(0.48, 0.24, 0.18), vec3<f32>(0.45, 0.3, 0.22), vec3<f32>(0.25, 0.2, 0.22), vec3<f32>(0.45, 0.45, 0.5));
    return to_linear(vec3<f32>(b.r * 0.8, b.g * 0.85, b.b * 0.9));
}

fn end_ambient() -> vec3<f32> {
    var b = scheme3(vec3<f32>(0.2, 0.17, 0.25), vec3<f32>(0.3, 0.3, 0.35), vec3<f32>(0.2, 0.17, 0.25), vec3<f32>(0.2, 0.2, 0.2));
    return to_linear(vec3<f32>(b.r * 0.85, b.g * 0.9, b.b * 1.05));
}

fn end_direct() -> vec3<f32> {
    var b = scheme3(vec3<f32>(0.3, 0.23, 0.45), vec3<f32>(0.25, 0.3, 0.3), vec3<f32>(0.12, 0.1, 0.2), vec3<f32>(0.25, 0.25, 0.25));
    return to_linear(vec3<f32>(b.r * 0.85, b.g * 0.9, b.b * 1.05));
}

fn end_aurora1() -> vec3<f32> {
    var b = scheme3(vec3<f32>(0.0, 0.45, 0.25), vec3<f32>(0.0, 0.45, 0.25), vec3<f32>(0.0, 0.45, 0.25), vec3<f32>(0.2, 0.1, 0.6));
    return to_linear(vec3<f32>(b.r * 1.1, b.g * 1.05, b.b * 0.95));
}

fn end_aurora2() -> vec3<f32> {
    var b = scheme3(vec3<f32>(0.45, 0.3, 0.1), vec3<f32>(0.45, 0.3, 0.1), vec3<f32>(0.45, 0.3, 0.1), vec3<f32>(0.7, 0.5, 0.0));
    return to_linear(vec3<f32>(b.r * 1.05, b.g * 0.9, b.b * 1.1));
}

fn end_sky_color() -> vec3<f32> {
    var b = scheme3(vec3<f32>(0.15, 0.1, 0.2), vec3<f32>(0.12, 0.1, 0.15), vec3<f32>(0.15, 0.12, 0.17), vec3<f32>(0.17, 0.0, 0.24));
    return to_linear(vec3<f32>(b.r * 0.85, b.g * 0.9, b.b * 1.05));
}

// ---- frame-derived colours --------------------------------------------------

struct LightColors {
    sky_top: vec3<f32>,
    sky_ground: vec3<f32>,
    ambient: vec3<f32>,
    direct: vec3<f32>,
    glare: vec3<f32>,
    torch: vec3<f32>,
    min_light: f32,
}

fn sky_cols() -> LightColors {
    var c: LightColors;

    let day = day_strength();
    let night = night_strength();
    let dawn = dawn_strength();
    let dusk = dusk_strength();

    var top = sky_top_sunrise() * dawn + sky_top_noon() * day + sky_top_sunset() * dusk + sky_top_night() * night;
    var ground = sky_ground_sunrise() * dawn + sky_ground_noon() * day + sky_ground_sunset() * dusk + sky_ground_night() * night;

    top = apply_saturation(top, 1.0 - frame.rain * (rain_sky_desaturation * 0.7)) * (1.0 - frame.rain * (rain_sky_darkening * 0.6));
    ground = ground * (1.0 - frame.rain * 0.35);

    c.sky_top = top;
    c.sky_ground = ground;

    // Ambient: a scalar per window, then to_linear.
    let ambient = (sunrise_ambient + 0.45) * dawn * 1.1 + (noon_ambient + 0.5) * day * 0.9 + (sunset_ambient + 0.5) * dusk * 1.05 + (night_ambient + 0.2) * night * 0.8;
    c.ambient = to_linear(vec3<f32>(max(ambient, 0.0)));

    if frame.dimension == -1 {
        c.ambient = nether_ambient();
        c.direct = vec3<f32>(0.0);
    } else if frame.dimension == 1 {
        c.ambient = end_ambient();
        c.direct = end_direct();
    } else {
        var direct: vec3<f32>;
        if frame.sun_direction.y > 0.0 {
            direct = sun_direct_sunrise() * dawn + sun_direct_noon() * day + sun_direct_sunset() * dusk;
        } else {
            // The moon's phase doesn't ride this line's Frame; a full moon's
            // influence is taken as a constant 0.85.
            direct = sun_direct_moon() * 0.85;
        }
        direct = direct * smoothstep(0.0, 0.2, abs(frame.sun_direction.y));
        direct = apply_saturation(direct, 1.0 - frame.rain * 0.4) * (1.0 - frame.rain * 0.3);
        c.direct = direct;
    }

    c.glare = sun_glare_color();
    c.torch = to_linear(vec3<f32>(f_lm().r * 1.1, f_lm().g * 1.1, f_lm().b * 1.2));

    var min_light = clamp(min_light_amount + frame.brightness * 0.08 - 0.08, 0.0, 0.4);
    min_light = to_linear_s(min_light);
    min_light = min_light + frame.night_vision / 4.0;
    c.min_light = min_light;

    return c;
}

// The sun glare over the sky (get_sun_glare).
fn get_sun_glare(dist: f32, glare_color: vec3<f32>) -> vec3<f32> {
    let glare = glare_color * (1.0 - frame.rain * rain_sky_darkening * 0.6);
    let visibility = dusk_strength() + dawn_strength();
    return glare * (dist * 0.6 + 0.4) * visibility;
}

// The round sun disc (also the water's sun glint). Returns linear light; the
// caller encodes.
fn round_sun(dist: f32) -> vec3<f32> {
    let d = dist * 0.5 + 0.5;
    let sun_color = vec3<f32>(3.5, 2.8, 1.4);
    let moon_color = vec3<f32>(1.3, 1.8, 2.9);
    let what = dusk_strength() + dawn_strength();
    var color = sun_color * (1.0 - smoothstep(0.0, 0.002, 1.0 - d)) * (day_strength() + what * 0.8);
    color = color + moon_color * smoothstep(0.999, 1.0, 1.0 - d) * (night_strength() + what * 0.8);
    return color;
}

// ---- sky gradient -----------------------------------------------------------

fn fogify(x: f32, w: f32) -> f32 {
    return w / (x * x + w * 1.5);
}

fn get_sky(view_dir: vec3<f32>, glare: vec3<f32>, cols: LightColors) -> vec3<f32> {
    let up_dot = view_dir.y + 0.15;
    return mix(cols.sky_top, cols.sky_ground + glare, fogify(max(up_dot, 0.0), 0.04));
}

// The sky colour the fog mixes toward, at a view direction.
fn sky_fog_color(view_dir: vec3<f32>, cols: LightColors) -> vec3<f32> {
    if frame.dimension == 0 {
        let glare_dist = dot(view_dir, frame.sun_direction);
        return get_sky(view_dir, get_sun_glare(glare_dist, cols.glare), cols);
    }
    if frame.dimension == 1 {
        return end_sky_color();
    }
    let fog_l = frame.fog_color;
    return mix(fog_l, normalize(fog_l + vec3<f32>(1e-5)), 0.5) / 2.5;
}

// ---- the pack light ---------------------------------------------------------
// The 0.1 MaterialInput has no normal field; the caller passes the surface's
// normal (from its screen derivatives in the material stage, or its own for
// the post stages).

fn mixed_lights(light_in: vec2<f32>, normal_a: vec3<f32>, cols: LightColors) -> vec3<f32> {
    var lm = max(light_in * 1.05 - vec2<f32>(0.05), vec2<f32>(0.0));   // softer offset

    if lm_flicker {
        // A slow drift over the value noise.
        let flicker = vnoise(vec2<f32>(frame.time * 8.0, 7.3));
        lm.x = lm.x * ((1.0 - 0.25 * 0.6) + flicker * 0.25 * 0.6);
    }

    var sky_ambient = cols.ambient;
    if frame.dimension == 0 {
        let n_dot_u = clamp(normal_a.y, -1.0, 1.0);
        sky_ambient = mix(sky_ambient, mix(cols.sky_ground, cols.sky_top, vec3<f32>(n_dot_u * 0.3 + 0.3)), vec3<f32>(0.6));
    } else {
        lm.y = 1.0;   // no sky light outside the Overworld
    }

    if frame.dimension != -1 {
        var n_dot_l: f32;
        if frame.dimension == 1 {
            n_dot_l = max(dot(normal_a, vec3<f32>(0.0, 1.0, 0.0)), 0.0);
        } else {
            n_dot_l = max(dot(normal_a, sun_or_moon()), 0.0);
        }
        let fake_shadow = smoothstep(0.9, 0.98, lm.y);
        sky_ambient = sky_ambient + cols.direct * vec3<f32>(n_dot_l * fake_shadow * 0.8);
    }

    lm.x = pow(lm.x, 3.5 - lm_falloff_curve);

    var mixed = cols.torch * vec3<f32>(lm.x) + mix(vec3<f32>(cols.min_light), sky_ambient, vec3<f32>(lm.y));
    mixed = mixed * (1.0 - frame.darkness * 0.7);   // soften the darkness effect
    return mixed;
}

// ---- tonemap operators -------------------------------------------------------

fn aces_film(x_in: vec3<f32>) -> vec3<f32> {
    let x = x_in * 0.6;
    let a = 2.51;
    let b = 0.03;
    let c = 2.43;
    let d = 0.59;
    let e = 0.14;
    return (x * (a * x + b)) / (x * (c * x + d) + e);
}

fn reinhard_jodie(v_in: vec3<f32>) -> vec3<f32> {
    let l = get_luminance(v_in);
    let tv = v_in / (1.0 + v_in);
    return mix(v_in / (1.0 + l), tv, tv);
}

fn rrt_and_odt_fit(v: vec3<f32>) -> vec3<f32> {
    let a = v * (v + 0.0245786) - 0.000090537;
    let b = v * (0.983729 * v + 0.4329510) + 0.238081;
    return a / b;
}

fn aces_slow(color_in: vec3<f32>) -> vec3<f32> {
    var color = pow(color_in, vec3<f32>(1.0 / 2.2));
    let input_mat = mat3x3<f32>(
        0.59719, 0.07600, 0.02840,
        0.35458, 0.90834, 0.13383,
        0.04823, 0.01566, 0.83777);
    color = input_mat * color;
    color = rrt_and_odt_fit(color);
    let output_mat = mat3x3<f32>(
        1.60475, -0.10208, -0.00327,
        -0.53108, 1.10813, -0.07276,
        -0.07367, -0.00605, 1.07602);
    color = output_mat * color;
    return clamp(color, vec3<f32>(0.0), vec3<f32>(1.0));
}

fn hejl_2015(hdr_in: vec3<f32>) -> vec3<f32> {
    let hdr = hdr_in * 0.6;
    let vh = vec4<f32>(hdr, 3.25);
    let va = 1.425 * vh + 0.05;
    let vf = ((vh * va + 0.004) / (vh * (va + 0.55) + 0.0491)) - 0.0813;
    return vf.rgb / vf.www;
}

fn apply_tonemap(x: vec3<f32>) -> vec3<f32> {
    if tonemap_operator == 1u { return reinhard_jodie(x); }
    if tonemap_operator == 2u { return aces_slow(x); }
    if tonemap_operator == 3u { return hejl_2015(x); }
    return aces_film(x);
}

// ---- fog ----------------------------------------------------------------------
// The engine fogs what material returns with vanilla's fog; these are the
// pack's own extras, run as a post pass over the whole picture. All linear.

fn get_border_fog(strength_in: f32, color: vec3<f32>, sky_color: vec3<f32>) -> vec3<f32> {
    var strength = strength_in * strength_in * 0.8;
    if frame.dimension != -1 {
        strength = strength * 0.9;
        strength = strength * 0.9;
    }
    strength = exp(-2.0 * strength);
    return mix(sky_color, color, vec3<f32>(strength));
}

fn get_blindness_fog(dist: f32, color: vec3<f32>) -> vec3<f32> {
    let d = clamp(1.0 - exp(-2.0 * dist / 12.0), 0.0, 1.0) * max(frame.darkness, frame.blindness);
    return color * (1.0 - d * 0.8);
}

fn get_atm_fog(dist: f32, color: vec3<f32>, world_pos: vec3<f32>, sky_color: vec3<f32>) -> vec3<f32> {
    var d = min(dist / 320.0, 1.0);
    d = 1.0 - exp(-2.0 * d);
    var visibility = dawn_strength() * 0.4 + night_strength() * 0.8;
    visibility = max(visibility, frame.rain * 0.8) * outdoors();
    visibility = visibility * (0.25 * 0.7);   // the mist's strength (0.25)
    visibility = visibility * (1.0 - fbm2(world_pos.xz, 1) * 0.7);

    let height_falloff = select(0.0, smoothstep(55.0, 75.0, world_pos.y) - smoothstep(75.0, 130.0, world_pos.y), world_pos.y >= 50.0);

    let factor = d * height_falloff * visibility;
    return mix(color, sky_color, vec3<f32>(factor * 0.8));
}

// The underwater colour treatment: the pack's own tint, distinct from the
// engine's underwater fog.
fn underwater_tint(dist: f32, color: vec3<f32>, cols: LightColors) -> vec3<f32> {
    if frame.eye_in != 1u {
        return color;
    }
    let water = to_linear(vec3<f32>(f_water().r * 0.8, f_water().g * 0.85, f_water().b * 0.9)) * (cols.sky_ground * 0.9 + cols.sky_top * 0.9);
    let biome = mix_preserve_c1lum(water, to_linear(frame.fog_color), f_biome_water() * 0.7);
    let d = clamp(dist / 80.0, 0.0, 1.0);
    return mix_preserve_c1lum(color, biome, d * 0.9);
}

// ---- reconstruct a world position (this line's post prelude has depth_at but
// no view_position; the matrices are the same) ---------------------------------

fn recon_world(uv: vec2<f32>, depth: f32) -> vec3<f32> {
    let clip = vec4<f32>(uv.x * 2.0 - 1.0, 1.0 - uv.y * 2.0, depth, 1.0);
    let view = frame.projection_inverse * clip;
    return (frame.view_inverse * vec4<f32>(view.xyz / view.w, 0.0)).xyz;
}

// Project a camera-relative world point to screen.
fn recon_screen(world: vec3<f32>) -> vec3<f32> {
    let view = (frame.view * vec4<f32>(world, 1.0)).xyz;
    let clip = frame.projection * vec4<f32>(view, 1.0);
    let sc = clip.xyz / vec3<f32>(clip.w);
    return vec3<f32>(sc.x * 0.5 + 0.5, 0.5 - sc.y * 0.5, sc.z);
}

// The view ray through a pixel, world axes (for the sky colour at a pixel).
fn recon_ray(uv: vec2<f32>) -> vec3<f32> {
    let clip = vec4<f32>(uv.x * 2.0 - 1.0, 1.0 - uv.y * 2.0, -1.0, 0.0);
    return normalize((frame.view_inverse * clip).xyz);
}
