import UIKit
import AVFoundation

final class CameraViewController: UIViewController {
    private let engine = CameraEngine.shared
    private var previewLayer: AVCaptureVideoPreviewLayer!

    private let topStack = UIStackView()
    private let lensStack = UIStackView()
    private let statusLabel = UILabel()
    private let zoomSlider = UISlider()
    private let zoomLabel = UILabel()
    private let photoButton = UIButton(type: .system)
    private let videoButton = UIButton(type: .system)
    private var queueButton: UIButton!
    private var flashButton: UIButton!
    private var torchButton: UIButton!
    private var torchOn = false
    private var badgeTimer: Timer?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        engine.delegate = self

        previewLayer = AVCaptureVideoPreviewLayer(session: engine.session)
        previewLayer.videoGravity = .resizeAspectFill
        view.layer.addSublayer(previewLayer)

        let pinch = UIPinchGestureRecognizer(target: self, action: #selector(onPinch(_:)))
        view.addGestureRecognizer(pinch)

        setupControls()
        NotificationCenter.default.addObserver(self, selector: #selector(refreshBadge),
                                               name: UploadQueue.changedNotification, object: nil)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        engine.start { [weak self] ok in
            guard let self = self else { return }
            if ok {
                self.rebuildLensRow()
                self.refreshZoom()
                self.statusLabel.text = "相机就绪"
            } else {
                self.statusLabel.text = "没有相机权限，请到系统设置开启"
            }
        }
        refreshBadge()
        badgeTimer = Timer.scheduledTimer(withTimeInterval: 2.5, repeats: true) { [weak self] _ in
            self?.refreshBadge()
        }
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        badgeTimer?.invalidate()
        badgeTimer = nil
        engine.stop()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer.frame = view.bounds
        let safe = view.safeAreaInsets
        let w = view.bounds.width
        topStack.frame = CGRect(x: 12, y: safe.top + 8, width: w - 24, height: 36)
        lensStack.frame = CGRect(x: 12, y: topStack.frame.maxY + 8, width: w - 24, height: 34)
        statusLabel.frame = CGRect(x: 16, y: lensStack.frame.maxY + 6, width: w - 32, height: 34)

        let bottomH: CGFloat = 190
        let bottomY = view.bounds.height - safe.bottom - bottomH
        zoomSlider.frame = CGRect(x: 16, y: bottomY, width: w - 110, height: 30)
        zoomLabel.frame = CGRect(x: w - 88, y: bottomY, width: 76, height: 30)
        let btnSize: CGFloat = 78
        let cy = bottomY + 50
        photoButton.frame = CGRect(x: w / 2 - btnSize - 20, y: cy, width: btnSize, height: btnSize)
        videoButton.frame = CGRect(x: w / 2 + 20, y: cy, width: btnSize, height: btnSize)
        photoButton.layer.cornerRadius = btnSize / 2
        videoButton.layer.cornerRadius = btnSize / 2
    }

    private func setupControls() {
        topStack.axis = .horizontal
        topStack.distribution = .fillEqually
        topStack.spacing = 6
        view.addSubview(topStack)

        queueButton = chip("队列·0") { [weak self] in
            self?.navigationController?.pushViewController(QueueViewController(), animated: true)
        }
        let settingsBtn = chip("设置") { [weak self] in
            self?.navigationController?.pushViewController(SettingsViewController(), animated: true)
        }
        flashButton = chip("闪光关") { [weak self] in self?.cycleFlash() }
        torchButton = chip("手电") { [weak self] in self?.toggleTorch() }
        topStack.addArrangedSubview(queueButton)
        topStack.addArrangedSubview(settingsBtn)
        topStack.addArrangedSubview(flashButton)
        topStack.addArrangedSubview(torchButton)

        lensStack.axis = .horizontal
        lensStack.spacing = 6
        view.addSubview(lensStack)

        statusLabel.textColor = .white
        statusLabel.font = .systemFont(ofSize: 12)
        statusLabel.numberOfLines = 2
        statusLabel.text = "正在启动相机…"
        view.addSubview(statusLabel)

        zoomSlider.minimumValue = 1
        zoomSlider.maximumValue = 8
        zoomSlider.addTarget(self, action: #selector(onZoomSlider), for: .valueChanged)
        view.addSubview(zoomSlider)
        zoomLabel.textColor = .white
        zoomLabel.font = .systemFont(ofSize: 11)
        zoomLabel.textAlignment = .right
        zoomLabel.text = "1.0x"
        view.addSubview(zoomLabel)

        styleRound(photoButton, title: "拍照", color: .white)
        photoButton.addTarget(self, action: #selector(onPhoto), for: .touchUpInside)
        view.addSubview(photoButton)

        styleRound(videoButton, title: "录像", color: .white)
        videoButton.addTarget(self, action: #selector(onVideo), for: .touchUpInside)
        view.addSubview(videoButton)
    }

    private func chip(_ title: String, action: @escaping () -> Void) -> UIButton {
        let b = UIButton(type: .system)
        b.setTitle(title, for: .normal)
        b.setTitleColor(.white, for: .normal)
        b.titleLabel?.font = .systemFont(ofSize: 13)
        b.backgroundColor = UIColor(white: 0, alpha: 0.45)
        b.layer.cornerRadius = 10
        b.layer.borderWidth = 1
        b.layer.borderColor = UIColor(white: 1, alpha: 0.3).cgColor
        b.addAction(UIAction { _ in action() }, for: .touchUpInside)
        return b
    }

    private func styleRound(_ b: UIButton, title: String, color: UIColor) {
        b.setTitle(title, for: .normal)
        b.setTitleColor(color, for: .normal)
        b.titleLabel?.font = .systemFont(ofSize: 16, weight: .semibold)
        b.backgroundColor = UIColor(white: 1, alpha: 0.15)
        b.layer.borderWidth = 3
        b.layer.borderColor = color.cgColor
    }

    private func rebuildLensRow() {
        lensStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        let flipTitle = engine.position == .back ? "切前置" : "切后置"
        let flip = chip(flipTitle) { [weak self] in
            self?.engine.switchPosition()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                self?.rebuildLensRow()
                self?.refreshZoom()
            }
        }
        lensStack.addArrangedSubview(flip)
        if engine.position == .back {
            for device in engine.backLenses {
                let label = engine.lensLabel(device)
                let b = chip(label) { [weak self] in
                    self?.engine.switchToDevice(device)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { self?.refreshZoom() }
                }
                if device == engine.currentDevice {
                    b.backgroundColor = UIColor(red: 0.16, green: 0.36, blue: 0.54, alpha: 0.9)
                }
                lensStack.addArrangedSubview(b)
            }
        }
    }

    private func refreshZoom() {
        zoomSlider.maximumValue = Float(max(1.1, engine.maxZoom))
        zoomSlider.value = Float(engine.zoom)
        zoomLabel.text = String(format: "%.1fx / %.0fx", engine.zoom, engine.maxZoom)
    }

    @objc private func onZoomSlider() {
        engine.setZoom(CGFloat(zoomSlider.value))
        zoomLabel.text = String(format: "%.1fx / %.0fx", engine.zoom, engine.maxZoom)
    }

    @objc private func onPinch(_ g: UIPinchGestureRecognizer) {
        if g.state == .changed {
            engine.setZoom(engine.zoom * g.scale)
            g.scale = 1
            zoomSlider.value = Float(engine.zoom)
            zoomLabel.text = String(format: "%.1fx / %.0fx", engine.zoom, engine.maxZoom)
        }
    }

    private func cycleFlash() {
        switch engine.flashMode {
        case .off:
            engine.flashMode = .on
            flashButton.setTitle("闪光开", for: .normal)
        case .on:
            engine.flashMode = .auto
            flashButton.setTitle("闪光自动", for: .normal)
        default:
            engine.flashMode = .off
            flashButton.setTitle("闪光关", for: .normal)
        }
    }

    private func toggleTorch() {
        torchOn.toggle()
        engine.setTorch(torchOn)
        torchButton.setTitle(torchOn ? "手电开" : "手电", for: .normal)
    }

    @objc private func onPhoto() {
        if engine.isRecording {
            statusLabel.text = "录像中无法拍照，请先停止"
            return
        }
        engine.takePhoto()
    }

    @objc private func onVideo() {
        if engine.isRecording || engine.isSessionActive {
            engine.stopVideoSession()
            setRecordingUI(false)
            statusLabel.text = "正在保存录像…"
        } else {
            engine.startVideoSession(prefix: "VID")
        }
    }

    private func setRecordingUI(_ recording: Bool) {
        videoButton.setTitle(recording ? "停止" : "录像", for: .normal)
        videoButton.setTitleColor(recording ? .red : .white, for: .normal)
        videoButton.layer.borderColor = (recording ? UIColor.red : UIColor.white).cgColor
        videoButton.backgroundColor = recording
            ? UIColor(red: 1, green: 0, blue: 0, alpha: 0.3)
            : UIColor(white: 1, alpha: 0.15)
    }

    @objc private func refreshBadge() {
        queueButton.setTitle("队列·\(UploadQueue.shared.count)", for: .normal)
    }
}

extension CameraViewController: CameraEngineDelegate {
    func engineStatus(_ text: String) {
        DispatchQueue.main.async { self.statusLabel.text = text }
    }
    func engineRecordingChanged(_ recording: Bool) {
        DispatchQueue.main.async { self.setRecordingUI(recording) }
    }
    func engineSaved(_ name: String) {
        DispatchQueue.main.async { self.refreshBadge() }
    }
}