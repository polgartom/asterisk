#if OS == .LINUX {

get_os_fonts_path :: () -> string {
    return "/usr/share/fonts";
}

}

#if OS == .WINDOWS {

get_os_fonts_path :: () -> string {
    // Windows is terrible. SHGetKnownFolderPath returns you something that you need to free with CoTaskMemFree,
    // which is in ole32.dll.
    // Note that THIS IS OUR ONLY DEPENDENCY ON OLE32.
    // We put it here so that you don't take the dependency unless you call this function
    // (unless dead code elimination is off!).
    ole32    :: #system_library "ole32";
    shell32  :: #system_library "shell32";

    SHGetKnownFolderPath :: (nFolder: REFGUID, dwFlags: DWORD, hToken: HANDLE, pszPath: **u16) -> HRESULT #foreign shell32;
    CoTaskMemFree :: (microsoft_is_not_good: *void) #foreign ole32;

    path_data: *u16;
    hr := SHGetKnownFolderPath(*FOLDERID_Fonts, KF_FLAG_CREATE, null, *path_data);
    defer CoTaskMemFree(path_data);
    if !SUCCEEDED(hr) return "";

    return wide_to_utf8(path_data);
}

#scope_file

// https://learn.microsoft.com/en-us/windows/win32/shell/knownfolderid
// GUID	{FD228CB7-AE11-4AE3-864C-16F3910AB8FE}
// Display Name	Fonts
// Folder Type	FIXED
// Default Path	%windir%\Fonts
// CSIDL Equivalent	CSIDL_FONTS
// Legacy Display Name	Fonts
// Legacy Default Path	%windir%\Fonts
FOLDERID_Fonts :: #run string_to_guid("FD228CB7-AE11-4AE3-864C-16F3910AB8FE");
KF_FLAG_CREATE :: 0x00008000;

#import "Windows";
#import "Windows_Utf8";

}