//
//  ResultView.swift
//  MultiOCR
//
//  View to display OCR results
//

import SwiftUI

struct ResultView: View {
    let result: OCRResult
    @Environment(\.presentationMode) var presentationMode
    
    var body: some View {
        VStack(spacing: 20) {
            Text("OCR Result")
                .font(.headline)
            
            TextEditor(text: .constant(result.text))
                .font(.body)
                .padding(5)
                .background(Color(NSColor.textBackgroundColor))
                .cornerRadius(5)
            
            HStack {
                Button("Close") {
                    presentationMode.wrappedValue.dismiss()
                }
                .keyboardShortcut(.cancelAction)
                
                Spacer()
                
                Button("Copy") {
                    let pasteboard = NSPasteboard.general
                    pasteboard.clearContents()
                    pasteboard.setString(result.text, forType: .string)
                }
                .keyboardShortcut("c", modifiers: .command)
            }
        }
        .padding()
        .frame(minWidth: 400, minHeight: 300)
    }
}
