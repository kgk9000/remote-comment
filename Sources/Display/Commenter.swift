import Foundation

struct Comment {
    let text: String
    let timestamp: Date
    let imageURL: URL
}

enum Commenter {

    static func comment(on imageURL: URL) async throws -> Comment {
        guard let cStr = getenv("ANTHROPIC_API_KEY"), let apiKey = String(validatingUTF8: cStr) else {
            throw CommentError.noApiKey
        }

        let imageData = try Data(contentsOf: imageURL)
        let base64Image = imageData.base64EncodedString()

        let systemPrompt = """
        You are a friendly, ambient coding assistant. You're looking at a screenshot of someone's \
        screen while they work on code. Give a brief, helpful comment about what you see — what \
        they might want to do next, something they might have missed, or an encouraging observation. \
        Keep it short (2-4 sentences), conversational, and useful. Don't be judgmental. \
        If you can't see any code, just comment on what you see.
        """

        let url = URL(string: "https://api.anthropic.com/v1/messages")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")

        let body: [String: Any] = [
            "model": "claude-sonnet-4-20250514",
            "max_tokens": 300,
            "system": systemPrompt,
            "messages": [
                [
                    "role": "user",
                    "content": [
                        [
                            "type": "image",
                            "source": [
                                "type": "base64",
                                "media_type": "image/jpeg",
                                "data": base64Image,
                            ],
                        ],
                        [
                            "type": "text",
                            "text": "What do you notice about what I'm working on?",
                        ],
                    ],
                ]
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
