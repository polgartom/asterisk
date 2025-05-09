#import "POSIX";


sleep_milliseconds :: (milliseconds: s32) {
    nanosleep :: (req: *timespec, rem: *timespec) -> int #foreign libc;

    MILLI_TO_NANO :: 1000000;
    MILLI_TO_SECS :: 1000;

    req: timespec;
    req.tv_sec = milliseconds / MILLI_TO_SECS;
    req.tv_nsec = MILLI_TO_NANO * (milliseconds % MILLI_TO_SECS);
    nanosleep(*req, null);
}

set_working_directory :: (s: string) -> bool {
    chdir :: (s: *u8) -> s32 #foreign libc;
    chdir_result := chdir(temp_c_string(s));
    return chdir_result == 0;
}

exit :: (status: s32) {
    // @Incomplete This would perform a series of C library termination procedures before ending the process.
    //  There's quick_exit, _Exit, etc. that perform minimal C lib procedures, but our goal will be to just
    // not call this version since we'll be avoiding the CRT.

    // @Incomplete: We lack a atexit() handlers, so any dynamic library that registers such procedure that is
    // supposed to execute after exit() call, won't be called.

    syscall_exit :: (syscall_number: u32, exit_code: s32) #expand {
        #if CPU == .X64 {
            #asm SYSCALL_SYSRET {
                mov.q nr: gpr === a, syscall_number;
                mov.d st: gpr === di, exit_code;
                syscall o0:, o1:, nr, st;
            }
        } else {
            syscall :: (__sysno: s64, __args: ..Any) -> s64 #foreign libc;
            syscall(syscall_number, exit_code);
        }
    }

    #if OS == {
        case .LINUX;
            syscall_exit(SYS_exit_group, status);
        case .ANDROID;
            syscall_exit(SYS_exit_group, status);
        case .MACOS;
            // SYSCALL_UNIX_BASE would not be necessary if we call libc’s syscall(), because it applies it automatically. But it doesn’t hurt either.
            syscall_exit(SYSCALL_UNIX_BASE | SYS_exit, status);
        case;
            libc_exit :: (status: s32) #foreign libc "exit";
            libc_exit(status);
    }
}

#scope_file

libc :: #system_library "libc";
