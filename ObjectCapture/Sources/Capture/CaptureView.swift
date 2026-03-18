import SwiftUI
import RealityKit

struct CaptureView: View {
  @StateObject private var coordinator = CaptureCoordinator()
  @State private var isReconstructing = false

  let onComplete: (URL) -> Void
  let onCancel: () -> Void

  var body: some View {
    ZStack {
      if let session = coordinator.session {
        ObjectCaptureView(session: session)
          .overlay(alignment: .bottom) {
            Button("キャンセル") {
              coordinator.cancel()
              onCancel()
            }
            .buttonStyle(.bordered)
            .tint(.white)
            .padding(.bottom, 40)
          }
      }

      if isReconstructing {
        Color.black.opacity(0.7)
          .ignoresSafeArea()
        VStack(spacing: 16) {
          ProgressView()
            .scaleEffect(1.5)
            .tint(.white)
          Text("3Dモデルを構築中...")
            .foregroundStyle(.white)
            .font(.headline)
        }
      }
    }
    .interactiveDismissDisabled()
    .task {
      await coordinator.startSession()
      guard let session = coordinator.session else {
        onCancel()
        return
      }

      for await newState in session.stateUpdates {
        switch newState {
        case .completed:
          isReconstructing = true
          do {
            let url = try await coordinator.reconstruct()
            onComplete(url)
          } catch {
            print("Reconstruction failed: \(error)")
            onCancel()
          }
          return
        case .failed(let error):
          print("Capture failed: \(error)")
          onCancel()
          return
        default:
          continue
        }
      }
    }
  }
}
