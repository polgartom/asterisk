//
// This is copied from the Simp demo, but, we use a Keymap to do stuff!
//

the_keymap: Keymap;

//
// Here are some variables that we will manipulate via the keymap procedures.
//

should_quit := false;  // Should we quit the program?

string_to_print := "";
square_position:  Vector2;
background_color := Vector3.{.05, .05, .05};

square_size_current := 1.0;
square_growing := false;


ROTATION_SPEED_MAX :: 3.5;       // Number of rotations per second.
rotation_speed_desired := 0.0;
rotation_speed_current := 0.0;
theta_current          := 0.0;   // In radians.

//
// Here are procedures to do various simple things, that you can call
// from the keymap file.
//

Quit :: () {
    should_quit = true;
}

BackgroundColor1 :: () {
    background_color = .{.25, .01, .007};
}

BackgroundColor2 :: () {
    background_color = .{.025, .22, .2};
}

BackgroundColor3 :: () {
    background_color = .{.17, .007, .2};
}

PrintFrobozz :: () {
    string_to_print = "frobozz";
}

PrintCapitalFrobozz :: () {
    string_to_print = "Frobozz";
}

PrintExtremeFrobozz :: () {
    string_to_print = "FROBOZZ!";
}

PrintCrazyFrobozz :: () {
    string_to_print = "FroBoZZ!??";
}

GrowSquareWhileHeld :: (pressed: bool) {
    square_growing = pressed;
}

RotateMoreCounterClockwise :: () {
    rotation_speed_desired += 0.5;
    Clamp(*rotation_speed_desired, -ROTATION_SPEED_MAX, ROTATION_SPEED_MAX);
}

RotateMoreClockwise :: () {
    rotation_speed_desired -= 0.5;
    Clamp(*rotation_speed_desired, -ROTATION_SPEED_MAX, ROTATION_SPEED_MAX);
}

StopRotation :: () {
    rotation_speed_desired = 0;
}

register_keymap_procedures :: () {
    //
    // At startup, we call this routine so that the Keymap file
    // will know which procedures can be found.
    //
    // We call 'add_proc' once for each procedure we want to register.
    // 'add_proc' wants both a string name and the procedure to call.
    // Here we pass both explicitly, and it's kind of redundant.
    // You could generate this with a metaprogram or use a macro...
    //

    k := *the_keymap;

    // Explicit version:

    add_proc(k, "BackgroundColor1", BackgroundColor1);
    add_proc(k, "BackgroundColor2", BackgroundColor2);
    add_proc(k, "BackgroundColor3", BackgroundColor3);
    
    add_proc(k, "Quit",             Quit);

    // You could use a macro, to make this more terse:

    Add :: (ident: Code) #expand {
        add_proc(k, #run get_identifier_name(ident), #insert ident);
    }

    Add(PrintFrobozz);
    Add(PrintCapitalFrobozz);
    Add(PrintExtremeFrobozz);
    Add(PrintCrazyFrobozz);

    Add(GrowSquareWhileHeld);

    Add(RotateMoreCounterClockwise);
    Add(RotateMoreClockwise);
    Add(StopRotation);

    //
    // As a third option, you could tag your command procedures with notes
    // and have a metaprogram collect them and automatically generate the
    // registration code.
    //


    //
    // The Keymap also has a way of registering arbitrary command strings in the keymap file,
    // that you can pass to whatever command processor you like. Set keymap.command_string_proc,
    // and that procedure will be called with each command string when its key is pressed.
    //

    k.command_string_proc = the_command_handler;
}


//
// For now our command handler is dumb and just
// changes the displayed text on the screen.
//

displayed_command_string: string;

the_command_handler :: (s: string) {
    free(displayed_command_string);

    displayed_command_string = sprint("COMMAND: %", s);  // So that we can free it.
    string_to_print = displayed_command_string;
}


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

    load_from_file(*the_keymap, "single_keymap", "single_keymap.keymap", false);

    // Let's save it back out, to exercise the Keymap save code.
    // Pretend that this represents user-remappable keys, the user just changed them,
    // and we are saving it out...
    save_to_file(*the_keymap, "single_keymap.user.keymap");
    
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

        for Input.events_this_frame {
            if it.type == .QUIT then should_quit = true;

            keymap_handle_event(the_keymap, it);
        }

        draw_one_frame();

        sleep_milliseconds(10);
    }
}

update_square_size :: (dt: float) {
    if square_growing {
        square_size_current += dt * 0.9;
    } else {
        // Shrink faster than grow!
        square_size_current -= dt * 2.5;
    }

    Clamp(*square_size_current, 1, 3);
}

update_square_rotation :: (dt: float) {
    dtheta_dt := 1.0;
    if rotation_speed_desired < rotation_speed_current {
        rotation_speed_current -= dtheta_dt * dt;
        if rotation_speed_current < rotation_speed_desired  rotation_speed_current = rotation_speed_desired;
    } else {
        rotation_speed_current += dtheta_dt * dt;
        if rotation_speed_current > rotation_speed_desired  rotation_speed_current = rotation_speed_desired;
    }

    theta_current += rotation_speed_current * TAU * dt;

    // Wrap the angle so we don't get an indefinitely huge value.
    if theta_current > TAU  theta_current -= TAU;
    if theta_current < 0    theta_current += TAU;
}

draw_one_frame :: () {
    Simp.update_window(my_window);
    Simp.clear_render_target(background_color.x, background_color.y, background_color.z, 1);

    Simp.set_shader_for_color();

    time := seconds_since_init();
    dt := cast(float)(time - last_time);
    Clamp(*dt, 0, 0.1);
    last_time = time;

    // A rotating square, controlled by the parameters that we adjust via the keymap.
    {
        update_square_size(dt);
        update_square_rotation(dt);

        b := (window_height / 10.0) * square_size_current;

        p: Vector2;
        p.x = cast(float)(window_width  / 2);
        p.y = cast(float)(window_height / 2);

        theta := theta_current;

        ct := cos(theta);
        st := sin(theta);

        w := Vector2.{b*ct, b*st};
        h := Vector2.{b*st, -b*ct};

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
        text := string_to_print;
        text_width := Simp.prepare_text(my_font, text);

        text_x := (window_width - text_width) / 2;
        text_y := window_height/2 - my_font.character_height/4;

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


get_identifier_name :: (name: Code) -> string {
    #import "Compiler";

    // This is just to help with the Add macro above.

    node := compiler_get_nodes(name);
    if node.kind != .IDENT {
        compiler_report("Not an identifier.", make_location(node));
        return "";
    }

    ident := cast(*Code_Ident) node;
    return ident.name;
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
