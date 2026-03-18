# Object Capture PoC Design

## Overview

React Native (Expo) から Swift の ObjectCaptureSession を使い、フィギュアなど現実のオブジェクトを3Dスキャンし、スキャン結果の USDZ モデルをアプリ内で閲覧できる PoC。

## Goals

- ObjectCaptureSession による3Dスキャンが React Native から動作することを検証
- スキャンした USDZ モデルをアプリ内で表示（回転・ズーム）できることを確認

## Non-Goals

- 宝物box（一覧・コレクション管理）機能
- スタイリング・UI デザイン
- クラウド保存・共有機能
- 複数モデルの管理

## Architecture

### Tech Stack

- **React Native**: Expo (SDK 52+) + Expo Router
- **Native Modules**: expo-modules-core で Swift モジュールを実装
- **3D Capture**: ObjectCaptureSession (iOS 17+)
- **3D Reconstruction**: PhotogrammetrySession (on-device, iOS 17+)
- **3D Viewer**: SceneKit (SCNView)
- **Storage**: ローカル Documents ディレクトリ

### Project Structure

```
rn-object-capture-bridge-example/
├── app/                          # Expo Router screens
│   ├── index.tsx                 # ホーム（スキャン開始ボタン）
│   └── viewer.tsx                # ビューア画面
├── modules/
│   ├── object-capture/           # Expo Module: スキャン
│   │   ├── index.ts              # JS API
│   │   ├── src/
│   │   │   ├── ObjectCaptureModule.swift  # Expo Module 定義、startCapture() の実装
│   │   │   └── ObjectCaptureView.swift    # SwiftUI ビュー（ObjectCaptureSession のUI + 再構成処理）
│   │   └── expo-module.config.json
│   └── model-viewer/             # Expo Module: USDZ ビューア
│       ├── index.ts              # JS API
│       ├── src/
│       │   ├── ModelViewerModule.swift
│       │   └── ModelViewerView.swift
│       └── expo-module.config.json
├── app.json
├── package.json
└── tsconfig.json
```

### Module Design

#### ObjectCaptureModule

**JS API:**

```typescript
// modules/object-capture/index.ts
export async function startCapture(): Promise<string>
// Returns: USDZ file path in Documents directory
```

**Swift Implementation:**

- `startCapture()` が呼ばれると SwiftUI の ObjectCaptureView をフルスクリーンモーダルで表示
- ObjectCaptureSession のライフサイクル管理: `ready` → `detecting` → `capturing` → `finishing` → `completed`
- キャプチャ完了後、PhotogrammetrySession でオンデバイス再構成
- USDZ を `Documents/{UUID}.usdz` に保存
- Promise で USDZ ファイルパスを resolve、エラー時は reject

#### ModelViewerView

**JS API:**

```typescript
// modules/model-viewer/index.ts
import { requireNativeView } from 'expo-modules-core'

export const ModelViewer: React.ComponentType<{
  modelPath: string
  style?: ViewStyle
}>
```

**Swift Implementation:**

- Expo View として SCNView をラップ
- `modelPath` prop で USDZ ファイルパスを受け取る
- SCNScene に USDZ をロードして表示
- `allowsCameraControl = true` で回転・ズーム対応

### Data Flow

```
[ホーム画面]
  → ボタンタップ
  → ObjectCaptureModule.startCapture()
  → Swift: ObjectCaptureSession 起動（フルスクリーン SwiftUI）
  → ユーザーがオブジェクト周りを撮影
  → Swift: PhotogrammetrySession で USDZ 再構成
  → Documents/{UUID}.usdz に保存
  → Promise<string> でファイルパスを返す
  → router.push('/viewer', { modelPath })
  → <ModelViewer modelPath={path} /> で3D表示
```

### React Native Screens

#### Home (app/index.tsx)

- 「スキャン開始」ボタンのみ
- ボタンタップで `startCapture()` を呼び、結果のパスでビューア画面に遷移

#### Viewer (app/viewer.tsx)

- `useLocalSearchParams()` で `modelPath` を取得
- `<ModelViewer>` コンポーネントで USDZ を表示
- 戻るボタンでホームに戻る

### SwiftUI-UIKit Bridging Strategy

ObjectCaptureView は SwiftUI ビューだが、Expo Module は UIKit コンテキストで動作する。ブリッジ方法:

1. `UIHostingController` で SwiftUI の ObjectCaptureView をラップ
2. Expo Module の `appContext` から現在の `UIViewController` を取得
3. `present(_:animated:)` でフルスクリーンモーダルとして表示
4. キャプチャ完了/キャンセル時に `dismiss` し、Promise を resolve/reject

### Expo Config Plugin

`app.json` の `expo.ios` で以下を設定:

- `deploymentTarget`: `"17.0"`
- `infoPlist.NSCameraUsageDescription`: カメラ使用理由の説明文
- 必要なフレームワーク: RealityKit, SceneKit, Metal (自動リンク)

### Reconstruction Detail Level

PhotogrammetrySession の再構成は `.reduced` を使用。PoC では速度を優先し、高品質な再構成は不要。`.reduced` なら再構成時間は概ね30秒〜1分程度。

### File Path Format

`startCapture()` が返すパスは絶対ファイルパス (例: `/var/mobile/Containers/.../Documents/UUID.usdz`)。Swift 側で `URL(fileURLWithPath:)` で変換して使用。

### Disk Space / Temp Files

ObjectCaptureSession のキャプチャ中に中間画像データが一時ディレクトリに保存される (数百MB)。再構成完了後、中間データは削除する。最終的な USDZ ファイルのみ Documents に残す。

## Constraints

- **iOS 17+ 必須**: ObjectCaptureSession およびオンデバイス PhotogrammetrySession の最低要件
- **デバイスサポート**: `ObjectCaptureSession.isSupported` で実行時チェック。LiDAR + Neural Engine が必要 (iPhone 12 Pro 以降)
- **シミュレータ不可**: 実機テストが必須
- **再構成時間**: `.reduced` 品質で概ね30秒〜1分。メモリ消費が大きいため、古いデバイスではメモリ警告が出る可能性あり
- **カメラ権限**: `NSCameraUsageDescription` 必須。権限拒否時はエラーとして処理

## Error Handling

- `ObjectCaptureSession.isSupported == false`: アラートを表示して処理を中断
- カメラ権限拒否: Promise を reject し、設定画面への誘導メッセージを表示
- キャプチャ中のキャンセル: Promise を reject し、一時ファイルをクリーンアップしてホーム画面に戻る
- 再構成失敗: Promise を reject し、一時ファイルをクリーンアップしてエラーメッセージを表示
- アプリバックグラウンド遷移: PoC では特別な対処はしない（セッションが中断される可能性あり）
