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

macro char @t(#v) {
    $if HTTP_PARSER_STRICT
        return 0;
    $endif
    return #v;
}

const char tokens[256] = {
    /*   0 nul    1 soh    2 stx    3 etx    4 eot    5 enq    6 ack    7 bel  */
    0,       0,       0,       0,       0,       0,       0,       0,
    /*   8 bs     9 ht    10 nl    11 vt    12 np    13 cr    14 so    15 si   */
    0,       0,       0,       0,       0,       0,       0,       0,
    /*  16 dle   17 dc1   18 dc2   19 dc3   20 dc4   21 nak   22 syn   23 etb */
    0,       0,       0,       0,       0,       0,       0,       0,
    /*  24 can   25 em    26 sub   27 esc   28 fs    29 gs    30 rs    31 us  */
    0,       0,       0,       0,       0,       0,       0,       0,
    /*  32 sp    33  !    34  "    35  #    36  $    37  %    38  &    39  '  */
    0,      '!',      0,      '#',     '$',     '%',     '&',    '\'',
    /*  40  (    41  )    42  *    43  +    44  ,    45  -    46  .    47  /  */
    0,       0,      '*',     '+',      0,      '-',     '.',      0,
    /*  48  0    49  1    50  2    51  3    52  4    53  5    54  6    55  7  */
    '0',     '1',     '2',     '3',     '4',     '5',     '6',     '7',
    /*  56  8    57  9    58  :    59  ;    60  <    61  =    62  >    63  ?  */
    '8',     '9',      0,       0,       0,       0,       0,       0,
    /*  64  @    65  A    66  B    67  C    68  D    69  E    70  F    71  G  */
    0,      'a',     'b',     'c',     'd',     'e',     'f',     'g',
    /*  72  H    73  I    74  J    75  K    76  L    77  M    78  N    79  O  */
    'h',     'i',     'j',     'k',     'l',     'm',     'n',     'o',
    /*  80  P    81  Q    82  R    83  S    84  T    85  U    86  V    87  W  */
    'p',     'q',     'r',     's',     't',     'u',     'v',     'w',
    /*  88  X    89  Y    90  Z    91  [    92  \    93  ]    94  ^    95  _  */
    'x',     'y',     'z',      0,       0,       0,      '^',     '_',
    /*  96  `    97  a    98  b    99  c   100  d   101  e   102  f   103  g  */
    '`',     'a',     'b',     'c',     'd',     'e',     'f',     'g',
    /* 104  h   105  i   106  j   107  k   108  l   109  m   110  n   111  o  */
    'h',     'i',     'j',     'k',     'l',     'm',     'n',     'o',
    /* 112  p   113  q   114  r   115  s   116  t   117  u   118  v   119  w  */
    'p',     'q',     'r',     's',     't',     'u',     'v',     'w',
    /* 120  x   121  y   122  z   123  {   124  |   125  }   126  ~   127 del */
    'x',     'y',     'z',      0,      '|',      0,      '~',       0 };

const char normal_url_char[32] = {
    /*   0 nul    1 soh    2 stx    3 etx    4 eot    5 enq    6 ack    7 bel  */
    0    |   0    |   0    |   0    |   0    |   0    |   0    |   0,
    /*   8 bs     9 ht    10 nl    11 vt    12 np    13 cr    14 so    15 si   */
    0    | @t(2)  |   0    |   0    | @t(16) |   0    |   0    |   0,
    /*  16 dle   17 dc1   18 dc2   19 dc3   20 dc4   21 nak   22 syn   23 etb */
    0    |   0    |   0    |   0    |   0    |   0    |   0    |   0,
    /*  24 can   25 em    26 sub   27 esc   28 fs    29 gs    30 rs    31 us  */
    0    |   0    |   0    |   0    |   0    |   0    |   0    |   0,
    /*  32 sp    33  !    34  "    35  #    36  $    37  %    38  &    39  '  */
    0    |   2    |   4    |   0    |   16   |   32   |   64   |  128,
    /*  40  (    41  )    42  *    43  +    44  ,    45  -    46  .    47  /  */
    1    |   2    |   4    |   8    |   16   |   32   |   64   |  128,
    /*  48  0    49  1    50  2    51  3    52  4    53  5    54  6    55  7  */
    1    |   2    |   4    |   8    |   16   |   32   |   64   |  128,
    /*  56  8    57  9    58  :    59  ;    60  <    61  =    62  >    63  ?  */
    1    |   2    |   4    |   8    |   16   |   32   |   64   |   0,
    /*  64  @    65  A    66  B    67  C    68  D    69  E    70  F    71  G  */
    1    |   2    |   4    |   8    |   16   |   32   |   64   |  128,
    /*  72  H    73  I    74  J    75  K    76  L    77  M    78  N    79  O  */
    1    |   2    |   4    |   8    |   16   |   32   |   64   |  128,
    /*  80  P    81  Q    82  R    83  S    84  T    85  U    86  V    87  W  */
    1    |   2    |   4    |   8    |   16   |   32   |   64   |  128,
    /*  88  X    89  Y    90  Z    91  [    92  \    93  ]    94  ^    95  _  */
    1    |   2    |   4    |   8    |   16   |   0    |   64   |  128,
    /*  96  `    97  a    98  b    99  c   100  d   101  e   102  f   103  g  */
    1    |   2    |   4    |   8    |   16   |   32   |   64   |  128,
    /* 104  h   105  i   106  j   107  k   108  l   109  m   110  n   111  o  */
    1    |   2    |   4    |   8    |   16   |   32   |   64   |  128,
    /* 112  p   113  q   114  r   115  s   116  t   117  u   118  v   119  w  */
    1    |   2    |   4    |   8    |   16   |   32   |   64   |  128,
    /* 120  x   121  y   122  z   123  {   124  |   125  }   126  ~   127 del */
    1    |   2    |   4    |   8    |   16   |   32   |   64   |   0,
    };

enum HeaderStates
{ H_GENERAL
    , H_C
    , H_CO
    , H_CON
    
    , H_MATCHING_CONNECTION
    , H_MATCHING_PROXY_CONNECTION
    , H_MATCHING_CONTENT_LENGTH
    , H_MATCHING_TRANSFER_ENCODING
    , H_MATCHING_UPGRADE
    
    , H_CONNECTION
    , H_CONTENT_LENGTH
    , H_TRANSFER_ENCODING
    , H_UPGRADE
    
    , H_MATCHING_TRANSFER_ENCODING_CHUNKED
    , H_MATCHING_CONNECTION_TOKEN_START
    , H_MATCHING_CONNECTION_KEEP_ALIVE
    , H_MATCHING_CONNECTION_CLOSE
    , H_MATCHING_CONNECTION_UPGRADE
    , H_MATCHING_CONNECTION_TOKEN
    
    , H_TRANSFER_ENCODING_CHUNKED
    , H_CONNECTION_KEEP_ALIVE
    , H_CONNECTION_CLOSE
    , H_CONNECTION_UPGRADE
};

enum HttpHostState {
      S_HTTP_HOST_ZERO
    , S_HTTP_HOST_DEAD
    , S_HTTP_USERINFO_START
    , S_HTTP_USERINFO
    , S_HTTP_HOST_START
    , S_HTTP_HOST_V6_START
    , S_HTTP_HOST
    , S_HTTP_HOST_V6
    , S_HTTP_HOST_V6_END
    , S_HTTP_HOST_PORT_START
    , S_HTTP_HOST_PORT
};

macro char @token(#c) @if(HTTP_PARSER_STRICT) {
    return tokens[#c];
}

macro char @token(#c) @if(!HTTP_PARSER_STRICT) {
    return #c == ' ' ? ' ' : tokens[#c];
}

macro uint @bit_at(#a, #i) {
    return (!!((uint)(#a)[(uint)(#i) >> 3] & 
                (1 << ((uint)(#i) & 7))));
}

macro bool @is_url_char(#c) {
    return @bit_at(normal_url_char, (char)#c);
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

macro ParserState @parse_url_char(#s, #ch) {
    if (#ch == ' ' || #ch == '\r' || #ch == '\n') {
        return S_DEAD;
    }

$if HTTP_PARSER_STRICT
    if (#ch == '\t' || #ch == '\f') {
        return S_DEAD;
    }
$endif

    switch (#s) {
        case s_req_spaces_before_url:
            if (#ch == '/' || #ch == '*') {
                return S_REQ_PATH;
            }
            if (@is_alpha(#ch)) {
                return S_REQ_SCHEMA;
            }
            break;

        case s_req_schema:
            if (@is_alpha(#ch)) {
                return #s;
            }
            if (#ch == ':') {
                return S_REQ_SCHEMA_SLASH;
            }
            break;

        case S_REQ_SCHEMA_SLASH:
            if (#ch == '/') {
                return S_REQ_SCHEMA_SLASH_SLASH;
            }
            break;

        case S_REQ_SCHEMA_SLASH_SLASH:
            if (#ch == '/') {
                return S_REQ_SERVER_START;
            }
            break;

        case S_REQ_SERVER_WITH_AT:
            if (#ch == '@') {
                return S_DEAD;
            }
            /* FALLTHROUGH */
        case S_REQ_SERVER_START:
        case S_REQ_SERVER:
            if (#ch == '/') {
                return S_REQ_PATH;
            }
            if (#ch == '?') {
                return S_REQ_QUERY_STRING_START;
            }
            if (#ch == '@') {
                return S_REQ_SERVER_WITH_AT;
            }
            if (IS_USERINFO_CHAR(#ch) || #ch == '[' || #ch == ']') {
                return S_REQ_SERVER;
            }
            break;

        case s_req_path:
            if (@is_url_char(#ch)) {
                return #s;
            }
            switch (#ch) {
                case '?':
                    return S_REQ_QUERY_STRING_START;
                case '#':
                    return S_REQ_FRAGMENT_START;
            }
            break;

        case S_REQ_QUERY_STRING_START:
        case S_REQ_QUERY_STRING:
            if (@is_url_char(#ch)) {
                return S_REQ_QUERY_STRING;
            }
            switch (#ch) {
                case '?':
                    return S_REQ_QUERY_STRING; // allow extra '?' in query string
                case '#':
                    return S_REQ_FRAGMENT_START;
            }
            break;

        case S_REQ_FRAGMENT_START:
            if (@is_url_char(#ch)) {
                return S_REQ_FRAGMENT;
            }
            switch (#ch) {
                case '?':
                    return S_REQ_FRAGMENT;
                case '#':
                    return #s;
            }
            break;

        case S_REQ_FRAGMENT:
            if (@is_url_char(#ch)) {
                return #s;
            }
            switch (#ch) {
                case '?':
                case '#':
                    return #s;
            }
            break;

        default:
            break;
    }

    return S_DEAD; // We should never fall out of the switch above unless there's an error
}

const CONNECTION = "connection";
const PROXY_CONNECTION = "proxy-connection";
const CONTENT_LENGTH = "content-length";
const TRANSFER_ENCODING = "transfer-encoding";
const UPGRADE = "upgrade";

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
                case S_RES_HTTP:
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
                case S_REQ_SCHEMA:
                case S_REQ_SCHEMA_SLASH:
                case S_REQ_SCHEMA_SLASH_SLASH:
                case S_REQ_SERVER_START:
                    switch (ch) {
                        case ' ':
                        case '\r':
                        case '\n':
                            self.http_errno = HttpErrno.INVALID_URL;
                            break ERROR;
                        default:
                            p_state = @parse_url_char(p_state, ch);
                            if (@unlikely(p_state == S_DEAD)) {
                                self.http_errno = HttpErrno.INVALID_URL;
                                break ERROR;
                            }
                    }
                    break;
                case S_REQ_SERVER:
                case S_REQ_SERVER_WITH_AT:
                case S_REQ_PATH:
                case S_REQ_QUERY_STRING_START:
                case S_REQ_QUERY_STRING:
                case S_REQ_FRAGMENT_START:
                case S_REQ_FRAGMENT:
                    switch (ch) {
                        case ' ':
                            p_state = S_REQ_HTTP_START;
                            @callback_data(self, settings, p_state, p, data, on_url);
                            break;
                        case '\r':
                        case '\n':
                            self.http_major = 0;
                            self.http_minor = 0;
                            p_state = ch == '\r' ? S_REQ_LINE_ALMOST_DONE : S_HEADER_FIELD_START;
                            @callback_data(self, settings, p_state, p, data, on_url);
                            break;
                        default:
                            p_state = @parse_url_char(p_state, ch);
                            if (@unlikely(p_state == S_DEAD)) {
                                self.http_errno = HttpErrno.INVALID_URL;
                                break ERROR;
                            }
                    }
                    break;
                case S_REQ_HTTP_START:
                    switch (ch) {
                        case 'H':
                            p_state = S_REQ_HTTP_H;
                            break;
                        case ' ':
                            break;
                        default:
                            self.http_errno = HttpErrno.INVALID_CONSTANT;
                            goto ERROR;
                    }
                    break;
                                case S_RES_H:
                    if (ch != 'T') {
                        self.http_errno = HttpErrno.STRICT;
                        break ERROR;
                    }
                    p_state = S_RES_HT;
                    break;
                case S_REQ_HT:
                    if (ch != 'T') {
                        self.http_errno = HttpErrno.STRICT;
                        break ERROR;
                    }
                    p_state = S_REQ_HTT;
                    break;
                case S_REQ_HTT:
                    if (ch != 'P') {
                        self.http_errno = HttpErrno.STRICT;
                        break ERROR;
                    }
                    p_state = S_REQ_HTTP;
                    break;
                case S_REQ_HTTP:
                    if (ch != '/') {
                        self.http_errno = HttpErrno.STRICT;
                        break ERROR;
                    }
                    p_state = S_REQ_FIRST_HTTP_MAJOR;
                    break;
                case S_REQ_FIRST_HTTP_MAJOR:
                    if (@unlikely(ch < '0' || ch > '9')) {
                        self.http_errno = HttpErrno.INVALID_VERSION;
                        break ERROR;
                    }
                    parser.http_major = ch - '0';
                    p_state = S_REQ_HTTP_MAJOR;
                    break;
                case S_REQ_HTTP_MAJOR:
                    if (ch == '.') {
                        p_state = S_REQ_FIRST_HTTP_MINOR;
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
                case S_REQ_FIRST_HTTP_MINOR:
                    if (@unlikely(ch < '0' || ch > '9')) {
                        self.http_errno = HttpErrno.INVALID_VERSION;
                        break ERROR;
                    }
                    self.http_minor = ch - '0';
                    p_state = S_REQ_HTTP_MINOR;
                    break;
                case S_REQ_HTTP_MINOR:
                    switch (ch) {
                        case '\r':
                            p_state = S_REQ_LINE_ALMOST_DONE;
                        case '\n':
                            p_state = S_HEADER_FIELD_START;
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
                case S_REQ_LINE_ALMOST_DONE:
                    if (@unlikely(ch == '\r')) {
                        p_state = S_HEADERS_ALMOST_DONE;
                        break;
                    }
                    p_state = S_HEADER_FIELD_START;
                    
                    break;
                case S_HEADER_FIELD_START:
                    if (ch == '\r') {
                        p_state = S_HEADERS_ALMOST_DONE;
                        break;
                    }
                    if (ch == '\n') {
                        p_state = S_HEADERS_ALMOST_DONE;
                        --p;
                        break;
                    }

                    c = @token(ch);

                    if (@unlikely(!c)) {
                        self.http_errno = HttpErrno.INVALID_HEADER_TOKEN;
                        break ERROR;
                    }

                    header_field_mark = p;
                    self.index = 0;
                    p_state = S_HEADER_FIELD;

                    switch (c) {
                        case 'c':
                            self.header_state = H_C;
                            break;
                        case 'p':
                            self.header_state = H_MATCHING_PROXY_CONNECTION;
                            break;
                        case 't':
                            self.header_state = H_MATCHING_TRANSFER_ENCODING;
                            break;
                        case 'u':
                            self.header_state = H_MATCHING_UPGRADE;
                        default:
                            self.header_state = H_GENERAL;
                    }
                    break;
                case S_HEADER_FIELD:
                    char* start = p;
                    for (; p != ((char*) data) + len; p++) {
                        ch = *p;
                        c = @token(ch);
                        if (!c) break;

                        switch (self.header_state) {
                            case H_GENERAL: break;
                            case H_C:
                                self.index++;
                                self.header_state = (c == 'o' ? H_CO : H_GENERAL);
                                break;
                            case H_CO:
                                self.index++;
                                self.header_state = (c == 'n' ? H_CON : H_GENERAL);
                                break;
                            case H_CON:
                                self.index++;
                                switch (c) {
                                    case 'n':
                                        self.header_state = H_MATCHING_CONNECTION;
                                        break;
                                    case 't':
                                        self.header_state = H_MATCHING_CONTENT_LENGTH;
                                        break;
                                    default:
                                        self.header_state = H_GENERAL;
                                        break;
                                }
                                break;
                            case H_MATCHING_CONNECTION:
                                self.index++;
                                if (self.index > CONNECTION.sizeof-1 || c != CONNECTION[self.index]) {
                                    self.header_state = H_GENERAL;
                                } else if (self.index == CONNECTION.sizeof-2) {
                                    self.header_state = H_CONNECTION;
                                }
                                break;
                            case H_MATCHING_PROXY_CONNECTION:
                                self.index++;
                                if (self.index > PROXY_CONNECTION.sizeof-1 || c != PROXY_CONNECTION[self.index]) {
                                    self.header_state = H_GENERAL;
                                } else if (self.index == PROXY_CONNECTION.sizeof-2) {
                                    self.header_state = H_CONNECTION;
                                }
                                break;
                            case H_MATCHING_CONTENT_LENGTH:
                                self.index++;
                                if (self.index > CONTENT_LENGTH.sizeof-1 || c != CONTENT_LENGTH[self.index]) {
                                    self.header_state = H_GENERAL;
                                } else if (self.index == CONTENT_LENGTH.sizeof-2) {
                                    self.header_state = H_CONTENT_LENGTH;
                                }
                                break;
                            case H_MATCHING_TRANSFER_ENCODING:
                                self.index++;
                                if (self.index > TRANSFER_ENCODING.sizeof-1 || c != TRANSFER_ENCODING[self.index]) {
                                    self.header_state = H_GENERAL;
                                } else if (self.index == TRANSFER_ENCODING.sizeof-2) {
                                    self.header_state = H_TRANSFER_ENCODING;
                                }
                                break;
                            case H_MATCHING_UPGRADE:
                                self.index++;
                                if (self.index > UPGRADE.sizeof-1 || c != UPGRADE[self.index]) {
                                    self.header_state = H_GENERAL;
                                } else if (self.index == UPGRADE.sizeof-2) {
                                    self.header_state = H_UPGRADE;
                                }
                                break;
                            case H_CONNECTION:
                            case H_CONTENT_LENGTH:
                            case H_TRANSFER_ENCODING:
                            case H_UPGRADE:
                                if (ch != ' ') {
                                    self.header_state = H_GENERAL;
                                }
                                break;
                            
                            default:
                                assert(0 && "Unknown Header State");
                                break;
                        }
                    }

                    if (@count_header_size(self, p-start)) break ERROR;
                    if (p == data + len) {
                        --p;
                        break;
                    }
                    if (ch == ':') {
                        p_state = S_HEADER_VALUE_DISCARD_WS;
                        @callback_data(self, settings, p_state, p, data, on_header_field);
                        break;
                    }

                    self.http_errno = HttpErrno.INVALID_HEADER_TOKEN;
                    break ERROR;
            }
        }
    } while(0);
}