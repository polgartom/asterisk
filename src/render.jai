
swap_buffers :: (window: Window_Type) {
    Simp.swap_buffers(my_window, vsync=false);

    {
        // https://community.khronos.org/t/swapbuffers-and-synchronization/107667/5
        BOOST_THE_FPS_MAGICALLY :: true;
        #if BOOST_THE_FPS_MAGICALLY {
            glFinish :: () #foreign;
            glFinish();
        }
    }
}

should_redraw :: inline () -> bool {
    #if DEBUG return true;

    return redraw_requested && mode == .WIDGET;
}

redraw_requested := true; // @Todo: Use this on WINDOWS and LINUX
