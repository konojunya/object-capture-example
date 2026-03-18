import SwiftUI
import RealityKit

@available(iOS 17.0, *)
@MainActor
class ObjectCaptureCoordinator: ObservableObject {
  var session: ObjectCaptureSession?
  private var captureDir: URL?
  var onComplete: ((String) -> Void)?
  var onError: ((Error) -> Void)?
  var onCancel: (() -> Void)?

  func startSession() async {
    let session = ObjectCaptureSession()
    self.session = session

    let documentsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
    let captureDir = documentsDir.appendingPathComponent("capture-\(UUID().uuidString)")
    self.captureDir = captureDir

    let imagesDir = captureDir.appendingPathComponent("Images")
    let checkpointsDir = captureDir.appendingPathComponent("Checkpoints")

    try? FileManager.default.createDirectory(at: imagesDir, withIntermediateDirectories: true)
    try? FileManager.default.createDirectory(at: checkpointsDir, withIntermediateDirectories: true)

    var config = ObjectCaptureSession.Configuration()
    config.checkpointDirectory = checkpointsDir

    session.start(
      imagesDirectory: imagesDir,
      configuration: config
    )
  }

  func reconstruct() async {
    guard let captureDir = captureDir else {
      onError?(NSError(domain: "ObjectCapture", code: -1, userInfo: [NSLocalizedDescriptionKey: "No capture directory"]))
      return
    }

    let documentsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
    let outputPath = documentsDir.appendingPathComponent("\(UUID().uuidString).usdz")

    do {
      let request = PhotogrammetrySession.Request.modelFile(url: outputPath, detail: .reduced)
      let imagesDir = captureDir.appendingPathComponent("Images")
      let photogrammetrySession = try PhotogrammetrySession(input: imagesDir)

      try photogrammetrySession.process(requests: [request])

      for try await output in photogrammetrySession.outputs {
        switch output {
        case .requestComplete(_, let result):
          switch result {
          case .modelFile(let url):
            cleanupCaptureDir()
            onComplete?(url.path)
            return
          default:
            break
          }
        case .requestError(_, let error):
          cleanupCaptureDir()
          onError?(error)
          return
        default:
          continue
        }
      }
    } catch {
      cleanupCaptureDir()
      onError?(error)
    }
  }

  func cancel() {
    session?.cancel()
    cleanupCaptureDir()
    onCancel?()
  }

  private func cleanupCaptureDir() {
    guard let captureDir = captureDir else { return }
    try? FileManager.default.removeItem(at: captureDir)
    self.captureDir = nil
  }
}

@available(iOS 17.0, *)
struct ObjectCaptureContentView: View {
  @ObservedObject var coordinator: ObjectCaptureCoordinator
  @State private var isReconstructing = false

  var body: some View {
    ZStack {
      if let session = coordinator.session {
        ObjectCaptureView(session: session)
          .overlay(alignment: .bottom) {
            HStack(spacing: 20) {
              Button("Cancel") {
                coordinator.cancel()
              }
              .buttonStyle(.bordered)

              if case .completing = session.state {
                // Session is finishing, no additional buttons needed
              } else if case .finished = session.state {
                // Will auto-transition to reconstruction
              }
            }
            .padding(.bottom, 40)
          }
      }

      if isReconstructing {
        Color.black.opacity(0.7)
          .ignoresSafeArea()
        VStack(spacing: 16) {
          ProgressView()
            .scaleEffect(1.5)
          Text("3Dモデルを構築中...")
            .foregroundColor(.white)
            .font(.headline)
        }
      }
    }
    .task {
      await coordinator.startSession()
      guard let session = coordinator.session else { return }

      for await newState in session.stateUpdates {
        switch newState {
        case .completed:
          isReconstructing = true
          await coordinator.reconstruct()
          return
        case .failed(let error):
          coordinator.onError?(error)
          return
        default:
          continue
        }
      }
    }
  }
}
