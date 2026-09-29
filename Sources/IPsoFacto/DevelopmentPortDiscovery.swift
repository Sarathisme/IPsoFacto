import Foundation
import IPsoFactoCore

/// Reads the user's TCP listener table. `lsof` provides the owning PID and
/// port; `ps` adds the full command line so Metro and similar tools can be
/// identified instead of being shown as generic Node processes.
enum DevelopmentPortDiscovery {
    static func scan() -> [DevelopmentPort] {
        guard let lsofOutput = run("/usr/sbin/lsof", arguments: ["-nP", "-Fpcn", "-iTCP", "-sTCP:LISTEN"]),
              !lsofOutput.isEmpty else { return [] }

        let pids = Set(lsofOutput.split(whereSeparator: \.isNewline).compactMap { line -> Int? in
            guard line.first == "p" else { return nil }
            return Int(line.dropFirst())
        })
        let commands = commandLines(for: pids)
        return DevelopmentPortClassifier.listeningPorts(lsofFields: lsofOutput, commandsByPID: commands)
    }

    private static func commandLines(for pids: Set<Int>) -> [Int: String] {
        guard !pids.isEmpty,
              let output = run("/bin/ps", arguments: ["-p", pids.sorted().map(String.init).joined(separator: ","), "-o", "pid=,command="]) else { return [:] }
        var result: [Int: String] = [:]
        for line in output.split(whereSeparator: \.isNewline) {
            let fields = line.split(maxSplits: 1, whereSeparator: \.isWhitespace)
            guard fields.count == 2, let pid = Int(fields[0]) else { continue }
            result[pid] = String(fields[1])
        }
        return result
    }

    private static func run(_ executable: String, arguments: [String]) -> String? {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: executable)
        task.arguments = arguments
        let output = Pipe()
        task.standardOutput = output
        task.standardError = Pipe()
        do {
            try task.run()
            task.waitUntilExit()
            guard task.terminationStatus == 0 else { return nil }
            return String(data: output.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)
        } catch {
            return nil
        }
    }
}
