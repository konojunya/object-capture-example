import ExpoModulesCore
import SwiftUI
import RealityKit

class NotSupportedException: Exception, @unchecked Sendable {
  override var reason: String {
    "Object Capture is not supported on this device. Requires iOS 17+ and LiDAR."
  }
}

class PresentationFailedException: Exception, @unchecked Sendable {
  override var reason: String {
    "Could not find a view controller to present from"
  }
}

class CaptureFailedException: GenericException<String>, @unchecked Sendable {
  override var reason: String {
    "Capture failed: \(param)"
  }
}

class CaptureCancelledException: Exception, @unchecked Sendable {
  override var reason: String {
    "Capture was cancelled by the user"
  }
}

public class ObjectCaptureModule: Module {
  public func definition() -> ModuleDefinition {
    Name("ObjectCapture")

    AsyncFunction("isSupported") { () -> Bool in
      if #available(iOS 17.0, *) {
        return await MainActor.run {
          ObjectCaptureSession.isSupported
        }
      }
      return false
    }

    AsyncFunction("startCapture") { () async throws -> String in
      if #available(iOS 17.0, *) {
        let supported = await MainActor.run {
          ObjectCaptureSession.isSupported
        }
        guard supported else {
          throw NotSupportedException()
        }

        return try await withCheckedThrowingContinuation { continuation in
          Task { @MainActor [weak self] in
            self?.presentCaptureView(continuation: continuation)
          }
        }
      } else {
        throw NotSupportedException()
      }
    }
  }

  @available(iOS 17.0, *)
  @MainActor
  private func presentCaptureView(continuation: CheckedContinuation<String, Error>) {
    guard let viewController = appContext?.utilities?.currentViewController() else {
      continuation.resume(throwing: PresentationFailedException())
      return
    }

    let coordinator = ObjectCaptureCoordinator()

    coordinator.onComplete = { [weak viewController] path in
      DispatchQueue.main.async {
        viewController?.dismiss(animated: true) {
          continuation.resume(returning: path)
        }
      }
    }

    coordinator.onError = { [weak viewController] error in
      DispatchQueue.main.async {
        viewController?.dismiss(animated: true) {
          continuation.resume(throwing: CaptureFailedException(error.localizedDescription))
        }
      }
    }

    coordinator.onCancel = { [weak viewController] in
      DispatchQueue.main.async {
        viewController?.dismiss(animated: true) {
          continuation.resume(throwing: CaptureCancelledException())
        }
      }
    }

    let swiftUIView = ObjectCaptureContentView(coordinator: coordinator)
    let hostingController = UIHostingController(rootView: swiftUIView)
    hostingController.modalPresentationStyle = .fullScreen
    viewController.present(hostingController, animated: true)
  }
}
