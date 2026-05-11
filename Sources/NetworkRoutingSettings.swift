import Foundation

struct NetworkRoutingSettings: Codable, Equatable, Sendable {
    var bypassesSystemProxy: Bool

    static let `default` = NetworkRoutingSettings(bypassesSystemProxy: false)
}

final class AppNetworkSessionProvider: @unchecked Sendable {
    static let shared = AppNetworkSessionProvider()

    private let lock = NSLock()
    private var settings: NetworkRoutingSettings
    private var session: URLSession

    private init(settings: NetworkRoutingSettings = .default) {
        self.settings = settings
        self.session = Self.makeSession(settings: settings)
    }

    func update(settings newSettings: NetworkRoutingSettings) {
        lock.lock()
        guard settings != newSettings else {
            lock.unlock()
            return
        }
        settings = newSettings
        let oldSession = session
        session = Self.makeSession(settings: newSettings)
        lock.unlock()

        oldSession.finishTasksAndInvalidate()
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        try await currentSession().data(for: request)
    }

    func upload(for request: URLRequest, from bodyData: Data) async throws -> (Data, URLResponse) {
        try await currentSession().upload(for: request, from: bodyData)
    }

    private func currentSession() -> URLSession {
        lock.lock()
        defer { lock.unlock() }
        return session
    }

    private static func makeSession(settings: NetworkRoutingSettings) -> URLSession {
        URLSession(configuration: makeConfiguration(settings: settings))
    }

    private static func makeConfiguration(settings: NetworkRoutingSettings) -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.ephemeral
        if settings.bypassesSystemProxy {
            configuration.connectionProxyDictionary = [:]
        }
        return configuration
    }
}
