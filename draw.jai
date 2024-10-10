draw_frame :: (text: string, second_elapsed: bool) {
    // Draw cursor
    {
        row := get_cursor_row(text);
        cx  := get_cursor_x(text);

        Simp.set_shader_for_color();

        top  := window_height - ((my_font.default_line_spacing+line_height) * row) + top_offset;
        left := cx - left_offset;
        h := my_font.character_height;

        Simp.immediate_quad(left, top + (h-h*0.1), left + my_font.em_width, top - (h/2-(h*0.2)), cursor_color);

        // ch := get_char_at_string_index(text, cursor_pos);
        // PrintDev("cursor | i: % % ; x1: % y1: % x2: % y2: %\n", cursor_pos, ch, left, top + (h-h*0.1), left + my_font.em_width, top - (h/2-(h*0.2)));
    }

    // Draw lines
    if text.count {
        avg_row_render_time: float64 = 0.0;
        rendered_rows := 0;

        line_height := get_line_height();

        start_row: s64 = xx (top_offset / line_height); 
        start_row = clamp(start_row - 1, 0, row_table.count-1);

        end_row: s64 = xx ((top_offset + window_height) / line_height);
        end_row = clamp(end_row + 1, end_row, row_table.count-1);

        for row_index: start_row..end_row {
            row := row_table[row_index];
            if row.cols == 0 continue;

            time := seconds_since_init()*1000;

            bottom := window_height - (line_height*(row_index+1)) + top_offset;
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

    // Draw debug info
    if show_debug_info {

        {
            ct := seconds_since_init();
            if second_elapsed {
                frametime = (ct - last_time) * 1000; // frametime
                fps       = 1000/frametime;
            }

            PrintDev("%fps %ms %sec\n", 
                formatFloat(fps, trailing_width=0), 
                formatFloat(frametime, trailing_width=2), 
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