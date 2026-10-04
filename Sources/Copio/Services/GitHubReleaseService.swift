import Foundation

enum GitHubReleaseStatus {
    case available
    case noRelease
    case missingAppcast
}

enum GitHubReleaseService {
    private struct Release: Decodable {
        struct Asset: Decodable { let name: String }
        let assets: [Asset]
    }

    static func latestStatus() async throws -> GitHubReleaseStatus {
        let url = URL(string: "https://api.github.com/repos/Bes-js/Copio/releases/latest")!
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("Copio", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        if response.statusCode == 404 { return .noRelease }
        guard (200..<300).contains(response.statusCode) else { throw URLError(.badServerResponse) }
        let release = try JSONDecoder().decode(Release.self, from: data)
        return release.assets.contains(where: { $0.name == "appcast.xml" }) ? .available : .missingAppcast
    }
}
