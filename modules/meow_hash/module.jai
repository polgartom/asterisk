// This is a port of https://github.com/cmuratori/meow_hash. This is a fully functional and performant port.

// TODO(ryan): Eventually swap the builtin __reg type over to reg.
reg :: __reg;

MEOW_HASH_VERSION :: 5;
MEOW_HASH_VERSION_NAME :: "0.5/calico";

MEOW_PAGESIZE :: 4096;
MEOW_PREFETCH :: 4096;
MEOW_PREFETCH_LIMIT :: 0x3ff;

MeowShiftAdjust: [32] u8 = u8.[0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15];
MeowMaskLen: [32] u8 = u8.[255,255,255,255, 255,255,255,255, 255,255,255,255, 255,255,255,255, 0,0,0,0, 0,0,0,0, 0,0,0,0, 0,0,0,0];

// NOTE(casey): The default seed is now a "nothing-up-our-sleeves" number for good measure.  You may verify that it is just an encoding of Pi.
MeowDefaultSeed: [128] u8 = u8.[
    0x32, 0x43, 0xF6, 0xA8, 0x88, 0x5A, 0x30, 0x8D,
    0x31, 0x31, 0x98, 0xA2, 0xE0, 0x37, 0x07, 0x34,
    0x4A, 0x40, 0x93, 0x82, 0x22, 0x99, 0xF3, 0x1D,
    0x00, 0x82, 0xEF, 0xA9, 0x8E, 0xC4, 0xE6, 0xC8,
    0x94, 0x52, 0x82, 0x1E, 0x63, 0x8D, 0x01, 0x37,
    0x7B, 0xE5, 0x46, 0x6C, 0xF3, 0x4E, 0x90, 0xC6,
    0xCC, 0x0A, 0xC2, 0x9B, 0x7C, 0x97, 0xC5, 0x0D,
    0xD3, 0xF8, 0x4D, 0x5B, 0x5B, 0x54, 0x70, 0x91,
    0x79, 0x21, 0x6D, 0x5D, 0x98, 0x97, 0x9F, 0xB1,
    0xBD, 0x13, 0x10, 0xBA, 0x69, 0x8D, 0xFB, 0x5A,
    0xC2, 0xFF, 0xD7, 0x2D, 0xBD, 0x01, 0xAD, 0xFB,
    0x7B, 0x8E, 0x1A, 0xFE, 0xD6, 0xA2, 0x67, 0xE9,
    0x6B, 0xA7, 0xC9, 0x04, 0x5F, 0x12, 0xC7, 0xF9,
    0x92, 0x4A, 0x19, 0x94, 0x7B, 0x39, 0x16, 0xCF,
    0x70, 0x80, 0x1F, 0x2E, 0x28, 0x58, 0xEF, 0xC1,
    0x66, 0x36, 0x92, 0x0D, 0x87, 0x15, 0x74, 0xE6
];

MEOW_DUMP_STATE :: (T: string, r0: reg, r1: reg, r2: reg, r3: reg, r4: reg, r5: reg, r6: reg, r7: reg) #expand
{
    // TODO(ryan): How to expose this for users of the module?
}

MEOW_MIX_REG :: (r1: reg, r2: reg, r3: reg, r4: reg, r5: reg, i1: reg, i2: reg, i3: reg, i4: reg) #expand
{
    #asm
    {
        aesdec  r1, r2;
        paddq   r3, i1;
        pxor    r2, i2;
        aesdec  r2, r4;
        paddq   r5, i3;
        pxor    r4, i4;
    }
}

MEOW_MIX :: (r1: reg, r2: reg, r3: reg, r4: reg, r5: reg, ptr: *void, $OFFSET: s32) #expand
{
    #asm
    {
        movdqu i1:, [ptr + (OFFSET + 15)];
        movdqu i2:, [ptr + (OFFSET + 0)];
        movdqu i3:, [ptr + (OFFSET + 1)];
        movdqu i4:, [ptr + (OFFSET + 16)];
    }

    MEOW_MIX_REG(r1, r2, r3, r4, r5, i1, i2, i3, i4);
}

MEOW_SHUFFLE :: (r1: reg, r2: reg, r3: reg, r4: reg, r5: reg, r6: reg) #expand
{
    #asm
    {
        aesdec  r1, r4;
        paddq   r2, r5;
        pxor    r4, r6;
        aesdec  r4, r2;
        paddq   r5, r6;
        pxor    r2, r3;
    }
}

MeowU64From :: (Hash: reg, $INDEX: int) -> u64 #expand
{
    Result: u64 = ---;
    #asm
    {
        pextrq Result, Hash, INDEX;
    }
    return Result;
}

MeowU32From :: (Hash: reg, $INDEX: int) -> u32 #expand
{
    Result: u32 = ---;
    #asm
    {
        pextrd Result, Hash, INDEX;
    }
    return Result;
}


MeowBegin :: (Seed: [128] u8, h0: reg, h1: reg, h2: reg, h3: reg, h4: reg, h5: reg, h6: reg, h7: reg) #expand
{
    //
    // NOTE(casey): Seed the eight hash registers
    //

    SeedPtr := Seed.data;
    #asm
    {
        movdqu h0, [SeedPtr + 0x00];
        movdqu h1, [SeedPtr + 0x10];
        movdqu h2, [SeedPtr + 0x20];
        movdqu h3, [SeedPtr + 0x30];
        movdqu h4, [SeedPtr + 0x40];
        movdqu h5, [SeedPtr + 0x50];
        movdqu h6, [SeedPtr + 0x60];
        movdqu h7, [SeedPtr + 0x70];
    }

    MEOW_DUMP_STATE("Seed", h0, h1, h2, h3, h4, h5, h6, h7);
}

MeowAbsorbBlocks :: (BlockCount: u64, Source: *void, h0: reg, h1: reg, h2: reg, h3: reg, h4: reg, h5: reg, h6: reg, h7: reg) #expand
{
    //
    // NOTE(casey): Hash full 256-byte blocks
    //

    if BlockCount > MEOW_PREFETCH_LIMIT
    {
        // NOTE(casey): For large input, modern Intel x64's can't hit full speed without prefetching, so we use this loop
        while BlockCount
        {
            #asm
            {
                prefetcht0 [Source + (MEOW_PREFETCH + 0x00)];
                prefetcht0 [Source + (MEOW_PREFETCH + 0x40)];
                prefetcht0 [Source + (MEOW_PREFETCH + 0x80)];
                prefetcht0 [Source + (MEOW_PREFETCH + 0xc0)];
            }

            MEOW_MIX(h0, h4, h6, h1, h2, Source, 0x00);
            MEOW_MIX(h1, h5, h7, h2, h3, Source, 0x20);
            MEOW_MIX(h2, h6, h0, h3, h4, Source, 0x40);
            MEOW_MIX(h3, h7, h1, h4, h5, Source, 0x60);
            MEOW_MIX(h4, h0, h2, h5, h6, Source, 0x80);
            MEOW_MIX(h5, h1, h3, h6, h7, Source, 0xa0);
            MEOW_MIX(h6, h2, h4, h7, h0, Source, 0xc0);
            MEOW_MIX(h7, h3, h5, h0, h1, Source, 0xe0);

            Source += 0x100;
            BlockCount -= 1;
        }
    }
    else
    {
        // NOTE(casey): For small input, modern Intel x64's can't hit full speed _with_ prefetching (because of port pressure), so we use this loop.
        while BlockCount
        {
            MEOW_MIX(h0, h4, h6, h1, h2, Source, 0x00);
            MEOW_MIX(h1, h5, h7, h2, h3, Source, 0x20);
            MEOW_MIX(h2, h6, h0, h3, h4, Source, 0x40);
            MEOW_MIX(h3, h7, h1, h4, h5, Source, 0x60);
            MEOW_MIX(h4, h0, h2, h5, h6, Source, 0x80);
            MEOW_MIX(h5, h1, h3, h6, h7, Source, 0xa0);
            MEOW_MIX(h6, h2, h4, h7, h0, Source, 0xc0);
            MEOW_MIX(h7, h3, h5, h0, h1, Source, 0xe0);

            Source += 0x100;
            BlockCount -= 1;
        }
    }
}

MeowEnd :: (Len: u64, Source: *void, r1: reg, r3: reg, h0: reg, h1: reg, h2: reg, h3: reg, h4: reg, h5: reg, h6: reg, h7: reg, Store128: *void) #expand
{
    //
    // NOTE(casey): Construct the residual and length injests
    //

    #asm
    {
        movdqu  r0:, r1;
        movdqu  r2:, r1;
        palignr r0, r3, 15;
        palignr r2, r3, 1;

        // NOTE(casey): We have room for a 128-bit nonce and a 64-bit none here, but
        // the decision was made to leave them zero'd so as not to confuse people
        // about how to use them or what security implications they had.
        pxor    r4:, r4;
        pxor    r5:, r5;
        pxor    r6:, r6;

        movq    r7:, Len;
        palignr r4, r7, 15;
        palignr r6, r7, 1;
    }
    
    MEOW_DUMP_STATE("PostBlocks", h0, h1, h2, h3, h4, h5, h6, h7);
    MEOW_DUMP_STATE("Residuals", r0, r1, r2, r3, r4, r5, r6, r7);
    
    // NOTE(casey): To maintain the mix-down pattern, we always Meow Mix the less-than-32-byte residual, even if it was empty
    MEOW_MIX_REG(h0, h4, h6, h1, h2,  r0, r1, r2, r3);
    
    // NOTE(casey): Append the length, to avoid problems with our 32-byte padding
    MEOW_MIX_REG(h1, h5, h7, h2, h3,  r4, r5, r6, r7);
    
    MEOW_DUMP_STATE("PostAppend", h0, h1, h2, h3, h4, h5, h6, h7);
    
    //
    // NOTE(casey): Hash all full 32-byte blocks
    //
    LaneCount := (Len >> 5) & 0x7;
    while true
    {
        if LaneCount == 0 break; MEOW_MIX(h2, h6, h0, h3, h4, Source, 0x00); LaneCount -= 1;
        if LaneCount == 0 break; MEOW_MIX(h3, h7, h1, h4, h5, Source, 0x20); LaneCount -= 1;
        if LaneCount == 0 break; MEOW_MIX(h4, h0, h2, h5, h6, Source, 0x40); LaneCount -= 1;
        if LaneCount == 0 break; MEOW_MIX(h5, h1, h3, h6, h7, Source, 0x60); LaneCount -= 1;
        if LaneCount == 0 break; MEOW_MIX(h6, h2, h4, h7, h0, Source, 0x80); LaneCount -= 1;
        if LaneCount == 0 break; MEOW_MIX(h7, h3, h5, h0, h1, Source, 0xa0); LaneCount -= 1;
        if LaneCount == 0 break; MEOW_MIX(h0, h4, h6, h1, h2, Source, 0xc0); LaneCount -= 1;
        break;
    }

    //
    // NOTE(casey): Mix the eight lanes down to one 128-bit hash
    //
    
    MEOW_DUMP_STATE("PostLanes", h0, h1, h2, h3, h4, h5, h6, h7);
    
    MEOW_SHUFFLE(h0, h1, h2, h4, h5, h6);
    MEOW_SHUFFLE(h1, h2, h3, h5, h6, h7);
    MEOW_SHUFFLE(h2, h3, h4, h6, h7, h0);
    MEOW_SHUFFLE(h3, h4, h5, h7, h0, h1);
    MEOW_SHUFFLE(h4, h5, h6, h0, h1, h2);
    MEOW_SHUFFLE(h5, h6, h7, h1, h2, h3);
    MEOW_SHUFFLE(h6, h7, h0, h2, h3, h4);
    MEOW_SHUFFLE(h7, h0, h1, h3, h4, h5);
    MEOW_SHUFFLE(h0, h1, h2, h4, h5, h6);
    MEOW_SHUFFLE(h1, h2, h3, h5, h6, h7);
    MEOW_SHUFFLE(h2, h3, h4, h6, h7, h0);
    MEOW_SHUFFLE(h3, h4, h5, h7, h0, h1);
    
    MEOW_DUMP_STATE("PostMix", h0, h1, h2, h3, h4, h5, h6, h7);
    
    #if !is_constant(Store128)
    {
        if Store128 #asm
        {
            movdqu [Store128 + 0x00], h0;
            movdqu [Store128 + 0x10], h1;
            movdqu [Store128 + 0x20], h2;
            movdqu [Store128 + 0x30], h3;
            movdqu [Store128 + 0x40], h4;
            movdqu [Store128 + 0x50], h5;
            movdqu [Store128 + 0x60], h6;
            movdqu [Store128 + 0x70], h7;
        }
    }
    
    #asm
    {
        paddq   h0, h2;
        paddq   h1, h3;
        paddq   h4, h6;
        paddq   h5, h7;
        pxor    h0, h1;
        pxor    h4, h5;
        paddq   h0, h4;
    }
    
    MEOW_DUMP_STATE("PostFold", h0, h1, h2, h3, h4, h5, h6, h7);
}

// TODO(ryan): I wish we could 'return' the h0 hash reg...
MeowHash :: (Seed: [128] u8, Len: u64, Source: *void, h0: reg) #expand
{
    // Declare our 8 hash registers.
    #asm
    {
        // TODO(ryan): I wish we could get these back as 'outputs' from the MeowBegin expansion...
        h1: vec; h2: vec; h3: vec; h4: vec; h5: vec; h6: vec; h7: vec;
    }

    MeowBegin(Seed, h0, h1, h2, h3, h4, h5, h6, h7);

    BlockCount := Len >> 8;
    Advance := BlockCount << 8;
    MeowAbsorbBlocks(BlockCount, Source, h0, h1, h2, h3, h4, h5, h6, h7);

    //
    // NOTE(casey): Load any less-than-32-byte residual
    //

    #asm
    {
        pxor r1:, r1;
        pxor r3:, r3;
    }

    //
    // TODO(casey): I need to put more thought into how the end-of-buffer stuff is actually working out here,
    // because I _think_ it may be possible to remove the first branch (on Len8) and let the mask zero out the
    // result, but it would take a little thought to make sure it couldn't read off the end of the buffer due
    // to the & 0xf on the align computation.
    //

    // NOTE(casey): First, we have to load the part that is _not_ 16-byte aligned
    Last := Source + (Len & ~0xf);
    Len8 := Len & 0xf;
    if Len8
    {
        // TODO(ryan): If we had rip-rel addressing in #asm directly, we wouldn't need to explicitly load these pointers
        // before hand.
        MeowMaskLenPtr := MeowMaskLen.data;
        MeowShiftAdjustPtr := MeowShiftAdjust.data;

        // NOTE(casey): Load the mask early
        MaskIndex := 0x10 - Len8;
        #asm
        {
            movdqu Mask:, [MeowMaskLenPtr + MaskIndex];
        }

        LastOk := cast(*void) ((cast(u64) Source + Len - 1) | (MEOW_PAGESIZE - 1)) - 16;

        Align: u64 = 0;
        if Last > LastOk Align = (cast(u64) Last) & 0xf;

        LastAligned := Last - Align;

        #asm
        {
            movdqu  ShiftAdjust:, [MeowShiftAdjustPtr + Align];
            movdqu  r1, [LastAligned];
            pshufb  r1, ShiftAdjust;
            
            // NOTE(jeffr): and off the extra bytes
            pand    r1, Mask;
        }
    }
    
    // NOTE(casey): Next, we have to load the part that _is_ 16-byte aligned
    if Len & 0x10 #asm
    {
        movdqu r3, r1;
        movdqu r1, [Last - 0x10];
    }

    Source += Advance;
    MeowEnd(Len, Source, r1, r3, h0, h1, h2, h3, h4, h5, h6, h7, null);
}

meow_state :: struct
{
    RegisterFile: [256] u8;
    TotalLengthInBytes: u64;
    
    BufferLen: u32;
    
    Buffer: [256] u8;
    Pad: [32] u8; // NOTE(casey): So we know we can over-read Buffer as necessary
}

MeowBegin :: (State: *meow_state, Seed: [128] u8)
{
    #asm { h0: vec; h1: vec; h2: vec; h3: vec; h4: vec; h5: vec; h6: vec; h7: vec; }
    MeowBegin(Seed, h0, h1, h2, h3, h4, h5, h6, h7);

    // NOTE(ryan): Store hash registers
    RegisterFilePtr := State.RegisterFile.data;
    #asm
    {
        movdqu [RegisterFilePtr + 0x00], h0;
        movdqu [RegisterFilePtr + 0x10], h1;
        movdqu [RegisterFilePtr + 0x20], h2;
        movdqu [RegisterFilePtr + 0x30], h3;
        movdqu [RegisterFilePtr + 0x40], h4;
        movdqu [RegisterFilePtr + 0x50], h5;
        movdqu [RegisterFilePtr + 0x60], h6;
        movdqu [RegisterFilePtr + 0x70], h7;
    }

    State.BufferLen = 0;
    State.TotalLengthInBytes = 0;
}

MeowAbsorb :: (State: *meow_state, Len: u64, Source: *void)
{
    // NOTE(ryan): Load hash registers
    RegisterFilePtr := State.RegisterFile.data;
    #asm
    {
        movdqu h0:, [RegisterFilePtr + 0x00];
        movdqu h1:, [RegisterFilePtr + 0x10];
        movdqu h2:, [RegisterFilePtr + 0x20];
        movdqu h3:, [RegisterFilePtr + 0x30];
        movdqu h4:, [RegisterFilePtr + 0x40];
        movdqu h5:, [RegisterFilePtr + 0x50];
        movdqu h6:, [RegisterFilePtr + 0x60];
        movdqu h7:, [RegisterFilePtr + 0x70];
    }

    State.TotalLengthInBytes += Len;

    // NOTE(casey): Handle any buffered residual
    if State.BufferLen
    {
        Fill: u64 = State.Buffer.count - State.BufferLen;
        if Fill > Len
        {
            Fill = Len;
        }

        Len -= Fill;
        while Fill
        {
            State.Buffer[State.BufferLen] = << cast(*u8) Source;
            State.BufferLen += 1;
            Source += 1;
            Fill -= 1;
        }

        if State.BufferLen == State.Buffer.count
        {
            BlockCount: u64 = 1;
            MeowAbsorbBlocks(BlockCount, State.Buffer.data, h0, h1, h2, h3, h4, h5, h6, h7);
            State.BufferLen = 0;
        }
    }

    // NOTE(casey): Handle any full blocks
    BlockCount := Len >> 8;
    Advance := BlockCount << 8;
    MeowAbsorbBlocks(BlockCount, Source, h0, h1, h2, h3, h4, h5, h6, h7);
    
    Len -= Advance;
    Source += Advance;
    
    // NOTE(casey): Store residual
    while Len
    {
        State.Buffer[State.BufferLen] = << cast(*u8) Source;
        State.BufferLen += 1;
        Source += 1;
        Len -= 1;
    }

    // NOTE(ryan): Store hash registers
    #asm
    {
        movdqu [RegisterFilePtr + 0x00], h0;
        movdqu [RegisterFilePtr + 0x10], h1;
        movdqu [RegisterFilePtr + 0x20], h2;
        movdqu [RegisterFilePtr + 0x30], h3;
        movdqu [RegisterFilePtr + 0x40], h4;
        movdqu [RegisterFilePtr + 0x50], h5;
        movdqu [RegisterFilePtr + 0x60], h6;
        movdqu [RegisterFilePtr + 0x70], h7;
    }
}

// TODO(ryan): I wish we could 'return' the h0 hash reg...
MeowEnd :: (State: *meow_state, h0: reg, Store128: *void = null) #expand
{
    // NOTE(ryan): Load hash registers
    RegisterFilePtr := State.RegisterFile.data;
    #asm
    {
        movdqu h0,  [RegisterFilePtr + 0x00];
        movdqu h1:, [RegisterFilePtr + 0x10];
        movdqu h2:, [RegisterFilePtr + 0x20];
        movdqu h3:, [RegisterFilePtr + 0x30];
        movdqu h4:, [RegisterFilePtr + 0x40];
        movdqu h5:, [RegisterFilePtr + 0x50];
        movdqu h6:, [RegisterFilePtr + 0x60];
        movdqu h7:, [RegisterFilePtr + 0x70];
    }

    //
    // NOTE(casey): Load any less-than-32-byte residual
    //

    #asm
    {
        pxor r1:, r1;
        pxor r3:, r3;
    }

    Source := State.Buffer.data;
    Len := State.TotalLengthInBytes;
    
    // NOTE(casey): First, we have to load the part that is _not_ 16-byte aligned
    Last := Source + (Len & 0xf0);
    Len8 := Len & 0xf;
    if Len8
    {
        // TODO(ryan): If we had rip-rel addressing in #asm directly, we wouldn't need to explicitly load these pointers
        // before hand.
        MeowMaskLenPtr := MeowMaskLen.data;
        MaskIndex := 0x10 - Len8;
        #asm
        {
            movdqu  Mask:, [MeowMaskLenPtr + MaskIndex];
            movdqu  r1, [Last];
            pand    r1, Mask;
        }
    }

    // NOTE(casey): Next, we have to load the part that _is_ 16-byte aligned
    if State.TotalLengthInBytes & 0x10 #asm
    {
        movdqu r3, r1;
        movdqu r1, [Last - 0x10];
    }

    MeowEnd(Len, Source, r1, r3, h0, h1, h2, h3, h4, h5, h6, h7, Store128);
}
