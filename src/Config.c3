module c3web::config;

import std::io;
import std::io::os;
import std::io::file;
import std::io::path;
import std::collections::object;
import std::encoding::json;

struct Config {
    String address;
    uint port;
    uint workers;
    Object* cors;
    Object* experimental;
}

fn Config read_from_file() {
    @pool() {
        Path path = path::temp_cwd()!!;
        path = path.new_append("config.json")!!;

        if (!path::is_file(path)) {
            io::printn("STARTUP\t| Creating config file...");
            File! file = file::open_path(path, "w");
            if (catch anyfault err = file) {
                io::printn(err);
                return {};
            }
            file.write(
`{
    "address": "127.0.0.1",
    "port": 8080,
    "workers": 0,
    "cors": {
        "enabled": false,
        "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
        "Access-Control-Allow-Headers": "Content-Type",
        "Access-Control-Allow-Origin": "*"
    },
    "experimental": {
        "preload-files": 0,
        "preload-folders": 0
    }
}`)!!;
            file.flush()!!;
            file.close()!!;
        }

        File! file = file::open_path(path, "r");
        Object*! json = json::parse(&file);
        file.flush()!!;
        file.close()!!;

        Config config = {.address = json.get_string("address")??"", .port = json.get_int("port")??0, .workers = json.get_int("workers")??0, .cors = json.get_or_create_obj("cors")??null, .experimental = json.get_or_create_obj("experimental")??null};

        free(json)!!;
        return config;
    };
}