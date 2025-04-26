/*

This is a very simple random number generator of the MCG type.

It is from the "Today's 64-bit Minimal Standard" section of https://www.pcg-random.org/posts/does-it-beat-the-minimal-standard.html.

*/

random_get :: (state : *Random_State) -> u64 #no_aoc {
    FACTOR_HIGH : u64 : 0x0fc9_4e3b_f4e9_ab32;
    FACTOR_LOW  : u64 : 0x8664_58cd_56f5_e605;

    // A 128-bit multiply.
    // @Copypasta from modules/Basic/Apollo_Time.jai, but probably worth having
    // separately here so as not to create a dependency.
    // We can re-evaluate this as code gets big.
    //
    // All we are doing here is:
    //
    //     state = state * FACTOR;
    //
    // where 'state' and 'FACTOR' are 128-bit unsigned integers.
    //

    p := state;

    #if CPU == .X64 {
        #asm {
            result_high: gpr === d;
            result_low:  gpr === a;

            factor:   gpr;
            high_sum: gpr;
            low_storage: gpr;  // Hold this until we are ready to write it out.

            // Low times low:
            mov result_low, [p + 0];  // This is input as well as result.
            mov factor,     FACTOR_LOW;

            mul result_high, result_low, factor;

            mov low_storage, result_low;  // Hold onto this for a while, please.
            mov high_sum, result_high;    // Store the high part.

            // High a times low b. 'factor' still holds low b.
            mov result_low, [p + 8];
            mul result_high, result_low, factor;
            add high_sum, result_low;

            // Low a times high b.
            mov result_low, [p + 0];
            mov factor,     FACTOR_HIGH;
            mul result_high, result_low, factor;
            add high_sum, result_low;

            // High a times high b is discarded.

            mov [p + 8], high_sum;
            mov [p + 0], low_storage;
        }
    } else {
        Basic :: #import "Basic"; // For multiply_64bits_with_overflow

        mul64_high, mul64_low := Basic.multiply_64bits_with_overflow(p.low, FACTOR_LOW);

        p.high = mul64_high + (p.high * FACTOR_LOW) + (p.low * FACTOR_HIGH);
        p.low  = mul64_low; // Don't put this before p.high, as p.high uses the old value of p.low.
    }

    return p.high;
}

random_get :: inline () -> u64 {
    return random_get(*context.random_state);
}

random_seed :: inline (state : *Random_State, new_seed : u64) {
    // The only requirement is that the seed be odd.
    // If you only give us 1 u64 (which we support for ease-of-use reasons)
    // we will just put a 1 in the bottom slot, so it's odd.

    state.low  = 1;
    state.high = new_seed;
}

random_seed :: inline (new_seed : u64) {
    random_seed(*context.random_state, new_seed);
}

random_seed :: inline (state : *Random_State, new_seed: Random_State) {
    // If you want to do the big seed.

    state.low = new_seed.low | 1; // Low must be an odd number.
    state.high = new_seed.high;
}

random_seed :: inline (new_seed : Random_State) {
    random_seed(*context.random_state, new_seed);
}

// It's often useful to get a floating-point number in the range [0, 1].
random_get_zero_to_one :: inline (state : *Random_State) -> float {
    randint := random_get(state) & MASK;
    return randint / cast(float) MASK;
}

random_get_zero_to_one :: inline () -> float {
    return random_get_zero_to_one(*context.random_state);
}

// This one gives a floating-point number in the range [0, 1).
random_get_zero_to_one_open :: inline (state : *Random_State) -> float {
    randint := random_get(state) & MASK;
    return randint / cast(float) RANDRANGE;
}

random_get_zero_to_one_open :: inline () -> float {
    return random_get_zero_to_one_open(*context.random_state);
}

//
// New versions that give us full float precision; we may
// upgrade to these by default later:
//
random_get_zero_to_one_new :: (state: *Random_State) -> float64 #no_aoc {
    #import "Bit_Operations";
    
    union {
        d: float64;
        x: u64;
    };

    ctz :: inline (x: u64) -> s32 {
        result := bit_scan_forward(x);
        if result == 0  return 64;
        return result-1;
    }
    
    x = random_get(state);
    e := ctz(x) - 11;
    
    if e >= 0 e = ctz(random_get(state));

    x = (((x >> 11) + 1) >> 1) - ((cast,no_check(u64)e - 1011) << 52);
    
    return d;
}

random_get_zero_to_one_new :: inline () -> float64 {
    return random_get_zero_to_one_new(*context.random_state);
}

random_get_zero_to_one_open_new :: (state: *Random_State) -> float64 {
    u := random_get(state) >> 11;
    return u * 0h3ca0_0000_0000_0000;  // This is 1.0p-53

    // esert: @j_blow if you only care about [0,1) range, you can do (random_u64() >> 40) * (0x1.0p-24f), search for float in https://prng.di.unimi.it/

    // If we wanted 32-bit floats (also need to change the shift):
    // return u * 0h33800000;  // This is 1.0p-24
}

random_get_zero_to_one_open_new :: inline () -> float64 {
    return random_get_zero_to_one_open_new(*context.random_state);
}


// It's often useful to get a floating-point number in some floating-point range [min, max].
random_get_within_range :: inline (state : *Random_State, min: float, max: float) -> float {
    // We allow min and max to be flipped, no big whoop.

    randint := random_get(state) & MASK;
    addition := (randint / cast(float) MASK) * (max - min);

    result := min + addition;

    // Deal with floating-point inaccuracy (@Speed: Can this actually happen?)
    if result > max  result = max;
    if result < min  result = min;

    return result;
}

random_get_within_range :: inline (min: float, max: float) -> float {
    return random_get_within_range(*context.random_state, min, max);
}

Random_State :: struct {
    low : u64;
    high : u64;
}

#scope_file

RANDRANGE : u32 : 1 << 24;  // Not using all the bits for stuff like float divides, because we start losing accuracy due to the max representable integer. Maybe could be smarter than this. Must be a power of two for MASK to work. The highest exactly-representable integer in float32 is 2**24.
MASK :: RANDRANGE - 1;
#assert (RANDRANGE & MASK) == 0;

// Obviously, we picked an arbitrary number for state.
// State must be relatively prime with the modulus, which is 0x7fff_ffff.
#add_context random_state := Random_State.{1, 0};

/*
// Here is a simple program you could compile to convince yourself you are getting resonable numbers.
// It calls random_get() and sums up how many times each bit in the result was set. This is not
// a sophisticated statistical test; for that you'd want a spectral random number test. Still,
// this is something basic you can use to know things are not completely broken.

#scope_export

main :: () {
    #import "Basic";
    #import "Random";

    bit_counts: [64] int;

    ITERATIONS :: 10000;

    for 1..ITERATIONS {
        r := random_get();

        for bit_index: 0..63 {
            bit := cast(u64) 1 << bit_index;
            if r & bit  bit_counts[bit_index] += 1;
        }
    }

    for bit_counts print("[%] %\n", it_index, it);
}
*/
