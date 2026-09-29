import Testing
@testable import IPsoFactoCore

@Suite("DevelopmentPortClassifier")
struct DevelopmentPortTests {
    @Test("keeps development runtimes and removes unrelated listeners")
    func filtersListeners() {
        let lsof = """
        p41
        cnode
        n*:5173
        p42
        cpython3
        n127.0.0.1:8000
        p43
        cpostgres
        n127.0.0.1:5432
        p44
        cnode
        n*:8081
        n[::1]:8081
        """
        let ports = DevelopmentPortClassifier.listeningPorts(
            lsofFields: lsof,
            commandsByPID: [41: "node node_modules/vite/bin/vite.js", 42: "python manage.py runserver", 44: "node node_modules/metro/src/cli.js"]
        )

        #expect(ports == [
            DevelopmentPort(pid: 41, port: 5173, runtime: .node, command: "node node_modules/vite/bin/vite.js"),
            DevelopmentPort(pid: 42, port: 8000, runtime: .python, command: "python manage.py runserver"),
            DevelopmentPort(pid: 44, port: 8081, runtime: .metro, command: "node node_modules/metro/src/cli.js")
        ])
    }

    @Test("recognizes runtimes from a full executable path")
    func recognizesPathBasedRuntime() {
        let ports = DevelopmentPortClassifier.listeningPorts(lsofFields: "p77\ncuvicorn\nn*:9000", commandsByPID: [77: "/opt/homebrew/bin/uvicorn app:main"])
        #expect(ports.first?.runtime == .python)
    }
}
