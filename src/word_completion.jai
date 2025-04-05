// @CLEANUP: REWRITE THIS! I just moved this from "focus" editor I implemented, but this is very bad!

word_completion :: (forwards := true, subwords := false) {
    using word_complete;
    should_abort = false;

    if !active {
        search_for_subwords = subwords;
        word_complete_search();

        if results.count == 0 then return;
        active = true;
    }

    if forwards {
        word_completion_next();
    } else {
        word_completion_previous();
    }
}

word_completion_next :: () {
    using word_complete;

    selected_result_index = (selected_result_index + 1) % results.count;

    word_complete_apply();
}

word_completion_previous :: () {
    using word_complete;

    if selected_result_index - 1 < 0 {
        selected_result_index = results.count-1;
    } else {
        selected_result_index -= 1;
    }

    word_complete_apply();
}

word_complete_abort :: () {
    using word_complete;

    active = false;
    if !results.count return;

    for results { free(it.word); }
    array_reset_keeping_memory(*results);
    selected_result_index = -1;
}

word_complete_search :: () {
    // hmm...
    UNDERSCORE_PENALTY     :: 1000000000;
    CASE_SENSITIVE_PENALTY :: 100000000;

    editor, buffer := get_active_editor_and_buffer();

    buffer_str := to_string(buffer);

    using word_complete;

    cursor := *editor.cursor;
    right := cursor.pos;
    left  := seek_left_utf8_until_alphanum(buffer_str, cursor.pos, include_last_non_alphanum_char=false);
    initial_word = get_range_as_string(buffer_str, Range.{left, right});

    if initial_word.count == 0 then return;

    add_new_result_or_update_delta :: inline (new_result: string, delta: s64) {
        if word_complete.search_for_subwords {
            for 0..new_result.count-1 {
                if new_result[it] == #char "_" {
                    delta += UNDERSCORE_PENALTY;
                    break;
                }
            }
        }

        for * word_complete.results {
            if it.word == new_result {
                // found a closer one
                if delta < it.cursor_delta then it.cursor_delta = xx delta;
                return;
            } 
        }

        result := Word_Result.{word = new_result, cursor_delta = xx delta}; 
        array_add(*word_complete.results, result);
    }

    pos := 0;
    while pos != buffer_str.count-1 {
        pos = find_index_from_left_nocase(buffer_str, initial_word, pos);
        if pos == -1 break;

        defer pos += initial_word.count;
        if pos == left || (pos > 0 && is_word_char(buffer_str[pos-1])) {
            // Exclude results that are part of another word. For instance, if your subword is 'ine' and you have a word like 'wine' elsewhere, it will not include the result 'ine' from 'w[ine]'.
            continue;
        }

        for i: pos..buffer_str.count-1 {
            c := buffer_str[i];
            if !is_word_char(c) || i == buffer_str.count-1 {
                is_subword := c == #char "_";

                s := advance(buffer_str, pos); 
                s.count = i - pos;
                if s != initial_word {
                    // Now, we're going left to right, so the distance between the word and the cursor will 
                    // always be closer than in right-to-left searching; thus, we need to apply some corrections to it.
                    cursor_delta := cursor.pos - pos;
                    if pos >= right then cursor_delta = i - cursor.pos;
                    if is_upper(initial_word[0]) != is_upper(buffer_str[pos]) then cursor_delta += CASE_SENSITIVE_PENALTY;
                    add_new_result_or_update_delta(s, cursor_delta);
                }

                if !is_subword then break;
            }
        }

    }

    if !word_complete.results.count then return;

    bubble_sort(word_complete.results, (a, b) => cast(s64) ((a.cursor_delta) - (b.cursor_delta)));

    add_new_result_or_update_delta(initial_word, delta = 0);
    for * word_complete.results { it.word = copy_string(it.word); }
}

word_complete_apply :: ($apply_history := false) {
    using word_complete;

    if !results return;
    editor, buffer := get_active_editor_and_buffer();

    result := results[selected_result_index];
    word   := result.word;
 
    buf_str := to_string(buffer);
    buf_len := cast(s32) buffer.count;

    // @Todo: We don't want to save every replacement in the history, we want to save the last one, when we released the CTRL key
    cursor := *editor.cursor;
    cursor.sel = seek_left_utf8_until_alphanum(buf_str, cursor.pos, include_last_non_alphanum_char=false);
    replace_selection(editor, buffer, cursor, result.word, history=true);
}

// This procedure is copied from focus editor
is_word_char :: (c: u8) -> bool {
	return (#char "A" <= c && c <= #char "Z") ||
		(#char "a" <= c && c <= #char "z") ||
		(#char "0" <= c && c <= #char "9") ||
		c == #char "_";
}

Word_Completion :: struct {
    MAX_TOTAL_RESULT :: 30;

    initial_word: string;

    active := false;
    should_abort := false;
    selected_result_index := -1;
    search_for_subwords := false;
    results: [..] Word_Result;
}

Word_Result :: struct {
    word:         string;
    cursor_delta: s32;
}

word_complete: Word_Completion;