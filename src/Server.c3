module c3web;
import std::collections::map;

LibcAllocator alloc;

struct FolderConfig {
    String path;
    bool recursive;
    bool hidden;
}

struct ControllerParadise {
    inline HttpRequest req;
    HashMap(<String,String>) args;
    Allocator allocator;
}

def Cref = ControllerParadise;
def Request = ControllerParadise;

def @Route(uri) = { @tag("controller", uri) };
def @File(uri) = { @tag("file", uri) };
def @Folder(uri) = { @tag("folder", uri) };

macro bool @method_has_tag(#self, $method, $tag) {
  return $typeof(*#self).$eval($method).has_tagof($tag);
}

fn void ControllerParadise.init(ControllerParadise* self) {
    $foreach($method : $typeof(*self).methodsof)
        $if @method_has_tag(self, $method, "controller"):
            var $tag = $typeof(*self).$eval($method).tagof("controller");
            routes::add_route($tag, &$typeof(*self).$eval($method));
            routes::add_tag($tag, "controller", $tag);
            $if @method_has_tag(self, $method, "file"):
                var $filetag = $typeof(*self).$eval($method).tagof("file");
                routes::add_tag($tag, "file", $filetag);
            $else
                $if @method_has_tag(self, $method, "folder"):
                    var $foldertag = $typeof(*self).$eval($method).tagof("folder");
                    var $MyType = $typeof($foldertag);
                    $if $MyType.typeid == String.typeid:
                        routes::add_tag($tag, "folder", $foldertag);
                    $else
                        routes::add_tag($tag, "folder", $foldertag.path, $foldertag.recursive, $foldertag.hidden);
                    $endif
                $endif
            $endif
        $endif
    $endforeach
}

module c3web::server @private;

const NAME = "c3web";
const VERSION = "0.1.0";
const SUBVERSION = "PRERELEASE";

import c3web::routes;
import libc;
import std::thread;
import libuv;
import std::io;
import std::os::win32;
import std::collections::map;
import std::collections::object;
import c3web::utils;

const DEFAULT_PORT = 7000;
const UV_ECONNRESET = -4077;
const UV_EOF = -4095;
const DEFAULT_BACKLOG = 128;

Object* cors_config;
UVTty* tty;
UVTcp* _server;
Platform_sockaddr_in addr;
CULongLong curr = 0;
ControllerParadise paradise;

import std::collections::list;

macro void log(String message) {
    $if $feature(DEBUG):
        io::print($$LINE);
        io::print(" ");
        io::printn(message);
    $endif
}

fn void on_close(UVHandle* handle) {
    OnStackAllocator* a = handle.data;
    a.free();
    allocator::free(&c3web::alloc, a.data);
    allocator::free(&c3web::alloc, a);
    allocator::free(&c3web::alloc, handle);
}

fn void alloc_buffer(UVHandle *handle, CLong suggested_size, UVBuf *buf) {
    *buf = libuv::uv_buf_init(allocator::malloc((OnStackAllocator*) handle.data, suggested_size), (CUInt) suggested_size);
}

fn void write_uv_data(UVStream* client, void* data, usz len, int need_copy_data, int need_free_data) {
    UVBuf* buf = allocator::new((OnStackAllocator*) client.data, UVBuf);
//    defer allocator::free((OnStackAllocator*)client.data, data);
    defer allocator::free((OnStackAllocator*)client.data, buf);
	if(data == null || len == 0) {
		return;
	}
	if(len == (uint) -1) {
		len = ((ZString)data).len();
	}
	*buf = libuv::uv_buf_init(data, (uint) len);
    libuv::uv_try_write(client, buf, 1);
    libuv::uv_close(client, &on_close);
} 

fn void echo_read(UVStream *client, CLong nread, UVBuf *buf) {
    Allocator _alloc = (OnStackAllocator*) client.data;

    defer if (buf.base) {
        allocator::free(_alloc, buf.base);
    }
    
    if (nread > 0) {
        HttpRequest* req = allocator::new(_alloc, HttpRequest); 
        req.headers.new_init(allocator: &c3web::alloc);
        defer req.free(_alloc);
        defer allocator::free(_alloc, req);
        if (catch excuse = req.read((char*)buf.base, nread, _alloc)) {
            io::eprintn(excuse);
            return;
        }

        tty_log(DEBUG, "-> %s %s", req.method, req.uri);
        ZString ret = "HTTP/1.1 200 OK\r\n\r\nPong";
        
        write_uv_data(client,ret,ret.len(),1,1);
//        allocator::free(_alloc, ret);
    }
    else if (nread < 0) {
        libuv::uv_close(client, &on_close);
    }
}

bool hi = false;

fn void worker_thread(void* arg) {
    UVLoop loop;
    if (libuv::uv_loop_init(&loop)) {
        io::eprintn("loop init failed");
        return;
    }

    // UVSignal* signal = allocator::new(&c3web::alloc, UVSignal);
    // libuv::uv_signal_init(&loop, signal);
    // libuv::uv_signal_start(signal, &close, 2); // SIGINT
    // if (!hi) {
    //     signal.data = (void*) 1;
    //     hi = true;
    // }

    UVTcp tcp;
    libuv::uv_tcp_init(&loop, &tcp);
    libuv::uv_tcp_open(&tcp, *((UVOsSock*) arg));
    libuv::uv_tcp_keepalive(&tcp, 1, 1);
    
    libuv::uv_listen((UVStream*) &tcp, DEFAULT_BACKLOG, &on_new_connection);
    libuv::uv_run(&loop, UV_RUN_DEFAULT);
    libuv::uv_loop_close(&loop);    
}


fn void on_new_connection(UVStream *server, CLong status) {
    // assert(server == (UVStream*) _server);
    if (status < 0) {
        io::eprintf("New connection error %s\n", libuv::uv_strerror((CInt)status));
        return;
    }

    //log("new uvtcp");
    libuv::UVTcp* client = allocator::new(&c3web::alloc, UVTcp);
    //log("new allocator");
    void* allocator = allocator::new(&c3web::alloc, OnStackAllocator);
    //log("new data");
    char[] data = allocator::new_array(&c3web::alloc, char, 65536 * 2);
    //log("init alloc");
    ((OnStackAllocator*) allocator).init(data, &c3web::alloc);
    client.data = allocator;
    libuv::uv_tcp_init(server.loop, client);
    libuv::uv_accept(server, client);
    libuv::uv_read_start(client, &alloc_buffer, &echo_read);
}

fn void _tty_log(ZString s) {
    UVBuf buf;
    buf.base = (CChar*) s;
    buf.len = s.len();
    libuv::uv_try_write((UVStream*) tty, &buf, 1);
}

module c3web::server @public;
import c3web::config;
import c3web::routes;
import libuv;
import std::time;
import std::collections::object;
import std::io::path;

enum LogType : int (String name) {
    INFO = "\u001b[34mINFO\u001b[0m",
    DEBUG = "\u001b[37mDEBUG\u001b[0m",
    SEVERE = "\u001b[31mSEVERE\u001b[0m",
    WARNING = "\u001b[33mWARNING\u001b[0m"
}

fn void tty_log(LogType type, String fmt, args...) {
    $if !$feature(DEBUG):
        if (type == DEBUG) {
            return;
        }
    $endif
    String _fmt = string::join_new({type.name, "\t| ", fmt, "\n"}, "", &c3web::alloc);
    ZString buf = string::new_format_zstr(_fmt, ...args, allocator: &c3web::alloc);
    _tty_log(buf);
    _fmt.free();
    allocator::free(&c3web::alloc, buf);
}

// fn void on_uv_walk(UVHandle* handle, void* arg) {
//     libuv::uv_close(handle, null);
// }
// import libc;

// fn void timer_cb(UVTimer* handle) {
//     libc::exit(0);
// }

// fn void close(UVSignal* signal, long signum) {
//     int result = libuv::uv_loop_close(signal.loop);
//     if(result == -4082) { // UV_EBUSY
//         libuv::uv_walk(signal.loop, &on_uv_walk, null);
//     }
//     if (signal.data != null) {
//         tty_log(INFO, "Closing server...");
//     }
//     UVTimer timer;
//     libuv::uv_timer_init(libuv::uv_default_loop(), &timer);
//     libuv::uv_timer_start(&timer, &timer_cb, 5000, 0);
// }
bool reload = false;
fn void on_change(UVFsEvent* handle, CChar* filename, long events, long status) {
    if (events != 2) libuv::uv_close(handle, null);
    if (reload) {
        reload = false;
        return;
    }
    io::printn(*handle);
    CChar* buffer = allocator::malloc(&c3web::alloc, 1024);
    libuv::uv_fs_event_getpath(handle, buffer, (CLongLong*) &&1024); 
    tty_log(DEBUG, "Changed %s", (ZString) buffer);
    String file = ((ZString) buffer).copy(&c3web::alloc);
    allocator::free(&c3web::alloc, buffer);
    Request req;
    req.allocator = &c3web::alloc;
    req.headers.new_init(allocator: &c3web::alloc);
    req.args.new_init(allocator: &c3web::alloc);
    req.args["filename"] = file;
    req.args["force-preload"] = "true";
    HttpResponse res = routes::file(&req);
    req.free();
    DataPreload pr = routes::preload[file]!!;
    pr.data = res.body.copy_str(&c3web::alloc);
    routes::preload[file] = pr;
    res.free();
    reload = true;
}

fn int start_server(Config config) {
    cors_config = config.cors;

    usz worker_threads = config.workers > 0 ? config.workers : libuv::uv_available_parallelism();

    tty = allocator::new(&c3web::alloc, UVTty);
    libuv::uv_tty_init(libuv::uv_default_loop(), tty, 2, 1);
    libuv::uv_tty_set_mode(tty, UV_TTY_MODE_NORMAL);

    UVLoop* loop = allocator::new(&c3web::alloc, UVLoop);
    libuv::uv_loop_init(loop);

    UVUtsname name;
    libuv::uv_os_uname(&name);
    tty_log(INFO, "Starting %s (%s:%s) on %s %s...", NAME, VERSION, SUBVERSION, (ZString) &name.sysname, (ZString) &name.release);
    if (SUBVERSION != "VERSION") {
        tty_log(WARNING, "You are using Testing version of %s. This is NOT recommended for production use.", NAME);
    }
    tty_log(INFO, "Using %s worker threads. (%s)", worker_threads, config.workers > 0 ? "Config Value" : "uv_available_parallelism()");

    tty_log(INFO, "Registering routes...");
    Clock clock;
    clock.mark();
    paradise.init();
    tty_log(INFO, "Registered %d routes in %s.", routes::count, clock.mark());
    tty_log(DEBUG, "Routes initialisation is currently not compile-time. Having many routes would probably take some time...");
    
    int preload_files = config.experimental.get_int("preload-files") ?? 0;
    int preload_folders = config.experimental.get_int("preload-folders") ?? 0;
    if (preload_files || preload_folders) {
        tty_log(INFO, "Caching routes... (Set by Config)");
        tty_log(DEBUG, "Caching takes some time. Please wait...");
        clock.mark();
        routes::tagsMap.@each (; String key, Object* value) {
            String file = value.get_string("file")??"";
            if (file != "" && preload_files) {
                if (!routes::preload.has_key(file)) {
                    routes::preload[file] = DataPreload {.mode = PreloadMode.from_ordinal(0)};
                    switch (preload_files) {
                        case 1: 
                            Request req;
                            req.allocator = &c3web::alloc;
                            req.headers.new_init(allocator: &c3web::alloc);
                            req.args.new_init(allocator: &c3web::alloc);
                            req.args["filename"] = file;
                            HttpResponse res = routes::file(&req);
                            req.free();
                            DataPreload pr = routes::preload[file]!!;
                            tty_log(DEBUG, "%s (%s) -> {%s, %s, %s}", key, value, pr.mode, pr.last_updated, pr.data);
                        case 3:
                            // Path _path = path::new(file, &c3web::alloc)!!;
                            // Path path = _path.new_absolute(&c3web::alloc)!!;
                            // _path.free();
                            // String absolute = path.to_new_string(&c3web::alloc); 
                            // path.free();
                    
                            UVFsEvent* event = allocator::new(&c3web::alloc, UVFsEvent);
                            libuv::uv_fs_event_init(loop, event);
                            tty_log(DEBUG, "Adding Watcher for %s", file);
                            libuv::uv_fs_event_start(event, (UVFsEventCb) &on_change, (CChar*) file.zstr_copy(), 1);
                    }
                }
            }
            if (((value.get_string("folder")??"")!="") && preload_folders) {
                preload_folders = 0;
                tty_log(WARNING, "Preload @Folders is not implemented. Skipping...");
            }
        };
        tty_log(INFO, "Done caching in %s.", clock.mark());
    }

    UVTcp server;
    _server = &server;
    libuv::uv_tcp_init(loop, _server);
    libuv::uv_ip4_addr((CChar*) config.address.zstr_copy(&c3web::alloc), config.port, &addr);
    libuv::uv_tcp_bind(_server, (Platform_sockaddr*)&addr, 0);
    libuv::uv_tcp_keepalive(_server, 1, 1);
    libuv::uv_tcp_simultaneous_accepts(_server, 1);
    UVOsSock sock;
    libuv::uv_fileno((UVHandle*) _server, (UVOsFd*) &sock);

    UVThread* workers = allocator::new_array(&c3web::alloc, UVThread, worker_threads);
    for (usz i = 0; i < worker_threads; i++) {
        libuv::uv_thread_create(&workers[i], &worker_thread, (void*) &sock);
    }
    tty_log(DEBUG, "Created %d threads.", worker_threads);

    if (cors_config && cors_config.get_bool("enabled")??false) {
        tty_log(INFO, "CORS Middleware Enabled.");
    }

    tty_log(INFO, "Listening on %s:%d...", config.address, config.port);

    libuv::uv_run(loop, UV_RUN_DEFAULT);

    for (usz i = 0; i < worker_threads; i++) {
        libuv::uv_thread_join(&workers[i]);
    }

    libuv::uv_loop_close(loop);
    libuv::uv_loop_close(libuv::uv_default_loop());

    return 0;
}