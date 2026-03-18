import SwiftUI
import SceneKit

struct ModelViewerView: View {
  let modelURL: URL

  var body: some View {
    SceneKitView(url: modelURL)
      .ignoresSafeArea(edges: .bottom)
  }
}

private struct SceneKitView: UIViewRepresentable {
  let url: URL

  func makeUIView(context: Context) -> SCNView {
    let sceneView = SCNView()
    sceneView.autoenablesDefaultLighting = true
    sceneView.allowsCameraControl = true
    sceneView.backgroundColor = .black

    if let scene = try? SCNScene(url: url) {
      sceneView.scene = scene
    }

    return sceneView
  }

  func updateUIView(_ uiView: SCNView, context: Context) {}
}
