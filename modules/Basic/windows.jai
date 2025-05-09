sleep_milliseconds :: (milliseconds: s32) {
    Sleep(milliseconds);
}

set_working_directory :: (s: string) -> bool {
    wide := utf8_to_wide(s,, allocator=temp);
    if !wide  return false;

    result := SetCurrentDirectoryW(wide);
    return (result != 0);
}

get_working_directory :: () -> result: string /* Temporary Storage */ {  // Returns the empty string on failure.
    status := GetCurrentDirectoryW(0, null);
    utf16_buf := cast(*u16) alloc(status * size_of(u16),, allocator=__temporary_allocator);
    if !utf16_buf  return "";

    status = GetCurrentDirectoryW(status, utf16_buf);

    if status > 0 {
        return wide_to_utf8(utf16_buf,, allocator=temp);
    } else {
        log_error("Unable to get the current directory.");
        return "";
    }
}

exit :: (status: s32) {
    FlushFileBuffers(windows_standard_output);
    FlushFileBuffers(windows_standard_error);
    ExitProcess(xx status);
}

#scope_file

// We redefine this stuff here, so that we can use this module without
// importing modules/Windows, because that is huge and gnarly.

// This is an experiment, though. Maybe it's not worth duplicating all this stuff,
// if people are going to import Windows anwyay. Hard to say.
//           -jblow, 6 February 2020

kernel32 :: #system_library "kernel32";
BOOL     :: enum s32 { FALSE :: 0; TRUE :: 1; }

Sleep    :: (milliseconds: s32) -> void #foreign kernel32;
QueryPerformanceFrequency :: (result: *s64) -> s32 #foreign kernel32;
QueryPerformanceCounter   :: (result: *s64) -> s32 #foreign kernel32;
SetCurrentDirectoryW :: (name: *u16) -> BOOL #foreign kernel32;
GetCurrentDirectoryW :: (nBufferLength: DWORD, lpBuffer: *u16) -> DWORD #foreign kernel32;
GetLocalTime :: (time: *SYSTEMTIME) -> void #foreign kernel32;
GetSystemTime :: (time : *SYSTEMTIME) -> void #foreign kernel32;

FlushFileBuffers :: (hFile: HANDLE) -> BOOL #foreign kernel32;
ExitProcess :: (exit_code: u32) -> void #foreign kernel32;

SYSTEMTIME :: struct {
    wYear         : u16;
    wMonth        : u16;
    wDayOfWeek    : u16;
    wDay          : u16;
    wHour         : u16;
    wMinute       : u16;
    wSecond       : u16;
    uMilliseconds : u16;
}

HANDLE :: *void;
HWND   :: HANDLE;

DWORD  :: u32;

RECT :: struct {
    left, top, right, bottom: s32;
}

POINT :: struct {
    x, y: s32;
}

// STD_INPUT_HANDLE  :: -10;
STD_OUTPUT_HANDLE :: -11;
// STD_ERROR_HANDLE  :: -12;

#import "Windows_Utf8";

