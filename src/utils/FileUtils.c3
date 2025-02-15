module c3web::utils;

import std::collections::map;

fn String! format_path(String format, HashMap(<String, String>)* args) {
    @pool() {
        foreach (String key: args.tcopy_keys()) {
            DString _placeholder = dstring::new();
            _placeholder.appendf("{%s}", key);
            String placeholder = _placeholder.copy_str();
            _placeholder.free();
            if (format.contains(placeholder)) {
                String[] split = format.split(placeholder);
                DString new = dstring::new_join(split, args.get(key)!!);
                format = new.copy_str();
                new.free();
            }
        }

        return format;
    };
}
