draw_frame :: () {
    c := map_color_to_vec4(.BACKGROUND);
    Simp.clear_render_target(c.x, c.y, c.z, c.w);

    Simp.set_shader_for_color(true);

    x, y, width, height := get_dimensions(window, true);

    rect := make_rect(0.0, 0.0, xx width, xx height);

    LEFT_PADDING :: 5;
    _, rect = cut_left(rect, LEFT_PADDING);

    // @Todo: Fix the footer visual
    if editors[0].visible && editors[1].visible {
        left, right := cut_left(rect, floor(rect.w/2));
        sepa_rect := right;
        _, right = cut_left(right, LEFT_PADDING);

        draw_editor(*editors[0], left);
        draw_editor(*editors[1], right);

        Simp.set_shader_for_color(true);
        c := map_color_to_vec4(.LAYOUT_SEPARATOR);
        Simp.immediate_quad(sepa_rect.x - 1.0, sepa_rect.y, sepa_rect.x + 1.0, sepa_rect.h + sepa_rect.y, c);
        
    } else {
        draw_editor(*editors[0], rect);
    }

    //draw_debug_mouse_character_selection(active_editor, rect);
    
    // Widgets
    if mode == .WIDGET {
        draw_widgets();
    }

    if show_debug_info {
        // b := active_editor.active_buffer;
        // for b.history {
        //     PrintDev("% t: % ; range: % ; text: % ; old_text: %\n", ifx it_index == b.history_index then ">" else "", it.type, it.range, it.text, it.old_text);
        // }

        draw_global_debug_info(active_editor.rect_for_draw);
    }

    swap_buffers();
}

swap_buffers :: () {
    Simp.CheckInit();
    if state.current_shader Simp.immediate_flush();

    #if OS == .WINDOWS {
        // @Todo: Explain

        // Fix the Simp.swap_buffers() GetDC() leak
        Win :: #import "Windows";
        dc := Win.wglGetCurrentDC();
        Win.SwapBuffers(dc);
    } else {
        Simp.swap_buffers(window);
    }
}

draw_editor :: (using editor: *Editor, rect: Rect) {
    if !is_active(editor) context.color_intensity *= 0.90;
    defer reset_color_intensity();
    
    r, footer_r := cut_top(rect, window_height-footer_height);

    editor.rect_for_draw = r;

    buffer := editor.active_buffer;

    if editor.y_scroll_anim.active {
        using editor.y_scroll_anim;

        t := (current_time - started_at) / duration;
        t = clamp(t, 0.0, 1.0);
        distance := (target - start);
        // v := start + cast(float)(distance * t * t * (3.0 - 2.0 * t)); // smoothstep
        v := start + cast(float)(distance * t);                          // lerp

        if t == 1.0 then active = false;

        editor.top_offset = v;

        redraw_requested = true;
    }

    if editor.x_scroll_anim.active {
        using editor.x_scroll_anim;

        t := (current_time - started_at) / duration;
        t = clamp(t, 0.0, 1.0);
        distance := (target - start);
        v := start + cast(float)(distance * t);

        if t == 1.0 then active = false;

        editor.left_offset = v;

        redraw_requested = true;
    }

    if editor.cursor.moved {
        editor.cursor.moved = false;

        scroll_to_cursor(editor, editor.cursor, animation_duration=0.08);
    }

    draw_selection(editor, buffer, r);

    // Draw text
    if buffer.count {
        using editor;
        using buffer;

        avg_row_render_time: float64 = 0.0;
        rendered_rows := 0;

        line_height := fnt_get_line_height();

        start_row: s64 = xx (top_offset / line_height);
        start_row = clamp(start_row - 1, 0, row_table.count-1);

        end_row := last_visible_row_index(editor, buffer);

        color := map_color_to_vec4(.TEXT_DEFAULT);

        left_pad := cast(float32) r_font.em_width;

        push_scissor(r);
        defer pop_scissor();

        // Draw lines
        for row_index: start_row..end_row {
            row := row_table[row_index];
            if row.size == 0 continue;

            bottom := (r.h + r.y) - (line_height*(row_index+1)) + top_offset;
            
            left := r.x;
            line_text := slice(buffer, row.end - row.size, row.size);
            draw_code(buffer, xx (left-left_offset), xx bottom, line_text);
        }
        
    }

    draw_cursor(editor, buffer, r, cursor_shape, cursor_line_indicator);

    {
        // Draw footer

        push_scissor(footer_r);
        defer pop_scissor();

        footer := footer_r;
        Simp.set_shader_for_color(true);

        font := r_font_sm;

        fg_color := map_color_to_vec4(.FOOTER_TEXT);
        bg_color := map_color_to_vec4(.FOOTER_BACKGROUND);
        if active_editor != editor {
            bg_color = map_color_to_vec4(.FOOTER_BACKGROUND_DARKEN);
        }

        // Footer shape
        Simp.immediate_quad(footer.x, footer.y, footer.x + footer.w, footer.h, bg_color);

        width := 0;
        left := footer.x + 10;
        center := font_calc_y_center_insert_point(footer, font.character_height);

        {
            // Draw buffer's file info
            using buffer;

            info_text: string = ---;

            if readonly { // scratch buffer
                info_text = name;

            } else {
                path := filepath;
                if !path path = "Untitled";
                if filepath {
                    path = filepath;
                    workdir := get_workdir();
                    if begins_with(path, workdir) {
                        advance(*path, workdir.count + 1); // +1 for the path separator
                        assert(path.count > 0);
                    }
                }

                info_text = tprint(
                    "%1%2%3",
                    path,
                    ifx !exists_on_disk then " <new>" else "",
                    ifx unsaved         then "*"      else "",
                );
            }

            width = Simp.prepare_text(font, info_text);
            Simp.draw_prepared_text(font, xx left, xx center, fg_color);

            left += width;
        }

        assert(editor.cursor.pos <= buffer.count, "buffer: % ; cursor: %\n", buffer.*, editor.cursor);

        row := find_row_index(buffer, editor.cursor.pos) + 1;
        col := byte_pos_to_row_col_index(buffer, editor.cursor.pos) + 1;
        total_row_percent := ceil((row / cast(float32)buffer.row_table.count) * 100.0);

        row_col_info := tprint("%\% Ln % Col %", total_row_percent, row, col);
        if show_debug_info {
            row_col_info = tprint("% Pos %", row_col_info, editor.cursor.pos);
        }

        RIGHT_PAD :: 1.1;
        width = Simp.prepare_text(font, row_col_info);
        Simp.draw_prepared_text(font, xx (footer.x + footer.w - width * RIGHT_PAD), xx center, fg_color);
    }

}

draw_cursor :: (editor: *Editor, buffer: *Buffer, r: Rect, shape := Cursor_Shape.BLOCK, line_indicator := Cursor_Line_Indicator.FILLED) {
    push_scissor(r);
    defer pop_scissor();

    Simp.set_shader_for_color(true);

    c  := *editor.cursor;

    row_index := find_row_index(buffer, c.pos);
    row := buffer.row_table[row_index];
    line_text := get_row_as_string(buffer, row);
    line_text  = slice(line_text, 0, c.pos - row.start);

    cx := r.x + measure_text_width(r_font, line_text) - editor.left_offset;
    cw := em(1.0, r_font);
    ch := r_font.character_height;

    bottom := (r.h + r.y) - fnt_get_line_height(row_index + 1) + editor.top_offset;

    bg_color := map_color_to_vec4(.CURSOR);
    fg_color := map_color_to_vec4(.TEXT_UNDER_CURSOR);

    if active_editor != editor {
        bg_color = map_color_to_vec4(.CURSOR_INACTIVE);
        fg_color = map_color_to_vec4(.TEXT_UNDER_INACTIVE_CURSOR);
    }

    if buffer.readonly {
        shape = .LINE;
        line_indicator = .NONE;
    }

    if #complete line_indicator == {
        case .NONE;
        case .FILLED;
            // Current line indicator shape
            p1 := bottom + (ch-ch*0.1);
            p2 := bottom - (ch/2-(ch*0.2)) - 1.0;

            color := map_color_to_vec4(.CURSOR_LINE_BACKGROUND);
            Simp.immediate_quad(r.x, p1, r.x + r.w, p2, color);
        case .BORDERED;
            p1 := bottom + (ch-ch*0.1);
            p2 := bottom - (ch/2-(ch*0.2)) - 1.0;

            THICKNESS :: 2; // @Todo: Add to config
            border_color := #run hex_to_vec4(0xcccccc_1a); // map_color_to_vec4(.CURSOR_LINE_BACKGROUND); // @Todo: Add to config

            Simp.immediate_quad(r.x, p1, r.x + r.w, p1 + THICKNESS, border_color); // top
            Simp.immediate_quad(r.x, p2, r.x + r.w, p2 + THICKNESS, border_color); // bottom
    }

    if #complete shape == {
        case .BLOCK;
            Simp.immediate_quad(cast(float32)cx, bottom + (ch-ch*0.1), cast(float32)(cx + cw), bottom - (ch/2-(ch*0.2)), bg_color);
            // Change character's color under the cursor
            if buffer.count {
                character := get_character_as_string_at(buffer, xx c.pos);
                Simp.prepare_text(r_font, character);
                Simp.draw_prepared_text(r_font, xx cx, xx bottom, fg_color);
            }
        case .LINE;
            Simp.immediate_quad(cast(float32)cx, bottom + (ch-ch*0.1), cast(float32)(cx + max(cw*.5, 3.0)), bottom - (ch/2-(ch*0.2)), bg_color);

        case .UNDERSCORE;
            Simp.immediate_quad(cast(float32)cx, bottom, cast(float32)(cx + cw), bottom - (ch/2-(ch*0.2)), bg_color);
    }

    Simp.immediate_flush();
}

// @Todo: This thing is not doing draws properly. Also we should create an array of selections, because
// we should draw those after the find text widget.
draw_selection :: (editor: *Editor, buffer: *Buffer, r: Rect) {
    c := *editor.cursor;
    if !has_selection(c) return;

    Simp.set_shader_for_color(true);
    Simp.immediate_begin();

    selection_color := map_color_to_vec4(.TEXT_SELECTION);

    left_pad := cast(float32) r_font.em_width;

    ch := r_font.character_height;
    line_height := fnt_get_line_height();

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
        if t1.count then left += Simp.prepare_text(r_font, t1);

        // Convert the remained bytes in the row to pixels
        t2 := advance(t, start);
        t2.count -= row_end - min(sel_end, row_end);
        if t2.count then width += Simp.prepare_text(r_font, t2);
                    else width += r_font.em_width;

        bottom := (r.h+r.y) - (line_height*(row_index+1)) + editor.top_offset;
        // @Hacky We should add +.001 as a crude fix for some rounding issues because there is a very subtle gap if editor.top_offset is 0.0.
        Simp.immediate_quad(left, bottom + (ch-ch*0.1)+.001, left+width, bottom - (ch*.5-(ch*0.2)), selection_color);
    }

    ///////
    
    show_selection_occurences := false;
    t := s.data;
    while t < s.data + s.count {
        if !is_whitespace(t.*) {
            // We don't want to highlight a bunch of spaces without one unicode character at least
            show_selection_occurences = true;
            break;
        }

        t += 1 + trailingBytesForUTF8[t.*];
    }

    if show_selection_occurences {
        start_row := first_visible_row(editor, buffer);
        end_row := last_visible_row(editor, buffer);

        str := slice(buffer, start_row.start, end_row.end - start_row.start);
        step := 1 + trailingBytesForUTF8[s[s.count-1]];

        while str {
            index, found := find_index_from_left_nocase(str, s);
            if !found || index == -1 break;
            defer advance(*str, index + s.count + step - 1);

            if str.data + index == s.data continue; // Don't highlight again the current selection

            pos := str.data + index - buffer.data;

            ri := find_row_index(buffer, pos);
            row := buffer.row_table[ri];

            left := r.x - editor.left_offset;
            rem_left  := slice(buffer, row.start, pos - row.start);
            if rem_left then left += cast(float32) measure_text_width(r_font, rem_left);

            text := slice(buffer, row.start, row.end);
            text  = advance(text, rem_left.count);
            text  = slice(text, 0, s.count);
            width := measure_text_width(r_font, text);

            bottom := (r.h + r.y) - (line_height*(ri+1)) + editor.top_offset;

            //Simp.set_shader_for_color(true); // do we need this right here?
            Simp.immediate_quad(left, bottom + (ch-ch*0.1)+.001, left + width, bottom - (ch*.5-(ch*0.2)), map_color_to_vec4(.TEXT_SELECTION_MATCH));
        }
    }

    Simp.immediate_flush();
}

draw_widgets :: () {
    if active_widget == {
        case Find_Text_Dialog;         draw_find_text_dialog();
        case Find_Global_Text_Dialog;  draw_find_global_text_dialog();
        case Goto_Line_Dialog;         draw_goto_line_dialog();
        case File_Browser;             draw_file_browser();
        case Buffer_Browser;           draw_buffer_browser();
        case Command_Browser;          draw_command_browser();
    }
}

draw_command_browser :: () {
    font := r_font_sm;
    pad  := cast(float32) font.em_width * .5;
    ed_r := active_editor.rect_for_draw;
    
    theme := Text_Input.DEFAULT_THEME;
    theme.bg_color = #run hex_to_vec4(0x19_19_19_ff);
    theme.fg_color = #run hex_to_vec4(0xff_ff_ff_c5);
    theme.border_color = #run hex_to_vec4(0x30_25_5a_ff);
    theme.placeholder_color = #run hex_to_vec4(0xff_ff_ff_8a);
    theme.cursor_color = #run hex_to_vec4(0xff_ff_ff_c5);

    w := 400.0; // @Tempoary
    k := window_height * .1;

    h := cast(float, font.character_height * 2.0);
    b := cast(float, window_height - k*.1);
    r := make_rect(ed_r.x-pad, b-h, ed_r.w, h);
    r.x = window_width*.5 - w;
    r.w = w * 2.0;
    r.y += 5.0; 

    tinp := command_browser.self_text_input;
    update_text_input(tinp, r, font, placeholder="Switch to buffer", theme=theme);
    r.y -= 5.0; 

    options: [..] List_Input.Option(*Editor_Command);
    options.allocator = temp;
    array_reserve(*options, command_browser.options.count);

    for option: command_browser.options {
        if tinp.text {
            found, rem := contains_nocase(option.label_for_search, tinp.text);
            if !found continue;
        }

        array_add(*options, option);
    }

    list_rect := r;
    list_rect.h = 1.5*k;

    linp_theme := List_Input.DEFAULT_THEME;
    linp_theme.border_color = #run hex_to_vec4(0x30_25_5a_ff);
    linp_theme.current_item_bg_color = #run hex_to_vec4(0x30_25_5a_ff);
    linp := list_input(list_rect, xx #location(), options, font, theme=linp_theme);

    if tinp.typed {
        linp.scroll_value = 0.0;
        linp.selected_index = -1;
    }

    if linp.selected_index == -1 then linp.selected_index = 0;

    if linp.entered && options.count {
        if linp.selected_index >= options.count || linp.selected_index < 0 {
            log_error("Invalid index: % ; options: %\n", linp.selected_index, options);
            linp.selected_index = -1;
            return;                
        }
        
        selected_option := options[linp.selected_index];
        cmd := selected_option.ref;
        if cmd.proc {
            cmd.proc();
        }

        linp.selected_index = -1;

        close_current_widget();
    }

}

draw_buffer_browser :: () {
    font := r_font_sm;
    pad  := cast(float32) font.em_width * .5;
    ed_r := active_editor.rect_for_draw;
    
    theme := Text_Input.DEFAULT_THEME;
    theme.bg_color = #run hex_to_vec4(0x19_19_19_ff);
    theme.fg_color = #run hex_to_vec4(0xff_ff_ff_c5);
    theme.border_color = #run hex_to_vec4(0x30_25_0a_ff);
    theme.placeholder_color = #run hex_to_vec4(0xff_ff_ff_8a);
    theme.cursor_color = #run hex_to_vec4(0xff_ff_ff_c5);

    w := 400.0; // @Tempoary
    k := window_height * .1;

    h := cast(float, font.character_height * 2.0);
    b := cast(float, window_height - k*.1);
    r := make_rect(ed_r.x-pad, b-h, ed_r.w, h);
    r.x = window_width*.5 - w;
    r.w = w * 2.0;
    r.y += 5.0; 

    tinp := buffer_browser.bb_text_input;
    update_text_input(tinp, r, font, placeholder="Switch to buffer", theme=theme);
    r.y -= 5.0; 

    if tinp.typed update_visible_options(*buffer_browser);
    options := buffer_browser.visible_options;

    list_rect := r;
    list_rect.h = 1.5*k;

    linp_theme := List_Input.DEFAULT_THEME;
    linp_theme.border_color = #run hex_to_vec4(0x30_25_0a_ff);
    linp_theme.current_item_bg_color = #run hex_to_vec4(0x30_25_0a_ff);
    linp := list_input(list_rect, xx #location(), options, font, theme=linp_theme);

    if tinp.typed then linp.scroll_value = 0.0;
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

        close_current_widget();
    }

}

draw_file_browser :: () {
    _draw_file_browser();
}

draw_find_global_text_dialog :: () {
    using find_global_text_dialog;

    font := r_font_sm;
    pad  := cast(float32) font.em_width * .5;
    ed_r := active_editor.rect_for_draw;
    
    theme := Text_Input.DEFAULT_THEME;
    theme.bg_color = #run hex_to_vec4(0x19_19_19_ff);
    theme.fg_color = #run hex_to_vec4(0xff_ff_ff_c5);
    theme.border_color = #run hex_to_vec4(0x3a_4a_7a_ff);
    theme.placeholder_color = #run hex_to_vec4(0xff_ff_ff_8a);
    theme.cursor_color = #run hex_to_vec4(0xff_ff_ff_c5);

    //if process {
        //theme.border_color = #run hex_to_vec4(0x2a2a2a_ff);
    //}

    w := window_width * 0.5 - em(2.0, font); // @Tempoary
    k := window_height * .2;

    h := cast(float, font.character_height * 2.0);
    b := cast(float, window_height - k*.1);
    r := make_rect(ed_r.x-pad, b-h, ed_r.w, h);
    r.x = window_width*.5 - w;
    r.w = w * 2.0;
    r.y += 5.0; 

//    label(xx r.x, xx (r.y + r.h + font.character_height*.55), "Loading..", font, theme.fg_color);

    update_find_global_text_dialog();

    if process {
        color := #run hex_to_vec4(0x6a2a2a_ff);
        
        t := .6;
        blend_factor := sin(TAU * (xx current_time) * t);
        blend_factor += 0.0;
        blend_factor *= t;
        Clamp(*blend_factor, 0, 1);
                
        result: Vector4;
        result.x = lerp(cast(float)color.x, 0.0, blend_factor);
        result.y = lerp(cast(float)color.y, 0.0, blend_factor);
        result.z = lerp(cast(float)color.z, 0.0, blend_factor);
        result.w = color.w;
    
        theme.border_color = result;
    }

    tinp := fgt_input;
    update_text_input(tinp, r, font, placeholder="Search...", theme=theme);
    r.y -= 5.0; 

    list_rect := r;
    list_rect.h = 1.5*k;

    linp_theme := List_Input.DEFAULT_THEME;
    linp_theme.border_color = #run hex_to_vec4(0x3a_4a_7a_ff);
    linp_theme.current_item_bg_color = #run hex_to_vec4(0x3a_4a_7a_8a);
    linp := list_input(list_rect, xx #location(), options, font, theme=linp_theme);

    if fgt_input.typed {
        linp.selected_index = 0;
    }

    if linp.entered && options.count {
        if linp.selected_index >= options.count || linp.selected_index < 0 {
            log_error("Invalid index: % ; options: % ; buffers: %\n", linp.selected_index, options, buffers);
            return;             
        }
        
        selected_option := options[linp.selected_index];
        target := selected_option.ref;
        
        buffer := open_file_or_create_empty_buffer(active_editor, target.filepath);
        change_active_buffer(active_editor, buffer);

        if is_valid_line(buffer, target.line_number) {
            row := buffer.row_table[target.line_number-1];
            set_cursor_pos(buffer, *active_editor.cursor, row.start);
        }

        linp.selected_index = -1;

        close_current_widget();
    }

}

draw_find_text_dialog :: () {
    using find_text_dialog;

    ed_r := active_editor.rect_for_draw;

    {
        font := r_font_sm;
        ch := font.character_height;
        k      := ed_r.h * .1;
        kw     := ed_r.w * .15;
        width  := kw * 2.0;
        height := em(2.0, font);
        pad    := cast(float32, r_font.em_width);// * .5;

        r := make_rect(
            ed_r.x + ed_r.w - width - pad,
            ed_r.h - footer_height,
            width,
            xx font.character_height * 2.0,
        );

        // @Temporary: We don't want to set those values on every frame, right?
        theme := Text_Input.DEFAULT_THEME;
        theme.bg_color = #run hex_to_vec4(0x18_20_20_ff); // 0x122922_ff
        theme.border_color = #run hex_to_vec4(0x18_20_20_ff);
        theme.fg_color = #run hex_to_vec4(0xff_ff_ff_a9);
        theme.placeholder_color = #run hex_to_vec4(0xff_ff_ff_8a);
        theme.cursor_color = #run hex_to_vec4(0xff_ff_ff_c5);
        
        theme.border_color = #run hex_to_vec4(0xff_ff_ff_15);
        if occurences {
            theme.border_color = #run hex_to_vec4(0x20_51_22_ff);
        } else if input.text {
            theme.border_color = #run hex_to_vec4(0xa9_22_22_a0);
        }

        update_text_input(input, r, font, placeholder="Find text", theme);

        weight :: 2; // border weight
        r.h = ch*1.5;
        r.y -= r.h + 5 + weight*2;
        r.w *= .30;

        Simp.set_shader_for_color(true);
        Simp.immediate_quad(r.x - weight, r.y - weight, r.x + r.w + weight, r.y+r.h + weight, theme.bg_color);

        hint := tprint("%/%", current_occurrence+1, occurences.count);
        x := r.x + r.w*.5 - measure_text_width(font, hint)*.5;
        label(xx x, xx (r.y+r.h*.5-ch*.3), hint, font, theme.fg_color);
    }

    update_find_text_dialog();

    if !input.text return;

    r := ed_r;
    
    push_scissor(r);
    defer pop_scissor();

    editor, buffer := get_active_editor_and_buffer();
    rs_i := first_visible_row_index(editor, buffer);
    re_i := last_visible_row_index(editor, buffer);

    line_height := fnt_get_line_height();
    ch := r_font.character_height;
    color := map_color_to_vec4(.TEXT_HIGHLIGHT);

    #if 0 {
        // @Todo: Guess if the highlight rects need white or black text  
        // We can make the light text visible if we draw the light rects on the texts,
        // so If our text is white-ish and our rects is brighter yellow then the text
        // color become black. Basically we use the text color to make an inverse mask.
        glBlendFunc(GL_ONE_MINUS_DST_COLOR, GL_ONE);  // if the rect has darker color; the text color became white
        // glBlendFunc(GL_ONE_MINUS_DST_COLOR, GL_ZERO); // if the rect has brighter color; the text color became dark
        glEnable(GL_BLEND);
        defer {
            Simp.immediate_flush();
            glDisable(GL_BLEND);
            // glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);
        }
    } else {
        Simp.set_shader_for_color(true);
    }

    for pos: occurences {
        ri := find_row_index(buffer, pos);
        if ri < rs_i || ri > re_i continue;
    
        row := buffer.row_table[ri];

        left := r.x - editor.left_offset;
        rem_left  := slice(buffer, row.start, pos - row.start);
        if rem_left then left += cast(float32) measure_text_width(r_font, rem_left);

        text := slice(buffer, row.start, row.end);
        text  = advance(text, rem_left.count);
        text  = slice(text, 0, input.text.count);
        width := measure_text_width(r_font, text);

        bottom := (r.h + r.y) - (line_height*(ri+1)) + editor.top_offset;

        Simp.immediate_quad(left, bottom + (ch-ch*0.1)+.001, left + width, bottom - (ch*.5-(ch*0.2)), color);
    }


}

draw_goto_line_dialog :: () {
    using goto_line_dialog;

    assert(active_editor != null && active_editor.active_buffer != null);
    buffer := active_editor.active_buffer;

    ed_r := active_editor.rect_for_draw;

    font   := r_font_sm;
    k      := ed_r.h * .1;
    kw     := ed_r.w * .12;
    width  := kw * 2.0;
    height := em(2.0, font);
    pad    := cast(float32, r_font.em_width);// * .5;

    r := make_rect(
        ed_r.x + ed_r.w - width - pad,
        ed_r.h - footer_height,
        width,
        xx font.character_height * 2.0,
    );

    // @Temporary: We don't want to set those values on every frame, right?
    theme := Text_Input.DEFAULT_THEME;
    theme.bg_color = #run hex_to_vec4(0x18_20_20_ff); // 0x122922_ff
    theme.border_color = #run hex_to_vec4(0x18_20_20_ff);
    theme.fg_color = #run hex_to_vec4(0xff_ff_ff_a9);
    theme.placeholder_color = #run hex_to_vec4(0xff_ff_ff_8a);
    theme.cursor_color = #run hex_to_vec4(0xff_ff_ff_c5);
    
    theme.border_color = #run hex_to_vec4(0xff_ff_ff_15);
    
    line, ok := get_goto_line_dialog_value();
    if ok && is_valid_line(buffer, line) {
        theme.border_color = #run hex_to_vec4(0x5a_9e_22_6a);
    }

    update_text_input(input, r, font, placeholder="Go to line", theme);

    update_goto_line_dialog();

    if !input.text return;
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

    PrintDev("%fps %ms %sec | dt: % sim: %ms draw: %ms\n", 
        formatFloat(fps, trailing_width=0),
        formatFloat(frametime*1000, trailing_width=2, zero_removal=FormatFloat.Zero_Removal.NO),
        formatFloat(last_time, trailing_width=2, zero_removal=FormatFloat.Zero_Removal.NO),
        frame_dt, 
        last_showed_sim_time,
        last_rendering_time,
    );

    row := 1;
    max := 0;
    line_height := fnt_get_line_height();
    bottom: float32 = footer_height + line_height;

    for #v2 < debug_infos {
        s := it;
        ln := s[s.count-1] == #char "\n";
        if ln then s.count -= 1;

        rmargin := 10;

        w := Simp.prepare_text(r_font, s);
        bottom += line_height;
        Simp.draw_prepared_text(r_font, xx (r.x + r.w - w - rmargin), xx (bottom), .{.8, .8, .8, 1});

        if ln then row += 1;
    }
}

////////////////////////////////
//~ 

Text_Style :: struct {
    text: string;
    colors: [..] Color;
    default_colorv4: Vector4 = #run map_default_color_to_vec4(.TEXT_DEFAULT);
    font_override: *Simp.Dynamic_Font;
    x_offset: s64 = 0;
    y_offset: s64 = 0;
}

draw_text :: (x: s64, y: s64, ts: Text_Style) -> width: s64 {
    font := r_font;
    if ts.font_override {
        font = ts.font_override;
    }
    
    Simp.set_shader_for_text();
    
    width := Simp.prepare_text(font, ts.text, effect_flags=0);
    Simp.generate_quads_for_prepared_text(font, x, y, effect_flags=0);
    draw_generated_quads(ts, font);

    return width;
}

draw_generated_quads :: (using styled_text: Text_Style, font: *Simp.Dynamic_Font) {
    // #import "GL"(DUMP_GL_ERRORS=true, ENABLE_ALL_EXTENSIONS=false, DEFAULT_MSAA=4)();
    #import "GL";

    Simp.CheckInit();
    quads := font.current_quads;

    if state.current_shader Simp.immediate_flush();

    Simp.immediate_begin();

    glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);
    glEnable(GL_BLEND);

    draw_letter_quad :: inline (font: *Simp.Dynamic_Font, quad: Simp.Font_Quad, color: Vector4) {
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

    t := text;
    index := 0;

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

        color := default_colorv4;
        if index < colors.count {
            color = map_color_to_vec4(colors[index]);
        }

        inline draw_letter_quad(font, quad, color);

        t.data += 1 + trailingBytesForUTF8[t[0]];
        index += 1;
    }

    Simp.immediate_flush();

    glDisable(GL_BLEND);
}

draw_text :: inline (s: string, left: s64, bottom: s64, color: Vector4) -> s64 {
    w := Simp.prepare_text(r_font, s);
    Simp.draw_prepared_text(r_font, left, bottom, color);
    return w;
}

draw_character_height_aware_rect :: (font: *Simp.Dynamic_Font, left: float32, width: float32, bottom: float32, color: Vector4) {
    ch := font.character_height;

    Simp.immediate_quad(left, bottom + (ch-ch*0.1), left+width, bottom - (ch/2-(ch*0.2)), color);
}

draw_code :: (buffer: *Buffer, x: s64, y: s64, text: string) -> width: s64 {
    font := r_font;
    
    width := Simp.prepare_text(font, text, 0);
    Simp.generate_quads_for_prepared_text(font, x, y, 0);
    
    Simp.set_shader_for_text();
    draw_generated_quads(buffer, text, font);

    return width;
}

draw_generated_quads :: (buffer: *Buffer, text: string, font: *Simp.Dynamic_Font) {
    // #import "GL"(DUMP_GL_ERRORS=true, ENABLE_ALL_EXTENSIONS=false, DEFAULT_MSAA=4)();
    #import "GL";

    Simp.CheckInit();
    quads := font.current_quads;

    if state.current_shader Simp.immediate_flush();

    Simp.immediate_begin();

    glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);
    glEnable(GL_BLEND);

    draw_letter_quad :: inline (font: *Simp.Dynamic_Font, quad: Simp.Font_Quad, color: Vector4) {
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

    t := text;
    index := t.data - buffer.data;

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

        color := map_color_to_vec4(buffer.colors[index]);

        inline draw_letter_quad(font, quad, color);

        t.data += 1 + trailingBytesForUTF8[t[0]];
        index = t.data - buffer.data;
    }

    Simp.immediate_flush();

    glDisable(GL_BLEND);
}

draw_debug_mouse_character_selection :: (editor: *Editor, r: Rect) {
    Simp.set_shader_for_color(true);
    
    buffer := editor.active_buffer;

    mx, my, ok := get_mouse_pointer_position(right_handed=false);
    if (ok) {
        row_index := get_row_index_from_y_px(xx my, y_is_relative=true);
        if row_index != -1 {
            row_str := get_row_as_string(buffer, row_index);
            width := measure_text_width(r_font, row_str);
            bottom  := (r.h+r.y) - fnt_get_line_height(row_index+1) + editor.top_offset;
            ch      := r_font.character_height;
            Simp.immediate_quad(0.0, bottom + (ch-ch*0.1), xx width, bottom - (ch/2-(ch*0.2)), Vector4.{.3, .21, .21, .5});
        }

        approx_row := cast(s64)floor((my+editor.top_offset) / fnt_get_line_height());

        first := first_visible_row_index(editor, buffer);
        last  := last_visible_row_index(editor, buffer);
        for i: first..last {
            if i == approx_row {
                s := get_row_as_string(buffer, i);

                ch      := r_font.character_height;
                bottom  := (r.h+r.y) - fnt_get_line_height(approx_row+1) + editor.top_offset;
                // width   := Simp.prepare_text(r_font, s);
                // Simp.immediate_quad(0.0, bottom + (ch-ch*0.1), xx width, bottom - (ch/2-(ch*0.2)), Vector4.{.3, .21, .21, .5});

                cw := 0;
                left := 0.0;
                while s.count {
                    cw = Simp.get_character_width_in_pixels(r_font, s.data, .LEFT_JUSTIFIED);
                    if cast(float)mx <= left break;

                    left += cw;

                    bytes := 1 + trailingBytesForUTF8[s[0]];
                    s = advance(s, bytes);
                }

                if cw == 0 {
                    cw = r_font.em_width;
                    Simp.immediate_quad(0.0, bottom + (ch-ch*0.1), cast(float)cw, bottom - (ch/2-(ch*0.2)), Vector4.{1.0, .5, .3, .9});
                } else {
                    Simp.immediate_quad(left-cw, bottom + (ch-ch*0.1), left, bottom - (ch/2-(ch*0.2)), Vector4.{1.0, .5, .3, .9});
                }

                break;
            }
        }
    }
}

draw_quad :: (p0: Vector2, p1: Vector2, p2: Vector2, p3: Vector2, color: Vector4) {
    Simp.immediate_quad(p0, p1, p2, p3, color);  //  @Speed
}

draw_quad :: (r: Rect, color: Vector4) {
    p0, p1, p2, p3 := get_quad(r);
    draw_quad(p0, p1, p2, p3, color);
}

push_scissor :: (_rect: Rect) {
    rect := _rect;

    if scissor_stack {
        top := peek_pointer(scissor_stack);
        rect = intersect(top.*, rect);
    }

    set_scissor(rect);
    array_add(*scissor_stack, rect);
}

pop_scissor :: () {
    pop(*scissor_stack);

    if scissor_stack {
        r := peek(scissor_stack);
        set_scissor(r);
    } else {
        Simp.clear_scissor();
    }
}

set_scissor :: (r: Rect) {
    x0 := cast(s32) r.x;
    y0 := cast(s32) r.y;
    x1 := cast(s32) (r.x + r.w);
    y1 := cast(s32) (r.y + r.h);

    Simp.set_scissor(x0, y0, x1, y1);
}

scissor_stack: [..] Rect;