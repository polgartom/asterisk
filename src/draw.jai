draw_frame :: () {
    c := map_color_to_vec4(.BACKGROUND);
    Simp.clear_render_target(c.x, c.y, c.z, c.w);

    Simp.set_shader_for_color(true);

    x, y, width, height := get_dimensions(window, true);

    rect := make_rect(0.0, 0.0, xx width, xx height);
    
    // maybe_set_hot(.none, make_rect(0.0, 0.0, xx window_width, xx window_height));
    UI.hot = .none;
    // set_cursor_icon(.CUR_ARROW);

    if editor_panels_width == 0 || editor_panels_auto_size {
        editor_panels_width = rect.w / 2;
    }
    
    min_max_threshold := 100.0 * dpi_scale;
    editor_panels_width = max(min_max_threshold, editor_panels_width);
    editor_panels_width = min(width - min_max_threshold, editor_panels_width);

    if editors[0].visible && editors[1].visible {
        v := 1.0;
        if editors[1].width_anim.active {
            using editors[1].width_anim;
            
            t := (frame_time64 - started_at) / duration;
            t = clamp(t, 0.0, 1.0);
            distance := (target - start);
            v = start + cast(float)(distance * t * t * (3.0 - 2.0 * t)); // smoothstep
            if t == 1.0 then active = false;
            
            redraw_requested = true;
        }
        
        // We divide it with v rather than multiply because we want to animate right to left.
        // Maybe will be simpler if you just test it yourself. Try to multiply rather than divide and see the result.
        left, right := cut_left(rect, min(cast(float)width, editor_panels_width / v));
        right = cut_right(right, floor(right.w));
        sepa_rect := right;

        draw_editor(*editors[0], left, .editor_left);
        draw_editor(*editors[1], right, .editor_right);

        Simp.set_shader_for_color(true);
        sepa_rect.x -= 1 * dpi_scale;
        sepa_rect.w  = 2 * dpi_scale;
        sepa_color := map_color_to_vec4(.LAYOUT_SEPARATOR);
                
        maybe_set_hot(.editors_layout_separator, sepa_rect);
        
        if (UI.hot_last_frame == .editors_layout_separator && !mouse_grabbed_ui_id) || mouse_grabbed_ui_id == xx Ui_Id.editors_layout_separator {
            set_cursor_icon(.CUR_SIZEWE);
            sepa_color.w = .5; // alpha @Incomplete specify separate color for this!
            
            if mouse_dbl_clicked {
                editor_panels_width = 0;
                editor_panels_auto_size = true;
                
            } else if mouse_down {
                mx := get_mouse_pointer_position_right_handed();
                if !mouse_grabbed_ui_id {
                    mouse_grabbed_ui_id = xx Ui_Id.editors_layout_separator;
                    editor_panels_grabbed_x = xx mx;
                }
                editor_panels_width += xx ((mx - editor_panels_grabbed_x));
                editor_panels_grabbed_x = xx mx;
                editor_panels_auto_size = false;
            }
        }
        
        draw_quad(sepa_rect, sepa_color);
        
    } else {
        v := 0.0;
        if editors[1].width_anim.active {
            using editors[1].width_anim;
            
            t := (frame_time64 - started_at) / duration;
            t = clamp(t, 0.0, 1.0);
            distance := (target - start);
            // v = start + cast(float)(distance * t * t * (3.0 - 2.0 * t)); // smoothstep
            v = start + cast(float)(distance * t * t); // smoothstep
            if t == 1.0 then active = false;
            
            redraw_requested = true;
        }
        
        right, left := cut_right(rect, editor_panels_width*v);
        
        draw_editor(*editors[0], left, .editor_left);
        if right.w != 0 {
            draw_editor(*editors[1], right, .editor_right);
        }
    }
    
    // Widgets
    if mode == .WIDGET {
        draw_widgets();
    }
    
    UI.hot_last_frame = UI.hot;
    
    if show_font_debug_info {
        draw_font_metrics_debug(active_editor);
    }
        
    if show_debug_info {
        draw_global_debug_info(get_not_active_editor().rect_for_draw);
        // draw_debug_mouse_character_selection(active_editor, active_editor.rect_for_draw);
    }
    
        
    #if PROFILER && #exists(__Iprof) {
        if show_profiler {
            __Iprof.update(true);
            Iprof_Config.font_character_height = xx (r_font_tiny.character_height*2);
            Iprof_Config.line_spacing = xx (r_font_tiny.default_line_spacing);
            mx, my, ok := get_mouse_pointer_position(right_handed=false);
            __Iprof.set_cursor_screen_coordinates(xx mx, xx my);
            
            r := get_not_active_editor().rect_for_draw;
            
            height :: 800;
            rect := make_rect(
                xx (r.x + r.w  - 580),
                xx (r.h + r.y - 150 - height),
                xx (550),
                xx (height)
            );
            
            __Iprof.draw(rect.x, rect.y, rect.w, rect.h, *Iprof_Config);
            
            // @Todo:
            // __Iprof.draw_graph(
                // rect.x,
                // rect.y - 50,
                // rect.w,
                // 100,
                // *Iprof_Config
            // );
        }
    }
    
    swap_buffers();
}

#if PROFILER && #exists(__Iprof) {
    Iprof_Config := __Iprof.Config.{
        line_spacing = 0,
        font_character_height = 0,
        
        selected_bar_whiten_amount = 0.15,
    
        draw_text = (x: float, y: float, str: string, color: Vector4) {
            draw_text(xx x, xx (window_height - y + r_font_tiny.y_offset_for_centering), str, r_font_tiny, color);
        },
        text_width = (s: string) -> float {
            return xx measure_text_width(r_font_tiny, s);
        },
        draw_rectangle = (x0: float, y0: float, x1: float, y1: float, color: Vector4) {
            Simp.immediate_quad(x0, xx (window_height-y0), x1, xx (window_height-y1), color);
        },
        // draw_line = (p0: Vector2, p1: Vector2, p2: Vector2, p3: Vector2, color: Vector4) {
    
        // }
    };
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

draw_editor :: (using editor: *Editor, rect: Rect, ui_id: Ui_Id) {
    

    if !is_active(editor) context.color_intensity *= 0.95;
    defer reset_color_intensity();
        
    editor.panel_rect = rect;
    
    r, footer_r := cut_top(rect, window_height - get_footer_height());
    
    tabs_rect, r= := cut_top(r, xx (r_font.default_line_spacing*1.5));
    
    scrollbar_width := r_font.em_width * 1.5;
    scrollbar_area := cut_right(r, scrollbar_width);
    
    line_numbers_rect := r;
    if show_line_numbers && buffers.count {
        rows_count := max(100, editor.active_buffer.row_table.count);
        t := tprint("%", formatInt(rows_count, digits_per_comma=0));
        w := measure_text_width(r_font_sm, t) * 1.5;
        line_numbers_rect, r = cut_left(r, w);
        // _, tabs_rect = cut_left(tabs_rect, line_numbers_rect.w); // We align the tabs to the scrollbar
    }
    
    maybe_set_hot(ui_id, r);
    
    left_padding := r_font.em_width;
    _, r= := cut_left(r, xx left_padding);
    editor.rect_for_draw = r;
    
    if UI.hot_last_frame == ui_id && !mouse_grabbed_ui_id {
        set_cursor_icon(.CUR_BEAM);
            
        if mouse_clicked {
            close_current_widget();
        }
            
        mx, my := get_mouse_pointer_position(right_handed=true);
        if !is_point_in_rect(scrollbar_area, Vector2.{xx mx, xx my}) { // @Hacky
            if mouse_down {
                active_editor = editor;
                
                mx, my, ok := get_mouse_pointer_position(right_handed=false);
                pos := byte_pos_from_mouse_xy(editor, editor.active_buffer, mx, my);
                if pos != -1 {
                    set_cursor_pos(editor.active_buffer, *editor.cursor, pos, horizontal=true, with_selection=!vk_shift_down);
                }
            } else if mouse_dbl_clicked {
                // @Incomplete: Do this with no double click but click+click and we don't wait the 2. mouse release
                SelectSimilarCharacters();
            } else if mouse_scrolled_on_frame == .up {
                if vk_ctrl_down {
                    font_size += 1;
                    init_fonts();
                    force_editors_viewports_recalculations();
                } else if vk_shift_down {
                    scroll_left(editor);
                } else {
                    scroll_up(editor);
                }
            } else if mouse_scrolled_on_frame == .down {
                if vk_ctrl_down {
                    font_size -= 1;
                    init_fonts();
                    force_editors_viewports_recalculations();
                } else if vk_shift_down {
                    scroll_right(editor);
                } else {
                    scroll_down(editor);
                }
            }
        }
    }
    
    if editor.y_scroll_anim.active {
        using editor.y_scroll_anim;

        t := (frame_time64 - started_at) / duration;
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

        t := (frame_time64 - started_at) / duration;
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
    
    // Draw line numbers
    if show_line_numbers && buffers.count {
        rect := line_numbers_rect;
        
        Simp.set_shader_for_color(true);
        Simp.immediate_quad(rect.x, rect.y, rect.x + rect.w, rect.y + rect.h, map_color_to_vec4(.BACKGROUND2));
        Simp.immediate_quad(rect.x + rect.w, rect.y, rect.x + rect.w + 1.0, rect.y + rect.h, map_color_to_vec4(.LAYOUT_SEPARATOR)); // right border
        
        // rect = shrink_x(rect, r_font_sm.em_width*1.0);
        // rect.w -= r_font_sm.em_width*1.0;
        
        line_height := fnt_get_line_height();
        start_row := first_visible_row_index(editor, editor.active_buffer);
        end_row   := last_visible_row_index(editor, editor.active_buffer);
        
        color := map_color_to_vec4(.TEXT_DIMMED);
        
        array_reset_keeping_memory(*editor.active_buffer.quads_for_code_run);
        for ri: start_row..end_row {
            t := tprint("%", formatInt(ri+1, digits_per_comma=0));
            
            baseline := (rect.h + rect.y) - (line_height*(ri+1)) + top_offset;
            width := Simp.prepare_text(r_font_sm, t);
            left := rect.x + (rect.w/2 - width/2);
            // left := rect.x + max(0.0, rect.w - width);
            
            Simp.generate_quads_for_prepared_text(r_font_sm, xx left, xx baseline, 0);
            for quad: r_font_sm.current_quads {
                array_add(*editor.active_buffer.quads_for_code_run, .{quad, color});
            }
        }
        
        draw_code_run(editor.active_buffer);
    }

    draw_selection(editor, editor.active_buffer, r);

    draw_buffer_code(editor, editor.active_buffer);

    draw_cursor(editor, editor.active_buffer, r, cursor_shape, cursor_line_indicator);

    {
        // Draw scrollbar
        //MeasureScope("Draw scrollbar");
    
        Simp.set_shader_for_color(true);
    
        scrollbar_ui_id := ifx ui_id == .editor_left then Ui_Id.editor_left_scrollbar else Ui_Id.editor_right_scrollbar;
        
        // @Todo :WhiteSpacesAfterLastRow Make a procedure for this because we need to know what is the maximum empty space in rows that we show after the last row.
        y_threshold := fnt_get_line_height() * 6; 
        total_height := fnt_get_line_height() * editor.active_buffer.row_table.count + y_threshold;
        
        min_scroll := 0.0;
        max_scroll := total_height - r.h;
    
        area := scrollbar_area;        
        scrollbar := area;
        scrollbar.h = area.h * (area.h / total_height);
        scrollbar.h = max(20.0, scrollbar.h);
        scroll_zone_height := max(0.0, area.h - scrollbar.h);
                
        get_scrollbar_y :: (scrollbar: Rect, scroll: float32) -> float #expand {
            y := `scroll_zone_height * (`max_scroll - scroll) / (`max_scroll - `min_scroll) + `area.y;
            y = floor(y);
            return y;
        }
        
        scrollbar.y = get_scrollbar_y(scrollbar, editor.top_offset);
        
        mx, my := get_mouse_pointer_position_safe(right_handed=true);
        mouse_point := Vector2.{cast(float)mx, cast(float)my};
        
        // a := (mx - editor.panel_rect.x);
        // b := (area.x - editor.panel_rect.x);
        // if a > b then swap(*a, *b);
        // opacity := lerp(0.25, 0.8, (a / b));
        opacity := .25;
        
        if (UI.hot_last_frame == ui_id && mouse_point_within_rect(area) && mouse_grabbed_ui_id == 0) || mouse_grabbed_ui_id == xx scrollbar_ui_id {
            set_cursor_icon(.CUR_ARROW);
            opacity = .8;
            
            if mouse_down {
                active_editor = editor;
                
                if mouse_grabbed_ui_id != xx scrollbar_ui_id {
                    mouse_grabbed_ui_id = xx scrollbar_ui_id;

                    editor.scrollbar_grabbed_y = scrollbar.h / 2;
                    //if mouse_point.y > scrollbar.y && mouse_point.y < scrollbar.y + scrollbar.h {
                    if mouse_point_within_rect(scrollbar) {
                        editor.scrollbar_grabbed_y = scrollbar.h - (my - scrollbar.y);
                    }
                }
                
                grab_point := editor.scrollbar_grabbed_y;
                if scroll_zone_height > 0 {
                    editor.top_offset = (area.h + area.y - cast(float, my) - grab_point) / (area.h) * total_height;
                    editor.top_offset = max(0.0, editor.top_offset);
                    editor.top_offset = min(max_scroll, editor.top_offset);
                }
            }
        }
        
        scrollbar.y = get_scrollbar_y(scrollbar, editor.top_offset);
        
        color := map_color_to_vec4(.BACKGROUND2);
        color.w = opacity;
        draw_quad(area, color);
        
        left_border_rect := cut_left(area, 1);
        color = map_color_to_vec4(.LAYOUT_SEPARATOR);
        color.w = 0.1*opacity;
        draw_quad(left_border_rect, color);
        
        if scroll_zone_height > 0 {
            Simp.set_shader_for_rect();
            color := Vector4.{1, 1, 1, opacity*0.5};
            radius := 4.0 * dpi_scale;
            Simp.immediate_quad_with_radius(scrollbar.x, scrollbar.y, scrollbar.x + scrollbar.w, scrollbar.y + scrollbar.h, color, radius=radius);
            //Simp.immediate_quad(scrollbar.x, scrollbar.y, scrollbar.x+scrollbar.w, scrollbar.y + scrollbar.h, .{1,1,1,.5});
            //draw_quad(scrollbar, .{1, 1, 1, editor.scrollbar_opacity});
        }
        
        //Simp.immediate_quad(scrollbar.x, scrollbar.y+scrollbar.h+1, scrollbar.x+scrollbar.w, scrollbar.y+scrollbar.h-1, .{1,0,0,1});
        //Simp.immediate_quad(scrollbar.x, scrollbar.y+scrollbar.h/2+1, scrollbar.x+scrollbar.w, scrollbar.y+scrollbar.h/2-1, .{1,0,0,1});
        //Simp.immediate_quad(scrollbar.x, scrollbar.y+1, scrollbar.x+scrollbar.w, scrollbar.y-1, .{1,0,0,1});
        
        Simp.set_shader_for_color(true);
        
        put_line_marks_to_scrollbar :: (pos: s64, colorv4: Vector4) #expand {
            MARK_HEIGHT := 2 * dpi_scale;
            
            row_index := find_row_index(editor.active_buffer, pos);
            top_pos := fnt_get_line_height() * row_index;
            min_height := 0;
            max_height := fnt_get_line_height() * editor.active_buffer.row_table.count;
            y := area.y + area.h * (max_height - top_pos) / (max_height - min_height) - MARK_HEIGHT;
            
            Simp.immediate_quad(area.x, y, area.x + area.w, y + MARK_HEIGHT, colorv4);
        }
        
        if is_active(editor) {
            if mode == .WIDGET && active_widget == Find_Text_Dialog {
                color := map_color_to_vec4(.TEXT_HIGHLIGHT);
                color.w = .5; //alpha
                last_pos := -1;            
                for pos: find_text_dialog.occurrences {
                    if last_pos == pos continue; // don't draw more than once
                    last_pos = pos;
                    put_line_marks_to_scrollbar(pos, color);
                }
            }
            
            {
                // @Todo: Draw current selection occurrences
            }
        }

        {
            // Show the cursor position on the scrollbar
            color := map_color_to_vec4(.CURSOR);
            color.w = .8; //alpha
            put_line_marks_to_scrollbar(editor.cursor.pos, color);
        }
    }

    {
        // Draw tabs
        // @Cleanup This mess...
        
        MeasureScope("Draw tabs");
        
        font := r_font_sm;
        rect := tabs_rect;
        padding := font.em_width * dpi_scale;

        // rect.w -= scrollbar_area.w;
        // rect = shrink_x(rect, scrollbar_area.w); // This will ends at where the scrollbar starts, so the left and right editor tabs will be separated nicely.
        
        EDITOR_TABS_UI_ID := ifx ui_id == .editor_left then Ui_Id.editor_left_tabs else .editor_right_tabs;
        maybe_set_hot(EDITOR_TABS_UI_ID, rect);
                        
        Simp.set_shader_for_color(true);
        push_scissor(rect);
        defer pop_scissor();
        
        Simp.immediate_quad(rect.x, rect.y, rect.x + rect.w, rect.y + rect.h, map_color_to_vec4(.BACKGROUND2));
        Simp.immediate_quad(rect.x, rect.y, rect.x + rect.w, rect.y + 1, map_color_to_vec4(.LAYOUT_SEPARATOR));
        
        rect = shrink_x(rect, padding); 
        rect.w -= (scrollbar_area.w - padding); // This will ends at where the scrollbar starts, so the left and right editor tabs will be separated nicely.
        
        if editor.tabs_anim.active {
            using editor.tabs_anim;
    
            t := (frame_time64 - started_at) / duration;
            t = clamp(t, 0.0, 1.0);
            distance := (target - start);
            // v := start + cast(float)(distance * t * t * (3.0 - 2.0 * t)); // smoothstep
            v := start + cast(float)(distance * t);                          // lerp
    
            if t == 1.0 then active = false;
    
            editor.tabs_left_offset = v;
            
            redraw_requested = true;
        }
        
        left := rect.x - editor.tabs_left_offset;
        baseline := rect.y + default_text_baseline(font, rect.h);
        workdir := get_workdir();
        total_width := 0.0;
        for b: editor.tabs {
            tab_label := ifx b.name then b.name else "Untitled";
            if b.filepath {
                tab_label = b.filepath;
                if begins_with(tab_label, workdir) {
                    advance(*tab_label, workdir.count + 1); // +1 for the path separator
                    assert(tab_label.count > 0);
                }
            }
              
            bg_color_locked := false;
            fg_color_locked := false;
            fg_color   := map_color_to_vec4(.TEXT_DIMMED);
            bg_color   := v4(1, 1, 1, .02);
            icon_font  := r_font_icons;
            icon_glyph := FILE_ICON;
            
            if b.disk_state == .removed {
                fg_color = v4(.9, .4, .4, 1.0); // @Todo: Other Color
                fg_color_locked = true;
            } else if is_unsaved(b) {
                icon_font  = r_font_icons_solid;
                icon_glyph = PEN_ICON;
                
                fg_color = map_color_to_vec4(.CURSOR); // @Todo: Other Color
                fg_color_locked = true;
            } else if b.kind == .editor_config {
                icon_font  = r_font_icons_solid;
                icon_glyph = GEARS_ICON;
            } else if b.kind == .stdout {
                icon_font  = r_font_icons_solid;
                icon_glyph = TERMINAL_ICON;
                
                if b.stdout_stalled {
                    bg_color = #run hex_to_vec4(0xffc107_50); // @Todo: Specify a color
                    bg_color_locked = true;
                } else if b.stdout_in_progress {
                    bg_color = #run hex_to_vec4(0x618833_40); // @Todo: Specify a color
                    bg_color_locked = true;
                }
            }
            
            width := Simp.prepare_text(font, tab_label);
            icon_width := Simp.prepare_text(icon_font, icon_glyph);
            icon_width += xx padding;
            width += icon_width;
            tab_rect := make_rect(left - padding, rect.y, width + padding*2, rect.h);
            
            if UI.hot_last_frame == EDITOR_TABS_UI_ID && b != editor.active_buffer {
                if mouse_point_within_rect(rect) && mouse_point_within_rect(tab_rect) {
                    if !fg_color_locked then fg_color = map_color_to_vec4(.TEXT_DEFAULT);
                    if !bg_color_locked then bg_color = v4(1, 1, 1, .08);
                    
                    if mouse_clicked {
                        active_editor = editor;
                        change_active_buffer(editor, b);
                    }
                }
            }
            
            if b == editor.active_buffer {
                if !fg_color_locked then fg_color = map_color_to_vec4(.TEXT_DEFAULT);
                if !bg_color_locked then bg_color = v4(1, 1, 1, .1);
            }
            
            if editor.tabs_force_offset_check && b == editor.active_buffer {
                // Move the viewport to the selected buffer's tab
                
                if !editor.tabs_anim.active {
                    target := editor.tabs_left_offset;
                    if tab_rect.x + tab_rect.w > rect.x + rect.w {
                        target += ((tab_rect.x + tab_rect.w) - (rect.x + rect.w));
                    } else if tab_rect.x < rect.x {
                        target -= (rect.x - tab_rect.x);
                    }
                    
                    if target != editor.tabs_left_offset {
                        anim_x: Anim;
                        anim_x.active = true;
                        anim_x.start  = editor.tabs_left_offset;
                        anim_x.target = target;
                        anim_x.duration = .08;
                        anim_x.started_at = frame_time64;
                        editor.tabs_anim = anim_x;
                        redraw_requested = true;
                    }
                }
            }
            
            Simp.set_shader_for_color(true);
            draw_quad(tab_rect, bg_color);
            
            Simp.set_shader_for_text();
            Simp.draw_prepared_text(icon_font, xx (left), xx baseline, fg_color);
            Simp.draw_prepared_text(font, xx (left + icon_width), xx baseline, fg_color);
            
            left += width + padding;
            total_width += width + padding;
            
            // Background & Right border
            Simp.set_shader_for_color(true);
            Simp.immediate_quad(left, xx rect.y, xx (left + 1), xx (rect.y + rect.h), map_color_to_vec4(.LAYOUT_SEPARATOR));
            
            if it_index != buffers.count - 1 {
                left += padding;
                total_width += padding;
            }
        }
        
        if UI.hot_last_frame == EDITOR_TABS_UI_ID {
            avg_width := total_width / buffers.count / 2;
            if mouse_scrolled_on_frame == .up {
                target := editor.tabs_left_offset - avg_width;
                target = max(0.0, target);
                anim_x: Anim;
                anim_x.active = true;
                anim_x.start  = editor.tabs_left_offset;
                anim_x.target = target;
                anim_x.duration = 0.05;
                anim_x.started_at = frame_time64;
                editor.tabs_anim = anim_x;
                redraw_requested = true;
            } else if mouse_scrolled_on_frame == .down {
                target := editor.tabs_left_offset;
                if rect.x - editor.tabs_left_offset + total_width >= rect.x + rect.w {
                    //max_val := (rect.x + rect.w) - (rect.x - (editor.tabs_left_offset + avg_width) + total_width);
                    target = target + avg_width; // @Incomplete: CLamp the values                    
                    anim_x: Anim;
                    anim_x.active = true;
                    anim_x.start  = editor.tabs_left_offset;
                    anim_x.target = target;
                    anim_x.duration = 0.05;
                    anim_x.started_at = frame_time64;
                    editor.tabs_anim = anim_x;
                    redraw_requested = true;
                }
            }
        }
        
        {
            // Apply some correction, prevent the overflow during left to right scroll
            // Also, we need to apply correction if window size changes? How VSCode does that? @Incomplete
            
            target := *editor.tabs_left_offset;
            if editor.tabs_anim.active {
                target = *editor.tabs_anim.target;
            }
        
            a := rect.x - (target.*) + total_width;
            b := rect.x + rect.w;
            if a < b {
                correction := (b) - (a);
                target.* -= correction;
            }
            
            target.* = max(0.0, target.*);
        }
        
        editor.tabs_force_offset_check = false;
    }

    {
        // Draw footer
        //MeasureScope("Draw footer");

        push_scissor(footer_r);
        defer pop_scissor();

        footer := footer_r;
        Simp.set_shader_for_color(true);

        fg_color := map_color_to_vec4(.FOOTER_TEXT);
        bg_color := map_color_to_vec4(.FOOTER_BACKGROUND, apply_intensity=false);
        if active_editor != editor {
            bg_color = map_color_to_vec4(.FOOTER_BACKGROUND_DARKEN, apply_intensity=false);
        }
        
        // Footer shape
        Simp.immediate_quad(footer.x, footer.y, footer.x + footer.w, footer.y + footer.h, bg_color);

        width := 0;
        left := footer.x + 10;
        baseline := default_text_baseline(r_font_sm, footer.h, .bottom);

        if show_font_debug_info {
            Simp.immediate_quad(footer.x, footer.y+baseline, footer.x+footer.w, footer.y+baseline+1, .{1,0,0,.7});
            Simp.immediate_quad(footer.x, footer.y+footer.h/2, footer.x+footer.w, footer.y+footer.h/2+1, .{0,.6,.8,.9});
        }

        {
            // Draw buffer's file info
            b := editor.active_buffer;
            info_text := b.name;
            if !b.readonly {
                path := "Untitled";
                if b.filepath {
                    path = b.filepath;
                    workdir := get_workdir();
                    if begins_with(path, workdir) {
                        advance(*path, workdir.count + 1); // +1 for the path separator
                        assert(path.count > 0);
                    }
                }
    
                info_text = tprint(
                    "%1%2%3",
                    path,
                    ifx !b.exists_on_disk then " <new>" else "",
                    ifx is_unsaved(b)     then "*"      else "",
                );
                
                info_text = tprint("% | %", info_text, b.disk_state);
            }

            width = Simp.prepare_text(r_font_sm, info_text);
            Simp.draw_prepared_text(r_font_sm, xx left, xx baseline, fg_color);

            left += width;
        }

        assert(editor.cursor.pos <= editor.active_buffer.count, "buffer: % ; cursor: %\n", editor.active_buffer.count, editor.cursor.pos);

        row := find_row_index(editor.active_buffer, editor.cursor.pos) + 1;
        col := byte_pos_to_row_col_index(editor.active_buffer, editor.cursor.pos) + 1;
        total_row_percent := ceil((row / cast(float32)editor.active_buffer.row_table.count) * 100.0);
        text := tprint("%\% Ln % Col % Byte %  %", total_row_percent, row, col, editor.cursor.pos, language_kind_to_string(editor.active_buffer.language));
        
        width = Simp.prepare_text(r_font_sm, text);
        x := cast(s64, footer.x + footer.w - width * 1.1); // 1.1 is the padding
        y := cast(s64, baseline);
        Simp.draw_prepared_text(r_font_sm, x, y, fg_color);
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
    cw := r_font_max_em_width; //em(1.0, r_font);
    ch := r_font.character_height;

    right_to_left_handed := (r.h + r.y); // so we calculate things from "the top"
    baseline := right_to_left_handed - fnt_get_line_height(row_index + 1) + editor.top_offset;

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
    if buffer.kind == .stdout {
        shape = .UNDERSCORE;
        line_indicator = .NONE;
    }

    p1, p2 := fnt_top_bottom_from_baseline_for_quad(r_font, baseline);

    if #complete line_indicator == {
        case .NONE;
        case .FILLED;
            // Current line indicator shape
            color := map_color_to_vec4(.CURSOR_LINE_BACKGROUND);
            Simp.immediate_quad(r.x, p1, r.x + r.w, p2, color);
        case .BORDERED;
            thickness := 2 * dpi_scale; // @Todo: Add to config
            border_color := #run hex_to_vec4(0xcccccc_1a); // map_color_to_vec4(.CURSOR_LINE_BACKGROUND); // @Todo: Add to config
            Simp.immediate_quad(r.x, p1, r.x + r.w, p1 + thickness, border_color); // top
            Simp.immediate_quad(r.x, p2, r.x + r.w, p2 + thickness, border_color); // bottom
    }

    if #complete shape == {
        case .BLOCK;
            Simp.immediate_quad(cast(float32)cx, p1, cast(float32)(cx + cw), p2, bg_color);
            
            // Change character's color under the cursor
            if buffer.count {
                context.draw_invisible_characters = draw_invisible_characters;
                defer context.draw_invisible_characters = false;
                
                ch := get_character_as_string_at(buffer, c.pos, include_line_end_character=draw_invisible_characters);
                
                Simp.prepare_text(r_font, ch);
                Simp.draw_prepared_text(r_font, xx cx, cast(s64, baseline), fg_color);
                
            }
        case .LINE;
            Simp.immediate_quad(cast(float32)cx, p1, cast(float32)(cx + max(cw*.5, 3.0)), p2, bg_color);

        case .UNDERSCORE;
            Simp.immediate_quad(cast(float32)cx, baseline, cast(float32)(cx + cw), p2, bg_color);
    }

    Simp.immediate_flush();
}

// @Todo: This thing is not doing draws properly. Also we should create an array of selections, because
// we should draw those after the find text widget.
draw_selection :: (editor: *Editor, buffer: *Buffer, r: Rect) {
    //MeasureScope("Draw selection");

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

    first_visible_ri := first_visible_row_index(editor, buffer);
    last_visible_ri := last_visible_row_index(editor, buffer);

    for row_index: start_row..end_row {
        if row_index < first_visible_ri|| row_index > last_visible_ri continue;
        
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

        baseline := (r.h+r.y) - (line_height*(row_index+1)) + editor.top_offset;
        p1, p2 := fnt_top_bottom_from_baseline_for_quad(r_font, baseline);
        Simp.immediate_quad(left, p1, left+width, p2, selection_color);
    }

    show_selection_occurrences := false;
    t := s.data;
    while t < s.data + s.count {
        if !is_whitespace(t.*) {
            // We don't want to highlight a bunch of spaces without one unicode character at least
            show_selection_occurrences = true;
            break;
        }

        t += 1 + trailingBytesForUTF8[t.*];
    }

    if show_selection_occurrences {
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

            //Simp.set_shader_for_color(true); // do we need this right here?
            baseline := (r.h + r.y) - (line_height*(ri+1)) + editor.top_offset;
            p1, p2 := fnt_top_bottom_from_baseline_for_quad(r_font, baseline);
            Simp.immediate_quad(left, p1, left + width, p2, map_color_to_vec4(.TEXT_SELECTION_MATCH));
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
    update_text_input(tinp, r, font, placeholder="> Run command", theme=theme);
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

    options := buffer_browser.visible_options;

    list_rect := r;
    list_rect.h = 1.5*k;

    linp_theme := List_Input.DEFAULT_THEME;
    linp_theme.border_color = #run hex_to_vec4(0x30_25_0a_ff);
    linp_theme.current_item_bg_color = #run hex_to_vec4(0x30_25_0a_ff);
    linp := list_input(list_rect, buffer_browser.bb_list_input_ui_id, options, font, theme=linp_theme);
    
    if tinp.typed update_visible_options(*buffer_browser);
    
    if linp.entered && options.count {
        if linp.selected_index >= options.count || linp.selected_index < 0 {
            assert(false, "Invalid index: % ; options: % ; buffers: %\n", linp.selected_index, options, buffers);
            return;                
        }
        
        selected_option := options[linp.selected_index];
        buffer := selected_option.ref;
        change_active_buffer(active_editor, buffer);

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
    theme.border_color = #run hex_to_vec4(0x573a7aff);
    theme.placeholder_color = #run hex_to_vec4(0xff_ff_ff_8a);
    theme.cursor_color = #run hex_to_vec4(0xff_ff_ff_c5);

    //if process {
        //theme.border_color = #run hex_to_vec4(0x2a2a2a_ff);
    //}
    
    k := window_height * .2;

    target_width := max(window_width * 0.5 - em(2.0, font), 400); // @Tempoary
    target_height := k * 1.5;
    w := 0;
    h := target_height;

    {
        using open_animation;
        
        v := open_animation.target;
        if active {
            t := (frame_time64 - started_at) / duration;
            t = clamp(t, 0.0, 1.0);
            distance := (target - start);
            v = start + cast(float)(distance * t * t * (3.0 - 2.0 * t)); // smoothstep
            //v = start + cast(float)(distance * t); // lerp
            if t == 1.0 then active = false;
            
            redraw_requested = true;
        }
        
        w = cast(s64, target_width * v);
        
        redraw_requested = true;
        fgt_input.arrange_offset_this_frame = false;
    }

    text_input_height := cast(float, font.character_height * 2.0);
    b := cast(float, window_height - k*.1);
    r := make_rect(ed_r.x - pad, b - text_input_height, ed_r.w, text_input_height);
    r.x = window_width*.5 - w;
    r.w = w * 2.0;
    r.y += 5.0; 

//    label(xx r.x, xx (r.y + r.h + font.character_height*.55), "Loading..", font, theme.fg_color);

    update_find_global_text_dialog();

    if process {
        color := #run hex_to_vec4(0x6a2a2a_ff);
        
        t := .6;
        blend_factor := sin(TAU * cast(float, frame_time64) * t);
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
    list_rect.h = xx h;

    linp_theme := List_Input.DEFAULT_THEME;
    linp_theme.border_color = #run hex_to_vec4(0x573a7aff);
    linp_theme.current_item_bg_color = #run hex_to_vec4(0x573a7a_8a);
    linp := list_input(list_rect, fgt_list_input_ui_id, options, font, theme=linp_theme);

    if fgt_input.typed {
        reset_list_input(find_global_text_dialog);
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
            ed_r.h - get_footer_height(),
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
        if occurrences {
            theme.border_color = #run hex_to_vec4(0x20_51_22_ff);
        } else if input.text {
            theme.border_color = #run hex_to_vec4(0xa9_22_22_a0);
        }

        find_text_dialog_ui_id :: cast(Ui_Id)#location();
        maybe_set_hot(find_text_dialog_ui_id, r);
        if UI.hot_last_frame == find_text_dialog_ui_id {
            set_cursor_icon(.CUR_BEAM);
        }

        update_text_input(input, r, font, placeholder="Find text", theme);

        weight :: 2; // border weight
        r.h = ch*1.5;
        r.y -= r.h + 5 + weight*2;
        r.w *= .30;

        Simp.set_shader_for_rect();
        Simp.immediate_quad_with_radius(r.x - weight, r.y - weight, r.x + r.w + weight, r.y+r.h + weight, theme.bg_color, radius=r_rect_radius);
        hint := tprint("%/%", current_occurrence+1, occurrences.count);
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

    for pos: occurrences {
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
        ed_r.h - get_footer_height(),
        width,
        xx font.character_height * 2.0,
    );

    // @Temporary: We don't want to set those values on every frame, right?
    theme := Text_Input.DEFAULT_THEME;
    theme.bg_color = #run hex_to_vec4(0x18_20_20_ff); // 0x122922_ff
    // theme.border_color = #run hex_to_vec4(0x18_20_20_ff);
    theme.fg_color = #run hex_to_vec4(0xff_ff_ff_a9);
    theme.placeholder_color = #run hex_to_vec4(0xff_ff_ff_8a);
    theme.cursor_color = #run hex_to_vec4(0xff_ff_ff_c5);
    theme.border_color = #run hex_to_vec4(0xff_ff_ff_40);
    
    line, ok := get_goto_line_dialog_value();
    if ok && is_valid_line(buffer, line) {
        theme.border_color = #run hex_to_vec4(0x5a_9e_22_6a);
    }

    update_text_input(input, r, font, placeholder="Go to line", theme);

    update_goto_line_dialog();

    if !input.text return;
}

draw_global_debug_info :: (r: Rect) {
    e,b := get_active_editor_and_buffer();

    Simp.immediate_begin();
        
    PrintDev("[line-ends-scan] % lines | %ms\n", b.row_table.count, b.row_table_recalc_time);
    PrintDev("[syntax-highlighting] %ms\n", b.tokenization_time);
    //PrintDev("[code-draw-time (%)] avg %ms\n", buffer_code_draw_method, get_avg_from_measurement(*code_render_time));
    PrintDev("[viewport] x:% y:% | w:% h:%\n", e.left_offset, e.top_offset, e.rect_for_draw.w, e.rect_for_draw.h);
    mx, my, ok := get_mouse_pointer_position_right_handed();
    PrintDev("[mouse] x:% y:%\n", mx, my);
    PrintDev("[os] wait_os_event: %\n", wait_os_event_before_redraw);
    PrintDev("[video/vsync]: %\n", video_get_vsync());
    PrintDev("[frame] % | avg %ms\n", frame, get_avg_from_measurement(frametimes));

    PADDING :: 10;
    font := r_font_tiny;
    line_height := fnt_get_line_height();
    left := r.x + r.w - 30;
    baseline := r.y + line_height;
    max_width := 0;
    height := 0.0;
    
    for debug_infos {
        s := trim(it, "\n");
        width := measure_text_width(font, s);
        if width > max_width then max_width = width;
        height += line_height;
    }
    
    {
        Simp.set_shader_for_color(true);
        rect := make_rect(left - max_width, baseline, xx max_width, height);
        rect = expand(rect, PADDING);
        rect.x -= PADDING;
        draw_quad(rect, .{0, 0, 0, .7});
    }

    Simp.set_shader_for_text();
    for debug_infos {
        s := trim(it, "\n");

        w := Simp.prepare_text(font, s);
        baseline += line_height;
        Simp.draw_prepared_text(font, xx (left - w - PADDING), xx (baseline - PADDING), .{.4, .7, .8, 1});
    }
    
    Simp.immediate_flush();
}

draw_font_metrics_debug :: (editor: *Editor) {
    r := editor.rect_for_draw;
    
    push_scissor(r);
    defer pop_scissor();
    
    Simp.set_shader_for_color(true);
    
    c  := *editor.cursor;
    row_index := find_row_index(editor.active_buffer, c.pos);
    right_to_left_handed := (r.h + r.y); // so we calculate things from "the top"
    baseline := right_to_left_handed - fnt_get_line_height(row_index + 1) + editor.top_offset;
    p1 := baseline + r_font.typical_ascender;
    p2 := baseline - abs(r_font.typical_descender); // the descender is negative value for some reason!!!
    line_gap_from_baseline := r_font.default_line_spacing - abs(r_font.typical_ascender) - abs(r_font.typical_descender);
    p3_top    := baseline + r_font.typical_ascender + line_gap_from_baseline;
    p3_bottom := baseline - abs(r_font.typical_descender) - line_gap_from_baseline;
    actual_line_gap := line_gap_from_baseline / 2; // ??? It seems we get the line_gap with this of the bottom or the top (both hopefully)
    p4_top    := baseline + r_font.typical_ascender + actual_line_gap;
    p4_bottom := baseline - abs(r_font.typical_descender) - actual_line_gap;
    
    //Simp.immediate_quad(r.x, p1, r.x + r.w, p1+1, #run hex_to_vec4(0x60_80_Af_ff)); // character_height
    Simp.immediate_quad(r.x, p1, r.x + r.w, p1+1, #run hex_to_vec4(0x60_80_Af_ff)); // ascender
    Simp.immediate_quad(r.x, baseline, r.x + r.w, baseline+1, #run hex_to_vec4(0xff_00_20_5a)); // baseline
    Simp.immediate_quad(r.x, p2, r.x + r.w, p2+1, #run hex_to_vec4(0x20_ff_00_5a)); // descender
    Simp.immediate_quad(r.x, p3_top, r.x + r.w, p3_top+1, #run hex_to_vec4(0x80_80_F0_8a)); // line_gap_from_baseline
    Simp.immediate_quad(r.x, p3_bottom, r.x + r.w, p3_bottom+1, #run hex_to_vec4(0x80_80_F0_8a)); // line_gap_from_baseline
    Simp.immediate_quad(r.x, p4_top, r.x + r.w, p4_top+1, #run hex_to_vec4(0xF0_80_F0_8a)); // line_gap (top)
    Simp.immediate_quad(r.x, p4_bottom, r.x + r.w, p4_bottom+1, #run hex_to_vec4(0xF0_80_F0_8a)); // line_gap (bottom)
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

draw_text :: inline (left: s64, baseline: s64, text: string, font: *Simp.Dynamic_Font, color: Vector4  = .{1,1,1,1}) -> s64 {
    w := Simp.prepare_text(font, text);
    Simp.draw_prepared_text(font, left, baseline, color);
    return w;
}

draw_buffer_code :: (using editor: *Editor, using buffer: *Buffer) {
    MeasureScope("draw_buffer_code");

    if !buffer.count return;
    
    r := editor.rect_for_draw;
    line_height := fnt_get_line_height();
    start_row: s64 = xx (top_offset / line_height);
    start_row = clamp(start_row - 1, 0, row_table.count-1);
    end_row := last_visible_row_index(editor, buffer);
    color := map_color_to_vec4(.TEXT_DEFAULT);

    push_scissor(r);
    context.draw_invisible_characters = draw_invisible_characters; // So we can access this value in modules/Simp/font.jai
    
    defer {
        pop_scissor();
        context.draw_invisible_characters = false;
    }
    
    array_reset_keeping_memory(*buffer.quads_for_code_run);
    
    for row_index: start_row..end_row {
        row := row_table[row_index];
        // if row.size == 0 continue;

        baseline := (r.h + r.y) - (line_height*(row_index+1)) + top_offset;
        left := r.x;
        
        size := row.size;
        if context.draw_invisible_characters {
            size += 1; // Just for the invisible line end character
        }
        Clamp(*size, 0, buffer.count); // @Memory Maybe we won't overflow because the we allocate more memory than the buffer.count
        assert(size <= buffer.count && buffer.count < buffer.allocated);
        
        line_text := slice(buffer, row.end - row.size, size);
        generate_quads_for_code_run(buffer, xx (left - left_offset), xx baseline, line_text);
    }
    
    draw_code_run(buffer);
}

//text_glyphs_cache: Table(string, [..] *Simp.Glyph_Data);

generate_quads_for_code_run :: (buffer: *Buffer, x: s64, y: s64, text: string) {
    // assert(text.count > 0);
    if !text.count return;
    
    // @Speed Maybe we can cache the text, so we don't have to generate the quads every time!
    /*
    found, glyphs := table_find(*text_glyphs_cache, text);
    if found {
        array_reset_keeping_memory(*r_font.temporary_glyphs);
        array_copy(*r_font.temporary_glyphs, glyphs);
    } else {
        Simp.prepare_text(r_font, text, 0);
        
        glyphs: [..] *Simp.Glyph_Data;
        array_copy(*glyphs, r_font.temporary_glyphs);
        
        table_add(*text_glyphs_cache, copy_string(text), glyphs);
    }
    */
    
    Simp.prepare_text(r_font, text, 0);
    Simp.generate_quads_for_prepared_text(r_font, x, y, 0);
    
    t := text;
    index := t.data - buffer.data;
    
    invisible_char_color := map_color_to_vec4(.TEXT_INVISIBLE_CHARACTER);
    
    for quad: r_font.current_quads {
        color := map_color_to_vec4(buffer.colors[index]);
        if draw_invisible_characters && is_invisible_but_drawable(buffer.data[index]) {
            color = invisible_char_color;
        }
        
        array_add(*buffer.quads_for_code_run, .{quad, color});
        
        t.data += 1 + trailingBytesForUTF8[t[0]];
        index = t.data - buffer.data;
    }
}

draw_code_run :: (buffer: *Buffer) {
    #import "GL";

    draw_letter_quad :: inline (quad: Simp.Font_Quad, color: Vector4) {
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

    Simp.set_shader_for_text();
    Simp.immediate_begin();
    Simp.CheckInit();
    
    glBlendFunc(GL_SRC1_COLOR, GL_ONE_MINUS_SRC1_COLOR);
    glEnable(GL_BLEND);
    glTexParameterf(GL_TEXTURE_2D, GL_TEXTURE_MAX_ANISOTROPY_EXT, 0);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);

    last_texture: s64 = -1;

    code_quads := buffer.quads_for_code_run;

    for code_quad, i: code_quads {
        quad := code_quad.quad;
        color := code_quad.color;

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

        inline draw_letter_quad(quad, color);
    }

    Simp.immediate_flush();

    glDisable(GL_BLEND);
}

draw_generated_quads :: (buffer: *Buffer, text: string, font: *Simp.Dynamic_Font, $draw_invisible_chars := false) {
    // #import "GL"(DUMP_GL_ERRORS=true, ENABLE_ALL_EXTENSIONS=false, DEFAULT_MSAA=4)();
    #import "GL";

    draw_letter_quad :: inline (quad: Simp.Font_Quad, color: Vector4) {
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

    Simp.CheckInit();
    //if state.current_shader Simp.immediate_flush();
    Simp.set_shader_for_text();
    //glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);
    glBlendFunc(GL_SRC1_COLOR, GL_ONE_MINUS_SRC1_COLOR);
    glEnable(GL_BLEND);
    glTexParameterf(GL_TEXTURE_2D, GL_TEXTURE_MAX_ANISOTROPY_EXT, 0);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);

    quads := font.current_quads;

    last_texture: s64 = -1;

    t := text;
    index := t.data - buffer.data;
    
    #if draw_invisible_chars {
        invisible_char_color := map_color_to_vec4(.TEXT_INVISIBLE_CHARACTER);
    }

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
        
        #if draw_invisible_chars {
            if buffer.data[index] == #char " " {
                color = invisible_char_color;
            }
        }
        
        inline draw_letter_quad(quad, color);

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
    if mx < 0 || my < 0 || !ok return;
    
    approx_row_index := cast(s64)floor((my + editor.top_offset) / fnt_get_line_height());
    if approx_row_index >= buffer.row_table.count return;
    
    rs := get_row_as_string(buffer, approx_row_index);
    //log("> '%'\n", rs);
    ch := r_font.character_height;
    bottom := (r.h+r.y) - fnt_get_line_height(approx_row_index+1) + editor.top_offset;
    Simp.immediate_quad(r.x, bottom, r.x + r.w, bottom + ch, Vector4.{.1, .49, 1.0, .1});
    
    left := cast(float32)r.x;
    while rs.count {
        if cast(float, mx + editor.left_offset) <= left break;
        cw := Simp.get_character_width_in_pixels(r_font, rs.data, .LEFT_JUSTIFIED);
        left += cw;
        bytes := 1 + trailingBytesForUTF8[rs[0]];
        rs = advance(rs, bytes);
    }
    if rs {
        //log(">> '%'\n", string.{count=1 + trailingBytesForUTF8[rs[0]], data=rs.data});
    } else {
        // We on the line separator character (after the last character of the row)
    }
    
    //log("r: %\n", r.x);
    left = left - editor.left_offset;
    Simp.immediate_quad(left, bottom, left + r_font.em_width, bottom + ch, Vector4.{.5, .15, .21, .9});
}

draw_quad :: (p0: Vector2, p1: Vector2, p2: Vector2, p3: Vector2, color: Vector4) {
    Simp.immediate_quad(p0, p1, p2, p3, color);  //  @Speed
}

draw_quad :: (r: Rect, color: Vector4) {
    p0, p1, p2, p3 := get_quad(r);
    draw_quad(p0, p1, p2, p3, color);
}

draw_quad_with_radius :: (r: Rect, color: Vector4, radius := 0.0) {
    Simp.set_shader_for_rect();
    Simp.immediate_quad_with_radius(r.x, r.y, r.x + r.w, r.y + r.h, color, radius=radius);
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