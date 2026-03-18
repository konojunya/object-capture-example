import { requireNativeModule } from "expo-modules-core";

const ObjectCaptureModule = requireNativeModule("ObjectCapture");

export async function startCapture(): Promise<string> {
  return await ObjectCaptureModule.startCapture();
}

export async function isSupported(): Promise<boolean> {
  return await ObjectCaptureModule.isSupported();
}
