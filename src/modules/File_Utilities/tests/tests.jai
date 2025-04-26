file_utilities_tests :: () { // Very simple, to get the ball rolling.
    // @robustness @abner there are OS functions that create random and unique filenames

    DIRECTORY     :: "file_utilities_tests";

    FILENAME      :: "file_utilities_tests/test.txt";
    FILENAME_COPY :: "file_utilities_tests/test.txt.copy";
    FILENAME_TEMP :: "file_utilities_tests/test.txt.temp";
    DATA          :: "QWERTYUIOP\nASDFGHJKL;\nZXCVBNM,./\n";

    delete_directory(DIRECTORY);
    make_directory_if_it_does_not_exist(DIRECTORY);

    if file_exists(FILENAME) {
        assert(false, message="Creating '%' in working directory but it already exists.", FILENAME);
        return;
    }

    success := write_entire_file(FILENAME, DATA);
    assert(success == true, "Could not write file %", FILENAME);

    if file_exists(FILENAME_COPY) {
        assert(false, message="Creating '%' in working directory but it already exists.", FILENAME_COPY);
        return;
    }

    success = copy_file(FILENAME, FILENAME_COPY);
    assert(success == true, "Could not copy file % to %", FILENAME, FILENAME_COPY);

    files := file_list(DIRECTORY);
    assert(files.count > 0, "files.count (%) > 0", files.count);
    defer for files free(it);

    filename := "";
    for files {
        if it == FILENAME {
            filename = it;
            break;
        }
    }

    assert(filename == FILENAME, "\"%\" == \"%\"", filename, FILENAME);

    for files {
        if it == FILENAME_COPY {
            filename = it;
            break;
        }
    }

    assert(filename == FILENAME_COPY, "\"%\" == \"%\"", filename, FILENAME_COPY);

    // @todo @abner missing visit_files tests (although that's tested implicitly.)

    delete_directory(DIRECTORY);
    print("All OK\n");
} 

main :: () {
    file_utilities_tests();
}


#import "Basic";
#import "File";
#import "File_Utilities";
