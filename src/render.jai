
swap_buffers :: (window: Window_Type) {
    Simp.swap_buffers(my_window, vsync=false);

    {
        glFinish :: () #foreign;
        
        #if BYPASS_FRAMERATE_LIMIT {
            // https://community.khronos.org/t/swapbuffers-and-synchronization/107667/5
            glFinish(); // @Hacky
        }
    }
}

BYPASS_FRAMERATE_LIMIT :: true;