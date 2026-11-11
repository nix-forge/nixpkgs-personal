fn transparency(pdf: &[u8]) -> Vec<&'static str> {
    let text = String::from_utf8_lossy(pdf);
    let mut found = vec![];
    for (what, there) in [
        ("soft masks", text.contains("/SMask") && !text.contains("/SMask/None")),
        ("blend modes", text.contains("/BM") && !text.contains("/BM/Normal")),
        ("transparency groups", text.contains("/S/Transparency")),
        ("opacity", text.contains("/ca 0.") || text.contains("/CA 0.")),
    ] {
        if there {
            found.push(what);
        }
    }
    found
}
