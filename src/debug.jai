show_debug_info := DEBUG;
debug_infos: [..] string;

PrintDev :: (fmt: string, args: .. Any) #expand {
    s := tprint(fmt, ..args);
    array_add(*debug_infos, s); // can we use temporary allocator for dynamic arrays?
} @PrintLike

ll :: (fmt: string, args: .. Any) #expand {
    s := tprint(fmt, ..args);
    print("[%] %", #procedure_name(), s);
} @PrintLike

MeasureProc :: () #expand {
    time := seconds_since_init();
    `defer {
        print("[%/time] %ms\n", #procedure_name(), (seconds_since_init() - time) * 1000);
    };
} @PrintLike