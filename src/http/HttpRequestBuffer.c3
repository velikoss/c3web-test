module c3web;

const DEFAULT_BUFFER_SHRINKSIZE = 65536;
import libc;
import std::core::mem;
import libc::errno;
import std::collections::map;

struct RequestBufferChunk {
    void* buffer;
    usz size;
}

def RequestBuffer = void*;

struct HttpRequestBuffer {
    usz max_size;
    usz size;
    usz _mark;
    usz used;
    usz used_before;
    void* current;
    HashMap(<void*, usz>) offsets;
    bool offsets_active;
}

def RBCh = RequestBufferChunk;
def HRBr = HttpRequestBuffer;

fn void HRBr.consume(HRBr* self, usz consumed) {
    self.used_before = self.used;
    self.used += consumed;
}

fn void HRBr.mark(HRBr* self) {
    self._mark = self.used_before;
}

fn void! HRBr.sweep(HRBr* self) {
    usz used = self.used - self._mark;

    if (self._mark == 0) return;
    bool offsets_active = false;
    if (self.used > 0) {
        libc::memcpy(self.current, self.current + self._mark, used);
    }

    if (self.size > DEFAULT_BUFFER_SHRINKSIZE && self.used < DEFAULT_BUFFER_SHRINKSIZE) {
        self.size = DEFAULT_BUFFER_SHRINKSIZE;
        self.current = mem::realloc(self.current, self.size);
        if (!self.current) {
            libc::errno_set(errno::ENOMEM);
            self.size = 0;
        }
    }

    if (self.used) {
        self.offsets.@each(; void* pointer, usz offset) {
            if (offset <= self._mark) {
                self.offsets.remove(pointer);
            } else {
                offsets_active = true;
                self.offsets[pointer] = offset - self._mark;
            }
        };
    } else {
        self.offsets.clear();
    }

    self._mark = 0;
    self.used = used;
    self.offsets_active = offsets_active;
}

fn HRBr* http_request_buffer_init(usz max_size) {
    HRBr* buffer = mem::new(HRBr);
    buffer.max_size = max_size;
    buffer.offsets.new_init();
    return buffer;
}

fn void HRBr.chunk(HRBr* self, RBCh* chunk) {
    chunk.size = self.size ? (self.size - self.used) : 0;
    chunk.buffer = self.current + self.used; 
}

fn bool HRBr.alloc(HRBr* self, usz requested_size) {
    bool ret = true;
    void* previous = null;

    usz requested_size_capped = min(self.max_size, requested_size);

    if (!self.current) {
        self.current = mem::malloc(requested_size_capped);
        if (!self.current) {
            self.size = 0;
            libc::errno_set(errno::ENOMEM);
            ret = false;
        } else {
            self.size = requested_size_capped;
        }
    } else if (self.used * 2 < self.size) {
        /* ignoring allocation size unless we're above 50% usage */ // wtf
    } else if (self.size + requested_size_capped <= self.max_size) {
        /* time to reallocate memory and re-point anything using the buffer */
        previous = self.current;

        self.current = mem::realloc(self.current, self.size + requested_size_capped);
        self.size += requested_size_capped;

        if (!self.current) {
            self.size = 0;
            libc::errno_set(errno::ENOMEM);
            ret = false;
        } else if (self.current != previous) {
            self.offsets_active = true;
        }
    } else {
        self.size = 0;
        libc::errno_set(errno::ERANGE);
        ret = false;
    }

    return ret;
}

fn void HRBr.pin(HRBr* self, void* key, void* pointer) {
    usz*! offset_key = self.offsets.get_ref(key);
    usz offset = pointer - self.current;
    usz ret;
    if (catch offset_key) {
        self.offsets[key] = (ulong) null;
        offset_key = self.offsets.get_ref(key);
    }
    offset_key = &&offset;
}

fn void HRBr.reasign_pin(HRBr* self, void* old_key, void* new_key) {
    usz*! old_offset_key = self.offsets.get_ref(old_key);
    
    usz offset;
    usz ret;

    if (try old_offset_key) {
        offset = self.offsets[old_offset_key]!!;
        self.offsets[new_key] = offset;
        self.offsets.remove(old_key);
    }
}

fn void* HRBr.locate(HRBr* self, void* key, void* default_pointer = null) {
    void* location = default_pointer;
    usz*! offset_key = self.offsets.get_ref(key);
 
    usz offset;
    if (self.offsets_active) {
        if (try offset_key) {
            offset = *offset_key;
            location = self.current + offset;
        }
    }

    return location;
}

fn void HRBr.destroy(HRBr* self) {
    self.offsets.free();
    mem::free(self.current);
    mem::free(self);
}