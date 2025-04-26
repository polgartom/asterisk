#scope_file
Basic  :: #import "Basic";
#scope_export

Unicode_Result :: enum {
    CONVERSION_OK;
    SOURCE_EXHAUSTED;
    SOURCE_ILLEGAL;
}

UNI_REPLACEMENT_CHAR :: 0x0000FFFD;
UNI_MAX_BMP          :: 0x0000FFFF;
UNI_MAX_UTF16        :: 0x0010FFFF;
UNI_MAX_UTF32        :: 0x7FFFFFFF;

character_utf8_to_utf32 :: (s: *u8, source_length: s64, $strict := false) -> u32, s64, Unicode_Result {
    continuation_bytes := trailingBytesForUTF8[s[0]];

    if continuation_bytes + 1 > source_length {
        return UNI_REPLACEMENT_CHAR, source_length, .SOURCE_EXHAUSTED;
    }

    ch: u32 = s[0] & utf8_inital_byte_mask[continuation_bytes];

    for 1..continuation_bytes {  // Do nothing if it is 0.
        ch = ch << 6;
        #if strict if s[it] & 0xC0 != 0x80 then return UNI_REPLACEMENT_CHAR, it - 1, .SOURCE_ILLEGAL;
    	ch |= s[it] & 0x3F;
    }

    #if strict { 
        SURROGATES_START :: 0xD800;
        SURROGATES_END   :: 0xDFFF;
        if ch > UNI_MAX_UTF16 ||
          (SURROGATES_START <= ch && ch <= SURROGATES_END) ||
          (ch <= 0x0000007F && continuation_bytes != 0) ||
          (ch <= 0x000007FF && continuation_bytes != 1) ||
          (ch <= 0x0000FFFF && continuation_bytes != 2) ||
          continuation_bytes > 3 {
            return UNI_REPLACEMENT_CHAR, continuation_bytes+1, .SOURCE_ILLEGAL;
        }
    }

    if ch > UNI_MAX_UTF32 {
        ch = UNI_REPLACEMENT_CHAR;
    }

	return ch, continuation_bytes+1, Unicode_Result.CONVERSION_OK;
}


// Based on ConvertUTF.h reference implementation.
character_utf32_to_utf8 :: (ch: u32, preallocated_string: *string) {  // preallocated_string must have at least 4 characters of allocated memory.
    UNI_MAX_LEGAL_UTF32  :: 0x0010FFFF;
    UNI_REPLACEMENT_CHAR :: 0x0000FFFD;

    count := 0;
    if ch < 0x80                        count = 1;
    else if ch < 0x800                  count = 2;
    else if ch < 0x10000                count = 3;
    else if ch <= UNI_MAX_LEGAL_UTF32   count = 4;
    else {
        count = 3;
        ch = UNI_REPLACEMENT_CHAR;
    }

    byteMask :: 0xBF;
    byteMark :: 0x80; 

    preallocated_string.count = count;
    s := preallocated_string;
    
    if count == {
        case 4; s.data[3] = xx (ch | byteMark) & byteMask; ch = ch >> 6; #through;
        case 3; s.data[2] = xx (ch | byteMark) & byteMask; ch = ch >> 6; #through;
        case 2; s.data[1] = xx (ch | byteMark) & byteMask; ch = ch >> 6; #through;
        case 1; s.data[0] = xx (ch | firstByteMark[count]);
    }
}

character_utf32_to_utf8 :: (ch: u32) -> string {  // Returns a string allocated on the heap. Messy!
    // @Cleanup: We really are taking a dependency on Basic just for this?
    s := Basic.alloc_string(4); // No point heap-allocating less than this, even if the string is shorter...!
    character_utf32_to_utf8(ch, *s);
    return s;
}


unicode_next_character :: (s: *u8) -> *u8 {
    bytes_for_this_character := 1 + trailingBytesForUTF8[s.*];
    return s + bytes_for_this_character;
}

utf8_next_character :: (s: *string) -> code: u32, success: Unicode_Result {
    code, bytes, success := character_utf8_to_utf32(s.data, s.count);

    s.data  += bytes;
    s.count -= bytes;
    Basic.assert(s.count >= 0);

    return code, success;
}

//
// utf8_iter is an iterator proc you can use on a string, for example:
//
//    for :utf8_iter s { ... }
//
// We did this as a fun experiment, but maybe it's not worth using.
// There are some constraints, for example, we wanted to keep backward iteration
// single-pass, so it_index is not set in that case (it is always -1). And
// we don't support by-pointer iteration. Is this much better than doing
// this yourself in a tight loop? Maybe...

utf8_iter :: (s: *string, body: Code, flags: For_Flags) #expand {
    #assert !(flags & .POINTER) "POINTER traversal is not supported by this iterator, because a tthat point you have to call character_utf8_to_utf32 and are kind of just doing it yourself so why use the iterator?";

    end    := s.data + s.count;
    if !s return;

    `it: u32;
    `it_index: s64;
    
    #if flags & .REVERSE {
        cursor := end-1;

        `it_index = -1;  // it_index is not supported for reverse iteration. Deal with it. If you want that, this has to be a 2-pass algorithm where we count the characters in the first pass, and that's slower. But maybe we will do that.
    } else {
        cursor := s.data;

        `it_index = 0;
    }
    
    while 1 {
        #if flags & .REVERSE {
            // Seek backward to the first character that is < 127.

            while ((cursor.* & 0xc0) == 0x80) && (cursor > s.data) {
                cursor -= 1;
            }

            if (cursor.* & 0xc0) == 0x80 {
                Basic.log_error("The input string starts in the middle of a Unicode character. (cursor is % bytes from s.data)\n", cursor - s.data);
                break;
            }
        }
        
        code, bytes, unicode_result := character_utf8_to_utf32(cursor, end - cursor, true);
        if unicode_result != .CONVERSION_OK {
            Basic.log_error("Error: %\n", unicode_result);
            break;
        }

        `it = code;
        #insert body;

        #if flags & .REVERSE {
            cursor -= 1;
            if cursor < s.data break;
        } else {
            cursor += bytes;
            Basic.assert(cursor <= end);

            if cursor >= end  break;

            it_index += 1;
        }
    }
}
    

//#scope_file

trailingBytesForUTF8 :: u8.[
	0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0, 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
	0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0, 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
	0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0, 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
	0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0, 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
	0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0, 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
	0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0, 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
	1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1, 1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,
	2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2, 3,3,3,3,3,3,3,3,4,4,4,4,5,5,5,5
];

utf8_inital_byte_mask :: u8.[ 0x7F, 0x1F, 0x0F, 0x07, 0x03, 0x01 ];

offsetsFromUTF8 : [6] u32 : .[ 0x00000000, 0x00003080, 0x000E2080, 
					           0x03C82080, 0xFA082080, 0x82082080 ];

firstByteMark : [7] u8 : .[ 0x00, 0x00, 0xC0, 0xE0, 0xF0, 0xF8, 0xFC ];
