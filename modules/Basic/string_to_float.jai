// The code in this file parses strings to yield floating-point numbers.
// Solving this problem exactly for arbitrarily large input strings can be very
// difficult and slow, involving arbitrary-precision math. The convention in recent
// years has been that programming language libraries handle these cases, because
// it's the "right answer", even though almost nobody is ever going to call a
// function like this on a 50,000-character input.
//
// The code below doesn't try to do that. It should round-trip correctly with
// any output of any other correct system that prints enough digits to uniquely
// identify the floating-point number. If there are many more digits than that,
// then in some cases, it may round incorrectly, giving you a 1 ULP error.
//
// Do we want to fix this in the long term? I am not sure. On the one hand,
// the principle of least surprise says that the code should just do what you
// ask it to do, and not have weird constraints like this. On the other hand,
// if the resulting code is much more complicated, it incurs a burden on
// everyone every time they compile and link the code, and, it makes the
// source code less friendly, harder to read, and more like a scary thing
// that lives in the basement and we never want to go down there.
// And, long term, this kind of feeling is a big part of what's wrong with
// software. So maybe the correct bigger-picture decision is to live with
// the 1 ULP error on weird inputs that "nobody" is ever going to use. I am
// not sure.                             -jblow, 29 June 2020

// string_to_float is just calling string_to_float64 and then rounding. This is I guess not correct
// for some edge cases, as you can get the wrong answer due to double-rounding. Eventually we will
// want to fix this.
string_to_float :: (arg: string) -> (result: float, success: bool, remainder: string) {
    result64, success, remainder := string_to_float64(arg);
    return cast(float) result64, success, remainder;
}



//
// string_to_float64 and multiply_and_convert_to_float are translated from the dtoa-fast library
// by Albert Chan. You can see the copyright and license information in
// copyrights.txt.
//

// We picked this library because it looked reasonable, but did not
// perform an exhaustive survey.
// Here's an alternative library that may possibly be faster,
// but that also falls back to libc (ugh) for hard cases:
//     https://github.com/lemire/fast_double_parser

string_to_float64 :: (_s: string) -> (result: float64, success: bool, remainder: string) #no_abc {
    s := eat_spaces(_s);
    if !s return 0, false, "";

    n := 0;

    neg: s32;
    if      s[n] == #char "-" { n += 1; neg = 0x800; }
    else if s[n] == #char "+" { n += 1; }

    lz: s32;
    while (n < s.count) && (s[n] == #char "0") {      // Skip leading zeroes.
        n  += 1;
        lz += 1;
    }

    m, bot: u64;
    digits, nexp: s32;
    len := s.count;

    while n < len {         // Digits before the decimal point.
        c := s[n];
        if c < #char "0" break;
        if c > #char "9" break;

        if digits >= 19 {
            if digits == 28 { n += 1; nexp += 1; continue; }
            if digits == 19 { bot=m>>32; m &= 0xffff_ffff; }
        }

        m = 10 * m + (c - #char "0");
        digits += 1;

        n += 1;
    }

    all_digits := lz + digits;

    if (n < len) && (s[n] == #char ".") {     // Digits after the decimal point.
        nexp += all_digits;

        n += 1;

        if !digits {           // Leading zeroes again.
            while (n < len) && (s[n] == #char "0") { n += 1; lz += 1; }
        }

        while n < len {
            c := s[n];
            if c < #char "0" break;
            if c > #char "9" break;

            if digits >= 19 {
                if digits == 28 { n += 1; continue; }
                if digits == 19 { bot=m>>32; m &= 0xffff_ffff; }
            }

            m = 10 * m + (c - #char "0");
            digits += 1;

            n += 1;
        }

        all_digits = lz + digits;
        nexp -= all_digits;
    }

    if all_digits == 0 {   // We got no valid characters that could start a floating-point number.
        return 0, false, _s;
    }

    if (n < len - 1) && ((s[n]|32) == #char "e") { // Build nexp, the base-10 exponent of the number.
        // We checked against len-1 above, so that we can do the q check here without worrying too much.
        // If e is the last digit, it's not valid!
        q := n + 1;
        sign: s32 = 1;

        if      s[q] == #char "-" { q += 1; sign = -1; }
        else if s[q] == #char "+" { q += 1; }

        if (q < len) && (s[q] >= #char "0") && (s[q] <= #char "9") {      // valid nexp
            n = q + 1;
            d : s32 = s[q] - #char "0";

            while (n < len) && (s[n] >= #char "0") && (s[n] <= #char "9") {
                if d < 100000000  d = 10 * d + s[n] - #char "0";  // This seems weird... we cap d instead of letting it overflow/etc. Maybe because we know we will output Inf when it is this high?
                n += 1;
            }

            nexp += sign * d;
        }
    }

    remainder := advance(s, n);

    if !digits return (ifx neg then -0.0 else 0.0), true, remainder;

    if !INRANGE(digits + nexp, EXP_MIN, EXP_MAX) {
        if nexp <= 0   return (ifx neg then -0.0 else 0.0), true, remainder;

        return (ifx neg then  -FLOAT64_INFINITY else FLOAT64_INFINITY), true, remainder;
    }

    binary_leading_zeroes: s32;
    bexp: s32;

    skip := false;
    if digits == {
        case 20; bot *= 10;
        case 21; bot *= 100;
        case 22; bot *= 1000;
        case 23; bot *= 10000;
        case 24; bot *= 100000;
        case 25; bot *= 1000000;
        case 26; bot *= 10000000;
        case 27; bot *= 100000000;
        case 28; bot *= 1000000000;
        case;
        binary_leading_zeroes = clz64(m);
        m = m << binary_leading_zeroes;          // under 64 bits
        bexp = 64 + BIAS - binary_leading_zeroes;
        skip = true;
    }

    if !skip {
        top := bot + (m >> 32);
        binary_leading_zeroes = clz32(cast(u32)(top>>32));
        bot = m << 32 >> (32-binary_leading_zeroes);         // bot 32 bits
        m = (top << binary_leading_zeroes) | (bot >> 32);    // top 64 bits
        bexp = 96 + BIAS - binary_leading_zeroes;
    }

    result := multiply_and_convert_to_float(m, cast,trunc(u32) bot, bexp, nexp, neg);
    return result, true, remainder;
}

#scope_file

multiply_and_convert_to_float :: (m: u64, bot: u32, bexp: s32, i: s32, neg: s32) -> float64 {
    // This was called "strtod_cvt" in the original code.

    n2 := cast(u32)(m >> 32);  // top    32 bits
    n1 := cast,trunc(u32) m;   // middle 32 bits
    n0 := bot;                 // bottom 32 bits

    n2, n1, n0, bexp = MUL_96(n2,n1,n0,bexp, i);

    bot = n0;
    if cast,no_check(u32) bexp >= 2046 {    // not normal range
        if bexp >= 2046 return ifx neg then -FLOAT64_INFINITY else FLOAT64_INFINITY;

        // If we got here, bexp is negative... kinda gross.
        i = -bexp;  // Thus i becomes positive.
        bexp = 0;

        tail := ((cast(u64) n1) << 32 | n0) >> i;
        tail |= (cast(u64) n2) << (64-i);
        n0 = cast,trunc(u32) tail;
        n1 = cast(u32)(tail >> 32);
        n2 = n2 >> i;
    }

    if bot == 0 {
        if (n1 & 0xfff) == 0x400 {     // round 01000 ...
            // ULP :: 0;   // assumed halfway
            // #define FIX_0x400(r)  r += ULP() - 1
            // if n0 == 0 FIX_0x400(n1);

            // :PreciseRounding
            // If I understand correctly, these cases marked :PreciseRounding
            // represent the only points at which this code gives up and potentially
            // yields the incorrect rounding. At these two points, we could call
            // into an arbitrary-precision routine to yield the answer. (I believe
            // the original dtoa-fast uses MAPM in this case to get the right
            // answer, but we don't do that here).   -jblow, 29 June 2020

            if n0 == 0 n1 -= 1;
        }
    } else if bot > HOLE {
        if (n1 & 0x7ff) == 0x3ff {     // round ?0111 ...
            // #define FIX_0x3ff(r)  r += ULP() + !!(n1&0x800)
            // if n0 > HOLE FIX_0x3ff(n1);

            // :PreciseRounding
            // See above!
            if n0 > HOLE {
                if n1 & 0x800  n1 += 1;
            }
        }
    }

    u: HexDouble;
    u._u64 = ((n1 >> 10) + 1) >> 1;
    u._u64 += ((cast(u64)(neg|bexp))<<52) + ((cast(u64) n2)<<21);

    return u._float64;
}


//
// The code below is a fast 96-bit multiply, from MAPM version 4.9.5a,
// by Michael C. Ring. MAPM is a fairly extensive library, and we only
// extracted the part we need here. See copyrights.txt for the copyright info,
// as well as Michael's contact information.
//
// The license for the code requires that I also include this comment:
//

/*
 *   THE FILE CONTENTS BELOW HAVE BEEN MODIFIED FROM THE OFFICIAL MAPM DISTRIBUTION
 *   BY Jonathan Blow on 29 June, 2020.
 *
 *   THIS CODE IS ORIGINALLY FROM MAPM VERSION 4.9.5.
 *
 */


// Make a struct for (n2, n1, n0, bexp)? It would make all this a lot more readable.
// But, we only use two of these functions for now, so it actually doesn't matter much.
// But if we use more of MAPM eventually, this may become more of an issue, and it'd be
// worth seeing if there is a performance degradation due to using structs for the numbers.
// It would be a good test of the compiler to ensure that it doesn't make the code any slower.

MUL_96 :: inline (n2: u32, n1: u32, n0: u32, bexp: s32, i: s32) -> (r2: u32, r1: u32, r0: u32, rexp: s32) {
    c :: fast_bf96;
    base := (i+351)*3;

    // max(c[0]) = 0xffbbcfe9 < 0xffffffff
    // -> c[0]*n1 + 3 (x0 >> 32) under 64 bits

    c0 : u64 = c[base];
    c1 : u64 = c[base+1];
    c2 : u64 = c[base+2];

    x0 := c0 * n0;
    x1 := c0 * n1;
    x2 := c0 * n2;

    x1 += x0 >> 32; x0 = (cast,trunc(u32)x0) + c1 * n1;
    x1 += x0 >> 32; x0 = (cast,trunc(u32)x0) + c2 * n2;
    x1 += x0 >> 32;
    x2 += x1 >> 32; x1 = (cast,trunc(u32)x1) + c1 * n2;
    x2 += x1 >> 32;

    delta := (i * 108853) >> 15;  // This apparently has enough precision to reproduce the correct exponent for every entry in the fast_bf96 table, so that we don't have to store those exponents in the table.

    bexp += delta;

    r2, r1, r0, rexp := NORMALIZE(n2, n1, n0, bexp, x2, x1, x0, 1);

    return r2, r1, r0, rexp;
}

NORMALIZE :: (n2: u32, n1: u32, n0: u32, bexp: s32, x2: u64, x1: u64, x0: u64, size: s32) -> (r2: u32, r1: u32, r0: u32, rexp: s32) {
    if x2 & (1<<63) {
        r2 := cast,trunc(u32) (x2 >> 32);
        r1 := cast,trunc(u32)x2;
        r0 := cast,trunc(u32)x1;
        return r2, r1, r0, bexp + size;
    } else {
        r2 := cast(u32) (x2 >> 31);
        r1 := ((cast,trunc(u32) x1) >> 31) | ((cast,trunc(u32) x2) << 1);
        r0 := ((cast,trunc(u32) x0) >> 31) | ((cast,trunc(u32) x1) << 1);
        return r2, r1, r0, bexp + size - 1;
    }
}

fast_bf96 : [691*3] u32 : u32.[   // 1E-351 to 1E339
	 0x8049a4ac, 0x0c5811ae, 0x205b896d,
	 0xa05c0dd7, 0x0f6e1619, 0xa8726bc8,
	 0xc873114c, 0xd3499ba0, 0x128f06bb,
	 0xfa8fd5a0, 0x081c0288, 0x1732c869,
	 0x9c99e584, 0x05118195, 0x0e7fbd42,
	 0xc3c05ee5, 0x0655e1fa, 0x521fac92,
	 0xf4b0769e, 0x47eb5a78, 0xe6a797b7,
	 0x98ee4a22, 0xecf3188b, 0x9028bed2,
	 0xbf29dcab, 0xa82fdeae, 0x7432ee87,
	 0xeef453d6, 0x923bd65a, 0x113faa29,
	 0x9558b466, 0x1b6565f8, 0x4ac7ca59,
	 0xbaaee17f, 0xa23ebf76, 0x5d79bcf0,
	 0xe95a99df, 0x8ace6f53, 0xf4d82c2c,
	 0x91d8a02b, 0xb6c10594, 0x79071b9b,
	 0xb64ec836, 0xa47146f9, 0x9748e282,
	 0xe3e27a44, 0x4d8d98b7, 0xfd1b1b23,
	 0x8e6d8c6a, 0xb0787f72, 0xfe30f0f5,
	 0xb208ef85, 0x5c969f4f, 0xbdbd2d33,
	 0xde8b2b66, 0xb3bc4723, 0xad2c7880,
	 0x8b16fb20, 0x3055ac76, 0x4c3bcb50,
	 0xaddcb9e8, 0x3c6b1793, 0xdf4abe24,
	 0xd953e862, 0x4b85dd78, 0xd71d6dad,
	 0x87d4713d, 0x6f33aa6b, 0x8672648c,
	 0xa9c98d8c, 0xcb009506, 0x680efdaf,
	 0xd43bf0ef, 0xfdc0ba48, 0x0212bd1b,
	 0x84a57695, 0xfe98746d, 0x014bb630,
	 0xa5ced43b, 0x7e3e9188, 0x419ea3bd,
	 0xcf42894a, 0x5dce35ea, 0x52064cac,
	 0x818995ce, 0x7aa0e1b2, 0x7343efeb,
	 0xa1ebfb42, 0x19491a1f, 0x1014ebe6,
	 0xca66fa12, 0x9f9b60a6, 0xd41a26e0,
	 0xfd00b897, 0x478238d0, 0x8920b098,
	 0x9e20735e, 0x8cb16382, 0x55b46e5f,
	 0xc5a89036, 0x2fddbc62, 0xeb2189f7,
	 0xf712b443, 0xbbd52b7b, 0xa5e9ec75,
	 0x9a6bb0aa, 0x55653b2d, 0x47b233c9,
	 0xc1069cd4, 0xeabe89f8, 0x999ec0bb,
	 0xf148440a, 0x256e2c76, 0xc00670ea,
	 0x96cd2a86, 0x5764dbca, 0x38040692,
	 0xbc807527, 0xed3e12bc, 0xc6050837,
	 0xeba09271, 0xe88d976b, 0xf7864a44,
	 0x93445b87, 0x31587ea3, 0x7ab3ee6a,
	 0xb8157268, 0xfdae9e4c, 0x5960ea05,
	 0xe61acf03, 0x3d1a45df, 0x6fb92487,
	 0x8fd0c162, 0x06306bab, 0xa5d3b6d4,
	 0xb3c4f1ba, 0x87bc8696, 0x8f48a489,
	 0xe0b62e29, 0x29aba83c, 0x331acdab,
	 0x8c71dcd9, 0xba0b4925, 0x9ff0c08b,
	 0xaf8e5410, 0x288e1b6f, 0x07ecf0ae,
	 0xdb71e914, 0x32b1a24a, 0xc9e82cd9,
	 0x892731ac, 0x9faf056e, 0xbe311c08,
	 0xab70fe17, 0xc79ac6ca, 0x6dbd630a,
	 0xd64d3d9d, 0xb981787d, 0x092cbbcc,
	 0x85f04682, 0x93f0eb4e, 0x25bbf560,
	 0xa76c5823, 0x38ed2621, 0xaf2af2b8,
	 0xd1476e2c, 0x07286faa, 0x1af5af66,
	 0x82cca4db, 0x847945ca, 0x50d98d9f,
	 0xa37fce12, 0x6597973c, 0xe50ff107,
	 0xcc5fc196, 0xfefd7d0c, 0x1e53ed49,
	 0xff77b1fc, 0xbebcdc4f, 0x25e8e89c,
	 0x9faacf3d, 0xf73609b1, 0x77b19161,
	 0xc795830d, 0x75038c1d, 0xd59df5b9,
	 0xf97ae3d0, 0xd2446f25, 0x4b057328,
	 0x9becce62, 0x836ac577, 0x4ee367f9,
	 0xc2e801fb, 0x244576d5, 0x229c41f7,
	 0xf3a20279, 0xed56d48a, 0x6b435275,
	 0x9845418c, 0x345644d6, 0x830a1389,
	 0xbe5691ef, 0x416bd60c, 0x23cc986b,
	 0xedec366b, 0x11c6cb8f, 0x2cbfbe86,
	 0x94b3a202, 0xeb1c3f39, 0x7bf7d714,
	 0xb9e08a83, 0xa5e34f07, 0xdaf5ccd9,
	 0xe858ad24, 0x8f5c22c9, 0xd1b3400f,
	 0x91376c36, 0xd99995be, 0x23100809,
	 0xb5854744, 0x8ffffb2d, 0xabd40a0c,
	 0xe2e69915, 0xb3fff9f9, 0x16c90c8f,
	 0x8dd01fad, 0x907ffc3b, 0xae3da7d9,
	 0xb1442798, 0xf49ffb4a, 0x99cd11cf,
	 0xdd95317f, 0x31c7fa1d, 0x40405643,
	 0x8a7d3eef, 0x7f1cfc52, 0x482835ea,
	 0xad1c8eab, 0x5ee43b66, 0xda324365,
	 0xd863b256, 0x369d4a40, 0x90bed43e,
	 0x873e4f75, 0xe2224e68, 0x5a7744a6,
	 0xa90de353, 0x5aaae202, 0x711515d0,
	 0xd3515c28, 0x31559a83, 0x0d5a5b44,
	 0x8412d999, 0x1ed58091, 0xe858790a,
	 0xa5178fff, 0x668ae0b6, 0x626e974d,
	 0xce5d73ff, 0x402d98e3, 0xfb0a3d21,
	 0x80fa687f, 0x881c7f8e, 0x7ce66634,
	 0xa139029f, 0x6a239f72, 0x1c1fffc1,
	 0xc9874347, 0x44ac874e, 0xa327ffb2,
	 0xfbe91419, 0x15d7a922, 0x4bf1ff9f,
	 0x9d71ac8f, 0xada6c9b5, 0x6f773fc3,
	 0xc4ce17b3, 0x99107c22, 0xcb550fb4,
	 0xf6019da0, 0x7f549b2b, 0x7e2a53a1,
	 0x99c10284, 0x4f94e0fb, 0x2eda7444,
	 0xc0314325, 0x637a1939, 0xfa911155,
	 0xf03d93ee, 0xbc589f88, 0x793555ab,
	 0x96267c75, 0x35b763b5, 0x4bc1558b,
	 0xbbb01b92, 0x83253ca2, 0x9eb1aaed,
	 0xea9c2277, 0x23ee8bcb, 0x465e15a9,
	 0x92a1958a, 0x7675175f, 0x0bfacd89,
	 0xb749faed, 0x14125d36, 0xcef980ec,
	 0xe51c79a8, 0x5916f484, 0x82b7e127,
	 0x8f31cc09, 0x37ae58d2, 0xd1b2ecb8,
	 0xb2fe3f0b, 0x8599ef07, 0x861fa7e6,
	 0xdfbdcece, 0x67006ac9, 0x67a791e0,
	 0x8bd6a141, 0x006042bd, 0xe0c8bb2c,
	 0xaecc4991, 0x4078536d, 0x58fae9f7,
	 0xda7f5bf5, 0x90966848, 0xaf39a475,
	 0x888f9979, 0x7a5e012d, 0x6d8406c9,
	 0xaab37fd7, 0xd8f58178, 0xc8e5087b,
	 0xd5605fcd, 0xcf32e1d6, 0xfb1e4a9a,
	 0x855c3be0, 0xa17fcd26, 0x5cf2eea0,
	 0xa6b34ad8, 0xc9dfc06f, 0xf42faa48,
	 0xd0601d8e, 0xfc57b08b, 0xf13b94da,
	 0x823c1279, 0x5db6ce57, 0x76c53d08,
	 0xa2cb1717, 0xb52481ed, 0x54768c4b,
	 0xcb7ddcdd, 0xa26da268, 0xa9942f5d,
	 0xfe5d5415, 0x0b090b02, 0xd3f93b35,
	 0x9efa548d, 0x26e5a6e1, 0xc47bc501,
	 0xc6b8e9b0, 0x709f109a, 0x359ab641,
	 0xf867241c, 0x8cc6d4c0, 0xc30163d2,
	 0x9b407691, 0xd7fc44f8, 0x79e0de63,
	 0xc2109436, 0x4dfb5636, 0x985915fc,
	 0xf294b943, 0xe17a2bc4, 0x3e6f5b7b,
	 0x979cf3ca, 0x6cec5b5a, 0xa705992c,
	 0xbd8430bd, 0x08277231, 0x50c6ff78,
	 0xece53cec, 0x4a314ebd, 0xa4f8bf56,
	 0x940f4613, 0xae5ed136, 0x871b7795,
	 0xb9131798, 0x99f68584, 0x28e2557b,
	 0xe757dd7e, 0xc07426e5, 0x331aeada,
	 0x9096ea6f, 0x3848984f, 0x3ff0d2c8,
	 0xb4bca50b, 0x065abe63, 0x0fed077a,
	 0xe1ebce4d, 0xc7f16dfb, 0xd3e84959,
	 0x8d3360f0, 0x9cf6e4bd, 0x64712dd7,
	 0xb080392c, 0xc4349dec, 0xbd8d794d,
	 0xdca04777, 0xf541c567, 0xecf0d7a0,
	 0x89e42caa, 0xf9491b60, 0xf41686c4,
	 0xac5d37d5, 0xb79b6239, 0x311c2875,
	 0xd77485cb, 0x25823ac7, 0x7d633293,
	 0x86a8d39e, 0xf77164bc, 0xae5dff9c,
	 0xa8530886, 0xb54dbdeb, 0xd9f57f83,
	 0xd267caa8, 0x62a12d66, 0xd072df63,
	 0x8380dea9, 0x3da4bc60, 0x4247cb9e,
	 0xa4611653, 0x8d0deb78, 0x52d9be85,
	 0xcd795be8, 0x70516656, 0x67902e27,
	 0x806bd971, 0x4632dff6, 0x00ba1cd8,
	 0xa086cfcd, 0x97bf97f3, 0x80e8a40e,
	 0xc8a883c0, 0xfdaf7df0, 0x6122cd12,
	 0xfad2a4b1, 0x3d1b5d6c, 0x796b8057,
	 0x9cc3a6ee, 0xc6311a63, 0xcbe33036,
	 0xc3f490aa, 0x77bd60fc, 0xbedbfc44,
	 0xf4f1b4d5, 0x15acb93b, 0xee92fb55,
	 0x99171105, 0x2d8bf3c5, 0x751bdd15,
	 0xbf5cd546, 0x78eef0b6, 0xd262d45a,
	 0xef340a98, 0x172aace4, 0x86fb8971,
	 0x9580869f, 0x0e7aac0e, 0xd45d35e6,
	 0xbae0a846, 0xd2195712, 0x89748360,
	 0xe998d258, 0x869facd7, 0x2bd1a438,
	 0x91ff8377, 0x5423cc06, 0x7b6306a3,
	 0xb67f6455, 0x292cbf08, 0x1a3bc84c,
	 0xe41f3d6a, 0x7377eeca, 0x20caba5f,
	 0x8e938662, 0x882af53e, 0x547eb47b,
	 0xb23867fb, 0x2a35b28d, 0xe99e619a,
	 0xdec681f9, 0xf4c31f31, 0x6405fa00,
	 0x8b3c113c, 0x38f9f37e, 0xde83bc40,
	 0xae0b158b, 0x4738705e, 0x9624ab50,
	 0xd98ddaee, 0x19068c76, 0x3badd624,
	 0x87f8a8d4, 0xcfa417c9, 0xe54ca5d7,
	 0xa9f6d30a, 0x038d1dbc, 0x5e9fcf4c,
	 0xd47487cc, 0x8470652b, 0x7647c320,
	 0x84c8d4df, 0xd2c63f3b, 0x29ecd9f4,
	 0xa5fb0a17, 0xc777cf09, 0xf4681071,
	 0xcf79cc9d, 0xb955c2cc, 0x7182148d,
	 0x81ac1fe2, 0x93d599bf, 0xc6f14cd8,
	 0xa21727db, 0x38cb002f, 0xb8ada00e,
	 0xca9cf1d2, 0x06fdc03b, 0xa6d90811,
	 0xfd442e46, 0x88bd304a, 0x908f4a16,
	 0x9e4a9cec, 0x15763e2e, 0x9a598e4e,
	 0xc5dd4427, 0x1ad3cdba, 0x40eff1e1,
	 0xf7549530, 0xe188c128, 0xd12bee59,
	 0x9a94dd3e, 0x8cf578b9, 0x82bb74f8,
	 0xc13a148e, 0x3032d6e7, 0xe36a5236,
	 0xf18899b1, 0xbc3f8ca1, 0xdc44e6c3,
	 0x96f5600f, 0x15a7b7e5, 0x29ab103a,
	 0xbcb2b812, 0xdb11a5de, 0x7415d448,
	 0xebdf6617, 0x91d60f56, 0x111b495b,
	 0x936b9fce, 0xbb25c995, 0xcab10dd9,
	 0xb84687c2, 0x69ef3bfb, 0x3d5d514f,
	 0xe65829b3, 0x046b0afa, 0x0cb4a5a3,
	 0x8ff71a0f, 0xe2c2e6dc, 0x47f0e785,
	 0xb3f4e093, 0xdb73a093, 0x59ed2167,
	 0xe0f218b8, 0xd25088b8, 0x306869c1,
	 0x8c974f73, 0x83725573, 0x1e414218,
	 0xafbd2350, 0x644eeacf, 0xe5d1929e,
	 0xdbac6c24, 0x7d62a583, 0xdf45f746,
	 0x894bc396, 0xce5da772, 0x6b8bba8c,
	 0xab9eb47c, 0x81f5114f, 0x066ea92f,
	 0xd686619b, 0xa27255a2, 0xc80a537b,
	 0x8613fd01, 0x45877585, 0xbd06742c,
	 0xa798fc41, 0x96e952e7, 0x2c481138,
	 0xd17f3b51, 0xfca3a7a0, 0xf75a1586,
	 0x82ef8513, 0x3de648c4, 0x9a984d73,
	 0xa3ab6658, 0x0d5fdaf5, 0xc13e60d0,
	 0xcc963fee, 0x10b7d1b3, 0x318df905,
	 0xffbbcfe9, 0x94e5c61f, 0xfdf17746,
	 0x9fd561f1, 0xfd0f9bd3, 0xfeb6ea8b,
	 0xc7caba6e, 0x7c5382c8, 0xfe64a52e,
	 0xf9bd690a, 0x1b68637b, 0x3dfdce7a,
	 0x9c1661a6, 0x51213e2d, 0x06bea10c,
	 0xc31bfa0f, 0xe5698db8, 0x486e494f,
	 0xf3e2f893, 0xdec3f126, 0x5a89dba3,
	 0x986ddb5c, 0x6b3a76b7, 0xf8962946,
	 0xbe895233, 0x86091465, 0xf6bbb397,
	 0xee2ba6c0, 0x678b597f, 0x746aa07d,
	 0x94db4838, 0x40b717ef, 0xa8c2a44e,
	 0xba121a46, 0x50e4ddeb, 0x92f34d62,
	 0xe896a0d7, 0xe51e1566, 0x77b020ba,
	 0x915e2486, 0xef32cd60, 0x0ace1474,
	 0xb5b5ada8, 0xaaff80b8, 0x0d819992,
	 0xe3231912, 0xd5bf60e6, 0x10e1fff6,
	 0x8df5efab, 0xc5979c8f, 0xca8d3ffa,
	 0xb1736b96, 0xb6fd83b3, 0xbd308ff8,
	 0xddd0467c, 0x64bce4a0, 0xac7cb3f6,
	 0x8aa22c0d, 0xbef60ee4, 0x6bcdf07a,
	 0xad4ab711, 0x2eb3929d, 0x86c16c98,
	 0xd89d64d5, 0x7a607744, 0xe871c7bf,
	 0x87625f05, 0x6c7c4a8b, 0x11471cd7,
	 0xa93af6c6, 0xc79b5d2d, 0xd598e40d,
	 0xd389b478, 0x79823479, 0x4aff1d10,
	 0x843610cb, 0x4bf160cb, 0xcedf722a,
	 0xa54394fe, 0x1eedb8fe, 0xc2974eb4,
	 0xce947a3d, 0xa6a9273e, 0x733d2262,
	 0x811ccc66, 0x8829b887, 0x0806357d,
	 0xa163ff80, 0x2a3426a8, 0xca07c2dc,
	 0xc9bcff60, 0x34c13052, 0xfc89b393,
	 0xfc2c3f38, 0x41f17c67, 0xbbac2078,
	 0x9d9ba783, 0x2936edc0, 0xd54b944b,
	 0xc5029163, 0xf384a931, 0x0a9e795e,
	 0xf64335bc, 0xf065d37d, 0x4d4617b5,
	 0x99ea0196, 0x163fa42e, 0x504bced1,
	 0xc06481fb, 0x9bcf8d39, 0xe45ec286,
	 0xf07da27a, 0x82c37088, 0x5d767327,
	 0x964e858c, 0x91ba2655, 0x3a6a07f8,
	 0xbbe226ef, 0xb628afea, 0x890489f7,
	 0xeadab0ab, 0xa3b2dbe5, 0x2b45ac74,
	 0x92c8ae6b, 0x464fc96f, 0x3b0b8bc9,
	 0xb77ada06, 0x17e3bbcb, 0x09ce6ebb,
	 0xe5599087, 0x9ddcaabd, 0xcc420a6a,
	 0x8f57fa54, 0xc2a9eab6, 0x9fa94682,
	 0xb32df8e9, 0xf3546564, 0x47939822,
	 0xdff97724, 0x70297ebd, 0x59787e2b,
	 0x8bfbea76, 0xc619ef36, 0x57eb4edb,
	 0xaefae514, 0x77a06b03, 0xede62292,
	 0xdab99e59, 0x958885c4, 0xe95fab36,
	 0x88b402f7, 0xfd75539b, 0x11dbcb02,
	 0xaae103b5, 0xfcd2a881, 0xd652bdc2,
	 0xd59944a3, 0x7c0752a2, 0x4be76d33,
	 0x857fcae6, 0x2d8493a5, 0x6f70a440,
	 0xa6dfbd9f, 0xb8e5b88e, 0xcb4ccd50,
	 0xd097ad07, 0xa71f26b2, 0x7e2000a4,
	 0x825ecc24, 0xc873782f, 0x8ed40066,
	 0xa2f67f2d, 0xfa90563b, 0x72890080,
	 0xcbb41ef9, 0x79346bca, 0x4f2b40a0,
	 0xfea126b7, 0xd78186bc, 0xe2f610c8,
	 0x9f24b832, 0xe6b0f436, 0x0dd9ca7d,
	 0xc6ede63f, 0xa05d3143, 0x91503d1c,
	 0xf8a95fcf, 0x88747d94, 0x75a44c63,
	 0x9b69dbe1, 0xb548ce7c, 0xc986afbe,
	 0xc24452da, 0x229b021b, 0xfbe85bad,
	 0xf2d56790, 0xab41c2a2, 0xfae27299,
	 0x97c560ba, 0x6b0919a5, 0xdccd879f,
	 0xbdb6b8e9, 0x05cb600f, 0x5400e987,
	 0xed246723, 0x473e3813, 0x290123e9,
	 0x9436c076, 0x0c86e30b, 0xf9a0b672,
	 0xb9447093, 0x8fa89bce, 0xf808e40e,
	 0xe7958cb8, 0x7392c2c2, 0xb60b1d12,
	 0x90bd77f3, 0x483bb9b9, 0xb1c6f22b,
	 0xb4ecd5f0, 0x1a4aa828, 0x1e38aeb6,
	 0xe2280b6c, 0x20dd5232, 0x25c6da63,
	 0x8d590723, 0x948a535f, 0x579c487e,
	 0xb0af48ec, 0x79ace837, 0x2d835a9d,
	 0xdcdb1b27, 0x98182244, 0xf8e43145,
	 0x8a08f0f8, 0xbf0f156b, 0x1b8e9ecb,
	 0xac8b2d36, 0xeed2dac5, 0xe272467e,
	 0xd7adf884, 0xaa879177, 0x5b0ed81d,
	 0x86ccbb52, 0xea94baea, 0x98e94712,
	 0xa87fea27, 0xa539e9a5, 0x3f2398d7,
	 0xd29fe4b1, 0x8e88640e, 0x8eec7f0d,
	 0x83a3eeee, 0xf9153e89, 0x1953cf68,
	 0xa48ceaaa, 0xb75a8e2b, 0x5fa8c342,
	 0xcdb02555, 0x653131b6, 0x3792f412,
	 0x808e1755, 0x5f3ebf11, 0xe2bbd88b,
	 0xa0b19d2a, 0xb70e6ed6, 0x5b6aceae,
	 0xc8de0475, 0x64d20a8b, 0xf245825a,
	 0xfb158592, 0xbe068d2e, 0xeed6e2f0,
	 0x9ced737b, 0xb6c4183d, 0x55464dd6,
	 0xc428d05a, 0xa4751e4c, 0xaa97e14c,
	 0xf5330471, 0x4d9265df, 0xd53dd99f,
	 0x993fe2c6, 0xd07b7fab, 0xe546a803,
	 0xbf8fdb78, 0x849a5f96, 0xde985204,
	 0xef73d256, 0xa5c0f77c, 0x963e6685,
	 0x95a86376, 0x27989aad, 0xdde70013,
	 0xbb127c53, 0xb17ec159, 0x5560c018,
	 0xe9d71b68, 0x9dde71af, 0xaab8f01e,
	 0x92267121, 0x62ab070d, 0xcab39613,
	 0xb6b00d69, 0xbb55c8d1, 0x3d607b97,
	 0xe45c10c4, 0x2a2b3b05, 0x8cb89a7d,
	 0x8eb98a7a, 0x9a5b04e3, 0x77f3608e,
	 0xb267ed19, 0x40f1c61c, 0x55f038b2,
	 0xdf01e85f, 0x912e37a3, 0x6b6c46de,
	 0x8b61313b, 0xbabce2c6, 0x2323ac4b,
	 0xae397d8a, 0xa96c1b77, 0xabec975e,
	 0xd9c7dced, 0x53c72255, 0x96e7bd35,
	 0x881cea14, 0x545c7575, 0x7e50d641,
	 0xaa242499, 0x697392d2, 0xdde50bd1,
	 0xd4ad2dbf, 0xc3d07787, 0x955e4ec6,
	 0x84ec3c97, 0xda624ab4, 0xbd5af13b,
	 0xa6274bbd, 0xd0fadd61, 0xecb1ad8a,
	 0xcfb11ead, 0x453994ba, 0x67de18ed,
	 0x81ceb32c, 0x4b43fcf4, 0x80eacf94,
	 0xa2425ff7, 0x5e14fc31, 0xa1258379,
	 0xcad2f7f5, 0x359a3b3e, 0x096ee458,
	 0xfd87b5f2, 0x8300ca0d, 0x8bca9d6e,
	 0x9e74d1b7, 0x91e07e48, 0x775ea264,
	 0xc6120625, 0x76589dda, 0x95364afe,
	 0xf79687ae, 0xd3eec551, 0x3a83ddbd,
	 0x9abe14cd, 0x44753b52, 0xc4926a96,
	 0xc16d9a00, 0x95928a27, 0x75b7053c,
	 0xf1c90080, 0xbaf72cb1, 0x5324c68b,
	 0x971da050, 0x74da7bee, 0xd3f6fc16,
	 0xbce50864, 0x92111aea, 0x88f4bb1c,
	 0xec1e4a7d, 0xb69561a5, 0x2b31e9e3,
	 0x9392ee8e, 0x921d5d07, 0x3aff322e,
	 0xb877aa32, 0x36a4b449, 0x09befeb9,
	 0xe69594be, 0xc44de15b, 0x4c2ebe68,
	 0x901d7cf7, 0x3ab0acd9, 0x0f9d3701,
	 0xb424dc35, 0x095cd80f, 0x538484c1,
	 0xe12e1342, 0x4bb40e13, 0x2865a5f2,
	 0x8cbccc09, 0x6f5088cb, 0xf93f87b7,
	 0xafebff0b, 0xcb24aafe, 0xf78f69a5,
	 0xdbe6fece, 0xbdedd5be, 0xb573440e,
	 0x89705f41, 0x36b4a597, 0x31680a88,
	 0xabcc7711, 0x8461cefc, 0xfdc20d2b,
	 0xd6bf94d5, 0xe57a42bc, 0x3d329076,
	 0x8637bd05, 0xaf6c69b5, 0xa63f9a49,
	 0xa7c5ac47, 0x1b478423, 0x0fcf80dc,
	 0xd1b71758, 0xe219652b, 0xd3c36113,
	 0x83126e97, 0x8d4fdf3b, 0x645a1cac,
	 0xa3d70a3d, 0x70a3d70a, 0x3d70a3d7,
	 0xcccccccc, 0xcccccccc, 0xcccccccc,
	 0x80000000, 0x00000000, 0x00000000,
	 0xa0000000, 0x00000000, 0x00000000,
	 0xc8000000, 0x00000000, 0x00000000,
	 0xfa000000, 0x00000000, 0x00000000,
	 0x9c400000, 0x00000000, 0x00000000,
	 0xc3500000, 0x00000000, 0x00000000,
	 0xf4240000, 0x00000000, 0x00000000,
	 0x98968000, 0x00000000, 0x00000000,
	 0xbebc2000, 0x00000000, 0x00000000,
	 0xee6b2800, 0x00000000, 0x00000000,
	 0x9502f900, 0x00000000, 0x00000000,
	 0xba43b740, 0x00000000, 0x00000000,
	 0xe8d4a510, 0x00000000, 0x00000000,
	 0x9184e72a, 0x00000000, 0x00000000,
	 0xb5e620f4, 0x80000000, 0x00000000,
	 0xe35fa931, 0xa0000000, 0x00000000,
	 0x8e1bc9bf, 0x04000000, 0x00000000,
	 0xb1a2bc2e, 0xc5000000, 0x00000000,
	 0xde0b6b3a, 0x76400000, 0x00000000,
	 0x8ac72304, 0x89e80000, 0x00000000,
	 0xad78ebc5, 0xac620000, 0x00000000,
	 0xd8d726b7, 0x177a8000, 0x00000000,
	 0x87867832, 0x6eac9000, 0x00000000,
	 0xa968163f, 0x0a57b400, 0x00000000,
	 0xd3c21bce, 0xcceda100, 0x00000000,
	 0x84595161, 0x401484a0, 0x00000000,
	 0xa56fa5b9, 0x9019a5c8, 0x00000000,
	 0xcecb8f27, 0xf4200f3a, 0x00000000,
	 0x813f3978, 0xf8940984, 0x40000000,
	 0xa18f07d7, 0x36b90be5, 0x50000000,
	 0xc9f2c9cd, 0x04674ede, 0xa4000000,
	 0xfc6f7c40, 0x45812296, 0x4d000000,
	 0x9dc5ada8, 0x2b70b59d, 0xf0200000,
	 0xc5371912, 0x364ce305, 0x6c280000,
	 0xf684df56, 0xc3e01bc6, 0xc7320000,
	 0x9a130b96, 0x3a6c115c, 0x3c7f4000,
	 0xc097ce7b, 0xc90715b3, 0x4b9f1000,
	 0xf0bdc21a, 0xbb48db20, 0x1e86d400,
	 0x96769950, 0xb50d88f4, 0x13144480,
	 0xbc143fa4, 0xe250eb31, 0x17d955a0,
	 0xeb194f8e, 0x1ae525fd, 0x5dcfab08,
	 0x92efd1b8, 0xd0cf37be, 0x5aa1cae5,
	 0xb7abc627, 0x050305ad, 0xf14a3d9e,
	 0xe596b7b0, 0xc643c719, 0x6d9ccd05,
	 0x8f7e32ce, 0x7bea5c6f, 0xe4820023,
	 0xb35dbf82, 0x1ae4f38b, 0xdda2802c,
	 0xe0352f62, 0xa19e306e, 0xd50b2037,
	 0x8c213d9d, 0xa502de45, 0x4526f422,
	 0xaf298d05, 0x0e4395d6, 0x9670b12b,
	 0xdaf3f046, 0x51d47b4c, 0x3c0cdd76,
	 0x88d8762b, 0xf324cd0f, 0xa5880a69,
	 0xab0e93b6, 0xefee0053, 0x8eea0d04,
	 0xd5d238a4, 0xabe98068, 0x72a49045,
	 0x85a36366, 0xeb71f041, 0x47a6da2b,
	 0xa70c3c40, 0xa64e6c51, 0x999090b6,
	 0xd0cf4b50, 0xcfe20765, 0xfff4b4e3,
	 0x82818f12, 0x81ed449f, 0xbff8f10e,
	 0xa321f2d7, 0x226895c7, 0xaff72d52,
	 0xcbea6f8c, 0xeb02bb39, 0x9bf4f8a6,
	 0xfee50b70, 0x25c36a08, 0x02f236d0,
	 0x9f4f2726, 0x179a2245, 0x01d76242,
	 0xc722f0ef, 0x9d80aad6, 0x424d3ad2,
	 0xf8ebad2b, 0x84e0d58b, 0xd2e08987,
	 0x9b934c3b, 0x330c8577, 0x63cc55f4,
	 0xc2781f49, 0xffcfa6d5, 0x3cbf6b71,
	 0xf316271c, 0x7fc3908a, 0x8bef464e,
	 0x97edd871, 0xcfda3a56, 0x97758bf0,
	 0xbde94e8e, 0x43d0c8ec, 0x3d52eeed,
	 0xed63a231, 0xd4c4fb27, 0x4ca7aaa8,
	 0x945e455f, 0x24fb1cf8, 0x8fe8caa9,
	 0xb975d6b6, 0xee39e436, 0xb3e2fd53,
	 0xe7d34c64, 0xa9c85d44, 0x60dbbca8,
	 0x90e40fbe, 0xea1d3a4a, 0xbc8955e9,
	 0xb51d13ae, 0xa4a488dd, 0x6babab63,
	 0xe264589a, 0x4dcdab14, 0xc696963c,
	 0x8d7eb760, 0x70a08aec, 0xfc1e1de5,
	 0xb0de6538, 0x8cc8ada8, 0x3b25a55f,
	 0xdd15fe86, 0xaffad912, 0x49ef0eb7,
	 0x8a2dbf14, 0x2dfcc7ab, 0x6e356932,
	 0xacb92ed9, 0x397bf996, 0x49c2c37f,
	 0xd7e77a8f, 0x87daf7fb, 0xdc33745e,
	 0x86f0ac99, 0xb4e8dafd, 0x69a028bb,
	 0xa8acd7c0, 0x222311bc, 0xc40832ea,
	 0xd2d80db0, 0x2aabd62b, 0xf50a3fa4,
	 0x83c7088e, 0x1aab65db, 0x792667c6,
	 0xa4b8cab1, 0xa1563f52, 0x577001b8,
	 0xcde6fd5e, 0x09abcf26, 0xed4c0226,
	 0x80b05e5a, 0xc60b6178, 0x544f8158,
	 0xa0dc75f1, 0x778e39d6, 0x696361ae,
	 0xc913936d, 0xd571c84c, 0x03bc3a19,
	 0xfb587849, 0x4ace3a5f, 0x04ab48a0,
	 0x9d174b2d, 0xcec0e47b, 0x62eb0d64,
	 0xc45d1df9, 0x42711d9a, 0x3ba5d0bd,
	 0xf5746577, 0x930d6500, 0xca8f44ec,
	 0x9968bf6a, 0xbbe85f20, 0x7e998b13,
	 0xbfc2ef45, 0x6ae276e8, 0x9e3fedd8,
	 0xefb3ab16, 0xc59b14a2, 0xc5cfe94e,
	 0x95d04aee, 0x3b80ece5, 0xbba1f1d1,
	 0xbb445da9, 0xca61281f, 0x2a8a6e45,
	 0xea157514, 0x3cf97226, 0xf52d09d7,
	 0x924d692c, 0xa61be758, 0x593c2626,
	 0xb6e0c377, 0xcfa2e12e, 0x6f8b2fb0,
	 0xe498f455, 0xc38b997a, 0x0b6dfb9c,
	 0x8edf98b5, 0x9a373fec, 0x4724bd41,
	 0xb2977ee3, 0x00c50fe7, 0x58edec91,
	 0xdf3d5e9b, 0xc0f653e1, 0x2f2967b6,
	 0x8b865b21, 0x5899f46c, 0xbd79e0d2,
	 0xae67f1e9, 0xaec07187, 0xecd85906,
	 0xda01ee64, 0x1a708de9, 0xe80e6f48,
	 0x884134fe, 0x908658b2, 0x3109058d,
	 0xaa51823e, 0x34a7eede, 0xbd4b46f0,
	 0xd4e5e2cd, 0xc1d1ea96, 0x6c9e18ac,
	 0x850fadc0, 0x9923329e, 0x03e2cf6b,
	 0xa6539930, 0xbf6bff45, 0x84db8346,
	 0xcfe87f7c, 0xef46ff16, 0xe6126418,
	 0x81f14fae, 0x158c5f6e, 0x4fcb7e8f,
	 0xa26da399, 0x9aef7749, 0xe3be5e33,
	 0xcb090c80, 0x01ab551c, 0x5cadf5bf,
	 0xfdcb4fa0, 0x02162a63, 0x73d9732f,
	 0x9e9f11c4, 0x014dda7e, 0x2867e7fd,
	 0xc646d635, 0x01a1511d, 0xb281e1fd,
	 0xf7d88bc2, 0x4209a565, 0x1f225a7c,
	 0x9ae75759, 0x6946075f, 0x3375788d,
	 0xc1a12d2f, 0xc3978937, 0x0052d6b1,
	 0xf209787b, 0xb47d6b84, 0xc0678c5d,
	 0x9745eb4d, 0x50ce6332, 0xf840b7ba,
	 0xbd176620, 0xa501fbff, 0xb650e5a9,
	 0xec5d3fa8, 0xce427aff, 0xa3e51f13,
	 0x93ba47c9, 0x80e98cdf, 0xc66f336c,
	 0xb8a8d9bb, 0xe123f017, 0xb80b0047,
	 0xe6d3102a, 0xd96cec1d, 0xa60dc059,
	 0x9043ea1a, 0xc7e41392, 0x87c89837,
	 0xb454e4a1, 0x79dd1877, 0x29babe45,
	 0xe16a1dc9, 0xd8545e94, 0xf4296dd6,
	 0x8ce2529e, 0x2734bb1d, 0x1899e4a6,
	 0xb01ae745, 0xb101e9e4, 0x5ec05dcf,
	 0xdc21a117, 0x1d42645d, 0x76707543,
	 0x899504ae, 0x72497eba, 0x6a06494a,
	 0xabfa45da, 0x0edbde69, 0x0487db9d,
	 0xd6f8d750, 0x9292d603, 0x45a9d284,
	 0x865b8692, 0x5b9bc5c2, 0x0b8a2392,
	 0xa7f26836, 0xf282b732, 0x8e6cac77,
	 0xd1ef0244, 0xaf2364ff, 0x3207d795,
	 0x8335616a, 0xed761f1f, 0x7f44e6bd,
	 0xa402b9c5, 0xa8d3a6e7, 0x5f16206c,
	 0xcd036837, 0x130890a1, 0x36dba887,
	 0x80222122, 0x6be55a64, 0xc2494954,
	 0xa02aa96b, 0x06deb0fd, 0xf2db9baa,
	 0xc83553c5, 0xc8965d3d, 0x6f928294,
	 0xfa42a8b7, 0x3abbf48c, 0xcb772339,
	 0x9c69a972, 0x84b578d7, 0xff2a7604,
	 0xc38413cf, 0x25e2d70d, 0xfef51385,
	 0xf46518c2, 0xef5b8cd1, 0x7eb25866,
	 0x98bf2f79, 0xd5993802, 0xef2f773f,
	 0xbeeefb58, 0x4aff8603, 0xaafb550f,
	 0xeeaaba2e, 0x5dbf6784, 0x95ba2a53,
	 0x952ab45c, 0xfa97a0b2, 0xdd945a74,
	 0xba756174, 0x393d88df, 0x94f97111,
	 0xe912b9d1, 0x478ceb17, 0x7a37cd56,
	 0x91abb422, 0xccb812ee, 0xac62e055,
	 0xb616a12b, 0x7fe617aa, 0x577b986b,
	 0xe39c4976, 0x5fdf9d94, 0xed5a7e85,
	 0x8e41ade9, 0xfbebc27d, 0x14588f13,
	 0xb1d21964, 0x7ae6b31c, 0x596eb2d8,
	 0xde469fbd, 0x99a05fe3, 0x6fca5f8e,
	 0x8aec23d6, 0x80043bee, 0x25de7bb9,
	 0xada72ccc, 0x20054ae9, 0xaf561aa7,
	 0xd910f7ff, 0x28069da4, 0x1b2ba151,
	 0x87aa9aff, 0x79042286, 0x90fb44d2,
	 0xa99541bf, 0x57452b28, 0x353a1607,
	 0xd3fa922f, 0x2d1675f2, 0x42889b89,
	 0x847c9b5d, 0x7c2e09b7, 0x69956135,
	 0xa59bc234, 0xdb398c25, 0x43fab983,
	 0xcf02b2c2, 0x1207ef2e, 0x94f967e4,
	 0x8161afb9, 0x4b44f57d, 0x1d1be0ee,
	 0xa1ba1ba7, 0x9e1632dc, 0x6462d92a,
	 0xca28a291, 0x859bbf93, 0x7d7b8f75,
	 0xfcb2cb35, 0xe702af78, 0x5cda7352,
	 0x9defbf01, 0xb061adab, 0x3a088813,
	 0xc56baec2, 0x1c7a1916, 0x088aaa18,
	 0xf6c69a72, 0xa3989f5b, 0x8aad549e,
	 0x9a3c2087, 0xa63f6399, 0x36ac54e2,
	 0xc0cb28a9, 0x8fcf3c7f, 0x84576a1b,
	 0xf0fdf2d3, 0xf3c30b9f, 0x656d44a2,
	 0x969eb7c4, 0x7859e743, 0x9f644ae5,
	 0xbc4665b5, 0x96706114, 0x873d5d9f,
	 0xeb57ff22, 0xfc0c7959, 0xa90cb506,
	 0x9316ff75, 0xdd87cbd8, 0x09a7f124,
	 0xb7dcbf53, 0x54e9bece, 0x0c11ed6d,
	 0xe5d3ef28, 0x2a242e81, 0x8f1668c8,
	 0x8fa47579, 0x1a569d10, 0xf96e017d,
	 0xb38d92d7, 0x60ec4455, 0x37c981dc,
	 0xe070f78d, 0x3927556a, 0x85bbe253,
	 0x8c469ab8, 0x43b89562, 0x93956d74,
	 0xaf584166, 0x54a6babb, 0x387ac8d1,
	 0xdb2e51bf, 0xe9d0696a, 0x06997b05,
	 0x88fcf317, 0xf22241e2, 0x441fece3,
	 0xab3c2fdd, 0xeeaad25a, 0xd527e81c,
	 0xd60b3bd5, 0x6a5586f1, 0x8a71e223,
	 0x85c70565, 0x62757456, 0xf6872d56,
	 0xa738c6be, 0xbb12d16c, 0xb428f8ac,
	 0xd106f86e, 0x69d785c7, 0xe13336d7,
	 0x82a45b45, 0x0226b39c, 0xecc00246,
	 0xa34d7216, 0x42b06084, 0x27f002d7,
	 0xcc20ce9b, 0xd35c78a5, 0x31ec038d,
	 0xff290242, 0xc83396ce, 0x7e670471,
	 0x9f79a169, 0xbd203e41, 0x0f0062c6,
	 0xc75809c4, 0x2c684dd1, 0x52c07b78,
	 0xf92e0c35, 0x37826145, 0xa7709a56,
	 0x9bbcc7a1, 0x42b17ccb, 0x88a66076,
	 0xc2abf989, 0x935ddbfe, 0x6acff893,
	 0xf356f7eb, 0xf83552fe, 0x0583f6b8,
	 0x98165af3, 0x7b2153de, 0xc3727a33,
	 0xbe1bf1b0, 0x59e9a8d6, 0x744f18c0,
	 0xeda2ee1c, 0x7064130c, 0x1162def0,
	 0x9485d4d1, 0xc63e8be7, 0x8addcb56,
	 0xb9a74a06, 0x37ce2ee1, 0x6d953e2b,
	 0xe8111c87, 0xc5c1ba99, 0xc8fa8db6,
	 0x910ab1d4, 0xdb9914a0, 0x1d9c9892,
	 0xb54d5e4a, 0x127f59c8, 0x2503beb6,
	 0xe2a0b5dc, 0x971f303a, 0x2e44ae64,
	 0x8da471a9, 0xde737e24, 0x5ceaecfe,
	 0xb10d8e14, 0x56105dad, 0x7425a83e,
	 0xdd50f199, 0x6b947518, 0xd12f124e,
	 0x8a5296ff, 0xe33cc92f, 0x82bd6b70,
	 0xace73cbf, 0xdc0bfb7b, 0x636cc64d,
	 0xd8210bef, 0xd30efa5a, 0x3c47f7e0,
	 0x8714a775, 0xe3e95c78, 0x65acfaec,
	 0xa8d9d153, 0x5ce3b396, 0x7f1839a7,
	 0xd31045a8, 0x341ca07c, 0x1ede4811,
	 0x83ea2b89, 0x2091e44d, 0x934aed0a,
	 0xa4e4b66b, 0x68b65d60, 0xf81da84d,
	 0xce1de406, 0x42e3f4b9, 0x36251260,
	 0x80d2ae83, 0xe9ce78f3, 0xc1d72b7c,
	 0xa1075a24, 0xe4421730, 0xb24cf65b,
	 0xc94930ae, 0x1d529cfc, 0xdee033f2,
	 0xfb9b7cd9, 0xa4a7443c, 0x169840ef,
	 0x9d412e08, 0x06e88aa5, 0x8e1f2895,
	 0xc491798a, 0x08a2ad4e, 0xf1a6f2ba,
	 0xf5b5d7ec, 0x8acb58a2, 0xae10af69,
	 0x9991a6f3, 0xd6bf1765, 0xacca6da1,
	 0xbff610b0, 0xcc6edd3f, 0x17fd090a,
	 0xeff394dc, 0xff8a948e, 0xddfc4b4c,
	 0x95f83d0a, 0x1fb69cd9, 0x4abdaf10,
	 0xbb764c4c, 0xa7a4440f, 0x9d6d1ad4,
	 0xea53df5f, 0xd18d5513, 0x84c86189,
	 0x92746b9b, 0xe2f8552c, 0x32fd3cf5,
	 0xb7118682, 0xdbb66a77, 0x3fbc8c33,
	 0xe4d5e823, 0x92a40515, 0x0fabaf3f,
	 0x8f05b116, 0x3ba6832d, 0x29cb4d87,
	 0xb2c71d5b, 0xca9023f8, 0x743e20e9,
	 0xdf78e4b2, 0xbd342cf6, 0x914da924,
	 0x8bab8eef, 0xb6409c1a, 0x1ad089b6,
	 0xae9672ab, 0xa3d0c320, 0xa184ac24,
	 0xda3c0f56, 0x8cc4f3e8, 0xc9e5d72d,
	 0x88658996, 0x17fb1871, 0x7e2fa67c,
	 0xaa7eebfb, 0x9df9de8d, 0xddbb901b,
	 0xd51ea6fa, 0x85785631, 0x552a7422,
	 0x8533285c, 0x936b35de, 0xd53a8895,
	 0xa67ff273, 0xb8460356, 0x8a892aba,
	 0xd01fef10, 0xa657842c, 0x2d2b7569,
	 0x8213f56a, 0x67f6b29b, 0x9c3b2962,
	 0xa298f2c5, 0x01f45f42, 0x8349f3ba,
	 0xcb3f2f76, 0x42717713, 0x241c70a9,
	 0xfe0efb53, 0xd30dd4d7, 0xed238cd3,
	 0x9ec95d14, 0x63e8a506, 0xf4363804,
	 0xc67bb459, 0x7ce2ce48, 0xb143c605,
	 0xf81aa16f, 0xdc1b81da, 0xdd94b786,
	 0x9b10a4e5, 0xe9913128, 0xca7cf2b4,
	 0xc1d4ce1f, 0x63f57d72, 0xfd1c2f61,
	 0xf24a01a7, 0x3cf2dccf, 0xbc633b39,
	 0x976e4108, 0x8617ca01, 0xd5be0503,
	 0xbd49d14a, 0xa79dbc82, 0x4b2d8644,
	 0xec9c459d, 0x51852ba2, 0xddf8e7d6,
	 0x93e1ab82, 0x52f33b45, 0xcabb90e5,
	 0xb8da1662, 0xe7b00a17, 0x3d6a751f,
	 0xe7109bfb, 0xa19c0c9d, 0x0cc51267,
	 0x906a617d, 0x450187e2, 0x27fb2b80,
	 0xb484f9dc, 0x9641e9da, 0xb1f9f660,
	 0xe1a63853, 0xbbd26451, 0x5e7873f8,
	 0x8d07e334, 0x55637eb2, 0xdb0b487b,
	 0xb049dc01, 0x6abc5e5f, 0x91ce1a9a,
	 0xdc5c5301, 0xc56b75f7, 0x7641a140,
	 0x89b9b3e1, 0x1b6329ba, 0xa9e904c8,
	 0xac2820d9, 0x623bf429, 0x546345fa,
	 0xd732290f, 0xbacaf133, 0xa97c1779,
	 0x867f59a9, 0xd4bed6c0, 0x49ed8eab,
	 0xa81f3014, 0x49ee8c70, 0x5c68f256,
	 0xd226fc19, 0x5c6a2f8c, 0x73832eec,
	 0x83585d8f, 0xd9c25db7, 0xc831fd53,
	 0xa42e74f3, 0xd032f525, 0xba3e7ca8,
	 0xcd3a1230, 0xc43fb26f, 0x28ce1bd2,
	 0x80444b5e, 0x7aa7cf85, 0x7980d163,
	 0xa0555e36, 0x1951c366, 0xd7e105bc,
	 0xc86ab5c3, 0x9fa63440, 0x8dd9472b,
	 0xfa856334, 0x878fc150, 0xb14f98f6,
	 0x9c935e00, 0xd4b9d8d2, 0x6ed1bf9a,
	 0xc3b83581, 0x09e84f07, 0x0a862f80,
	 0xf4a642e1, 0x4c6262c8, 0xcd27bb61,
	 0x98e7e9cc, 0xcfbd7dbd, 0x8038d51c,
	 0xbf21e440, 0x03acdd2c, 0xe0470a63,
	 0xeeea5d50, 0x04981478, 0x1858ccfc,
	 0x95527a52, 0x02df0ccb, 0x0f37801e,
	 0xbaa718e6, 0x8396cffd, 0xd3056025,
	 0xe950df20, 0x247c83fd, 0x47c6b82e,
	 0x91d28b74, 0x16cdd27e, 0x4cdc331d,
	 0xb6472e51, 0x1c81471d, 0xe0133fe4,
	 0xe3d8f9e5, 0x63a198e5, 0x58180fdd,
	 0x8e679c2f, 0x5e44ff8f, 0x570f09ea,
	 0xb201833b, 0x35d63f73, 0x2cd2cc65,
	 0xde81e40a, 0x034bcf4f, 0xf8077f7e,
	 0x8b112e86, 0x420f6191, 0xfb04afaf,
	 0xadd57a27, 0xd29339f6, 0x79c5db9a,
	 0xd94ad8b1, 0xc7380874, 0x18375281,
	 0x87cec76f, 0x1c830548, 0x8f229391,
	 0xa9c2794a, 0xe3a3c69a, 0xb2eb3875,
	 0xd433179d, 0x9c8cb841, 0x5fa60692,
	 0x849feec2, 0x81d7f328, 0xdbc7c41b,
	 0xa5c7ea73, 0x224deff3, 0x12b9b522,
	 0xcf39e50f, 0xeae16bef, 0xd768226b,
	 0x81842f29, 0xf2cce375, 0xe6a11583,
	 0xa1e53af4, 0x6f801c53, 0x60495ae3,
	 0xca5e89b1, 0x8b602368, 0x385bb19c,
	 0xfcf62c1d, 0xee382c42, 0x46729e03,
	 0x9e19db92, 0xb4e31ba9, 0x6c07a2c2,
	 0xc5a05277, 0x621be293, 0xc7098b73,
	 0xf7086715, 0x3aa2db38, 0xb8cbee4f,
	 0x9a65406d, 0x44a5c903, 0x737f74f1,
	 0xc0fe9088, 0x95cf3b44, 0x505f522e,
	 0xf13e34aa, 0xbb430a15, 0x647726b9,
	 0x96c6e0ea, 0xb509e64d, 0x5eca7834,
	 0xbc789925, 0x624c5fe0, 0xb67d1641,
	 0xeb96bf6e, 0xbadf77d8, 0xe41c5bd1,
	 0x933e37a5, 0x34cbaae7, 0x8e91b962,
	 0xb80dc58e, 0x81fe95a1, 0x723627bb,
	 0xe61136f2, 0x227e3b09, 0xcec3b1aa,
	 0x8fcac257, 0x558ee4e6, 0x213a4f0a,
	 0xb3bd72ed, 0x2af29e1f, 0xa988e2cd,
	 0xe0accfa8, 0x75af45a7, 0x93eb1b80,
	 0x8c6c01c9, 0x498d8b88, 0xbc72f130 ];



HexDouble :: union {
    _u64:     u64;
    _float64: float64;
}

clz64 :: (x: u64) -> n: s32 { // @Speed! Replace with an intrinsic.
    if !x return 64;

    n: s32;
    mask: u64 = 0x8000_0000_0000_0000;

    while !(x & mask) {
        n += 1;
        mask = mask >> 1;
    }

    return n;
}

clz32 :: (x: u32) -> n: s32 { // @Speed! Replace with an intrinsic.
    if !x return 32;

    n: s32;
    mask: u64 = 0x8000_0000;

    while !(x & mask) {
        n += 1;
        mask = mask >> 1;
    }

    return n;
}

INRANGE :: (value: $T, low: T, high: T) -> bool {
    if value < low  return false;
    if value > high return false;
    return true;
}

EXP_MIN :: -323;
EXP_MAX :: 309;
BIAS :: 1021;

HOLE :: ~cast(u32)98;
FLOAT64_INFINITY   :: 0h7FF00000_00000000;

