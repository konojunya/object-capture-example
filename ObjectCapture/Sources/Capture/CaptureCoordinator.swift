import Foundation
import RealityKit

@MainActor
class CaptureCoordinator: ObservableObject {
  var session: ObjectCaptureSession?
  private var captureDir: URL?

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

    session.start(imagesDirectory: imagesDir, configuration: config)
  }

  func reconstruct() async throws -> URL {
    guard let captureDir = captureDir else {
      throw CaptureError.noCaptureDirectory
    }

    let documentsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
    let outputURL = documentsDir.appendingPathComponent("\(UUID().uuidString).usdz")
    let imagesDir = captureDir.appendingPathComponent("Images")

    let photogrammetrySession = try PhotogrammetrySession(input: imagesDir)
    let request = PhotogrammetrySession.Request.modelFile(url: outputURL, detail: .reduced)

    try photogrammetrySession.process(requests: [request])

    for try await output in photogrammetrySession.outputs {
      switch output {
      case .requestComplete(_, let result):
        if case .modelFile(let url) = result {
          cleanupCaptureDir()
          return url
        }
      case .requestError(_, let error):
        cleanupCaptureDir()
        throw error
      default:
        continue
      }
    }

    cleanupCaptureDir()
    throw CaptureError.reconstructionFailed
  }

  func cancel() {
    session?.cancel()
    cleanupCaptureDir()
  }

  private func cleanupCaptureDir() {
    guard let captureDir = captureDir else { return }
    try? FileManager.default.removeItem(at: captureDir)
    self.captureDir = nil
  }
}

enum CaptureError: LocalizedError {
  case noCaptureDirectory
  case reconstructionFailed

  var errorDescription: String? {
    switch self {
    case .noCaptureDirectory:
      return "キャプチャディレクトリが見つかりません"
    case .reconstructionFailed:
      return "3Dモデルの構築に失敗しました"
    }
  }
}
