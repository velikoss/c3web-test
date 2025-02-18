module c3web;

enum HttpRequestState {
    OK, SIZE_EXCEEDED, BAD_REQUEST, INTERNAL_ERROR
}

struct HttpRequest {
    ushort http_major;
    ushort http_minor;
    char method;
    int keep_alive;
    ZString url;
    void* headers;
    ZString body;
    usz body_length;
    HttpRequestState state;
}