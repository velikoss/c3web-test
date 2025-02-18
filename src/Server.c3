module c3web;
import std::collections::map;

LibcAllocator alloc;

struct FolderConfig {
    String path;
    bool recursive;
    bool hidden;
}

// struct ControllerParadise {
//     inline HttpRequest req;
//     HashMap(<String,String>) args;
//     Allocator allocator;
// }

// def Cref = ControllerParadise;
// def Request = ControllerParadise;

// def @Route(uri) = { @tag("controller", uri) };
// def @File(uri) = { @tag("file", uri) };
// def @Folder(uri) = { @tag("folder", uri) };

// macro bool @method_has_tag(#self, $method, $tag) {
//   return $typeof(*#self).$eval($method).has_tagof($tag);
// }

// fn void ControllerParadise.init(ControllerParadise* self) {
//     $foreach($method : $typeof(*self).methodsof)
//         $if @method_has_tag(self, $method, "controller"):
//             var $tag = $typeof(*self).$eval($method).tagof("controller");
//             routes::add_route($tag, &$typeof(*self).$eval($method));
//             routes::add_tag($tag, "controller", $tag);
//             $if @method_has_tag(self, $method, "file"):
//                 var $filetag = $typeof(*self).$eval($method).tagof("file");
//                 routes::add_tag($tag, "file", $filetag);
//             $else
//                 $if @method_has_tag(self, $method, "folder"):
//                     var $foldertag = $typeof(*self).$eval($method).tagof("folder");
//                     var $MyType = $typeof($foldertag);
//                     $if $MyType.typeid == String.typeid:
//                         routes::add_tag($tag, "folder", $foldertag);
//                     $else
//                         routes::add_tag($tag, "folder", $foldertag.path, $foldertag.recursive, $foldertag.hidden);
//                     $endif
//                 $endif
//             $endif
//         $endif
//     $endforeach
// }

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
CULongLong curr = 0;
// ControllerParadise paradise;


UVLoop* uv_loop;
void* routes;
int listener_count;
UVAsync* listener_async_handles;
UVLoop* listener_event_loops;
UVBarrier* listeners_created_barrier;

import std::collections::list;



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
import std::net::os;

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


fn int http_server_write_response_single(WriteContext* write_context, ZString* response) {
    HttpConnection* connection = write_context.connection;

    if (connection.state == OPEN) {
        UVWrite* write_req = (UVWrite*) mem::malloc(UVWrite.sizeof + UVBuf.sizeof);
        UVBuf* resbuf = (UVBuf*) (write_req + 1); // woah

        resbuf.base = (CChar*) response;
        resbuf.len = response.len();

        write_req.data = write_context;

        UVStream* stream = (UVStream*) &(write_context.connection.stream);

        if (libuv::uv_is_writable(stream)) {
            /* Ensuring that the the response can still be written. */
            libuv::uv_write(write_req, stream, resbuf, 1, &http_server_after_write);
            /* TODO: Use the return values from uv_write() */
        } else {
            /* The connection was closed, so we can write the response back, but we still need to free up things */
            http_server_cleanup_write(resbuf.base, write_context, write_req);
        }
    }

    return 0;
}

fn void http_server_cleanup_write(ZString response_string, WriteContext* write_context, UVWrite* write_req) {
    mem::free(response_string);
    mem::free(write_context);
    mem::free(write_req);
}

fn void http_stream_on_read_http_parser(UVStream* tcp, CLongLong nread, UVBuf* buf) {
    HttpConnection* connection = (HttpConnection*)(tcp.data);

    if (nread > 0) {
        /* Need to tell the buffer that we care about the next nread bytes */
        connection.buffer.consume(nread);
        connection.parser.execute(&parser_settings, (ZString*) buf.base, nread);

        if (connection.parser.http_errno) {
            handle_bad_request(connection);
        } else {
            /* We finished processing this chunk of data, therefore we can't get rid of any chunks that were read before
             * the current one we're reading.
             *
             * We can't get rid of the one we're currently processing as it may contain a partial request that will
             * only be complete with the next chunk coming into a subsequent call of this function. */
            connection.buffer.sweep()!!;
        }
    } else if (nread == 0) {
        /* no-op - there's no data to be read, but there might be later */
    }
    else if (nread == UV_ENOBUFS) {
        handle_buffer_exceeded_error(connection);
    }
    else if (nread == UV_EOF){
        UVShutdown* req = mem::new(UVShutdown);
        req.data = connection;
        libuv::uv_shutdown(req, &(connection.stream), &http_stream_on_shutdown);
    }
    else if (nread == UV_ECONNRESET || nread == UV_ECONNABORTED) {
        /* Let's close the connection as the other peer just disappeared */
        http_stream_close_connection(connection);
    } else {
        /* We didn't see this coming, but an unexpected UV error code was passed in, so we'll
         * respond with a blanket 500 error if we can */
        handle_internal_error(connection);
    }
}

fn void http_stream_on_shutdown(UVShutdown* req, int status) {
    HttpConnection* connection = req.data;
    UVHandle* stream = &(connection.stream);
    if (connection.state == OPEN) {
        http_stream_close_connection(connection);
    }
    mem::free(req);
}

fn void handle_bad_request(HttpConnection* connection)
{
    if (connection.request) {
        connection.request.state = BAD_REQUEST;
    }

    handle_request_error(connection);
}

fn void handle_buffer_exceeded_error(HttpConnection* connection)
{
    if (connection.request) {
        connection.request.state = SIZE_EXCEEDED;
    }

    handle_request_error(connection);
}

fn void handle_internal_error(HttpConnection* connection)
{
    if (connection.request) {
        connection.request.state = INTERNAL_ERROR;
    }

    handle_request_error(connection);
}

fn void handle_request_error(HttpConnection* connection) {
    UVHandle* stream = &(connection.stream);
    if (connection.state == OPEN) {
        libuv::uv_read_stop((UVStream*) stream);
    }

    connection.keep_alive = 0;

    if (connection.request) {
        if (connection.state == OPEN) {
            http_request_on_message_complete(&(connection.parser));
        }
    } else {
        http_stream_close_connection(connection);
    }
}

fn void http_stream_close_connection(HttpConnection* connection) {
    if (connection.state == OPEN) {
        connection.state = CLOSING;
        libuv::uv_close(&connection.stream, &http_stream_on_close);
    }
}

fn void http_stream_on_close(UVHandle* handle) {
    HttpConnection* connection = handle.data;
    if (connection.state != CLOSED) {
        connection.state = CLOSED;
        free_http_connection(connection);
    }
}

fn void http_stream_on_alloc(UVHandle* client, long suggested_size, UVBuf* buf) {
    HttpConnection* connection = (HttpConnection*) client.data;
    bool success = connection.buffer.alloc(suggested_size);
    RequestBufferChunk chunk;
    chunk.buffer = null;
    chunk.size = 0;

    if (success) {
        connection.buffer.chunk(&chunk);
    } else {
        // todo
    }
    *buf = libuv::uv_buf_init(chunk.buffer, (CUInt) chunk.size);
}

fn void* http_request_buffer_init(int size) {
    HttpRequestBuffer* buffer = mem::new(HttpRequestBuffer);
    buffer.max_size = size;
    return buffer;
}

fn HttpConnection* create_http_connection() {
    HttpConnection* connection = mem::new(HttpConnection);
    connection.buffer = http_request_buffer_init(16 * 1024);
    return connection;
}

fn void http_stream_on_connect(UVStream* stream, long status) {
    HttpConnection* connection = create_http_connection();
    libuv::uv_tcp_init(stream.loop, &(connection.stream));
    connection.parser.init(HTTP_REQUEST);

    connection.parser.data = connection;
    connection.stream.data = connection;

    int rc = libuv::uv_accept(stream, (UVStream*) &connection.stream);
    if (!rc) {
        // err
        io::eprintn("accept error");
        return;
    }
    rc = libuv::uv_read_start((UVStream*) &connection.stream, &http_stream_on_alloc, &http_stream_on_read);
        if (!rc) {
        // err
        io::eprintn("read start error");
        return;
    }
}

fn void thread_start(void* arg) {
    int rc;
    ServerContext* ctx = arg;
    UVLoop* loop = mem::new(UVLoop);
    UVTcp tcp;

    libuv::uv_loop_init(loop);
    listener_event_loops[ctx.index] = *loop;

    //cache

    Platform_sockaddr_in addr;
    UVTcp server;

    rc = libuv::uv_tcp_init_ex(loop, &server, 2);
    libuv::uv_ip4_addr("0.0.0.0", 8080, &addr);

    UVOsFd fd;
    int on = 1;
    libuv::uv_fileno(&server, &fd);
    rc = os::setsockopt((NativeSocket) fd, os::SOL_SOCKET, os::SO_REUSEPORT, (char*)&on, int.sizeof);
    if (rc) {
        // err
    }

    libuv::uv_tcp_bind(&server, (Platform_sockaddr*) &addr, 0);
    int r = libuv::uv_listen((UVStream*) &server, 128, &http_stream_on_connect);

    rc = libuv::uv_run(loop, UV_RUN_DEFAULT);
    libuv::uv_loop_close(loop);
    mem::free(loop);
}

struct StreamHandle {
    UVPipe pipe;
    UVTcp tcp;
}

def HandleStorage = char[StreamHandle.sizeof];

struct ServerContext {
    int index;
    HandleStorage server_handle;
    uint num_connects;
    UVAsync async_handle;
    UVThread thread_id;
    UVSem semaphore;
    bool tcp_nodelay;
    uint listen_backlog;
}

fn int start_server(Config config) {
    int threads = libuv::uv_available_parallelism();
    uv_loop = libuv::uv_default_loop();
    listener_count = threads;
    listener_async_handles = mem::new_array(UVAsync, listener_count);
    listener_event_loops = mem::new_array(UVLoop, listener_count);

    listeners_created_barrier = mem::new(UVBarrier);
    libuv::uv_barrier_init(listeners_created_barrier, listener_count + 1);

    UVAsync* service_handle = mem::new(UVAsync);
    libuv::uv_async_init(uv_loop, service_handle, null);

    if (listener_count == 1) {
        // Single threaded experience. Very cool
        // idk
    } else {
        ServerContext* servers = mem::new_array(ServerContext, listener_count);
        for (int i = 0; i < threads; ++i) {
            ServerContext* ctx = servers + i;
            ctx.index = i;
            int rc = libuv::uv_thread_create(&ctx.thread_id, &thread_start, ctx);
        }

        libuv::uv_run(uv_loop, UV_RUN_DEFAULT);
    }
    return 0;
}