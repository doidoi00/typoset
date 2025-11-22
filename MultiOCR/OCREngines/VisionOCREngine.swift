//
//  VisionOCREngine.swift
//  MultiOCR
//
//  Apple Vision Framework OCR implementation
//

import Foundation
import Vision
import AppKit

class VisionOCREngine: OCREngine {
    let engineType: OCREngineType = .vision
    
    func performOCR(on image: NSImage, completion: @escaping (Result<String, OCRError>) -> Void) {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            completion(.failure(.invalidImage))
            return
        }
        
        let request = VNRecognizeTextRequest { request, error in
            if let error = error {
                completion(.failure(.processingFailed(error.localizedDescription)))
                return
            }
            
            guard let observations = request.results as? [VNRecognizedTextObservation] else {
                completion(.failure(.processingFailed("No text found")))
                return
            }
            
            let recognizedText = observations.compactMap { observation in
                observation.topCandidates(1).first?.string
            }.joined(separator: "\n")
            
            if recognizedText.isEmpty {
                completion(.failure(.processingFailed("No text recognized")))
            } else {
                completion(.success(recognizedText))
            }
        }
        
        // Configure request for best accuracy
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.recognitionLanguages = ["en-US", "ko-KR"] // English and Korean
        
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try handler.perform([request])
            } catch {
                completion(.failure(.processingFailed(error.localizedDescription)))
            }
        }
    }
}
