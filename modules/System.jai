Processor_Query_Type :: enum u8 {
    ALL_PHYSICAL;
    ALL_LOGICAL;
    PERFORMANCE_PHYSICAL;
    PERFORMANCE_LOGICAL;
}


// @@ Add to OS/System module?
// Returns a temporary string.
#if OS == .WINDOWS {
    #scope_file

    Windows       :: #import "Windows";
    Utf8          :: #import "Windows_Utf8";
    OS_Error_Code :: Windows.OS_Error_Code;

    #scope_export

    get_username :: () -> string, success:bool {
        UNLEN :: 256;

        buffer : [UNLEN+1]u16;
        count : u32 = xx buffer.count;

        if Windows.GetUserNameW(buffer.data, *count) {
            return Utf8.wide_to_utf8(buffer.data,, Basic.temp), true;
        }

        return "", false;
    }

    // Returns a string that doesn't need to be freed (because it points to system memory)
    get_home_directory :: (username := "") -> string, success: bool {
        if username {
            // @ToDo: Not supported on Windows yet.
            Basic.assert(false, "get_home_directory with a username argument is not yet supported on Windows.\n");  // Why is this in the API then? @Cleanup.
            return "", false;
        }

        name16 := Utf8.utf8_to_wide("USERPROFILE",, Basic.temp);
        result := cast(*u16)Windows._wgetenv(cast(*s16)name16);
        if !result      return "", false;

        return Utf8.wide_to_utf8(result,, Basic.temp), true;
    }

    // Returns a temporary string.
    get_machinename :: () -> string {
        MAX_COMPUTERNAME_LENGTH :: 31;

        buffer : [MAX_COMPUTERNAME_LENGTH + 1]u16;
        count : u32 = xx buffer.count;

        if Windows.GetComputerNameW(buffer.data, *count) {
            return Utf8.wide_to_utf8(buffer.data,, Basic.temp);
        }

        return "";
    }


    get_path_of_running_executable :: () -> string /* Temporary Storage */ {
        buf: [Windows.MAX_PATH] u16;

        my_handle := Windows.GetModuleHandleW(null);
        success   := Windows.GetModuleFileNameW(my_handle, buf.data, Windows.MAX_PATH);

        if success <= 0 {
            // log("get_path_of_running_executable", "Unable to get the filename of the running executable. This is bad!");
            return "";
        } else {
            // @@ Use translate path?
            convert_slashes :: (s: string) {
                for 0..s.count-1 {
                    if s[it] == #char "\\"  s[it] = #char "/";
                }
            }

            exe_name := Utf8.wide_to_utf8(buf.data,, Basic.temp);
            convert_slashes(exe_name);

            return exe_name;
        }
    }

    // Similar to the macOS implementation, the API supports an arbitrary number
    // of performance levels but we only differentiate the highest level and the
    // total. If you need the value more than once, you should cache it in a global.
    get_number_of_processors :: ($type: Processor_Query_Type = .PERFORMANCE_LOGICAL) -> count: s32 {
        PERFORMANCE :: type == .PERFORMANCE_PHYSICAL || type == .PERFORMANCE_LOGICAL;
        PHYSICAL    :: type == .ALL_PHYSICAL         || type == .PERFORMANCE_PHYSICAL;

        #if type == .ALL_LOGICAL {
            siSysInfo : Windows.SYSTEM_INFO;
            Windows.GetNativeSystemInfo(*siSysInfo);
            return cast(s32) siSysInfo.dwNumberOfProcessors;
        } else {
            Bit_Operations :: #import "Bit_Operations";
            Basic.auto_release_temp(); // For cpu_information_buffer

            length: u32 = 0;
            Windows.GetLogicalProcessorInformationEx(Windows.RelationProcessorCore, null, *length);
            cpu_information_buffer: *u8 = Basic.talloc(length);
            Windows.GetLogicalProcessorInformationEx(Windows.RelationProcessorCore, xx cpu_information_buffer, *length);

            offset: u32 = 0;
            #if PERFORMANCE {
                max_performance  := 0;
                count_at_max: s32 = 0;
            } else {
                count:  s32 = 0;
            }


            while offset < length {
                cpu_information := cast(*Windows.SYSTEM_LOGICAL_PROCESSOR_INFORMATION_EX) (cpu_information_buffer + offset);
                offset += cpu_information.Size;

                #if PHYSICAL {
                    count_per_group: s32 = 1;
                } else {
                    count_per_group: s32 = Bit_Operations.popcount(cpu_information.Processor.GroupMask.Mask);
                }

                if cpu_information.Relationship != .RelationProcessorCore continue;

                #if PERFORMANCE {
                    if cpu_information.Processor.EfficiencyClass > max_performance {
                        max_performance = cpu_information.Processor.EfficiencyClass;
                        count_at_max = count_per_group;
                    } else if cpu_information.Processor.EfficiencyClass == max_performance {
                        count_at_max += count_per_group;
                    }
                } else {
                    count += count_per_group;
                }
            }

            #if PERFORMANCE {
                return count_at_max;
            } else {
                return count;
            }
        }
    }

    get_error_value :: Windows.GetLastError;

    get_error_string :: (error_code: OS_Error_Code) -> string {
        // Returns a string in temporary storage.
        lpMsgBuf: *u16;
        success := Windows.FormatMessageW(
            Windows.FORMAT_MESSAGE_ALLOCATE_BUFFER |
                Windows.FORMAT_MESSAGE_FROM_SYSTEM |
                Windows.FORMAT_MESSAGE_IGNORE_INSERTS,
            null, error_code,
            Windows.MAKELANGID(Windows.LANG_NEUTRAL, Windows.SUBLANG_DEFAULT), // Default language
                *lpMsgBuf, 0, null);

        if !success return "";

        defer Windows.LocalFree(lpMsgBuf);

        String :: #import "String";
        result := Utf8.wide_to_utf8(lpMsgBuf,, Basic.temp);
        
        // Chop off the newline so that we can format this standardly. Argh.
        return String.trim_right(result, "\r\n");
    }

    get_error_value_and_string :: () -> (error_code: OS_Error_Code, description: string) { // 'description' is in temporary storage, or a static string.
        error_code := Windows.GetLastError();
        description := get_error_string(error_code);
        return error_code, description;
    }
} else #if OS_IS_UNIX && OS != .PS5 {
    #scope_file
    #import "POSIX";
    Process :: #import "Process";
    #scope_export

    get_error_value :: errno;

    get_error_string :: (error_code: OS_Error_Code) -> string {
        error_buffer: [1024] u8;

        libc :: #system_library "libc";
        #if OS == .LINUX {
            strerror_r :: (errnum: s32, buf: *u8, buflen: s32) -> *u8 #foreign libc;

            result := strerror_r(error_code, error_buffer.data, error_buffer.count);
            if !result {
                // This also sets errno to a new error on Linux; ignore for now?
                return Basic.sprint("OS did not return us a valid string for error %. Returned error was %", error_code, errno());
            }

            s := to_string(result);
        } else {
            strerror_r :: (errnum: s32, buf: *u8, buflen: s32) -> int #foreign libc;

            result := strerror_r(error_code, error_buffer.data, error_buffer.count);
            if result != 0 {
                return Basic.sprint("OS did not return us a valid string for error %. Returned error was %", error_code, result);
            }

            s := to_string(error_buffer.data);
        }
        return Basic.copy_temporary_string(s);
    }

    get_error_value_and_string :: () -> (error_code: OS_Error_Code, description: string) { // 'description' is in temporary storage, or a static string.
        error_code := errno();
        description := get_error_string(error_code);
        return error_code, description;
    }
}

#if OS == .LINUX || OS == .ANDROID {
    // Results will be allocated with the temporary allocator
    get_passwd_for_user :: (username := "") -> (success: bool, p: passwd) {
        buffer_size := sysconf(_SC_GETPW_R_SIZE_MAX);
        if buffer_size == -1  {
            // Could not determine correct buffer size. Let’s guess a value and retry, if necessary
            buffer_size = 1024;
        }

        while true {
            buffer := Basic.alloc(buffer_size,, Basic.temp);

            result_pwd: *passwd;
            pwd: passwd;
            result: s32;
            if username {
                result = getpwnam_r(Basic.to_c_string(username), *pwd, buffer, cast(u64) buffer_size, *result_pwd);
            } else {
                user_uid := getuid();
                result = getpwuid_r(user_uid, *pwd, buffer, cast(u64) buffer_size, *result_pwd);
            }

            if result != 0 {
                error_code := errno();
                MAX_BUFFER_SIZE :: 16384; // Don't let this get out of hand
                if error_code == ERANGE && buffer_size < MAX_BUFFER_SIZE {
                    buffer_size *= 2;
                    continue;
                }

                if error_code == ENOENT {
                    // Some systems report "no such user" via ENOENT, some by setting result_pwd to null.
                    return false, .{};
                }

                error_string := get_error_string(error_code);
                if username Basic.log_error("Could not get passwd details for user \"%\": % %", username, error_code, error_string);
                else        Basic.log_error("Could not get passwd details for current user: % %", error_code, error_string);
            }

            if !username Basic.assert(result_pwd != null);
            if !result_pwd {
                // Some systems report "no such user" via ENOENT, some by setting result_pwd to null.
                return false, pwd;
            }

            return true, pwd;
        }
    }

    // Returns a temporary string.
    get_username :: () -> string, success: bool {
        success, pwd := get_passwd_for_user();
        if !success     return "", false;

        return to_string(pwd.pw_name), true;
    }

    // Returns a string that doesn't need to be freed (because it points to system memory)
    get_home_directory :: (username := "") -> string, success: bool {
        if !username {
            // The current user should be able to overwrite their home dir with $HOME
            result := getenv("HOME");
            if result   return to_string(result), true;
        }

        success, pwd := get_passwd_for_user(username);

        if !success return "", false;

        return to_string(pwd.pw_dir), true;
    }

    // Returns a temporary string.
    get_machinename :: () -> string {
        hostname: [1024] u8;
        result := gethostname(xx hostname.data, hostname.count);
        if result < 0 return "unknown";
        return Basic.copy_temporary_string(to_string(hostname.data));
    }

    get_path_of_running_executable :: () -> string /* Temporary Storage */ {
        buf: [4096] u8;  // @StaticBuffer @Robustness

        length := readlink("/proc/self/exe", buf.data, buf.count);
        if length < 0 return "";

        out: string;
        out.data = Basic.alloc(length,, Basic.temp);
        out.count = length;
        memcpy(out.data, buf.data, length);

        return out;
    }

    // @Incomplete: Does Linux support performance and efficiency core counts on Alder
    // Lake, Apple Silicon, etc? We could go the CPUID route for Intel but that would
    // require running on every single core which would be slow however it is possible.
    get_number_of_processors :: ($type: Processor_Query_Type = .PERFORMANCE_LOGICAL) -> count: s32 #modify {
        // Deduplicate the number of instances of this procedure since we
        // do not yet have a way to get the number of performance cores.
        if type == .PERFORMANCE_PHYSICAL then type = .ALL_PHYSICAL;
        if type == .PERFORMANCE_LOGICAL  then type = .ALL_LOGICAL;
        return true;
    } {
        #if type == .ALL_LOGICAL {
            libc :: #system_library "libc";
            get_nprocs :: () -> s32 #foreign libc;
            return get_nprocs();
        } else {
            // Linux just does not make this easy :(
            File :: #import "File";
            // /proc/cpuinfo is a special file so we can't just use read_entire_file because that will not
            // be able to figure out the file size. (It can't be seeked and even fstat just returns 0)
            file_descriptor := open("/proc/cpuinfo", O_RDONLY | O_CLOEXEC);
            original_cpu_info: [..] u8;
            defer Basic.array_free(original_cpu_info);
            if file_descriptor != -1 {
                BLOCK_SIZE :: 4096;
                block: [BLOCK_SIZE] u8;
                completed := read(file_descriptor, block.data, BLOCK_SIZE);
                // If this has short reads, I consider the Linux implementation broken
                while completed > 0 {
                    data: [] u8;
                    data.data = block.data;
                    data.count = completed;
                    Basic.array_add(*original_cpu_info, ..data);
                    completed = read(file_descriptor, block.data, BLOCK_SIZE);
                }
                close(file_descriptor);
                if completed == -1 {
                    return get_number_of_processors(.ALL_LOGICAL);
                }
            }

            cpu_info := cast(string)original_cpu_info;
            if !cpu_info.count return get_number_of_processors(.ALL_LOGICAL);

            String :: #import "String";

            count: s32 = 0;
            last: string;
            while cpu_info.count {
                line_end := String.find_index_from_left(cpu_info, #char "\n");

                if String.starts_with(cpu_info, "core id") {
                    id := cpu_info;
                    if line_end != -1 {
                        id.count = line_end;
                    }
                    last_space := String.find_index_from_right(id, #char " ");
                    if last_space != -1 {
                        id.data += last_space;
                        id.count = id.count - last_space;
                    }
                    if id != last {
                        count += 1;
                        last = id;
                    }
                }

                cpu_info.count -= line_end + 1;
                cpu_info.data  += line_end + 1;
            }

            if !count return get_number_of_processors(.ALL_LOGICAL);
            return count;
        }
    }
} else #if OS == .MACOS {
    #scope_file
    ObjC :: #import "Objective_C";

    c_free   :: (memory: *void)                        #foreign crt "free"; // :CFree:
    crt      :: #system_library "libc";
    #scope_export

    // Returns a temporary string.
    get_username :: () -> string, success:bool {
        // @@ In The Witness we used NSFullUserName.
        ns_username := ObjC.NSUserName();
        defer ObjC.release(ns_username);
        return Basic.copy_temporary_string(ObjC.to_string(ns_username)), true;
    }

    // Returns a string that doesn't need to be freed (either a temporary string or system memory)
    get_home_directory :: (username := "") -> string, success: bool {
        if !username {
            // The current user should be able to overwrite their home dir with $HOME
            result := getenv("HOME");
            if result   return to_string(result), true;

            return Basic.copy_temporary_string(ObjC.to_string(ObjC.NSUserName())), true;
        }

        ObjC.init_objective_c();
        ns_dir: *ObjC.NSString;
        if username {
            ns_username := ObjC.NSString.initWithString(ObjC.objc_alloc(ObjC.NSString), username);
            defer ObjC.release(ns_username);
            ns_dir = ObjC.NSHomeDirectoryForUser(ns_username);
        } else {
            ns_dir = ObjC.NSHomeDirectory();
        }
        defer ObjC.release(ns_dir);

        return Basic.copy_temporary_string(ObjC.to_string(ns_dir)), true;
    }

    // Returns a temporary string.
    get_machinename :: () -> string {
        NSHost :: ObjC.NSHost;
        ObjC.init_objective_c();
        current_host := NSHost.currentHost();
        localized_name := current_host.localizedName(current_host);
        return Basic.copy_temporary_string(ObjC.to_string(localized_name));
    }

    get_path_of_running_executable :: () -> string /* Temporary Storage */ {
        BUFFER_SIZE :: 4096;   // @StaticBuffer @Robustness
        buf: [BUFFER_SIZE] u8;
        length: u32 = BUFFER_SIZE-1;

        result := Basic._NSGetExecutablePath(buf.data, *length);
        if result != 0 return "";

        buf[length] = 0;

        out_path := realpath(buf.data, null);
        if out_path {
            length = cast(u32) c_style_strlen(out_path);
            Basic.assert(length <= BUFFER_SIZE);
            memcpy(buf.data, out_path, length);
            c_free(out_path);
        }

        out := Basic.talloc_string(length);
        memcpy(out.data, buf.data, length);

        return out;
    }

    // This will return the number of cores at the highest performance level. Currently this
    // is the performance cores on Apply Silicon chips and all cores on intel. If you want the
    // total number of cores, use get_total_number_of_processors. Theoretically, an arbitrary
    // number of performance levels are supported but we just categorize the highest performance
    // and the total. If you need this value more than once, you should cache it in a global.
    get_number_of_processors :: ($type: Processor_Query_Type = .PERFORMANCE_LOGICAL) -> count: s32 {
        proc_count: s32;
        proc_count_size: u64 = size_of(type_of(proc_count));
        #if type == .ALL_LOGICAL {
            MIB :: s32.[CTL_HW, HW_AVAILCPU];
            error := sysctl(MIB.data, MIB.count, *proc_count, *proc_count_size, null, 0);
            if error {
                // This should exist on all versions
                return 1;
            }
        } else #if type == .ALL_PHYSICAL {
            if sysctlbyname("hw.physicalcpu", *proc_count, *proc_count_size, null, 0) != 0 {
                // This should exist on all versions.
                return 1;
            }
        } else #if type == .PERFORMANCE_PHYSICAL {
            if sysctlbyname("hw.perflevel0.logicalcpu", *proc_count, *proc_count_size, null, 0) != 0 {
                // hw.perflevelN may not be available on older versions of macOS with intel (homogenous) processors
                proc_count = get_number_of_processors(.ALL_PHYSICAL);
            }

        } else #if type == .PERFORMANCE_LOGICAL {
            if sysctlbyname("hw.perflevel0.physicalcpu", *proc_count, *proc_count_size, null, 0) != 0 {
                // hw.perflevelN may not be available on older versions of macOS with intel (homogenous) processors
                proc_count = get_number_of_processors(.ALL_LOGICAL);
            }
        }
        return proc_count;
    }
}

#scope_file
Basic :: #import "Basic";

#if OS == .PS5 {
    #load "ps5/ps5_system.jai";
}
