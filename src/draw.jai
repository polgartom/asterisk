draw_frame :: (current_time: float64) {
    Simp.set_shader_for_color(true);

    x, y, width, height := get_dimensions(my_window, true);
    ui_per_frame_update(my_window, width, height, current_time);

    rect := get_rect(0.0, 0.0, xx width, xx height);

    if editors[0].visible && editors[1].visible {
        left, right := cut_left(rect, floor(rect.w/2));

        draw_editor(*editors[0], left);
        draw_editor(*editors[1], right);

        Simp.set_shader_for_color(true);
        c := map_color_to_vec4(.LAYOUT_SEPARATOR);
        Simp.immediate_quad(right.x - 1.0, right.y, right.x + 1.0, right.h + right.y, c);
    } else {
        draw_editor(*editors[0], rect);
    }

    // if editor_in_focus {
    //     draw_debug_mouse_character_selection();
    // }

    // Widgets
    if mode == .WIDGET {
        draw_widgets();
    }

    if show_debug_info {
        draw_global_debug_info(active_editor.rect_for_draw);
    }

    // @Todo: Draw this by pressing a hotkey designated for this. We could use Ctrl + F1-F12 or something.
    // {
    //     // Draw current editor's history

    //     edi, buf := get_active_editor_and_buffer();
    //     r := get_rect(window_width/2.0 , window_height-10.0, window_width/2.1, 200.0);

    //     options: [..] List_Input.Option;
    //     options.allocator = temp;
    //     array_reserve(*options, buf.history.count);
    //     for h, i: buf.history {
    //         o := array_add(*options);
    //         o.label = tprint("% % % %", i, h.type, h.text, ifx buf.history_index==i then " <<" else "");
    //     }

    //     list_input(r, xx #location(), primary_font_xs, options);
    // }

}

draw_editor :: (using editor: *Editor, rect: Rect) {
    left_pad := cast(float32) primary_font.em_width;

    r, footer_r := cut_top(rect, window_height-footer_height);
    _, r=       := cut_left(r, left_pad);

    defer editor.rect_for_draw = r;

    // Simp.immediate_quad(pad_r.x, pad_r.y, pad_r.x + pad_r.w, pad_r.h + pad_r.y, PURPLE_COLOR);

    buffer := editor.active_buffer;

    // if should_recalc_editor_offsets {
        // should_recalc_editor_offsets = false;
    {
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
    // }

    draw_selection(editor, buffer, r);

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

        color := map_color_to_vec4(.TEXT_DEFAULT);
        if active_editor != editor {
            color = map_color_to_vec4(.TEXT_DIMMED);
        }

        for row_index: start_row..end_row {
            row := row_table[row_index];
            if row.size == 0 continue;

            // time := seconds_since_init() * 1000;

            bottom := (r.h + r.y) - (line_height*(row_index+1)) + top_offset;

            left := r.x;
            line_text := slice(buffer, row.end - row.size, row.size);
            Font.prepare_text(primary_font, line_text, start_x = xx left_offset, max_width = cast(s64)(r.w-left_pad));
            Font.draw_prepared_text(primary_font, xx left, xx bottom, color);

            // avg_row_render_time += (seconds_since_init() * 1000 - time);
            // rendered_rows += 1;
        }

        // avg_row_render_time = ifx rendered_rows > 0 then avg_row_render_time/rendered_rows else 0.0;
        // PrintDev("draw_rows: %/% %ms avg/row\n", rendered_rows, row_table.count, formatFloat(avg_row_render_time, trailing_width=3));
    }

    draw_cursor(editor, buffer, r);

    {
        // Draw footer

        push_scissor(footer_r);
        defer pop_scissor();

        footer := footer_r;
        Simp.set_shader_for_color(true);

        font := primary_font_xs;

        bg_color := map_color_to_vec4(.FOOTER_BACKGROUND);
        if active_editor != editor {
            bg_color = map_color_to_vec4(.FOOTER_BACKGROUND_DARKEN);
        }

        // Footer shape
        Simp.immediate_quad(footer.x, footer.y, footer.x + footer.w, footer.h, bg_color);

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

        row := find_row_index(buffer, buffer._cursor.pos) + 1;
        col := byte_pos_to_col_pos(buffer, buffer._cursor.pos) + 1;
        total_row_percent := ceil((row / cast(float32)buffer.row_table.count) * 100.0);

        row_col_info := tprint("%\% Ln % Col %", total_row_percent, row, col);
        if show_debug_info {
            row_col_info = tprint("% Pos %", row_col_info, buffer._cursor.pos);
        }

        RIGHT_PAD :: 1.1;
        width = Simp.prepare_text(font, row_col_info);
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

    bg_color := map_color_to_vec4(.CURSOR);
    fg_color := map_color_to_vec4(.TEXT_UNDER_CURSOR);

    if active_editor != editor {
        bg_color = map_color_to_vec4(.CURSOR_INACTIVE);
        fg_color = map_color_to_vec4(.TEXT_UNDER_INACTIVE_CURSOR);
    }

    // @Todo: Current line indicator frame shape
    // #if CURRENT_LINE_INDICATOR_STYLE == .FRAME {
    //     p1 := bottom + (ch-ch*0.1);
    //     p2 := bottom - (ch/2-(ch*0.2)) - 1.0;

    //     Simp.immediate_quad(r.x, p1, r.x + r.w, p1 + CURRENT_LINE_INDICATOR_FRAME_WIDTH, CURRENT_LINE_INDICATOR_COLOR); // top
    //     Simp.immediate_quad(r.x, p2, r.x + r.w, p2 + CURRENT_LINE_INDICATOR_FRAME_WIDTH, CURRENT_LINE_INDICATOR_COLOR); // bottom
    // }

    {
        // Current line indicator shape
        p1 := bottom + (ch-ch*0.1);
        p2 := bottom - (ch/2-(ch*0.2)) - 1.0;

        color := map_color_to_vec4(.CURSOR_LINE_BACKGROUND);
        Simp.immediate_quad(r.x, p1, r.x + r.w, p2, color);
    }

    // Cursor shape
    Simp.immediate_quad(cast(float32)cx, bottom + (ch-ch*0.1), cast(float32)(cx + cw), bottom - (ch/2-(ch*0.2)), bg_color);

    // Change character's color under the cursor
    if buffer.count {
        character := get_character_as_string_at(buffer, xx c.pos);
        Font.prepare_text(primary_font, character);
        Font.draw_prepared_text(primary_font, xx cx, xx bottom, fg_color);
    }
}

// @Todo: This thing is not doing draws properly. Also we should create an array of selections, because
// we should draw those after the find text widget.
draw_selection :: (editor: *Editor, buffer: *Buffer, r: Rect) {
    c := *buffer._cursor;
    if !has_selection(c) return;

    Simp.set_shader_for_color(true);
    selection_color := map_color_to_vec4(.TEXT_SELECTION);

    left_pad := cast(float32) primary_font.em_width;

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
        // @Hacky We should add +.001 as a crude fix for some rounding issues because there is a very subtle gap if editor.top_offset is 0.0.
        Simp.immediate_quad(left, bottom + (ch-ch*0.1)+.001, left+width, bottom - (ch*.5-(ch*0.2)), selection_color);
    }

}

draw_widgets :: () {
    proc := default_theme_procs[current_theme];
    my_theme = proc();
    set_default_theme(my_theme);

    if active_widget == {
        case Find_Text_Dialog; draw_find_text_dialog();
        case File_Browser;     draw_file_browser();
        case Buffer_Browser;   draw_buffer_browser();
    }
}

draw_buffer_browser :: () {
    font := my_font_small;
    pad  := cast(float32) primary_font.em_width * .5;
    ed_r := active_editor.rect_for_draw;
    
    // @Temporary: We don't want to set those values on every frame, right?
    theme := Text_Input.DEFAULT_THEME;
    theme.bg_color = #run hex_to_vec4(0x502129ff);// #run hex_to_vec4(0x1c2d29ff);
    theme.fg_color = #run hex_to_vec4(0xff_ff_ff_c5);
    theme.placeholder_color = #run hex_to_vec4(0xff_ff_ff_8a);
    theme.cursor_color = #run hex_to_vec4(0xff_ff_ff_c5);

    h := cast(float)font.character_height * 2.0;
    b := cast(float, window_height);
    r := get_rect(ed_r.x-pad, b-h, ed_r.w, h);
    tinp := text_input(r, xx #location(), font, placeholder="Switch to buffer", theme=theme);

    options: [..] List_Input.Option(Buffer);
    options.allocator = temp;
    array_reserve(*options, buffers.count);

    // @Speed: We are doing this on every frame!!!
    wd := get_working_directory();
    path_unify_sepa(wd);

    for *b: buffers {
        if !b.initialized continue;

        title := "* New *";
        if b.exists_on_disk {
            title = b.filepath;
            // if begins_with(title, wd) {
            //     skip := wd.count;
            //     if title[wd.count] == #char "/" skip += 1; 
            //     advance(*title, skip);
            // }
        }

        if tinp.text {
            found, rem := contains_nocase(title, tinp.text);
            if !found continue;
        }

        array_add(*options, .{label=copy_temporary_string(title), ref=b});
    }

    list_rect := r;
    k := ed_r.h * .1;
    list_rect.h = 1.5*k;
    linp := list_input(list_rect, xx #location(), font, options);
    
    if linp.selected_index == -1 then linp.selected_index = 0;

    if linp.entered && options.count {
        if linp.selected_index >= options.count || linp.selected_index < 0 {
            assert(false, "Invalid index: % ; options: % ; buffers: %\n", linp.selected_index, options, buffers);
            return;                
        }
        
        selected_option := options[linp.selected_index];
        buffer := selected_option.ref;
        change_active_buffer(active_editor, buffer);

        linp.selected_index = -1;

        array_add(*user_events, .{ type = .CLOSE_WIDGET });
    }

}

draw_file_browser :: () {
    font := my_font_small;
    pad  := cast(float32) primary_font.em_width * .5;
    ed_r := active_editor.rect_for_draw;
    
    // @Temporary: We don't want to set those values on every frame, right?
    theme := Text_Input.DEFAULT_THEME;
    theme.bg_color = #run hex_to_vec4(0x502129ff);// #run hex_to_vec4(0x1c2d29ff);
    theme.fg_color = #run hex_to_vec4(0xff_ff_ff_c5);
    theme.placeholder_color = #run hex_to_vec4(0xff_ff_ff_8a);
    theme.cursor_color = #run hex_to_vec4(0xff_ff_ff_c5);

    h := cast(float)font.character_height * 2.0;
    b := cast(float, window_height);
    r := get_rect(ed_r.x-pad, b-h, ed_r.w, h);
    tinp := text_input(r, xx #location(), font, placeholder=file_browser.current_dir, theme=theme);

    {
        using file_browser;

        options: [..] List_Input.Option(void);
        options.allocator = temp;
        array_reserve(*options, items.count);

        // @Speed: We are doing this on every frame!!!
        for items {
            if tinp.text {
                found, rem := contains_nocase(it.short_name, tinp.text);
                if !found continue;
            }
            array_add(*options, .{label=copy_temporary_string(it.short_name)});
        }

        list_rect := r;
        k := ed_r.h * .1;
        list_rect.h = 1.5*k;
        linp := list_input(list_rect, xx #location(), font, options);
        
        if linp.selected_index == -1 then linp.selected_index = 0;

        if linp.entered && options.count {
            if linp.selected_index >= options.count || linp.selected_index < 0 {
                assert(false, "Invalid index: % ; options: % ; items: %\n", linp.selected_index, options, items);
                return;                
            }
            selected_option := options[linp.selected_index];

            index := -1;        
            for items {
                if it.short_name == selected_option.label {
                    index = it_index;
                    break;
                }
            }
            assert(index != -1);

            item := items[index];
            if item.is_directory {
                ok := file_browser_change_dir(item);
                assert(ok);
                file_browser_scan();

                clear_text(tinp);

                linp.scroll_value = 0.0;
                linp.selected_index = 0;
            } else {
                clear_text(tinp);
                linp.scroll_value = 0.0;
                linp.selected_index = 0;

                index := find_buffer_index_by_filepath(item.full_name);
                if index != -1 {
                    buffer := *buffers[index];
                    change_active_buffer(active_editor, buffer); 
                } else {
                    open_file_or_create_empty_buffer(active_editor, item.full_name);
                }

                array_add(*user_events, .{ type = .CLOSE_WIDGET });
            }

        }

        if tinp.typed && items.count {
            linp.selected_index = 0;
        }
    }

}

draw_find_text_dialog :: () {
    using find_text_dialog;

    ed_r := active_editor.rect_for_draw;

    {
        font   := my_font_small;
        k      := ed_r.h * .1;
        height := em(2.0, font);
        pad    := cast(float32, primary_font.em_width);// * .5;

        r := get_rect(
            ed_r.x - pad,
            footer_height,
            ed_r.w,
            xx font.character_height * 2.0,
        );

        // @Temporary: We don't want to set those values on every frame, right?
        theme := Text_Input.DEFAULT_THEME;
        theme.bg_color = #run hex_to_vec4(0x502129ff);// #run hex_to_vec4(0x1c2d29ff);
        theme.fg_color = #run hex_to_vec4(0xff_ff_ff_c5);
        theme.placeholder_color = #run hex_to_vec4(0xff_ff_ff_8a);
        theme.cursor_color = #run hex_to_vec4(0xff_ff_ff_c5);

        update_text_input(input, r, font, placeholder="Find...", theme);
    }

    update_find_text_dialog();

    if !input.text return;

    r := ed_r;
    
    push_scissor(r);
    defer pop_scissor();

    editor, buffer := get_active_editor_and_buffer();
    rs_i := first_visible_row_index(editor, buffer);
    re_i := last_visible_row_index(editor, buffer);

    line_height := get_line_height();
    ch := primary_font.character_height;
    color := map_color_to_vec4(.TEXT_HIGHLIGHT);

    for pos: occurences {
        ri := find_row_index(buffer, pos);
        if ri < rs_i || ri > re_i continue;
    
        row := buffer.row_table[ri];

        left := r.x - editor.left_offset;
        rem_left  := slice(buffer, row.start, pos - row.start);
        if rem_left then left += cast(float32) measure_text_width(primary_font, rem_left);

        text := slice(buffer, row.start, row.end);
        text  = advance(text, rem_left.count);
        text  = slice(text, 0, input.text.count);
        width := measure_text_width(primary_font, text);

        bottom := (r.h + r.y) - (line_height*(ri+1)) + editor.top_offset;

        Simp.immediate_quad(left, bottom + (ch-ch*0.1)+.001, left + width, bottom - (ch*.5-(ch*0.2)), color);
    }

}

draw_global_debug_info :: (r: Rect) {
    // Simp.immediate_flush();

    // FPS
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
        Simp.draw_prepared_text(my_font, xx (r.x + r.w - w - rmargin), xx (bottom), .{.8, .8, .8, 1});

        if ln then row += 1;
    }

    array_reset(*debug_infos);
}

/////////////////////

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
    color := map_color_to_vec4(.TEXT_DEFAULT);

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

// DEBUG_CROSSHAIR_COLOR :: Vector4.{5.0/255.0, 6.0/255.0, 10.0/255.0, 1.0};
// PURPLE_COLOR :: Vector4.{.5, .3, .8, 1.0};
// FOOTER_COLOR :: Vector4.{209.0/255.0, 181.0/255.0, 142.0/255.0, 1.0};

#scope_file

Font :: #import, file "font.jai";