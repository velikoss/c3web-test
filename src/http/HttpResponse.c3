module c3web;

def Http_response_complete_callback = fn void(void* user_data);

struct WriteContext {
    HttpConnection* connection;
    HttpRequest* request;
    void* user_data;
    Http_response_complete_callback callback;
}