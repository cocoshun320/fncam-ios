import Foundation

enum DirRule {
    static func expand(job: UploadJob) -> String {
        let levels = Settings.shared.dirLevels
        let start = job.time > 0 ? Date(timeIntervalSince1970: job.time) : Date()
        let end = start.addingTimeInterval(TimeInterval(max(0, job.dur)))
        let video = job.kind == "video"

        let dateCn = fmt("yy年M月d日", start)
        let dateIso = fmt("yyyy-MM-dd", start)
        let time = fmt("HH:mm:ss", start)
        let endTime = fmt("HH:mm:ss", end)
        let hour = fmt("HH点", start)
        let type = video ? "视频" : "照片"
        let duration = String(Int(job.dur)) + "秒"
        let range = time + "~" + endTime

        var out: [String] = []
        for level in levels {
            var s = level
            s = s.replacingOccurrences(of: "{date}", with: dateCn)
            s = s.replacingOccurrences(of: "{date2}", with: dateIso)
            s = s.replacingOccurrences(of: "{type}", with: type)
            s = s.replacingOccurrences(of: "{time}", with: time)
            s = s.replacingOccurrences(of: "{start}", with: time)
            s = s.replacingOccurrences(of: "{end}", with: endTime)
            s = s.replacingOccurrences(of: "{hour}", with: hour)
            s = s.replacingOccurrences(of: "{duration}", with: duration)
            s = s.replacingOccurrences(of: "{range}", with: range)
            s = sanitize(s)
            if !s.isEmpty { out.append(s) }
        }
        return out.joined(separator: "/")
    }

    private static func fmt(_ pattern: String, _ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = pattern
        return f.string(from: date)
    }

    private static func sanitize(_ s: String) -> String {
        var r = s
        for ch in ["\\", ":", "*", "?", "\"", "<", ">", "|"] {
            r = r.replacingOccurrences(of: ch, with: "")
        }
        return r.trimmingCharacters(in: .whitespaces)
    }
}