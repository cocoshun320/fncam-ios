import Foundation
import UIKit

struct UploadJob: Codable {
    var assetId: String
    var name: String
    var kind: String   // image / video
    var time: Double   // 拍摄/开始时间（epoch 秒）
    var dur: Double    // 时长（秒）
    var attempts: Int
}

final class UploadQueue {
    static let shared = UploadQueue()
    static let changedNotification = Notification.Name("UploadQueueChanged")

    private let lock = NSLock()
    private var jobs: [UploadJob] = []
    private var running = false
    private(set) var statusText = ""

    private init() {
        if let data = UserDefaults.standard.data(forKey: "queue"),
           let a = try? JSONDecoder().decode([UploadJob].self, from: data) {
            jobs = a
        }
    }

    var count: Int {
        lock.lock(); defer { lock.unlock() }
        return jobs.count
    }

    var all: [UploadJob] {
        lock.lock(); defer { lock.unlock() }
        return jobs
    }

    private func persist() {
        UserDefaults.standard.set(try? JSONEncoder().encode(jobs), forKey: "queue")
    }

    private func notifyChanged() {
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: UploadQueue.changedNotification, object: nil)
        }
    }

    func add(assetId: String, name: String, kind: String, time: Double, dur: Double) {
        lock.lock()
        if !jobs.contains(where: { $0.assetId == assetId }) {
            jobs.append(UploadJob(assetId: assetId, name: name, kind: kind,
                                  time: time, dur: dur, attempts: 0))
            persist()
        }
        lock.unlock()
        notifyChanged()
        if Settings.shared.autoUpload { kick() }
    }

    func remove(assetId: String) {
        lock.lock()
        jobs.removeAll { $0.assetId == assetId }
        persist()
        lock.unlock()
        notifyChanged()
    }

    private func bump(_ assetId: String) {
        lock.lock()
        if let idx = jobs.firstIndex(where: { $0.assetId == assetId }) {
            jobs[idx].attempts += 1
            let j = jobs.remove(at: idx)
            jobs.append(j)
            persist()
        }
        lock.unlock()
        notifyChanged()
    }

    private func first() -> UploadJob? {
        lock.lock(); defer { lock.unlock() }
        return jobs.first
    }

    private func setStatus(_ s: String) {
        statusText = s
        notifyChanged()
    }

    func kick() {
        lock.lock()
        if running || jobs.isEmpty {
            lock.unlock()
            return
        }
        running = true
        lock.unlock()
        DispatchQueue.global(qos: .utility).async { [weak self] in
            self?.loop()
        }
    }

    private func loop() {
        var bgTask: UIBackgroundTaskIdentifier = .invalid
        bgTask = UIApplication.shared.beginBackgroundTask(withName: "ftp-upload") {
            UIApplication.shared.endBackgroundTask(bgTask)
            bgTask = .invalid
        }
        defer {
            if bgTask != .invalid { UIApplication.shared.endBackgroundTask(bgTask) }
            lock.lock(); running = false; lock.unlock()
        }

        var done = 0
        while let job = first() {
            if job.attempts >= 5 {
                setStatus("有文件多次失败，请检查设置")
                break
            }
            if Settings.shared.host.trimmingCharacters(in: .whitespaces).isEmpty {
                setStatus("未配置 FTP 服务器")
                break
            }
            if Settings.shared.wifiOnly && !NetMonitor.shared.isWiFi {
                setStatus("等待 WiFi 网络")
                break
            }
            guard PhotoStore.asset(job.assetId) != nil else {
                remove(assetId: job.assetId)
                continue
            }
            setStatus("导出 \(job.name)…")
            guard let fileURL = PhotoStore.exportAsset(job.assetId, kind: job.kind) else {
                bump(job.assetId)
                setStatus("读取相册文件失败")
                break
            }
            let ftp = FTPClient()
            do {
                try ftp.connect(host: Settings.shared.host, port: Settings.shared.port,
                                ftps: Settings.shared.ftps)
                try ftp.login(user: Settings.shared.user, pass: Settings.shared.pass)
                try ftp.prepare()
                let base = Settings.shared.dir
                let sub = DirRule.expand(job: job)
                let full = sub.isEmpty ? base : (base == "/" ? "" : base) + "/" + sub
                try ftp.makeAndEnter(path: full)
                try ftp.upload(fileURL: fileURL, remoteName: job.name) { pct in
                    self.setStatus("上传 \(job.name) \(pct)%")
                }
                ftp.quit()
                try? FileManager.default.removeItem(at: fileURL)
                remove(assetId: job.assetId)
                done += 1
                if Settings.shared.deleteAfter {
                    PhotoStore.deleteAsset(job.assetId)
                }
            } catch {
                ftp.quit()
                try? FileManager.default.removeItem(at: fileURL)
                bump(job.assetId)
                setStatus("上传失败：\(error.localizedDescription)")
                break
            }
        }
        if done > 0 { setStatus("已备份 \(done) 个文件") }
        if count == 0 && statusText.isEmpty { setStatus("") }
    }
}