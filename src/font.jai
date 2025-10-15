init_fonts :: () {
    font_data: string;

    if font_family {
        ok, font_data= := table_find(*loaded_fonts, font_family);
        if !ok {
            found := false;
            filepath: string;
            ext, found_ext := path_extension(font_family);
            if ext && found_ext {
                found = file_exists(font_family);
                filepath = font_family;
            } else {
                found, filepath = find_font_by_name(font_family);
            }

            if found {
                font_data, ok = File.read_entire_file(filepath);
                if ok table_add(*loaded_fonts, font_family, font_data);
            } else {
                log_error("Unable to locate '%' font. If the font is installed then maybe it's not ttf, which is currently the only supported format.\n", font_family);
                free_string(*font_family); // do not try next time
            }
        }
    }

    if !font_data then font_data = BAKED_FONT_DEFAULT.data;

    r_font       = Simp.get_font_at_size(cast([]u8)font_data, cast(int)(font_size*dpi_scale));
    r_font_sm    = Simp.get_font_at_size(cast([]u8)font_data, cast(int)(font_size_sm*dpi_scale));
    r_font_icons = Simp.get_font_at_size(cast([]u8)BAKED_FONT_ICONS.data, cast(int)(font_size*dpi_scale));
    assert(r_font != null && r_font_sm != null && r_font_icons != null);

    file_icon_md_width        = measure_text_width(r_font_icons, FILE_ICON);
    folder_icon_md_width      = measure_text_width(r_font_icons, FOLDER_ICON);
    folder_open_icon_md_width = measure_text_width(r_font_icons, FOLDER_ICON);    
}

load_font :: (name: string) -> Loaded_Font {
    path := tprint("data/%", name);
    data, success := File.read_entire_file(path);
    assert(success, "Couldn't load font '%'", path);

    return Loaded_Font.{ name = name, data = data};
}

fontawesome_utf32_to_utf8 :: (character: u32) -> string {
    s := alloc_string(4);
    zero_memory(s.data, 4);
    character_utf32_to_utf8(character, *s);
    return s;
}

fnt_get_line_height :: inline (row: s64 = 1, font: *Simp.Dynamic_Font = null) -> float32 {
    if !font then font = r_font;
    return row * (font.default_line_spacing + line_height*dpi_scale);
}

em :: (x: float, font: *Simp.Dynamic_Font) -> float {
    if font return font.em_width * x;
    return 1;  // In case we get null fonts from the user.
}

find_font_by_name :: (name: string, allocator := temp) -> bool, string {
    // Copied from Focus editor

    // We would like to use `EnumFontFamiliesExA()` so we can filter out fonts that are
    // not monospace. However it only enumerates fonts that have been loaded in GDI via
    // `AddFontResourceEx()` which doesn't include fonts installed in the user specific
    // location (`%LocalAppData%\Microsoft\Windows\Fonts`) by default.
    //
    // Instead of spamming `AddFontResourceEx()` calls we just take file names straight
    // from he registry.

    hkeys  : []HKEY   = .[HKEY_CURRENT_USER, HKEY_LOCAL_MACHINE];
    styles : []string = .[" Regular", ""];
    types  : []string = .[" (TrueType)", ""];
    key    : string   = "Software\\Microsoft\\Windows NT\\CurrentVersion\\Fonts\0";  // Needs '\0' at the end so we can pass it to RegGetValueA()
    for hkey : hkeys {
        for style : styles {
            for type : types {
                buff: [1024]u8;
                size: DWORD = buff.count - 1;

                value := sprint("%1%2%3\0", name, style, type);  // Needs '\0' at the end so we can pass it to RegGetValueA()
                defer free(value);

                ret := RegGetValueA(hkey, key.data, value.data, RRF_RT_REG_SZ, null, buff.data, *size);
                if ret != 0 continue;

                path := to_string(buff.data, size);
                if !is_absolute_path(path) {
                    full_path := tprint("%/%", get_fonts_path(), path);
                    return true, copy_string(full_path,, allocator = allocator);
                }
                return true, copy_string(path,, allocator = allocator);
            }
        }
    }

    return false, "";
}

#if OS == .WINDOWS {
    get_fonts_path :: () -> string {
        // Copied from Focus editor

        // Windows is terrible. SHGetKnownFolderPath returns you something that you need to free with CoTaskMemFree,
        // which is in ole32.dll.
        // Note that THIS IS OUR ONLY DEPENDENCY ON OLE32.
        // We put it here so that you don't take the dependency unless you call this function
        // (unless dead code elimination is off!).
        ole32    :: #system_library "ole32";
        shell32  :: #system_library "shell32";
        SHGetKnownFolderPath :: (nFolder: REFGUID, dwFlags: DWORD, hToken: HANDLE, pszPath: **u16) -> HRESULT #foreign shell32;
        CoTaskMemFree :: (microsoft_is_not_good: *void) #foreign ole32;

        if !fonts_dir_default {
            path_utf16: *u16;
            ret := SHGetKnownFolderPath(*FOLDERID_Fonts, KF_FLAG_CREATE, null, *path_utf16);
            defer CoTaskMemFree(path_utf16);
            if SUCCEEDED(ret) {
                fonts_dir_default = wide_to_utf8(path_utf16);
                path_overwrite_separators(fonts_dir_default, #char "/");
            } else {
                fonts_dir_default = "C:/Windows/Fonts";
            }
        }
        return fonts_dir_default;
    }
}

r_font:       *Simp.Dynamic_Font;
r_font_sm:    *Simp.Dynamic_Font;
r_font_icons: *Simp.Dynamic_Font;

font_family: string;
font_size: u8 = 14;
font_size_sm: u8 = 13; // change this dynamically based on the dpi and the font_size

file_icon_md_width := 0;
folder_icon_md_width := 0;
folder_open_icon_md_width := 0;

PEN_ICON            :: #run fontawesome_utf32_to_utf8(0xf304);
CASE_SENSITIVE_ICON :: #run fontawesome_utf32_to_utf8(0xf031);
WHOLE_WORD_ICON     :: #run fontawesome_utf32_to_utf8(0xe4ba);
REGEX_SEARCH_ICON   :: #run fontawesome_utf32_to_utf8(0xf621);
BULLET_ICON         :: #run fontawesome_utf32_to_utf8(0x2022);
XMARK_ICON          :: #run fontawesome_utf32_to_utf8(0xf057);
FILE_ICON           :: #run fontawesome_utf32_to_utf8(0xf15b);
FOLDER_ICON         :: #run fontawesome_utf32_to_utf8(0xf07b);
FOLDER_OPEN_ICON    :: #run fontawesome_utf32_to_utf8(0xf07c);

BAKED_FONT_DEFAULT :: #run load_font("firacode-retina/FiraCode-Retina.ttf");
BAKED_FONT_ICONS   :: #run load_font("font-awesome/Font Awesome 6 Free-Solid-900.otf");

loaded_fonts: Table(string, string);

fonts_dir_default: string;

Loaded_Font :: struct {
    name: string;
    data: string;
}

#scope_file

#if OS == .WINDOWS {
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
}