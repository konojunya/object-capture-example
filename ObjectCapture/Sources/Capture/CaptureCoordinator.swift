#if !targetEnvironment(simulator)
import Foundation
import SwiftUI
import RealityKit

@MainActor
class CaptureCoordinator: ObservableObject {
  @Published var session: ObjectCaptureSession?
  @Published var capturedImageCount: Int = 0
  @Published var capturedFilesList: String = ""
  private var captureDir: URL?
  private var imageCountTimer: Timer?

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
    // isOverCaptureEnabled is for Mac reconstruction, not needed on-device

    session.start(imagesDirectory: imagesDir, configuration: config)

    // Poll image count periodically - check all files recursively
    imageCountTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
      Task { @MainActor in
        guard let self, let captureDir = self.captureDir else { return }
        // List everything in capture dir
        if let enumerator = FileManager.default.enumerator(at: captureDir, includingPropertiesForKeys: [.isRegularFileKey]) {
          var count = 0
          var fileList: [String] = []
          while let url = enumerator.nextObject() as? URL {
            let isFile = (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) ?? false
            if isFile {
              count += 1
              if fileList.count < 5 {
                fileList.append(url.lastPathComponent)
              }
            }
          }
          self.capturedImageCount = count
          if self.capturedFilesList != fileList.joined(separator: ", ") {
            self.capturedFilesList = fileList.joined(separator: ", ")
          }
        }
      }
    }
  }

  func reconstruct() async throws -> URL {
    guard let captureDir = captureDir else {
      throw CaptureError.noCaptureDirectory
    }

    imageCountTimer?.invalidate()

    // Free GPU/memory from capture session (Apple sample does this)
    session = nil

    let documentsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
    let outputURL = documentsDir.appendingPathComponent("\(UUID().uuidString).usdz")
    let imagesDir = captureDir.appendingPathComponent("Images")
    let checkpointsDir = captureDir.appendingPathComponent("Checkpoints")

    // Match WWDC code: pass checkpointDirectory to PhotogrammetrySession too
    var pgConfig = PhotogrammetrySession.Configuration()
    pgConfig.checkpointDirectory = checkpointsDir

    let photogrammetrySession = try PhotogrammetrySession(
      input: imagesDir,
      configuration: pgConfig
    )

    let request = PhotogrammetrySession.Request.modelFile(url: outputURL)
    try photogrammetrySession.process(requests: [request])

    for try await output in photogrammetrySession.outputs {
      print("[Reconstruct] output: \(output)")
      switch output {
      case .requestComplete(let request, let result):
        print("[Reconstruct] requestComplete: \(request) result: \(result)")
        if case .modelFile(let url) = result {
          cleanupCaptureDir()
          return url
        }
      case .requestError(let request, let error):
        print("[Reconstruct] requestError: \(request) error: \(error)")
        cleanupCaptureDir()
        throw CaptureError.reconstructionDetail("\(error)")
      case .processingComplete:
        print("[Reconstruct] processingComplete")
        if FileManager.default.fileExists(atPath: outputURL.path) {
          cleanupCaptureDir()
          return outputURL
        }
      case .invalidSample(let id, let reason):
        print("[Reconstruct] invalidSample id:\(id) reason:\(reason)")
        continue
      case .skippedSample(let id):
        print("[Reconstruct] skippedSample id:\(id)")
        continue
      case .requestProgress(let request, let fraction):
        print("[Reconstruct] progress: \(Int(fraction * 100))%")
        continue
      default:
        print("[Reconstruct] other: \(output)")
        continue
      }
    }

    cleanupCaptureDir()
    throw CaptureError.reconstructionFailed
  }

  func cancel() {
    imageCountTimer?.invalidate()
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
  case reconstructionDetail(String)

  var errorDescription: String? {
    switch self {
    case .noCaptureDirectory:
      return "キャプチャディレクトリが見つかりません"
    case .reconstructionFailed:
      return "3Dモデルの構築に失敗しました"
    case .reconstructionDetail(let detail):
      return "再構成エラー: \(detail)"
    }
  }
}
#endif
