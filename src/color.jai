#add_context color_intensity: Vector4 = #run v4(1.0);

reset_color_intensity :: () {
    context.color_intensity = v4(1.0);
}

map_color_to_vec4 :: inline (color: Color) -> Vector4 {
    return COLOR_MAP[cast(s64) color] * context.color_intensity;
}

map_default_color_to_vec4 :: inline (color: Color) -> Vector4 {
    return DEFAULT_COLOR_MAP[cast(s64) color] * context.color_intensity;
}

darken :: (color: Vector4, amount: float) -> Vector4 {
    result: Vector4;

    result.x = lerp(color.x, 0, amount);
    result.y = lerp(color.y, 0, amount);
    result.z = lerp(color.z, 0, amount);
    result.w = color.w;

    return result;
}

whiten :: (color: Vector3, amount: float) -> Vector3 {
    result: Vector3;

    result.x = lerp(color.x, 1, amount);
    result.y = lerp(color.y, 1, amount);
    result.z = lerp(color.z, 1, amount);

    return result;
}

whiten :: (color: Vector4, amount: float) -> Vector4 {
    result: Vector4;

    result.xyz = whiten(color.xyz, amount);
    result.w = color.w;

    return result;
}

is_bright :: (color: Vector4) -> bool {
    // color.rgb in 0..1 range
    r := color.x;
    g := color.y;
    b := color.z;

    luminance := 0.2126*r + 0.7152*g + 0.0722*b;
    return luminance > 0.5;
}

COLOR_MAP_SIZE :: #run enum_highest_value(Color) + 1;
COLOR_MAP: [COLOR_MAP_SIZE] Vector4;

#no_reset DEFAULT_COLOR_MAP: [COLOR_MAP_SIZE] Vector4 = #run,stallable -> [COLOR_MAP_SIZE] Vector4 {
    ok := parse_style_section(DEFAULT_CONFIG_FILE_DATA);
    assert(ok, "parse_style_section() proc failed at compile-time\n");
    
    return COLOR_MAP;
}

Color :: enum u8 {
    NONE :: 0;

    COLOR_GREEN;

    LANG_TOKEN_KEYWORD;
    LANG_TOKEN_DIRECTIVE;
    LANG_TOKEN_COMMENT;
    LANG_TOKEN_STRING_LITERAL;
    LANG_TOKEN_NUMERIC_VALUE;
    LANG_TOKEN_PROCEDURE_CALL;
    LANG_TOKEN_ESCAPED;

    BACKGROUND;
    BACKGROUND2;
    LAYOUT_SEPARATOR;
    TEXT_DEFAULT;
    TEXT_DIMMED;
    TEXT_SELECTION;
    TEXT_SELECTION_MATCH;
    TEXT_HIGHLIGHT;
    TEXT_UNDER_CURSOR;
    TEXT_UNDER_INACTIVE_CURSOR;
    CURSOR;
    CURSOR_INACTIVE;
    CURSOR_LINE_BACKGROUND;
    FOOTER_BACKGROUND;
    FOOTER_BACKGROUND_DARKEN;
    FOOTER_TEXT;
}

/*** NICE COLORS ***/
/* 
    0xc2c2_ff_ff - purple-ish
*/