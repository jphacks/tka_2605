//
//  CameraManager.swift
//  app
//
//  Created by tknooa on 2026/10/17.
//

import AVFoundation
import SwiftUI


@Observable
class CameraManager: NSObject, AVCapturePhotoCaptureDelegate {
    let session = AVCaptureSession()
    private var photoOutput = AVCapturePhotoOutput()
    private var photoAction: ((UIImage) -> Void)?
    
    var capturedImage: UIImage?
    
    override init() {
        super.init()
        self.photoAction = nil
    }

    func start() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            configureAndStart()

        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) {
                [weak self] granted in

                guard granted else { return }

                self?.configureAndStart()
            }

        default:
            print("カメラへのアクセスが許可されていません")
        }
    }

    private func configureAndStart() {
        guard !session.isRunning else { return }

        session.beginConfiguration()
        session.sessionPreset = .photo

        defer {
            session.commitConfiguration()

            DispatchQueue.global(qos: .userInitiated).async {
                self.session.startRunning()
            }
        }

        guard
            let device = AVCaptureDevice.default(
                .builtInWideAngleCamera,
                for: .video,
                position: .back
            ),
            let input = try? AVCaptureDeviceInput(device: device),
            session.canAddInput(input),
            session.canAddOutput(photoOutput)
        else {
            print("カメラを初期化できません")
            return
        }

        session.addInput(input)
        session.addOutput(photoOutput)
    }

    func takePhoto(action: @escaping (UIImage) -> Void) {
        let settings = AVCapturePhotoSettings()
        photoOutput.capturePhoto(
            with: settings,
            delegate: self
        )
        photoAction = action
    }

    func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishProcessingPhoto photo: AVCapturePhoto,
        error: Error?
    ) {
        guard
            error == nil,
            let data = photo.fileDataRepresentation(),
            let image = UIImage(data: data),
            let cropped = croppedImage(image)
        else {
            return
        }

        DispatchQueue.main.async {
            self.capturedImage = cropped
            if let action = self.photoAction {
                action(cropped)
            }
        }
    }
    
    private func croppedImage(
        _ image: UIImage
    ) -> UIImage? {
        let aspectRatio: CGFloat = 1.0
        
        // UIImageの向きを正規化する
        let size = image.size

        let renderer = UIGraphicsImageRenderer(size: size)
        let normalizedImage = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }

        guard let cgImage = normalizedImage.cgImage else {
            return nil
        }

        let width = CGFloat(cgImage.width)
        let height = CGFloat(cgImage.height)
        let currentRatio = width / height

        let cropRect: CGRect

        if currentRatio > aspectRatio {
            // 横幅を切り取る
            let newWidth = height * aspectRatio
            cropRect = CGRect(
                x: (width - newWidth) / 2,
                y: 0,
                width: newWidth,
                height: height
            )
        } else {
            // 高さを切り取る
            let newHeight = width / aspectRatio
            cropRect = CGRect(
                x: 0,
                y: (height - newHeight) / 2,
                width: width,
                height: newHeight
            )
        }

        guard let cropped = cgImage.cropping(to: cropRect.integral) else {
            return nil
        }

        return UIImage(
            cgImage: cropped,
            scale: normalizedImage.scale,
            orientation: .up
        )
    }
}
