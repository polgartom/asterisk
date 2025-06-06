

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
//~ Viewport

Viewport :: struct {
    
}