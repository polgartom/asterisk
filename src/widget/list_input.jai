
// The r: Rect's h (height) param represents the maximum height of the list.
list_input :: (r: Rect, ui_id: u64, options: [] List_Input.Option, font: *Simp.Dynamic_Font, theme := List_Input.DEFAULT_THEME) -> *List_Input {
    
    found, input := table_find(*inputs, ui_id);
    if !found {
        input = New(List_Input);
        table_add(*inputs, ui_id, input);
    }

    using input;

    moved := false;
    entered = false;
    for event: events_to_handle_this_frame_for_widgets {
        if event.type == .KEYBOARD {
            key := event.key_code;
            using Key_Code;
            if event.key_pressed {
                if key == {
                    case ARROW_UP;   move_to_prev_option(input, options); moved = true;
                    case ARROW_DOWN; move_to_next_option(input, options); moved = true;
                    case ENTER;      entered = true;
                }
            }
        }
    }

    left_pad := 5.0;
    pad := 0.0;
    ch  := font.character_height;
    min_bottom := r.y - pad - r.h*1.5*2.0;
    t := r.y - pad;

    x_pad := left_pad;
    y_pad := ch;
    x := r.x + x_pad;
    y := t - y_pad - ch*.55;
    y_off := ch * 2.0;

    expected_bottom_with_options := t - (options.count+1) * y_off; // +1 because we keep a little bit padding on bottom
    b := expected_bottom_with_options;

    if b <= min_bottom {
        b = min_bottom;
    }
    
    // PrintDev("[%]: expected_height: % b: % ; overflow: %", #procedure_name(), expected_height, b, expected_height <= b);

    // Draw the container box
    thickness :: 2.0; // border thickness
    Simp.set_shader_for_rect();
    Simp.immediate_quad_with_radius(r.x-thickness, b-thickness, r.x + r.w + thickness, t + thickness, theme.border_color, radius=r_rect_radius); // border
    Simp.immediate_quad_with_radius(r.x, b, r.x + r.w, t, theme.bg_color, radius=r_rect_radius);
    Simp.immediate_flush();

    if !options.count {
        left   := r.x + left_pad * 1.5;
        bottom := b + ch*.5; // center
        label(xx left, xx bottom, "No items...", font, theme.placeholder_color);

        return input;
    }

    bottom_padding := 5.0;

    rect := make_rect(r.x, b + bottom_padding, r.w, t-b);
    push_scissor(rect);
    defer pop_scissor();

    y += scroll_value;

    max_scroll_value := options.count*y_off;
    
    if selected_index != -1 {
        i := selected_index;
        target := y - (i*y_off);
        top_threshold := t - y_off * 2;

        if moved {
            if target < b + y_off {
                _anim.active = true;
                _anim.start  = scroll_value;
                _anim.target = scroll_value + ((b+y_off*2) - target + y_off);
                _anim.duration = 0.07;
                _anim.started_at = frame_time64;
            } else if target >= top_threshold {
                _anim.active = true;
                _anim.start  = scroll_value;
                _anim.target = scroll_value - (target - top_threshold + y_off);
                _anim.duration = 0.07;
                _anim.started_at = frame_time64;
            }
        }
    }

    if _anim.active {
        using _anim;

        t := (frame_time64 - started_at) / duration;
        t = clamp(t, 0.0, 1.0);
        distance := (target - start);
        v := start + cast(float)(distance * t);

        if t == 1.0 then active = false;

        scroll_value = v;

        redraw_requested = true;
    }

    k := max_scroll_value;
    if k > rect.h then k-=rect.h;
    scroll_value = clamp(scroll_value, 0.0, k + bottom_padding);

    //rendered := 0;

    for opt, i: options {
        defer y -= y_off;
        
        outside := y+y_off < b || y >= t;
        if outside continue;

        //rendered += 1;

        Simp.set_shader_for_color(true);
        Simp.immediate_quad(r.x, y-ch*.5+1.0, x + r.w, y-ch*.5, .{1.0,1.0,1.0,.07}); // bottom border
        
        color := theme.fg_color;
        if i == selected_index {
            Simp.immediate_quad(r.x, y+ch*1.5, x + r.w, y-ch*.5, theme.current_item_bg_color);
            color = theme.current_item_fg_color;
        }
        
        _x: s64 = xx x;
        _y: s64 = xx (y+ch*.25);
        if opt.label_prefix {
            ts := opt.label_prefix_styled;
            if !ts.font_override ts.font_override = font;
            draw_text(_x + ts.x_offset, _y + ts.y_offset, ts);
        }
        
        ts := opt.label_styled;
        if !ts.font_override ts.font_override = font;
        draw_text(_x + ts.x_offset, _y + ts.y_offset, ts);
    }

    //PrintDev("options rendered: %\n", rendered);

    return input;
}

reset_list_input :: (using input: *List_Input) {
    input.scroll_value = 0.0;
    input.selected_index = 0;
}

#scope_file

_anim: Anim;

move_to_next_option :: (using i: *List_Input, options: [] List_Input.Option) {
    if !options.count return;
    
    selected_index = (selected_index + 1) % options.count;
}

move_to_prev_option :: (using i: *List_Input, options: [] List_Input.Option) {
    if !options.count return;
    
    selected_index -= 1;

    if selected_index < 0 {
        selected_index = options.count - 1;
    }
}

inputs: Table(u64, *List_Input);

#scope_export

List_Input :: struct {
    scroll_value: float;
    entered := false;
    selected_index := -1;

    Option :: struct ($T: Type = void) {        
        label_styled: Text_Style;
        label_prefix_styled: Text_Style;
        
        label_for_search: string;
        ref: T;

        priority: s64 = 0; // for sorting
        
        #place label_styled;
            label: string;
        
        #place label_prefix_styled;
            label_prefix: string;
    }

    DEFAULT_THEME :: Theme.{
        fg_color              = .{1.0,1.0,1.0,.5},
        bg_color              = #run hex_to_vec4(0x101520_ff),
        
        border_color          = #run hex_to_vec4(0x10_25_5a_ff),
        current_item_bg_color = #run hex_to_vec4(0x10_25_5a_ff),
        current_item_fg_color = .{1.0,1.0,1.0,.7},
        
        placeholder_color     = .{1.0,1.0,1.0,.5},
    };

    Theme :: struct {
        fg_color:          Vector4;
        bg_color:          Vector4;
        placeholder_color: Vector4;
        
        border_color:      Vector4;
        
        current_item_bg_color: Vector4;
        current_item_fg_color: Vector4;
    }

}