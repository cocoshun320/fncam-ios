import UIKit

final class SettingsViewController: UIViewController {
    private let scroll = UIScrollView()
    private let stack = UIStackView()
    private let levelsStack = UIStackView()
    private let previewLabel = UILabel()

    private let hostField = UITextField()
    private let portField = UITextField()
    private let userField = UITextField()
    private let passField = UITextField()
    private let dirField = UITextField()
    private let albumField = UITextField()
    private let segField = UITextField()
    private let maxField = UITextField()

    private let ftpsSwitch = UISwitch()
    private let wifiSwitch = UISwitch()
    private let delSwitch = UISwitch()
    private let autoSwitch = UISwitch()

    private var levels: [String] = Settings.shared.dirLevels

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor(white: 0.08, alpha: 1)
        title = "设置"

        scroll.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scroll)
        stack.axis = .vertical
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        scroll.addSubview(stack)
        NSLayoutConstraint.activate([
            scroll.frameLayoutGuide.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scroll.frameLayoutGuide.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scroll.frameLayoutGuide.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scroll.frameLayoutGuide.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor, constant: -20),
            stack.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor, constant: 16),
            stack.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor, constant: -40),
            stack.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor, constant: -40)
        ])

        let back = UIButton(type: .system)
        back.setTitle("← 返回相机", for: .normal)
        back.setTitleColor(.white, for: .normal)
        back.contentHorizontalAlignment = .left
        back.addAction(UIAction { [weak self] _ in self?.navigationController?.popViewController(animated: true) }, for: .touchUpInside)
        stack.addArrangedSubview(back)

        addTitle("FTP 备份（飞牛 NAS）")
        addNote("在 fnOS 开启 FTP 服务，填写地址账号。普通 FTP 明文传输，建议局域网使用。")
        configField(hostField, "服务器地址", Settings.shared.host, .default)
        configField(portField, "端口", String(Settings.shared.port), .numberPad)
        configField(userField, "用户名", Settings.shared.user, .default)
        configField(passField, "密码", Settings.shared.pass, .default)
        passField.isSecureTextEntry = true
        configField(dirField, "远程目录", Settings.shared.dir, .default)
        addSwitch("使用 FTPS（加密，实验性）", ftpsSwitch, Settings.shared.ftps)
        addSwitch("仅 WiFi 下上传", wifiSwitch, Settings.shared.wifiOnly)
        addSwitch("上传成功后从相册删除（iOS 会弹确认框）", delSwitch, Settings.shared.deleteAfter)
        addSwitch("拍摄后自动上传", autoSwitch, Settings.shared.autoUpload)

        addTitle("相册与录制")
        configField(albumField, "相册分组名", Settings.shared.album, .default)
        configField(segField, "每段时长（秒，0=不分段）", String(Settings.shared.segmentSec), .numberPad)
        configField(maxField, "最长总时长（分钟，0=不限）", String(Settings.shared.maxTotalMin), .numberPad)

        addTitle("FTP 子目录（点选）")
        addNote("每一级是一个文件夹，点该行直接选命名方式，不用输入代码。")
        levelsStack.axis = .vertical
        levelsStack.spacing = 6
        stack.addArrangedSubview(levelsStack)
        let addLevel = smallButton("+ 添加一级") { [weak self] in
            guard let self = self else { return }
            if self.levels.count >= 5 { self.toast("最多 5 级"); return }
            self.levels.append("{date}")
            self.rebuildLevels()
        }
        stack.addArrangedSubview(addLevel)
        previewLabel.textColor = UIColor(white: 0.7, alpha: 1)
        previewLabel.font = .systemFont(ofSize: 12)
        previewLabel.numberOfLines = 0
        stack.addArrangedSubview(previewLabel)
        let presetRow = UIStackView()
        presetRow.axis = .horizontal
        presetRow.spacing = 6
        presetRow.distribution = .fillEqually
        presetRow.addArrangedSubview(smallButton("日期/类型") { [weak self] in self?.applyPreset(["{date}", "{type}"]) })
        presetRow.addArrangedSubview(smallButton("日期/时长/时段") { [weak self] in self?.applyPreset(["{date}", "{duration}", "{range}"]) })
        presetRow.addArrangedSubview(smallButton("仅日期") { [weak self] in self?.applyPreset(["{date}"]) })
        stack.addArrangedSubview(presetRow)
        rebuildLevels()

        stack.addArrangedSubview(bigButton("保存设置") { [weak self] in self?.save() })
        stack.addArrangedSubview(bigButton("测试 FTP 连接") { [weak self] in self?.testFTP() })
        stack.addArrangedSubview(bigButton("立即上传队列") { [weak self] in
            UploadQueue.shared.kick()
            self?.toast("已开始上传 \(UploadQueue.shared.count) 个文件")
        })
        addNote("照片视频存入相册「\(Settings.shared.album)」分组。iOS 限制：锁屏或退后台时相机和上传会被系统暂停，无法息屏拍摄。")
    }

    // MARK: - 目录点选

    private func applyPreset(_ v: [String]) {
        levels = v
        rebuildLevels()
    }

    private func rebuildLevels() {
        Settings.shared.dirLevels = levels
        levelsStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        if levels.isEmpty {
            addNoteTo(levelsStack, "未设置子目录：文件直接传到远程目录")
        }
        for (i, level) in levels.enumerated() {
            let row = UIStackView()
            row.axis = .horizontal
            row.spacing = 6
            let sel = UIButton(type: .system)
            sel.setTitle("第\(i + 1)级 · \(labelFor(level))", for: .normal)
            sel.setTitleColor(.white, for: .normal)
            sel.titleLabel?.font = .systemFont(ofSize: 13)
            sel.backgroundColor = UIColor(red: 0.16, green: 0.36, blue: 0.54, alpha: 1)
            sel.layer.cornerRadius = 8
            sel.heightAnchor.constraint(equalToConstant: 44).isActive = true
            sel.addAction(UIAction { [weak self] _ in self?.pickLevel(i) }, for: .touchUpInside)
            row.addArrangedSubview(sel)
            let del = UIButton(type: .system)
            del.setTitle("删除", for: .normal)
            del.setTitleColor(.white, for: .normal)
            del.backgroundColor = UIColor(red: 0.35, green: 0.16, blue: 0.16, alpha: 1)
            del.layer.cornerRadius = 8
            del.widthAnchor.constraint(equalToConstant: 60).isActive = true
            del.addAction(UIAction { [weak self] _ in
                self?.levels.remove(at: i)
                self?.rebuildLevels()
            }, for: .touchUpInside)
            row.addArrangedSubview(del)
            levelsStack.addArrangedSubview(row)
        }
        refreshPreview()
    }

    private func pickLevel(_ idx: Int) {
        let options: [(String, String?)] = [
            ("日期（如 26年11月15日）", "{date}"),
            ("日期（如 2026-11-15）", "{date2}"),
            ("类型（照片 / 视频）", "{type}"),
            ("时长（如 100秒）", "{duration}"),
            ("开始时间（如 11:56:00）", "{start}"),
            ("结束时间（如 14:00:00）", "{end}"),
            ("时段（如 11:56:00~14:00:00）", "{range}"),
            ("小时（如 11点）", "{hour}"),
            ("固定文字（自定义）", nil)
        ]
        let ac = UIAlertController(title: "选择第\(idx + 1)级文件夹命名", message: nil, preferredStyle: .actionSheet)
        for (title, value) in options {
            ac.addAction(UIAlertAction(title: title, style: .default) { [weak self] _ in
                guard let self = self else { return }
                if let v = value {
                    self.levels[idx] = v
                    self.rebuildLevels()
                } else {
                    self.askFixedText(idx)
                }
            })
        }
        ac.addAction(UIAlertAction(title: "取消", style: .cancel))
        if let pop = ac.popoverPresentationController {
            pop.sourceView = view
            pop.sourceRect = CGRect(x: view.bounds.midX, y: view.bounds.midY, width: 0, height: 0)
        }
        present(ac, animated: true)
    }

    private func askFixedText(_ idx: Int) {
        let ac = UIAlertController(title: "固定文字", message: "输入文件夹名", preferredStyle: .alert)
        ac.addTextField { $0.placeholder = "如 我的备份" }
        ac.addAction(UIAlertAction(title: "确定", style: .default) { [weak self] _ in
            let t = (ac.textFields?.first?.text ?? "").trimmingCharacters(in: .whitespaces)
                .replacingOccurrences(of: "/", with: "-")
            if !t.isEmpty {
                self?.levels[idx] = t
                self?.rebuildLevels()
            }
        })
        ac.addAction(UIAlertAction(title: "取消", style: .cancel))
        present(ac, animated: true)
    }

    private func labelFor(_ v: String) -> String {
        switch v {
        case "{date}": return "日期（26年11月15日）"
        case "{date2}": return "日期（2026-11-15）"
        case "{type}": return "类型（照片/视频）"
        case "{duration}": return "时长（100秒）"
        case "{start}": return "开始时间（11:56:00）"
        case "{end}": return "结束时间（14:00:00）"
        case "{range}": return "时段（开始~结束）"
        case "{hour}": return "小时（11点）"
        default: return "固定文字：\(v)"
        }
    }

    private func refreshPreview() {
        let demo = UploadJob(assetId: "", name: "IMG_示例.jpg", kind: "image",
                             time: Date().timeIntervalSince1970, dur: 100, attempts: 0)
        let sub = DirRule.expand(job: demo)
        let base = Settings.shared.dir.isEmpty ? "/" : Settings.shared.dir
        previewLabel.text = "路径预览：" + base + (sub.isEmpty ? "" : "/" + sub) + "/IMG_示例.jpg"
    }

    // MARK: - 保存 / 测试

    private func save() {
        Settings.shared.host = hostField.text?.trimmingCharacters(in: .whitespaces) ?? ""
        Settings.shared.port = Int(portField.text ?? "") ?? 21
        Settings.shared.user = userField.text ?? ""
        Settings.shared.pass = passField.text ?? ""
        let d = dirField.text?.trimmingCharacters(in: .whitespaces) ?? "/"
        Settings.shared.dir = d.isEmpty ? "/" : d
        let al = albumField.text?.trimmingCharacters(in: .whitespaces) ?? ""
        Settings.shared.album = al.isEmpty ? "影传相机" : al
        Settings.shared.segmentSec = max(0, Int(segField.text ?? "") ?? 0)
        Settings.shared.maxTotalMin = max(0, Int(maxField.text ?? "") ?? 0)
        Settings.shared.ftps = ftpsSwitch.isOn
        Settings.shared.wifiOnly = wifiSwitch.isOn
        Settings.shared.deleteAfter = delSwitch.isOn
        Settings.shared.autoUpload = autoSwitch.isOn
        Settings.shared.dirLevels = levels
        toast("已保存")
    }

    private func testFTP() {
        save()
        toast("正在连接…")
        DispatchQueue.global(qos: .utility).async { [weak self] in
            var msg: String
            let ftp = FTPClient()
            do {
                try ftp.connect(host: Settings.shared.host, port: Settings.shared.port, ftps: Settings.shared.ftps)
                try ftp.login(user: Settings.shared.user, pass: Settings.shared.pass)
                try ftp.prepare()
                try ftp.makeAndEnter(path: Settings.shared.dir)
                msg = "连接成功，目录可访问"
                ftp.quit()
            } catch {
                msg = "失败：\(error.localizedDescription)"
                ftp.quit()
            }
            DispatchQueue.main.async { self?.toast(msg) }
        }
    }

    // MARK: - UI  helpers

    private func addTitle(_ t: String) {
        let l = UILabel()
        l.text = t
        l.textColor = .white
        l.font = .systemFont(ofSize: 19, weight: .semibold)
        stack.addArrangedSubview(l)
    }

    private func addNote(_ t: String) { addNoteTo(stack, t) }

    private func addNoteTo(_ s: UIStackView, _ t: String) {
        let l = UILabel()
        l.text = t
        l.textColor = UIColor(white: 0.65, alpha: 1)
        l.font = .systemFont(ofSize: 12)
        l.numberOfLines = 0
        s.addArrangedSubview(l)
    }

    private func configField(_ f: UITextField, _ placeholder: String, _ value: String, _ kb: UIKeyboardType) {
        let l = UILabel()
        l.text = placeholder
        l.textColor = UIColor(white: 0.7, alpha: 1)
        l.font = .systemFont(ofSize: 12)
        stack.addArrangedSubview(l)
        f.placeholder = placeholder
        f.text = value
        f.keyboardType = kb
        f.textColor = .white
        f.backgroundColor = UIColor(white: 0.15, alpha: 1)
        f.layer.cornerRadius = 6
        f.leftView = UIView(frame: CGRect(x: 0, y: 0, width: 10, height: 1))
        f.leftViewMode = .always
        f.heightAnchor.constraint(equalToConstant: 42).isActive = true
        f.autocorrectionType = .no
        f.autocapitalizationType = .none
        stack.addArrangedSubview(f)
    }

    private func addSwitch(_ title: String, _ sw: UISwitch, _ on: Bool) {
        let row = UIStackView()
        row.axis = .horizontal
        let l = UILabel()
        l.text = title
        l.textColor = .white
        l.font = .systemFont(ofSize: 13)
        l.numberOfLines = 0
        sw.isOn = on
        row.addArrangedSubview(l)
        row.addArrangedSubview(sw)
        stack.addArrangedSubview(row)
    }

    private func smallButton(_ title: String, action: @escaping () -> Void) -> UIButton {
        let b = UIButton(type: .system)
        b.setTitle(title, for: .normal)
        b.setTitleColor(.white, for: .normal)
        b.titleLabel?.font = .systemFont(ofSize: 12)
        b.backgroundColor = UIColor(red: 0.2, green: 0.33, blue: 0.48, alpha: 1)
        b.layer.cornerRadius = 8
        b.heightAnchor.constraint(equalToConstant: 40).isActive = true
        b.addAction(UIAction { _ in action() }, for: .touchUpInside)
        return b
    }

    private func bigButton(_ title: String, action: @escaping () -> Void) -> UIButton {
        let b = UIButton(type: .system)
        b.setTitle(title, for: .normal)
        b.setTitleColor(.white, for: .normal)
        b.backgroundColor = UIColor(red: 0.16, green: 0.36, blue: 0.54, alpha: 1)
        b.layer.cornerRadius = 8
        b.heightAnchor.constraint(equalToConstant: 48).isActive = true
        b.addAction(UIAction { _ in action() }, for: .touchUpInside)
        return b
    }

    private func toast(_ s: String) {
        let ac = UIAlertController(title: nil, message: s, preferredStyle: .alert)
        present(ac, animated: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { ac.dismiss(animated: true) }
    }
}