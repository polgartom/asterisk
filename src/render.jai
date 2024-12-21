
swap_buffers :: (window: Window_Type) {
    // https://community.khronos.org/t/swapbuffers-and-synchronization/107667/5
    
    Simp.swap_buffers(my_window, vsync=false);

    #if OS == .WINDOWS {
        glFinish :: () #foreign;
        if !vsync_on then glFinish();
    }
}

vsync_on := true;