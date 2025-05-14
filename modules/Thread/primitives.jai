Thread_Index :: s64;
Thread_Proc  :: #type (*Thread) -> s64;

Thread :: struct {
    index : Thread_Index;
    proc  : Thread_Proc;
    data  : *void;
    workspace : Workspace;  // This will be 0 if running a final program, nonzero inside the compiler.

    starting_context: #Context;
    starting_temporary_storage: Temporary_Storage;

    allocator_used_for_temporary_storage: Allocator;

    #if LOAD_THREAD_GROUP worker_info: *Thread_Group.Worker_Info;   // Used by Thread_Group; unused otherwise.

    #if _STACK_TRACE  stack_trace_sentinel: Stack_Trace_Node;  // Set the pointer to the address of this for new contexts.

    using specific : Thread_Os_Specific;
}

POSIX_THREADS :: (OS == .LINUX || OS == .MACOS || OS == .IOS || OS == .ANDROID);

#if OS == .WINDOWS || OS == .PS5 || POSIX_THREADS {


thread_init :: (thread: *Thread, proc: Thread_Proc, temporary_storage_size : s32 = 16384, starting_storage: *Temporary_Storage = null) -> bool {

    // It should be documented that starting_storage gets value-copied into the
    // Temporary_Storage used by the thread. So don't expect its fields to change;
    // you can look at thread.starting_storage to see what happened.

    thread.workspace = get_current_workspace();

    #if OS == .WINDOWS {
        entry_proc :: (parameter: *void) -> s32 #c_call {
            thread := cast(*Thread) parameter;

            new_context := thread.starting_context;
            new_context.thread_index = xx thread.index;  // @Cleanup: Context has a 32-bit thread index, but ours is 64.

            #if _STACK_TRACE  new_context.stack_trace = *thread.stack_trace_sentinel;

            result: s32;
            push_context new_context {
                a := new_context.allocator;

                #if Race_Detector Race_Detector.thread_started();
                a.proc(.THREAD_START, 0, 0, null, a.data);

                result = cast(s32) thread.proc(thread);  // @Cleanup: We can only return s32, but our thread proc returns s64, hmm.

                // If you crash in this call, it may be because you're deinitializing the Thread object before it has run to completion.
                // It is not enough for the thread.proc to have completed, the Thread's allocator and temporary storage must remain
                // valid until the thread is complete as indicated, for example, by the thread_is_done function.
                a.proc(.THREAD_STOP, 0, 0, null, a.data);

                #if Race_Detector Race_Detector.thread_stopped();
            }

            return result;
        }

        windows_thread_id : s32;

        // Because we are using the CRT, we need to call _beginthreadex.
        // Which is dumb, but it is what it is.
        // Once we remove dependency on the CRT we can stop doing this.
        //    -jblow, 10 February 2017

        // windows_thread := CreateThread(null, 0, xx entry_proc, thread, CREATE_SUSPENDED, *windows_thread_id);
        windows_thread := cast(HANDLE)_beginthreadex(null, 0, xx entry_proc, thread, CREATE_SUSPENDED, *windows_thread_id);

        if !windows_thread {
            // print("Thread create failed!!\n");
            return false;
        }

        thread.windows_thread_id = windows_thread_id;
        thread.windows_thread    = windows_thread;
    } else #if POSIX_THREADS {
        entry_proc :: (parameter: *void) -> *void #c_call {
            thread := cast(*Thread) parameter;
            wait_for(*thread.suspended_semaphore);

            new_context := thread.starting_context;
            new_context.thread_index = xx thread.index;  // @Cleanup: Context has a 32-bit thread index, but ours is 64.

            #if _STACK_TRACE  new_context.stack_trace = *thread.stack_trace_sentinel;

            result: s32;
            push_context new_context {
                result = cast(s32) thread.proc(thread);  // @Cleanup: We can only return s32, but our thread proc returns s64, hmm.

                thread.is_done = true;
                signal(*thread.is_alive_semaphore);
                return cast(*void) result;
            }
        }

        init(*thread.suspended_semaphore);
        init(*thread.is_alive_semaphore);

        ok := pthread_create(*thread.thread_handle, null, entry_proc, thread);

        if ok != 0 {
            // print("Failed to create thread!\n");
            destroy(*thread.suspended_semaphore);
            destroy(*thread.is_alive_semaphore);
            return false;
        }
    } else #if OS == .PS5 {
        if !ps5_createthread(thread) {
            return false;
        }
    }

    thread.proc = proc;

    thread.starting_context.allocator   = context.allocator;
    thread.starting_context.logger      = context.logger;
    thread.starting_context.logger_data = context.logger_data;

    storage := *thread.starting_temporary_storage;
    thread.starting_context.temporary_storage = storage;
    if starting_storage {
        storage.* = starting_storage.*;
    } else {
        set_initial_data(storage, temporary_storage_size, Basic.alloc(temporary_storage_size));
        storage.current_page_bytes_occupied = 0;
        storage.total_bytes_occupied = 0;
        storage.high_water_mark = 0;

        thread.allocator_used_for_temporary_storage = context.allocator;
    }

    thread.index = atomic_add(*next_thread_index, 1);
    return true;
}

thread_deinit :: (thread: *Thread) {
    #if OS == .WINDOWS {
        if thread.windows_thread CloseHandle(thread.windows_thread);
        thread.windows_thread = null;
    } else #if POSIX_THREADS {
        if thread.thread_handle {
            pthread_join(thread.thread_handle, null);
        }
        #if OS == .LINUX || OS == .ANDROID {
            thread.thread_handle = 0;
        } else {
            thread.thread_handle = null;
        }

        destroy(*thread.suspended_semaphore);
        destroy(*thread.is_alive_semaphore);
    } else #if OS == .PS5 {
        ps5_closethread(thread);
    }

    assert(thread.index > 0);
    table_index := thread.index - 1;

    ts := *thread.starting_temporary_storage;
    if thread.allocator_used_for_temporary_storage.proc {
        Basic.free(ts.original_data,, thread.allocator_used_for_temporary_storage);
    }

    overflow := ts.overflow_pages;
    while overflow {
        next := overflow.next;
        Basic.free(overflow,, overflow.allocator);
        overflow = next;
    }

    thread.index = 0;
}

} // OS_WINDOWS || OS_LINUX || OS_MACOS || OS_PS5

#if OS == .WINDOWS {
    Per_OS_Critical_Section_Type :: CRITICAL_SECTION;
    Per_OS_Condition_Variable_Type :: CONDITION_VARIABLE;
} else #if POSIX_THREADS {
    Per_OS_Critical_Section_Type :: pthread_mutex_t;
    Per_OS_Condition_Variable_Type :: pthread_cond_t;
}

Mutex :: struct {
    csection: Per_OS_Critical_Section_Type;

    #if DEBUG {
        initialized := false;

        name:        string;
        order:       Mutex_Order;

        redundant_lock_counter: s32;  // Used if we lock the same mutex more than once in a row.

        // Copied from context.mutex_tracking so we can restore them on unlock:
        outer_name:     string;
        outer_order:    Mutex_Order;
        outer_csection: *Per_OS_Critical_Section_Type;
    }
}


Wait_For_Result :: enum {
    SUCCESS;
    TIMEOUT;
    ERROR;
}

Condition_Variable :: struct {
    condition_variable : Per_OS_Condition_Variable_Type;

    #if DEBUG {
        initialized := false;

        name:           string;
        current_mutex:  *Mutex;

    }
};


#if POSIX_THREADS {
    #import "POSIX";

    Thread_Os_Specific :: struct {
        thread_handle: pthread_t;
        is_alive_semaphore:  Semaphore;
        suspended_semaphore: Semaphore;
        is_done: bool;
    }

    thread_start :: (thread: *Thread) {
        signal(*thread.suspended_semaphore);
    }

    // @ToDo: Replace with a pthread_kill() variant? But how do timeouts fit into this? Shall we sleep & kill in a loop?
    thread_is_done :: (thread: *Thread, milliseconds: s32 = 0) -> bool {  // Pass -1 for milliseconds to wait indefinitely. (This works cross-platform).
        if milliseconds < -1 Basic.log_error("Invalid value % for 'milliseconds' in thread_is_done().\n", milliseconds);

        if thread.is_done return true; // Fast path, to avoid the semaphore wait_for/signal overhead

        // Since pthread doesn't define a way to poke a sibiling thread
        // for its running status, we have to share an event flag set
        // by our entry_proc function.
        result := wait_for(*thread.is_alive_semaphore, milliseconds);  // If milliseconds == -1, wait_for waits indefinitely, so it is pass-through functionality from the input parameter value.
        if result != .SUCCESS return false;

        // @Hack: Make sure that this function can be called again to keep it in sync with the Windows version
        // and the name of this function (which implies that it can be called more than once to check the status).
        // But we should probably redesign this API.
        //  -rluba, 2023-03-13
        signal(*thread.is_alive_semaphore);

        assert(thread.is_done);
        return true;
    }

    destroy :: (using m: *Mutex) {
        #if DEBUG assert(m.initialized);
        pthread_mutex_destroy(*csection);
    }


    init :: (using m: *Mutex, desired_name := "", desired_order: Mutex_Order = -1) {
        attr: pthread_mutexattr_t;
        pthread_mutexattr_init(*attr);
        #if OS == .MACOS || OS == .IOS {
            pthread_mutexattr_settype(*attr, PTHREAD_MUTEX_RECURSIVE);
        } else {
            pthread_mutexattr_settype(*attr, xx PTHREAD_MUTEX.RECURSIVE_NP);
        }

        ret := pthread_mutex_init(*csection, *attr);
        assert(ret == 0);

        #if DEBUG {
            assert(desired_order >= -1);

            name  = desired_name;
            order = desired_order;
            initialized = true;
        }
    }

    init :: (using cv : *Condition_Variable, desired_name := "") {
        pthread_cond_init(*cv.condition_variable, null);
        #if DEBUG {
            name = desired_name;
            initialized = true;
        }
    }

    destroy :: (using cv : *Condition_Variable) {
        pthread_cond_destroy(*cv.condition_variable);
        #if DEBUG {
            assert(initialized);
            initialized = false;
        }
    }

    #if OS == .MACOS {
        // There’s no sem_timedwait in pthread on macOS, so we have to fall back to a lower-level implementation using semaphore_*.

        #import "macos";

        Semaphore :: struct {
            owner: task_t;
            event: semaphore_t = 0;
        }

        init :: (s: *Semaphore, initial_value: s32 = 0) {
            assert(initial_value >= 0);

            s.owner = mach_task_self();
            s.event = 0;
            result := semaphore_create(s.owner, *s.event, SYNC_POLICY_FIFO, initial_value);
            assert(result == KERN.SUCCESS);
        }

        destroy :: (s: *Semaphore) {
            if (s.event) {
                semaphore_destroy(s.owner, s.event);
            }
            s.event = 0;
        }

        signal :: (s: *Semaphore) {
            semaphore_signal(s.event);
        }

        wait_for :: (s: *Semaphore, milliseconds: s32 = -1) -> Wait_For_Result #no_context {
            result: kern_return_t = ---;
            if milliseconds < 0 {
                result = KERN.ABORTED;
                while result == KERN.ABORTED {
                    result = semaphore_wait(s.event);
                }
            } else {
                seconds := milliseconds / 1000;
                milliseconds -= seconds * 1000;
                timeout: mach_timespec_t;
                timeout.tv_sec  = cast (u32) seconds;
                timeout.tv_nsec = milliseconds * 1_000_000;
                result = semaphore_timedwait(s.event, timeout);
            }
            if result == {
                case KERN.SUCCESS;
                    return .SUCCESS;
                case KERN.OPERATION_TIMED_OUT;
                    // assert(milliseconds >= 0);
                    return .TIMEOUT;
                case;
                    push_context {
                        Basic.log_error("wait_for error: %\n", result);
                    }
                    return .ERROR;
            }
        }
    } else {
        Semaphore :: struct {
            semaphore: sem_t;
        }

        init :: (s: *Semaphore, initial_value: s32 = 0) {
            assert(initial_value >= 0);
            result := sem_init(*s.semaphore, 0, cast(u32) initial_value);
            assert(result == 0);
        }

        destroy :: (s: *Semaphore) {
            sem_destroy(*s.semaphore);
        }

        signal :: (s: *Semaphore) {
            sem_post(*s.semaphore);
        }

        wait_for :: (s: *Semaphore, milliseconds: s32 = -1) -> Wait_For_Result #no_context {
            result: s32 = ---;
            if milliseconds < 0 {
                result = sem_wait(*s.semaphore);
                while result == -1 && errno() == EINTR {
                    result = sem_wait(*s.semaphore);
                }
            } else {
                current_time : timespec;
                if clock_gettime(.REALTIME, *current_time) == -1 return .ERROR;

                nsec_new := cast(s64)current_time.tv_nsec + 1_000_000 * cast(s64)milliseconds;
                sec_new  := current_time.tv_sec + nsec_new / 1_000_000_000;
                nsec_new %= 1_000_000_000;

                end_time := timespec.{
                    tv_sec  = sec_new,
                    tv_nsec = nsec_new
                };

                // sem_timedwait takes an _absolute_ time as timeout for whatever reason.
                // So we need to get the current time and add our timeout duration to it.
                result = sem_timedwait(*s.semaphore, *end_time);
            }

            if result == -1 {
                if errno() == {
                    case ETIMEDOUT;
                        // assert(milliseconds >= 0);
                        return .TIMEOUT;
                    case;
                        return .ERROR;
                }
            }

            return .SUCCESS;
        }
    }
}

#if OS == .WINDOWS {
    #scope_file
    #import "Windows";
    #scope_export

    Thread_Os_Specific :: struct {
        windows_thread:    HANDLE;
        windows_thread_id: s32;
    }

    thread_start :: (thread: *Thread) {
        ResumeThread(thread.windows_thread);
    }

    thread_is_done :: (thread: *Thread, milliseconds: s32 = 0) -> bool { // Pass -1 for milliseconds to wait indefinitely. (This works cross-platform).
        if milliseconds < -1 Basic.log_error("Invalid value % for 'milliseconds' in thread_is_done().\n", milliseconds);

        // @Cleanup: Waiting in milliseconds as our API is lame.
        result := WaitForSingleObject(thread.windows_thread, cast,no_check(DWORD) milliseconds);  // We rely on -1 casting to 0xffff_ffff.
        return result != WAIT_TIMEOUT;
    }

    destroy :: (using m: *Mutex) {
        #if DEBUG assert(m.initialized);
        DeleteCriticalSection(*csection);
    }


    init :: (using m: *Mutex, desired_name := "", desired_order: Mutex_Order = -1) {
        InitializeCriticalSection(*csection);

        #if DEBUG {
            assert(desired_order >= -1);

            name  = desired_name;
            order = desired_order;
            initialized = true;
        }
    }

    Semaphore :: struct {
        event: HANDLE;
    }

    init :: (s: *Semaphore, initial_value: s32 = 0) {
        assert(initial_value >= 0);
        s.event = CreateSemaphoreW(null, initial_value, 0x7fff_ffff, null);
    }

    destroy :: (s: *Semaphore) {
        CloseHandle(s.event);
    }

    signal :: (s: *Semaphore) {
        ReleaseSemaphore(s.event, 1, null);
    }

    wait_for :: (s: *Semaphore, milliseconds : s32 = -1) -> Wait_For_Result {
        res: DWORD;
        if milliseconds < 0 {
            res = WaitForSingleObject(s.event, INFINITE);
        } else {
            res = WaitForSingleObject(s.event, cast(u32) milliseconds);
        }

        assert(res != WAIT_FAILED);

        if res == WAIT_OBJECT_0 return .SUCCESS;
        if res == WAIT_TIMEOUT  return .TIMEOUT;

        return .ERROR;
    }


    init :: (using cv : *Condition_Variable, desired_name := "") {
        InitializeConditionVariable(*condition_variable);
        #if DEBUG {
            name = desired_name;
            initialized = true;
        }
    }

    destroy :: (using cv : *Condition_Variable) {
        #if DEBUG {
            assert(initialized);
            initialized = false;
        }
    }
}

#if OS == .WINDOWS || POSIX_THREADS {

csection_lock :: (csection: *Per_OS_Critical_Section_Type) #expand {
    #if OS == .WINDOWS EnterCriticalSection(csection);
    else pthread_mutex_lock(csection);
}

csection_unlock :: (csection: *Per_OS_Critical_Section_Type) #expand {
    #if OS == .WINDOWS LeaveCriticalSection(csection);
    else pthread_mutex_unlock(csection);
}


cvariable_wait :: (condition_variable : *Per_OS_Condition_Variable_Type, csection : *Per_OS_Critical_Section_Type, wait_time_ms : s32 = -1) {
    #if OS == .WINDOWS {
        SleepConditionVariableCS(condition_variable, csection, cast,no_check(DWORD)wait_time_ms);
    } else {
        if wait_time_ms == -1 {
            pthread_cond_wait(condition_variable, csection);
        } else {
                seconds := wait_time_ms / 1000;
                milliseconds := wait_time_ms - seconds * 1000;

                // pthread_cond_timedwait takes an _absolute_ time as timeout for whatever reason.
                // So we need to get the current time and add our timeout duration to it.
                time: timespec;
                clock_gettime(.REALTIME, *time);
                time.tv_sec  += seconds;
                time.tv_nsec += milliseconds * 1_000_000;
                pthread_cond_timedwait(condition_variable, csection, *time);
        }
    }
}

cvariable_wake :: (condition_variable : *Per_OS_Condition_Variable_Type) {
    #if OS == .WINDOWS WakeConditionVariable(condition_variable);
    else pthread_cond_signal(condition_variable);
}

cvariable_wake_all :: (condition_variable : *Per_OS_Condition_Variable_Type) {
    #if OS == .WINDOWS WakeAllConditionVariable(condition_variable);
    else pthread_cond_broadcast(condition_variable);
}


}

#if DEBUG {
    // We change the arguments of lock and unlock in DEBUG to take #caller_location,
    // otherwise we'd put the #if inside these procedures probably. We're doing this
    // for speed reasons.
    lock :: (using m: *Mutex, loc := #caller_location) {
        //
        // We take the lock before setting any of our checking variables that are stored on Mutex,
        // to avoid race conditions. The irony here is that if a newbie makes a 100% deadlock, they won't
        // see the deadlock assertion below, because it won't have a chance to run, because of the deadlock.
        // But those cases are relatively easy to debug.
        // You will see this assertion in the actual difficult-to-debug case of a spurious deadlock that
        // doesn't usually happen.
        //
        // In the future, we could explore trying to put the lock in between the check and the setting
        // of all the outer_* values, but it's not totally obvious that that is okay at this minute.
        //                       -jblow, 3 May 2021.
        //

        #if Race_Detector Race_Detector.write_lock(*csection);

        csection_lock(*csection);

        if order >= 0 {
            t := *context.mutex_tracking;
            redundant := false;         // This is here to detect when we lock the same Mutex multiple times in succession; we don't want to destroy the outer_* in that case!
            if t.current_order != -1 {  // Check the order!
                okay := true;
                if t.current_order == order {
                    // If we are locking the same mutex twice in a row, that is fine.
                    // Otherwise it's illegal.
                    if t.current_mutex_id == *csection {
                        redundant = true;
                    } else {
                        okay = false;
                    }
                } else if t.current_order < order {
                    okay = false;  // Totally illegal.
                }

                if !okay {
                    Basic.log_error("Attempt to lock mutexes out of order.\n");

                    Basic.log("While we had already locked '%' at order % (%:%)...\n", t.current_name, t.current_order, t.current_order_set_by.fully_pathed_filename, t.current_order_set_by.line_number);
                    Basic.log("We tried to lock '%' at order % (%:%).\n", name, order, loc.fully_pathed_filename, loc.line_number);
                    Basic.log("Lock order must strictly decrease, so this is invalid.\n");

                    assert(false);
                }
            }

            if redundant {
                redundant_lock_counter += 1;
            } else {
                outer_order    = t.current_order;
                outer_name     = t.current_name;
                outer_csection = t.current_mutex_id;

                t.current_order        = order;
                t.current_order_set_by = loc;
                t.current_name         = name;
                t.current_mutex_id     = *csection;
            }
        }
    }

    unlock :: (using m: *Mutex, loc := #caller_location) {
        if order >= 0 {
            t := *context.mutex_tracking;

            // This assertion happens if you unlock things in the wrong order.
            // Maybe we could add a nicer message here.
            if t.current_mutex_id != *csection {
                Basic.log_error("Attempt to unlock mutexes out of order.\n");

                Basic.log("While we were unlocking '%' at order % (%:%)...\n", name, order, loc.fully_pathed_filename, loc.line_number);
                Basic.log("We saw the most-recently locked Mutex was '%' at order % (%:%).\n", t.current_name, t.current_order, t.current_order_set_by.fully_pathed_filename, t.current_order_set_by.line_number);
                Basic.log("It is invalid to unlock mutexes out of order.\n");
                assert(false);
            }

            if redundant_lock_counter > 0 {
                redundant_lock_counter -= 1;
            } else {
                t.current_order        = outer_order;
                t.current_order_set_by = loc;
                t.current_name         = outer_name;
                t.current_mutex_id     = outer_csection;
            }
        }

        csection_unlock(*csection);
        #if Race_Detector Race_Detector.write_unlock(*csection);
    }
} else {
    lock :: (using m: *Mutex) {
        csection_lock(*m.csection);
        #if Race_Detector Race_Detector.write_lock(*csection);
    }

    unlock :: (using m: *Mutex) {
        csection_unlock(*m.csection);
        #if Race_Detector Race_Detector.write_unlock(*csection);
    }
}

#if DEBUG {
    wait :: (c: *Condition_Variable, m: *Mutex, loc := #caller_location) {
        assert(c.initialized);
        assert(m.initialized);
        t := *context.mutex_tracking;
        if t.current_mutex_id != *m.csection {
            Basic.log_error("Attempt to wait on a condition variable with a mutex which was not the last one locked. This is effectively unlocking mutex out of order.\n");
            Basic.log("While we were unlocking mutex '%' with condition variable % (%:%)...\n", m.name, c.name, loc.fully_pathed_filename, loc.line_number);
            assert(false);
        }


        #if Race_Detector Race_Detector.write_unlock(*m.csection);
        cvariable_wait(*c.condition_variable);
        #if Race_Detector Race_Detector.write_lock(*m.csection);
    }


} else {
    wait :: (c: *Condition_Variable, m: *Mutex) {
        #if Race_Detector Race_Detector.write_unlock(*m.csection);
        cvariable_wait(*c.condition_variable, *m.csection);
        #if Race_Detector Race_Detector.write_lock(*m.csection);
    }

}

wake :: (c: *Condition_Variable) {
    #if DEBUG assert(c.initialized);
    cvariable_wake(*c.condition_variable);
}

wake_all :: (c: *Condition_Variable) {
    #if DEBUG assert(c.initialized);
    cvariable_wake(*c.condition_variable);
}

#if OS == .PS5 {
    #load "ps5.jai";
}

