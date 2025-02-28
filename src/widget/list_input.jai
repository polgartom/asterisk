list_input :: (r: Rect, ui_id: u64, font: *Simp.Dynamic_Font, new_options: [] List_Input.Option = .[]) -> *List_Input {
    timer := seconds_since_init();
    defer PrintDev("[%] %ms\n", #procedure_name(), formatFloat((seconds_since_init()-timer)*1000, trailing_width=4));
    
    input, found := table_find(*inputs, ui_id);
    if !found {
        input = New(List_Input);
        table_add(*inputs, ui_id, input);
    }

    using input;

    if new_options.count {
        replace_options(input, new_options);
    }

    entered = false;
    for event: events_to_handle_this_frame {
        if event.type == .KEYBOARD {
            key := event.key_code;
            using Key_Code;
            if event.key_pressed {
                if key == {
                    case ARROW_UP;   move_to_prev_option(input);
                    case ARROW_DOWN; move_to_next_option(input);
                    case ENTER;      entered = true;
                }
            }
        }
    }

    left_pad := 5.0;
    pad := 0.0;
    ch  := font.character_height;
    b   := r.y - pad - r.h*1.5*2.0;
    t   := r.y - pad;

    Simp.set_shader_for_color(true);
    Simp.immediate_quad(r.x, b, r.x + r.w, t, #run hex_to_vec4(0x382d38ff));

    if (options.count) {
        rect := get_rect(r.x, b+5.0, r.w, t-b);

        push_scissor(rect);
        defer pop_scissor();

        x_pad := left_pad;
        y_pad := ch;

        x := r.x + x_pad;
        y := t - y_pad-ch*.75;
        y_off := ch * 2.0;

        y += scroll_value;

        if selected_option_index != -1 {
            i := selected_option_index;
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
            // if y < b || y >= t continue;

            Simp.set_shader_for_color(true);
            Simp.immediate_quad(r.x, y-ch*.5+1.0, x + r.w, y-ch*.5, .{1.0,1.0,1.0,.07});

            if i == selected_option_index {
                Simp.immediate_quad(r.x, y+ch*1.5, x + r.w, y-ch*.5, #run hex_to_vec4(0x2f262fff));
            }

            label(xx x, xx (y+ch*.25), opt.label, font, .{1.0,1.0,1.0,.5});
        }

    } else {
        left   := r.x + left_pad * 1.5;
        bottom := t - (r.h*1.5*2.0*0.5) - ch*.3; // center
        label(xx left, xx bottom, "No items ...", font, .{.5,.5,.5,1.0});
    }

    return input;
}

handle_list_input_event :: (event: Event) {
    array_add(*events_to_handle_this_frame, event);
}

clear_list_input_events :: () {
    array_reset_keeping_memory(*events_to_handle_this_frame);
}

#scope_file

move_to_next_option :: (using i: *List_Input) {
    if !options.count return;
    
    selected_option_index = (selected_option_index + 1) % options.count;
}

move_to_prev_option :: (using i: *List_Input) {
    if !options.count return;
    
    selected_option_index -= 1;

    if selected_option_index < 0 {
        selected_option_index = options.count - 1;
    }
}

replace_options :: (using i: *List_Input, new_options: [] List_Input.Option) {
    array_reset_keeping_memory(*options);

    for new_opt: new_options {
        opt := array_add(*options);
        assert(!!new_opt.label);
        modify_string(*opt.label, new_opt.label);
    }
}

events_to_handle_this_frame: [..] Event;
inputs: Table(u64, *List_Input);

#scope_export

List_Input :: struct {
    scroll_value: float;
    
    entered := false;

    options: [..] Option;
    selected_option_index := -1;
    
    Option :: struct {
        label: string;
    }

}