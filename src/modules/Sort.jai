// Sorting algorithms, such as bubble sort and quick sort.

bubble_sort :: (array: [] $T, f: (T, T) -> s64) {
    count := array.count;

    last_j := count-2;
    first_j := 0;
    
    while true {
        latest_swap := -1;
        first_swap  := -1;
        for j : first_j..last_j {
            a := array[j];
            b := array[j+1];

            compare := f(a, b);
            if compare > 0 {
                array[j]   = b;
                array[j+1] = a;
                latest_swap = j;
                if first_swap == -1  first_swap = j;
            }
        }

        if latest_swap == -1 return;
        // assert(latest_swap <= last_j);
        last_j = latest_swap - 1;
        first_j = ifx first_swap-1 > 0 then first_swap-1;
    }
}

// @Speed: This version of quick_sort (and probably the other one)
// seems to compare items to themselves a lot, which is clearly pointless.
// Fix that!
quick_sort :: (array: [] $T, f: (T, T) -> $R) -> [] T {  // R is an integer type, but may be e.g. 32-bit.
    quicksort_helper :: (a: *T, n: s64, f: (T, T) -> R) {
        if n < 2 return;

        p := a[n / 2];

        i := 0;
        j := n-1;

        while true {
            while f(a[i], p) < 0  {i += 1;}
            while f(p, a[j]) < 0  {j -= 1;}

            if i >= j break;

            t := a[i];
            a[i] = a[j];
            a[j] = t;

            i += 1;
            j -= 1;
        }
        
        quicksort_helper(a, i, f);
        quicksort_helper(a + i, n - i, f);
    }

    quicksort_helper(array.data, array.count, f);
    return array;    
}


// This version of quicksort only returns the array
// so that we can do the weird LINQ thing. We can
// think about syntactic alternatives.
quick_sort :: (array: [] $T, f: (T) -> $R) -> [] T {
    // @Cleanup: This is a cutnpaste from the Quicksort above, except
    // with a different type of f. If we could do some kind of fancy
    // thing with static_if, we would not have to copy and paste the code.

    quicksort_helper :: (a: *$T, n: s64, f: (T) -> $R) {
        if n < 2 return;

        p := a[n / 2];

        i := 0;
        j := n-1;

        while true {
            fp := f(p);
            while f(a[i]) < fp  {i += 1;}
            while fp < f(a[j])  {j -= 1;}

            if i >= j break;

            t := a[i];
            a[i] = a[j];
            a[j] = t;

            i += 1;
            j -= 1;
        }
        
        quicksort_helper(a, i, f);
        quicksort_helper(a + i, n - i, f);
    }

    quicksort_helper(array.data, array.count, f);
    return array;  
}

compare_floats :: (a: float, b: float) -> s64 {
    delta := a - b;
    if delta < 0 return -1;
    if delta > 0 return  1;
    return 0;
}

compare_strings :: (a: string, b: string) -> s64 {
    for 0..a.count-1 {
        if it >= b.count return 1;
        
        delta := cast(s64) a[it] - cast(s64) b[it];
        if delta return delta;
    }

    if b.count > a.count return -1;
    return 0;
}

