//
//  GeminiOCREngine.swift
//  MultiOCR
//
//  Gemini Vision AI OCR implementation
//

import Foundation
import AppKit

class GeminiOCREngine: OCREngine {
    let engineType: OCREngineType = .gemini
    private let apiEndpoint = "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash-exp:generateContent"
    
    func performOCR(on image: NSImage, completion: @escaping (Result<String, OCRError>) -> Void) {
        guard let apiKey = SettingsManager.shared.geminiAPIKey, !apiKey.isEmpty else {
            completion(.failure(.apiKeyMissing))
            return
        }
        
        guard let imageData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: imageData),
              let pngData = bitmap.representation(using: .png, properties: [:]) else {
            completion(.failure(.invalidImage))
            return
        }
        
        let base64Image = pngData.base64EncodedString()
        
        let requestBody: [String: Any] = [
            "contents": [
                [
                    "parts": [
                        [
                            "text": "Extract all text from this image. Return only the extracted text without any additional commentary or formatting."
                        ],
                        [
                            "inline_data": [
                                "mime_type": "image/png",
                                "data": base64Image
                            ]
                        ]
                    ]
                ]
            ]
        ]
        
        guard let url = URL(string: "\(apiEndpoint)?key=\(apiKey)") else {
            completion(.failure(.apiError("Invalid API endpoint")))
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        } catch {
            completion(.failure(.processingFailed(error.localizedDescription)))
            return
        }
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                completion(.failure(.networkError(error)))
                return
            }
            
            guard let data = data else {
                completion(.failure(.apiError("No data received")))
                return
            }
            
            do {
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let candidates = json["candidates"] as? [[String: Any]],
                   let firstCandidate = candidates.first,
                   let content = firstCandidate["content"] as? [String: Any],
                   let parts = content["parts"] as? [[String: Any]],
                   let firstPart = parts.first,
                   let text = firstPart["text"] as? String {
                    completion(.success(text.trimmingCharacters(in: .whitespacesAndNewlines)))
                } else if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                          let error = json["error"] as? [String: Any],
                          let message = error["message"] as? String {
                    completion(.failure(.apiError(message)))
                } else {
                    completion(.failure(.apiError("Unexpected response format")))
                }
            } catch {
                completion(.failure(.processingFailed(error.localizedDescription)))
            }
        }.resume()
    }
}
