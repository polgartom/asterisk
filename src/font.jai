prepare_text :: (font: *Dynamic_Font, text: string, start_x: s64, max_width: s64, effect_flags: Font_Effects = 0) -> (width: s64) {
    convert_to_temporary_glyphs(font, text, effect_flags, start_x, max_width);
    return font.temporary_glyphs_width_in_pixels;
}

convert_to_temporary_glyphs :: (using font: *Dynamic_Font, s: string, effect_flags: Font_Effects, start_x: s64, max_width: s64) {
    glyph_conversion_failed = false;

    array_reset(*font.temporary_glyphs);
    array_reset(*font.temporary_glyphs_byte_offsets);

    left := 0;
    temporary_glyphs_width_in_pixels = 0;

    if !s return;

    original_string := s;

    t := s.data;
    while t < s.data + s.count {
        t_str: string;
        t_str.data = t;
        t_str.count = 1;
        utf32 := one_utf32_char(t);

        glyph := find_or_create_glyph_utf8(font, t);
        if glyph {
            left += glyph.advance;
            if left >= start_x {
                add_glyph_to_temporaries(font, glyph, t - s.data);
            }
        }

        t = unicode_next_character(t);

        if temporary_glyphs_width_in_pixels >= max_width break;
    }

    if effect_flags then do_glyph_substitutions(font, effect_flags);
}

prepare_text :: (font: *Dynamic_Font, text: string, effect_flags: Font_Effects = 0) -> (width: s64) {
    convert_to_temporary_glyphs(font, text, effect_flags);
    return font.temporary_glyphs_width_in_pixels;
}

convert_to_temporary_glyphs :: (using font: *Dynamic_Font, s: string, effect_flags: Font_Effects) {
    glyph_conversion_failed = false;

    array_reset(*font.temporary_glyphs);
    array_reset(*font.temporary_glyphs_byte_offsets);

    temporary_glyphs_width_in_pixels = 0;

    if !s return;

    original_string := s;

    t := s.data;
    while t < s.data + s.count {
        t_str: string;
        t_str.data = t;
        t_str.count = 1;
        utf32 := one_utf32_char(t);

        glyph := find_or_create_glyph_utf8(font, t);
        if glyph {
            add_glyph_to_temporaries(font, glyph, t - s.data);
        }

        t = unicode_next_character(t);
    }

    if effect_flags then do_glyph_substitutions(font, effect_flags);
}

generate_quads_for_prepared_text :: (font: *Dynamic_Font, x: s64, y: s64, effect_flags: Font_Effects) {
    assert(font != null);

    array_reset_keeping_memory(*font.current_quads);
    array_reserve(*font.current_quads, font.temporary_glyphs.count);

    sx := cast(float) x;
    sy := cast(float) y;

    // @Speed!
    for info: font.temporary_glyphs {
        if !info.page continue;

        sx1 := sx  + cast(float) info.offset_x;
        sx2 := sx1 + cast(float) info.width;

        sy1, sy2: float = ---;
        if context.simp.coordinate_system == .LEFT_HANDED {
            sy1 = sy  - cast(float) info.ascent;
            sy2 = sy1 + cast(float) info.height;
        } else {
            sy2 = sy  + cast(float) info.ascent;
            sy1 = sy2 - cast(float) info.height;
        }
    

        quad: Font_Quad = ---;
        quad.glyph = info;
        quad.p0 = .{sx1, sy1};
        quad.p1 = .{sx2, sy1};
        quad.p2 = .{sx2, sy2};
        quad.p3 = .{sx1, sy2};

        width  := info.page.bitmap_data.width;  // *Not* map.width, as map may be dirty.
        height := info.page.bitmap_data.height; // Ibid.

        quad.u0 = info.x0 / cast(float) width;
        quad.u1 = (cast(float) info.x0 + info.width) / width;

        if context.simp.coordinate_system == .LEFT_HANDED {
            quad.v1 = info.y0 / cast(float) height;
            quad.v0 = (cast(float) info.y0 + info.height) / height;
        } else {
            quad.v0 = info.y0 / cast(float) height;
            quad.v1 = (cast(float) info.y0 + info.height) / height;
        }

        array_add(*font.current_quads, quad);
		sx += cast(float) info.advance;

    }
}

find_or_create_glyph :: (using font: *Dynamic_Font, utf32: u32, glyph_index: u32, hash_key: int) -> *Glyph_Data {

    data, success := table_find(*font.glyph_lookup, hash_key);
    if success  return data;

    face := font.private1;  // XXX Why not using?

    // @Move: Make this happen at font construction time.  @Speed.
    // However we can't right now, because we share this face among
    // multiple Dynamic_Fonts...

    error := FT_Set_Pixel_Sizes(face, 0, cast(u32) font.character_height);    // XXX WHy not using?
    assert(!error);


    if utf32 {
        glyph_index = FT_Get_Char_Index(face, utf32);
        if !glyph_index {
            log_error("Unable to find a glyph in font '%' for utf32 character %.\n", font.name, utf32);
            glyph_index = glyph_index_for_unknown_character;
            // print("assigning glyph_index %\n", glyph_index);
        }

        if glyph_index {
            error := FT_Load_Glyph(face, glyph_index, FT_LOAD_RENDER);
            assert(!error);
        }
    } else {
        assert(glyph_index >= 0);
        error := FT_Load_Glyph(face, glyph_index, FT_LOAD_RENDER);
        assert(!error);
    }

    data = cast(*Glyph_Data) get(*glyph_and_line_pool, size_of(Glyph_Data));
    data.utf32 = utf32;
    data.glyph_index_within_font = glyph_index;

    copy_glyph_to_bitmap(face, data);

    table_add(*font.glyph_lookup, hash_key, data);

    return data;
}

find_or_create_glyph :: (font: *Dynamic_Font, utf32: u32) -> *Glyph_Data {
    return find_or_create_glyph(font, utf32, 0, utf32);
}

find_or_create_glyph_utf8 :: (font: *Dynamic_Font, utf8: *u8) -> *Glyph_Data {  // XXX Overloading
    utf32 := one_utf32_char(utf8);
    return find_or_create_glyph(font, utf32);
}

add_glyph_to_temporaries :: inline (font: *Dynamic_Font, glyph: *Glyph_Data, byte_offset: int) {
    assert(glyph != null);

    assert(font.temporary_glyphs.count == font.temporary_glyphs_byte_offsets.count);
    array_add(*font.temporary_glyphs, glyph);
    array_add(*font.temporary_glyphs_byte_offsets, byte_offset);
    assert(font.temporary_glyphs.count == font.temporary_glyphs_byte_offsets.count);

    font.temporary_glyphs_width_in_pixels += glyph.advance;

    //
    // FreeType returns glyph index 0 for undefined glyphs... just signal
    // the condition that this happened.
    //

    if glyph.glyph_index_within_font == 0 font.glyph_conversion_failed = true;
}

draw_prepared_text :: (font: *Dynamic_Font, x: s64, y: s64, color := Vector4.{1, 1, 1, 1}, effects: Font_Effects = 0) {
    generate_quads_for_prepared_text(font, x, y, effects);
    draw_generated_quads(font, color);
}

one_utf32_char :: inline (s: *u8) -> u32 {
    utf32 := character_utf8_to_utf32(s, DUMMY_SOURCE_LENGTH);  // @BufferLength @Robustness
    return utf32;
} @NoProfile

do_glyph_substitutions :: (using font : *Dynamic_Font, effect_flags: Font_Effects) {
    if effect_flags & .LINING_FIGURES {
        // Substitute lining figures...
        for * ptr : temporary_glyphs {
            glyph := ptr.*;
            sub := single_substitute(font, feature_lining_numbers, glyph);
            if sub then ptr.* = sub;
        }
    }

    if effect_flags & .SMALLCAPS {
        // Substitute smallcaps...
        for * ptr : temporary_glyphs {
            // @Hack for Karmina; if we have LINING_FIGURES and SMALLCAPS selected,
            // then just do lining figures if it's a digit... otherwise we end
            // up converting digits to smallcaps and that doesn't look right.

            glyph := ptr.*;
            if effect_flags & .LINING_FIGURES {
                utf32 := glyph.utf32;
                if ((utf32 < 127) && isdigit(utf32)) continue;
            }

            sub := single_substitute(font, feature_smallcaps, glyph);
            if sub ptr.* = sub;
        }
    }
}

single_substitute :: (using font: *Dynamic_Font, feature: *Font_Feature, orig: *Glyph_Data) -> *Glyph_Data {
    if !feature return orig;

    orig_utf32 := orig.utf32;

    for * table : feature.lookup_tables {  // XXX Array simplify

        for * subtable : table.subtables {
            index := get_index_within_coverage_table(subtable.coverage_table, orig);
            if index == -1 return orig;

            if table.lookup_type == 1 {
                if subtable.format == 1 {  // SingleSubstFormat1
                    glyph_id := orig.glyph_index_within_font + cast(u32) subtable.delta_glyph_id;
                    new_glyph := find_or_create_glyph(font, 0, glyph_id, glyph_id_to_hash_key(glyph_id));
                    if !new_glyph return null;

                    new_glyph.utf32 = orig_utf32;
                    return new_glyph;
                } else if subtable.format == 2 {  // SingleSubstFormat2
                    assert(index < subtable.glyphs.count);

                    glyph_id := subtable.glyphs[index];
                    new_glyph := find_or_create_glyph(font, 0, glyph_id, glyph_id_to_hash_key(glyph_id));
                    if !new_glyph return null;

                    new_glyph.utf32 = orig_utf32;
                    return new_glyph;
                } else {
                    assert(false);
                }
            }

            if table.lookup_type == 2 {
                entry := *subtable.sequence_table[index];

                glyph_id := entry.glyphs[0];
                new_glyph := find_or_create_glyph(font, 0, glyph_id, glyph_id_to_hash_key(glyph_id));
                if !new_glyph return null;

                //
                // @Hack: If for some reason there was more than 1 glyph in this table,
                // we just use the first one... for now we are just using this for
                // SmallCaps so it should not be a big deal.
                //
                new_glyph.utf32 = orig_utf32;
                return new_glyph;
            }
        }
    }

    return orig;
}

get_index_within_format_1_coverage_table :: (table: *Font_Coverage_Table, glyph: *Glyph_Data) -> s64 {
    // @Cleanup: This whole proc can be replaced by a generic array find.

    for table.glyphs
        if it == glyph.glyph_index_within_font
            return it_index;

    return -1;
}

get_index_within_format_2_coverage_table :: (table: *Font_Coverage_Table, glyph: *Glyph_Data) -> s64 {
    glyph_id := cast(s32) glyph.glyph_index_within_font;  // Because record.* are s32... sigh.

    for table.range_records {
        if glyph_id < it.start continue;
        if glyph_id > it.end continue;

        delta := glyph_id - it.start;
        return it.start_coverage_index + delta;
    }

    return -1;
}

get_index_within_coverage_table :: (table: *Font_Coverage_Table, glyph: *Glyph_Data) -> s64 {
    if table.format == 1 return get_index_within_format_1_coverage_table(table, glyph);
    if table.format == 2 return get_index_within_format_2_coverage_table(table, glyph);

    assert(false);

    return -1;
}

copy_glyph_to_bitmap :: (face: FT_Face, data: *Glyph_Data) {
    b := *face.glyph.bitmap;

    data.width  = b.width;
    data.height = b.rows;
    data.advance = cast,trunc(s16) (face.glyph.advance.x >> 6);   // @Cleanup: reduce the number of casts?
    data.offset_x = cast,trunc(s16) face.glyph.bitmap_left;
    data.offset_y = cast,trunc(s16) face.glyph.bitmap_top;

    metrics := *face.glyph.metrics;
    data.ascent = cast,trunc(s16) (metrics.horiBearingY >> 6);  // This trunc seemed necessary because at least one font gave us weird data here. Maybe it's a buggy font, or maybe we are doing something weird / dumb.

    font_line := get_font_line(b.width, b.rows);
    if !font_line {
        // Fail! ... They get kind-of garbage.
        data.x0 = 0;
        data.y0 = 0;
        log_error("font_line is null!\n");
        assert(false);
        data.page = null;
        return;
    }

    dest_x := font_line.bitmap_cursor_x;
    dest_y := font_line.bitmap_cursor_y;

    data.x0 = dest_x;
    data.y0 = dest_y;
    data.page = font_line.page;

    bitmap := font_line.page.bitmap_data;

    rows  := cast(s32) b.rows; // FreeType has changed the rows and width types to unsigned, and they may be zero
    width := cast(s32) b.width;
    for j : 0..rows-1 {
        for i : 0..width-1 {
            source_pixel := b.buffer[(rows - 1 - j) * b.pitch + i];

            dest_pixel := bitmap.data.data + ((dest_y + j) * bitmap.width + (dest_x + i)) * 4;
            dest_pixel[0] = 255;
            dest_pixel[1] = 255;
            dest_pixel[2] = 255;
            dest_pixel[3] = source_pixel;
        }
    }

    font_line.bitmap_cursor_x += cast(s16) b.width;
    font_line.page.dirty = true;
}

get_font_line :: (width: int, height: int) -> *Font_Line {
    for page : font_pages {
        line := find_line_within_page(page, width, height);
        if line return line;
    }

    page := make_font_page();
    if !page return null;

    array_add(*font_pages, page);

    return find_line_within_page(page, width, height);  // If we didn't find it somehow, we lose!
}

find_line_within_page :: (page: *Font_Page, width: int, height: int) -> *Font_Line {
    bitmap := page.bitmap_data;

    for page.lines {
        if it.height < height continue;  // Line too short!
        if ((it.height * 7) / 10) > height continue;  // Line too tall!

        if bitmap.width - it.bitmap_cursor_x < width continue;  // No room at end of line!

        return it;  // Found one!
    }

    // If there's not enough room to start a new line, bail.
    height_remaining := bitmap.height - page.line_cursor_y;
    if height_remaining < height return null;

    // Or if for some reason the page is too narrow for the character...
    // In this case, starting a new line would not help!
    if bitmap.width < width return null;

    // Start a new line... With some extra space for expansion if we have room.
    desired_height := (height * 11) / 10;

    if desired_height > height_remaining desired_height = height_remaining;

    line : *Font_Line = get(*glyph_and_line_pool, size_of(Font_Line));
    if !line return null;

    line.page = page;
    line.bitmap_cursor_x = 0;
    line.bitmap_cursor_y = page.line_cursor_y;
    line.height = desired_height;

    array_add(*page.lines, line);

    page.line_cursor_y += cast(s16) desired_height;

    return line;
}

make_font_page :: () -> *Font_Page {
    page := New(Font_Page);

    bitmap := New(Bitmap);
    // @Speed: Make the bitmap R8!
    bitmap_alloc(bitmap, xx page_size_x, xx page_size_y, .RGBA8);
    page.bitmap_data = bitmap;

    return page;
}

glyph_and_line_pool : Pool;
ft_library    : FT_Library;
fonts_initted := false;

// We probably should make different page sizes
// for different fonts.
page_size_x := 2048;
page_size_y := 1024;

// Wacky structures used in the font file format.

loaded_file_fonts   : [..] *Loaded_Font;
loaded_memory_fonts : [..] *Loaded_Font;
font_pages    : [..] *Font_Page;
dynamic_fonts : [..] *Dynamic_Font;

DUMMY_SOURCE_LENGTH :: 1000;  // This is stupid.

#scope_file

#import "Simp";

#import "freetype-2.12.1";
#import "Hash_Table";
#import "Hash";
#import "Unicode";
#import "Pool";
#import "File";
#import "Basic";  // For free.
#import "Math";  // For Vector2, Vector3, Vector4.