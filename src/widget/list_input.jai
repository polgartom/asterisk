// The r: Rect's h (height) param represents the maximum height of the list.
list_input :: (r: Rect, ui_id: u64, font: *Simp.Dynamic_Font, options: []List_Input.Option = .[]) -> *List_Input {
    timer := seconds_since_init();
    defer PrintDev("[%] %ms\n", #procedure_name(), formatFloat((seconds_since_init()-timer)*1000, trailing_width=4));
    
    input, found := table_find(*inputs, ui_id);
    if !found {
        input = New(List_Input);
        table_add(*inputs, ui_id, input);
    }

    using input;

    // if new_options.count {
    //     replace_options(input, new_options);
    // }

    entered = false;
    for event: events_to_handle_this_frame_for_widgets {
        if event.type == .KEYBOARD {
            key := event.key_code;
            using Key_Code;
            if event.key_pressed {
                if key == {
                    case ARROW_UP;   move_to_prev_option(input, options);
                    case ARROW_DOWN; move_to_next_option(input, options);
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
    y := t - y_pad-ch*.75;
    y_off := ch * 2.0;

    expected_bottom_with_options := t - (options.count+1) * y_off; // +1 because we keep a little bit padding on bottom
    b := expected_bottom_with_options;

    if b <= min_bottom {
        b = min_bottom;
    }
    
    // PrintDev("[%]: expected_height: % b: % ; overflow: %", #procedure_name(), expected_height, b, expected_height <= b);

    Simp.set_shader_for_color(true);
    Simp.immediate_quad(r.x, b, r.x + r.w, t, #run hex_to_vec4(0x1c2d29ff));

    if !options.count {
        left   := r.x + left_pad * 1.5;
        bottom := b + ch*.5; // center
        label(xx left, xx bottom, "No items...", font, .{.5,.5,.5,1.0});

        return input;
    }

    rect := get_rect(r.x, b+5.0, r.w, t-b);
    push_scissor(rect);
    defer pop_scissor();

    y += scroll_value;

    if selected_index != -1 {
        i := selected_index;
        vy := y - (i*y_off);
        if vy < b + ch {
            scroll_value += y_off;
        } else if vy >= t {
            scroll_value -= y_off;
        }
        
        Clamp(*scroll_value, 0.0, options.count*y_off);
    }

    for opt, i: options {
        defer y -= y_off;
        // if y < b || y >= t continue; // We should filter out the options that are not visible (overflowed) before we render. @Incomplete

        Simp.set_shader_for_color(true);
        Simp.immediate_quad(r.x, y-ch*.5+1.0, x + r.w, y-ch*.5, .{1.0,1.0,1.0,.07});

        if i == selected_index {
            Simp.immediate_quad(r.x, y+ch*1.5, x + r.w, y-ch*.5, #run hex_to_vec4(0x24_33_33_ff));
            
            label(xx (x+2), xx ((y+ch*.25)-2.5), opt.label, font, .{0.0,0.0,0.0,.4}); // shadow
            label(xx x, xx (y+ch*.25), opt.label, font, .{1.0,1.0,1.0,.5});
        } else {
            label(xx x, xx (y+ch*.25), opt.label, font, .{1.0,1.0,1.0,.5});
        }

    }

    return input;
}

#scope_file

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
    
    Option :: struct {
        label: string;
    }

}