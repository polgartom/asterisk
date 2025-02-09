draw_frame :: (second_elapsed: bool, current_time: float64) {
    x, y, width, height := get_dimensions(my_window, true);
    ui_per_frame_update(my_window, width, height, current_time);

    frame_rect := get_rect(0.0, 0.0, xx width, xx height);

    Simp.set_shader_for_color(true);

    {
        rect := frame_rect;
        
        if editors[0].visible && editors[1].visible {
            left, right := cut_left(rect, floor(rect.w/2));

            draw_editor(*editors[0], left);
            draw_editor(*editors[1], right);

            Simp.set_shader_for_color(true);
            BORDER_COLOR :: #run Vector4.{text_color.x,text_color.y,text_color.z,text_color.w*.2};
            Simp.immediate_quad(right.x - 1.0, right.y, right.x + 1.0, right.h + right.y, BORDER_COLOR);
        }
    }

    // r=, footer := cut_top(r, window_height-footer_height);

    // Draw mouse
    // if editor_in_focus {
    //     draw_debug_mouse_character_selection();
    // }

    // Widgets
    if mode == .WIDGET {
        draw_widgets();
    }

    // Draw debug info
    if show_debug_info {

        // {
        //     // Draw crosshair
        //     Simp.set_shader_for_color();
        //     Simp.immediate_quad(window_width/2.0-1.0, 0.0, window_width/2.0, xx window_height, DEBUG_CROSSHAIR_COLOR); 
        //     Simp.immediate_quad(0.0, window_height/2.0-1.0, xx window_width, window_height/2.0, DEBUG_CROSSHAIR_COLOR); 
        // }

        #if 1 {
            // Draw fps
            ct := seconds_since_init();
            if second_elapsed {
                frametime = (ct - last_time); // frametime
                fps       = 1/frametime;
                last_showed_sim_time = last_simulation_time;
                last_rendering_time = (ct-last_time)*1000;
            }

            PrintDev("sim: %ms draw: %ms\n", formatFloat(last_showed_sim_time, trailing_width=3), formatFloat(last_rendering_time, trailing_width=2));
            PrintDev("%fps %ms %sec\n", 
                formatFloat(fps, trailing_width=0), 
                formatFloat(frametime*1000, trailing_width=2, zero_removal=FormatFloat.Zero_Removal.NO), 
                formatFloat(last_time, trailing_width=2, zero_removal=FormatFloat.Zero_Removal.NO)
            );
        }

        row := 1;
        max := 0;
        line_height := get_line_height();
        bottom: float32 = footer_height + line_height;

        for #v2 < debug_infos {
            s := it;
            ln := s[s.count-1] == #char "\n";
            if ln then s.count -= 1;

            rmargin := 10;

            w := Simp.prepare_text(my_font, s);
            bottom += line_height;
            Simp.draw_prepared_text(my_font, xx (window_width - w - rmargin), xx (bottom), .{.8, .8, .8, 1});

            if ln then row += 1;

            free(it.data);
        }

        array_reset(*debug_infos);
    }
}

draw_editor :: (using editor: *Editor, rect: Rect) {
    left_pad := cast(float32) primary_font.em_width;
    
    r, footer_r := cut_top(rect, window_height-footer_height);
    _, r= := cut_left(r, left_pad);

    // Simp.immediate_quad(pad_r.x, pad_r.y, pad_r.x + pad_r.w, pad_r.h + pad_r.y, PURPLE_COLOR);

    buffer := editor.active_buffer;

    if should_recalc_editor_offsets {
        should_recalc_editor_offsets = false;

        cw := em(1.0, primary_font);
        ch := primary_font.character_height;

        x_pad := left_pad   * 2.0;
        y_pad := footer_r.h * 2.0;

        mx    := get_cursor_x(buffer, *buffer._cursor);
        relmx := mx - editor.left_offset - r.w;
        if relmx + x_pad + cw > 0 {
            editor.left_offset += abs(relmx + x_pad + cw);
        } else if abs(relmx - x_pad) > r.w {
            editor.left_offset -= abs(relmx - x_pad) - r.w;
            if editor.left_offset < 0 then editor.left_offset = 0;
        }

        my    := get_line_height(find_row_index(buffer, buffer._cursor.pos));
        relmy := r.h - my + editor.top_offset;
        if relmy - y_pad < 0 {
            editor.top_offset += abs(relmy - y_pad);
        } else if relmy + y_pad > r.h + r.y {
            editor.top_offset -= (relmy + y_pad) - (r.h+r.y);
            if editor.top_offset < 0 then editor.top_offset = 0;
        }
    }

    // Draw text
    if buffer.count {
        using editor;
        using buffer;

        avg_row_render_time: float64 = 0.0;
        rendered_rows := 0;

        line_height := get_line_height();

        start_row: s64 = xx (top_offset / line_height); 
        start_row = clamp(start_row - 1, 0, row_table.count-1);

        end_row := last_visible_row_index(editor, buffer);

        color := text_color;
        if active_editor != editor then color = #run SetVector4ColorAlpha(text_color, .8);

        colors: [..] Vector4;
        array_add(*colors, text_color);

        for row_index: start_row..end_row {
            row := row_table[row_index];
            if row.size == 0 continue;

            time := seconds_since_init() * 1000;

            bottom := (r.h + r.y) - (line_height*(row_index+1)) + top_offset;

            left := r.x;
            line_text := slice(buffer, row.end - row.size, row.size);
            Font.prepare_text(primary_font, line_text, start_x = xx left_offset, max_width = cast(s64)(r.w-left_pad));
            Font.draw_prepared_text(primary_font, xx left, xx bottom, color);

            avg_row_render_time += (seconds_since_init() * 1000 - time);
            rendered_rows += 1;
        }

        avg_row_render_time = ifx rendered_rows > 0 then avg_row_render_time/rendered_rows else 0.0;
        PrintDev("draw_rows: %/% %ms avg/row\n", rendered_rows, row_table.count, formatFloat(avg_row_render_time, trailing_width=3));
    }

    // @Temporary
    if mode == .WIDGET && active_editor == editor && search_text {
        // Draw search_widget's results

        Simp.set_shader_for_color(true);

        using editor;
        using buffer;
        
        push_scissor(rect);
        defer pop_scissor();

        width := measure_text_width(search_text);

        start_row_index := first_visible_row_index(editor, buffer);
        start_row := row_table[start_row_index];

        end_row_index := last_visible_row_index(editor, buffer);
        end_row := row_table[end_row_index];

        for pos: search_widget.occurences {
            if pos < start_row.start || pos > end_row.end continue;

            row_index := find_row_index(buffer, pos);
            row := row_table[row_index];

            left   := r.x - left_offset;
            bottom := (rect.h + rect.y) - get_line_height(row_index+1) + editor.top_offset;

            if pos != row.start {
                t := get_row_as_string(buffer, row);
                t = slice(t, 0, pos - row.start);
                left += Simp.prepare_text(primary_font, t);
            }

            draw_character_height_aware_rect(primary_font, left, cast(float32)width, bottom, HIGHLIGHT_COLOR);
        }
    }

    draw_selection(editor, buffer, r);
    draw_cursor(editor, buffer, r);

    {
        push_scissor(footer_r);
        defer pop_scissor();

        footer := footer_r;

        // Draw footer
        font := primary_font_xs;

        Simp.set_shader_for_color(true);
        
        color := FOOTER_COLOR;
        if active_editor != editor then color = #run SetVector4ColorAlpha(FOOTER_COLOR, .6);
        Simp.immediate_quad(footer.x, footer.y, footer.x + footer.w, footer.h, color);

        width := 0;
        left := footer.x + 10;
        center := footer.y + footer.h / 2 - font.character_height / 2;

        {
            // Draw buffer's file info
            using buffer;

            path := filepath;
            if path {
                workdir := get_working_directory();
                path_overwrite_separators(workdir, #char "/");
                if begins_with(path, workdir) {
                    advance(*path, workdir.count + 1); // +1 for the path separator
                    assert(path.count > 0);
                }
            } else {
                path = "Untitled";
            }

            fileinfo := tprint(
                "%1%2%3",
                path,
                ifx !exists_on_disk then " <new>" else "",
                ifx dirty           then " (unsaved)"  else "",
            );

            width = Simp.prepare_text(font, fileinfo);
            Simp.draw_prepared_text(font, xx left, xx center, .{.0,.0,.0,1.0});

            left += width;
        }

        {
            count := count_buffers(editor, initialized=true);
            relative_index := 0;
            for * editor.buffers {
                if !it.initialized continue;
                
                relative_index += 1;
                if it == buffer break;
            }

            buffer_info := tprint(" | %/%", relative_index, count);
            width = Simp.prepare_text(font, buffer_info);
            Simp.draw_prepared_text(font, xx left, xx center, .{.0,.0,.0,1.0});
        }

        row := find_row_index(buffer, buffer._cursor.pos) + 1;
        col := byte_pos_to_col_pos(buffer, buffer._cursor.pos) + 1;
        total_row_percent := ceil((row / cast(float32)buffer.row_table.count) * 100.0);
        row_col_info := tprint("%\% Ln % Col %", total_row_percent, row, col);
        width = Simp.prepare_text(font, row_col_info);
        RIGHT_PAD :: 1.1;
        Simp.draw_prepared_text(font, xx (footer.x + footer.w - width * RIGHT_PAD), xx center, .{.0,.0,.0,1.0});
    }
}

draw_cursor :: (editor: *Editor, buffer: *Buffer, r: Rect) {
    c  := *buffer._cursor;
    
    row_index := find_row_index(buffer, c.pos);
    row := buffer.row_table[row_index];
    line_text := get_row_as_string(buffer, row);
    line_text  = slice(line_text, 0, c.pos - row.start);

    cx := r.x + Font.prepare_text(primary_font, line_text, start_x = xx editor.left_offset, max_width = xx r.w);
    cw := em(1.0, primary_font);
    ch := primary_font.character_height;
    
    bottom := (r.h + r.y) - get_line_height(row_index + 1) + editor.top_offset;

    Simp.set_shader_for_color(true);

    {
        color := ifx active_editor == editor then CURSOR_COLOR else Vector4.{1,1,1,.4};
        Simp.immediate_quad(cast(float32)cx, bottom + (ch-ch*0.1), cast(float32)(cx + cw), bottom - (ch/2-(ch*0.2)), color);
    }
    
    #if CURRENT_LINE_INDICATOR_STYLE == .FRAME {
        p1 := bottom + (ch-ch*0.1);
        p2 := bottom - (ch/2-(ch*0.2)) - 1.0;

        Simp.immediate_quad(r.x, p1, r.x + r.w, p1 + CURRENT_LINE_INDICATOR_FRAME_WIDTH, CURRENT_LINE_INDICATOR_COLOR); // top
        Simp.immediate_quad(r.x, p2, r.x + r.w, p2 + CURRENT_LINE_INDICATOR_FRAME_WIDTH, CURRENT_LINE_INDICATOR_COLOR); // bottom
    }
    
    #if CURRENT_LINE_INDICATOR_STYLE == .HIGHLIGHT {
        p1 := bottom + (ch-ch*0.1);
        p2 := bottom - (ch/2-(ch*0.2)) - 1.0;

        Simp.immediate_quad(r.x, p1, r.x + r.w, p2, CURRENT_LINE_INDICATOR_COLOR);
    }

    if active_editor == editor && buffer.count {
        character := get_character_as_string_at(buffer, xx c.pos);
        Font.prepare_text(primary_font, character);
        Font.draw_prepared_text(primary_font, xx cx, xx bottom, CURSOR_COLOR_TEXT);
    }
}

draw_selection :: (editor: *Editor, buffer: *Buffer, r: Rect) {
    Simp.set_shader_for_color(true);
    
    left_pad := cast(float32) primary_font.em_width;

    c := *buffer._cursor;
    if !has_selection(c) return;

    ch := primary_font.character_height;
    line_height := get_line_height();

    sel_start, sel_end := selected_range(c);
    start_row := find_row_index(buffer, sel_start);
    end_row := find_row_index(buffer, sel_end);

    s := slice(buffer, sel_start, sel_end - sel_start);

    push_scissor(r);
    defer pop_scissor();

    for row_index: start_row..end_row {
        row := buffer.row_table[row_index];
        row_start := row.end-row.size;
        row_end   := row.end;

        left  := -editor.left_offset + r.x;
        width := 0.0;

        t := slice(buffer, row_start, row.size);

        // Convert the first N unselected bytes in the row to pixels
        start := max(sel_start, row_start) - row_start;
        t1 := slice(t, 0, start);
        if t1.count then left += Simp.prepare_text(primary_font, t1);

        // Convert the remained bytes in the row to pixels
        t2 := advance(t, start);
        t2.count -= row_end - min(sel_end, row_end);
        if t2.count then width += Simp.prepare_text(primary_font, t2);
                    else width += primary_font.em_width;

        bottom := (r.h+r.y) - (line_height*(row_index+1)) + editor.top_offset;
        Simp.immediate_quad(left, bottom + (ch-ch*0.1), left+width, bottom - (ch/2-(ch*0.2)), SELECTION_COLOR); 
    }

}

draw_widgets :: () {
    proc := default_theme_procs[current_theme];
    my_theme = proc();
    set_default_theme(my_theme);  // Just in case we don't explicitly pass themes sometimes...!

    // print("> active_widget: %\n", active_widget);

    if active_widget == {
        case Search_Widget;
            update_search_widget();
        case File_Browser_Widget;
            update_file_browser_widget();
    }

    // k := window_height * .1;
    // w := window_width*0.5-4*k;
    // Simp.immediate_quad(0.0, 9*k, w, 9*k+3, CURSOR_COLOR);
    // Simp.immediate_quad(window_width - w, 9*k, xx window_width, 9*k+3, CURSOR_COLOR);
}

draw_text :: inline (s: string, left: s64, bottom: s64, color: Vector4) -> s64 {
    w := Simp.prepare_text(my_font, s);
    Simp.draw_prepared_text(my_font, left, bottom, color);
    return w;
}

draw_character_height_aware_rect :: (font: *Simp.Dynamic_Font, left: float32, width: float32, bottom: float32, color: Vector4) {
    ch := font.character_height;

    Simp.immediate_quad(left, bottom + (ch-ch*0.1), left+width, bottom - (ch/2-(ch*0.2)), color);
}

// draw_highlighted_prepared_text :: (font: *Simp.Dynamic_Font, x: s64, y: s64, row: Row_Info, fallback_color := Vector4.{1, 1, 1, 1}) {
//     Simp.generate_quads_for_prepared_text(font, x, y, 0);
//     draw_highlighted_generated_quads(font, row, fallback_color);
// }

// draw_highlighted_text :: (font: *Simp.Dynamic_Font, x: s64, y: s64, text: string, buffer: *Buffer, row_index: s64, fallback_color := Vector4.{1, 1, 1, 1}) -> width: s64 {
//     width := Simp.prepare_text(font, text, 0);
//     Simp.generate_quads_for_prepared_text(font, x, y, 0);
//     draw_highlighted_generated_quads(font, buffer, row_index, fallback_color);

//     return width;
// }

draw_highlighted_generated_quads :: (font: *Simp.Dynamic_Font, text: string) {
    #import "GL";

    Simp.CheckInit();
    quads := font.current_quads;

    if state.current_shader Simp.immediate_flush();

    Simp.set_shader_for_text();
    Simp.immediate_begin();

    glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);
    glEnable(GL_BLEND);

    draw_letter_quad :: (font: *Simp.Dynamic_Font, quad: Simp.Font_Quad, color: Vector4) {
        page := quad.glyph.page;

        if page.bitmap_data.width  <= 1 return;
        if page.bitmap_data.height <= 1 return;

        using quad;
        uv0 := Vector2.{u0, v0};
        uv1 := Vector2.{u1, v0};
        uv2 := Vector2.{u1, v1};

        uv3 := Vector2.{u0, v1};

        inline Simp.immediate_quad(p0, p1, p2, p3, color, uv0, uv1, uv2, uv3);
    }

    glTexParameterf(GL_TEXTURE_2D, GL_TEXTURE_MAX_ANISOTROPY_EXT, 1);

    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);

    last_texture: s64 = -1;
    color := text_color;

    for quad, i: quads {
        page := quad.glyph.page;
        map  := *page.texture;

        if page.dirty {
            page.dirty = false;
            Simp.texture_load_from_bitmap(map, page.bitmap_data);
        }

        if map.gl_handle != last_texture {
            Simp.immediate_flush();
            handle := map.gl_handle;
            last_texture = handle;

            shader := state.current_shader;
            loc := glGetUniformLocation(shader.gl_handle, "text_sampler");
            if loc < 0  log_error("Unable to find text_sampler in shader_text!");
            glActiveTexture(GL_TEXTURE0);
            glBindTexture(GL_TEXTURE_2D, handle);  // Bind handle to slot 0.
            glUniform1i(loc, 0);
        }

        inline draw_letter_quad(font, quad, color);
    }

    Simp.immediate_flush();

    glDisable(GL_BLEND);
}

draw_debug_mouse_character_selection :: (editor: *Editor, r: Rect) {
    buffer := editor.active_buffer;

    mx, my, ok := get_mouse_pointer_position(right_handed=false);
    if (ok) {
        row_index := get_row_index_from_y_px(xx my, y_is_relative=true);
        if row_index != -1 {
            row_str := get_row_as_string(buffer, row_index);
            width := measure_text_width(row_str);
            bottom  := (r.h+r.y) - get_line_height(row_index+1) + editor.top_offset;
            ch      := my_font.character_height;
            Simp.immediate_quad(0.0, bottom + (ch-ch*0.1), xx width, bottom - (ch/2-(ch*0.2)), Vector4.{.3, .21, .21, .5});
        }

        approx_row := cast(s64)floor((my+editor.top_offset) / get_line_height());

        first := first_visible_row_index(editor, buffer);
        last  := last_visible_row_index(editor, buffer);
        for i: first..last {
            if i == approx_row {
                s := get_row_as_string(buffer, i);

                ch      := my_font.character_height;
                bottom  := (r.h+r.y) - get_line_height(approx_row+1) + editor.top_offset;
                // width   := Simp.prepare_text(my_font, s);
                // Simp.immediate_quad(0.0, bottom + (ch-ch*0.1), xx width, bottom - (ch/2-(ch*0.2)), Vector4.{.3, .21, .21, .5});

                cw := 0;
                left := 0.0;
                while s.count {
                    cw = Simp.get_character_width_in_pixels(my_font, s.data, .LEFT_JUSTIFIED);
                    if cast(float)mx <= left break;
                    
                    left += cw;
                    
                    bytes := 1 + trailingBytesForUTF8[s[0]];
                    s = advance(s, bytes);
                }
                
                if cw == 0 {
                    cw = my_font.em_width;
                    Simp.immediate_quad(0.0, bottom + (ch-ch*0.1), cast(float)cw, bottom - (ch/2-(ch*0.2)), Vector4.{1.0, .5, .3, .9});
                } else {
                    Simp.immediate_quad(left-cw, bottom + (ch-ch*0.1), left, bottom - (ch/2-(ch*0.2)), Vector4.{1.0, .5, .3, .9});
                }

                break;
            }
        }
    }
}

DEBUG_CROSSHAIR_COLOR :: Vector4.{5.0/255.0, 6.0/255.0, 10.0/255.0, 1.0};
PURPLE_COLOR :: Vector4.{.5, .3, .8, 1.0};
FOOTER_COLOR :: Vector4.{209.0/255.0, 181.0/255.0, 142.0/255.0, 1.0};

#scope_file

Font :: #import, file "font.jai";