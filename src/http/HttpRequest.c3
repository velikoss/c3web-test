module c3web;

import std::io;
import std::net;
import std::collections;
import std::core::string;

const ulong MAX_READ_SIZE = /* 5 MiB */ 1024 * 1024 * 5;

struct HttpRequest {
    HttpVerb method;
    String uri;
    HttpHeaders headers;
    String body;
}

fault HttpRequestError {
    NO_DATA,
    REQUEST_TOO_LARGE,
    MALFORMED_REQUEST,
    UNSUPPORTED_VERSION,
    UNIMPLEMENTED
}

fault HttpVerbError {
    INVALID_VERB
}

fn void! HttpRequest.set_method(HttpRequest* self, String verb) {
    self.method = {|
        switch (verb) {
            case "HEAD": return HttpVerb.HEAD;
            case "GET": return HttpVerb.GET;
            case "PATCH": return HttpVerb.PATCH;
            case "POST": return HttpVerb.POST;
            case "PUT": return HttpVerb.PUT;
            case "DELETE": return HttpVerb.DELETE;
            case "OPTIONS": return HttpVerb.OPTIONS;
            case "TRACE": return HttpVerb.TRACE;
            case "CONNECT": return HttpVerb.CONNECT;
            default: return HttpVerbError.INVALID_VERB?;
        }
    |}!;
}

import libc;


fn void! HttpRequest.read(HttpRequest* self, char* bytes, CLongLong nread, Allocator allocator = allocator::heap()) {
    if (nread == 0) return HttpRequestError.NO_DATA?;
    usz i = 0;
    DString line; line.new_init(allocator: allocator);
    defer line.free();
    for (; bytes[i + 1] != '\n'; i++) {
        line.append_char(bytes[i]);
    }
    String st = line.copy_str(allocator);
    String[] status = st.split(" ", allocator: allocator);
    self.set_method(status[0])!!;
    self.uri = status[1].copy(allocator);
    defer allocator::free(allocator, status);

    if (status.len != 3) return HttpRequestError.MALFORMED_REQUEST?;
    // if (status[^1] != "HTTP/1.1") {
    //     io::printn(status[^1]);
    //     return HttpRequestError.UNSUPPORTED_VERSION?;
    // }

    while (!(st.trim().len == 0) ) {
        line.clear();
        for (; bytes[i + 1] != '\n'; i++) {
            line.append_char(bytes[i]);
        }
        st = line.copy_str(allocator);
        String[] header = st.split(": ", max: 1, allocator: allocator);
        self.headers.add_header(headerName: header[0], headerValue: header[1], allocator: allocator);
    }

    line.clear();
    for (; i < nread; i++) {
        line.append_char(bytes[i]);
    }
    self.body = line.copy_str(allocator);
}

fn void HttpRequest.free(HttpRequest* self, Allocator allocator = allocator::heap()) {
    self.headers.@each(; String key, List(<String>) values)
    {
        values.free();
    };
    self.headers.free();
    self.uri.free(allocator);
    self.body.free(allocator);
}
