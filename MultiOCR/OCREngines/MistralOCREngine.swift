//
//  MistralOCREngine.swift
//  MultiOCR
//
//  Mistral AI Vision OCR implementation
//

import Foundation
import AppKit

class MistralOCREngine: OCREngine {
    let engineType: OCREngineType = .mistral
    private let apiEndpoint = "https://api.mistral.ai/v1/chat/completions"
    
    func performOCR(on image: NSImage, completion: @escaping (Result<String, OCRError>) -> Void) {
        guard let apiKey = SettingsManager.shared.mistralAPIKey, !apiKey.isEmpty else {
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
            "model": "pixtral-12b-2409",
            "messages": [
                [
                    "role": "user",
                    "content": [
                        [
                            "type": "text",
                            "text": "Extract all text from this image. Return only the extracted text without any additional commentary or formatting."
                        ],
                        [
                            "type": "image_url",
                            "image_url": "data:image/png;base64,\(base64Image)"
                        ]
                    ]
                ]
            ]
        ]
        
        guard let url = URL(string: apiEndpoint) else {
            completion(.failure(.apiError("Invalid API endpoint")))
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        
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
                   let choices = json["choices"] as? [[String: Any]],
                   let firstChoice = choices.first,
                   let message = firstChoice["message"] as? [String: Any],
                   let content = message["content"] as? String {
                    completion(.success(content.trimmingCharacters(in: .whitespacesAndNewlines)))
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
