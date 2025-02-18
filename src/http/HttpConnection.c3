module c3web;
import libuv;

enum HttpConnectionState {OPEN, CLOSING, CLOSED}

struct HttpConnection {
    UVTcp stream;
    HttpParser parser;
    UVWrite write_req;
    HttpRequest* request;
    ZString current_header_key;
    ZString current_header_value;
    int keep_alive;
    int last_was_value;
    HttpConnectionState state;
    HttpRequestBuffer* buffer;
}