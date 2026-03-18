#if !targetEnvironment(simulator)
import SwiftUI
import RealityKit

struct CaptureView: View {
  @StateObject private var coordinator = CaptureCoordinator()
  @State private var isReconstructing = false
  @State private var captureState: ObjectCaptureSession.CaptureState = .ready
  @State private var shotCount: Int = 0
  @State private var feedbackText: String = ""
  @State private var debugLog: [String] = []
  @State private var errorMessage: String?
  @State private var detectionFailed = false

  let onComplete: (URL) -> Void
  let onCancel: () -> Void

  var body: some View {
    ZStack {
      if let session = coordinator.session {
        ObjectCaptureView(session: session, cameraFeedOverlay: { GradientBackground() })

        VStack {
          // Top bar
          HStack(alignment: .top) {
            Button("キャンセル") {
              coordinator.cancel()
              onCancel()
            }
            .padding(12)
            .font(.subheadline).bold()
            .foregroundColor(.white)
            .background(.ultraThinMaterial)
            .environment(\.colorScheme, .dark)
            .cornerRadius(15)

            Spacer()

            // Debug
            VStack(alignment: .trailing, spacing: 2) {
              ForEach(debugLog.suffix(8), id: \.self) { line in
                Text(line).font(.caption2).foregroundStyle(.green)
              }
            }
            .padding(6)
            .background(.black.opacity(0.5))
            .clipShape(RoundedRectangle(cornerRadius: 6))
          }
          .padding(.top, 60)
          .padding(.horizontal, 16)

          Spacer()

          // Feedback
          if !feedbackText.isEmpty {
            Text(feedbackText)
              .foregroundStyle(.orange)
              .font(.callout).bold()
              .padding(8)
              .background(.black.opacity(0.5))
              .clipShape(RoundedRectangle(cornerRadius: 8))
          }

          // Shot count (during capturing)
          if case .capturing = captureState {
            Text("\(shotCount) shots")
              .foregroundStyle(.yellow)
              .font(.caption).bold()
              .padding(.top, 4)
          }

          // Controls based on state
          captureControls(session: session)
            .padding(.bottom, 40)
        }
      }

      if let errorMessage {
        Color.black.opacity(0.85).ignoresSafeArea()
        VStack(spacing: 20) {
          Text("Error").font(.title2).fontWeight(.bold).foregroundStyle(.red)
          ScrollView {
            Text(errorMessage)
              .foregroundStyle(.white).font(.body).multilineTextAlignment(.leading)
            VStack(alignment: .leading, spacing: 2) {
              ForEach(debugLog, id: \.self) { line in
                Text(line).font(.caption2).foregroundStyle(.green)
              }
            }
          }
          .frame(maxHeight: 400).padding()
          Button("閉じる") { onCancel() }
            .buttonStyle(.borderedProminent).tint(.red)
        }
        .padding()
      } else if isReconstructing {
        Color.black.opacity(0.7).ignoresSafeArea()
        VStack(spacing: 16) {
          ProgressView().scaleEffect(1.5).tint(.white)
          Text("3Dモデルを構築中...").foregroundStyle(.white).font(.headline)
        }
      }
    }
    .interactiveDismissDisabled()
    // State updates
    .task {
      debugLog.append("starting...")
      await coordinator.startSession()
      guard let session = coordinator.session else {
        errorMessage = "session nil"
        return
      }
      debugLog.append("state: \(session.state)")

      for await newState in session.stateUpdates {
        let stateStr: String
        switch newState {
        case .ready: stateStr = "ready"
        case .detecting: stateStr = "detecting"
        case .capturing: stateStr = "capturing"
        case .finishing: stateStr = "finishing"
        case .completed: stateStr = "completed"
        case .failed: stateStr = "failed"
        default: stateStr = "unknown"
        }
        debugLog.append("→ \(stateStr)")
        captureState = newState

        switch newState {
        case .completed:
          isReconstructing = true
          do {
            let url = try await coordinator.reconstruct()
            onComplete(url)
          } catch {
            errorMessage = "reconstruct: \(error)"
          }
          return
        case .failed(let error):
          errorMessage = "failed: \(error)"
          return
        default:
          continue
        }
      }
    }
    // Shot count
    .task {
      try? await Task.sleep(for: .milliseconds(500))
      guard let session = coordinator.session else { return }
      for await count in session.numberOfShotsTakenUpdates {
        shotCount = count
        debugLog.append("shots: \(count)")
      }
    }
    // Feedback
    .task {
      try? await Task.sleep(for: .milliseconds(500))
      guard let session = coordinator.session else { return }
      for await fb in session.feedbackUpdates {
        let texts = fb.map { f -> String in
          switch f {
          case .objectTooClose: return "近すぎます"
          case .objectTooFar: return "遠すぎます"
          case .movingTooFast: return "速すぎます"
          case .environmentLowLight: return "もっと明るく"
          case .environmentTooDark: return "暗すぎます"
          case .outOfFieldOfView: return "画面内に収めて"
          case .objectNotDetected: return "オブジェクト未検出"
          case .overCapturing: return "十分撮れました"
          default: return "\(f)"
          }
        }
        feedbackText = texts.joined(separator: " / ")
      }
    }
  }

  @ViewBuilder
  private func captureControls(session: ObjectCaptureSession) -> some View {
    switch captureState {
    // Step 1: ready → user taps Continue → startDetecting()
    case .ready:
      Button {
        detectionFailed = !(session.startDetecting())
        debugLog.append("startDetecting: \(!detectionFailed)")
      } label: {
        Text("Continue")
          .font(.body).fontWeight(.bold)
          .foregroundColor(.white)
          .padding(.horizontal, 25)
          .padding(.vertical, 20)
          .background(.blue)
          .clipShape(Capsule())
      }

    // Step 2: detecting → bounding box appears → user taps Start Capture → startCapturing()
    case .detecting:
      VStack(spacing: 12) {
        if detectionFailed {
          Text("検出に失敗しました。もう一度試してください")
            .foregroundStyle(.red).font(.caption)
        }
        Button {
          session.startCapturing()
          debugLog.append("startCapturing")
        } label: {
          Text("Start Capture")
            .font(.body).fontWeight(.bold)
            .foregroundColor(.white)
            .padding(.horizontal, 25)
            .padding(.vertical, 20)
            .background(.blue)
            .clipShape(Capsule())
        }
      }

    // Step 3: capturing → user walks around → finish when done
    case .capturing:
      HStack(spacing: 20) {
        // Manual shot button
        Button {
          session.requestImageCapture()
          debugLog.append("manual shot")
        } label: {
          Image(systemName: "button.programmable")
            .font(.largeTitle)
            .foregroundColor(session.canRequestImageCapture ? .white : .gray)
        }
        .disabled(!session.canRequestImageCapture)

        // Finish button
        Button {
          session.finish()
          debugLog.append("finish, shots: \(shotCount)")
        } label: {
          Text("Done")
            .font(.body).fontWeight(.bold)
            .foregroundColor(.white)
            .padding(.horizontal, 25)
            .padding(.vertical, 20)
            .background(shotCount >= 10 ? .green : .orange)
            .clipShape(Capsule())
        }
      }

    case .finishing:
      ProgressView()
        .tint(.white)

    default:
      EmptyView()
    }
  }
}

private struct GradientBackground: View {
  var body: some View {
    VStack {
      LinearGradient(colors: [.black.opacity(0.4), .clear], startPoint: .top, endPoint: .bottom)
        .frame(height: 200)
      Spacer()
      LinearGradient(colors: [.black.opacity(0.4), .clear], startPoint: .bottom, endPoint: .top)
        .frame(height: 200)
    }
    .ignoresSafeArea()
    .allowsHitTesting(false)
  }
}
#endif
