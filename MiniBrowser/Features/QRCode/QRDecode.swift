import UIKit
import CoreImage

// MARK: - 二维码识别（从静态图片）
extension QRCode {
    /// 用 CIDetector 从一张图片中识别二维码，返回首个命中的字符串内容。
    /// 无二维码或图片不可用时返回 nil（调用方据此提示「未识别到」）。
    static func decode(from image: UIImage) -> String? {
        guard let ciImage = CIImage(image: image) else { return nil }
        let context = CIContext()
        let detector = CIDetector(ofType: CIDetectorTypeQRCode,
                                  context: context,
                                  options: [CIDetectorAccuracy: CIDetectorAccuracyHigh])
        let features = detector?.features(in: ciImage) ?? []
        for case let qr as CIQRCodeFeature in features {
            if let message = qr.messageString, !message.isEmpty { return message }
        }
        return nil
    }
}
