//
// This is a demo of how to use the Keymap_Set. It's the 2nd in this series; if you haven't yet
// looked at single_keymap.jai, start there; this file is for when you are done with that.
//

the_set: Keymap_Set;

// A Keymap_Set groups together Keymaps that can be dynamically enabled and disabled at runtime
// based on what mode you're in (application main, menu, editor, profiling, etc).

// When we add our keymaps, we store the pointers here so that they're easy to disable and
// re-enable:

keymap_editor:    *Keymap;
keymap_profiling: *Keymap;
keymap_main:      *Keymap;

//
// Here are some variables that we will manipulate via the keymap procedures.
//

should_quit := false;

square_position:  Vector2;

square_size_current := 1.0;
square_growing_time := 0.0;

Program_Mode :: enum u8 {
    MAIN;
    EDITOR;
    PROFILING;
};

mode := Program_Mode.MAIN;

//
// Here are procedures you can call from the keymap file.
//

GoToModeMain :: () {
    mode = .MAIN;
}

GoToModeEditor :: () {
    mode = .EDITOR;
}

GoToModeProfiling :: () {
    mode = .PROFILING;
}

Quit :: () {
    should_quit = true;
}

// Called only when in MAIN mode (because that is the only time its binding is not overshadowed):
PumpSquareSize :: () {
    square_growing_time = .15;
}

// Called only when in EDITOR mode:
EnterPressedEditor :: () {
    num_enter_presses += 1;
}

// Called only when in PROFILING mode:
EnterPressedProfiling :: () {
    profiling_text_position += 1;
    if profiling_text_position > PROFILING_TEXT_POSITION_MAX  profiling_text_position = 0;
}

//
// Variables for the Editor:
//

num_enter_presses := 0;

//
// Variables for Profiling:
//

profiling_text_position := 0;
PROFILING_TEXT_POSITION_MAX :: 5;

//
// Code of our main program:
//

register_keymap_procedures :: () {
    //
    // Currently, when using a Keymap_Set, the Keymaps that you add first
    // take priority over anything later, when multiple Keymaps have bindings
    // for the same command. Currently there is no dynamic reordering.
    // We'll see if we need that...
    //
    
    keymap_editor = add_keymap(*the_set, "Editor");

    add_proc(keymap_editor, "EnterPressed", EnterPressedEditor);

    keymap_profiling = add_keymap(*the_set, "Profiling");
    
    add_proc(keymap_profiling, "EnterPressed", EnterPressedProfiling);

    k := add_keymap(*the_set, "Main");

    add_proc(k, "GoToModeMain",      GoToModeMain);
    add_proc(k, "GoToModeEditor",    GoToModeEditor);
    add_proc(k, "GoToModeProfiling", GoToModeProfiling);
    add_proc(k, "PumpSquareSize",    PumpSquareSize);
    add_proc(k, "Quit",              Quit);
}


//
// For now our command handler is dumb and just
// changes the displayed text on the screen.
//

my_window: Window_Type;
window_width  : s32 = 1920;
window_height : s32 = 1080;

render_width  : s32 = 1920;
render_height : s32 = 1080;

main :: () {
    #if OS == .WINDOWS {
        Windows :: #import "Windows";
        Windows.SetProcessDPIAware();

        // Windows is very bad at thread-switching by default unless you do this. Sad.
        Windows.timeBeginPeriod(1);
    }

    my_window = create_window(window_width, window_height, "A Window");

    Simp.set_render_target(my_window);

    path := path_strip_filename(get_path_of_running_executable());
    set_working_directory(path);
    my_init_fonts();

    register_keymap_procedures();

    load_from_file(*the_set, "keymap_set", "keymap_set.keymap", false);

    // Let's save it back out, to exercise the Keymap save code.
    // Pretend that this represents user-remappable keys, the user just changed them,
    // and we are saving it out...
    save_to_file(*the_set, "keymap_set.user.keymap");

    //
    // Render the main loop and do stuff.
    //
    while !should_quit {
        Input.update_window_events();

        for Input.get_window_resizes() {
            Simp.update_window(it.window);

            if it.window == my_window {
                should_reinit := (it.width != window_width) || (it.height != window_height);

                window_width  = it.width;
                window_height = it.height;
                render_width  = window_width;
                render_height = window_height;

                if should_reinit my_init_fonts();  // Resize the font for the new window size.
            }
        }

        {
            //
            // Enable or disable Keymaps depending on which mode we're in.
            //

            enable(*the_set, keymap_editor,    mode == .EDITOR);
            enable(*the_set, keymap_profiling, mode == .PROFILING);

            // We leave Main enabled at all times (Keymaps default to enabled),
            // because that has the bindings to switch between modes!
        }
        
        for Input.events_this_frame {
            if it.type == .QUIT then should_quit = true;
            handle_event(*the_set, it);
        }

        draw_one_frame();

        sleep_milliseconds(10);
    }
}

update_square_size :: (dt: float) {
    if square_growing_time > 0 {
        square_size_current += dt * 7.9;
        square_growing_time -= dt;
    } else {
        // Shrink faster than grow!
        square_size_current -= dt * 1.8;
    }

    Clamp(*square_size_current, 1, 5);
}

draw_one_frame :: () {
    background_color: Vector3;
    text := "(mode uninitialized)";

    enter_presses := 0;
    
    if #complete mode == {
        case .MAIN;
            background_color = .{.25, .01, .007};
            text = "Main Mode";
        case .EDITOR;
            background_color = .{.025, .22, .2};
            text = tprint("Editor (enter has been pressed % time%).", num_enter_presses, ifx num_enter_presses != 1 then "s");
        
        case .PROFILING;
            background_color = .{.17, .007, .2};
            text = "Profiling...";
    }

    Simp.update_window(my_window);
    Simp.clear_render_target(background_color.x, background_color.y, background_color.z, 1);

    Simp.set_shader_for_color();

    time := seconds_since_init();
    dt := cast(float)(time - last_time);
    Clamp(*dt, 0, 0.1);
    last_time = time;

    // This time, the square doesn't spin (slightly less code for the example!)
    {
        update_square_size(dt);

        b := (window_height / 10.0) * square_size_current;

        p: Vector2;
        p.x = cast(float)(window_width  / 2);
        p.y = cast(float)(window_height / 2);

        w := Vector2.{b, 0};
        h := Vector2.{0, b};

        p0 := p - w - h;
        p1 := p + w - h;
        p2 := p + w + h;
        p3 := p - w + h;

        a :: 1.0;
        c0 := Vector4.{1, 0, 0, a};
        c1 := Vector4.{0, 1, 0, a};
        c2 := Vector4.{0, 0, 1, a};
        c3 := Vector4.{1, 1, 1, a};

        Simp.immediate_quad(p0, p1, p2, p3, c0, c1, c2, c3);
    }

    // Draw some text.
    {
        text_width := Simp.prepare_text(my_font, text);

        text_x := (window_width - text_width) / 2;
        text_y := window_height/2 - my_font.character_height/4;

        if mode == .PROFILING {
            text_y -= profiling_text_position * my_font.default_line_spacing;
        }
        
        theta := cast(float) fmod_cycling(time*3, TAU);
        color: Vector4;
        color.x = cos(theta)*.5+.5;
        Clamp(*color.x, 0, 1);
        color.y = 1;
        color.z = sin(theta)*.5+.5;
        Clamp(*color.z, 0, 1);
        color.w = 1;

        Simp.draw_prepared_text(my_font, text_x, text_y, color);
    }

    Simp.swap_buffers(my_window);
}

my_init_fonts :: () {
    pixel_height := window_height / 24;

    // @Cleanup: Don't have path + name be separate.
    my_font = Simp.get_font_at_size(".", "OpenSans-BoldItalic.ttf", pixel_height);
    assert(my_font != null);
}

my_font: *Simp.Dynamic_Font;
last_time: float64;


Simp  :: #import "Simp";
Input :: #import "Input";

#import "Window_Creation";

#import "Basic";
#import "Math";
#import "System";  // For get_path_of_running_executable. @Cleanup.
#import "String";  // For path_strip_filename. @Cleanup.
#import "Keymap";
