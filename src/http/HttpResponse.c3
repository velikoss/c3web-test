module c3web;

import std::io;
import std::net;
import std::collections;
import std::core::string;
import std::core::dstring;

struct HttpResponse {
    HttpStatus status;
    HttpHeaders headers;
    DString body;
}

fn String itoa(usz i, void* alloc) {
    server::tty_log(DEBUG, "Itoa %d", i);
    DString buffer = dstring::new("", (OnStackAllocator*) alloc);
    defer buffer.free();
    while (i > 0) {
        usz a = i % 10;
        buffer.insert_at(0, a + '0');
        i /= 10;
    }
    return buffer.str_view();
}

fn ZString HttpResponse.zwrite(HttpResponse* self, void* alloc) {
    DString buffer = dstring::new("", (OnStackAllocator*) alloc);
    //buffer.appendf("HTTP/1.1 %d %s\r\n", self.status.code, self.status.message);
    buffer.append_chars("HTTP/1.1 200 ");
    buffer.append_chars(self.status.message);
    buffer.append_chars("\r\n");
    

    if (self.body.len() > 0) {
        if (!self.headers.is_initialized()) {
            self.headers.new_init(allocator: (OnStackAllocator*) alloc);
        }

        StringList content_length;
        content_length.new_init(1, allocator: (OnStackAllocator*) alloc);
        String i = itoa(self.body.len(), alloc);
        content_length.push(i); // Leaked Allocation
        defer allocator::free((OnStackAllocator*) alloc, i);
        self.headers.set("Content-Length", content_length);
    }
    self.headers.@each(; String key, List(<String>) values)
    {
        buffer.append_chars(key);
        buffer.append_chars(": ");
        foreach (value: values) {
            buffer.append_chars(value);
            // todo multiple headers
        }
        buffer.append_chars("\r\n");
    };
    if (self.headers.len() > 0) {
        buffer.append_chars("\r\n");
    }
    foreach (char c: self.body) {
        buffer.append_char(c);
    }
    ZString ret = buffer.copy_zstr((OnStackAllocator*) alloc);
    buffer.free();
    return ret;
}   

fn void HttpResponse.free(HttpResponse* self) {
    self.headers.@each(; String key, List(<String>) values)
    {
        values.free();
    };
    self.headers.free();
    self.body.free();
    // allocator::free(&c3api::alloc, self.body);
    //free(self);
}
