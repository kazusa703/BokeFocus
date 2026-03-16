# BokeFocus - CLAUDE.md

## アプリ概要

BokeFocusは、ユーザーが画像上で対象をラフに囲むだけで精密にセグメンテーションし、対象以外の背景をぼかす**背景ぼかし特化iOSアプリ**。Adobe Photoshopの「オブジェクト選択ツール」に相当するインタラクティブセグメンテーション体験をオンデバイスで実現する。

### コアバリュー
- **「囲むだけでボケる」** — 従来の背景ぼかしアプリの大半は「自動で人物検出」するだけ。本アプリは任意のオブジェクトをユーザーが指定して精密選択できる
- 完全オンデバイス処理。サーバー不要、プライバシー安全

---

## 技術スタック

| 項目 | 選定 |
|------|------|
| 言語 | Swift |
| UI | SwiftUI |
| 最小OS | iOS 17.0 |
| セグメンテーション（主） | EdgeSAM（Core ML、Encoder+Decoder 2モデル構成） |
| セグメンテーション（自動フォールバック） | Vision framework `VNGenerateForegroundInstanceMaskRequest` |
| 画像合成 | Core Image（CIFilter） |
| 前処理 | 初期: vImage + CPU / 最適化後: Metal compute kernel |
| 画像入力 | PHPicker（フォトライブラリ） |
| MLComputeUnits | `.all`（Neural Engine最大活用） |
| 収益モデル | AdMob バナー/インターステ + 広告削除IAP（¥480） |

---

## アーキテクチャ

### モデル構成

EdgeSAMは公式配布の**変換済みCore MLモデル**（`.mlpackage`）を使用。自前変換は行わない。

```
BokeFocus/
├── Models/
│   ├── EdgeSAMEncoder.mlpackage   # 入力: 1×3×1024×1024 → 出力: 1×256×64×64
│   └── EdgeSAMDecoder.mlpackage   # 入力: embedding + coords + labels → 出力: masks
```

**重要**: モデル追加後、Xcodeの `modelDescription` で入出力名・型・shapeを必ず現物確認すること。READMEと異なる場合がある。

### レイヤー構成

```
┌─────────────────────────────────────────────────────┐
│  View Layer (SwiftUI)                                │
│  ├── ImagePickerView (PHPicker)                      │
│  ├── EditorView                                      │
│  │   ├── ImageDisplayView (AspectFit表示)            │
│  │   ├── SelectionOverlayView (BBox/ポイント描画)    │
│  │   └── MaskOverlayView (選択結果の可視化)          │
│  └── ResultView (ぼかし結果プレビュー + 保存)        │
├─────────────────────────────────────────────────────┤
│  ViewModel Layer                                     │
│  ├── EditorViewModel (@Observable)                   │
│  │   ├── 画像読み込み・表示状態管理                   │
│  │   ├── ユーザー操作（BBox/ポイント）の状態管理      │
│  │   └── セグメンテーション・ぼかし実行の制御         │
├─────────────────────────────────────────────────────┤
│  Service Layer                                       │
│  ├── ImagePreprocessor (★最重要)                     │
│  │   ├── letterbox変換（リサイズ+パディング）         │
│  │   ├── RGB正規化 → MLMultiArray(1×3×1024×1024)    │
│  │   ├── scale / padOffset の保持・公開              │
│  │   └── プロンプト座標変換（同じscale/padで変換）    │
│  ├── SegmentationService                             │
│  │   ├── EdgeSAMEngine (Core ML推論)                 │
│  │   └── VisionEngine (自動セグメンテーション)        │
│  ├── MaskPostprocessor                               │
│  │   ├── パディング領域除外                           │
│  │   ├── 元画像サイズへリサイズ                       │
│  │   ├── 閾値処理（logits→二値マスク）               │
│  │   └── マスク→CIImage変換                          │
│  └── BlurCompositor                                  │
│      ├── マスクリファイン（erode + feather）          │
│      ├── CIGaussianBlur / CIBokehBlur               │
│      └── CIBlendWithMask合成                         │
├─────────────────────────────────────────────────────┤
│  Infrastructure                                      │
│  ├── CoordinateConverter                             │
│  │   └── 画面座標 ↔ 画像ピクセル座標 ↔ SAM座標      │
│  └── CIContext (Metal device, アプリ起動時に1回生成)  │
└─────────────────────────────────────────────────────┘
```

---

## 画面フロー

```
[ホーム] → [写真選択(PHPicker)] → [エディター] → [結果プレビュー] → [保存/共有]
                                       │
                                       ├── タップ → Vision自動検出試行
                                       │            → 対象あり → マスク生成 → ぼかし
                                       │            → 対象なし → BBox描画モードへ
                                       │
                                       ├── BBox描画（ドラッグ） → EdgeSAM推論 → マスク生成
                                       │
                                       └── ポイント追加（タップ）で選択を微調整
                                            ├── 通常タップ → positive point (label=1)
                                            └── トグルボタンON時 → negative point (label=0)
```

---

## ★ ImagePreprocessor — 最重要コンポーネント

前処理・座標変換の整合性がアプリ品質を決める。**同一のパラメータで画像も座標も変換する**設計。

### 責務

```swift
struct LetterboxParams {
    let scale: CGFloat           // 1024 / max(H, W)
    let resizedWidth: Int        // round(W * scale)
    let resizedHeight: Int       // round(H * scale)
    let padX: Int                // (1024 - resizedWidth) / 2  ※左側パディング
    let padY: Int                // (1024 - resizedHeight) / 2 ※上側パディング
    let originalSize: CGSize     // 元画像サイズ
}
```

### 画像前処理パイプライン

1. 元画像（CGImage/CIImage）を取得
2. 長辺が1024になるようリサイズ（アスペクト比維持）
3. ImageNet正規化: `(pixel / 255.0 - mean) / std`
   - mean = [0.485, 0.456, 0.406]
   - std  = [0.229, 0.224, 0.225]
4. 短辺側を0パディングして1024×1024化
5. CHW配列（1×3×1024×1024）として `MLMultiArray(dataType: .float32)` に格納
6. `LetterboxParams` を保持（後続の座標変換・後処理で再利用）

**初期実装はCPU（vImage + MLMultiArray直書き）で正しさを検証してからMetal化する。**

### プロンプト座標変換

ユーザーが画面上で描いたBBox/ポイントをSAM入力座標に変換する関数。

```
画面座標 (screenPoint)
  ↓ AspectFit表示のオフセット・スケール除去
画像ピクセル座標 (imagePoint)
  ↓ LetterboxParams の scale, padX, padY を適用
SAM座標 (samPoint) — 1024×1024空間、(height, width)フォーマット
```

**注意**: EdgeSAMのプロンプト座標は `(height, width)` = `(y, x)` 順。一般的な `(x, y)` とは逆。

```swift
func screenToSAMCoords(screenPoint: CGPoint, viewSize: CGSize, params: LetterboxParams) -> CGPoint {
    // 1. AspectFit表示領域の計算
    let imageAspect = params.originalSize.width / params.originalSize.height
    let viewAspect = viewSize.width / viewSize.height
    let (displayW, displayH, offsetX, offsetY): (CGFloat, CGFloat, CGFloat, CGFloat)
    if imageAspect > viewAspect {
        displayW = viewSize.width
        displayH = viewSize.width / imageAspect
        offsetX = 0
        offsetY = (viewSize.height - displayH) / 2
    } else {
        displayH = viewSize.height
        displayW = viewSize.height * imageAspect
        offsetX = (viewSize.width - displayW) / 2
        offsetY = 0
    }
    
    // 2. 画面座標 → 画像ピクセル座標
    let imageX = (screenPoint.x - offsetX) * params.originalSize.width / displayW
    let imageY = (screenPoint.y - offsetY) * params.originalSize.height / displayH
    
    // 3. 画像ピクセル → SAM 1024空間（letterbox適用）
    let samX = imageX * params.scale + CGFloat(params.padX)
    let samY = imageY * params.scale + CGFloat(params.padY)
    
    // 4. EdgeSAMは (height, width) = (y, x) フォーマット
    return CGPoint(x: samY, y: samX)  // !!注意: 逆順!!
}
```

### BBox → SAMプロンプト変換

```swift
func boundingBoxToSAMPrompt(startScreen: CGPoint, endScreen: CGPoint, ...) -> (coords: MLMultiArray, labels: MLMultiArray) {
    let topLeft = screenToSAMCoords(screenPoint: startScreen, ...)
    let bottomRight = screenToSAMCoords(screenPoint: endScreen, ...)
    
    // coords: shape [1, 2, 2] — 2点（左上、右下）
    // labels: [2, 3] — 2=BBox左上, 3=BBox右下
    ...
}
```

---

## EdgeSAM推論フロー

### Encoder（画像読み込み時に1回だけ実行）

```swift
// 1. 前処理
let (tensor, params) = imagePreprocessor.preprocess(image: selectedImage)

// 2. Encoder推論（~100ms on iPhone 14）
let encoderOutput = try edgeSAMEncoder.prediction(image: tensor)
let imageEmbedding = encoderOutput.imageEmbeddings  // 1×256×64×64

// 3. params と imageEmbedding をキャッシュ
// → ユーザーがBBox/ポイントを入力するたびにDecoderだけ再実行
```

### Decoder（ユーザー操作のたびに実行、~12ms）

```swift
// ユーザーのBBox or ポイントをSAM座標に変換
let (coords, labels) = coordinateConverter.toSAMPrompt(...)

// Decoder推論
let decoderOutput = try edgeSAMDecoder.prediction(
    imageEmbeddings: imageEmbedding,
    point_coords: coords,
    point_labels: labels
)
// → masks出力（256×256 or モデル固有サイズ）
```

**Decoder入出力の名前・型はXcodeの modelDescription で必ず現物確認。**

---

## マスク後処理（MaskPostprocessor）

### パイプライン

```
Decoder出力（256×256 logits or probability）
  ↓
1. パディング領域を除外
   - LetterboxParams の padX, padY から、
     マスク空間（256×256）での対応パディングを算出
   - pad_mask_x = padX * 256 / 1024
   - pad_mask_y = padY * 256 / 1024
   - 実画像に対応する領域だけ切り出し
  ↓
2. 元画像サイズへバイリニアリサイズ
  ↓
3. 閾値処理で二値化
   - logits出力なら: >= 0.0 → foreground
   - probability出力なら: >= 0.5 → foreground
   ★ 現物出力を確認して閾値を決定する
  ↓
4. CIImage変換（グレースケール、白=前景、黒=背景）
```

---

## ぼかし合成（BlurCompositor）

### パイプライン

```swift
func compositeBlur(original: CIImage, mask: CIImage, blurRadius: Float = 20.0) -> CIImage? {
    // 1. マスクリファイン
    //    - CIMorphologyMinimum (radius: 2) — エッジのフリンジ除去
    //    - CIGaussianBlur (radius: 4) on mask — エッジをフェザリング
    let refined = mask
        .applyingFilter("CIMorphologyMinimum", parameters: [kCIInputRadiusKey: 2.0])
        .clampedToExtent()
        .applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: 4.0])
        .cropped(to: original.extent)
    
    // 2. 背景ぼかし（★ clampedToExtent() を先に呼ぶ → グレーフリンジ防止）
    let blurred = original
        .clampedToExtent()
        .applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: blurRadius])
        .cropped(to: original.extent)
    
    // 3. 合成: 鮮明な前景 + ぼかし背景
    let blend = CIFilter.blendWithMask()
    blend.inputImage = original      // 鮮明
    blend.backgroundImage = blurred  // ぼかし
    blend.maskImage = refined        // 白=前景（鮮明）を表示
    return blend.outputImage
}
```

### ぼかしオプション（v2以降）

| フィルタ | 特徴 | 用途 |
|---------|------|------|
| `CIGaussianBlur` | 高速、均一なぼかし | デフォルト |
| `CIBokehBlur` | カメラレンズ風ボケ味、ringAmount/softness調整可 | プレミアム機能 |

---

## Visionフレームワーク（自動検出フォールバック）

```swift
// タップ時: Visionで自動セグメンテーション試行
let request = VNGenerateForegroundInstanceMaskRequest()
let handler = VNImageRequestHandler(ciImage: image)
try handler.perform([request])

if let result = request.results?.first {
    let instanceMask = result.instanceMask  // CVPixelBuffer, UInt8
    // タップ位置のピクセル値でインスタンスを特定
    let tappedInstance = readPixelValue(mask: instanceMask, at: imagePoint)
    
    if tappedInstance > 0 {
        // → そのインスタンスのマスクを生成して使用
        let mask = try result.generateScaledMaskForImage(
            forInstances: IndexSet(integer: Int(tappedInstance)),
            from: handler
        )
        // → BlurCompositorへ
    } else {
        // → 背景をタップした or 検出なし → BBox描画モードへ遷移
    }
}
```

**Visionは「ユーザー入力なしで被写体検出できる場合」のショートカット。検出できない場合はEdgeSAMにフォールバック。**

---

## UIインタラクション

### BBox描画

```swift
// EditorView内
.gesture(
    DragGesture(minimumDistance: 5)
        .onChanged { value in
            if !isDragging {
                boxStart = value.startLocation
                isDragging = true
            }
            boxEnd = value.location
        }
        .onEnded { _ in
            let (coords, labels) = coordinateConverter.boundingBoxToSAMPrompt(
                startScreen: boxStart, endScreen: boxEnd, ...
            )
            Task { await viewModel.runEdgeSAMDecoder(coords: coords, labels: labels) }
            isDragging = false
        }
)
```

### ポイント追加（選択の微調整）

- マスク生成後、ユーザーがタップで追加ポイントを指定
- 通常タップ → positive point（label=1）: 選択に追加
- 「除外モード」トグルON時 → negative point（label=0）: 選択から除外
- 追加ポイントのたびにBBox座標＋全ポイント座標をまとめてDecoderに渡す（~12ms）

### マスクオーバーレイ

- 選択領域外を半透明カラー（例: 黒50%）でオーバーレイ
- 選択領域の境界をハイライト（点線 or グロー）

### ぼかし強度調整

- スライダー（blurRadius: 5〜50）
- リアルタイムプレビュー（CIContextの再レンダリング）

---

## パフォーマンス目標（iPhone 14基準）

| 処理 | 目標 |
|------|------|
| EdgeSAM Encoder | < 200ms |
| EdgeSAM Decoder（1回のプロンプト） | < 20ms |
| Vision自動セグメンテーション | < 200ms |
| マスク後処理 | < 30ms |
| ぼかし合成（12MP画像） | < 100ms |
| **タップ→ぼかしプレビュー表示** | **< 500ms** |
| **BBox→マスク更新** | **< 50ms**（Decoder+後処理のみ） |

---

## 実装マイルストーン

### Phase 1: Vision自動検出MVP
- [ ] PHPickerで画像選択 → AspectFit表示
- [ ] タップ → VNGenerateForegroundInstanceMaskRequest でインスタンス検出
- [ ] マスク取得 → BlurCompositor でぼかし合成
- [ ] 結果プレビュー + 保存（UIActivityViewController）
- **ゴール**: Vision APIだけで「タップ→背景ぼかし」が動く最小アプリ

### Phase 2: EdgeSAM統合（コア機能）
- [ ] 変換済みCore MLモデル（Encoder/Decoder）をプロジェクトに追加
- [ ] Xcodeで modelDescription 確認、入出力名・型・shapeを記録
- [ ] ImagePreprocessor実装（CPU版: vImage + MLMultiArray）
  - [ ] letterbox変換（リサイズ+パディング）
  - [ ] RGB正規化（ImageNet mean/std）
  - [ ] LetterboxParams保持
- [ ] CoordinateConverter実装
  - [ ] 画面座標 → 画像座標 → SAM座標（h,w順）
  - [ ] BBox → SAMプロンプト（coords + labels）変換
- [ ] Encoder推論 + embedding キャッシュ
- [ ] Decoder推論 + マスク出力
- [ ] MaskPostprocessor実装
  - [ ] パディング除外 → リサイズ → 閾値処理
  - [ ] **出力がlogitsかprobabilityか現物確認して閾値決定**
- [ ] BBox描画UI（DragGesture）
- [ ] **検証**: 既知の画像でBBox→マスクの位置が正しいことを目視確認
- **ゴール**: 「BBoxを描く→対象が精密選択される→背景ぼかし」が動く

### Phase 3: インタラクション強化
- [ ] ポイント追加による選択微調整（positive/negative）
- [ ] マスクオーバーレイ表示（選択外を半透明着色）
- [ ] ぼかし強度スライダー
- [ ] Vision検出失敗時のEdgeSAMフォールバック自動遷移
- [ ] Undo/やり直し

### Phase 4: 最適化・収益化
- [ ] 前処理のMetal化（CPU→Metal compute kernel）
- [ ] CIBokehBlurオプション追加
- [ ] AdMob統合（バナー + インターステ）
- [ ] 広告削除IAP（¥480）
- [ ] App Store申請準備（スクリーンショット、説明文、プライバシーポリシー）

### Phase 5: 拡張（検討）
- [ ] EdgeTAMへの差し替え検証（精度比較）
- [ ] 複数オブジェクト選択対応
- [ ] ぼかし以外のエフェクト（モノクロ背景、背景差し替え等）

---

## ファイル構成

```
BokeFocus/
├── App/
│   └── BokeFocusApp.swift
├── Views/
│   ├── HomeView.swift
│   ├── EditorView.swift
│   ├── SelectionOverlayView.swift
│   ├── MaskOverlayView.swift
│   ├── ResultView.swift
│   └── Components/
│       ├── BlurSlider.swift
│       └── ModeToggle.swift          # positive/negativeポイント切替
├── ViewModels/
│   └── EditorViewModel.swift
├── Services/
│   ├── ImagePreprocessor.swift       # ★ letterbox + 正規化 + LetterboxParams
│   ├── CoordinateConverter.swift     # ★ 画面↔画像↔SAM座標変換
│   ├── EdgeSAMEngine.swift           # Core ML Encoder/Decoder推論
│   ├── VisionEngine.swift            # VNGenerateForegroundInstanceMaskRequest
│   ├── MaskPostprocessor.swift       # パディング除外 + リサイズ + 閾値処理
│   └── BlurCompositor.swift          # マスクリファイン + ぼかし + 合成
├── Models/
│   ├── EdgeSAMEncoder.mlpackage
│   └── EdgeSAMDecoder.mlpackage
├── Utilities/
│   ├── CIContextManager.swift        # 共有CIContext（Metal device）
│   └── MLMultiArrayExtensions.swift  # ヘルパー
├── Resources/
│   └── Assets.xcassets
└── Info.plist
```

---

## 既知のハマりポイント・注意事項

### 座標系の罠
1. **EdgeSAMのプロンプトは (height, width) = (y, x) 順**。通常の (x, y) と逆
2. **AspectFit表示のオフセット計算を忘れると選択がズレる**。画面座標をそのまま画像座標にしない
3. **letterboxのパディングはプロンプト座標にも適用する**。`ImagePreprocessor`が保持する`LetterboxParams`を使い回すこと

### モデル関連
4. **`.mlpackage`はunzipしてからXcodeに追加**
5. **入出力名・型はREADMEではなくXcodeの modelDescription が正**
6. **Decoder出力がlogitsかprobabilityか確認して閾値を決める**（logits→0.0, probability→0.5）
7. **IoU予測は信頼できない**ため、stability scoreでマスク選択する

### Core Image関連
8. **CIGaussianBlurの前に必ず `.clampedToExtent()` を呼ぶ**。忘れるとエッジにグレーフリンジが出る
9. **CIContextはアプリ起動時に1回だけ生成して再利用**。毎回生成するとメモリリーク的な挙動になる

### 開発順序
10. **最初はCPU実装で「マスクが正しく出る」ことを確認 → その後Metal化**。いきなりMetalだと「遅い」のか「間違ってる」のか切り分けられない
11. **SegmentAnythingMobileは前処理/後処理のMetal実装を参考にする。ただしモデル分割構造（3分割 vs 2分割）は異なるのでそのまま写経しない**

---

## 参考リソース

| リソース | 用途 |
|---------|------|
| [EdgeSAM公式](https://github.com/chongzhou96/EdgeSAM) | Core MLモデルDL、I/O仕様、変換スクリプト |
| [SegmentAnythingMobile](https://github.com/AlessandroToschi/SegmentAnythingMobile) | Metal前処理/後処理の実装参考 |
| [SAM2 Studio](https://github.com/huggingface/sam2-studio) | SwiftUI UXパターン（ポイント追加、BBox描画）の参考 |
| [Apple: Applying Visual Effects to Foreground Subjects](https://developer.apple.com/documentation/vision/applying-visual-effects-to-foreground-subjects) | Vision API + Core Image合成の公式サンプル |
| [EdgeTAM](https://github.com/facebookresearch/EdgeTAM) | 将来のモデル差し替え候補（CVPR 2025, Apache 2.0） |
