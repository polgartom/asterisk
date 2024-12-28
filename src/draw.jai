draw_frame :: (text: string, second_elapsed: bool, current_time: float64) {
    editor, buffer := get_active_editor_and_buffer();

    x, y, width, height := get_dimensions(my_window, true);
    ui_per_frame_update(my_window, width, height, current_time);

    r := get_rect(0.0, 0.0, xx width, xx height);
    r=, footer := cut_top(r, window_height-footer_height);

    if should_recalc_editor_offsets {
        should_recalc_editor_offsets = false;

        cw := my_font.em_width;
        ch := my_font.character_height;

        x_pad := cw * 2;
        y_pad := get_line_height() * 2;

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

    // Draw mouse
    if editor_in_focus {
        // mx, my, ok := get_mouse_pointer_position(right_handed=false);
        // if (ok) {
        //     row_index := get_row_index_from_y_px(xx my, y_is_relative=true);
        //     if row_index != -1 {
        //         ok, row_str := get_row_as_string(buffer, row_index);
        //         width := measure_text_width(row_str);
        //         bottom  := (r.h+r.y) - get_line_height(row_index+1) + editor.top_offset;c
        //         ch      := my_font.character_height;
        //         Simp.immediate_quad(0.0, bottom + (ch-ch*0.1), xx width, bottom - (ch/2-(ch*0.2)), Vector4.{.3, .21, .21, .5});
        //     }

            // approx_row := cast(s64)floor((my+editor.top_offset) / get_line_height());

            // first := first_visible_row_index(editor, buffer);
            // last  := last_visible_row_index(editor, buffer);
            // for i: first..last {
            //     if i == approx_row {
            //         success, s := get_row_as_string(buffer, i);
            //         assert(success);

            //         ch      := my_font.character_height;
            //         bottom  := (r.h+r.y) - get_line_height(approx_row+1) + editor.top_offset;
            //         // width   := Simp.prepare_text(my_font, s);
            //         // Simp.immediate_quad(0.0, bottom + (ch-ch*0.1), xx width, bottom - (ch/2-(ch*0.2)), Vector4.{.3, .21, .21, .5});

            //         cw := 0;
            //         left := 0.0;
            //         while s.count {
            //             cw = Simp.get_character_width_in_pixels(my_font, s.data, .LEFT_JUSTIFIED);
            //             if cast(float)mx <= left break;
                        
            //             left += cw;
                        
            //             bytes := 1 + trailingBytesForUTF8[s[0]];
            //             s = advance(s, bytes);
            //         }
                    
            //         if cw == 0 {
            //             cw = my_font.em_width;
            //             Simp.immediate_quad(0.0, bottom + (ch-ch*0.1), cast(float)cw, bottom - (ch/2-(ch*0.2)), Vector4.{1.0, .5, .3, .9});
            //         } else {
            //             Simp.immediate_quad(left-cw, bottom + (ch-ch*0.1), left, bottom - (ch/2-(ch*0.2)), Vector4.{1.0, .5, .3, .9});
            //         }

            //         break;
            //     }
            // }
        // }
    }

    // @Temporary
    if mode == .WIDGET {
        Simp.set_shader_for_color(true);

        using editor;
        using buffer;
        
        // bottom := (r.h+r.y) - (line_height*(row_index+1)) + top_offset;

        if search_text {
            width := measure_text_width(search_text);

            start_row_index := first_visible_row_index(editor, buffer);
            start_row := row_table[start_row_index];

            end_row_index := last_visible_row_index(editor, buffer);
            end_row := row_table[end_row_index];

            for pos: search_widget.occurences {
                if pos < start_row.start || pos > end_row.end continue;

                row_index := find_row_index(buffer, pos);
                row := row_table[row_index];
                
                left   := -left_offset;
                bottom := (r.h+r.y) - get_line_height(row_index+1) + editor.top_offset;

                if pos != row.start {
                    t := get_row_as_string(buffer, row);
                    t = slice(t, 0, pos - row.start);
                    left += measure_text_width(t);
                }

                draw_character_height_aware_rect(my_font, left, cast(float32)width, bottom, HIGHLIGHT_COLOR);
            }
        }
    }

    draw_selection(editor, buffer, r);

    // Draw lines
    if text.count {
        using editor;
        using buffer;

        avg_row_render_time: float64 = 0.0;
        rendered_rows := 0;

        line_height := get_line_height();

        start_row: s64 = xx (top_offset / line_height); 
        start_row = clamp(start_row - 1, 0, row_table.count-1);

        // end_row: s64 = xx ((top_offset + (r.h)) / line_height);
        // end_row = clamp(end_row + 1, end_row, row_table.count-1);
        end_row := last_visible_row_index(editor, buffer);

        for row_index: start_row..end_row {
            row := row_table[row_index];
            if row.size == 0 continue;

            time := seconds_since_init()*1000;

            // bottom := window_height - (line_height*(row_index+1)) + top_offset;
            bottom := (r.h+r.y) - (line_height*(row_index+1)) + top_offset;

            left := -left_offset;
            t := slice(text, row.end-row.size, row.size);
            left += draw_text(t, xx left, xx bottom, text_color);

            avg_row_render_time += (seconds_since_init()*1000 - time);
            rendered_rows += 1;
        }

        avg_row_render_time = ifx rendered_rows > 0 then avg_row_render_time/rendered_rows else 0.0;
        PrintDev("draw_rows: %/% %ms avg/row\n", rendered_rows, row_table.count, formatFloat(avg_row_render_time, trailing_width=3));
    }

    draw_cursor(editor, buffer, r);

    // Draw footer
    {
        Simp.set_shader_for_color(true);

        Simp.immediate_quad(footer.x, footer.y, footer.w, footer.h, FOOTER_COLOR);
        // Simp.immediate_flush();
        // Simp.immediate_quad(footer.x, footer.h, footer.w, footer.h-2, .{149.0/255.0, 121.0/255.0, 82.0/255.0, 1.0});

        left := 10;
        center := footer.y + footer.h / 2 - my_font.character_height / 2;
        // Simp.immediate_quad(footer.x, footer.h/2, footer.w, footer.h/2-2, .{149.0/255.0, 121.0/255.0, 82.0/255.0, 1.0}); // center debug

        buffer := editor.active_buffer;
        opened_file: string = ---;
        filepath := buffer.filepath;
        if filepath {
            opened_file = tprint("% %", filepath, ifx buffer.dirty then "(unsaved)" else "");
        } else {
            opened_file = tprint("<new file>");
        }

        w := Simp.prepare_text(my_font, opened_file);
        Simp.draw_prepared_text(my_font, left, xx center, .{.0,.0,.0,1.0});

        left += w;
        active_buffer_index := get_buffer_index(editor, editor.active_buffer);
        index := tprint("| %/%", active_buffer_index + 1, editor.buffers.count);
        w = Simp.prepare_text(my_font, index);
        Simp.draw_prepared_text(my_font, left, xx center, .{.0,.0,.0,1.0});

        row := find_row_index(buffer, buffer._cursor.pos)+1;
        col := byte_pos_to_col_pos(buffer, buffer._cursor.pos);
        row_col_info := tprint("Row % Col %", row, col);
        w = Simp.prepare_text(my_font, row_col_info);
        Simp.draw_prepared_text(my_font, xx (window_width-w*1.25), xx center, .{.0,.0,.0,1.0});
    }

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

draw_cursor :: (editor: *Editor, buffer: *Buffer, r: Rect) {
    Simp.set_shader_for_color(true);
    
    c  := *buffer._cursor;
    ch := my_font.character_height;

    row_index := find_row_index(buffer, c.pos);
    bottom := (r.h+r.y) - get_line_height(row_index+1) + editor.top_offset;
    cx   := get_cursor_x(buffer, c) - editor.left_offset;
    cw   := my_font.em_width;

    Simp.immediate_quad(cast(float32) cx, bottom + (ch-ch*0.1), cast(float32)(cx + cw), bottom - (ch/2-(ch*0.2)), CURSOR_COLOR);
    // Simp.immediate_quad(cast(float32) cx, bottom - ch/2, cast(float32)(cx + cw), bottom + ch, CURSOR_COLOR);

    if buffer.count {
        character := get_character_as_string_at(buffer, xx c.pos);
        draw_text(character, xx cx, xx bottom, CURSOR_COLOR_TEXT);
    }
}

draw_selection :: (editor: *Editor, buffer: *Buffer, r: Rect) {
    Simp.set_shader_for_color(true);
    
    c := *buffer._cursor;
    if !has_selection(c) return;

    ch := my_font.character_height;
    sel_start, sel_end := selected_range(c);
    start_row := find_row_index(buffer, sel_start);
    end_row := find_row_index(buffer, sel_end);

    s := slice(buffer, sel_start, sel_end - sel_start);
    // PrintDev(">> |%| <<", s);

    line_height := get_line_height();
    for row_index: start_row..end_row {
        row := buffer.row_table[row_index];
        row_start := row.end-row.size;
        row_end   := row.end;

        left  := -editor.left_offset;
        width := 0.0;

        t := slice(buffer, row_start, row.size);

        // Convert the first N unselected bytes in the row to pixels
        start := max(sel_start, row_start) - row_start;
        t1 := slice(t, 0, start);
        if t1.count then left += Simp.prepare_text(my_font, t1);

        // Convert the remained bytes in the row to pixels
        t2 := advance(t, start);
        t2.count -= row_end - min(sel_end, row_end);
        if t2.count then width += Simp.prepare_text(my_font, t2);
                    else width += my_font.em_width;

        bottom := (r.h+r.y) - (line_height*(row_index+1)) + editor.top_offset;
        Simp.immediate_quad(left, bottom + (ch-ch*0.1), left+width, bottom - (ch/2-(ch*0.2)), SELECTION_COLOR); 
    }
}

draw_widgets :: () {
    proc := default_theme_procs[current_theme];
    my_theme = proc();
    set_default_theme(my_theme);  // Just in case we don't explicitly pass themes sometimes...!

    update_search_widget();
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

DEBUG_CROSSHAIR_COLOR :: Vector4.{5.0/255.0, 6.0/255.0, 10.0/255.0, 1.0};
PURPLE_COLOR :: Vector4.{.5, .3, .8, 1.0};
FOOTER_COLOR :: Vector4.{209.0/255.0, 181.0/255.0, 142.0/255.0, 1.0};
