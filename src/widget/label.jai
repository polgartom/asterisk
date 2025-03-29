label :: (left: s64, bottom: s64, text: string, font: *Simp.Dynamic_Font, color: Vector4) -> s64 {
    if !text return 0;
    
    width := Simp.prepare_text(font, text);
    Simp.draw_prepared_text(font, left, bottom, color);

    return width;
}