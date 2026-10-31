import Foundation
import Network
import CryptoKit

/// How the Mac and iPhone apps talk to each other over the home Wi-Fi.
/// This file is identical in both apps (macos/Sources/AuraPlayer/Services/SyncWire.swift and
/// ios/AuraPlayerIOS/Services/SyncWire.swift): keep them in step.
///
/// One message = 4 bytes header length, 4 bytes body length, the header (JSON), the body (raw bytes).
/// Every request is signed with the pairing code shown on the Mac, so other devices on the network can't read or change the library.
enum SyncWire {
    static let serviceType = "_auraplayer._tcp"
    static let maxBody = 64 * 1024 * 1024
    static let maxClockSkew: Double = 300
    
    struct Header: Codable {
        var op: String
        var time: Double = Date().timeIntervalSince1970
        var auth: String = ""
        /// Request: the revision the sender based its change on. Response: the current revision.
        var revision: String?
        var ok: Bool?
        var error: String?
        var device: String?
    }
    
    // MARK: - Pairing code
    
    static func sign(code: String, op: String, time: Double) -> String {
        let key = SymmetricKey(data: Data(code.utf8))
        let mac = HMAC<SHA256>.authenticationCode(for: Data("\(op)|\(Int(time))".utf8), using: key)
        return Data(mac).map { String(format: "%02x", $0) }.joined()
    }
    
    static func isAuthorized(_ header: Header, code: String) -> Bool {
        guard abs(Date().timeIntervalSince1970 - header.time) < maxClockSkew else { return false }
        let expected = Data(sign(code: code, op: header.op, time: header.time).utf8)
        let given = Data(header.auth.utf8)
        guard expected.count == given.count else { return false }
        return zip(expected, given).reduce(0) { $0 | ($1.0 ^ $1.1) } == 0   // constant time
    }
    
    /// Short fingerprint of some data: two copies of the library with the same revision are identical
    static func revision(of data: Data) -> String {
        SHA256.hash(data: data).prefix(12).map { String(format: "%02x", $0) }.joined()
    }
    
    enum WireError: Error, LocalizedError {
        case closed, tooLarge, badMessage, timeout
        var errorDescription: String? {
            switch self {
            case .closed: return "The connection closed"
            case .tooLarge: return "The library is too large to sync"
            case .badMessage: return "Unreadable message"
            case .timeout: return "Timed out"
            }
        }
    }
}

/// Sends and receives whole messages over one connection
final class SyncChannel: @unchecked Sendable {
    let connection: NWConnection
    
    init(_ connection: NWConnection) { self.connection = connection }
    
    /// Waits until the connection is usable
    func start(timeout: TimeInterval = 8) async throws {
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask { [connection] in
                try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
                    final class Once: @unchecked Sendable { var done = false }
                    let once = Once()
                    connection.stateUpdateHandler = { state in
                        guard !once.done else { return }
                        switch state {
                        case .ready: once.done = true; cont.resume()
                        case .failed(let e): once.done = true; cont.resume(throwing: e)
                        case .cancelled: once.done = true; cont.resume(throwing: SyncWire.WireError.closed)
                        default: break
                        }
                    }
                    connection.start(queue: .global(qos: .userInitiated))
                }
            }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                throw SyncWire.WireError.timeout
            }
            _ = try await group.next()
            group.cancelAll()
        }
    }
    
    func close() { connection.cancel() }
    
    func send(_ header: SyncWire.Header, body: Data = Data()) async throws {
        let headerData = try JSONEncoder().encode(header)
        var message = Data()
        for length in [UInt32(headerData.count), UInt32(body.count)] {
            withUnsafeBytes(of: length.bigEndian) { message.append(contentsOf: $0) }
        }
        message.append(headerData)
        message.append(body)
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            connection.send(content: message, completion: .contentProcessed { error in
                if let error { cont.resume(throwing: error) } else { cont.resume() }
            })
        }
    }
    
    func receive() async throws -> (SyncWire.Header, Data) {
        let lengths = try await readExactly(8)
        let headerLength = Int(lengths.prefix(4).reduce(UInt32(0)) { $0 << 8 | UInt32($1) })
        let bodyLength = Int(lengths.suffix(4).reduce(UInt32(0)) { $0 << 8 | UInt32($1) })
        guard headerLength > 0, headerLength < 64 * 1024 else { throw SyncWire.WireError.badMessage }
        guard bodyLength <= SyncWire.maxBody else { throw SyncWire.WireError.tooLarge }
        let headerData = try await readExactly(headerLength)
        let body = bodyLength > 0 ? try await readExactly(bodyLength) : Data()
        guard let header = try? JSONDecoder().decode(SyncWire.Header.self, from: headerData) else { throw SyncWire.WireError.badMessage }
        return (header, body)
    }
    
    private func readExactly(_ count: Int) async throws -> Data {
        var result = Data()
        while result.count < count {
            let chunk: Data = try await withCheckedThrowingContinuation { cont in
                connection.receive(minimumIncompleteLength: 1, maximumLength: min(count - result.count, 1 << 20)) { data, _, isComplete, error in
                    if let error { cont.resume(throwing: error) }
                    else if let data, !data.isEmpty { cont.resume(returning: data) }
                    else { cont.resume(throwing: SyncWire.WireError.closed) }
                }
            }
            result.append(chunk)
        }
        return result
    }
}
