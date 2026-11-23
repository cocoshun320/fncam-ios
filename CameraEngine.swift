import Foundation
import AVFoundation
import UIKit

protocol CameraEngineDelegate: AnyObject {
    func engineStatus(_ text: String)
    func engineRecordingChanged(_ recording: Bool)
    func engineSaved(_ name: String)
}

final class CameraEngine: NSObject {
    static let shared = CameraEngine()

    let session = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "camera.session")
    private let photoOutput = AVCapturePhotoOutput()
    private let movieOutput = AVCaptureMovieFileOutput()
    private var videoInput: AVCaptureDeviceInput?
    private var audioInputAdded = false
    private(set) var currentDevice: AVCaptureDevice?
    private var configured = false

    private(set) var backLenses: [AVCaptureDevice] = []
    private(set) var position: AVCaptureDevice.Position = .back
    weak var delegate: CameraEngineDelegate?

    // 录制会话
    private var sessionActive = false
    private var sessionPrefix = "VID"
    private var segmentSec = 0
    private var maxTotalSec = 0
    private var sessionStart = Date()
    private var recordStart = Date()
    private var recordURL: URL?
    private var recordName = ""
    private var photoName = ""
    private var photoTime = Date()

    var isRecording: Bool { movieOutput.isRecording }
    var isSessionActive: Bool { sessionActive }

    private override init() {
        super.init()
        discoverLenses()
        NotificationCenter.default.addObserver(self, selector: #selector(wasInterrupted),
                                               name: .AVCaptureSessionWasInterrupted, object: session)
        NotificationCenter.default.addObserver(self, selector: #selector(interruptionEnded),
                                               name: .AVCaptureSessionInterruptionEnded, object: session)
    }

    private func discoverLenses() {
        let discovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInUltraWideCamera, .builtInWideAngleCamera, .builtInTelephotoCamera],
            mediaType: .video, position: .back)
        backLenses = discovery.devices
    }

    func lensLabel(_ device: AVCaptureDevice) -> String {
        switch device.deviceType {
        case .builtInUltraWideCamera: return "超广角"
        case .builtInTelephotoCamera: return "长焦"
        default: return "主摄"
        }
    }

    // MARK: - 启动与配置

    func start(completion: @escaping (Bool) -> Void) {
        AVCaptureDevice.requestAccess(for: .video) { videoOK in
            AVCaptureDevice.requestAccess(for: .audio) { _ in
                guard videoOK else {
                    DispatchQueue.main.async { completion(false) }
                    return
                }
                self.sessionQueue.async {
                    self.configureSession(device: self.defaultBackDevice())
                    if !self.session.isRunning { self.session.startRunning() }
                    DispatchQueue.main.async { completion(true) }
                }
            }
        }
    }

    func stop() {
        sessionQueue.async {
            if self.session.isRunning { self.session.stopRunning() }
        }
    }

    private func defaultBackDevice() -> AVCaptureDevice? {
        if let wide = backLenses.first(where: { $0.deviceType == .builtInWideAngleCamera }) {
            return wide
        }
        return backLenses.first ?? AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)
    }

    private func configureSession(device: AVCaptureDevice?) {
        session.beginConfiguration()
        session.sessionPreset = .high
        if let old = videoInput {
            session.removeInput(old)
            videoInput = nil
        }
        if let device = device, let input = try? AVCaptureDeviceInput(device: device) {
            if session.canAddInput(input) {
                session.addInput(input)
                videoInput = input
                currentDevice = device
                position = device.position
            }
        }
        if !audioInputAdded,
           let audio = AVCaptureDevice.default(for: .audio),
           let ainput = try? AVCaptureDeviceInput(device: audio),
           session.canAddInput(ainput) {
            session.addInput(ainput)
            audioInputAdded = true
        }
        if !configured {
            if session.canAddOutput(photoOutput) { session.addOutput(photoOutput) }
            if session.canAddOutput(movieOutput) { session.addOutput(movieOutput) }
            configured = true
        }
        session.commitConfiguration()
    }

    func switchToDevice(_ device: AVCaptureDevice) {
        sessionQueue.async {
            self.configureSession(device: device)
            DispatchQueue.main.async {
                self.delegate?.engineStatus("已切换：\(self.lensLabel(device))")
            }
        }
    }

    func switchPosition() {
        sessionQueue.async {
            let target: AVCaptureDevice.Position = self.position == .back ? .front : .back
            let device: AVCaptureDevice?
            if target == .back {
                device = self.defaultBackDevice()
            } else {
                device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front)
            }
            self.configureSession(device: device)
            DispatchQueue.main.async {
                self.delegate?.engineStatus(target == .front ? "前置摄像头" : "后置摄像头")
            }
        }
    }

    // MARK: - 变焦 / 手电

    var maxZoom: CGFloat {
        guard let d = currentDevice else { return 1 }
        return min(d.activeFormat.videoMaxZoomFactor, 60)
    }

    var zoom: CGFloat { currentDevice?.videoZoomFactor ?? 1 }

    func setZoom(_ factor: CGFloat) {
        guard let d = currentDevice else { return }
        let clamped = max(1, min(factor, maxZoom))
        do {
            try d.lockForConfiguration()
            d.videoZoomFactor = clamped
            d.unlockForConfiguration()
        } catch {}
    }

    func setTorch(_ on: Bool) {
        guard let d = currentDevice, d.hasTorch else { return }
        do {
            try d.lockForConfiguration()
            d.torchMode = on ? .on : .off
            d.unlockForConfiguration()
        } catch {}
    }

    // MARK: - 拍照

    func takePhoto() {
        sessionQueue.async {
            guard self.configured, !self.movieOutput.isRecording else {
                DispatchQueue.main.async { self.delegate?.engineStatus("录像中无法拍照") }
                return
            }
            let settings = AVCapturePhotoSettings()
            if let d = self.currentDevice, d.hasFlash {
                settings.flashMode = self.flashMode
            }
            self.photoName = Settings.stamp("IMG", ".jpg")
            self.photoTime = Date()
            self.photoOutput.capturePhoto(with: settings, delegate: self)
        }
    }

    var flashMode: AVCaptureDevice.FlashMode = .off

    // MARK: - 录像会话（分段 + 总时长）

    func startVideoSession(prefix: String) {
        sessionQueue.async {
            guard self.configured, !self.movieOutput.isRecording, !self.sessionActive else { return }
            self.sessionActive = true
            self.sessionPrefix = prefix
            self.segmentSec = Settings.shared.segmentSec
            self.maxTotalSec = Settings.shared.maxTotalMin * 60
            self.sessionStart = Date()
            self.beginSegment()
        }
    }

    func stopVideoSession() {
        sessionQueue.async {
            self.sessionActive = false
            if self.movieOutput.isRecording {
                self.movieOutput.stopRecording()
            }
        }
    }

    private func beginSegment() {
        if self.segmentSec > 0 {
            self.movieOutput.maxRecordedDuration = CMTime(seconds: Double(self.segmentSec), preferredTimescale: 1)
        } else {
            self.movieOutput.maxRecordedDuration = .invalid
        }
        self.recordName = Settings.stamp(self.sessionPrefix, ".mp4")
        self.recordStart = Date()
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(self.recordName)
        self.recordURL = url
        try? FileManager.default.removeItem(at: url)
        self.movieOutput.startRecording(to: url, recordingDelegate: self)
        DispatchQueue.main.async {
            self.delegate?.engineRecordingChanged(true)
            self.delegate?.engineStatus(self.segmentSec > 0
                ? "分段录制中（每段 \(self.segmentSec) 秒）" : "录制中")
        }
    }

    // MARK: - 中断

    @objc private func wasInterrupted() {
        sessionActive = false
        DispatchQueue.main.async {
            self.delegate?.engineRecordingChanged(false)
            self.delegate?.engineStatus("系统中断（来电/切后台），录制已停止")
        }
    }

    @objc private func interruptionEnded() {
        DispatchQueue.main.async {
            self.delegate?.engineStatus("中断结束，可继续拍摄")
        }
    }
}

// MARK: - 拍照回调

extension CameraEngine: AVCapturePhotoCaptureDelegate {
    func photoOutput(_ output: AVCapturePhotoOutput,
                     didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        if let error = error {
            DispatchQueue.main.async { self.delegate?.engineStatus("拍照失败：\(error.localizedDescription)") }
            return
        }
        guard let data = photo.fileDataRepresentation() else {
            DispatchQueue.main.async { self.delegate?.engineStatus("拍照失败：无数据") }
            return
        }
        let name = photoName
        let time = photoTime.timeIntervalSince1970
        PhotoStore.saveImage(data: data) { assetId in
            if let id = assetId {
                UploadQueue.shared.add(assetId: id, name: name, kind: "image", time: time, dur: 0)
                self.delegate?.engineSaved(name)
                self.delegate?.engineStatus("已拍照并存入相册：\(name)")
            } else {
                self.delegate?.engineStatus("保存到相册失败，请检查相册权限")
            }
        }
    }
}

// MARK: - 录像回调

extension CameraEngine: AVCaptureFileOutputRecordingDelegate {
    func fileOutput(_ output: AVCaptureFileOutput,
                    didFinishRecordingTo outputFileURL: URL,
                    from connections: [AVCaptureConnection], error: Error?) {
        let dur = Date().timeIntervalSince(recordStart)
        let name = recordName
        let time = recordStart.timeIntervalSince1970
        let exists = FileManager.default.fileExists(atPath: outputFileURL.path)
        let attrs = try? FileManager.default.attributesOfItem(atPath: outputFileURL.path)
        let size = (attrs?[.size] as? NSNumber)?.int64Value ?? 0

        if !exists || size == 0 {
            sessionActive = false
            DispatchQueue.main.async {
                self.delegate?.engineRecordingChanged(false)
                self.delegate?.engineStatus("录像失败：\(error?.localizedDescription ?? "文件无效")")
            }
            return
        }

        PhotoStore.saveVideo(url: outputFileURL) { assetId in
            try? FileManager.default.removeItem(at: outputFileURL)
            if let id = assetId {
                UploadQueue.shared.add(assetId: id, name: name, kind: "video", time: time, dur: dur)
                self.delegate?.engineSaved(name)
                self.delegate?.engineStatus("一段已存入相册：\(name)")
            } else {
                self.delegate?.engineStatus("保存到相册失败，请检查相册权限")
            }
            self.sessionQueue.async {
                let timeUp = self.maxTotalSec > 0
                    && Date().timeIntervalSince(self.sessionStart) >= Double(self.maxTotalSec)
                if self.sessionActive && !timeUp {
                    self.sessionQueue.asyncAfter(deadline: .now() + 0.4) {
                        if self.sessionActive { self.beginSegment() }
                    }
                } else {
                    self.sessionActive = false
                    DispatchQueue.main.async {
                        self.delegate?.engineRecordingChanged(false)
                        if timeUp { self.delegate?.engineStatus("录制已到时自动停止") }
                    }
                }
            }
        }
    }
}