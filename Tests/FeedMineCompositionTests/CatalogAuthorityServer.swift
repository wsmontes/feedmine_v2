import Darwin
import Foundation

/// A real HTTP/1.1 server on loopback, serving one directory: `GET /<path>` answers the file's bytes, and 404 when
/// the directory holds no such file. It exists so the update path is exercised over a socket — URL construction,
/// status handling and byte handling against a server that really answers — instead of against a stubbed session
/// that would agree with whatever URL it was handed.
///
/// `replies` overrides a path: a test can serve bytes that differ from the file on disk (a payload that does not
/// match its declaration) or answer a status the directory does not imply. The port is assigned by the OS, and
/// `stop()` closes the listener, which is how a test states "the authority is not there".
final class CatalogAuthorityServer: @unchecked Sendable {
    /// What the server answers for one declared path, keyed without a leading slash.
    struct Reply {
        let status: Int
        let bytes: Data?
    }

    private let root: URL
    private let replies: [String: Reply]
    private let lock = NSLock()
    private let queue = DispatchQueue(label: "catalog-authority-fixture")
    private var listening: Int32
    let port: UInt16

    init(root: URL, replies: [String: Reply] = [:]) throws {
        let listener = try Self.loopbackListener()
        self.root = root
        self.replies = replies
        self.listening = listener.descriptor
        self.port = listener.port
        queue.async { [self] in acceptLoop() }
    }

    /// `http://127.0.0.1:<port>/` — the payload's base, exactly as the published manifest's own directory is.
    var baseURL: URL { URL(string: "http://127.0.0.1:\(port)/")! }

    /// The manifest the channel is pointed at: `manifest.json` at the served root, the same shape and the same
    /// relation to its payload as the published one.
    var manifestURL: URL { baseURL.appendingPathComponent("manifest.json") }

    /// The URL of any declared path, as the channel will ask for it.
    func url(for path: String) -> URL {
        path.split(separator: "/").reduce(baseURL) { $0.appendingPathComponent(String($1)) }
    }

    func stop() {
        lock.lock()
        let descriptor = listening
        listening = -1
        lock.unlock()
        if descriptor >= 0 { close(descriptor) }
    }

    deinit { stop() }

    // MARK: - Private

    private struct Listener {
        let descriptor: Int32
        let port: UInt16
    }

    private enum ListenError: Error {
        case failed(String)
    }

    /// A listening socket on loopback with an OS-assigned port.
    private static func loopbackListener() throws -> Listener {
        let descriptor = socket(AF_INET, SOCK_STREAM, 0)
        guard descriptor >= 0 else { throw ListenError.failed("socket: errno \(errno)") }
        var reuse: Int32 = 1
        setsockopt(descriptor, SOL_SOCKET, SO_REUSEADDR, &reuse, socklen_t(MemoryLayout<Int32>.size))
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = 0
        address.sin_addr.s_addr = inet_addr("127.0.0.1")
        let bound = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(descriptor, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bound == 0, Darwin.listen(descriptor, 16) == 0 else {
            close(descriptor)
            throw ListenError.failed("bind/listen: errno \(errno)")
        }
        var actual = sockaddr_in()
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        let named = withUnsafeMutablePointer(to: &actual) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(descriptor, $0, &length) }
        }
        guard named == 0 else {
            close(descriptor)
            throw ListenError.failed("getsockname: errno \(errno)")
        }
        return Listener(descriptor: descriptor, port: UInt16(bigEndian: actual.sin_port))
    }

    private func acceptLoop() {
        while true {
            lock.lock()
            let descriptor = listening
            lock.unlock()
            guard descriptor >= 0 else { return }
            let connection = Darwin.accept(descriptor, nil, nil)
            guard connection >= 0 else { return }
            serve(connection)
            close(connection)
        }
    }

    /// One request per connection, answered and closed: enough for a client that asks for files, and nothing that
    /// can outlive the test that started it.
    private func serve(_ connection: Int32) {
        var request = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while !request.contains(Data([13, 10, 13, 10])) {
            let read = recv(connection, &buffer, buffer.count, 0)
            if read <= 0 { return }
            request.append(contentsOf: buffer[0..<read])
        }
        guard let text = String(data: request, encoding: .utf8),
            let line = text.split(separator: "\r\n").first else { return }
        let parts = line.split(separator: " ")
        guard parts.count >= 2 else { return }
        var path = String(parts[1])
        if let query = path.firstIndex(of: "?") { path = String(path[path.startIndex..<query]) }
        path = String(path.drop(while: { $0 == "/" }))
        path = path.removingPercentEncoding ?? path
        let reply = replies[path] ?? servedReply(for: path)
        respond(connection, status: reply.status, body: reply.bytes ?? Data())
    }

    private func servedReply(for path: String) -> Reply {
        let file = path.split(separator: "/").reduce(root) { $0.appendingPathComponent(String($1)) }
        guard let bytes = try? Data(contentsOf: file) else { return Reply(status: 404, bytes: nil) }
        return Reply(status: 200, bytes: bytes)
    }

    private func respond(_ connection: Int32, status: Int, body: Data) {
        let phrase = status == 200 ? "OK" : (status == 404 ? "Not Found" : "Error")
        var response = Data(
            "HTTP/1.1 \(status) \(phrase)\r\nContent-Length: \(body.count)\r\nConnection: close\r\n\r\n".utf8)
        response.append(body)
        response.withUnsafeBytes { raw in
            guard let base = raw.baseAddress else { return }
            var sent = 0
            while sent < raw.count {
                let written = send(connection, base.advanced(by: sent), raw.count - sent, 0)
                if written <= 0 { return }
                sent += written
            }
        }
    }
}
