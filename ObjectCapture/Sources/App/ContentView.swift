import SwiftUI
#if !targetEnvironment(simulator)
import RealityKit
#endif

struct ContentView: View {
  @State private var modelPath: URL?
  @State private var isCapturing = false

  private var isCaptureSupported: Bool {
    #if targetEnvironment(simulator)
    return false
    #else
    return ObjectCaptureSession.isSupported
    #endif
  }

  var body: some View {
    NavigationStack {
      VStack(spacing: 32) {
        Text("Object Capture PoC")
          .font(.largeTitle)
          .fontWeight(.bold)

        if isCaptureSupported {
          Button {
            isCapturing = true
          } label: {
            Label("スキャン開始", systemImage: "camera.viewfinder")
              .font(.title3)
              .fontWeight(.semibold)
              .frame(maxWidth: .infinity)
              .padding()
              .background(.blue)
              .foregroundStyle(.white)
              .clipShape(RoundedRectangle(cornerRadius: 12))
          }
          .padding(.horizontal, 32)
        } else {
          Label("このデバイスは Object Capture に対応していません", systemImage: "exclamationmark.triangle")
            .foregroundStyle(.secondary)
        }
      }
      .navigationDestination(item: $modelPath) { path in
        ModelViewerView(modelURL: path)
          .navigationTitle("3D Viewer")
          .navigationBarTitleDisplayMode(.inline)
      }
      #if !targetEnvironment(simulator)
      .fullScreenCover(isPresented: $isCapturing) {
        CaptureView { url in
          isCapturing = false
          modelPath = url
        } onCancel: {
          isCapturing = false
        }
      }
      #endif
    }
  }
}
