//
//  ViewController.swift
//  Vision Face Detection
//
//

import UIKit
import AVFoundation
import Vision

final class ViewController: UIViewController {
    var session: AVCaptureSession?
    let shapeLayer = CAShapeLayer()
    
    @IBOutlet weak var accView: UIView!
    @IBOutlet weak var cameraView: UIView!
    
    let faceDetectionRequest = VNDetectFaceRectanglesRequest()
    let faceDetectionRequestHandler = VNSequenceRequestHandler()
    
    let faceLandmarksRequest = VNDetectFaceLandmarksRequest()
    let faceLandmarksDetectionRequestHandler = VNSequenceRequestHandler()
    
    let leftEyeView = UIImageView(image: UIImage(named: "coeur"))
    let rightEyeView = UIImageView(image: UIImage(named: "coeur"))
    let noseView = UIImageView(image: UIImage(named: "noseDog"))
    let tongueView = UIImageView(image: UIImage(named: "tongueDog"))
    
    lazy var previewLayer: AVCaptureVideoPreviewLayer? = {
        guard let session = self.session else { return nil }
        
        var previewLayer = AVCaptureVideoPreviewLayer(session: session)
        previewLayer.videoGravity = .resizeAspectFill
        
        return previewLayer
    }()
    
    var frontCamera: AVCaptureDevice? = {
        return AVCaptureDevice.default(AVCaptureDevice.DeviceType.builtInWideAngleCamera, for: AVMediaType.video, position: .front)
    }()
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        sessionPrepare()
        session?.startRunning()
        
        accView.addSubview(tongueView)
        accView.addSubview(noseView)
        accView.addSubview(leftEyeView)
        accView.addSubview(rightEyeView)
        //        leftEyeView.backgroundColor = UIColor.black
        //        rightEyeView.backgroundColor = UIColor.red
        
        leftEyeView.contentMode = .scaleAspectFill
        rightEyeView.contentMode = .scaleAspectFill
        tongueView.contentMode = .scaleAspectFill
        noseView.contentMode = .scaleAspectFit
        
        leftEyeView.alpha = 0.5
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        
        DispatchQueue.main.async {
            self.previewLayer?.frame = self.cameraView.bounds
            self.shapeLayer.frame = self.cameraView.bounds
        }
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard let previewLayer = previewLayer else { return }
        
        cameraView.layer.addSublayer(previewLayer)
        
        //Vision uses a flipped coordinate system
        shapeLayer.setAffineTransform(CGAffineTransform(scaleX: -1, y: -1))
        accView.transform = CGAffineTransform(scaleX: -1, y: -1)
    }
    
    func sessionPrepare() {
        session = AVCaptureSession()
        guard let session = session, let captureDevice = frontCamera else { return }
        
        do {
            let deviceInput = try AVCaptureDeviceInput(device: captureDevice)
            session.beginConfiguration()
            
            if session.canAddInput(deviceInput) {
                session.addInput(deviceInput)
            }
            
            let output = AVCaptureVideoDataOutput()
            output.videoSettings = [
                String(kCVPixelBufferPixelFormatTypeKey) : Int(kCVPixelFormatType_420YpCbCr8BiPlanarFullRange)
            ]
            
            output.alwaysDiscardsLateVideoFrames = true
            
            if session.canAddOutput(output) {
                session.addOutput(output)
            }
            
            session.commitConfiguration()
            let queue = DispatchQueue(label: "output.queue")
            output.setSampleBufferDelegate(self, queue: queue)
            print("setup delegate")
        } catch {
            print("can't setup session")
        }
    }
}

extension ViewController: AVCaptureVideoDataOutputSampleBufferDelegate {
    
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        
        let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer)
        
        let attachments = CMCopyDictionaryOfAttachments(kCFAllocatorDefault, sampleBuffer, kCMAttachmentMode_ShouldPropagate)
        let ciImage = CIImage(cvImageBuffer: pixelBuffer!, options: attachments as! [String : Any]?)
        
        //leftMirrored for front camera
        let ciImageWithOrientation = ciImage.oriented(forExifOrientation: Int32(UIImageOrientation.leftMirrored.rawValue))
        
        detectFace(on: ciImageWithOrientation)
    }
    
}

extension ViewController {
    
    func detectFace(on image: CIImage) {
        try? faceDetectionRequestHandler.perform([faceDetectionRequest], on: image)
        if let results = faceDetectionRequest.results as? [VNFaceObservation] {
            if !results.isEmpty {
                faceLandmarksRequest.inputFaceObservations = results
                detectLandmarks(on: image)
                
                DispatchQueue.main.async {
                    self.shapeLayer.sublayers?.removeAll()
                }
            }
        }
    }
    
    func detectLandmarks(on image: CIImage) {
        try? faceLandmarksDetectionRequestHandler.perform([faceLandmarksRequest], on: image)
        if let landmarksResults = faceLandmarksRequest.results as? [VNFaceObservation] {
            
            for observation in landmarksResults {
                
                DispatchQueue.main.async {
                    if let boundingBox = self.faceLandmarksRequest.inputFaceObservations?.first?.boundingBox {
                        let faceBoundingBox = boundingBox.scaled(to: self.cameraView.bounds.size)
                        self.drawBox(rect: faceBoundingBox)
                        
                        let leftEye = observation.landmarks?.leftEye
                        self.translateFaceItem(usingLandmark: leftEye,
                                               bound: faceBoundingBox,
                                               view: self.leftEyeView)
                        
                        let rightEye = observation.landmarks?.rightEye
                        self.translateFaceItem(usingLandmark: rightEye,
                                               bound: faceBoundingBox,
                                               view: self.rightEyeView)
                        
                        let nose = observation.landmarks?.nose
                        self.translateFaceItem(usingLandmark: nose,
                                               bound: faceBoundingBox,
                                               view: self.noseView)
                        
                        let lips = observation.landmarks?.innerLips
                        self.translateFaceItem(usingLandmark: lips,
                                               bound: faceBoundingBox,
                                               view: self.tongueView)
                        
                        //                        self.convertPointsForFace(lips, faceBoundingBox, color: .purple)
                        //
                        //                        let leftEyebrow = observation.landmarks?.leftEyebrow
                        //                        self.convertPointsForFace(leftEyebrow, faceBoundingBox, color: .cyan)
                        //
                        //                        let rightEyebrow = observation.landmarks?.rightEyebrow
                        //                        self.convertPointsForFace(rightEyebrow, faceBoundingBox, color: .yellow)
                        //
                        //                        let noseCrest = observation.landmarks?.noseCrest
                        //                        self.convertPointsForFace(noseCrest, faceBoundingBox, color: .magenta)
                        //
                        //                        let outerLips = observation.landmarks?.outerLips
                        //                        self.convertPointsForFace(outerLips, faceBoundingBox, color: .brown)
                    }
                }
            }
        }
    }
    
    func translateFaceItem(usingLandmark landmark: VNFaceLandmarkRegion2D?, bound boundingBox: CGRect, view:UIView) {
        if let points = landmark?.normalizedPoints {
            let faceLandmarkPoints = points.map { (point: CGPoint) -> (x: CGFloat, y: CGFloat) in
                let pointX = (point.x * boundingBox.width + boundingBox.origin.x)
                let pointY = (point.y * boundingBox.height + boundingBox.origin.y)
                
                return (x: pointX, y: pointY)
            }
            
            var minX:CGFloat = 0
            var maxX:CGFloat = 0
            var minY:CGFloat = 0
            var maxY:CGFloat = 0
            
            for (index, point) in faceLandmarkPoints.enumerated() {
                if index == 0 {
                    minX = point.x; maxX = point.x
                    minY = point.y; maxY = point.y
                    continue
                }
                
                minX = min(minX, point.x)
                maxX = max(maxX, point.x)
                
                minY = min(minY, point.y)
                maxY = max(maxY, point.y)
            }
            let inset = UIEdgeInsetsMake(10, 10, 10, 10)
            let rect = CGRect(x: minX - inset.left,
                              y: minY - inset.bottom,
                              width: (maxX - minX) + (inset.left + inset.right),
                              height: (maxY - minY) + (inset.top + inset.bottom))
            
            drawBox(rect: rect)
            
            view.transform = CGAffineTransform(rotationAngle: CGFloat.pi)
            view.frame = rect
            
            view.superview?.bringSubview(toFront: view)
        }
        
    }
    
    func drawLandmark(_ landmark: VNFaceLandmarkRegion2D?, _ boundingBox: CGRect, color:UIColor) {
        if let points = landmark?.normalizedPoints {
            let faceLandmarkPoints = points.map { (point: CGPoint) -> CGPoint in
                let pointX = point.x * boundingBox.width + boundingBox.origin.x
                let pointY = point.y * boundingBox.height + boundingBox.origin.y
                
                return CGPoint(x: pointX, y: pointY)
            }
            
            DispatchQueue.main.async {
                self.draw(points: faceLandmarkPoints, color: color)
            }
        }
    }
    
    func drawBox(rect:CGRect) {
        DispatchQueue.main.async {
            let newLayer = CAShapeLayer()
            newLayer.strokeColor = UIColor.red.cgColor
            newLayer.lineWidth = 2.0
            
            let path = UIBezierPath(rect: rect)
            path.stroke()
            
            newLayer.path = path.cgPath
            
            self.shapeLayer.addSublayer(newLayer)
        }
    }
    
    func draw(points: [CGPoint], color:UIColor) {
        let newLayer = CAShapeLayer()
        newLayer.strokeColor = color.cgColor
        newLayer.fillColor = color.cgColor
        newLayer.lineWidth = 2.0
        
        let path = UIBezierPath()
        path.move(to: CGPoint(x: points[0].x, y: points[0].y))
        for i in 0..<points.count - 1 {
            let point = CGPoint(x: points[i].x, y: points[i].y)
            path.addLine(to: point)
            path.move(to: point)
        }
        path.addLine(to: CGPoint(x: points[0].x, y: points[0].y))
        path.close()
        path.fill()
        
        newLayer.path = path.cgPath
        
        shapeLayer.addSublayer(newLayer)
    }
    
    
    //    func convert(_ points: UnsafePointer<vector_float2>, with count: Int) -> [(x: CGFloat, y: CGFloat)] {
    //        var convertedPoints = [(x: CGFloat, y: CGFloat)]()
    //        for i in 0...count {
    //            convertedPoints.append((CGFloat(points[i].x), CGFloat(points[i].y)))
    //        }
    //
    //        return convertedPoints
    //    }
}
