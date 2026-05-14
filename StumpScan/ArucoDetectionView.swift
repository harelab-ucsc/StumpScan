import ARKit
import RealityKit
import SwiftUI
import UIKit

struct ArucoDetectionView: UIViewRepresentable {
    func makeUIView(context: Context) -> ArucoARView {
        ArucoARView(detector: OpenCVArucoTagDetector())
    }

    func updateUIView(_ uiView: ArucoARView, context: Context) {}
}

// MARK: - ArucoARView

final class ArucoARView: UIView, ARSessionDelegate {

    // MARK: Subviews
    private let arView = ARView(frame: .zero)
    private let overlayLayer = CALayer()
    private let statusLabel = UILabel()
    private let controlPanel = DetectionControlPanel()

    // MARK: Detection
    private let detector: any ArucoTagDetector
    private let detectionQueue = DispatchQueue(label: "hare.derick.StumpScan.detection", qos: .userInitiated)
    private let minimumDetectionInterval: TimeInterval = 0.1

    private var isDetecting = false
    private var lastDetectionTime: TimeInterval = 0
    private var latestDetections: [ArucoTag] = []
    private var latestFrame: ARFrame?

    private var currentDictionary: TagDictionary = .aruco4x4

    // MARK: Init

    init(detector: any ArucoTagDetector) {
        self.detector = detector
        super.init(frame: .zero)
        detector.validateConfiguration()
        setUpView()
        updateStatusLabel(text: currentDictionary.mode.promptText)
        startSession()
    }

    required init?(coder: NSCoder) { fatalError() }

    // MARK: Layout

    override func layoutSubviews() {
        super.layoutSubviews()
        arView.frame = bounds
        overlayLayer.frame = bounds
        layoutStatusLabel()
        layoutControlPanel()

        if let latestFrame {
            drawDetections(latestDetections, for: latestFrame)
        }
    }

    private func layoutStatusLabel() {
        let hPad: CGFloat = 16
        let top = safeAreaInsets.top + 12
        let maxW = max(0, bounds.width - hPad * 2)
        let fit = statusLabel.sizeThatFits(CGSize(width: maxW - 24, height: .greatestFiniteMagnitude))
        statusLabel.frame = CGRect(x: hPad, y: top, width: maxW, height: max(36, fit.height + 16))
    }

    private func layoutControlPanel() {
        let panelHeight: CGFloat = 120
        let bottom = bounds.height - safeAreaInsets.bottom
        controlPanel.frame = CGRect(x: 0, y: bottom - panelHeight, width: bounds.width, height: panelHeight)
    }

    // MARK: Setup

    private func setUpView() {
        backgroundColor = .black

        arView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        arView.automaticallyConfigureSession = false
        addSubview(arView)

        overlayLayer.masksToBounds = true
        layer.addSublayer(overlayLayer)

        statusLabel.textColor = .white
        statusLabel.backgroundColor = UIColor.black.withAlphaComponent(0.65)
        statusLabel.font = .systemFont(ofSize: 14, weight: .semibold)
        statusLabel.numberOfLines = 0
        statusLabel.textAlignment = .center
        statusLabel.layer.cornerRadius = 8
        statusLabel.layer.masksToBounds = true
        addSubview(statusLabel)

        controlPanel.onChange = { [weak self] dictionary in
            guard let self else { return }
            self.currentDictionary = dictionary
            self.latestDetections = []
            self.overlayLayer.sublayers?.forEach { $0.removeFromSuperlayer() }
            self.updateStatusLabel(text: dictionary.mode.promptText)
        }
        addSubview(controlPanel)
    }

    private func startSession() {
        guard ARWorldTrackingConfiguration.isSupported else { return }
        let config = ARWorldTrackingConfiguration()
        config.planeDetection = []
        arView.session.delegate = self
        arView.session.run(config, options: [.resetTracking, .removeExistingAnchors])
    }

    // MARK: ARSessionDelegate

    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        guard frame.timestamp - lastDetectionTime >= minimumDetectionInterval, !isDetecting else { return }
        lastDetectionTime = frame.timestamp
        isDetecting = true

        let pixelBuffer = frame.capturedImage
        let capturedFrame = frame
        let dictionary = currentDictionary

        detectionQueue.async { [weak self] in
            guard let self else { return }
            let detections = self.detector.detect(in: pixelBuffer, dictionary: dictionary)
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.isDetecting = false
                self.latestFrame = capturedFrame
                self.latestDetections = detections
                self.updateStatusLabel(text: dictionary.mode.detectionText(count: detections.count))
                self.drawDetections(detections, for: capturedFrame)
            }
        }
    }

    // MARK: Status label

    private func updateStatusLabel(text: String) {
        statusLabel.text = text
        setNeedsLayout()
    }

    // MARK: Overlay drawing

    private func drawDetections(_ detections: [ArucoTag], for frame: ARFrame) {
        overlayLayer.sublayers?.forEach { $0.removeFromSuperlayer() }
        guard !bounds.isEmpty else { return }

        let orientation = window?.windowScene?.effectiveGeometry.interfaceOrientation ?? .portrait
        let transform = frame.displayTransform(for: orientation, viewportSize: bounds.size)

        for detection in detections {
            let viewCorners = detection.corners.map {
                ArucoOverlayMapper.viewPoint(for: $0, imageSize: detection.imageSize,
                                             viewportSize: bounds.size, transform: transform)
            }
            guard let first = viewCorners.first else { continue }

            let path = UIBezierPath()
            path.move(to: first)
            viewCorners.dropFirst().forEach { path.addLine(to: $0) }
            path.close()

            let shape = CAShapeLayer()
            shape.path = path.cgPath
            shape.strokeColor = UIColor.systemGreen.cgColor
            shape.fillColor = UIColor.clear.cgColor
            shape.lineWidth = 4
            shape.lineJoin = .round
            overlayLayer.addSublayer(shape)

            if let top = viewCorners.min(by: { $0.y < $1.y }) {
                let text = CATextLayer()
                text.string = "ID \(detection.id)"
                text.fontSize = 14
                text.foregroundColor = UIColor.black.cgColor
                text.backgroundColor = UIColor.systemGreen.cgColor
                text.alignmentMode = .center
                text.contentsScale = window?.windowScene?.screen.scale ?? 1
                text.cornerRadius = 4
                text.masksToBounds = true
                text.frame = ArucoOverlayMapper.labelFrame(anchoredAt: top, viewportSize: bounds.size)
                overlayLayer.addSublayer(text)
            }
        }
    }
}

// MARK: - DetectionControlPanel

private final class DetectionControlPanel: UIView {

    var onChange: ((TagDictionary) -> Void)?

    private let modeControl = UISegmentedControl(items: DetectionMode.allCases.map(\.displayName))
    private let slider = UISlider()
    private let tickStack = UIStackView()
    private let sliderRow = UIView()

    private var currentMode: DetectionMode = .aruco
    private var sliderIndex: Int = 0

    override init(frame: CGRect) {
        super.init(frame: frame)
        setUpViews()
    }

    required init?(coder: NSCoder) { fatalError() }

    // MARK: Setup

    private func setUpViews() {
        let blur = UIVisualEffectView(effect: UIBlurEffect(style: .systemThinMaterialDark))
        blur.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        addSubview(blur)

        // Mode toggle
        modeControl.selectedSegmentIndex = 0
        modeControl.selectedSegmentTintColor = .systemGreen
        modeControl.setTitleTextAttributes([.foregroundColor: UIColor.white], for: .normal)
        modeControl.setTitleTextAttributes([.foregroundColor: UIColor.black], for: .selected)
        modeControl.addTarget(self, action: #selector(modeChanged), for: .valueChanged)
        addSubview(modeControl)

        // Slider
        slider.minimumValue = 0
        slider.maximumValue = Float(currentMode.dictionaries.count - 1)
        slider.value = 0
        slider.minimumTrackTintColor = .systemGreen
        slider.addTarget(self, action: #selector(sliderChanged), for: .valueChanged)
        slider.addTarget(self, action: #selector(sliderReleased), for: [.touchUpInside, .touchUpOutside])
        sliderRow.addSubview(slider)
        addSubview(sliderRow)

        // Tick labels
        tickStack.axis = .horizontal
        tickStack.distribution = .equalSpacing
        tickStack.alignment = .center
        rebuildTicks()
        addSubview(tickStack)
    }

    private func rebuildTicks() {
        tickStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        for dict in currentMode.dictionaries {
            let label = UILabel()
            label.text = dict.tickLabel
            label.font = .systemFont(ofSize: 11, weight: .medium)
            label.textColor = .secondaryLabel
            label.textAlignment = .center
            tickStack.addArrangedSubview(label)
        }
        updateTickHighlight()
    }

    private func updateTickHighlight() {
        for (i, view) in tickStack.arrangedSubviews.enumerated() {
            guard let label = view as? UILabel else { continue }
            label.textColor = i == sliderIndex ? .systemGreen : UIColor.white.withAlphaComponent(0.5)
            label.font = i == sliderIndex
                ? .systemFont(ofSize: 11, weight: .bold)
                : .systemFont(ofSize: 11, weight: .medium)
        }
    }

    // MARK: Layout

    override func layoutSubviews() {
        super.layoutSubviews()
        let hPad: CGFloat = 20
        let w = bounds.width - hPad * 2
        let segH: CGFloat = 34
        let sliderH: CGFloat = 28
        let tickH: CGFloat = 18
        let spacing: CGFloat = 10

        let totalH = segH + spacing + sliderH + tickH
        let startY = (bounds.height - totalH) / 2

        modeControl.frame = CGRect(x: hPad, y: startY, width: w, height: segH)

        let sliderY = startY + segH + spacing
        sliderRow.frame = CGRect(x: hPad, y: sliderY, width: w, height: sliderH)
        slider.frame = sliderRow.bounds

        tickStack.frame = CGRect(x: hPad, y: sliderY + sliderH, width: w, height: tickH)
    }

    // MARK: Actions

    @objc private func modeChanged() {
        let newMode = DetectionMode.allCases[modeControl.selectedSegmentIndex]
        guard newMode != currentMode else { return }
        currentMode = newMode
        slider.maximumValue = Float(currentMode.dictionaries.count - 1)
        // preserve slider position across modes
        slider.value = Float(sliderIndex)
        rebuildTicks()
        emitChange()
    }

    @objc private func sliderChanged() {
        // live snap while dragging
        let snapped = Int(slider.value.rounded())
        if snapped != sliderIndex {
            sliderIndex = snapped
            updateTickHighlight()
        }
    }

    @objc private func sliderReleased() {
        sliderIndex = Int(slider.value.rounded())
        slider.setValue(Float(sliderIndex), animated: true)
        updateTickHighlight()
        emitChange()
    }

    private func emitChange() {
        let dict = currentMode.dictionaries[sliderIndex]
        onChange?(dict)
    }
}
