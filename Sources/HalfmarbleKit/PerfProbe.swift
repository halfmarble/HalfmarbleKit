import Darwin.Mach

//  The mach process samplers behind every halfmarble perf read-out — moved
//  here from StringFusor's PerfHUD (2026-07-25) so both shells of any app
//  compare the SAME numbers.

public enum PerfProbe {
    /// phys_footprint via TASK_VM_INFO — the memory Xcode attributes to the app.
    public static func footprintMB() -> Int {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.stride / MemoryLayout<integer_t>.stride)
        let kr = withUnsafeMutablePointer(to: &info) { ptr in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        guard kr == KERN_SUCCESS else { return 0 }
        return Int(info.phys_footprint) / (1024 * 1024)
    }

    /// Summed non-idle thread CPU usage (can exceed 100% on many cores).
    /// TH_USAGE_SCALE is 1000; TH_FLAGS_IDLE is 0x1 (neither imports as a
    /// Swift symbol, so they are spelled out here).
    public static func cpuPercent() -> Int {
        var list: thread_act_array_t?
        var n = mach_msg_type_number_t(0)
        guard task_threads(mach_task_self_, &list, &n) == KERN_SUCCESS, let threads = list else { return 0 }
        defer {
            // task_threads hands back a SEND RIGHT per thread, not just an array:
            // each one has to be released or the task's IPC namespace grows on
            // every call. Freeing only the array (which is all this used to do)
            // leaks one dead name per distinct thread ever sampled, and the
            // urefs on a still-live thread's name climb forever — this runs
            // 2x/sec for as long as the app renders. Deallocate the rights
            // FIRST, then the memory that held them.
            for i in 0..<Int(n) { mach_port_deallocate(mach_task_self_, threads[i]) }
            vm_deallocate(mach_task_self_, vm_address_t(UInt(bitPattern: threads)),
                          vm_size_t(Int(n) * MemoryLayout<thread_t>.stride))
        }
        var total = 0.0
        for i in 0..<Int(n) {
            var info = thread_basic_info()
            var count = mach_msg_type_number_t(MemoryLayout<thread_basic_info_data_t>.stride / MemoryLayout<integer_t>.stride)
            let kr = withUnsafeMutablePointer(to: &info) { ptr in
                ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                    thread_info(threads[i], thread_flavor_t(THREAD_BASIC_INFO), $0, &count)
                }
            }
            if kr == KERN_SUCCESS, (info.flags & 0x1) == 0 {   // skip idle threads
                total += Double(info.cpu_usage) / 1000.0 * 100.0
            }
        }
        return Int(total.rounded())
    }
}
