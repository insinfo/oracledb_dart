# cython: language_level=3
"""Test-only helpers that expose internal ``Buffer`` APIs to Python."""

from libc.stdint cimport uint8_t, uint16_t, uint32_t

from oracledb.base_impl cimport Buffer, GrowableBuffer


cdef void _initialize_buffer(Buffer buffer, Py_ssize_t max_size):
    buffer._initialize(max_size)
    buffer._size = 0
    buffer._pos = 0


cdef void _seal_buffer(Buffer buffer):
    if buffer._pos > buffer._size:
        buffer._size = buffer._pos


cdef bytes _snapshot(Buffer buffer):
    cdef Py_ssize_t used = buffer._size
    if buffer._pos > used:
        used = buffer._pos
    return bytes(buffer._data_obj[:used])


cdef class TestableBuffer(Buffer):

    cpdef void initialize(self, Py_ssize_t max_size):
        _initialize_buffer(self, max_size)

    cpdef void finalize_for_read(self):
        _seal_buffer(self)
        self._pos = 0

    cpdef bytes snapshot(self):
        return _snapshot(self)

    cpdef void write_uint8_public(self, uint8_t value):
        self.write_uint8(value)

    cpdef int read_uint8_public(self):
        cdef uint8_t value
        self.read_ub1(&value)
        return value

    cpdef void write_uint16be_public(self, uint16_t value):
        self.write_uint16be(value)

    cpdef object read_str_with_length_public(self):
        return self.read_str_with_length()

    cpdef void write_str_public(self, str value):
        self.write_str(value)

    cpdef void write_bytes_public(self, bytes value):
        self.write_bytes(value)

    cpdef void write_bytes_with_length_public(self, bytes value):
        self.write_bytes_with_length(value)

    cpdef object read_bytes_public(self):
        return self.read_bytes()

    cpdef object read_bytes_with_length_public(self):
        return self.read_bytes_with_length()

    cpdef void write_ub4_public(self, uint32_t value):
        self.write_ub4(value)

    cpdef uint32_t read_ub4_public(self):
        cdef uint32_t value
        self.read_ub4(&value)
        return value

    cpdef void write_oracle_number_public(self, bytes num_bytes):
        self.write_oracle_number(num_bytes)

    cpdef void rewind(self):
        self._pos = 0

    cpdef void seal(self):
        _seal_buffer(self)

    cpdef Py_ssize_t max_size(self):
        return self._max_size


cdef class TestableGrowableBuffer(GrowableBuffer):

    cpdef void initialize(self, Py_ssize_t max_size):
        _initialize_buffer(self, max_size)

    cpdef void finalize_for_read(self):
        _seal_buffer(self)
        self._pos = 0

    cpdef bytes snapshot(self):
        return _snapshot(self)

    cpdef Py_ssize_t max_size(self):
        return self._max_size

    cpdef void write_bytes_public(self, bytes value):
        self.write_bytes(value)
