// The r: Rect's h (height) param represents the maximum height of the list.
list_input :: (r: Rect, ui_id: u64, font: *Simp.Dynamic_Font, options: []List_Input.Option = .[], theme := List_Input.DEFAULT_THEME) -> *List_Input {
//    timer := seconds_since_init();
//    defer PrintDev("[%] %ms\n", #procedure_name(), formatFloat((seconds_since_init()-timer)*1000, trailing_width=4));
    
    input, found := table_find(*inputs, ui_id);
    if !found {
        input = New(List_Input);
        table_add(*inputs, ui_id, input);
    }

    using input;

    // if new_options.count {
    //     replace_options(input, new_options);
    // }

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
    Simp.set_shader_for_color(true);
    
    weight :: 2.0;
    Simp.immediate_quad(r.x-weight, b-weight, r.x + r.w + weight, t + weight, theme.border_color); // border
    
    Simp.immediate_quad(r.x, b, r.x + r.w, t, theme.bg_color);
    
    if !options.count {
        left   := r.x + left_pad * 1.5;
        bottom := b + ch*.5; // center
        label(xx left, xx bottom, "No items...", font, theme.placeholder_color);

        return input;
    }

    rect := get_rect(r.x, b+5.0, r.w, t-b);
    push_scissor(rect);
    defer pop_scissor();

    y += scroll_value;

    max_scroll_value := options.count*y_off;

    if selected_index != -1 {
        i := selected_index;
        target := y - (i*y_off);
        bottom_threshold := b + ch*3.0;

        if moved {
            if target < bottom_threshold {
                _anim.active = true;
                _anim.start  = scroll_value;
                _anim.target = scroll_value + (bottom_threshold - target);
                _anim.duration = 0.05;
                _anim.elapsed = 0.0;
            } else if target >= t {
                _anim.active = true;
                _anim.start  = scroll_value;
                _anim.target = scroll_value - (target + y_off - t);
                _anim.duration = 0.05;
                _anim.elapsed = 0.0;
            }
        }

        if _anim.active {
            _anim.elapsed += xx current_dt;
            d := clamp(_anim.elapsed / _anim.duration, 0.0, 1.0);
            if d == 1.0 then _anim.active = false;

            val := lerp(_anim.start, _anim.target, d);
            // ll("> % / % ; elapsed: % ; d: %\n", val, _anim.target, _anim.elapsed, d);

            scroll_value = val;
        }
        
        Clamp(*scroll_value, 0.0, max_scroll_value);
    }

    for opt, i: options {
        defer y -= y_off;
        
        outside := y < b || y >= t;
        if outside continue;

        Simp.set_shader_for_color(true);
        // Simp.immediate_quad(r.x, y-ch*.5+1.0, x + r.w, y-ch*.5, .{1.0,1.0,1.0,.07}); // bottom border
        color := theme.fg_color;
        if i == selected_index {
            Simp.immediate_quad(r.x, y+ch*1.5, x + r.w, y-ch*.5, theme.current_item_bg_color);
            color = theme.current_item_fg_color;
        }
        
        label(xx x, xx (y+ch*.25), opt.label, font, color);
    }

    return input;
}

#scope_file

_current: float64 = 0.0;
_target: float64 = 1131.150024;
_dt: float64 = 0.0;
_time: float64 = 0.0;

_anim: Anim;

Anim :: struct {
    active: bool;

    start: float;
    target: float;

    duration: float;
    elapsed: float;
}

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

// replace_options :: (using i: *List_Input, new_options: [] List_Input.Option) {
//     array_reset_keeping_memory(*options);

//     for new_opt: new_options {
//         opt := array_add(*options);
//         assert(!!new_opt.label);
//         modify_string(*opt.label, new_opt.label);
//     }
// }

inputs: Table(u64, *List_Input);

#scope_export

List_Input :: struct {
    scroll_value: float;
    entered := false;
    selected_index := -1;

    active_t: float;

    Option :: struct (T: Type) {
        label: string;
        ref: *T;
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