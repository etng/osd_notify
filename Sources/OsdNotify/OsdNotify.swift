import AppKit
import Darwin

@main
struct OsdNotifyApp {
    @MainActor
    static func main() {
        appendDiagnosticEvent(
            "invocation",
            arguments: Array(CommandLine.arguments.dropFirst())
        )

        do {
            let command = try parseCommand()

            switch command {
            case .version:
                printVersion()
                return

            case .checkUpdate:
                try checkForUpdates()
                return

            case .status:
                printRuntimeStatus()
                return

            case .logs:
                printRecentDiagnosticEvents()
                return

            case .daemon:
                runDaemon()
                return

            case .clear(let options):
                appendDiagnosticEvent(
                    "clear",
                    source: options.source,
                    detail: options.all ? "all" : "source"
                )
                do {
                    let response = try sendDaemonRequest(.clear(options), autostart: false)
                    if !response.message.isEmpty {
                        print(response.message)
                    }
                    if !response.ok {
                        exit(1)
                    }
                } catch {
                    if options.all {
                        clearAllOverlays(quiet: false)
                    } else {
                        clearExistingOverlay(source: options.source, quiet: false)
                    }
                }
                return

            case .show(let options):
                appendDiagnosticEvent(
                    "show",
                    source: options.source,
                    message: options.message
                )
                let response = try sendDaemonRequest(.show(options), autostart: true)
                if !response.ok {
                    throw CLIError.message(response.message)
                }
                return

            case .play(let options):
                try playTimedText(options)
                return

            case .recite(let options):
                try recitePlainText(options)
                return

            case .poem(let options):
                try recitePoem(options)
                return

            case .poetry(let options):
                try recitePoetry(options)
                return
            }
        } catch {
            appendDiagnosticEvent("command-failed", detail: "exit=2")
            fputs("osd-notify: \(error)\n\n", stderr)
            printUsage()
            exit(2)
        }
    }

    @MainActor
    private static func runDaemon() {
        let app = NSApplication.shared
        let delegate = DaemonAppDelegate()
        Darwin.signal(SIGTERM, SIG_IGN)
        Darwin.signal(SIGINT, SIG_IGN)
        let terminationSignals = [SIGTERM, SIGINT].map { signalNumber in
            let source = DispatchSource.makeSignalSource(signal: signalNumber, queue: .main)
            source.setEventHandler {
                NSApp.terminate(nil)
            }
            source.resume()
            return source
        }
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
        terminationSignals.forEach { $0.cancel() }
        _ = delegate
    }
}
