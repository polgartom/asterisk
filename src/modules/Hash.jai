// Hash functions for short strings and small data types.
// Probably some more should be added.

//
// This file is here largely to interface with Hash_Table, though the hashes
// are usable separately.
//
// That said, the hashes in this file right now are probably not the best ones
// for any particular use.
//
// We will be revamping them at some point.
//
// Of particular concern is that the 'h' parameter, which is an argument to sdbm_hash(),
// is being used by the higher-level routines like get_hash() in order to chain hash results
// together. The idea is, if you hash data A, then you can combine A with some new data B
// by passing the hash from A in as the 'h' parameter to B.
//
// But I think as a higher-level construct, this is a bad way to do it, because it requires
// any hash function you use to be able to take this parameter. But many don't, and if people
// try to randomly add such a parameter into an existing hash function so it can plug in here,
// it probably won't be hashed well.
//
// I think a better solution is to provide a hash mixing function that can be used to chain
// any two hash results together, without caring how those results were generated.
// When we have such a mixing function we will provide it here, and remove the 'h' parameters
// from the higher-level API. So, be ready for those to go away.
//
//              -jblow, 4 March 2022
//

// Hash function from the open source sdbm project. It's equivalent to:
// `hash(i) = hash(i - 1) * 65599 + data[i]`
// The constant 65599 was picked out of thin air, but happens to be a prime.
// Like djb2, this produces sequential hashes for inputs with sequential
// trailing bytes as is common in strings. fmv-1a is a better general-purpose
// string hash.
sdbm_hash :: (data: *void, size: int, h := HASH_INIT) -> u32 {
    for 0..size-1 #no_abc #no_aoc { 
        h = (h << 16) + (h << 6) - h + (cast(*u8)data)[it];
    }
    
    return h;
}

// This is the same as the `sdbm_hash` function, but it makes sure that zero and 
// negative zero produce the same hash. It may make more sense to cleanup your input
// to avoid negative zeros than to use a custom hash function.
sdbm_float_hash :: inline (f: *float, count: int, h := HASH_INIT) -> u32 {
    for 0..count-1 #no_abc #no_aoc {
        x : union { f:float; u:u32; };
        x.f = f[it];
        if x.u == 0x80000000 x.u = 0;
        h = inline sdbm_hash(*x, 4, h);
    }

    return h;
}

djb2_hash :: (s: string) -> u32 {
    // djb2 hash.
    // People seem to like this, but it seems pretty sequential
    // for asset strings we often see. For example, if you
    // have the asset names "foo1", "foo2", "foo3", these
    // will all hash to sequential slots, because they only differ
    // in the last character and those characters are sequential!
    
    hash := HASH_INIT;

    for 0..s.count-1 #no_abc #no_aoc {
        hash = ((hash << 5) + hash) + s[it];    // hash * 33 + c
    }

    return hash;
}

// FNV-1a hash: http://www.isthe.com/chongo/tech/comp/fnv/index.html
// It provides pretty good distribution and performance.  Not as good
// as Knuth for single values, but chains better for repeated hashing.
// It should be xor folded to the desired range rather than shifted.
FNV_64_PRIME        : u64 : 0x100000001b3;
FNV_64_OFFSET_BIAS  : u64 : 0xcbf29ce484222325;

fnv1a_hash :: inline (val : u64, h := FNV_64_OFFSET_BIAS) -> u64 #no_aoc {
    h ^= val;
    return h * FNV_64_PRIME;
}

fnv1a_hash :: (data: *void, size: int, h := FNV_64_OFFSET_BIAS) -> u64 {
    for 0..size-1 #no_abc #no_aoc { 
        h = fnv1a_hash((cast(*u8)data)[it], h);
    }
    
    return h;
}

// Knuth multiplicative 64-bit hash.  Should be down-shifted to desired
// range rather than masked.
knuth_hash :: inline (x : u64) -> u64 #no_aoc {
    KNUTH_GOLDEN_RATIO_64 :: 11400714819323198485;
    return KNUTH_GOLDEN_RATIO_64 * x;
}

// A default get_hash for many basic data types:
get_hash :: (x : $T, h := HASH_INIT) -> u32
#modify {
    ti := cast(*Type_Info) T;

    while ti.type == .VARIANT {
        tiv := cast(*Type_Info_Variant) ti;
        ti = tiv.variant_of;
    }
    
    if ti.type == .INTEGER return true;    // Accept integers.
    if ti.type == .BOOL    return true;    // Accept booleans.
    if ti.type == .ENUM    return true;    // Accept enums.
    if ti.type == .POINTER return true;    // Accept pointers.
    if ti.type == .FLOAT   return true;    // Accept floats.
    return false;                          // Reject anything else.
}
{
    // For hashing integers, Knuth hash seems substantially better
    // than sdbm for large tables with lots of potential collisions.
    // Also it's a lot faster, so, we are going with that for now.

    #if (T == float32) || (T == float64) {
        // Unlike sdbm_float_hash, does not tweak contents.
        return inline sdbm_hash(*x, size_of(T), h);
    } else {
        return cast(u32)(knuth_hash((cast,no_check(u64) x) ^ h) >> 32);
    }
}

get_hash :: (s: string, h := HASH_INIT) -> u32 {
    return cast,trunc(u32) inline fnv1a_hash(s.data, s.count, h);
}

get_hash :: (array: [] $T, h := HASH_INIT) -> u32 {
    return inline sdbm_hash(xx array.data, array.count * size_of(T), h);
}

#scope_file
HASH_INIT : u32 : 5381;
