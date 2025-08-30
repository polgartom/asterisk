
init_fonts :: () {
    _BAKED_FONT_DATA :: #run -> [] u8 {
        #import "Compiler";
        filename := tprint("%/../data/firacode-retina/FiraCode-Retina.ttf", #filepath);
        font_binary, success := File.read_entire_file(filename);
        if !success compiler_report(tprint("Unable to load font file '%'!\n", filename));

        result := add_global_data(cast([] u8)font_binary, .READ_ONLY);
        return result;
    }

    primary_font    = Simp.get_font_at_size(_BAKED_FONT_DATA, ui.font_size);
    primary_font_xs = Simp.get_font_at_size(_BAKED_FONT_DATA, ui.font_xs_size);

    font_icons = Simp.get_font_at_size(cast([]u8)FONT_ICONS.data, ui.font_size);

    file_icon_md_width = measure_text_width(font_icons, FILE_ICON);
    folder_icon_md_width = measure_text_width(font_icons, FOLDER_ICON);
    folder_open_icon_md_width = measure_text_width(font_icons, FOLDER_ICON);

    assert(primary_font != null && primary_font_xs != null);
}


load_font :: (name: string) -> Loaded_Font {
    path := tprint("data/%", name);
    data, success := File.read_entire_file(path);
    assert(success, "Couldn't load font '%'", path);

    return Loaded_Font.{ name = name, data = data};
}

Loaded_Font :: struct {
    name: string;
    data: string;
}

primary_font: *Simp.Dynamic_Font;
primary_font_xs: *Simp.Dynamic_Font;
font_icons: *Simp.Dynamic_Font;

FONT_ICONS :: #run load_font("font-awesome/Font Awesome 6 Free-Solid-900.otf");

PEN_ICON            :: #run fontawesome_utf32_to_utf8(0xf304);
CASE_SENSITIVE_ICON :: #run fontawesome_utf32_to_utf8(0xf031);
WHOLE_WORD_ICON     :: #run fontawesome_utf32_to_utf8(0xe4ba);
REGEX_SEARCH_ICON   :: #run fontawesome_utf32_to_utf8(0xf621);
BULLET_ICON         :: #run fontawesome_utf32_to_utf8(0x2022);
XMARK_ICON          :: #run fontawesome_utf32_to_utf8(0xf057);
FILE_ICON           :: #run fontawesome_utf32_to_utf8(0xf15b);
FOLDER_ICON         :: #run fontawesome_utf32_to_utf8(0xf07b);
FOLDER_OPEN_ICON    :: #run fontawesome_utf32_to_utf8(0xf07c);

file_icon_md_width := 0;
folder_icon_md_width := 0;
folder_open_icon_md_width := 0;

fontawesome_utf32_to_utf8 :: (character: u32) -> string {
    s := alloc_string(4);
    zero_memory(s.data, 4);
    character_utf32_to_utf8(character, *s);
    return s;
}

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
    // GUID    {FD228CB7-AE11-4AE3-864C-16F3910AB8FE}
    // Display Name    Fonts
    // Folder Type    FIXED
    // Default Path    %windir%\Fonts
    // CSIDL Equivalent    CSIDL_FONTS
    // Legacy Display Name    Fonts
    // Legacy Default Path    %windir%\Fonts
    FOLDERID_Fonts :: #run string_to_guid("FD228CB7-AE11-4AE3-864C-16F3910AB8FE");
    KF_FLAG_CREATE :: 0x00008000;
    
    #import "Windows";
    #import "Windows_Utf8";

}