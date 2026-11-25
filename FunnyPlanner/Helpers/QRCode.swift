//
//  QRCode.swift
//  FunnyPlanner
//
//  Gera um QR code (CGImage) para o link da sala, sem depender de AppKit/UIKit,
//  via CoreImage — assim o mesmo código serve em qualquer plataforma Apple.
//

import CoreImage
import CoreImage.CIFilterBuiltins

enum QRCode {
    static func cgImage(from string: String) -> CGImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(string.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage else { return nil }
        let scaled = output.transformed(by: CGAffineTransform(scaleX: 10, y: 10))
        return CIContext().createCGImage(scaled, from: scaled.extent)
    }
}
