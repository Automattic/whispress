import Foundation

enum ElevenLabsClientError: LocalizedError {
    case missingAPIKey
    case missingVoice
    case requestFailed(Int, String)
    case invalidResponse(String)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "Add an ElevenLabs API key before using ElevenLabs speech."
        case .missingVoice:
            return "Choose an ElevenLabs voice before using ElevenLabs speech."
        case .requestFailed(let statusCode, let details):
            return "ElevenLabs request failed with status \(statusCode): \(details)"
        case .invalidResponse(let details):
            return "Invalid ElevenLabs response: \(details)"
        }
    }
}

struct ElevenLabsVoiceOption: Identifiable, Equatable {
    let id: String
    let name: String
    let category: String?

    var displayName: String {
        guard let category, !category.isEmpty else { return name }
        return "\(name) (\(category.capitalized))"
    }
}

final class ElevenLabsClient {
    private struct VoicesResponse: Decodable {
        let voices: [Voice]
        let hasMore: Bool?
        let nextPageToken: String?

        private enum CodingKeys: String, CodingKey {
            case voices
            case hasMore = "has_more"
            case nextPageToken = "next_page_token"
        }
    }

    private struct Voice: Decodable {
        let voiceID: String
        let name: String
        let category: String?

        private enum CodingKeys: String, CodingKey {
            case voiceID = "voice_id"
            case name
            case category
        }

        var option: ElevenLabsVoiceOption {
            ElevenLabsVoiceOption(id: voiceID, name: name, category: category)
        }
    }

    private struct SpeechRequest: Encodable {
        let text: String
        let modelID: String

        private enum CodingKeys: String, CodingKey {
            case text
            case modelID = "model_id"
        }
    }

    private let session = URLSession(configuration: .ephemeral)

    func fetchVoices(apiKey: String) async throws -> [ElevenLabsVoiceOption] {
        let apiKey = normalizedAPIKey(apiKey)
        guard !apiKey.isEmpty else { throw ElevenLabsClientError.missingAPIKey }

        var voices: [ElevenLabsVoiceOption] = []
        var nextPageToken: String?

        repeat {
            var components = URLComponents(string: "https://api.elevenlabs.io/v2/voices")!
            var queryItems = [
                URLQueryItem(name: "page_size", value: "100"),
                URLQueryItem(name: "sort", value: "name"),
                URLQueryItem(name: "sort_direction", value: "asc"),
                URLQueryItem(name: "include_total_count", value: "false")
            ]
            if let nextPageToken {
                queryItems.append(URLQueryItem(name: "next_page_token", value: nextPageToken))
            }
            components.queryItems = queryItems

            guard let url = components.url else {
                throw ElevenLabsClientError.invalidResponse("Could not build voices URL")
            }

            var request = URLRequest(url: url)
            request.setValue(apiKey, forHTTPHeaderField: "xi-api-key")
            request.setValue("application/json", forHTTPHeaderField: "Accept")

            let (data, response) = try await session.data(for: request)
            try validate(response: response, data: data)
            let decoded = try JSONDecoder().decode(VoicesResponse.self, from: data)
            voices.append(contentsOf: decoded.voices.map(\.option))

            if decoded.hasMore == true, let token = decoded.nextPageToken, !token.isEmpty {
                nextPageToken = token
            } else {
                nextPageToken = nil
            }
        } while nextPageToken != nil

        return voices.sorted {
            $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
        }
    }

    func synthesizeSpeech(text: String, voiceID: String, apiKey: String) async throws -> Data {
        let apiKey = normalizedAPIKey(apiKey)
        let voiceID = voiceID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !apiKey.isEmpty else { throw ElevenLabsClientError.missingAPIKey }
        guard !voiceID.isEmpty else { throw ElevenLabsClientError.missingVoice }

        var components = URLComponents(
            url: URL(string: "https://api.elevenlabs.io")!
                .appendingPathComponent("v1")
                .appendingPathComponent("text-to-speech")
                .appendingPathComponent(voiceID),
            resolvingAgainstBaseURL: false
        )!
        components.queryItems = [
            URLQueryItem(name: "output_format", value: "mp3_44100_128")
        ]

        guard let url = components.url else {
            throw ElevenLabsClientError.invalidResponse("Could not build text-to-speech URL")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 60
        request.setValue(apiKey, forHTTPHeaderField: "xi-api-key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("audio/mpeg", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONEncoder().encode(
            SpeechRequest(text: text, modelID: "eleven_multilingual_v2")
        )

        let (data, response) = try await session.data(for: request)
        try validate(response: response, data: data)
        guard !data.isEmpty else {
            throw ElevenLabsClientError.invalidResponse("No audio returned")
        }
        return data
    }

    private func normalizedAPIKey(_ apiKey: String) -> String {
        apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func validate(response: URLResponse, data: Data) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ElevenLabsClientError.invalidResponse("No HTTP response")
        }
        guard (200...299).contains(httpResponse.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw ElevenLabsClientError.requestFailed(httpResponse.statusCode, body)
        }
    }
}
