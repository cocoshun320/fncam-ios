import Foundation
import CFNetwork

/// 基于 Foundation Stream 的同步 FTP 客户端（在后台线程调用）。
/// 支持 PASV、MKD 逐级建目录、SIZE 查询、REST 断点续传、显式 FTPS（实验性）。
final class FTPClient {
    struct Reply {
        let code: Int
        let text: String
    }

    enum FTPError: LocalizedError {
        case msg(String)
        var errorDescription: String? {
            switch self { case .msg(let s): return s }
        }
    }

    private var inStream: InputStream?
    private var outStream: OutputStream?
    private var readBuf = Data()
    private var host = ""
    private var useTLS = false

    // MARK: - 连接与命令

    func connect(host: String, port: Int, ftps: Bool) throws {
        self.host = host
        self.useTLS = ftps
        var ins: InputStream?
        var outs: OutputStream?
        Stream.getStreamsToHost(withName: host, port: port, inputStream: &ins, outputStream: &outs)
        guard let i = ins, let o = outs else { throw FTPError.msg("无法创建连接") }
        inStream = i
        outStream = o
        i.schedule(in: .current, forMode: .default)
        o.schedule(in: .current, forMode: .default)
        i.open()
        o.open()
        try waitOpen(i)
        try waitOpen(o)
        let r = try readReply(timeout: 20)
        guard r.code == 220 else { throw FTPError.msg("连接被拒绝: \(r.text)") }
        if ftps {
            let auth = try command("AUTH TLS")
            guard auth.code == 234 else { throw FTPError.msg("服务器不支持 FTPS: \(auth.text)") }
            applyTLS(i, beforeOpen: false)
            applyTLS(o, beforeOpen: false)
            _ = try command("PBSZ 0")
            let prot = try command("PROT P")
            guard prot.code == 200 else { throw FTPError.msg("FTPS 加密通道失败: \(prot.text)") }
        }
    }

    func login(user: String, pass: String) throws {
        let u = try command("USER " + (user.isEmpty ? "anonymous" : user))
        if u.code == 230 { return }
        guard u.code == 331 else { throw FTPError.msg("登录失败: \(u.text)") }
        let p = try command("PASS " + pass)
        guard p.code == 230 || p.code == 202 else { throw FTPError.msg("账号或密码错误: \(p.text)") }
    }

    func prepare() throws {
        let t = try command("TYPE I")
        guard t.code == 200 else { throw FTPError.msg("TYPE 失败: \(t.text)") }
    }

    /// 逐级创建并进入目录，path 形如 /backup/26年11月23日/照片
    func makeAndEnter(path: String) throws {
        let clean = path.trimmingCharacters(in: .whitespaces)
        if clean.isEmpty || clean == "/" { return }
        let cwd = try command("CWD " + clean)
        if cwd.code == 250 { return }
        var cur = ""
        for seg in clean.split(separator: "/") {
            if seg.isEmpty { continue }
            cur += "/" + seg
            _ = try command("MKD " + cur)
        }
        let again = try command("CWD " + clean)
        guard again.code == 250 else { throw FTPError.msg("无法进入目录 \(clean): \(again.text)") }
    }

    func remoteSize(_ name: String) -> Int64 {
        if let r = try? command("SIZE " + name), r.code == 213 {
            return Int64(r.text.trimmingCharacters(in: .whitespaces)) ?? 0
        }
        return 0
    }

    func quit() {
        _ = try? command("QUIT")
        closeControl()
    }

    // MARK: - 上传（断点续传）

    func upload(fileURL: URL, remoteName: String, progress: @escaping (Int) -> Void) throws {
        let attrs = try FileManager.default.attributesOfItem(atPath: fileURL.path)
        let total = (attrs[.size] as? NSNumber)?.int64Value ?? 0
        guard total > 0 else { throw FTPError.msg("本地文件为空") }
        var offset = remoteSize(remoteName)
        if offset >= total {
            progress(100)
            return
        }
        do {
            try doUpload(fileURL: fileURL, remoteName: remoteName, total: total,
                         offset: offset, progress: progress)
        } catch {
            // 续传失败则删掉远端残片整文件重传一次
            _ = try? command("DELE " + remoteName)
            offset = 0
            try doUpload(fileURL: fileURL, remoteName: remoteName, total: total,
                         offset: 0, progress: progress)
        }
    }

    private func doUpload(fileURL: URL, remoteName: String, total: Int64,
                          offset: Int64, progress: @escaping (Int) -> Void) throws {
        let (dHost, dPort) = try pasv()
        var dins: InputStream?
        var douts: OutputStream?
        Stream.getStreamsToHost(withName: dHost, port: dPort, inputStream: &dins, outputStream: &douts)
        guard let di = dins, let do_ = douts else { throw FTPError.msg("无法创建数据连接") }
        if useTLS {
            applyTLS(di, beforeOpen: true)
            applyTLS(do_, beforeOpen: true)
        }
        di.schedule(in: .current, forMode: .default)
        do_.schedule(in: .current, forMode: .default)
        di.open()
        do_.open()
        try waitOpen(di)
        try waitOpen(do_)

        if offset > 0 {
            let rest = try command("REST " + String(offset))
            guard rest.code == 350 else { throw FTPError.msg("服务器不支持续传: \(rest.text)") }
        }
        let stor = try command("STOR " + remoteName)
        guard stor.code == 150 || stor.code == 125 else {
            di.close(); do_.close()
            throw FTPError.msg("上传被拒绝: \(stor.text)")
        }

        let handle = try FileHandle(forReadingFrom: fileURL)
        defer { try? handle.close() }
        if offset > 0 { try handle.seek(toOffset: UInt64(offset)) }
        var sent = offset
        var lastTs = Date(timeIntervalSince1970: 0)
        while true {
            guard let chunk = try handle.read(upToCount: 65536), !chunk.isEmpty else { break }
            try writeAll(chunk, to: do_, timeout: 120)
            sent += Int64(chunk.count)
            let now = Date()
            if now.timeIntervalSince(lastTs) > 0.7 || sent >= total {
                lastTs = now
                progress(Int(min(100, sent * 100 / total)))
            }
        }
        do_.close()
        let done = try readReply(timeout: 60)
        di.close()
        guard done.code == 226 || done.code == 250 else {
            throw FTPError.msg("上传未完成: \(done.text)")
        }
        progress(100)
    }

    private func pasv() throws -> (String, Int) {
        let r = try command("PASV")
        guard r.code == 227 else { throw FTPError.msg("PASV 失败: \(r.text)") }
        guard let open = r.text.firstIndex(of: "("), let close = r.text.firstIndex(of: ")") else {
            throw FTPError.msg("PASV 响应异常: \(r.text)")
        }
        let inner = r.text[r.text.index(after: open)..<close]
        let parts = inner.split(separator: ",").compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
        guard parts.count >= 6 else { throw FTPError.msg("PASV 解析失败: \(r.text)") }
        let host = "\(parts[0]).\(parts[1]).\(parts[2]).\(parts[3])"
        let port = parts[4] * 256 + parts[5]
        return (host, port)
    }

    // MARK: - TLS

    private func applyTLS(_ stream: Stream, beforeOpen: Bool) {
        let ssl: [String: Any] = [
            kCFStreamSSLValidatesCertificateChain as String: false,
            kCFStreamSSLPeerName as String: host
        ]
        stream.setProperty(ssl, forKey: Stream.PropertyKey(rawValue: kCFStreamPropertySSLSettings as String))
        stream.setProperty(StreamSocketSecurityLevel.negotiatedSSL, forKey: .socketSecurityLevelKey)
    }

    // MARK: - 底层读写

    private func command(_ cmd: String) throws -> Reply {
        guard let o = outStream else { throw FTPError.msg("连接已关闭") }
        try writeAll(Data((cmd + "\r\n").utf8), to: o, timeout: 20)
        return try readReply(timeout: 30)
    }

    private func waitOpen(_ stream: Stream) throws {
        let deadline = Date().addingTimeInterval(15)
        while stream.streamStatus == .opening || stream.streamStatus == .notOpen {
            if Date() > deadline { throw FTPError.msg("连接超时") }
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.05))
        }
        if stream.streamStatus == .error || stream.streamStatus == .atEnd {
            throw FTPError.msg("连接失败: \(stream.streamError?.localizedDescription ?? "未知")")
        }
    }

    private func writeAll(_ data: Data, to stream: OutputStream, timeout: TimeInterval) throws {
        var offset = 0
        let deadline = Date().addingTimeInterval(timeout)
        while offset < data.count {
            if Date() > deadline { throw FTPError.msg("发送超时") }
            if stream.hasSpaceAvailable {
                let n = data.withUnsafeBytes { (ptr: UnsafeRawBufferPointer) -> Int in
                    guard let base = ptr.baseAddress else { return -1 }
                    return stream.write(base.advanced(by: offset).assumingMemoryBound(to: UInt8.self),
                                        maxLength: data.count - offset)
                }
                if n > 0 {
                    offset += n
                } else if n < 0 {
                    throw FTPError.msg("发送失败: \(stream.streamError?.localizedDescription ?? "未知")")
                }
            } else {
                RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.02))
            }
        }
    }

    private func readReply(timeout: TimeInterval) throws -> Reply {
        let deadline = Date().addingTimeInterval(timeout)
        var tmp = [UInt8](repeating: 0, count: 8192)
        while true {
            if let reply = parseReply() { return reply }
            if Date() > deadline { throw FTPError.msg("等待服务器响应超时") }
            if let i = inStream, i.hasBytesAvailable {
                let n = i.read(&tmp, maxLength: tmp.count)
                if n > 0 {
                    readBuf.append(contentsOf: tmp[0..<n])
                } else if n < 0 {
                    throw FTPError.msg("读取失败: \(i.streamError?.localizedDescription ?? "连接断开")")
                }
            } else {
                if let i = inStream, i.streamStatus == .atEnd || i.streamStatus == .error {
                    throw FTPError.msg("连接已断开")
                }
                RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.03))
            }
        }
    }

    /// 从缓冲区解析一条完整 FTP 回复（支持多行）
    private func parseReply() -> Reply? {
        guard let sep = readBuf.range(of: Data("\r\n".utf8)) else { return nil }
        // 逐行扫描，找到 "NNN " 结尾行
        var cursor = readBuf.startIndex
        var lines: [String] = []
        var code: Int?
        var endPos: Data.Index?
        while let r = readBuf.range(of: Data("\r\n".utf8), in: cursor..<readBuf.endIndex) {
            let lineData = readBuf[cursor..<r.lowerBound]
            let line = String(data: lineData, encoding: .utf8) ?? ""
            lines.append(line)
            cursor = r.upperBound
            if line.count >= 4 {
                let prefix = String(line.prefix(3))
                if let c = Int(prefix), line[line.index(line.startIndex, offsetBy: 3)] == " " {
                    code = c
                    endPos = r.upperBound
                    break
                }
            }
            _ = sep
        }
        guard let c = code, let end = endPos else { return nil }
        readBuf.removeSubrange(readBuf.startIndex..<end)
        return Reply(code: c, text: lines.joined(separator: " "))
    }

    private func closeControl() {
        inStream?.close()
        outStream?.close()
        inStream = nil
        outStream = nil
        readBuf.removeAll()
    }
}