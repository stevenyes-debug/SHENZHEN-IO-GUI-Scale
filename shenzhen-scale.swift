import Foundation
import CoreGraphics
import AppKit

let fileManager = FileManager.default
let environment = ProcessInfo.processInfo.environment

func fail(_ message: String) -> Never {
    let text = "错误：" + message + "\n"
    FileHandle.standardError.write(Data(text.utf8))
    exit(1)
}

func noLaunchRequested(_ args: [String]) -> Bool {
    return environment["SHENZHEN_IO_NO_LAUNCH"] == "1" || args.contains("--no-launch")
}

func usage() {
    print("""
    SHENZHEN I/O GUI Scale

    用法：
      shenzhen-scale.command 2       设置 2x GUI 缩放并启动游戏
      shenzhen-scale.command 1.5     设置 1.5x GUI 缩放
      shenzhen-scale.command status  查看当前配置
      shenzhen-scale.command restore 恢复第一次使用前的配置并启动

    可选缩放范围：1.0 到 4.0
    """)
}

func homePath() -> String {
    if let override = environment["SHENZHEN_IO_HOME"], override.isEmpty == false {
        return override
    }
    return fileManager.homeDirectoryForCurrentUser.path
}

func findConfigURL() -> URL {
    if let override = environment["SHENZHEN_IO_CONFIG"], override.isEmpty == false {
        let url = URL(fileURLWithPath: override)
        if fileManager.fileExists(atPath: url.path) == false {
            fail("找不到配置文件：\(url.path)")
        }
        return url
    }

    let root = URL(fileURLWithPath: homePath())
        .appendingPathComponent("Library/Application Support/SHENZHEN IO", isDirectory: true)
    guard let children = try? fileManager.contentsOfDirectory(at: root, includingPropertiesForKeys: [.contentModificationDateKey], options: [.skipsHiddenFiles]) else {
        fail("找不到 SHENZHEN I/O 的配置目录：\(root.path)")
    }

    var candidates: [(URL, Date)] = []
    for directory in children {
        let config = directory.appendingPathComponent("config.cfg")
        if fileManager.fileExists(atPath: config.path) {
            let values = try? config.resourceValues(forKeys: [.contentModificationDateKey])
            candidates.append((config, values?.contentModificationDate ?? Date.distantPast))
        }
    }

    guard let newest = candidates.max(by: { $0.1 < $1.1 }) else {
        fail("没有找到 config.cfg。请先启动一次 SHENZHEN I/O。")
    }
    return newest.0
}

func readText(_ url: URL) -> String {
    do {
        return try String(contentsOf: url, encoding: .utf8)
    } catch {
        fail("读取配置失败：\(error.localizedDescription)")
    }
}

func writeText(_ text: String, to url: URL) {
    do {
        try text.write(to: url, atomically: true, encoding: .utf8)
    } catch {
        fail("写入配置失败：\(error.localizedDescription)")
    }
}

func replaceValue(in text: String, key: String, value: String) -> String {
    let escaped = NSRegularExpression.escapedPattern(for: key)
    let pattern = "(?m)^\\s*" + escaped + "\\s*=\\s*.*$"
    guard let regex = try? NSRegularExpression(pattern: pattern) else {
        fail("无法处理配置项：\(key)")
    }
    let range = NSRange(text.startIndex..<text.endIndex, in: text)
    if regex.firstMatch(in: text, options: [], range: range) != nil {
        return regex.stringByReplacingMatches(in: text, options: [], range: range, withTemplate: key + " = " + value)
    }
    let separator = text.hasSuffix("\n") ? "" : "\n"
    return text + separator + key + " = " + value + "\n"
}

func intValue(in text: String, key: String) -> Int? {
    let escaped = NSRegularExpression.escapedPattern(for: key)
    let pattern = "(?m)^\\s*" + escaped + "\\s*=\\s*(\\d+)"
    guard let regex = try? NSRegularExpression(pattern: pattern),
          let match = regex.firstMatch(in: text, options: [], range: NSRange(text.startIndex..<text.endIndex, in: text)),
          let range = Range(match.range(at: 1), in: text) else {
        return nil
    }
    return Int(text[range])
}

func displayPixels() -> (Int, Int) {
    if let widthText = environment["SHENZHEN_IO_DISPLAY_WIDTH"],
       let heightText = environment["SHENZHEN_IO_DISPLAY_HEIGHT"],
       let width = Int(widthText),
       let height = Int(heightText) {
        return (width, height)
    }
    let display = CGMainDisplayID()
    let backingScale = NSScreen.main?.backingScaleFactor ?? 1.0
    let width = Int((Double(CGDisplayPixelsWide(display)) * backingScale).rounded())
    let height = Int((Double(CGDisplayPixelsHigh(display)) * backingScale).rounded())
    return (width, height)
}

func backupURL(for config: URL) -> URL {
    return config.appendingPathExtension("gui-scale-backup")
}

func makeBackupIfNeeded(config: URL) {
    let backup = backupURL(for: config)
    if fileManager.fileExists(atPath: backup.path) == false {
        do {
            try fileManager.copyItem(at: config, to: backup)
        } catch {
            fail("无法备份原配置：\(error.localizedDescription)")
        }
    }
}

func printCurrentStatus(config: URL) {
    let text = readText(config)
    let width = intValue(in: text, key: "Resolution.Width")
    let height = intValue(in: text, key: "Resolution.Height")
    let fullscreen = text.lowercased().contains("fullscreen = true")
    let display = displayPixels()
    print("配置文件：\(config.path)")
    print("全屏：\(fullscreen ? "是" : "否")")
    if let width, let height {
        print("当前内部渲染分辨率：\(width) × \(height)")
        if width > 0 {
            let scale = Double(display.0) / Double(width)
            print(String(format: "相对主显示器像素尺寸：约 %.2fx", scale))
        }
    } else {
        print("未找到 Resolution.Width / Resolution.Height")
    }
    let backup = backupURL(for: config)
    print("原始配置备份：\(fileManager.fileExists(atPath: backup.path) ? backup.path : "尚未创建")")
}

func configure(scale: Double, config: URL, launch: Bool) {
    guard scale >= 1.0 && scale <= 4.0 else {
        fail("缩放范围是 1.0 到 4.0")
    }
    makeBackupIfNeeded(config: config)
    let display = displayPixels()
    let targetWidth = max(320, Int((Double(display.0) / scale).rounded()))
    let targetHeight = max(240, Int((Double(display.1) / scale).rounded()))

    var text = readText(config)
    text = replaceValue(in: text, key: "Fullscreen", value: "True")
    text = replaceValue(in: text, key: "Resolution.Width", value: String(targetWidth))
    text = replaceValue(in: text, key: "Resolution.Height", value: String(targetHeight))
    writeText(text, to: config)

    print(String(format: "已设置 GUI 缩放：%.2fx", scale))
    print("内部渲染分辨率：\(targetWidth) × \(targetHeight)")
    print("显示模式：全屏")
    print("原配置已备份到：\(backupURL(for: config).path)")
    if launch {
        launchGame()
    }
}

func restore(config: URL, launch: Bool) {
    let backup = backupURL(for: config)
    guard fileManager.fileExists(atPath: backup.path) else {
        fail("没有找到原始配置备份：\(backup.path)")
    }
    let original = readText(backup)
    writeText(original, to: config)
    print("已恢复原始配置：\(config.path)")
    if launch {
        launchGame()
    }
}

func launchGame() {
    if environment["SHENZHEN_IO_NO_LAUNCH"] == "1" {
        print("测试模式：没有启动游戏。")
        return
    }

    let steam = Process()
    steam.executableURL = URL(fileURLWithPath: "/usr/bin/open")
    steam.arguments = ["steam://rungameid/504210"]
    do {
        try steam.run()
        steam.waitUntilExit()
        if steam.terminationStatus == 0 {
            print("已请求 Steam 启动 SHENZHEN I/O。")
            return
        }
    } catch {
        // Fall through to direct app launch.
    }

    let appPath = environment["SHENZHEN_IO_APP"] ?? (homePath() + "/Library/Application Support/Steam/steamapps/common/SHENZHEN IO/Shenzhen IO.app")
    if fileManager.fileExists(atPath: appPath) {
        let direct = Process()
        direct.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        direct.arguments = ["-n", appPath]
        do {
            try direct.run()
            direct.waitUntilExit()
            print("已启动 SHENZHEN I/O。")
        } catch {
            fail("无法启动游戏：\(error.localizedDescription)")
        }
    } else {
        print("配置已保存。请从 Steam 启动 SHENZHEN I/O。")
    }
}

let rawArgs = Array(CommandLine.arguments.dropFirst())
let args = rawArgs.filter { $0 != "--no-launch" }
guard let command = args.first else {
    usage()
    exit(0)
}

if command == "-h" || command == "--help" || command == "help" {
    usage()
    exit(0)
}

let config = findConfigURL()
let launch = noLaunchRequested(rawArgs) == false

switch command.lowercased() {
case "status":
    printCurrentStatus(config: config)
case "restore":
    restore(config: config, launch: launch)
default:
    guard let scale = Double(command) else {
        usage()
        exit(1)
    }
    configure(scale: scale, config: config, launch: launch)
}
