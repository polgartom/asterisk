draw_frame :: (text: string, second_elapsed: bool, current_time: float64) {
    active_editor := get_active_editor();

    proc := default_theme_procs[current_theme];
    my_theme = proc();
    set_default_theme(my_theme);  // Just in case we don't explicitly pass themes sometimes...!
    x, y, width, height := get_dimensions(my_window, true);
    ui_per_frame_update(my_window, width, height, current_time);

    r := get_rect(0.0, 0.0, xx width, xx height);
    r=, footer := cut_top(r, window_height-footer_height);

    {
        using active_editor;

        rel_x := get_cursor_rel_x(*editor);
        if rel_x - window_width >= 0 {
            left_offset += rel_x - window_width;
        } else if rel_x - my_font.em_width < 0 {
            left_offset -= (rel_x * -1) + my_font.em_width;
        }

        rel_y := get_cursor_rel_y(*editor);
        if xx rel_y < r.y {
            top_offset += abs(r.y-rel_y);
        } else if rel_y + my_font.character_height > xx window_height {
            top_offset -= rel_y + my_font.character_height - window_height;
        }
    }

    // Draw cursor
    if editor_in_focus {
        using active_editor;

        row := get_cursor_row(*editor);
        cx  := get_cursor_x(*editor);

        Simp.set_shader_for_color();

        // top  := window_height - ((my_font.default_line_spacing+line_height) * row) + top_offset;
        top  := (r.h+r.y) - ((my_font.default_line_spacing+line_height) * row) + top_offset;

        left := cx - left_offset;
        h := my_font.character_height;

        // @Improve: This isn't accurate
        Simp.immediate_quad(left, top + (h-h*0.1), left + my_font.em_width, top - (h/2-(h*0.2)), CURSOR_COLOR); 
    }

    // Draw lines
    if text.count {
        using active_editor;
        using active_editor.active_buffer;

        avg_row_render_time: float64 = 0.0;
        rendered_rows := 0;

        line_height := get_line_height();

        start_row: s64 = xx (top_offset / line_height); 
        start_row = clamp(start_row - 1, 0, row_table.count-1);

        // end_row: s64 = xx ((top_offset + (r.h)) / line_height);
        // end_row = clamp(end_row + 1, end_row, row_table.count-1);
        end_row := last_visible_row_index(editor.active_buffer);

        for row_index: start_row..end_row {
            row := row_table[row_index];
            if row.cols == 0 continue;

            time := seconds_since_init()*1000;

            // bottom := window_height - (line_height*(row_index+1)) + top_offset;
            bottom := (r.h+r.y) - (line_height*(row_index+1)) + top_offset;

            left := -left_offset;
            t := slice(text, row.pos-row.cols, row.cols);
            left += draw_text(t, xx left, xx bottom, text_color);

            if draw_special_chars {
                s := tprint("¶");
                draw_text(s, xx left, xx bottom, .{1.0, 1.0, 1.0, .4});
            }

            avg_row_render_time += (seconds_since_init()*1000 - time);
            rendered_rows += 1;
        }

        avg_row_render_time = ifx rendered_rows > 0 then avg_row_render_time/rendered_rows else 0.0;
        PrintDev("rendered rows/total: %/% ; avg/row: %ms\n", rendered_rows, row_table.count, formatFloat(avg_row_render_time, trailing_width=3));
    }

    // Draw footer
    {
        Simp.set_shader_for_color();
        Simp.immediate_quad(footer.x, footer.y, footer.w, footer.h, FOOTER_COLOR);
        // Simp.immediate_quad(footer.x, footer.h, footer.w, footer.h-2, .{149.0/255.0, 121.0/255.0, 82.0/255.0, 1.0});

        center := footer.y+footer.h/2-my_font.character_height/2;
        // Simp.immediate_quad(footer.x, footer.h/2, footer.w, footer.h/2-2, .{149.0/255.0, 121.0/255.0, 82.0/255.0, 1.0}); // center debug

        opened_file := editor.active_buffer.filepath;
        if !opened_file then opened_file = tprint("<new file>");

        w := Simp.prepare_text(my_font, opened_file);
        Simp.draw_prepared_text(my_font, 10, xx center, .{.0,.0,.0,1.0});

        ln := get_cursor_row(*editor)-1;
        col := get_cursor_col(*editor);
        lncolinfo := tprint("Ln % Col %", ln, col);
        w = Simp.prepare_text(my_font, lncolinfo);
        Simp.draw_prepared_text(my_font, xx (window_width-w*1.25), xx center, .{.0,.0,.0,1.0});
    }

    // Widgets
    // if !editor_in_focus {
    //     {
    //         k := window_height * .1;
    //         width := window_width * .15;
    //         height := my_font.character_height*2.0;
    //         top_pad := 0.2*k;
    //         text_theme := my_theme.text_input_theme;
    //         text_theme.font = my_font;
    //         r := get_rect((window_width/2.0)-width, window_height-height-top_pad, width+width, my_font.character_height*2.0);
    //         action, _, state := text_input(r, search_text, *text_theme, input_action=.ACTIVATE);
    //         if action & .ENTERED {
    //             add_editor_event(FindNextOccurence);
    //         } else if action & .TEXT_MODIFIED {
    //             last_occurance_offset = -1;
    //             modify_string(*search_text, state.text);
    //             add_editor_event(FindNextOccurence);
    //         // } else if action & .ESCAPED {
    //         //     // @TODO!
    //         //     set_last_inert_text(state, "");
    //         }
    //     }
    // }

    // Draw debug info
    if show_debug_info {
        // {
        //     // Draw crosshair
        //     Simp.set_shader_for_color();
        //     Simp.immediate_quad(window_width/2.0-1.0, 0.0, window_width/2.0, xx window_height, DEBUG_CROSSHAIR_COLOR); 
        //     Simp.immediate_quad(0.0, window_height/2.0-1.0, xx window_width, window_height/2.0, DEBUG_CROSSHAIR_COLOR); 
        // }

        {
            ct := seconds_since_init();
            if second_elapsed {
                frametime = (ct - last_time); // frametime
                fps       = 1/frametime;
            }

            PrintDev("%fps %ms %sec\n", 
                formatFloat(fps, trailing_width=0), 
                formatFloat(frametime*1000, trailing_width=2), 
                formatFloat(last_time, trailing_width=0)
            );
        }

        row := 1;
        max := 0;
        for debug_infos if it.count > max then max = it.count;
        for debug_infos {
            s := it;
            ln := s[s.count-1] == #char "\n";
            if ln then s.count -= 1;

            // roffset := max - it.count;
            rmargin := 10;

            w := Simp.prepare_text(my_font, s);
            top := ((my_font.default_line_spacing+line_height) * row);
            Simp.draw_prepared_text(my_font, xx (window_width - w - rmargin), xx (window_height-top), .{.8, .8, .8, 1});

            if ln then row += 1;

            free(it.data);
        }

        array_reset(*debug_infos);
    }

}

draw_text :: inline (s: string, left: s64, bottom: s64, color: Vector4) -> s64 {
    w := Simp.prepare_text(my_font, s);
    Simp.draw_prepared_text(my_font, left, bottom, color);
    return w;
}

DEBUG_CROSSHAIR_COLOR :: Vector4.{5.0/255.0, 6.0/255.0, 10.0/255.0, 1.0};
PURPLE_COLOR :: Vector4.{.5, .3, .8, 1.0};
FOOTER_COLOR :: Vector4.{209.0/255.0, 181.0/255.0, 142.0/255.0, 1.0};