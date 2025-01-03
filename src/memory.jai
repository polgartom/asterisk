// Remove this @Cleanup
SlowMemcpy :: (destination: *void, source: *void, count: s64) #expand {
    d := cast(*u8) destination;  s := cast(*u8) source;

    #if 1 {
        c_memmove(destination, source, xx count);
    } else {
        overlapping := destination > source && destination < source + count;
        if !overlapping {
            for 0 .. count - 1
                d[it] = s[it];
        } else {
            for #v2 < count - 1 .. 0
                d[it] = s[it];
        }
    }
}

ZeroMemory :: (ptr: *void, size: s64) #expand {
    memset(ptr, 0, size);
}

Align :: inline (n: $T, $$ PAGE_SIZE: s64) -> T #expand {
    return (n + PAGE_SIZE-1) & ~(PAGE_SIZE-1);
}

c_malloc  :: (size: u64) -> *void                               #foreign crt "malloc";
c_free    :: (memory: *void)                                    #foreign crt "free";
c_realloc :: (memory: *void, size: u64) -> *void                #foreign crt "realloc";
c_memmove :: (dest: *void, src: *void, count: u64) -> *void     #foreign crt "memmove";