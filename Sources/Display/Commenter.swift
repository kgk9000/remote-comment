import Foundation

struct Comment {
    let text: String
    let timestamp: Date
    let imageURL: URL
}

enum Commenter {

    /// Send a screenshot + its OCR text to Claude and get a code comment back.
    /// The OCR text file is expected at the same path as the image but with a .txt extension.
    static func comment(on imageURL: URL) async throws -> Comment {
        guard let cStr = getenv("ANTHROPIC_API_KEY"), let apiKey = String(validatingUTF8: cStr) else {
            throw CommentError.noApiKey
        }

        let imageData = try Data(contentsOf: imageURL)
        let base64Image = imageData.base64EncodedString()
        let mediaType = imageURL.pathExtension == "png" ? "image/png" : "image/jpeg"

        // Load the OCR text if available (same filename, .txt extension).
        let txtURL = imageURL.deletingPathExtension().appendingPathExtension("txt")
        let ocrText = (try? String(contentsOf: txtURL, encoding: .utf8)) ?? ""

        let systemPrompt = """
        You are a friendly, ambient coding assistant. You're looking at a screenshot of \
        someone's screen, along with OCR-extracted text from that screenshot.

        Use the OCR text to read the code accurately — don't guess from the image. \
        The image is provided for visual context (layout, which app, etc.).

        If you can see code, copy THEIR code exactly as written, but fix any bugs or \
        issues you spot. Mark each fix with a brief inline comment explaining the change. \
        Do not rewrite their code or add new functions — only correct what's there.

        If there's no code visible, give a brief, helpful comment about what you see.

        Keep it concise and useful. Don't be judgmental.
        """

        // Build the user message: image + OCR text.
        var userContent: [[String: Any]] = [
            [
                "type": "image",
                "source": [
                    "type": "base64",
                    "media_type": mediaType,
                    "data": base64Image,
                ],
            ],
        ]

        if !ocrText.isEmpty {
            userContent.append([
                "type": "text",
                "text": "OCR text from the screenshot:\n\n\(ocrText)",
            ])
        }

        userContent.append([
            "type": "text",
            "text": "What do you notice about what I'm working on?",
        ])

        let url = URL(string: "https://api.anthropic.com/v1/messages")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")

        let body: [String: Any] = [
            "model": "claude-sonnet-4-20250514",
            "max_tokens": 1024,
            "system": systemPrompt,
            "messages": [
                ["role": "user", "content": userContent],
            ],
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            let text = String(data: data, encoding: .utf8) ?? "unknown error"
            throw CommentError.apiError(text)
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let content = json["content"] as? [[String: Any]],
              let first = content.first,
              let text = first["text"] as? String else {
            throw CommentError.apiError("Unexpected response format")
        }

        return Comment(text: text, timestamp: Date(), imageURL: imageURL)
    }
}

enum CommentError: LocalizedError {
    case noApiKey
    case apiError(String)

    var errorDescription: String? {
        switch self {
        case .noApiKey:
            return "Set ANTHROPIC_API_KEY environment variable"
        case .apiError(let msg):
            return "API error: \(msg)"
        }
    }
}
