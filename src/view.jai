

////////////////////////////////
//~ Rect

expand :: (rect: Rect, amount: float) -> Rect {
    r := rect;
    r.x -= amount;
    r.y -= amount;
    r.w += 2*amount;
    r.h += 2*amount;

    return r;
}

expand_x :: (rect: Rect, amount: float) -> Rect {
    r := rect;
    r.x -= amount;
    r.w += 2*amount;

    return r;
}

expand_y :: (rect: Rect, amount: float) -> Rect {
    r := rect;
    r.y -= amount;
    r.h += 2*amount;

    return r;
}

shrink :: (rect: Rect, amount: float) -> Rect {
    return expand(rect, -amount);
}

shrink_x :: (rect: Rect, amount: float) -> Rect {  // Shrink by 'amount' on both sides of the rectangle.
    return expand_x(rect, -amount);
}

shrink_y :: (rect: Rect, amount: float) -> Rect {  // Shrink by 'amount' on both sides of the rectangle.
    return expand_y(rect, -amount);
}

cut_left  :: (rect: Rect, amount: float, margin := 0.0) -> (left: Rect, remainder: Rect) {
    remainder := rect;

    m := margin * .5;
    remainder.w -= amount + m;
    remainder.x += amount + m;

    left := rect;
    left.w = amount - m;

    return left, remainder;
}

cut_right :: (rect: Rect, amount: float, margin := 0.0) -> (right: Rect, remainder: Rect) {
    m := margin * .5;
    remainder := rect;

    remainder.w -= amount + m;

    right := rect;
    right.x = remainder.x + remainder.w + margin;
    right.w = amount - m;

    return right, remainder;
}

cut_bottom :: (rect: Rect, amount: float, margin := 0.0) -> (bottom: Rect, remainder: Rect) {
    remainder := rect;

    m := margin * .5;
    remainder.h -= amount + m;
    remainder.y += amount + m;

    bottom := rect;
    bottom.h = amount - m;

    return bottom, remainder;
}

cut_top :: (rect: Rect, amount: float, margin := 0.0) -> (top: Rect, remainder: Rect) {
    m := margin * .5;
    remainder := rect;

    remainder.h -= amount + m;

    top := rect;
    top.y = remainder.y + remainder.h + margin;
    top.h = amount - m;

    return top, remainder;
}

make_rect :: (x: int, y: int, w: int, h: int) -> Rect {
    return .{
        x = xx x,
        y = xx y,
        w = xx w,
        h = xx h,
    };
}

make_rect :: (x: float, y: float, w: float, h: float) -> Rect {
    return .{
        x = x,
        y = y,
        w = w,
        h = h,
    };
}

Rect :: struct {
    x, y: float;
    w, h: float;
}

v2 :: xy;
v3 :: xyz;
v4 :: xyzw;

get_quad :: (using r: Rect, snap_coordinates := false) -> (p0: Vector2, p1: Vector2, p2: Vector2, p3: Vector2) {
    p0 := v2(x  , y  );
    p1 := v2(x+w, y  );
    p2 := v2(x+w, y+h);
    p3 := v2(x  , y+h);

    if snap_coordinates {
        p0.x = floor(p0.x + .5);
        p0.y = floor(p0.y + .5);
        p1.x = floor(p1.x + .5);
        p1.y = floor(p1.y + .5);
        p2.x = floor(p2.x + .5);
        p2.y = floor(p2.y + .5);
        p3.x = floor(p3.x + .5);
        p3.y = floor(p3.y + .5);
    }

    return p0, p1, p2, p3;
}

intersect :: (a: Rect, b: Rect) -> Rect {
    x := max(a.x, b.x);
    y := max(a.y, b.y);

    w := max(min(a.x+a.w, b.x+b.w) - x, 0);
    h := max(min(a.y+a.h, b.y+b.h) - y, 0);

    rect := make_rect(x, y, w, h);
    return rect;
}

////////////////////////////////
//~ 

Alignment :: enum { none; top; left; right; center; bottom; };

font_calc_y_center_insert_point :: (rect: Rect, character_height: int) -> float {
    return rect.y + rect.h*.5 - character_height*.5;
}

em :: (x: float, font: *Simp.Dynamic_Font) -> float {
    if font return font.em_width * x;
    return 1;  // In case we get null fonts from the user.
}

push_scissor :: (_rect: Rect) {
    rect := _rect;

    if scissor_stack {
        top := peek_pointer(scissor_stack);
        rect = intersect(top.*, rect);
    }

    set_scissor(rect);
    array_add(*scissor_stack, rect);
}

pop_scissor :: () {
    pop(*scissor_stack);

    if scissor_stack {
        r := peek(scissor_stack);
        set_scissor(r);
    } else {
        Simp.clear_scissor();
    }
}

set_scissor :: (r: Rect) {
    x0 := cast(s32) r.x;
    y0 := cast(s32) r.y;
    x1 := cast(s32) (r.x + r.w);
    y1 := cast(s32) (r.y + r.h);

    Simp.set_scissor(x0, y0, x1, y1);
}

scissor_stack: [..] Rect;

////////////////////////////////
//~ Range

is_overlap :: (r1: Range, r2: Range) -> bool {
    if r1.a > r2.b || r2.a > r1.a return false;
    return true;
}

get_overlap_range :: (r1: Range, r2: Range) -> bool, Range {
    if !is_overlap(r1, r2) return false, .{0,0};

    return true, .{max(r1.a, r2.a), min(r1.b, r2.b)};
}

Range :: struct {
    start: s64;
    end:   s64;

    #place start; 
    a: s64; b: s64;
}

////////////////////////////////
//~ Viewport

Viewport :: struct {
    
}