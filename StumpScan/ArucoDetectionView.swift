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
    private let minimapView = MinimapView(frame: .zero)
    private let coachingOverlay = ARCoachingOverlayView()

    // MARK: Detection
    private let detector: any ArucoTagDetector
    private let detectionQueue = DispatchQueue(label: "hare.derick.StumpScan.detection", qos: .userInitiated)
    private let minimumDetectionInterval: TimeInterval = 0.1

    private var isDetecting = false
    private var lastDetectionTime: TimeInterval = 0
    private var latestDetections: [ArucoTag] = []
    private var latestFrame: ARFrame?
    private var currentDictionary: TagDictionary = .aruco4x4

    // MARK: Persistence
    private let tagStore = TagPositionStore()

    // MARK: Init

    init(detector: any ArucoTagDetector) {
        self.detector = detector
        super.init(frame: .zero)
        detector.validateConfiguration()
        setUpView()
        updateStatusLabel(text: currentDictionary.mode.promptText)
        startSession()
        setUpCoachingOverlay()
    }

    required init?(coder: NSCoder) { fatalError() }

    // MARK: Layout

    override func layoutSubviews() {
        super.layoutSubviews()
        arView.frame = bounds
        overlayLayer.frame = bounds
        layoutStatusLabel()
        layoutControlPanel()
        layoutMinimap()

        if let latestFrame {
            drawOverlays(latestDetections, for: latestFrame)
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
        // Extend all the way to the physical bottom; content inside stays above safe area
        let contentHeight: CGFloat = 120
        let panelHeight = contentHeight + safeAreaInsets.bottom
        controlPanel.frame = CGRect(x: 0, y: bounds.height - panelHeight,
                                    width: bounds.width, height: panelHeight)
        controlPanel.contentHeight = contentHeight
    }

    private func layoutMinimap() {
        let size: CGFloat = 160
        let x: CGFloat = 12
        let y: CGFloat = bounds.height - safeAreaInsets.bottom - 120 - 12 - size
        minimapView.frame = CGRect(x: x, y: max(safeAreaInsets.top + 8, y), width: size, height: size)
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
        controlPanel.onReset = { [weak self] in
            self?.resetSavedPoses()
        }
        addSubview(controlPanel)
        addSubview(minimapView)
    }

    private func startSession() {
        guard ARWorldTrackingConfiguration.isSupported else { return }
        let config = ARWorldTrackingConfiguration()
        config.planeDetection = [.horizontal, .vertical]
        if ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh) {
            config.sceneReconstruction = .mesh
        }
        arView.session.delegate = self
        arView.session.run(config, options: [.resetTracking, .removeExistingAnchors])
    }

    private func setUpCoachingOverlay() {
        coachingOverlay.session = arView.session
        coachingOverlay.delegate = self
        coachingOverlay.goal = .anyPlane
        coachingOverlay.activatesAutomatically = true
        coachingOverlay.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        coachingOverlay.frame = bounds
        addSubview(coachingOverlay)
    }

    // MARK: ARSessionDelegate

    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        guard frame.timestamp - lastDetectionTime >= minimumDetectionInterval, !isDetecting else { return }
        lastDetectionTime = frame.timestamp
        isDetecting = true

        // Copy only the pixel buffer — holding a full ARFrame across threads
        // causes ARKit to throttle/stop frame delivery once too many are retained.
        let pixelBuffer = frame.capturedImage
        let capturedFrame = frame   // retained only on main thread; released after drawOverlays
        let dictionary = currentDictionary

        detectionQueue.async { [weak self] in
            guard let self else { return }
            let detections = self.detector.detect(in: pixelBuffer, dictionary: dictionary)
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.isDetecting = false
                self.latestDetections = detections
                self.latestFrame = capturedFrame
                self.updateTagPositions(detections, frame: capturedFrame)
                self.updateStatusLabel(text: dictionary.mode.detectionText(count: detections.count))
                self.drawOverlays(detections, for: capturedFrame)
                // capturedFrame released here; only one frame held at a time
            }
        }
    }

    // MARK: World position

    private func updateTagPositions(_ detections: [ArucoTag], frame: ARFrame) {
        let orientation = window?.windowScene?.effectiveGeometry.interfaceOrientation ?? .portrait
        let displayTx = frame.displayTransform(for: orientation, viewportSize: bounds.size)

        for tag in detections {
            // Tag center in view space
            let sum = tag.corners.reduce(CGPoint.zero) { CGPoint(x: $0.x + $1.x, y: $0.y + $1.y) }
            let imageCenter = CGPoint(x: sum.x / 4, y: sum.y / 4)
            let normalizedVP = CGPoint(x: imageCenter.x / tag.imageSize.width,
                                       y: imageCenter.y / tag.imageSize.height).applying(displayTx)
            let centerViewPt = CGPoint(x: normalizedVP.x * bounds.width,
                                       y: normalizedVP.y * bounds.height)

            guard let worldCenter = worldPosition(forViewPoint: centerViewPt, frame: frame) else { continue }

            // Project each image-space corner onto the tag's plane in 3D.
            // Plane: passes through worldCenter, normal faces the camera.
            let camPos = SIMD3<Float>(frame.camera.transform.columns.3.x,
                                      frame.camera.transform.columns.3.y,
                                      frame.camera.transform.columns.3.z)
            let planeNormal = simd_normalize(camPos - worldCenter)

            let worldCorners: [SIMD3<Float>] = tag.corners.map { corner in
                let normImg = CGPoint(x: corner.x / tag.imageSize.width,
                                     y: corner.y / tag.imageSize.height).applying(displayTx)
                let viewPt = CGPoint(x: normImg.x * bounds.width, y: normImg.y * bounds.height)
                let rayDir = cameraRayDirection(at: viewPt, frame: frame)

                // Ray–plane intersection
                let denom = simd_dot(planeNormal, rayDir)
                guard abs(denom) > 1e-6 else { return worldCenter }
                let t = simd_dot(planeNormal, worldCenter - camPos) / denom
                guard t > 0 else { return worldCenter }
                return camPos + rayDir * t
            }

            tagStore.update(id: tag.id, worldPosition: worldCenter, worldCorners: worldCorners)
        }
    }

    private func worldPosition(forViewPoint viewPoint: CGPoint, frame: ARFrame) -> SIMD3<Float>? {
        // Prefer raycast against detected geometry
        let results = arView.raycast(from: viewPoint, allowing: .estimatedPlane, alignment: .any)
        if let hit = results.first {
            let col = hit.worldTransform.columns.3
            return SIMD3<Float>(col.x, col.y, col.z)
        }
        // Fallback: unproject via camera intrinsics at 1 m
        return cameraRayPoint(at: viewPoint, frame: frame, depth: 1.0)
    }

    // Normalised world-space ray direction through a viewport point
    private func cameraRayDirection(at viewPoint: CGPoint, frame: ARFrame) -> SIMD3<Float> {
        let camera = frame.camera
        let K = camera.intrinsics
        let res = camera.imageResolution
        let orientation = window?.windowScene?.effectiveGeometry.interfaceOrientation ?? .portrait
        let invTx = frame.displayTransform(for: orientation, viewportSize: bounds.size).inverted()

        let normImg = CGPoint(x: viewPoint.x / bounds.width,
                              y: viewPoint.y / bounds.height).applying(invTx)
        let px = Float(normImg.x) * Float(res.width)
        let py = Float(normImg.y) * Float(res.height)

        let dirCamera = simd_normalize(SIMD3<Float>(
            (px - K[2][0]) / K[0][0],
            -(py - K[2][1]) / K[1][1],
            -1
        ))
        let t = camera.transform
        let R = simd_float3x3(columns: (
            SIMD3<Float>(t.columns.0.x, t.columns.0.y, t.columns.0.z),
            SIMD3<Float>(t.columns.1.x, t.columns.1.y, t.columns.1.z),
            SIMD3<Float>(t.columns.2.x, t.columns.2.y, t.columns.2.z)
        ))
        return simd_normalize(R * dirCamera)
    }

    private func cameraRayPoint(at viewPoint: CGPoint, frame: ARFrame, depth: Float) -> SIMD3<Float> {
        let origin = SIMD3<Float>(frame.camera.transform.columns.3.x,
                                   frame.camera.transform.columns.3.y,
                                   frame.camera.transform.columns.3.z)
        return origin + cameraRayDirection(at: viewPoint, frame: frame) * depth
    }

    // MARK: Overlay drawing

    private func drawOverlays(_ detections: [ArucoTag], for frame: ARFrame) {
        overlayLayer.sublayers?.forEach { $0.removeFromSuperlayer() }
        guard !bounds.isEmpty else { return }

        let orientation = window?.windowScene?.effectiveGeometry.interfaceOrientation ?? .portrait
        let displayTx = frame.displayTransform(for: orientation, viewportSize: bounds.size)
        let activeIDs = Set(detections.map(\.id))

        // Minimap
        minimapView.update(cameraTransform: frame.camera.transform,
                           anchors: tagStore.anchors,
                           activeIDs: activeIDs)

        // Pass 1 – persistent markers for known tags not currently visible
        for (id, anchor) in tagStore.anchors where !activeIDs.contains(id) {
            drawPersistentMarker(anchor: anchor, frame: frame)
        }

        // Pass 2 – solid green borders for currently visible tags
        for detection in detections {
            let viewCorners = detection.corners.map {
                ArucoOverlayMapper.viewPoint(for: $0, imageSize: detection.imageSize,
                                             viewportSize: bounds.size, transform: displayTx)
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
                addLabel("ID \(detection.id)", at: top, color: .systemGreen)
            }
        }
    }

    // Projects a world-space point to screen coords; returns nil if behind the camera or off-screen.
    private func project(_ worldPos: SIMD3<Float>, frame: ARFrame) -> CGPoint? {
        let camera = frame.camera
        let camPos = SIMD3<Float>(camera.transform.columns.3.x,
                                  camera.transform.columns.3.y,
                                  camera.transform.columns.3.z)
        let forward = SIMD3<Float>(-camera.transform.columns.2.x,
                                   -camera.transform.columns.2.y,
                                   -camera.transform.columns.2.z)
        guard simd_dot(simd_normalize(worldPos - camPos), forward) > 0 else { return nil }

        let orientation = window?.windowScene?.effectiveGeometry.interfaceOrientation ?? .portrait
        let pt = camera.projectPoint(worldPos, orientation: orientation, viewportSize: bounds.size)
        let margin: CGFloat = -40
        guard bounds.insetBy(dx: margin, dy: margin).contains(pt) else { return nil }
        return pt
    }

    private func drawPersistentMarker(anchor: TagAnchor, frame: ARFrame) {
        let orientation = window?.windowScene?.effectiveGeometry.interfaceOrientation ?? .portrait
        let camera = frame.camera
        let camPos = SIMD3<Float>(camera.transform.columns.3.x,
                                   camera.transform.columns.3.y,
                                   camera.transform.columns.3.z)
        let forward = SIMD3<Float>(-camera.transform.columns.2.x,
                                    -camera.transform.columns.2.y,
                                    -camera.transform.columns.2.z)

        // Project all 4 stored 3D corners; bail if any is behind the camera or off-screen
        let margin: CGFloat = -60
        var screenCorners: [CGPoint] = []
        for corner in anchor.worldCorners {
            guard simd_dot(simd_normalize(corner - camPos), forward) > 0 else { return }
            let pt = camera.projectPoint(corner, orientation: orientation, viewportSize: bounds.size)
            guard bounds.insetBy(dx: margin, dy: margin).contains(pt) else { return }
            screenCorners.append(pt)
        }
        guard screenCorners.count == 4 else { return }

        let alpha = min(1.0, CGFloat(anchor.observationCount) / 5.0) * 0.85 + 0.15
        let color = UIColor.systemBlue.withAlphaComponent(alpha)

        let path = UIBezierPath()
        path.move(to: screenCorners[0])
        screenCorners.dropFirst().forEach { path.addLine(to: $0) }
        path.close()

        let shape = CAShapeLayer()
        shape.path = path.cgPath
        shape.strokeColor = color.cgColor
        shape.fillColor = UIColor.systemBlue.withAlphaComponent(alpha * 0.08).cgColor
        shape.lineWidth = 4
        shape.lineJoin = .round
        shape.lineDashPattern = [8, 5]
        overlayLayer.addSublayer(shape)

        if let top = screenCorners.min(by: { $0.y < $1.y }) {
            addLabel("ID \(anchor.id)", at: top, color: .systemBlue)
        }
    }

    private func addLabel(_ text: String, at point: CGPoint, color: UIColor) {
        let layer = CATextLayer()
        layer.string = text
        layer.fontSize = 14
        layer.foregroundColor = UIColor.black.cgColor
        layer.backgroundColor = color.cgColor
        layer.alignmentMode = .center
        layer.contentsScale = window?.windowScene?.screen.scale ?? 1
        layer.cornerRadius = 4
        layer.masksToBounds = true
        layer.frame = ArucoOverlayMapper.labelFrame(anchoredAt: point, viewportSize: bounds.size)
        overlayLayer.addSublayer(layer)
    }

    // MARK: Actions

    private func resetSavedPoses() {
        tagStore.reset()
        latestDetections = []
        overlayLayer.sublayers?.forEach { $0.removeFromSuperlayer() }
        minimapView.update(cameraTransform: matrix_identity_float4x4, anchors: [:], activeIDs: [])
    }

    // MARK: Status label

    private func updateStatusLabel(text: String) {
        statusLabel.text = text
        setNeedsLayout()
    }
}

// MARK: - ARCoachingOverlayViewDelegate

extension ArucoARView: ARCoachingOverlayViewDelegate {
    func coachingOverlayViewWillActivate(_ coachingOverlayView: ARCoachingOverlayView) {
        controlPanel.alpha = 0
        minimapView.alpha = 0
    }

    func coachingOverlayViewDidDeactivate(_ coachingOverlayView: ARCoachingOverlayView) {
        UIView.animate(withDuration: 0.3) {
            self.controlPanel.alpha = 1
            self.minimapView.alpha = 1
        }
    }
}

// MARK: - DetectionControlPanel

private final class DetectionControlPanel: UIView {

    var onChange: ((TagDictionary) -> Void)?
    var onReset: (() -> Void)?

    // Set by ArucoARView so content stays above the safe area bottom inset
    var contentHeight: CGFloat = 120 { didSet { setNeedsLayout() } }

    private let modeControl = UISegmentedControl(items: DetectionMode.allCases.map(\.displayName))
    private let resetButton = UIButton(type: .system)
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

    private func setUpViews() {
        let blur = UIVisualEffectView(effect: UIBlurEffect(style: .systemThinMaterialDark))
        blur.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        addSubview(blur)

        modeControl.selectedSegmentIndex = 0
        modeControl.selectedSegmentTintColor = .systemGreen
        modeControl.setTitleTextAttributes([.foregroundColor: UIColor.white], for: .normal)
        modeControl.setTitleTextAttributes([.foregroundColor: UIColor.black], for: .selected)
        modeControl.addTarget(self, action: #selector(modeChanged), for: .valueChanged)
        addSubview(modeControl)

        resetButton.setImage(UIImage(systemName: "arrow.counterclockwise"), for: .normal)
        resetButton.tintColor = UIColor.white.withAlphaComponent(0.6)
        resetButton.addTarget(self, action: #selector(resetTapped), for: .touchUpInside)
        addSubview(resetButton)

        slider.minimumValue = 0
        slider.maximumValue = Float(currentMode.dictionaries.count - 1)
        slider.value = 0
        slider.minimumTrackTintColor = .systemGreen
        slider.addTarget(self, action: #selector(sliderChanged), for: .valueChanged)
        slider.addTarget(self, action: #selector(sliderReleased), for: [.touchUpInside, .touchUpOutside])
        sliderRow.addSubview(slider)
        addSubview(sliderRow)

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

    override func layoutSubviews() {
        super.layoutSubviews()
        let hPad: CGFloat = 20
        let resetW: CGFloat = 36
        let segH: CGFloat = 34
        let sliderH: CGFloat = 28
        let tickH: CGFloat = 18
        let spacing: CGFloat = 10
        let totalH = segH + spacing + sliderH + tickH
        let startY = (contentHeight - totalH) / 2

        // Segmented control takes most of the width; reset icon sits to its right
        let segW = bounds.width - hPad * 2 - resetW - 8
        modeControl.frame = CGRect(x: hPad, y: startY, width: segW, height: segH)
        resetButton.frame = CGRect(x: hPad + segW + 8, y: startY, width: resetW, height: segH)

        let sliderY = startY + segH + spacing
        let w = bounds.width - hPad * 2
        sliderRow.frame = CGRect(x: hPad, y: sliderY, width: w, height: sliderH)
        slider.frame = sliderRow.bounds
        tickStack.frame = CGRect(x: hPad, y: sliderY + sliderH, width: w, height: tickH)
    }

    @objc private func resetTapped() {
        onReset?()
    }

    @objc private func modeChanged() {
        let newMode = DetectionMode.allCases[modeControl.selectedSegmentIndex]
        guard newMode != currentMode else { return }
        currentMode = newMode
        slider.maximumValue = Float(currentMode.dictionaries.count - 1)
        slider.value = Float(sliderIndex)
        rebuildTicks()
        emitChange()
    }

    @objc private func sliderChanged() {
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
        onChange?(currentMode.dictionaries[sliderIndex])
    }
}
