import Foundation

/// A TCP listener whose owning process is a commonly used development
/// runtime. Database servers and unrelated system listeners are deliberately
/// not included.
public struct DevelopmentPort: Equatable, Sendable, Identifiable {
    public enum Runtime: String, Equatable, Sendable {
        case node = "Node.js"
        case metro = "Metro"
        case python = "Python"
        case bun = "Bun"
        case deno = "Deno"
        case ruby = "Ruby"
        case php = "PHP"
        case java = "Java"
        case go = "Go"
        case rust = "Rust"
        case dotnet = ".NET"
    }

    public let pid: Int
    public let port: Int
    public let runtime: Runtime
    public let command: String

    public var id: String { "\(pid):\(port)" }
    public var displayName: String { runtime.rawValue }

    public init(pid: Int, port: Int, runtime: Runtime, command: String) {
        self.pid = pid
        self.port = port
        self.runtime = runtime
        self.command = command
    }
}

/// Parses `lsof -Fpcn -iTCP -sTCP:LISTEN` output and applies the narrow
/// runtime filter used by the menu. Keeping this logic pure makes the process
/// discovery behavior testable without reading the live process table.
public enum DevelopmentPortClassifier {
    public static func listeningPorts(lsofFields: String, commandsByPID: [Int: String] = [:]) -> [DevelopmentPort] {
        var pid: Int?
        var executable = ""
        var results: [DevelopmentPort] = []
        var seen = Set<String>()

        for line in lsofFields.split(whereSeparator: \.isNewline) {
            guard let field = line.first else { continue }
            let value = String(line.dropFirst())
            switch field {
            case "p": pid = Int(value)
            case "c": executable = value
            case "n":
                guard let pid, let port = portNumber(in: value) else { continue }
                let command = commandsByPID[pid] ?? executable
                guard let runtime = runtime(for: command, fallbackExecutable: executable) else { continue }
                let key = "\(pid):\(port)"
                guard seen.insert(key).inserted else { continue }
                results.append(DevelopmentPort(pid: pid, port: port, runtime: runtime, command: command))
            default: continue
            }
        }
        return results.sorted { ($0.port, $0.pid) < ($1.port, $1.pid) }
    }

    private static func portNumber(in listener: String) -> Int? {
        guard let separator = listener.lastIndex(of: ":") else { return nil }
        return Int(listener[listener.index(after: separator)...])
    }

    private static func runtime(for command: String, fallbackExecutable: String) -> DevelopmentPort.Runtime? {
        let text = "\(fallbackExecutable) \(command)".lowercased()
        if text.contains("metro") { return .metro }
        if matches(text, names: ["node", "nodejs"]) { return .node }
        if matches(text, names: ["python", "python3", "python2", "uvicorn", "gunicorn", "flask", "django"]) { return .python }
        if matches(text, names: ["bun"]) { return .bun }
        if matches(text, names: ["deno"]) { return .deno }
        if matches(text, names: ["ruby", "rails", "puma"]) { return .ruby }
        if matches(text, names: ["php"]) { return .php }
        if matches(text, names: ["java", "gradle"]) { return .java }
        if matches(text, names: ["go"]) { return .go }
        if matches(text, names: ["cargo", "rust"]) { return .rust }
        if matches(text, names: ["dotnet"]) { return .dotnet }
        return nil
    }

    /// Commands may be absolute paths or include arguments. Checking token
    /// boundaries avoids classifying a listener merely because a project path
    /// happens to contain a runtime's name.
    private static func matches(_ text: String, names: [String]) -> Bool {
        let tokens = text.split { !$0.isLetter && !$0.isNumber && $0 != "." && $0 != "_" }
        return tokens.contains { token in
            let value = String(token)
            return names.contains(where: { value == $0 || value.hasPrefix($0 + ".") })
        }
    }
}
