// SPDX-License-Identifier: GPL-2.0-only
// C-side process handle. The finalizer releases OS resources; MoonBit only
// borrows the handle, mirroring transport/ffi.mbt.

///|
type Proc

///|
extern "c" fn proc_new() -> Proc = "bf_proc_new"

///|
#borrow(proc)
extern "c" fn proc_error(proc : Proc) -> Int = "bf_proc_error"

///|
extern "c" fn proc_is_windows() -> Int = "bf_proc_is_windows"

///|
#borrow(proc, command)
extern "c" fn proc_spawn(proc : Proc, command : Bytes, length : Int) -> Int = "bf_proc_spawn"

///|
#borrow(proc)
extern "c" fn proc_poll(proc : Proc) -> Int = "bf_proc_poll"

///|
#borrow(proc)
extern "c" fn proc_exit_code(proc : Proc) -> Int = "bf_proc_exit_code"

///|
#borrow(proc)
extern "c" fn proc_pid(proc : Proc) -> Int = "bf_proc_pid"

///|
#borrow(proc)
extern "c" fn proc_kill(proc : Proc) -> Int = "bf_proc_kill"
