import AppKit

let arguments = CommandLine.arguments

if arguments.contains("--help") || arguments.contains("-h") {
    print(ScheduleDump.usage)
    exit(0)
}

if arguments.contains("--version") {
    print("DeepSeek Peak 1.0.0")
    exit(0)
}

if arguments.contains("--dump") {
    exit(ScheduleDump.run(arguments: arguments))
}

let application = NSApplication.shared
let delegate = AppDelegate()
application.delegate = delegate
application.setActivationPolicy(.accessory)
application.run()
