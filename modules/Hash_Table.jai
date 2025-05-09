/*

A simple hash table.

Notes Last Updated: 11 May 2022

# Overview

This hash table stores all entries in a contiguous array, for good performance when
looking things up. (Some tables work by storing linked lists of entires, but this can
lead to more cache misses.)

When storing a value, we map its hash to a slot index; if that slot is free, we
put the key and value there, otherwise we just keep incrementing the slot index
by 1 until we find an empty slot. Because the table can never be full, we are
guaranteed to find a slot eventually.

When looking up a value, we perform this same process to find the correct slot.

We use hash values to indicate whether slots are empty or removed, because we can't
really know that based on keys or values, given that keys or values can be of arbitrary
type.

A hash of 0 means that slot is not used, so new values can be put there. A hash of 1
means that slot was once valid, but has since been removed. A hash of 2 or higher
(`FIRST_VALID_HASH`) means this is a currently live entry.

Whenever we hash a key, if the result is less than 2, we just add 2 to it
to put it into the valid range. This means that four values out of our 32-bit hash range
have a doubled probability of collision, but that is a small price to pay.

You can iterate over the table straightforwardly:

    for table {
        key, value := it_index, it;
    }

*/


/*

By way of explaining why it's all good and okay for this hash table to be so simple,
we'll quote Charles Bloom, who said in 2017:

-----
The last time I looked at hashing, my main conclusions were :

1. A properly loaded (eg. not too full (eg. less than 70% or so)) hash
table satisfies almost all queries in the first slot.

(I think any statistics or testing of open-address hashing at more than 70%
full is not helpful.)

2. Because of #1, what you do after the first probe is almost
irrelevant.  The only exception to this is if you have some bad degeneracy
in your hash function or data, in which case anything you can do to break
that degeneracy is a useful difference.  The simplest (and therefore best)
seems to be quadratic probing.

3. Because of #1, storing your data compactly, like {Hash,Key,Data} is
best, because you always take exactly one cache miss per query.  There are
some advantages to doing Hash-Hash-Hash, Key-Key-Key, but doing that
naively means a much higher constant # of cache misses.  (I've seen a lot
of hash table implementations that use multiple arrays;
eg. khash and google's, and that's just totally wrong.)

4. Because of #1, any prefetching was a lose.  After you compute the hash,
you need that first line immediately, so there's no time for a prefetch.
And then you need the second line so rarely that a prefetch doesn't help.

5. Because of #1, Cuckoo hashing is strictly worse, since it needs 2 cache
lines instead of 1.

6. Because of #1, the hash function is at least as important as the lookup
method.  The hash function probably takes more clocks.


The only time to ever look at hash table speed is if you are memory
constrained.  If you're not, then hey just make it bigger and it also gets
faster.  So given that you are memory constrained, you always have to trade
off against things like making the key/data smaller or omitting one or two
of hash/key/data.  eg. if hash/key/data can be 8 bytes or 12 bytes instead
of 16, you can run the table much less full in the same memory.

*/


/*
This hash table started life as some code in C by Sean Barrett, but it's
been changed so much that it's probably no longer recognizable.

For some evidence that this table is reasonably fast, even for large table sizes,
see jai/examples/hash_table_test.jai. We maybe should put that test here,
but I didn't want to bloat the file. There is also some additional
documentation there about how we handle collisions in this table,
and why.
*/

#module_parameters (COUNT_COLLISIONS := false)();

// A hash table that maps keys to values using 32 bit hashes.
Table :: struct (Key_Type: Type, Value_Type: Type,
                 given_hash_function: (Key_Type) -> u32 = null,
                 given_compare_function: (Key_Type, Key_Type) -> bool = null,
                 LOAD_FACTOR_PERCENT: u32 = 70,
                 REFILL_REMOVED := true
                ) {
    // If you leave compare_function null, the table will use
    // operator ==.

    count:        int;   // The number of valid items in the table.

    allocated:    int;   // The number of slots for which we have allocated memory.
    slots_filled: int;   // The number of slots that can't be used for new items (either currently valid items or items that were removed).

    allocator:      Allocator;

    Entry :: struct {
        hash:  u32;
        key:   Key_Type;
        value: Value_Type;
    }

    entries: [] Entry;

    // We either use the hash function that was passed to us, or,
    // if it was null, we use a default one.
    #if given_hash_function {
        hash_function :: given_hash_function;
    } else {
        hash_function :: x => Hash.get_hash(x);
    }

    // Same situation with the compare function.
    #if given_compare_function {
        compare_function :: given_compare_function;
    } else {
        compare_function :: (a: Key_Type, b: Key_Type) -> bool { return a == b; };
    }

    #if COUNT_COLLISIONS {
        add\_collisions: s64;
        find_collisions: s64;
    }

    SIZE_MIN :: 32;
}


for_expansion :: (table: *$T/Table, body: Code, flags: For_Flags) #expand {
    #assert(!(flags & .REVERSE)); // We don't handle the reverse flag.

    for * entry, i: table.entries {
        if entry.hash < FIRST_VALID_HASH  continue;

        #if flags & .POINTER {
            `it := *entry.value;
        } else {
            `it := entry.value;
        }

        `it_index := entry.key;

        #insert (remove={entry.hash=REMOVED_HASH; table.count-=1;}) body;
    }
}


// Initialize a `Table` and allocates the given number of slots.
// You don't have to call init; if you don't, you'll get
// an initial table of size `SIZE_MIN`.

init :: (using table: *Table, slots_to_allocate: s64 = 0) {
    Basic.remember_allocators(table);

    resize(table, slots_to_allocate);
}

resize :: (using table: *Table, slots_to_allocate: s64 = 0) {
    if slots_to_allocate == 0 slots_to_allocate = SIZE_MIN;
    n := next_power_of_two(slots_to_allocate);
    table.allocated = n;

    // Right now we align to 8 bytes. Should we handle arbitrary alignment of both
    // keys and values? Maybe, but that will complicate the table,
    // so let's not worry about it now unless we need it.

    // We used to create entries[] uninitialized for performance reasons,
    // but this led to problems when people would for example try to assign
    // hash tables containing strings to global data; the compiler would
    // try to copy the uninitialized strings and crash (because it has no way
    // to know they are uninitialized). For now we will go back to zero-initializing
    // by putting 'true' here, but I don't love this.  -jblow, 24 November 2024.
    entries = Basic.NewArray(n, Entry, true,, table.allocator);
    for * entries  it.hash = 0;
}

// Frees the memory allocated by the table.
deinit :: (table: *Table) {
    Basic.free(table.entries.data,, table.allocator);
}

// This reset keeps the current number of allocated slots;
// it just clears occupancy.
// @@ IC: I like this behavior, but array_reset frees memory and that is confusing. See array_reset for more discussion.
table_reset :: (using table: *Table) {
    count        = 0;
    slots_filled = 0;
    for * entries  it.hash = 0;
}

//
// Walk_Table is a macro that factors out the details of traversing the hash table,
// so that they can be re-used by multiple routines without having to keep these details
// in sync. We expect the calling site to define:
//
//    table: Table;
//    key:   table.Key_Type;
//
// We write back into the caller:
//
//    hash:  u32;
//    index: u32;
//    table_while_loop: iterator variable you can use to 'continue', etc.
// Walk_Table is intended for our own internal use. User-level traversal should
// probably use the for_expansion.
//
Walk_Table :: (code: Code) #expand {
    mask := cast,trunc(u32)(`table.allocated - 1);

    `hash := `table.hash_function(`key);
    if hash < FIRST_VALID_HASH  hash += FIRST_VALID_HASH;

    `index := hash & mask;

    // We use the 'triangular numbers' version of quadratic probing.
    // It yields more collisions per insertion than double hashing
    // (double hashing gives us 0.74, triangular numbers give us 0.84)
    // but the collisions are cheaper because the initial probes
    // are cache-coherent, unlike with double hashing. At large table sizes
    // this ends up mattering substantially. (examples/hash_table_test.jai,
    // at the 128 million entry table size, takes 15.5 seconds with triangular
    // numbers, 17.8 seconds with double hashing.)

    // Triangular numbers are guaranteed to hit every entry in the table:
    // https://fgiesen.wordpress.com/2015/02/22/triangular-numbers-mod-2n/

    probe_increment : u32 = 1;

    // If table.entries[index] is zero, that slot is unoccupied, so we are done walking.
    // If it's nonzero, we do whatever the caller wants to do (for example, check whether
    // it is the entry we are looking for).
    while `table_while_loop := `table.entries[index].hash {
        #insert code;   // Do whatever the caller wants to do for this slot index.

        index = (index + probe_increment) & mask;    // Since table.allocated is always power of two, the & wraps our index within the table. (Requires that probe_increment is not big enough to wrap index into negative numbers, which it won't be because it's u32 and index is s64.);
        probe_increment += 1;
    }
}


// table_ensure_space
//
// Call this if you want to be able to add 'items' number of things to the table without the table
// resizing in the middle. Useful in cases where you want to add multiple items to a table inside
// one block of code, while keeping pointers to those items, and wanting those pointers to remain valid.
table_ensure_space :: (table: *Table, items: s64) {
    if (table.slots_filled + items)*100 >= table.allocated*table.LOAD_FACTOR_PERCENT  expand(table);
}


// table_add
//
// Adds the given key value pair to the table, returns a pointer to the inserted value.
// If you add a key twice, the table will not currently notice that this has happened,
// so you'll just get the first one. It's unclear whether we should assert on this;
// it sort of depends on how slow you think key comparison might be. Maybe that should
// be a compile-time parameter to the hash table?   -jblow, 8 September 2020
table_add :: (table: *Table, key: table.Key_Type, value: table.Value_Type) -> *table.Value_Type {
    // The + 1 is here to handle the weird case when the table size is 1 and you add the first item...
    // If we just do table_count * 2 >= table.allocated, we would fill the table, causing an infinite loop on find.

    #assert table.LOAD_FACTOR_PERCENT < 100;  // A 100% full table will infinite loop (and you will want to be substantially smaller than this for reasonable performance).

    // Without dividing, we want to test:
    //    (filled / allocated >= 70/100)
    // Therefore, we say
    //    (filled * 100 >= allocated * 70)

    if (table.slots_filled + 1)*100 >= table.allocated*table.LOAD_FACTOR_PERCENT  expand(table);

    Basic.assert(table.slots_filled < table.allocated);

    Walk_Table(#code {
        #if table.REFILL_REMOVED {
            if table.entries[index].hash == REMOVED_HASH {
                table.slots_filled -= 1;  // 1 will get re-added below, for total increment 0.
                break;
            }
        }

        #if COUNT_COLLISIONS  table.add_collisions += 1;
    });

    // Walk_Table walked us to an unused entry, so, add our new data into this slot.

    table.count        += 1;
    table.slots_filled += 1;

    entry := *table.entries[index];
    entry.hash  = hash;
    entry.key   = key;
    entry.value = value;

    return *entry.value;
}

// table_set
//
// Adds or replaces the given key value pair.
table_set :: (table: *Table, key: table.Key_Type, value: table.Value_Type) -> *table.Value_Type {
    value_ptr := table_find_pointer(table, key);
    if value_ptr {
        value_ptr.* = value;
        return value_ptr;
    } else {
        return table_add(table, key, value);
    }
}

// table_contains
//
// Returns whether a table contains key. Useful when table is being used as a set.
table_contains :: (table: *Table, key: table.Key_Type) -> bool {
    return table_find_pointer(table, key) != null;
}


// Lookup the given key and return a pointer to the corresponding value.
// If multiple values are added with the same key, we return the first match.
// If you think you might have key collisions, use table_find_multiple.

// We now take 'table' by pointer so that if COUNT_COLLISIONS, we can modify
// the collision count, which is stored on the table. If we stored it elsewhere
// this would no longer be necessary (but might be slower?)  - 8 July 2022
table_find_pointer :: (table: *Table, key: table.Key_Type) -> *table.Value_Type {
    if !table.allocated  return null;

    Walk_Table(#code {
        entry := *table.entries[index];
        if entry.hash == hash {
            if inline table.compare_function(entry.key, key)  return *entry.value;
        }

        #if COUNT_COLLISIONS  table.find_collisions += 1;
    });

    return null;
}

// Lookup the given key and return the corresponding value.
//
// You need to pay attention to 'success' because if it's false,
// the return value will be uninitialized. Thus the `#must`.
//
// See the note on table_find_pointer about collisions and about
// why 'table' is being passed by pointer.
table_find :: (table: *Table, key: table.Key_Type) -> (table.Value_Type, success: bool #must) {
    pointer := inline table_find_pointer(table, key);
    if pointer  return pointer.*, true;

    dummy: table.Value_Type = ---;
    return dummy, false;
}

// Warning: table_find_multiple has not yet been tested.
table_find_multiple :: (table: *Table, key: table.Key_Type) -> [] table.Value_Type /* Allocated with the temporary allocator! */ {
    if !table.allocated  return .[];

    results: [..] table.Value_Type;
    results.allocator = Basic.temporary_allocator;

    Walk_Table(#code {
        entry := *table.entries[index];
        if entry.hash == hash {
            if inline table.compare_function(entry.key, key) {
                Basic.array_add(*results, entry.value);
            } else {
                #if COUNT_COLLISIONS  table.find_collisions += 1;
            }
        } else {
            #if COUNT_COLLISIONS  table.find_collisions += 1;
        }
    });

    return results;
}


//
// End of deprecated routines.
//

// Remove the first entry at the given key. Returns false if the key was not found.
table_remove :: (table: *Table, key: table.Key_Type) -> (success: bool, value: table.Value_Type) {
    if !table.allocated {
        dummy: table.Value_Type;
        return false, dummy;  // Empty table, means not found!
    }

    Walk_Table(#code {
        entry := *table.entries[index];

        if (entry.hash == hash) && inline table.compare_function(entry.key, key) {
            entry.hash = REMOVED_HASH;  // No valid entry will ever hash to REMOVED_HASH.
            table.count -= 1;
            return true, entry.value;
        }
    });

    dummy: table.Value_Type;
    return false, dummy;
}


// find_or_add is kind of like table_set, but used when you
// just want a pointer to the value, which you can fill in.
find_or_add :: (table: *Table, key: table.Key_Type) -> (entry: *table.Value_Type, newly_added: bool) {
    value := table_find_pointer(table, key);
    if value return value, false;

    new_value: table.Value_Type;
    value = table_add(table, key, new_value);
    return value, true;
}


// We expose these reserved hash values just in case you want
// to write your own hash table iterator.
NEVER_OCCUPIED_HASH :: 0;
REMOVED_HASH        :: 1;
FIRST_VALID_HASH    :: 2;

// A beta user requested being able to call expand(), so, here:
expand :: (table: *Table) {
    old_entries := table.entries;

    // If we were adding and removing lots of stuff from the table,
    // we might have lots of slots filled with REMOVED_HASH, so,
    // in that case, don't grow!
    new_allocated: s64 = ---;

    if (table.count * 2 + 1) * 100 < table.allocated * table.LOAD_FACTOR_PERCENT {  // The *2 is to say, if we double the size, are we still small enough to fit into the current memory? The reason we are doing this test is, if we removed a bunch of elements, maybe we are full of REMOVED_HASH markers, and if we just rehash to the same size, we can get rid of those. An alternate version (simpler?) might be to check table.count vs table.slots_filled. Note that this becomes less necessary if REFILL_REMOVED is enabled.
        // Just go with the current size, but clean out the removals.
        new_allocated = table.allocated;
    } else {
        // We need to go deeper!
        new_allocated = table.allocated * 2;
    }

    if new_allocated < table.SIZE_MIN  new_allocated = table.SIZE_MIN;

    resize(table, new_allocated);

    table.count        = 0;   // count and slots_filled will be incremented by table_add.
    table.slots_filled = 0;

    for * entry, index: old_entries {
        // Note that if we removed some stuff, we will over-allocate the next table.
        // Maybe we should count the number of clobbers and subtract that. I dunno.
        if entry.hash >= FIRST_VALID_HASH  table_add(table, entry.key, entry.value);
    }

    Basic.free(old_entries.data,, table.allocator);
}

next_power_of_two :: inline (x : int) -> int {
    // @Speed: This could certainly be faster.
    // There is probably something in Hacker's Delight for this.
    Basic.assert(x != 0);
    p := 1;
    while x > p p += p;
    return p;
}

#scope_file

Hash  :: #import "Hash";
Basic :: #import "Basic";
