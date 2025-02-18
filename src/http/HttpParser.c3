module c3web;
import libc;

const HTTP_MAX_HEADER_SIZE = 8 * 1024;
def HttpCb = fn int (HttpParser*);
def HttpDataCb = fn int (HttpParser*, char* at, usz length);

struct HttpParserSettings {
    HttpCb     on_message_begin;
    HttpDataCb on_url;
    HttpDataCb on_status;
    HttpDataCb on_header_field;
    HttpDataCb on_header_value;
    HttpCb     on_headers_complete;
    HttpDataCb on_body;
    HttpCb     on_message_complete;
}

struct HttpParser {
    bitstruct : uint 
    {
        uint type : 0..1;
        uint flags : 2..8;
        uint state : 9..16;
        uint header_state : 17..23;
        uint index : 24..31;
    }
    
    uint nread;
    ulong content_length;
    ushort http_major;
    ushort http_minor;
    
    bitstruct : uint 
    {
        uint status_code : 0..15;
        uint method : 16..23;
        uint http_errno : 24..30;
        uint upgrade : 31..31;
    }

    void *data;
}

enum HttpParserType { HTTP_REQUEST, HTTP_RESPONSE, HTTP_BOTH }

enum ParserState: inline uint { 
    S_ZERO
    , S_DEAD /* IMPORTANT THAT THIS IS > 0 */
    , S_START_REQ_OR_RES
    , S_RES_OR_RESP_H
    , S_START_RES
    , S_RES_H
    , S_RES_HT
    , S_RES_HTT
    , S_RES_HTTP
    , S_RES_FIRST_HTTP_MAJOR
    , S_RES_HTTP_MAJOR
    , S_RES_FIRST_HTTP_MINOR
    , S_RES_HTTP_MINOR
    , S_RES_FIRST_STATUS_CODE
    , S_RES_STATUS_CODE
    , S_RES_STATUS_START
    , S_RES_STATUS
    , S_RES_LINE_ALMOST_DONE
    , S_START_REQ
    , S_REQ_METHOD
    , S_REQ_SPACES_BEFORE_URL
    , S_REQ_SCHEMA
    , S_REQ_SCHEMA_SLASH
    , S_REQ_SCHEMA_SLASH_SLASH
    , S_REQ_SERVER_START
    , S_REQ_SERVER
    , S_REQ_SERVER_WITH_AT
    , S_REQ_PATH
    , S_REQ_QUERY_STRING_START
    , S_REQ_QUERY_STRING
    , S_REQ_FRAGMENT_START
    , S_REQ_FRAGMENT
    , S_REQ_HTTP_START
    , S_REQ_HTTP_H
    , S_REQ_HTTP_HT
    , S_REQ_HTTP_HTT
    , S_REQ_HTTP_HTTP
    , S_REQ_FIRST_HTTP_MAJOR
    , S_REQ_HTTP_MAJOR
    , S_REQ_FIRST_HTTP_MINOR
    , S_REQ_HTTP_MINOR
    , S_REQ_LINE_ALMOST_DONE
    , S_HEADER_FIELD_START
    , S_HEADER_FIELD
    , S_HEADER_VALUE_DISCARD_WS
    , S_HEADER_VALUE_DISCARD_WS_ALMOST_DONE
    , S_HEADER_VALUE_DISCARD_LWS
    , S_HEADER_VALUE_START
    , S_HEADER_VALUE
    , S_HEADER_VALUE_LWS
    , S_HEADER_ALMOST_DONE
    , S_CHUNK_SIZE_START
    , S_CHUNK_SIZE
    , S_CHUNK_PARAMETERS
    , S_CHUNK_SIZE_ALMOST_DONE
    , S_HEADERS_ALMOST_DONE
    , S_HEADERS_DONE
    
    /* IMPORTANT: 'S_HEADERS_DONE' MUST BE THE LAST 'HEADER' STATE. ALL
     * STATES BEYOND THIS MUST BE 'BODY' STATES. IT IS USED FOR OVERFLOW
     * CHECKING. SEE THE PARSING_HEADER() MACRO.
     */
    
    , S_CHUNK_DATA
    , S_CHUNK_DATA_ALMOST_DONE
    , S_CHUNK_DATA_DONE
    , S_BODY_IDENTITY
    , S_BODY_IDENTITY_EOF
    , S_MESSAGE_DONE
}

enum HttpErrno : inline uint (ZString message) {
    OK = "success",
    CB_MESSAGE_BEGIN = "the on_message_begin callback failed",
    CB_URL = "the on_url callback failed",
    CB_HEADER_FIELD = "the on_header_field callback failed",
    CB_HEADER_VALUE = "the on_header_value callback failed",
    CB_HEADERS_COMPLETE = "the on_headers_complete callback failed",
    CB_BODY = "the on_body callback failed",
    CB_MESSAGE_COMPLETE = "the on_message_complete callback failed",
    CB_STATUS = "the on_status callback failed",
    INVALID_EOF_STATE = "stream ended at an unexpected time",
    HEADER_OVERFLOW = "too many header bytes seen; overflow detected",
    CLOSED_CONNECTION = "data received after completed connection: close message",
    INVALID_VERSION = "invalid HTTP version",
    INVALID_STATUS = "invalid HTTP status code",
    INVALID_METHOD = "invalid HTTP method",
    INVALID_URL = "invalid URL",
    INVALID_HOST = "invalid host",
    INVALID_PORT = "invalid port",
    INVALID_PATH = "invalid path",
    INVALID_QUERY_STRING = "invalid query string",
    INVALID_FRAGMENT = "invalid fragment",
    LF_EXPECTED = "LF character expected",
    INVALID_HEADER_TOKEN = "invalid character in header",
    INVALID_CONTENT_LENGTH = "invalid character in content-length header",
    INVALID_CHUNK_SIZE = "invalid character in chunk size header",
    INVALID_CONSTANT = "invalid constant string",
    INVALID_INTERNAL_STATE = "encountered unexpected internal state",
    STRICT = "strict mode assertion failed",
    PAUSED = "parser is paused",
    UNKNOWN = "an unknown error occurred"
}

fn void HttpParser.init(HttpParser* self, HttpParserType t) {
    void* data = self.data;
    libc::memset(self, 0, HttpParser.sizeof);
    self.data = data;
    self.type = t.ordinal;
    self.state = (t == HTTP_REQUEST ? ParserState.S_START_REQ : (t == HTTP_RESPONSE ? ParserState.S_START_RES : ParserState.S_START_REQ_OR_RES));
    self.http_errno = HttpErrno.OK;
}

macro bool @count_header_size(#parser, #v) {
    #parser.nread += (uint) #v;
    if (@unlikely(#parser.nread > (HTTP_MAX_HEADER_SIZE))) {
        #parser.http_errno = HttpErrno.HEADER_OVERFLOW;
        return true;
    }
    return false;
}

macro long @callback_data(#self, #settings, #p_state, #p, #data, #a) {
    do {                                                                 
        assert(#self.http_errno == HttpErrno.OK);                   
        if (@likely(#settings.#a != null)) {                    
            #self.state = p_state;
            if (@unlikely(0 != #settings.#a(self))) {
                #self.http_errno = HttpErrno.CB_MESSAGE_COMPLETE;
            }
            #p_state = ParserState.from_ordinal(self.state);
            /* We either errored above or got paused; get out */
            if (@unlikely(#self.http_errno != HttpErrno.OK)) {
                return ((char*)p - (char*)data + 1);
            }
        }
    } while(0);
    return -1;
}

macro long @callback_notify(#self, #settings, #p_state, #p, #data, #a) {
    do {                                                                 
        assert(#self.http_errno == HttpErrno.OK);                   
        if (@likely(#settings.#a != null)) {                    
            #self.state = p_state;
            if (@unlikely(0 != #settings.#a(self))) {
                #self.http_errno = HttpErrno.CB_MESSAGE_COMPLETE; // todo better errno
            }
            #p_state = ParserState.from_ordinal(self.state);
            /* We either errored above or got paused; get out */
            if (@unlikely(#self.http_errno != HttpErrno.OK)) {
                return ((char*)p - (char*)data);
            }
        }
    } while(0);
    return -1;
}

macro char @lower(#ch) {
    return #ch >= 'a' && #ch < 'z' ? ch : ch - 'A' + 'a';
}

macro bool @is_alpha(#ch) {
    return @lower(#ch) >= 'a' && @lower(#ch) <= 'z';
}

fn usz HttpParser.execute(HttpParser* self, HttpParserSettings* settings, ZString data, usz len) {
    char c, ch;
    ichar unhex_val;
    char* p = (char*) data;
    char *header_field_mark = (char*) 0; 
    char *header_value_mark = (char*) 0;
    char *url_mark = (char*) 0;
    char *body_mark = (char*) 0;
    char *status_mark = (char*) 0;
    ParserState p_state = ParserState.from_ordinal(self.state);

    do ERROR: {
        if (self.http_errno) {
            return 0;
        }
        
        if (len == 0) {
            switch (p_state) {
                case S_BODY_IDENTITY_EOF:
                    @callback_notify(self, settings, p_state, p, data, on_message_complete);
                    return 0;
                case S_DEAD:
                case S_START_REQ:
                case S_START_RES:
                case S_START_REQ_OR_RES:
                    return 0;
                default:
                    self.http_errno = HttpErrno.INVALID_EOF_STATE;
            }
        }

        if (p_state == S_HEADER_FIELD) {
            header_field_mark = data;
        }
        if (p_state == S_HEADER_VALUE) {
            header_value_mark = data;
        }
        switch (p_state) {
            case S_REQ_PATH:
            case S_REQ_SCHEMA:
            case S_REQ_SCHEMA_SLASH:
            case S_REQ_SCHEMA_SLASH_SLASH:
            case S_REQ_SERVER_START:
            case S_REQ_SERVER:
            case S_REQ_SERVER_WITH_AT:
            case S_REQ_QUERY_STRING_START:
            case S_REQ_QUERY_STRING:
            case S_REQ_FRAGMENT_START:
            case S_REQ_FRAGMENT:
                url_mark = data;
                break;
            case S_RES_STATUS:
                status_mark = data;
                break;
            default:
                break;
        }

        for (p = data; p != data + len; p++) {
            ch = *p;
            if (p_state <= S_HEADERS_DONE) {
                if (@count_header_size(self, 1)) break ERROR;
            }

            switch (p_state) {
                case S_DEAD:
                    if (@likely(ch == '\r' || ch == '\n')) break;
                    self.http_errno = HttpErrno.CLOSED_CONNECTION;
                    break ERROR;
                case S_START_REQ_OR_RES:
                    if (ch == '\r' || ch == '\n') break;
                    self.flags = 0;
                    self.content_length = usz.max;

                    if (ch == 'H') {
                        p_state = S_RES_OR_RESP_H;
                        @callback_notify(self, settings, p_state, p, data, on_message_begin);
                    } else {
                        self.type = HTTP_REQUEST;
                        p_state = S_START_REQ;
                        --p;
                    }
                    break;
                case S_START_REQ:
                    self.flags = 0;
                    self.content_length = usz.max;
                    switch (ch) {
                        case 'H':
                            p_state = S_RES_H;
                            break;
                        case '\n':
                        case '\r':
                            break;
                        default:
                            self.http_errno = HttpErrno.INVALID_CONSTANT;
                            break ERROR;
                    }
                    @callback_notify(self, settings, p_state, p, data, on_message_begin);
                    break;
                case S_RES_H:
                    if (ch != 'T') {
                        self.http_errno = HttpErrno.STRICT;
                        break ERROR;
                    }
                    p_state = S_RES_HT;
                    break;
                case S_RES_HT:
                    if (ch != 'T') {
                        self.http_errno = HttpErrno.STRICT;
                        break ERROR;
                    }
                    p_state = S_RES_HTT;
                    break;
                case S_RES_HTT:
                    if (ch != 'P') {
                        self.http_errno = HttpErrno.STRICT;
                        break ERROR;
                    }
                    p_state = S_RES_HTTP;
                    break;
                case s_res_HTTP:
                    if (ch != '/') {
                        self.http_errno = HttpErrno.STRICT;
                        break ERROR;
                    }
                    p_state = S_RES_FIRST_HTTP_MAJOR;
                    break;
                case S_RES_FIRST_HTTP_MAJOR:
                    if (@unlikely(ch < '0' || ch > '9')) {
                        self.http_errno = HttpErrno.INVALID_VERSION;
                        break ERROR;
                    }
                    parser.http_major = ch - '0';
                    p_state = S_RES_HTTP_MAJOR;
                    break;
                case S_RES_HTTP_MAJOR:
                    if (ch == '.') {
                        p_state = S_RES_FIRST_HTTP_MINOR;
                        break;
                    }
                    if (ch < '0' || ch > '9') {
                        self.http_errno = HttpErrno.INVALID_VERSION;
                        break ERROR;
                    }

                    self.http_major *= 10;
                    self.http_major += ch - '0';

                    if (@unlikely(self.http_major > 999)) {
                        self.http_errno = HttpErrno.INVALID_VERSION;
                        break ERROR;
                    }
                    break;
                case S_RES_FIRST_HTTP_MINOR:
                    if (@unlikely(ch < '0' || ch > '9')) {
                        self.http_errno = HttpErrno.INVALID_VERSION;
                        break ERROR;
                    }
                    self.http_minor = ch - '0';
                    p_state = S_RES_HTTP_MINOR;
                    break;
                case S_RES_HTTP_MINOR:
                    if (ch == ' ') {
                        p_state = S_RES_FIRST_STATUS_CODE;
                        break;
                    }

                    if (@unlikely(ch < '0' || ch > '9')) {
                        self.http_errno = HttpErrno.INVALID_VERSION;
                        break ERROR;
                    }

                    self.http_minor *= 10;
                    self.http_minor += ch - '0';

                    if (@unlikely(self.http_minor > 999)) {
                        self.http_errno = HttpErrno.INVALID_VERSION;
                        break ERROR;
                    }

                    break;
                case S_RES_FIRST_STATUS_CODE:
                    if (@unlikely(ch < '0' || ch > '9')) {
                        self.http_errno = HttpErrno.INVALID_VERSION;
                        break ERROR;
                    }
                    self.status_code = ch - '0';
                    p_state = S_RES_STATUS_CODE;
                    break;
                case S_RES_STATUS_CODE:
                    if (ch < '0' || ch > '9') {
                        switch (ch) {
                            case ' ':
                                p_state = S_RES_STATUS_START;
                            case '\r':
                                p_state = S_RES_LINE_ALMOST_DONE;
                            case '\n':
                                p_state = S_HEADER_FIELD_START;
                            default:
                                self.http_errno = HttpErrno.INVALID_STATUS;
                                break ERROR;
                        }
                        break;
                    }

                    self.status_code *= 10;
                    self.status_code += ch - '0';

                    if (@unlikely(self.status_code > 999)) {
                        self.http_errno = HttpErrno.INVALID_STATUS;
                        break ERROR;
                    }

                    break;
                case S_RES_STATUS_START:
                    if (ch == '\r') {
                        p_state = S_RES_LINE_ALMOST_DONE;
                        @callback_data(self, settings, p_state, p, data, on_status);
                        break;
                    }
                    if (ch == '\n') {
                        p_state = S_HEADER_FIELD_START;
                        @callback_data(self, settings, p_state, p, data, on_status);
                        break;
                    }
                    break;
                case S_RES_LINE_ALMOST_DONE:
                    if (ch != '\n') {
                        self.http_errno = HttpErrno.STRICT;
                        break ERROR;
                    }
                    p_state = S_HEADER_FIELD_START;
                    break;
                case S_START_REQ:
                    if (ch == '\r' || ch == '\n') break;
                    self.flags = 0;
                    self.content_length = usz.max;

                    if (@unlikely(!@is_alpha(ch))) {
                        self.http_errno = HttpErrno.INVALID_METHOD;
                        break ERROR;
                    }

                    self.method = 0;
                    self.index = 1;
                    switch (ch) {
                        case 'C': 
                            self.method = HTTP_CONNECT; 
                            break;
                        case 'D': 
                            self.method = HTTP_DELETE; 
                            break;
                        case 'G': 
                            self.method = HTTP_GET; 
                            break;
                        case 'H': 
                            self.method = HTTP_HEAD; 
                            break;
                        case 'L': 
                            self.method = HTTP_LOCK; 
                            break;
                        case 'M': 
                            self.method = HTTP_MKCOL; 
                            break;
                        case 'N': 
                            self.method = HTTP_NOTIFY; 
                            break;
                        case 'O': 
                            self.method = HTTP_OPTIONS; 
                            break;
                        case 'P': 
                            self.method = HTTP_POST; 
                            break;
                        case 'R': 
                            self.method = HTTP_REPORT; 
                            break;
                        case 'S': 
                            self.method = HTTP_SUBSCRIBE; 
                            break;
                        case 'T': 
                            self.method = HTTP_TRACE; 
                            break;
                        case 'U': 
                            self.method = HTTP_UNLOCK; 
                            break;
                        default:
                            self.http_errno = HttpErrno.INVALID_METHOD;
                            break ERROR;
                    }

                    p_state = S_REQ_METHOD; 
                    @callback_notify(self, settings, p_state, p, data, on_message_begin);
                    break;
                case S_REQ_METHOD:
                    char* matcher;
                    if (@unlikely(ch == '\0')) {
                        self.http_errno = HttpErrno.INVALID_METHOD; // Set the error for invalid method
                        break ERROR; // Jump to the ERROR label for handling
                    }

                    matcher = method_strings[self.method];
                    if (ch == ' ' && matcher[self.index] == '\0') {
                        p_state = S_REQ_SPACES_BEFORE_URL; // Update state
                    } else if (ch == matcher[self.index]) {
                        // No action needed
                    } else if (self.method == HTTP_CONNECT) {
                        if (self.index == 1 && ch == 'H') {
                            self.method = HTTP_CHECKOUT;
                        } else if (self.index == 2 && ch == 'P') {
                            self.method = HTTP_COPY;
                        } else {
                            self.http_errno = HttpErrno.INVALID_METHOD; // Set the error for invalid method
                            break ERROR; // Jump to the ERROR label for handling
                        }
                    } else if (self.method == HTTP_MKCOL) {
                        if (self.index == 1 && ch == 'O') {
                            self.method = HTTP_MOVE;
                        } else if (self.index == 1 && ch == 'E') {
                            self.method = HTTP_MERGE;
                        } else if (self.index == 1 && ch == '-') {
                            self.method = HTTP_MSEARCH;
                        } else if (self.index == 2 && ch == 'A') {
                            self.method = HTTP_MKACTIVITY;
                        } else if (self.index == 3 && ch == 'A') {
                            self.method = HTTP_MKCALENDAR;
                        } else {
                            self.http_errno = HttpErrno.INVALID_METHOD; // Set the error for invalid method
                            break ERROR; // Jump to the ERROR label for handling
                        }
                    } else if (self.method == HTTP_SUBSCRIBE) {
                        if (self.index == 1 && ch == 'E') {
                            self.method = HTTP_SEARCH;
                        } else {
                            self.http_errno = HttpErrno.INVALID_METHOD; // Set the error for invalid method
                            break ERROR; // Jump to the ERROR label for handling
                        }
                    } else if (self.index == 1 && self.method == HTTP_POST) {
                        if (ch == 'R') {
                            self.method = HTTP_PROPFIND; // or HTTP_PROPPATCH
                        } else if (ch == 'U') {
                            self.method = HTTP_PUT; // or HTTP_PURGE
                        } else if (ch == 'A') {
                            self.method = HTTP_PATCH;
                        } else {
                            self.http_errno = HttpErrno.INVALID_METHOD;
                            break ERROR;
                        }
                    } else if (self.index == 2) {
                        if (self.method == HTTP_PUT) {
                            if (ch == 'R') {
                                self.method = HTTP_PURGE;
                            } else {
                                self.http_errno = HttpErrno.INVALID_METHOD;
                                break ERROR;
                            }
                        } else if (self.method == HTTP_UNLOCK) {
                            if (ch == 'S') {
                                self.method = HTTP_UNSUBSCRIBE;
                            } else {
                                self.http_errno = HttpErrno.INVALID_METHOD;
                                break ERROR;
                            }
                        } else {
                            self.http_errno = HttpErrno.INVALID_METHOD; // Set the error for invalid method
                            break ERROR; // Jump to the ERROR label for handling
                        }
                    } else if (self.index == 4 && self.method == HTTP_PROPFIND && ch == 'P') {
                        self.method = HTTP_PROPPATCH;
                    } else {
                        self.http_errno = HttpErrno.INVALID_METHOD; // Set the error for invalid method
                        break ERROR; // Jump to the ERROR label for handling
                    }

                    ++self.index; // Increment the index
                    break;
                case S_REQ_SPACES_BEFORE_URL:
                    if (ch == ' ') break;
                    if (url_mark == null) {
                        url_mark = p;
                    }
                    if (self.method == HTTP_CONNECT) {
                        p_state = S_REQ_SERVER_START;
                    }
                    p_state = S_REQ_SERVER_START;
                    
                    break;
            }
        }
    } while(0);
}