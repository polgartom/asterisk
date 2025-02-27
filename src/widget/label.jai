label :: (left: s64, bottom: s64, text: string, font: *Simp.Dynamic_Font, color: Vector4) {
    if !text return;
    
    Simp.prepare_text(font, text);
    Simp.draw_prepared_text(font, left, bottom, color);
}