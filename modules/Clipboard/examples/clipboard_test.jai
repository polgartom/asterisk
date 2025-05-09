Clipboard :: #import "Clipboard";

copy_screen_shot_to_clipboard :: () {
    async_read := Simp.pixel_read_begin(null, .RGB8);
    bitmap     := Simp.pixel_read_end(async_read);
    defer Simp.deinit(*bitmap);

    Clipboard.os_clipboard_set_bitmap(bitmap.width, bitmap.height, bitmap.data.data, 3);
}

main :: () {
    init_demo_app("Clipboard Demo");

    // run an event loop since X11 requires apps to stay alive to respond to selection requests.
    quit := false;
    fade := 1.0;
    decrement_fade := 0.01;
    report_text: string;

    text_to_copy_to_clipboard := copy_string("Hello, Sailor!");
    while !quit {
        update_window_events();

        for events_this_frame {
            if it.type == .QUIT then quit = true;

            if it.type == .KEYBOARD {
                if it.key_pressed == 0 continue;

                if it.key_code == xx #char "T" {
                    free(report_text);
                    report_text = sprint("'%' Copied to clipboard.", text_to_copy_to_clipboard);
                    Clipboard.os_clipboard_set_text(text_to_copy_to_clipboard);
                    fade = 1.0;
                    decrement_fade = 0.01;
                } else if it.key_code == xx #char "I" {
                    free(report_text);
                    report_text = sprint("Screenshot copied to clipboard.");
                    copy_screen_shot_to_clipboard();
                    fade = 1.0;
                    decrement_fade = 0.01;
                } else if it.key_code == xx #char "P" {
                    free(report_text);
                    report_text = sprint("Text in clipboard: %", Clipboard.os_clipboard_get_text());
                    fade = 1.0;
                    decrement_fade = 0.001;
                }
            }
        }

        resizes := get_window_resizes();  // We might want to collapse all resizes down to 1 for each window, but we don't currently do this, I think.
        for record: resizes {
            // @Bug: Calling update_window will make the render buffer stretch or shrink when resizing -Veeq7
            //Simp.update_window(the_window);
        }

        start_frame();
        fade -= decrement_fade;
        if fade < 0 then fade = 0;

        draw_text(the_font, .{1, 1, 1, fade}, 20, 20 + FONT_HEIGHT*3, report_text);
        draw_text(the_font, .{1, 1, 1, 1},    20, 20 + FONT_HEIGHT*2, "Press 'P' to print the text currently in the clipboard.");
        draw_text(the_font, .{1, 1, 1, 1},    20, 20 + FONT_HEIGHT*1, "Press 'I' to copy a screenshot to the clipboard.");
        draw_text(the_font, .{1, 1, 1, 1},    20, 20 + FONT_HEIGHT*0, "Press 'T' to copy '%' to the clipboard.", text_to_copy_to_clipboard);
        finish_frame();
    }

}

#scope_file

#import "Basic";
#import "Math";

#import "Window_Creation";
#import "Input";
Simp :: #import "Simp";

#import "String";
#import "System";

init_demo_app :: (title: string) {
    set_working_directory(path_strip_filename(get_path_of_running_executable()));

    the_window = create_window(WINDOW_WIDTH, WINDOW_HEIGHT, title);
    Simp.set_render_target(the_window);

    the_font = Simp.get_font_at_size(".", "Skytree_by_MONTAGNA.ttf", FONT_HEIGHT);
    assert(the_font != null);
}

start_frame :: () {
    while true {
        if elapsed_time >= TICK_PERIOD {
            elapsed_time -= TICK_PERIOD;
            break;
        }

        now := seconds_since_init();
        if last_time dt = cast(float) (now - last_time);
        last_time = now;

        elapsed_time += dt;
        sleep_milliseconds(2);
    }

    reset_temporary_storage();

    Simp.clear_render_target(0, 0, 0, 1);
}

finish_frame :: () {
    Simp.swap_buffers(the_window);
}

WINDOW_WIDTH  :: 1280;
WINDOW_HEIGHT :: 720;
FONT_HEIGHT   :: 32;
fps_time      := 0.0;
last_time:    float64;
elapsed_time: float64;
TICK_PERIOD : float64 : 1.0/60.0; // time between game updates
dt: float;
the_window: Window_Type;
the_font: *Simp.Dynamic_Font;

draw_text :: (font: *Simp.Dynamic_Font, color: Vector4, x: int, y: int, fmt: string, args: .. Any) {
    assert(font != null);
    builder: String_Builder;

    print_to_builder(*builder, fmt, ..args);
    text := builder_to_string(*builder);
    defer free(text);

    Simp.draw_text(font, x, y, text, color);
}
