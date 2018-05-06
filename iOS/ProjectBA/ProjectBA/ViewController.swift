//
//  ViewController.swift
//  ProjectBA
//
//  Created by Tolga Haliloğlu on 6.05.2018.
//  Copyright © 2018 BA. All rights reserved.
//

import UIKit
import ARKit
import Vision

class ViewController: UIViewController, ARSKViewDelegate, ARSessionDelegate {

    @IBOutlet weak var sceneView: ARSKView!
    @IBOutlet weak var statusTextView: UITextView!
    @IBOutlet weak var refreshButton: UIButton!
    
    // MARK: - View controller lifecycle
    override func viewDidLoad() {
        super.viewDidLoad()
        // Do any additional setup after loading the view, typically from a nib.
        
        let overlayScene = SKScene()
        overlayScene.scaleMode = .aspectFill
        sceneView.delegate = self
        sceneView.presentScene(overlayScene)
        sceneView.session.delegate = self
        
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        let configuration = ARWorldTrackingConfiguration()
        sceneView.session.run(configuration)
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        
        sceneView.session.pause()
    }
    
    // MARK: - ARSessionDelegate
    var currentBuffer: CVPixelBuffer?
    let visionQueue = DispatchQueue(label: "com.ba.ProjectBA.visionQueue", qos: .userInitiated)
    
    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        
        guard currentBuffer == nil, case .normal = frame.camera.trackingState else {
            return
        }
        
        self.currentBuffer = frame.capturedImage
        classifyCurrentImage()
    }
    
    func classifyCurrentImage() {
        let orientation = CGImagePropertyOrientation(rawValue: UInt32(UIDevice.current.orientation.rawValue))
        let requestHandler = VNImageRequestHandler(cvPixelBuffer: currentBuffer!, orientation: orientation!)
        visionQueue.async {
            do {
                defer { self.currentBuffer = nil }
                try requestHandler.perform([self.classificationRequest])
            } catch {
                print("Error: Vision request failed with error \"\(error)\"")
            }
        }
    }
    
    // MARK: - Vision classification
    private var identifierString = ""
    private var confidence: VNConfidence = 0.0
    
    lazy var classificationRequest:VNCoreMLRequest = {
        do {
            let model = try VNCoreMLModel(for: Inceptionv3().model)
            let request = VNCoreMLRequest(model: model, completionHandler: { [weak self] request, error in
                self?.processClassifications(for: request, error: error)
            })
            
            request.imageCropAndScaleOption = .centerCrop
            request.usesCPUOnly = true
            
            return request
        } catch {
            fatalError("Failed to load Vision ML model: \(error)")
        }
    }()
    
    func processClassifications(for request: VNRequest, error: Error?) {
        guard let results = request.results else {
            print("Unable to classify image.\n\(error!.localizedDescription)")
            return
        }
        
        let classifications = results as! [VNClassificationObservation]
        
        if let bestResult = classifications.first(where: { result in result.confidence > 0.5 }),
            let label = bestResult.identifier.split(separator: ",").first {
            identifierString = String(label)
            confidence = bestResult.confidence
        } else {
            identifierString = ""
            confidence = 0
        }
        
        DispatchQueue.main.async { [weak self] in
            self?.logClassifierResults()
        }
    }
    
    func logClassifierResults() {
        guard !self.identifierString.isEmpty else {
            return
        }
        let message = String(format: "Detected \(self.identifierString) with %.2f", self.confidence * 100) + "% confidence"
        print(message)
        statusTextView.text = message
    }
    
    // MARK: - Tap gesture handler & ARSKViewDelegate
    var anchorLabels = [UUID: String]()
    
    @IBAction func placeLabelAtLocation(_ sender: UITapGestureRecognizer) {
        let hitLocationInView = sender.location(in: sceneView)
        let hitTestResults = sceneView.hitTest(hitLocationInView, types: [.featurePoint, .estimatedHorizontalPlane])
        
        if let result = hitTestResults.first {
            let anchor = ARAnchor(transform: result.worldTransform)
            sceneView.session.add(anchor: anchor)
            
            anchorLabels[anchor.identifier] = identifierString
        }
    }
    
    func view(_ view: ARSKView, didAdd node: SKNode, for anchor: ARAnchor) {
        guard let labelText = anchorLabels[anchor.identifier] else {
            fatalError("missing expected associated label for anchor")
        }
        
        let label = TemplateLabelNode(text: labelText)
        node.addChild(label)
    }
    
    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }


}

