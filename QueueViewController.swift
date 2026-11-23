import UIKit
import Photos

final class QueueViewController: UIViewController, UITableViewDataSource, UITableViewDelegate {
    private let table = UITableView(frame: .zero, style: .plain)
    private let summary = UILabel()
    private var jobs: [UploadJob] = []

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor(white: 0.08, alpha: 1)
        table.backgroundColor = .clear
        table.separatorStyle = .none
        table.dataSource = self
        table.delegate = self
        table.rowHeight = 76
        table.register(QueueCell.self, forCellReuseIdentifier: "cell")
        table.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(table)

        let header = UIView()
        header.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(header)

        let back = UIButton(type: .system)
        back.setTitle("← 返回", for: .normal)
        back.setTitleColor(.white, for: .normal)
        back.addAction(UIAction { [weak self] _ in self?.navigationController?.popViewController(animated: true) }, for: .touchUpInside)

        let title = UILabel()
        title.text = "上传队列"
        title.textColor = .white
        title.font = .systemFont(ofSize: 20, weight: .semibold)

        summary.textColor = UIColor(white: 0.65, alpha: 1)
        summary.font = .systemFont(ofSize: 12)
        summary.numberOfLines = 0

        let upload = UIButton(type: .system)
        upload.setTitle("立即上传", for: .normal)
        upload.setTitleColor(.white, for: .normal)
        upload.backgroundColor = UIColor(red: 0.16, green: 0.36, blue: 0.54, alpha: 1)
        upload.layer.cornerRadius = 8
        upload.addAction(UIAction { _ in UploadQueue.shared.kick() }, for: .touchUpInside)

        let refresh = UIButton(type: .system)
        refresh.setTitle("刷新", for: .normal)
        refresh.setTitleColor(.white, for: .normal)
        refresh.backgroundColor = UIColor(red: 0.2, green: 0.33, blue: 0.48, alpha: 1)
        refresh.layer.cornerRadius = 8
        refresh.addAction(UIAction { [weak self] _ in self?.reload() }, for: .touchUpInside)

        let btnRow = UIStackView(arrangedSubviews: [upload, refresh])
        btnRow.axis = .horizontal
        btnRow.spacing = 8
        btnRow.distribution = .fillEqually

        [back, title, summary, btnRow].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            header.addSubview($0)
        }
        NSLayoutConstraint.activate([
            header.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            header.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            header.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
            back.leadingAnchor.constraint(equalTo: header.leadingAnchor),
            back.topAnchor.constraint(equalTo: header.topAnchor),
            title.leadingAnchor.constraint(equalTo: header.leadingAnchor),
            title.topAnchor.constraint(equalTo: back.bottomAnchor, constant: 6),
            summary.leadingAnchor.constraint(equalTo: header.leadingAnchor),
            summary.trailingAnchor.constraint(equalTo: header.trailingAnchor),
            summary.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 6),
            btnRow.leadingAnchor.constraint(equalTo: header.leadingAnchor),
            btnRow.trailingAnchor.constraint(equalTo: header.trailingAnchor),
            btnRow.topAnchor.constraint(equalTo: summary.bottomAnchor, constant: 10),
            btnRow.heightAnchor.constraint(equalToConstant: 44),
            btnRow.bottomAnchor.constraint(equalTo: header.bottomAnchor),
            table.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            table.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            table.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 10),
            table.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        NotificationCenter.default.addObserver(self, selector: #selector(reload),
                                               name: UploadQueue.changedNotification, object: nil)
        reload()
    }

    @objc private func reload() {
        jobs = UploadQueue.shared.all
        let status = UploadQueue.shared.statusText
        summary.text = "共 \(jobs.count) 个文件待上传" + (status.isEmpty ? "" : " · \(status)")
        table.reloadData()
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        jobs.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath) as! QueueCell
        let job = jobs[indexPath.row]
        cell.configure(job) { [weak self] in
            UploadQueue.shared.remove(assetId: job.assetId)
            self?.reload()
        }
        return cell
    }
}

final class QueueCell: UITableViewCell {
    private let thumb = UIImageView()
    private let nameLabel = UILabel()
    private let metaLabel = UILabel()
    private let removeButton = UIButton(type: .system)
    private var onRemove: (() -> Void)?
    private var currentId = ""

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        backgroundColor = .clear
        selectionStyle = .none
        let card = UIView()
        card.backgroundColor = UIColor(white: 0.15, alpha: 1)
        card.layer.cornerRadius = 8
        card.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(card)
        thumb.contentMode = .scaleAspectFill
        thumb.clipsToBounds = true
        thumb.backgroundColor = UIColor(white: 0.25, alpha: 1)
        thumb.layer.cornerRadius = 6
        nameLabel.textColor = .white
        nameLabel.font = .systemFont(ofSize: 13)
        nameLabel.lineBreakMode = .byTruncatingMiddle
        metaLabel.textColor = UIColor(white: 0.6, alpha: 1)
        metaLabel.font = .systemFont(ofSize: 11)
        removeButton.setTitle("移出", for: .normal)
        removeButton.setTitleColor(.white, for: .normal)
        removeButton.backgroundColor = UIColor(red: 0.35, green: 0.16, blue: 0.16, alpha: 1)
        removeButton.layer.cornerRadius = 6
        removeButton.addAction(UIAction { [weak self] _ in self?.onRemove?() }, for: .touchUpInside)
        [thumb, nameLabel, metaLabel, removeButton].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            card.addSubview($0)
        }
        NSLayoutConstraint.activate([
            card.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            card.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            card.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 3),
            card.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -3),
            thumb.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 8),
            thumb.centerYAnchor.constraint(equalTo: card.centerYAnchor),
            thumb.widthAnchor.constraint(equalToConstant: 56),
            thumb.heightAnchor.constraint(equalToConstant: 56),
            nameLabel.leadingAnchor.constraint(equalTo: thumb.trailingAnchor, constant: 10),
            nameLabel.topAnchor.constraint(equalTo: card.topAnchor, constant: 14),
            nameLabel.trailingAnchor.constraint(equalTo: removeButton.leadingAnchor, constant: -8),
            metaLabel.leadingAnchor.constraint(equalTo: nameLabel.leadingAnchor),
            metaLabel.topAnchor.constraint(equalTo: nameLabel.bottomAnchor, constant: 4),
            removeButton.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -8),
            removeButton.centerYAnchor.constraint(equalTo: card.centerYAnchor),
            removeButton.widthAnchor.constraint(equalToConstant: 56),
            removeButton.heightAnchor.constraint(equalToConstant: 36)
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    func configure(_ job: UploadJob, onRemove: @escaping () -> Void) {
        self.onRemove = onRemove
        currentId = job.assetId
        nameLabel.text = job.name
        let kind = job.kind == "video" ? "视频" : "照片"
        let retry = job.attempts > 0 ? " · 重试 \(job.attempts) 次" : ""
        metaLabel.text = kind + " · " + human(jobSize(job)) + retry
        thumb.image = nil
        let id = job.assetId
        PhotoStore.thumbnail(job.assetId, size: CGSize(width: 160, height: 160)) { [weak self] img in
            guard let self = self, self.currentId == id else { return }
            self.thumb.image = img
        }
    }

    private func jobSize(_ job: UploadJob) -> Int64 {
        if let asset = PhotoStore.asset(job.assetId) {
            let res = PHAssetResource.assetResources(for: asset)
            if let r = res.first, let size = r.value(forKey: "fileSize") as? Int64 {
                return size
            }
        }
        return 0
    }

    private func human(_ bytes: Int64) -> String {
        if bytes < 1024 { return "\(bytes) B" }
        if bytes < 1024 * 1024 { return String(format: "%.1f KB", Double(bytes) / 1024) }
        if bytes < 1024 * 1024 * 1024 { return String(format: "%.1f MB", Double(bytes) / 1048576) }
        return String(format: "%.2f GB", Double(bytes) / 1073741824)
    }
}