import ExpoModulesCore
import SwiftUI
import RealityKit

class NotSupportedException: Exception {
  override var reason: String {
    "Object Capture is not supported on this device. Requires iOS 17+ and LiDAR."
  }
}

class PresentationFailedException: Exception {
  override var reason: String {
    "Could not find a view controller to present from"
  }
}

class CaptureFailedException: GenericException<String> {
  override var reason: String {
    "Capture failed: \(param)"
  }
}

class CaptureCancelledException: Exception {
  override var reason: String {
    "Capture was cancelled by the user"
  }
}

public class ObjectCaptureModule: Module {
  public func definition() -> ModuleDefinition {
    Name("ObjectCapture")

    AsyncFunction("isSupported") { () -> Bool in
      if #available(iOS 17.0, *) {
        return ObjectCaptureSession.isSupported
      }
      return false
    }

    AsyncFunction("startCapture") { (promise: Promise) in
      if #available(iOS 17.0, *) {
        guard ObjectCaptureSession.isSupported else {
          promise.reject(NotSupportedException())
          return
        }

        Task { @MainActor [weak self] in
          self?.presentCaptureView(promise: promise)
        }
      } else {
        promise.reject(NotSupportedException())
      }
    }
  }

  @available(iOS 17.0, *)
  @MainActor
  private func presentCaptureView(promise: Promise) {
    guard let viewController = appContext?.utilities?.currentViewController() else {
      promise.reject(PresentationFailedException())
      return
    }

    let coordinator = ObjectCaptureCoordinator()

    coordinator.onComplete = { [weak viewController] path in
      DispatchQueue.main.async {
        viewController?.dismiss(animated: true) {
          promise.resolve(path)
        }
      }
    }

    coordinator.onError = { [weak viewController] error in
      DispatchQueue.main.async {
        viewController?.dismiss(animated: true) {
          promise.reject(CaptureFailedException(error.localizedDescription))
        }
      }
    }

    coordinator.onCancel = { [weak viewController] in
      DispatchQueue.main.async {
        viewController?.dismiss(animated: true) {
          promise.reject(CaptureCancelledException())
        }
      }
    }

    let swiftUIView = ObjectCaptureContentView(coordinator: coordinator)
    let hostingController = UIHostingController(rootView: swiftUIView)
    hostingController.modalPresentationStyle = .fullScreen
    viewController.present(hostingController, animated: true)
  }
}
