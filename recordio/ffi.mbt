///|
type FileHandle

///|
#borrow(bytes)
extern "c" fn print_error_ffi(bytes : Bytes, length : Int) -> Unit = "bf_print_error"

///|
#borrow(path)
extern "c" fn open_file(path : Bytes, write : Int) -> FileHandle = "bf_file_open"

///|
#borrow(file)
extern "c" fn close_file(file : FileHandle) -> Unit = "bf_file_close"

///|
#borrow(file)
extern "c" fn file_error(file : FileHandle) -> Int = "bf_file_error"

///|
#borrow(file, bytes)
extern "c" fn write_file(file : FileHandle, bytes : Bytes, length : Int) -> Int = "bf_file_write"

///|
#borrow(file)
extern "c" fn read_file(file : FileHandle, maximum : Int) -> Bytes = "bf_file_read"

///|
#borrow(path)
extern "c" fn make_directory(path : Bytes) -> Int = "bf_file_mkdir"

///|
#borrow(path)
extern "c" fn create_file(path : Bytes) -> FileHandle = "bf_file_create"
