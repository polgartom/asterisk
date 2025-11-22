#import "Basic";
#import "File";
#import "meow_hash";

/*
    This program loads and hashes a test file. The 128-bit hash is printed along with timing information.

    When tested with a -release build on the file at https://norvig.com/big.txt, you should see...
        hash: a7dbbcbb-448de7e8-c74e8d51-96bcda06
        rate: ~25-30gbps (for an i9-11900k with frequency scaling on)
*/
main :: ()
{
    Args := get_command_line_arguments();
    if (Args.count < 2)
    {
        print("Pass a path to the file you want to hash.\n");
        return;
    }

    TextToHash, Success := read_entire_file(Args[1]);
    if (!Success)
    {
        print("Failed to load test file '%'.\n", Args[1]);
        return;
    }

    Len := cast(u64) TextToHash.count;
    Source := TextToHash.data;

    SingleBlockApi(Len, Source);
    ChunkedApi(Len, Source);
}

SingleBlockApi :: (Len: u64, Source: *void) {
    t0 := seconds_since_init();

    #asm { Hash: vec; }
    MeowHash(MeowDefaultSeed, Len, Source, Hash);
    
    t1 := seconds_since_init();

    print("[single-block] Hash: %-%-%-%, rate: %gbps\n",
        formatInt(MeowU32From(Hash, 3), 16),
        formatInt(MeowU32From(Hash, 2), 16),
        formatInt(MeowU32From(Hash, 1), 16),
        formatInt(MeowU32From(Hash, 0), 16),
        (Len / (t1 - t0)) / (1024 * 1024 * 1024));
}

ChunkedApi :: (Len: u64, Source: *void) {
    t0 := seconds_since_init();

    State: meow_state = ---;
    MeowBegin(*State, MeowDefaultSeed);

    BytesRemaining := Len;
    while BytesRemaining
    {
        ChunkSize := BytesRemaining;
        if (ChunkSize > 4096)
        {
            ChunkSize = 4096;
        }

        MeowAbsorb(*State, ChunkSize, Source);
        BytesRemaining -= ChunkSize;
        Source += ChunkSize;
    }

    #asm { Hash: vec; };
    MeowEnd(*State, Hash);
    
    t1 := seconds_since_init();

    print("[chunked] Hash: %-%-%-%, rate: %gbps\n",
        formatInt(MeowU32From(Hash, 3), 16),
        formatInt(MeowU32From(Hash, 2), 16),
        formatInt(MeowU32From(Hash, 1), 16),
        formatInt(MeowU32From(Hash, 0), 16),
        (Len / (t1 - t0)) / (1024 * 1024 * 1024));
}
