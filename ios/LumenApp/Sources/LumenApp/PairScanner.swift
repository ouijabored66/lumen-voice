import AVFoundation
import SwiftUI
import UIKit

/// Camera scan of the desktop `/pair` QR. The image is not stored.
struct PairScanner: View {
    var onCode: (String) -> Void
    var onCancel: () -> Void

    @State private var denied = false
    @State private var noCamera = false
    @State private var ready = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if noCamera {
                Text("This iPhone has no camera to scan with. Type the URL and token from the pair page instead.")
                    .font(.body)
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .padding(24)
            } else if denied {
                VStack(spacing: 14) {
                    Text("Camera access is off, so Lumen can't scan the pairing QR.")
                        .multilineTextAlignment(.center)
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        Link("Open Settings", destination: url)
                    }
                }
                .font(.body)
                .foregroundStyle(.white)
                .padding(24)
            } else if ready {
                ScannerPreview(onCode: onCode)
                    .ignoresSafeArea()
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Theme.accent, lineWidth: 2)
                    .frame(width: 240, height: 240)
            }
            VStack {
                HStack {
                    Button("Cancel", action: onCancel)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(16)
                    Spacer()
                }
                Spacer()
                Text("Point the camera at the QR code on your computer.")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.white)
                    .padding(.bottom, 28)
            }
        }
        .onAppear { prepare() }
    }

    private func prepare() {
        guard AVCaptureDevice.default(for: .video) != nil else {
            noCamera = true
            return
        }
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            denied = false
            ready = true
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { ok in
                DispatchQueue.main.async {
                    denied = !ok
                    ready = ok
                }
            }
        default:
            denied = true
        }
    }
}

struct PairScanButton: View {
    @EnvironmentObject var model: LumenModel
    var title: String = "Scan QR code"
    var onFinished: (PairingOutcome) -> Void

    @State private var show = false
    @State private var busy = false

    var body: some View {
        Button {
            show = true
        } label: {
            HStack {
                Image(systemName: "qrcode.viewfinder")
                Text(title)
                Spacer()
                if busy { ProgressView() }
            }
        }
        .disabled(busy)
        .sheet(isPresented: $show) {
            PairScanner { code in
                show = false
                busy = true
                Task {
                    let outcome = await model.applyPairing(code)
                    busy = false
                    onFinished(outcome)
                }
            } onCancel: {
                show = false
            }
        }
    }
}

private struct ScannerPreview: UIViewControllerRepresentable {
    var onCode: (String) -> Void

    func makeUIViewController(context: Context) -> ScannerController {
        let c = ScannerController()
        c.onCode = onCode
        return c
    }

    func updateUIViewController(_ uiViewController: ScannerController, context: Context) {
        uiViewController.onCode = onCode
    }
}

final class ScannerController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
    var onCode: ((String) -> Void)?
    private let session = AVCaptureSession()
    private var handled = false
    private var preview: AVCaptureVideoPreviewLayer?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        guard let device = AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input) else { return }
        session.addInput(input)
        let output = AVCaptureMetadataOutput()
        guard session.canAddOutput(output) else { return }
        session.addOutput(output)
        output.setMetadataObjectsDelegate(self, queue: .main)
        if output.availableMetadataObjectTypes.contains(.qr) {
            output.metadataObjectTypes = [.qr]
        }
        let layer = AVCaptureVideoPreviewLayer(session: session)
        layer.videoGravity = .resizeAspectFill
        layer.frame = view.bounds
        view.layer.addSublayer(layer)
        preview = layer
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        preview?.frame = view.bounds
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.session.startRunning()
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        session.stopRunning()
    }

    func metadataOutput(_ output: AVCaptureMetadataOutput,
                        didOutput objects: [AVMetadataObject],
                        from connection: AVCaptureConnection) {
        guard !handled,
              let obj = objects.first as? AVMetadataMachineReadableCodeObject,
              obj.type == .qr,
              let value = obj.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else { return }
        handled = true
        session.stopRunning()
        onCode?(value)
    }
}
