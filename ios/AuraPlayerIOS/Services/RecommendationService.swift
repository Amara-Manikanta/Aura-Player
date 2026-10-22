import Foundation

public actor RecommendationService {
    public static let shared = RecommendationService()
    
    public struct Suggestion: Codable, Identifiable, Hashable, Sendable {
        public var id: String { videoId }
        public let videoId: String
        public let title: String
        public let channel: String
        public let duration: Double
        public let score: Double
        public let becauseOf: String
        public let seedCount: Int
    }
    
    private struct Saved: Codable {
        var generatedAt: Date
        var suggestions: [Suggestion]
    }
    
    public func loadSuggestions() -> [Suggestion] {
        if let bundleURL = Bundle.main.url(forResource: "for_you", withExtension: "json", subdirectory: "Resources") ??
                           Bundle.main.url(forResource: "for_you", withExtension: "json") {
            if let data = try? Data(contentsOf: bundleURL),
               let saved = try? JSONDecoder().decode(Saved.self, from: data) {
                return saved.suggestions
            }
        }
        return []
    }
}
