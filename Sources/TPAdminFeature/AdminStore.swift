import Foundation
import TPCore

@MainActor
public final class AdminStore: ObservableObject {
    public enum Section: String, CaseIterable, Sendable {
        case system, modules, claude
    }

    @Published public private(set) var system: SystemStatus?
    @Published public private(set) var fastfetch: [FastfetchRow] = []
    @Published public private(set) var modules: [AdminModule] = []
    @Published public private(set) var claude: ClaudeSessionList?
    @Published public var errorMessage: String?
    /// Containers / Claude sessions with an action in flight, to disable their buttons meanwhile.
    @Published public private(set) var busy: Set<String> = []
    /// The deploy shown in the job sheet; kept updated while it runs.
    @Published public var activeJob: DeployJob?

    private let client: AdminClient
    private static let pollInterval: Duration = .seconds(5)

    public init(client: AdminClient) {
        self.client = client
    }

    /// Refreshes `section` every few seconds until the calling task is cancelled — run it from the
    /// visible section's `.task(id:)` so polling stops as soon as the section or tab changes.
    public func poll(_ section: Section) async {
        while !Task.isCancelled {
            await refresh(section)
            try? await Task.sleep(for: Self.pollInterval)
        }
    }

    public func refresh(_ section: Section) async {
        do {
            switch section {
            case .system:
                system = try await client.systemStatus()
                // Cached server-side for a minute and barely changes; only fetch it once.
                if fastfetch.isEmpty { fastfetch = try await client.fastfetch() }
            case .modules:
                modules = try await client.modules()
            case .claude:
                claude = try await client.claudeSessions()
            }
            errorMessage = nil
        } catch is CancellationError {
            // The section changed mid-request; nothing to report.
        } catch {
            errorMessage = apiErrorMessage(error)
        }
    }

    // MARK: - Containers

    public func perform(_ action: AdminClient.ContainerAction, container: String) async {
        await withBusy(container) {
            try await client.perform(action, container: container)
            modules = try await client.modules()
        }
    }

    public func logs(container: String) async throws -> [String] {
        try await client.logs(container: container)
    }

    public func deploy(module: String, service: String? = nil) async {
        await withBusy(module) {
            activeJob = try await client.deploy(module: module, service: service)
        }
        await followActiveJob()
    }

    /// Polls the job until it finishes. Deploying tpcloud or tpadmin restarts what this request
    /// goes through, so transient errors are expected mid-deploy and simply retried.
    private func followActiveJob() async {
        var failures = 0
        while let job = activeJob, job.status == .running, !Task.isCancelled {
            try? await Task.sleep(for: .seconds(1))
            do {
                activeJob = try await client.job(id: job.id)
                failures = 0
            } catch {
                failures += 1
                if failures >= 30 {
                    errorMessage = "Se perdió el contacto con el despliegue: \(apiErrorMessage(error))"
                    return
                }
            }
        }
        modules = (try? await client.modules()) ?? modules
    }

    // MARK: - Claude

    public func startClaudeSession(directory: String) async -> ClaudeSession? {
        var started: ClaudeSession?
        await withBusy(directory) {
            started = try await client.startClaudeSession(directory: directory)
            claude = try await client.claudeSessions()
        }
        return started
    }

    public func trustClaudeSessionFolder(name: String) async {
        await withBusy(name) {
            try await client.trustClaudeSessionFolder(name: name)
            claude = try await client.claudeSessions()
        }
    }

    public func stopClaudeSession(name: String) async {
        await withBusy(name) {
            try await client.stopClaudeSession(name: name)
            claude = try await client.claudeSessions()
        }
    }

    private func withBusy(_ key: String, _ operation: () async throws -> Void) async {
        busy.insert(key)
        defer { busy.remove(key) }
        do {
            try await operation()
            errorMessage = nil
        } catch {
            errorMessage = apiErrorMessage(error)
        }
    }
}
