import Foundation

/// `agentpet focus-host` — the native-messaging host for the Focus Block browser
/// extension. Chrome launches it (via the wrapper script the app installs) each
/// time the extension opens a `connectNative` port. It streams the shared block
/// state to the extension and exits when the port closes.
///
/// Wire format is Chrome native messaging: each message is a 4-byte little-endian
/// length prefix followed by UTF-8 JSON. The app is the only writer of the state
/// file; this host is read-only, so the app→extension flow stays one-directional.
enum FocusHostCLI {
    static func run(arguments: [String]) -> Never {
        let statePath = FocusBlockPaths.stateFile

        func currentState() -> Data {
            if let d = FileManager.default.contents(atPath: statePath) { return d }
            // App hasn't written yet (feature never enabled): report "not blocking".
            return Data(#"{"blocking":false,"sites":[],"reason":""}"#.utf8)
        }

        // Push one framed message to the extension on stdout, tolerating a closed
        // pipe (browser gone) by exiting.
        func send(_ json: Data) {
            var len = UInt32(json.count).littleEndian
            let header = withUnsafeBytes(of: &len) { Data($0) }
            writeAll(header)
            writeAll(json)
        }

        func mtime() -> Date? {
            (try? FileManager.default.attributesOfItem(atPath: statePath)[.modificationDate]) as? Date
        }

        // Initial push.
        send(currentState())
        var lastMTime = mtime()

        // The app writes the state file atomically (temp + rename), so watch by
        // path via a low-rate mtime poll rather than a vnode source on a stale fd.
        let poll = DispatchSource.makeTimerSource(queue: .main)
        poll.schedule(deadline: .now() + 1, repeating: 1.0)
        poll.setEventHandler {
            let m = mtime()
            if m != lastMTime {
                lastMTime = m
                send(currentState())
            }
        }
        poll.resume()

        // Exit as soon as the extension closes the port: stdin hits EOF. Incoming
        // messages are drained and ignored (v1 is one-directional).
        let stdin = DispatchSource.makeReadSource(fileDescriptor: 0, queue: .main)
        stdin.setEventHandler {
            var buf = [UInt8](repeating: 0, count: 65536)
            let n = read(0, &buf, buf.count)
            if n <= 0 { exit(0) } // 0 = EOF (port closed), <0 = error
        }
        stdin.resume()

        dispatchMain()
    }

    /// Write every byte to stdout, handling partial writes; a broken pipe (the
    /// browser closed the port) just ends the process.
    private static func writeAll(_ data: Data) {
        data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
            guard var p = raw.baseAddress else { return }
            var remaining = raw.count
            while remaining > 0 {
                let n = write(1, p, remaining)
                if n <= 0 { exit(0) }
                p = p.advanced(by: n)
                remaining -= n
            }
        }
    }
}
