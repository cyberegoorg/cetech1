vec2 tex_coord = gl_FragCoord.xy * u_viewTexel.xy;
vec3 color = texture2D(get_hdr_sampler(), tex_coord);
vec3 bloom_color = texture2D(get_bloom_sampler(), tex_coord);
vec3 hdr_color = mix(color, bloom_color, 0.04);
//  vec3 hdr_color = color + bloom;

vec4 tonemaped_color = vec4_splat(0);

const uint tonemap_type = floatBitsToUint(load_params().x);
switch(tonemap_type) {
    default:
    case TONEMAP_TYPE_ACESS: {
        tonemaped_color = vec4(toGammaAccurate(toAcesFilmic(hdr_color)), 1);
        break;
    }

    case TONEMAP_TYPE_UNCHARTED: {
        tonemaped_color = vec4(toGammaAccurate(hable_map(hdr_color)), 1);
        break;
    }

    case TONEMAP_TYPE_LUMINANCE_DEBUG: {
        tonemaped_color = vec4(tonemap_display_range(hdr_color), 1);
        break;
    }
}

output.color0 = tonemaped_color;
