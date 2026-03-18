# object-capture-example

Swift / SwiftUI で Apple の ObjectCaptureSession を使い、現実のオブジェクトを3Dスキャンする PoC。

## Overview

フィギュアなど現実のオブジェクトを iPhone の LiDAR でスキャンし、3D モデル (USDZ) としてアプリ内で閲覧できます。

- **ObjectCaptureSession** (iOS 17+) によるガイド付き3Dキャプチャ
- **PhotogrammetrySession** によるオンデバイス USDZ 再構成 (`.reduced` 品質)
- **SceneKit** による USDZ ビューア（回転・ズーム対応）

## Architecture

```
ObjectCapture/Sources/
  App/
    ObjectCaptureApp.swift    → エントリポイント
    ContentView.swift         → ホーム画面（スキャン開始）
  Capture/
    CaptureView.swift         → ObjectCaptureSession の SwiftUI ラッパー
    CaptureCoordinator.swift  → セッション管理 + PhotogrammetrySession 再構成
  Viewer/
    ModelViewerView.swift     → SceneKit USDZ ビューア
```

## Requirements

- **iOS 17+**
- **LiDAR 搭載デバイス** (iPhone 12 Pro 以降)
- Xcode 16+
- [XcodeGen](https://github.com/yonaskolb/XcodeGen)

## Setup

```bash
xcodegen generate
open ObjectCapture.xcodeproj
```

Xcode で Signing の Team を設定し、実機にビルドしてください。

## Data Flow

```
スキャン開始ボタン
  → CaptureView (fullScreenCover)
  → ObjectCaptureSession でガイド付き撮影
  → PhotogrammetrySession で USDZ 再構成
  → Documents/{UUID}.usdz に保存
  → ModelViewerView で 3D 表示（回転・ズーム）
```

## License

MIT
