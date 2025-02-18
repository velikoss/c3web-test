module c3web::routes;
// import std::collections::map;
// import std::io;
// import std::collections::object;
// import std::core::dstring;
// import std::time;
// import libc;

// const FOLDER_TOP = `
// <style>
// table, th, td {
//   border: 1px solid black;
//   border-collapse: collapse;
//   table-layout: auto;
//   vertical-align: bottom;
//   padding: 5px;
// }
// </style>
// <h1>Contents of %s</h1><hr>
// <table>
//     <tr>
//         <th>Name</th>
//         <th>Size</th>
//     </tr>
//     <tr>
//         <td><a href="%s">🔙</a></th>
//         <td>0</th>
//     </tr>
//     `;

// const FOLDER_FILE = `   <tr>
//         <td>
//             <a href="%s/%s">%s %s</a>
//         </td>
//         <td>
//             <p>%d</p>
//         </td>
//     </tr>`;

// def RouteFunction = fn HttpResponse(ControllerParadise* req);
// def RouteMap = HashMap(<String, RouteNode*>);
// def TagsMap = HashMap(<String, Object*>);

// struct RouteNode {
//     String name;
//     RouteMap subnodes;
//     bool has_apply;
//     RouteFunction apply;
// }

// enum PreloadMode: inline int {
//     COMPILE,
//     FIRST,
//     UPDATE
// }

// struct DataPreload {
//     long last_updated;
//     PreloadMode mode;
//     String data;
// }

// HashMap(<String, DataPreload>) preload;

// usz count = 0;
// TagsMap tagsMap;
// RouteMap _lowLevel;

// // fn HttpResponse e404(Request* req) {
// //     HttpResponse res;
// //     res.status = HttpStatus.NOT_FOUND;
// //     String answer = string::new_format(`{"type":"error","status":404,"data":"%s -> %s"}`, req.method, req.uri, req,allocator: req.allocator);
// //     res.body = dstring::new(answer, req.allocator);
// //     res.headers.add_header("Content-Type", "application/json");
// //     return res;
// // }

// // fn HttpResponse file(Request* req) {
// //     HttpResponse res;

// //     String filename = req.args["filename"]!!;
// //     bool to_preload = (req.args["force-preload"]??"false") == "true";
// //     bool has_key = false;
// //     // server::tty_log(DEBUG, "%d", preload.len());
// //     DataPreload! value = preload[filename];

// //     if (catch e = value) {}
// //     else {
// //         has_key = true;

// //         // server::tty_log(DEBUG, "%s (%d)", value.data, value.data.len);
// //         if (!to_preload) {
// //             switch (value.mode) {
// //                 case COMPILE:
// //                     if (value.data.len == 0) {
// //                         to_preload = true;
// //                         break;
// //                     }
// //                     res.status = HttpStatus.OK;
// //                     res.body = dstring::new(value.data, allocator: req.allocator);
// //                     // server::tty_log(DEBUG, "%s", value.data);
// //                     res.headers.add_header("Content-Type", "text/plain");
// //                     return res;
// //                 case FIRST:
// //                     if (value.data.len == 0) {
// //                         to_preload = true;
// //                         break;
// //                     }
// //                     res.status = HttpStatus.OK;
// //                     res.body = dstring::new(value.data, allocator: req.allocator);
// //                     server::tty_log(DEBUG, "%s", value.data);
// //                     res.headers.add_header("Content-Type", "text/plain");
// //                     return res;
// //                 default: break;
// //                 // case UPDATE:
// //                 //     $if env::LINUX || env::BSD_FAMILY:
// //                 //         Stat stat;
// //                 //         if (catch err = os::native_stat(&stat, filename)) {
// //                 //             server::tty_log(SEVERE, "%s", err);
// //                 //             break;
// //                 //         }
// //                 //         server::tty_log(DEBUG, "%s", stat.st_mtime);
// //                 //         if (value.last_updated < stat.st_mtime) {
// //                 //             to_preload = true;
// //                 //         }
// //                 //     $else
// //                 //         server::tty_log(WARNING, "Stat is unimplemented for this platform");
// //                 //         break;
// //                 //     $endif
// //             }
// //         }
// //     } 

// //     defer if (has_key && to_preload) {
// //         DataPreload _value = preload[filename]!!;
// //         server::tty_log(DEBUG, "Caching %s with mode %s", filename, value!!.mode); 
// //         _value.data = res.body.copy_str(&c3web::alloc);
// //         if (_value.mode == UPDATE) {
// //             _value.last_updated = ((long) time::now()) / 1000000;
// //         }
// //         preload[filename] = _value;
// //     }

// //         File! file;

// //     if (file::is_file(filename)) {
// //         file = file::open(filename, "rb");
// //     } else {
// //         Path path = path::new_cwd(req.allocator)!!;
// //         defer path.free_with_allocator(req.allocator);
// //         path = path.new_append(filename)!!;

// //         file = file::open_path(path, "rb");
// //         filename = path.to_new_string(req.allocator);
// //     }

// //     defer {
// //       (void)file.flush();
// //       (void)file.close();
// //     }

// //     //io::printfn("%s:%d %s", $$MODULE, $$LINE, filename);

// //     if (catch anyfault err = file) {
// //         res.status = HttpStatus.NOT_FOUND;
// //         io::eprintfn("Failed to get file: %s", err);
// //         String fmt = string::new_format(`{"type":"error","status":404}`, "\n", req.method, req.uri, allocator: req.allocator);
// //         res.body = dstring::new(allocator: req.allocator);
// //         fmt.free();
// //         res.headers.add_header("Content-Type", "application/json");
// //     } else if (file::get_size(filename)!! > 5 * 1024 * 1024) { // TODO CONFIG (right now 5Mb is the limit for the file)
// //         res.status = HttpStatus.PAYLOAD_TOO_LARGE;
// //         String fmt = string::new_format(`{"type":"error","status":413}`, "\n", req.method, req.uri);
// //         res.body = dstring::new(fmt);
// //         fmt.free();
// //         res.headers.add_header("Content-Type", "application/json");
// //     } else {
// //         DString text;
// //         text.new_init(allocator: req.allocator);
// //         if (catch anyfault err1 = text.read_from_stream(&file)) {
// //             server::tty_log(SEVERE, "%s", err1);
// //             res.status = HttpStatus.BAD_REQUEST;
// //             String fmt = string::new_format(`{"type":"error","status":400}`, "\n", req.method, req.uri);
// //             res.body = dstring::new(fmt);
// //             fmt.free();
// //         } else {
// //             res.status = HttpStatus.OK;
// //             res.body = text;
// //             //server::tty_log(DEBUG, "%s", text);
// //             res.headers.add_header("Content-Type", "text/plain");
// //         }
// //     }

// //     return res;
// // }

// // fn HttpResponse folder(Request* req) {
// // @pool(req.allocator) {
// //     HttpResponse res;
// //     String filename = req.args["foldername"]!!;
// //     server::tty_log(DEBUG, "%s", filename);

// //     PathList! list;
// //     defer list!!.free();

// //     Path ls = path::new(filename, allocator: req.allocator)!!;
// //     defer ls.free_with_allocator(req.allocator);
    
// //     if (os::native_is_dir(filename)) {
// //         list = path::new_ls(ls, allocator: req.allocator)!!;
// //     } else {
// //         ls = ls.new_append(filename)!!;
// //         filename = ls.to_new_string(allocator: req.allocator);
// //         if (path::is_dir(ls)) {
// //             list = path::new_ls(ls, allocator: req.allocator)!!;
// //         }
// //     }

// //     if (catch anyfault err = list) {
// //         res.status = HttpStatus.NOT_FOUND;
// //         String fmt = string::new_format(`{"type":"error","status":404}`, "\n", req.method, req.uri, allocator: req.allocator);       
// //         res.body = dstring::new(fmt, allocator: req.allocator);
// //         fmt.free();
// //         res.headers.add_header("Content-Type", "application/json");
// //     } else {
// //         DString body = dstring::new(allocator: req.allocator);
// //         String[] split = req.uri.split("/", allocator: req.allocator)[..^2];
// //         String joined = string::join_new(split, "/", allocator: req.allocator);
// //         allocator::free(req.allocator, split);
// //         body.appendfn(FOLDER_TOP, filename, joined);
// //         allocator::free(req.allocator, joined);

// //         foreach (Path file: list) {
// //             server::tty_log(DEBUG, "%s/%s", filename, file);
// //             String relative_path = string::new_format("%s/%s", filename, file, req.allocator);
// //             body.appendfn(FOLDER_FILE, req.uri, file.str_view(), (path::is_dir(path::temp_new(relative_path)!!) ? "📁 " : "🔗 "), file.str_view(), file::get_size(relative_path)??0);
// //             relative_path.free();
// //         }

// //         body.append("</table>");

// //         res.status = HttpStatus.OK;

// //         server::tty_log(DEBUG, "%s", body);
// //         res.body = body;
// //         res.headers.add_header("Content-Type", "text/html; charset=utf-8");
// //     }

// //     return res;
// // };
// // }

// fn RouteFunction get_route(String uri, HashMap(<String,String>)* args, Allocator allocator = &c3web::alloc) {
//     DString reverse_path = dstring::new(uri, allocator);
//     if (uri[0] != '/') reverse_path.insert_at(0, "/"); // todo: libuv does that? guess not. old code
//     args.set("reverse_path", reverse_path.copy_str(allocator));
//     reverse_path.free();

//     if (uri == "" || uri == "/") { return (_lowLevel[uri].has_apply??false)?_lowLevel[uri].apply!!:&e404; }

//     String old_uri;
//     if (uri[0] == '/' && uri.len > 1) {
//         old_uri = uri;
//         uri = uri[1..];
//     }

//     if (!(uri.contains("{") && uri.contains("}")) && _lowLevel.has_key(uri)) 
//     {   // Dynamic URI check
//         return (_lowLevel[uri].has_apply??false)?_lowLevel[uri].apply!!:&e404;
//     }

//     String[] nodes = uri.split("/", allocator: allocator);
//     defer allocator::free(allocator, nodes);

//     RouteNode*! temp = _lowLevel[nodes[0]];
//     if (catch err = temp) {
//         if (err != SearchResult.MISSING) io::printfn("Catch err: %s", err);
//         return &e404;
//     }

//     reverse_path.new_init(allocator: allocator);
//     reverse_path.appendf("/%s", temp.name)!!;
//     int i = 0;
//     while (temp != null && i < nodes.len - 1) {
//         temp = get_next_node(temp, nodes[i++])??null;
//         if (temp == null) { continue; }
//         if (temp.name[0] == '{' && temp.name[^1] == '}') {
//             (*args)[temp.name[1:^2]] = nodes[i];
//         }
//         reverse_path.appendf("/%s", temp.name);
//     }

//     if (temp == null) {
//         args.set("reverse_path", "/e404");
//         return &e404;
//     }
    
//     args.set("reverse_path", reverse_path.copy_str(allocator));
//     reverse_path.free();
//     RouteFunction res = temp.apply;
//     return res;
// }

// fn void add_route(String uri, RouteFunction apply, Allocator allocator = &c3web::alloc) {
//     count++;
//     if (uri[0] == '/' && uri.len > 1) uri = uri[1..];

//     if (!(uri.contains("{") && uri.contains("}"))) 
//     {   // Dynamic URI check
//         _lowLevel[uri] = new_route(name: uri, apply: apply);
//         return;
//     }

//     String[] nodes = uri.split("/", allocator: allocator);
//     defer allocator::free(allocator, nodes);
//     RouteNode* temp;

//     if (!_lowLevel.has_key(nodes[0])) {
//         temp = new_route(nodes[0]);
//         _lowLevel[nodes[0]] = temp;
//     } else {
//         temp = _lowLevel[nodes[0]]!!;
//     }

//     foreach (i, node : nodes[..^2]) {
//         if (try _temp = get_next_node(temp, node)) {
//             temp = _temp;
//             continue;
//         }
//         String key = nodes[i + 1].is_braced() ? "{}" : nodes[i + 1];
//         temp.subnodes[key] = temp = new_route(nodes[i + 1]);
//     }

//     temp.apply = apply;
// }

// fn void init_route_map() {
//     _lowLevel.new_init(allocator: &c3web::alloc);
//     tagsMap.new_init(allocator: &c3web::alloc);
//     preload.new_init(allocator: &c3web::alloc);
// }

// fn void destroy_route_map() {
//     _lowLevel.free();
//     tagsMap.free();
//     preload.free();
// }

// import c3web::server;

// fn void add_tag(String func, String key, String value, bool recursive = false, bool hidden = false) {
//     if (key != "folder" || (key == "folder" && !hidden)) {
//         if (!tagsMap.has_key(func)) { tagsMap[func] = object::new_obj(&c3web::alloc); }
//         tagsMap[func]!!.set(key, value);
//     }
//     if (key == "folder") {
//         String filename = value;

//         PathList list;
//         defer list.free();

//         Path ls = path::new(filename, allocator: &c3web::alloc)!!;
//         defer ls.free_with_allocator(&c3web::alloc);
        
//         if (os::native_is_dir(filename)) {
//             list = path::new_ls(ls, allocator: &c3web::alloc)!!;
//         } else {
//             ls = ls.new_append(filename)!!;
//             filename = ls.to_new_string(allocator: &c3web::alloc);
//             if (path::is_dir(ls)) {
//                 list = path::new_ls(ls, allocator: &c3web::alloc)!!;
//             }
//         }
//         foreach (Path folder_file: list) {
//             server::tty_log(DEBUG, "Adding @File route from @Folder: %s/%s", func, folder_file);
//             String route = string::new_format("%s/%s", func, folder_file, allocator: &c3web::alloc);
//             defer route.free();
//             String path = string::new_format("%s/%s", filename, folder_file, allocator: &c3web::alloc);
//             defer path.free();
//             Path relative = path::new(path, allocator: &c3web::alloc)!!;
//             defer relative.free_with_allocator(&c3web::alloc);
//             if (path::is_dir(relative)) {
//                 if (recursive) {
//                     server::tty_log(DEBUG, "Adding @Folder route from @Folder %s: %s", func, route);
//                     server::tty_log(DEBUG, "%s: %s", func, path);
//                     if (!hidden) {
//                         add_route(route, &folder);
//                     }
//                     add_tag(route, "folder", path, recursive, hidden);
//                 }
//                 continue;
//             }
//             add_route(route, &file);
//             add_tag(route, "file", path);
//         }
//     }
// }

// fn RouteNode*! get_next_node(RouteNode* from, String to) {
//     return from.subnodes[to] ?? from.subnodes["{}"];
// }

// macro RouteNode* new_route(String name, HashMap(<String, RouteNode*>) subnodes = {}, RouteFunction apply = null) {
//     return allocator::clone(&c3web::alloc, RouteNode {name, subnodes, apply != null, apply});
// }

// fn bool String.is_braced(self) {
//     return self[0] == '{' && self[^1] == '}';
// }