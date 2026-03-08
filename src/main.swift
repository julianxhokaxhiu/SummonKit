#!/usr/bin/env swift

/****************************************************************************/
//    Copyright (C) 2026 Julian Xhokaxhiu                                   //
//                                                                          //
//    This file is part of SummonKit                                        //
//                                                                          //
//    SummonKit is free software: you can redistribute it and/or modify     //
//    it under the terms of the GNU General Public License as published by  //
//    the Free Software Foundation, either version 3 of the License         //
//                                                                          //
//    SummonKit is distributed in the hope that it will be useful,          //
//    but WITHOUT ANY WARRANTY; without even the implied warranty of        //
//    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the         //
//    GNU General Public License for more details.                          //
/****************************************************************************/

import Foundation
import AppKit
import UniformTypeIdentifiers
import Sparkle

struct LauncherProduct {
    let id: String
    let gameMenuTitle: String
    let displayName: String
    let statusWindowTitle: String
    let launchBanner: String
    let githubApiURL: String
    let installerFileBaseName: String
    let targetExeRelativePath: String
    let targetExeProfilePath: String
    let appSupportFolderName: String
    let gameDisplayName: String
    let steamGameDirectoryName: String
    let steamGameIDs: [String]
    let gogFallbackRelativePath: String
    let steamUserRelativePath: String
    let wineAppDefaultExeName: String
    let allowsCustomGameInstaller: Bool
}

protocol LauncherProductProviding {
    var product: LauncherProduct { get }
}

struct RuntimePaths {
    let bundle: URL
    let wineDir: URL
    let wineBin: URL
    let wineServer: URL
    let wineLib: URL
    let appSupport: URL
    let winePrefix: URL
    let targetExe: URL
    let logFile: URL
    let wineLogFile: URL

    static func make(for product: LauncherProduct) -> RuntimePaths {
        let bundle = Bundle.main.bundleURL
        let wineDir = bundle.appendingPathComponent("Contents/Resources/wine")
        let appSupport = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/SummonKit/\(product.appSupportFolderName)")
        let winePrefix = appSupport.appendingPathComponent("prefix")

        return RuntimePaths(
            bundle: bundle,
            wineDir: wineDir,
            wineBin: wineDir.appendingPathComponent("bin/wine"),
            wineServer: wineDir.appendingPathComponent("bin/wineserver"),
            wineLib: wineDir.appendingPathComponent("lib"),
            appSupport: appSupport,
            winePrefix: winePrefix,
            targetExe: winePrefix.appendingPathComponent(product.targetExeRelativePath),
            logFile: appSupport.appendingPathComponent("launcher.log"),
            wineLogFile: appSupport.appendingPathComponent("wine.log")
        )
    }
}

struct GameInstallLocation {
    let path: String
    let installDir: String
    let gameID: String
    let libraryPath: String
}

final class StatusWindow {
    private let window: NSWindow
    private let textView: NSTextView

    init(title: String, banner: String) {
        let windowSize = NSSize(width: 640, height: 360)
        self.window = NSWindow(
            contentRect: NSRect(origin: .zero, size: windowSize),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        self.window.title = title
        self.window.center()

        let scrollView = NSTextView.scrollableTextView()
        scrollView.frame = NSRect(origin: .zero, size: windowSize)
        scrollView.autoresizingMask = [.width, .height]
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .bezelBorder
        scrollView.drawsBackground = true
        scrollView.backgroundColor = .textBackgroundColor

        self.textView = scrollView.documentView as! NSTextView
        self.textView.isEditable = false
        self.textView.isSelectable = true
        self.textView.drawsBackground = true
        self.textView.backgroundColor = .textBackgroundColor
        self.textView.textColor = .labelColor
        self.textView.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        self.textView.isVerticallyResizable = true
        self.textView.isHorizontallyResizable = false
        self.textView.textContainer?.containerSize = NSSize(
            width: windowSize.width,
            height: .greatestFiniteMagnitude
        )
        self.textView.textContainer?.widthTracksTextView = true
        self.textView.isRichText = false
        self.textView.string = "INFO: \(banner)\n"

        self.window.contentView = scrollView
    }

    func show() {
        DispatchQueue.main.async {
            NSApp.activate(ignoringOtherApps: true)
            self.window.makeKeyAndOrderFront(nil)
        }
    }

    func hide() {
        DispatchQueue.main.async {
            self.window.orderOut(nil)
        }
    }

    func append(message: String, style: NSAlert.Style) {
        let prefix = style == .critical ? "ERROR: " : "INFO: "
        let line = prefix + message + "\n"

        DispatchQueue.main.async {
            self.textView.string += line
            let endRange = NSRange(location: self.textView.string.count, length: 0)
            self.textView.scrollRangeToVisible(endRange)
        }
    }
}

final class LauncherEngine {
    private let product: LauncherProduct
    private let paths: RuntimePaths
    private var statusWindow: StatusWindow!

    init(product: LauncherProduct) {
        self.product = product
        self.paths = RuntimePaths.make(for: product)
    }

    func start(completion: @escaping () -> Void) {
        statusWindow = StatusWindow(title: product.statusWindowTitle, banner: product.launchBanner)
        NSApp.activate(ignoringOtherApps: true)
        statusWindow.show()

        DispatchQueue.global(qos: .userInitiated).async {
            self.runMain()
            DispatchQueue.main.async {
                completion()
            }
        }
    }

    func openWineTool(_ toolName: String, completion: @escaping () -> Void) {
        statusWindow = StatusWindow(title: product.statusWindowTitle, banner: "Opening \(toolName)...")
        NSApp.activate(ignoringOtherApps: true)
        statusWindow.show()

        DispatchQueue.global(qos: .userInitiated).async {
            self.runWineTool(named: toolName)
            DispatchQueue.main.async {
                completion()
            }
        }
    }

    func openWinePrefix(completion: @escaping () -> Void) {
        statusWindow = StatusWindow(title: product.statusWindowTitle, banner: "Opening Wine Prefix...")
        NSApp.activate(ignoringOtherApps: true)
        statusWindow.show()

        DispatchQueue.global(qos: .userInitiated).async {
            self.openWinePrefixInFinder()
            DispatchQueue.main.async {
                completion()
            }
        }
    }

    func openGamePath(completion: @escaping () -> Void) {
        statusWindow = StatusWindow(title: product.statusWindowTitle, banner: "Opening Game Path...")
        NSApp.activate(ignoringOtherApps: true)
        statusWindow.show()

        DispatchQueue.global(qos: .userInitiated).async {
            self.openGamePathInFinder()
            DispatchQueue.main.async {
                completion()
            }
        }
    }

    func openSavePath(completion: @escaping () -> Void) {
        statusWindow = StatusWindow(title: product.statusWindowTitle, banner: "Opening Save Path...")
        NSApp.activate(ignoringOtherApps: true)
        statusWindow.show()

        DispatchQueue.global(qos: .userInitiated).async {
            self.openSavePathInFinder()
            DispatchQueue.main.async {
                completion()
            }
        }
    }

    func openLogsPath(completion: @escaping () -> Void) {
        statusWindow = StatusWindow(title: product.statusWindowTitle, banner: "Opening Logs Path...")
        NSApp.activate(ignoringOtherApps: true)
        statusWindow.show()

        DispatchQueue.global(qos: .userInitiated).async {
            self.openLogsPathInFinder()
            DispatchQueue.main.async {
                completion()
            }
        }
    }

    func openModLibraryPath(completion: @escaping () -> Void) {
        statusWindow = StatusWindow(title: product.statusWindowTitle, banner: "Opening Mod Library Path...")
        NSApp.activate(ignoringOtherApps: true)
        statusWindow.show()

        DispatchQueue.global(qos: .userInitiated).async {
            self.openModLibraryPathInFinder()
            DispatchQueue.main.async {
                completion()
            }
        }
    }

    func wipeInstallation(completion: @escaping () -> Void) {
        statusWindow = StatusWindow(title: product.statusWindowTitle, banner: "Wiping Installation...")
        NSApp.activate(ignoringOtherApps: true)
        statusWindow.show()

        DispatchQueue.global(qos: .userInitiated).async {
            self.wipeInstallationData()
            DispatchQueue.main.async {
                completion()
            }
        }
    }

    private func log(_ message: String) {
        let timestamp = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
        let logMessage = "[\(timestamp)] \(message)\n"
        print(message)

        try? FileManager.default.createDirectory(at: paths.appSupport, withIntermediateDirectories: true)
        if let data = logMessage.data(using: .utf8) {
            if FileManager.default.fileExists(atPath: paths.logFile.path) {
                if let handle = try? FileHandle(forWritingTo: paths.logFile) {
                    handle.seekToEndOfFile()
                    handle.write(data)
                    handle.closeFile()
                }
            } else {
                try? data.write(to: paths.logFile)
            }
        }
    }

    private func showStatusMessage(_ message: String, style: NSAlert.Style) {
        statusWindow.append(message: message, style: style)
    }

    private func showError(_ message: String) {
        log("FATAL: \(message)")
        showStatusMessage(message, style: .critical)
    }

    private func setupWineEnvironment() {
        let macOSUsername = FileManager.default.homeDirectoryForCurrentUser.lastPathComponent
        let windowsUserProfilePath = "Z:\\Users\\\(macOSUsername)\\\(product.appSupportFolderName)"
        setenv("APP_LIBRARY_PATH", windowsUserProfilePath, 1)
        setenv("DYLD_FALLBACK_LIBRARY_PATH", paths.wineLib.path, 1)
        setenv("LANG", "en-US.UTF-8", 1)
        setenv("LC_ALL", "en-US", 1)
        setenv("MVK_CONFIG_RESUME_LOST_DEVICE", "1", 1)
        setenv("WINEPREFIX", paths.winePrefix.path, 1)
        setenv("WINEDLLPATH", paths.wineDir.appendingPathComponent("lib/wine").path, 1)
        setenv("WINE_LARGE_ADDRESS_AWARE", "1", 1)
        setenv("WINEDEBUG", "+err,+warn,+debugstr", 1)
        setenv("WINEDLLOVERRIDES", "dinput=n,b", 1)
        setenv("DXMT_LOG_LEVEL", "info", 1)
        setenv("DXMT_LOG_PATH", paths.appSupport.path, 1)

        let dxmtRoot = paths.bundle.appendingPathComponent("Contents/Resources/dxmt")
        if let entries = try? FileManager.default.contentsOfDirectory(
            at: dxmtRoot,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) {
            let versionDirs = entries.filter {
                (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
            }.sorted { $0.lastPathComponent > $1.lastPathComponent }

            if let latestDXMT = versionDirs.first {
                setenv("WINEDLLPATH_PREPEND", latestDXMT.path, 1)
                log("WINEDLLPATH_PREPEND set to: \(latestDXMT.path)")
            } else {
                log("Warning: No DXMT version directory found under: \(dxmtRoot.path)")
            }
        } else {
            log("Warning: Failed to enumerate DXMT directory at: \(dxmtRoot.path)")
        }

        log("Wine environment configured")
    }

    @discardableResult
    private func runCommand(_ command: String, args: [String], wait: Bool = true) -> Int32 {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: command)
        task.arguments = args

        if command.contains("wine") {
            if let handle = try? FileHandle(forWritingTo: paths.wineLogFile) {
                handle.seekToEndOfFile()
                task.standardOutput = handle
                task.standardError = handle
            } else {
                try? FileManager.default.createDirectory(at: paths.appSupport, withIntermediateDirectories: true)
                try? Data().write(to: paths.wineLogFile)
                if let handle = try? FileHandle(forWritingTo: paths.wineLogFile) {
                    task.standardOutput = handle
                    task.standardError = handle
                }
            }
        } else {
            task.standardOutput = FileHandle.nullDevice
            task.standardError = FileHandle.nullDevice
        }

        do {
            try task.run()
            if wait {
                task.waitUntilExit()
            }
            return task.terminationStatus
        } catch {
            log("Error running \(command): \(error)")
            return -1
        }
    }

    private func initializeWinePrefixIfNeeded() {
        let driveC = paths.winePrefix.appendingPathComponent("drive_c")
        if !FileManager.default.fileExists(atPath: driveC.path) {
            log("Initializing Wine prefix at \(paths.winePrefix.path)...")
            showStatusMessage("First launch detected. Initializing Windows environment...", style: .informational)

            try? FileManager.default.createDirectory(at: paths.winePrefix, withIntermediateDirectories: true)
            runCommand(paths.wineBin.path, args: ["wineboot", "--init"])
            runCommand(paths.wineServer.path, args: ["-w"])

            log("Wine prefix initialized")
        }
    }

    private func configureWineRegistry() {
        log("Configuring Wine registry for GDI rendering...")
        runCommand(paths.wineBin.path, args: [
            "reg", "add",
            "HKCU\\Software\\Wine\\AppDefaults\\\(product.wineAppDefaultExeName)\\Direct3D",
            "/v", "renderer",
            "/t", "REG_SZ",
            "/d", "gdi",
            "/f"
        ])
        log("Wine registry configured")
    }

    private func setupSteamRegistry(steamPath: String) {
        log("Configuring Wine registry for Steam path...")
        let windowsPath = steamPath.replacingOccurrences(of: paths.winePrefix.path + "/drive_c", with: "C:")
            .replacingOccurrences(of: "/", with: "\\")

        runCommand(paths.wineBin.path, args: [
            "reg", "add",
            "HKCU\\SOFTWARE\\Valve\\Steam",
            "/v", "SteamPath",
            "/t", "REG_SZ",
            "/d", windowsPath,
            "/f"
        ])
        log("Steam registry configured with path: \(windowsPath)")
    }

    private func patchConfigVDF(at path: String, steamPath: String) {
        guard let content = try? String(contentsOfFile: path, encoding: .utf8) else {
            log("Failed to read config VDF for patching at: \(path)")
            return
        }

        let windowsPath = steamPath.replacingOccurrences(of: paths.winePrefix.path + "/drive_c", with: "C:")
            .replacingOccurrences(of: "/", with: "\\")

        let pattern = try! NSRegularExpression(
            pattern: "\"path\"\\s+\"[^\"]*\\/Users\\/[^\"]*\\/Library\\/Application Support\\/Steam\"",
            options: []
        )
        let range = NSRange(content.startIndex..., in: content)
        let matches = pattern.matches(in: content, options: [], range: range)

        guard !matches.isEmpty else {
            log("No Unix Steam path found in config VDF to patch")
            return
        }

        let replacement = NSRegularExpression.escapedTemplate(for: "\"path\"\t\t\"\(windowsPath)\"")
        let patched = pattern.stringByReplacingMatches(
            in: content,
            options: [],
            range: range,
            withTemplate: replacement
        )

        do {
            try patched.write(toFile: path, atomically: true, encoding: .utf8)
            log("Patched config VDF at: \(path)")
        } catch {
            log("Failed to patch config VDF: \(error.localizedDescription)")
        }
    }

    private func getLatestInstallerURL() -> String? {
        guard let url = URL(string: product.githubApiURL) else {
            return nil
        }

        do {
            let data = try Data(contentsOf: url)
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let assets = json["assets"] as? [[String: Any]] {
                for asset in assets {
                    if let name = asset["name"] as? String,
                       name.hasSuffix("_Release.exe"),
                       let downloadURL = asset["browser_download_url"] as? String {
                        return downloadURL
                    }
                }
            }
        } catch {
            log("Failed to fetch latest release info: \(error)")
        }

        return nil
    }

    private func downloadInstaller() -> Bool {
        log("Downloading \(product.displayName) installer...")

        guard let installerURL = getLatestInstallerURL() else {
            log("Failed to determine latest installer URL")
            return false
        }

        log("Latest installer URL: \(installerURL)")
        showStatusMessage("Downloading \(product.displayName) installer. This may take a few minutes...", style: .informational)

        let installerExe = paths.appSupport.appendingPathComponent("\(product.installerFileBaseName).exe")
        let tempFile = paths.appSupport.appendingPathComponent("\(product.installerFileBaseName).exe.tmp")

        guard let url = URL(string: installerURL) else {
            log("Invalid installer URL: \(installerURL)")
            return false
        }

        var request = URLRequest(url: url)
        request.setValue(
            "Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:148.0) Gecko/20100101 Firefox/148.0",
            forHTTPHeaderField: "User-Agent"
        )

        let semaphore = DispatchSemaphore(value: 0)
        var success = false

        let task = URLSession.shared.downloadTask(with: request) { tempURL, response, error in
            defer { semaphore.signal() }

            if let error = error {
                self.log("Download failed: \(error.localizedDescription)")
                return
            }

            guard let httpResponse = response as? HTTPURLResponse else {
                self.log("Download failed: no HTTP response")
                return
            }

            self.log("HTTP Response: \(httpResponse.statusCode)")
            guard httpResponse.statusCode < 400 else {
                self.log("Download failed with HTTP \(httpResponse.statusCode)")
                return
            }

            guard let tempURL = tempURL else {
                self.log("Download failed: missing temp URL")
                return
            }

            do {
                try FileManager.default.removeItem(at: installerExe)
            } catch {
                // Existing file may not exist.
            }

            do {
                try FileManager.default.moveItem(at: tempURL, to: installerExe)
                self.log("Download complete")
                success = true
            } catch {
                self.log("Failed to save downloaded file: \(error.localizedDescription)")
            }
        }

        task.resume()
        semaphore.wait()

        if !success {
            try? FileManager.default.removeItem(at: tempFile)
        }

        return success
    }

    private func promptForCustomGameInstaller() -> URL? {
        if !product.allowsCustomGameInstaller {
            return nil
        }

        if !Thread.isMainThread {
            return DispatchQueue.main.sync { self.promptForCustomGameInstaller() }
        }

        let alert = NSAlert()
        alert.messageText = "Optional: Install \(product.gameDisplayName)"
        alert.informativeText = "If you have a GOG (or other) installer, choose it now. Otherwise click Skip to continue with Steam autodetect."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Choose Installer")
        alert.addButton(withTitle: "Skip")

        let response = alert.runModal()
        guard response == .alertFirstButtonReturn else {
            return nil
        }

        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [UTType(filenameExtension: "exe")].compactMap { $0 }
        panel.title = "Choose \(product.gameDisplayName) Installer"
        panel.message = "Select your game installer .exe file."

        if panel.runModal() == .OK {
            return panel.url
        }

        return nil
    }

    private func parseInstallDirFromAppManifest(_ manifestPath: String) -> String? {
        guard let content = try? String(contentsOfFile: manifestPath, encoding: .utf8) else {
            return nil
        }

        for rawLine in content.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.contains("\"installdir\"") {
                let components = line.components(separatedBy: "\"")
                if components.count >= 4 {
                    let installDir = components[3]
                    if !installDir.isEmpty {
                        return installDir
                    }
                }
            }
        }

        return nil
    }

    private func findSteamGamePath() -> GameInstallLocation? {
        let steamConfig = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Steam/steamapps/libraryfolders.vdf")

        if FileManager.default.fileExists(atPath: steamConfig.path),
           let content = try? String(contentsOf: steamConfig, encoding: .utf8) {
            let lines = content.components(separatedBy: .newlines)
            var currentLibraryPath: String?
            var inAppsSection = false

            for line in lines {
                if line.contains("\"path\"") {
                    let components = line.components(separatedBy: "\"")
                    if components.count >= 4 {
                        currentLibraryPath = components[3]
                    }
                }

                if line.contains("\"apps\"") {
                    inAppsSection = true
                }

                if inAppsSection && line.trimmingCharacters(in: .whitespaces) == "}" {
                    inAppsSection = false
                    currentLibraryPath = nil
                }

                if inAppsSection, let libraryPath = currentLibraryPath {
                    for gameID in product.steamGameIDs {
                        if line.contains("\"\(gameID)\"") {
                            let manifestPath = "\(libraryPath)/steamapps/appmanifest_\(gameID).acf"
                            if let installDir = parseInstallDirFromAppManifest(manifestPath) {
                                let candidate = "\(libraryPath)/steamapps/common/\(installDir)"
                                if FileManager.default.fileExists(atPath: candidate) {
                                    log("Found \(product.gameDisplayName) (Game ID: \(gameID)) at: \(candidate) [installdir=\(installDir)]")
                                    return GameInstallLocation(path: candidate, installDir: installDir, gameID: gameID, libraryPath: libraryPath)
                                }
                            }

                            let fallbackCandidate = "\(libraryPath)/steamapps/common/\(product.steamGameDirectoryName)"
                            if FileManager.default.fileExists(atPath: fallbackCandidate) {
                                log("Found \(product.gameDisplayName) (Game ID: \(gameID)) at fallback path: \(fallbackCandidate)")
                                return GameInstallLocation(path: fallbackCandidate, installDir: product.steamGameDirectoryName, gameID: gameID, libraryPath: libraryPath)
                            }
                        }
                    }
                }
            }

            var libraryPaths: [String] = []
            for line in lines {
                if line.contains("\"path\"") {
                    let components = line.components(separatedBy: "\"")
                    if components.count >= 4 {
                        libraryPaths.append(components[3])
                    }
                }
            }

            for libraryPath in libraryPaths {
                for gameID in product.steamGameIDs {
                    let manifestPath = "\(libraryPath)/steamapps/appmanifest_\(gameID).acf"
                    if FileManager.default.fileExists(atPath: manifestPath) {
                        if let installDir = parseInstallDirFromAppManifest(manifestPath) {
                            let candidate = "\(libraryPath)/steamapps/common/\(installDir)"
                            if FileManager.default.fileExists(atPath: candidate) {
                                log("Found \(product.gameDisplayName) (Game ID: \(gameID) via manifest) at: \(candidate) [installdir=\(installDir)]")
                                return GameInstallLocation(path: candidate, installDir: installDir, gameID: gameID, libraryPath: libraryPath)
                            }
                        }

                        let fallbackCandidate = "\(libraryPath)/steamapps/common/\(product.steamGameDirectoryName)"
                        if FileManager.default.fileExists(atPath: fallbackCandidate) {
                            log("Found \(product.gameDisplayName) (Game ID: \(gameID) via manifest fallback) at: \(fallbackCandidate)")
                            return GameInstallLocation(path: fallbackCandidate, installDir: product.steamGameDirectoryName, gameID: gameID, libraryPath: libraryPath)
                        }
                    }
                }
            }
        }

        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let fallbacks = [
            home + "/Library/Application Support/Steam/steamapps/common/\(product.steamGameDirectoryName)",
            "/Volumes/SteamLibrary/steamapps/common/\(product.steamGameDirectoryName)"
        ]

        for fallback in fallbacks {
            if FileManager.default.fileExists(atPath: fallback) {
                log("Found \(product.gameDisplayName) at fallback: \(fallback)")
                return GameInstallLocation(
                    path: fallback,
                    installDir: URL(fileURLWithPath: fallback).lastPathComponent,
                    gameID: "",
                    libraryPath: ""
                )
            }
        }

        return nil
    }

    private func findGOGGamePath() -> GameInstallLocation? {
        let gogPath = paths.winePrefix.appendingPathComponent(product.gogFallbackRelativePath).path

        if FileManager.default.fileExists(atPath: gogPath) {
            log("Found \(product.gameDisplayName) at GOG fallback: \(gogPath)")
            return GameInstallLocation(
                path: gogPath,
                installDir: URL(fileURLWithPath: gogPath).lastPathComponent,
                gameID: "",
                libraryPath: ""
            )
        }

        return nil
    }

    private func findGamePath() -> GameInstallLocation? {
        if let steamInstall = findSteamGamePath() {
            return steamInstall
        }

        return findGOGGamePath()
    }

    private func recursivelyCopyFiles(from sourceURL: URL, to destinationURL: URL) -> Bool {
        let fileManager = FileManager.default

        do {
            try fileManager.createDirectory(at: destinationURL, withIntermediateDirectories: true)
            let sourceContents = try fileManager.contentsOfDirectory(
                at: sourceURL,
                includingPropertiesForKeys: [.isDirectoryKey]
            )

            for sourceItem in sourceContents {
                let destinationItem = destinationURL.appendingPathComponent(sourceItem.lastPathComponent)
                let values = try sourceItem.resourceValues(forKeys: [.isDirectoryKey])

                if values.isDirectory == true {
                    if !recursivelyCopyFiles(from: sourceItem, to: destinationItem) {
                        return false
                    }
                } else {
                    if fileManager.fileExists(atPath: destinationItem.path) {
                        try fileManager.removeItem(at: destinationItem)
                    }
                    try fileManager.copyItem(at: sourceItem, to: destinationItem)
                }
            }

            return true
        } catch {
            log("Error while copying game files: \(error.localizedDescription)")
            return false
        }
    }

    private func copyGameIntoWinePrefix(from sourcePath: String, installDir: String) -> String? {
        let sourceURL = URL(fileURLWithPath: sourcePath)
        let destinationURL = paths.winePrefix
            .appendingPathComponent("drive_c/Program Files (x86)/Steam/steamapps/common/\(installDir)")
        let destinationParent = destinationURL.deletingLastPathComponent()

        guard FileManager.default.fileExists(atPath: sourceURL.path) else {
            log("Source game path does not exist: \(sourceURL.path)")
            return nil
        }

        if FileManager.default.fileExists(atPath: destinationURL.path) {
            if let existingEntries = try? FileManager.default.contentsOfDirectory(atPath: destinationURL.path),
               !existingEntries.isEmpty {
                log("Game already present in Wine prefix at: \(destinationURL.path), skipping copy")
                return destinationURL.path
            }

            try? FileManager.default.removeItem(at: destinationURL)
        }

        try? FileManager.default.createDirectory(at: destinationParent, withIntermediateDirectories: true)
        showStatusMessage("Copying \(product.gameDisplayName) into Wine prefix. This may take a while...", style: .informational)

        if recursivelyCopyFiles(from: sourceURL, to: destinationURL) {
            log("Game copied to Wine prefix at: \(destinationURL.path)")
            return destinationURL.path
        }

        log("Failed to copy game using recursive copy")
        try? FileManager.default.removeItem(at: destinationURL)
        return nil
    }

    private func copySteamVDFFiles(gameID: String, libraryPath: String, steamPath: String) {
        guard !gameID.isEmpty && !libraryPath.isEmpty else {
            log("Cannot copy VDF files: gameID or libraryPath is empty")
            return
        }

        let fileManager = FileManager.default
        let steamappsPath = "\(steamPath)/steamapps"
        let configPath = "\(steamPath)/config"

        func copyIfNeeded(source: String, destination: String, label: String) -> Bool {
            guard fileManager.fileExists(atPath: source) else {
                self.log("Warning: \(label) not found at \(source)")
                return false
            }

            if fileManager.fileExists(atPath: destination),
               fileManager.contentsEqual(atPath: source, andPath: destination) {
                self.log("Skipping \(label): already up to date")
                return false
            }

            let parent = URL(fileURLWithPath: destination).deletingLastPathComponent().path
            do {
                try fileManager.createDirectory(atPath: parent, withIntermediateDirectories: true)
                if fileManager.fileExists(atPath: destination) {
                    try fileManager.removeItem(atPath: destination)
                }
                try fileManager.copyItem(atPath: source, toPath: destination)
                self.log("Copied \(label) to Wine prefix")
                return true
            } catch {
                self.log("Failed to copy \(label): \(error.localizedDescription)")
                return false
            }
        }

        var copiedAny = false
        copiedAny = copyIfNeeded(
            source: "\(libraryPath)/steamapps/libraryfolders.vdf",
            destination: "\(steamappsPath)/libraryfolders.vdf",
            label: "libraryfolders.vdf"
        ) || copiedAny
        copiedAny = copyIfNeeded(
            source: "\(libraryPath)/steamapps/appmanifest_\(gameID).acf",
            destination: "\(steamappsPath)/appmanifest_\(gameID).acf",
            label: "appmanifest_\(gameID).acf"
        ) || copiedAny
        copiedAny = copyIfNeeded(
            source: "\(libraryPath)/config/libraryfolders.vdf",
            destination: "\(configPath)/libraryfolders.vdf",
            label: "config/libraryfolders.vdf"
        ) || copiedAny

        if !copiedAny {
            log("Steam VDF files already up to date; no copy needed")
        }

        patchConfigVDF(at: "\(steamappsPath)/libraryfolders.vdf", steamPath: steamPath)
        patchConfigVDF(at: "\(configPath)/libraryfolders.vdf", steamPath: steamPath)
    }

    private func isSteamInstall(_ gameInstall: GameInstallLocation) -> Bool {
        if !gameInstall.gameID.isEmpty || !gameInstall.libraryPath.isEmpty {
            return true
        }
        return gameInstall.path.contains("/steamapps/common/")
    }

    private func ensureSteamUserDirectoriesIfNeeded(isSteamInstall: Bool) {
        guard isSteamInstall else {
            return
        }

        let userDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(product.steamUserRelativePath)

        do {
            try FileManager.default.createDirectory(at: userDir, withIntermediateDirectories: true)
            log("Ensured Steam user directories at: \(userDir.path)")
        } catch {
            log("Warning: Failed to create Steam user directories: \(error.localizedDescription)")
        }
    }

    private func runWineTool(named toolName: String) {
        log("Launching \(toolName)")
        showStatusMessage("Launching \(toolName)...", style: .informational)

        guard FileManager.default.fileExists(atPath: paths.wineBin.path) else {
            showError("Wine runtime not found in app bundle. Please rebuild the application.")
            return
        }

        setupWineEnvironment()

        let toolPath = paths.wineDir.appendingPathComponent("bin/\(toolName)")
        guard FileManager.default.fileExists(atPath: toolPath.path) else {
            showError("\(toolName) was not found in Wine runtime.")
            return
        }

        let task = Process()
        task.executableURL = toolPath

        do {
            try task.run()
            task.waitUntilExit()
            statusWindow.hide()
            log("=== \(toolName) exited ===")
        } catch {
            showError("Failed to launch \(toolName):\n\(error.localizedDescription)")
        }
    }

    private func openWinePrefixInFinder() {
        do {
            try FileManager.default.createDirectory(at: paths.winePrefix, withIntermediateDirectories: true)
            showStatusMessage("Opening Wine prefix in Finder...", style: .informational)
            NSWorkspace.shared.open(paths.winePrefix)
            statusWindow.hide()
            log("Opened Wine prefix: \(paths.winePrefix.path)")
        } catch {
            showError("Failed to open Wine prefix:\n\(error.localizedDescription)")
        }
    }

    private func showPathNotFoundPopup() {
        let presentAlert = {
            let alert = NSAlert()
            alert.messageText = "Path not found"
            alert.informativeText = "Could not locate \(self.product.gameDisplayName) in Steam paths or GOG fallback path."
            alert.alertStyle = .warning
            alert.addButton(withTitle: "OK")
            NSApp.activate(ignoringOtherApps: true)
            alert.runModal()
        }

        if Thread.isMainThread {
            presentAlert()
        } else {
            DispatchQueue.main.sync(execute: presentAlert)
        }
    }

    private func showPopup(title: String, message: String) {
        let presentAlert = {
            let alert = NSAlert()
            alert.messageText = title
            alert.informativeText = message
            alert.alertStyle = .warning
            alert.addButton(withTitle: "OK")
            NSApp.activate(ignoringOtherApps: true)
            alert.runModal()
        }

        if Thread.isMainThread {
            presentAlert()
        } else {
            DispatchQueue.main.sync(execute: presentAlert)
        }
    }

    private func confirmWipeInstallation() -> Bool {
        let presentAlert = {
            let alert = NSAlert()
            alert.messageText = "Wipe Installation"
            alert.informativeText = "This will permanently delete all \(self.product.displayName) data from this launcher installation, including save games and configuration files. This action cannot be undone."
            alert.alertStyle = .critical
            alert.addButton(withTitle: "Continue")
            alert.addButton(withTitle: "Cancel")
            NSApp.activate(ignoringOtherApps: true)
            return alert.runModal() == .alertFirstButtonReturn
        }

        if Thread.isMainThread {
            return presentAlert()
        } else {
            return DispatchQueue.main.sync(execute: presentAlert)
        }
    }

    private func wipeInstallationData() {
        guard confirmWipeInstallation() else {
            log("Wipe installation cancelled by user")
            statusWindow.hide()
            return
        }

        showStatusMessage("Deleting app data folder...", style: .informational)

        do {
            if FileManager.default.fileExists(atPath: paths.appSupport.path) {
                try FileManager.default.removeItem(at: paths.appSupport)
                log("Wiped installation data at: \(paths.appSupport.path)")
                showStatusMessage("Installation data wiped successfully.", style: .informational)
            } else {
                log("No installation data found to wipe at: \(paths.appSupport.path)")
                showStatusMessage("No installation data folder was found.", style: .informational)
            }
        } catch {
            showError("Failed to wipe installation data:\n\(error.localizedDescription)")
            return
        }

        statusWindow.hide()
    }

    private func openGamePathInFinder() {
        showStatusMessage("Locating game path...", style: .informational)

        guard let gameExeLocation = readGameExecutableLocationFromSettingsXML() else {
            showPopup(
                title: "Path not found",
                message: "Could not read FF7Exe/FF8Exe from settings.xml for \(product.displayName)."
            )
            statusWindow.hide()
            return
        }

        let gameExePath = convertWindowsPathToPrefixPath(gameExeLocation)
        let gamePath = gameExePath.deletingLastPathComponent()
        guard FileManager.default.fileExists(atPath: gamePath.path) else {
            showPopup(
                title: "Path not found",
                message: "Game path does not exist: \(gamePath.path)"
            )
            statusWindow.hide()
            log("Game path not found: \(gamePath.path) [source=\(gameExeLocation)]")
            return
        }

        let gameURL = URL(fileURLWithPath: gamePath.path, isDirectory: true)
        _ = DispatchQueue.main.sync {
            NSWorkspace.shared.open(gameURL)
        }

        statusWindow.hide()
        log("Opened game path: \(gamePath.path) [source=\(gameExeLocation)]")
    }

    private func hasSteamInstallInPrefix() -> Bool {
        let steamappsPath = paths.winePrefix.path + "/drive_c/Program Files (x86)/Steam/steamapps"
        let steamIDs = ["39140", "39150"]

        for gameID in steamIDs {
            let appManifest = "\(steamappsPath)/appmanifest_\(gameID).acf"
            if FileManager.default.fileExists(atPath: appManifest) {
                return true
            }
        }

        return false
    }

    private func openSavePathInFinder() {
        showStatusMessage("Locating save path...", style: .informational)

        if hasSteamInstallInPrefix() {
            let steamUserPath = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(product.steamUserRelativePath)

            do {
                try FileManager.default.createDirectory(at: steamUserPath, withIntermediateDirectories: true)
                _ = DispatchQueue.main.sync {
                    NSWorkspace.shared.open(steamUserPath)
                }
                statusWindow.hide()
                log("Opened save path (Steam user path): \(steamUserPath.path)")
                return
            } catch {
                showPopup(
                    title: "Path not found",
                    message: "Could not open Steam save path for \(product.gameDisplayName)."
                )
                statusWindow.hide()
                log("Failed to open Steam save path: \(error.localizedDescription)")
                return
            }
        }

        guard let gameExeLocation = readGameExecutableLocationFromSettingsXML() else {
            showPopup(
                title: "Path not found",
                message: "Could not read FF7Exe/FF8Exe from settings.xml for \(product.displayName)."
            )
            statusWindow.hide()
            log("Could not resolve game executable path from settings.xml to open save folder")
            return
        }

        let gameURL = convertWindowsPathToPrefixPath(gameExeLocation).deletingLastPathComponent()
        let saveCandidates = [
            gameURL.appendingPathComponent("save", isDirectory: true),
            gameURL.appendingPathComponent("Save", isDirectory: true)
        ]

        if let savePath = saveCandidates.first(where: { FileManager.default.fileExists(atPath: $0.path) }) {
            _ = DispatchQueue.main.sync {
                NSWorkspace.shared.open(savePath)
            }
            statusWindow.hide()
            log("Opened save path (game save folder): \(savePath.path)")
            return
        }

        showPopup(
            title: "Path not found",
            message: "Could not find a save folder inside \(product.gameDisplayName) game path."
        )
        statusWindow.hide()
        log("No save folder found inside game path: \(gameURL.path) [source=\(gameExeLocation)]")
    }

    private func openLogsPathInFinder() {
        showStatusMessage("Locating logs path...", style: .informational)

        let logsPath = paths.winePrefix.appendingPathComponent(product.targetExeProfilePath)

        guard FileManager.default.fileExists(atPath: logsPath.path) else {
            showPopup(
                title: "Path not found",
                message: "Could not find logs path for \(product.displayName)."
            )
            statusWindow.hide()
            log("Logs path not found: \(logsPath.path)")
            return
        }

        _ = DispatchQueue.main.sync {
            NSWorkspace.shared.open(logsPath)
        }
        statusWindow.hide()
        log("Opened logs path: \(logsPath.path)")
    }

    private func readLibraryLocationFromSettingsXML() -> String? {
        let settingsXML = paths.winePrefix
            .appendingPathComponent(product.targetExeProfilePath)
            .appendingPathComponent("settings.xml")

        guard let content = try? String(contentsOf: settingsXML, encoding: .utf8) else {
            log("Could not read settings.xml at: \(settingsXML.path)")
            return nil
        }

        let pattern = "<LibraryLocation>(.*?)</LibraryLocation>"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]) else {
            log("Failed to compile XML regex for LibraryLocation")
            return nil
        }

        let range = NSRange(content.startIndex..., in: content)
        guard let match = regex.firstMatch(in: content, options: [], range: range),
              let valueRange = Range(match.range(at: 1), in: content) else {
            log("LibraryLocation key not found in settings.xml")
            return nil
        }

        let raw = String(content[valueRange]).trimmingCharacters(in: .whitespacesAndNewlines)
        return raw.isEmpty ? nil : raw
    }

    private func readGameExecutableLocationFromSettingsXML() -> String? {
        let settingsXML = paths.winePrefix
            .appendingPathComponent(product.targetExeProfilePath)
            .appendingPathComponent("settings.xml")

        guard let content = try? String(contentsOf: settingsXML, encoding: .utf8) else {
            log("Could not read settings.xml at: \(settingsXML.path)")
            return nil
        }

        let keys = ["FF7Exe", "FF8Exe"]
        for key in keys {
            let pattern = "<\(key)>(.*?)</\(key)>"
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]) else {
                continue
            }

            let range = NSRange(content.startIndex..., in: content)
            guard let match = regex.firstMatch(in: content, options: [], range: range),
                  let valueRange = Range(match.range(at: 1), in: content) else {
                continue
            }

            let raw = String(content[valueRange]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !raw.isEmpty {
                return raw
            }
        }

        log("FF7Exe/FF8Exe keys not found in settings.xml")
        return nil
    }

    private func convertWindowsPathToPrefixPath(_ path: String) -> URL {
        let normalized = path.replacingOccurrences(of: "\\", with: "/")

        if let drive = normalized.first, normalized.dropFirst().hasPrefix(":/") {
            let driveSuffix = String(normalized.dropFirst(3))
            let driveLetter = String(drive).lowercased()

            // Z: is Wine's mapping of the host root filesystem (/).
            if driveLetter == "z" {
                return URL(fileURLWithPath: "/" + driveSuffix)
            }

            return paths.winePrefix
                .appendingPathComponent("drive_\(driveLetter)")
                .appendingPathComponent(driveSuffix)
        }

        if normalized.hasPrefix("/") {
            return URL(fileURLWithPath: normalized)
        }

        return paths.winePrefix.appendingPathComponent(normalized)
    }

    private func openModLibraryPathInFinder() {
        showStatusMessage("Locating mod library path...", style: .informational)

        guard let libraryLocation = readLibraryLocationFromSettingsXML() else {
            showPopup(
                title: "Path not found",
                message: "Could not read LibraryLocation from settings.xml for \(product.displayName)."
            )
            statusWindow.hide()
            return
        }

        let modLibraryPath = convertWindowsPathToPrefixPath(libraryLocation)
        guard FileManager.default.fileExists(atPath: modLibraryPath.path) else {
            showPopup(
                title: "Path not found",
                message: "Mod library path does not exist: \(libraryLocation)"
            )
            statusWindow.hide()
            log("Mod library path not found: \(modLibraryPath.path) [source=\(libraryLocation)]")
            return
        }

        _ = DispatchQueue.main.sync {
            NSWorkspace.shared.open(modLibraryPath)
        }
        statusWindow.hide()
        log("Opened mod library path: \(modLibraryPath.path)")
    }

    private func runInstallerIfNeeded(customInstaller: URL? = nil) {
        if FileManager.default.fileExists(atPath: paths.targetExe.path) {
            log("\(product.displayName) already installed")
            return
        }

        log("\(product.displayName) not found, starting installation flow")
        initializeWinePrefixIfNeeded()

        if let customInstaller = customInstaller {
            log("Running custom game installer: \(customInstaller.path)")
            showStatusMessage(
                "Running \(product.gameDisplayName) installer. Please follow the on-screen instructions.",
                style: .informational
            )
            runCommand(paths.wineBin.path, args: [customInstaller.path])
            runCommand(paths.wineServer.path, args: ["-w"])
        } else if product.allowsCustomGameInstaller {
            log("No custom installer selected; continuing with Steam autodetect")
        }

        if !downloadInstaller() {
            showError("Failed to download \(product.displayName) installer. Please check your internet connection.")
            return
        }

        log("Launching installer...")
        showStatusMessage("Running \(product.displayName) installer. Please wait...", style: .informational)

        let installerExe = paths.appSupport.appendingPathComponent("\(product.installerFileBaseName).exe")
        runCommand(paths.wineBin.path, args: [installerExe.path, "/VERYSILENT"])
        runCommand(paths.wineServer.path, args: ["-w"])

        if !FileManager.default.fileExists(atPath: paths.targetExe.path) {
            showError("Something went wrong. Please check the log file.")
            return
        }

        log("\(product.displayName) installed successfully")

        do {
            try FileManager.default.removeItem(at: installerExe)
            log("Cleaned up installer executable")
        } catch {
            log("Warning: Failed to clean up installer: \(error.localizedDescription)")
        }
    }

    private func runMain() {
        log("=== \(product.displayName) Launcher started ===")

        guard FileManager.default.fileExists(atPath: paths.wineBin.path) else {
            showError("Wine runtime not found in app bundle. Please rebuild the application.")
            return
        }

        setupWineEnvironment()

        let shouldPromptForCustomInstaller =
            product.allowsCustomGameInstaller &&
            !FileManager.default.fileExists(atPath: paths.targetExe.path)
        let selectedCustomInstaller = shouldPromptForCustomInstaller ? promptForCustomGameInstaller() : nil

        if selectedCustomInstaller == nil {
            log("Locating \(product.gameDisplayName) installation...")
            guard let gameInstall = findGamePath() else {
                showError(
                    "Could not locate \(product.gameDisplayName) in your Steam library. Please ensure it is installed via Steam."
                )
                return
            }

            let steamInstall = isSteamInstall(gameInstall)
            ensureSteamUserDirectoriesIfNeeded(isSteamInstall: steamInstall)

            if steamInstall {
                guard copyGameIntoWinePrefix(from: gameInstall.path, installDir: gameInstall.installDir) != nil else {
                    showError(
                        "Failed to copy \(product.gameDisplayName) into the Wine prefix. Please check permissions and free disk space."
                    )
                    return
                }

                let steamPath = paths.winePrefix.path + "/drive_c/Program Files (x86)/Steam"
                copySteamVDFFiles(gameID: gameInstall.gameID, libraryPath: gameInstall.libraryPath, steamPath: steamPath)
                setupSteamRegistry(steamPath: steamPath)
            } else {
                log("Detected non-Steam install at \(gameInstall.path); skipping Steam copy and Steam registry sync")
            }
        }

        configureWineRegistry()

        runInstallerIfNeeded(customInstaller: selectedCustomInstaller)

        guard FileManager.default.fileExists(atPath: paths.targetExe.path) else {
            showError("\(product.displayName) executable not found after installation flow.")
            return
        }

        log("Launching \(product.displayName)...")
        let task = Process()
        task.executableURL = paths.wineBin
        task.arguments = [paths.targetExe.path]

        do {
            try task.run()
            statusWindow.hide()
            task.waitUntilExit()
        } catch {
            showError("Failed to launch \(product.displayName):\n\(error.localizedDescription)")
            return
        }

        log("=== \(product.displayName) exited ===")
    }
}

final class MenuBarAppDelegate: NSObject, NSApplicationDelegate, SPUUpdaterDelegate {
    private enum UpdateChannel: String, CaseIterable {
        case stable
        case canary

        var displayName: String {
            switch self {
            case .stable:
                return "Stable"
            case .canary:
                return "Canary"
            }
        }

        var appcastFileName: String {
            switch self {
            case .stable:
                return "appcast.xml"
            case .canary:
                return "appcast-canary.xml"
            }
        }

        var feedURL: URL? {
            URL(string: "https://julianxhokaxhiu.github.io/SummonKit/\(appcastFileName)")
        }
    }

    private enum SettingsKeys {
        static let updateChannel = "summonkit.updateChannel"
    }

    private let products: [LauncherProduct]
    private var launchersByID: [String: LauncherEngine] = [:]
    private var menuItemsByActionAndProduct: [String: [String: NSMenuItem]] = [:]
    private var runningProductIDs: Set<String> = []
    private var updaterController: SPUStandardUpdaterController?
    private var settingsWindow: NSWindow?
    private var channelPopupButton: NSPopUpButton?

    init(products: [LauncherProduct]) {
        self.products = products
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Start the Sparkle updater before building the menu so the
        // "Check for Updates…" item can reference it as its target.
        updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: self,
            userDriverDelegate: nil
        )
        // Migrate away from previously persisted feed overrides created by
        // deprecated APIs like setFeedURL(_:).
        updaterController?.updater.clearFeedURLFromUserDefaults()
        applySelectedUpdateChannelToSparkle()
        buildMenuBar()
    }

    private func buildMenuBar() {
        let mainMenu = NSMenu()

        let appMenuItem = NSMenuItem()
        mainMenu.addItem(appMenuItem)

        let appMenu = NSMenu(title: "SummonKit")
        appMenuItem.submenu = appMenu

        appMenu.addItem(withTitle: "About SummonKit", action: #selector(openAboutSummonKit(_:)), keyEquivalent: "")

        appMenu.addItem(NSMenuItem.separator())
        let settingsItem = NSMenuItem(
            title: "Settings\u{2026}",
            action: #selector(openSettingsWindow(_:)),
            keyEquivalent: ","
        )
        if let gear = NSImage(systemSymbolName: "gearshape", accessibilityDescription: "Settings") {
            gear.isTemplate = true
            settingsItem.image = gear
            settingsItem.onStateImage = nil
            settingsItem.offStateImage = nil
        }
        appMenu.addItem(settingsItem)

        let checkUpdatesItem = NSMenuItem(
            title: "Check for Updates\u{2026}",
            action: #selector(SPUStandardUpdaterController.checkForUpdates(_:)),
            keyEquivalent: ""
        )
        checkUpdatesItem.target = updaterController
        appMenu.addItem(checkUpdatesItem)

        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(withTitle: "Quit SummonKit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        for product in products {
            let gameMenuItem = NSMenuItem(title: product.gameMenuTitle, action: nil, keyEquivalent: "")
            let gameMenu = NSMenu(title: product.gameMenuTitle)

            let launchItem = NSMenuItem(
                title: "Launch \(product.displayName)",
                action: #selector(launchFromMenu(_:)),
                keyEquivalent: ""
            )
            launchItem.target = self
            launchItem.representedObject = product.id
            gameMenu.addItem(launchItem)

            let logsPathItem = NSMenuItem(
                title: "Open \(product.displayName) Profile path",
                action: #selector(openLogsPathFromMenu(_:)),
                keyEquivalent: ""
            )
            logsPathItem.target = self
            logsPathItem.representedObject = product.id
            gameMenu.addItem(logsPathItem)

            let modLibraryPathItem = NSMenuItem(
                title: "Open \(product.displayName) Mod Library path",
                action: #selector(openModLibraryPathFromMenu(_:)),
                keyEquivalent: ""
            )
            modLibraryPathItem.target = self
            modLibraryPathItem.representedObject = product.id
            gameMenu.addItem(modLibraryPathItem)

            gameMenu.addItem(NSMenuItem.separator())

            let gamePathItem = NSMenuItem(
                title: "Open Game Path",
                action: #selector(openGamePathFromMenu(_:)),
                keyEquivalent: ""
            )
            gamePathItem.target = self
            gamePathItem.representedObject = product.id
            gameMenu.addItem(gamePathItem)

            let savePathItem = NSMenuItem(
                title: "Open Save Path",
                action: #selector(openSavePathFromMenu(_:)),
                keyEquivalent: ""
            )
            savePathItem.target = self
            savePathItem.representedObject = product.id
            gameMenu.addItem(savePathItem)

            gameMenu.addItem(NSMenuItem.separator())

            let winecfgItem = NSMenuItem(
                title: "Open Winecfg",
                action: #selector(openWinecfgFromMenu(_:)),
                keyEquivalent: ""
            )
            winecfgItem.target = self
            winecfgItem.representedObject = product.id
            gameMenu.addItem(winecfgItem)

            let regeditItem = NSMenuItem(
                title: "Open Regedit",
                action: #selector(openRegeditFromMenu(_:)),
                keyEquivalent: ""
            )
            regeditItem.target = self
            regeditItem.representedObject = product.id
            gameMenu.addItem(regeditItem)

            let winePrefixItem = NSMenuItem(
                title: "Open Wine Prefix",
                action: #selector(openWinePrefixFromMenu(_:)),
                keyEquivalent: ""
            )
            winePrefixItem.target = self
            winePrefixItem.representedObject = product.id
            gameMenu.addItem(winePrefixItem)

            gameMenu.addItem(NSMenuItem.separator())

            let wipeInstallationItem = NSMenuItem(
                title: "Wipe Installation",
                action: #selector(wipeInstallationFromMenu(_:)),
                keyEquivalent: ""
            )
            wipeInstallationItem.target = self
            wipeInstallationItem.representedObject = product.id
            gameMenu.addItem(wipeInstallationItem)

            menuItemsByActionAndProduct["launch", default: [:]][product.id] = launchItem
            menuItemsByActionAndProduct["gamePath", default: [:]][product.id] = gamePathItem
            menuItemsByActionAndProduct["savePath", default: [:]][product.id] = savePathItem
            menuItemsByActionAndProduct["modLibraryPath", default: [:]][product.id] = modLibraryPathItem
            menuItemsByActionAndProduct["logsPath", default: [:]][product.id] = logsPathItem
            menuItemsByActionAndProduct["winecfg", default: [:]][product.id] = winecfgItem
            menuItemsByActionAndProduct["regedit", default: [:]][product.id] = regeditItem
            menuItemsByActionAndProduct["prefix", default: [:]][product.id] = winePrefixItem
            menuItemsByActionAndProduct["wipeInstallation", default: [:]][product.id] = wipeInstallationItem
            gameMenuItem.submenu = gameMenu
            mainMenu.addItem(gameMenuItem)
        }

        NSApp.mainMenu = mainMenu
    }

    private func selectedUpdateChannel() -> UpdateChannel {
        if let rawValue = UserDefaults.standard.string(forKey: SettingsKeys.updateChannel),
           let channel = UpdateChannel(rawValue: rawValue) {
            return channel
        }

        return .stable
    }

    private func saveUpdateChannel(_ channel: UpdateChannel) {
        UserDefaults.standard.set(channel.rawValue, forKey: SettingsKeys.updateChannel)
    }

    private func applySelectedUpdateChannelToSparkle() {
        let channel = selectedUpdateChannel()

        guard let feedURL = channel.feedURL else {
            NSSound.beep()
            return
        }

        // Feed URL is now provided via SPUUpdaterDelegate.
        // Keeping this path validation helps catch malformed URLs early.
        _ = feedURL
    }

    func feedURLString(for updater: SPUUpdater) -> String? {
        return selectedUpdateChannel().feedURL?.absoluteString
    }

    private func ensureSettingsWindow() {
        if settingsWindow != nil {
            return
        }

        let windowRect = NSRect(x: 0, y: 0, width: 420, height: 170)
        let window = NSWindow(
            contentRect: windowRect,
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "SummonKit Settings"
        window.center()
        window.isReleasedWhenClosed = false

        let contentView = NSView(frame: windowRect)

        let channelLabel = NSTextField(labelWithString: "Update Channel")
        channelLabel.frame = NSRect(x: 24, y: 102, width: 130, height: 24)

        let popup = NSPopUpButton(frame: NSRect(x: 160, y: 98, width: 220, height: 30), pullsDown: false)
        popup.target = self
        popup.action = #selector(updateChannelSelectionChanged(_:))

        for channel in UpdateChannel.allCases {
            popup.addItem(withTitle: channel.displayName)
            popup.lastItem?.representedObject = channel.rawValue
        }

        let currentChannel = selectedUpdateChannel()
        if let index = UpdateChannel.allCases.firstIndex(of: currentChannel) {
            popup.selectItem(at: index)
        }

        contentView.addSubview(channelLabel)
        contentView.addSubview(popup)

        window.contentView = contentView

        settingsWindow = window
        channelPopupButton = popup
    }

    @objc private func openSettingsWindow(_ sender: Any?) {
        ensureSettingsWindow()
        guard let window = settingsWindow else {
            NSSound.beep()
            return
        }

        if let popup = channelPopupButton,
           let index = UpdateChannel.allCases.firstIndex(of: selectedUpdateChannel()) {
            popup.selectItem(at: index)
        }

        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func updateChannelSelectionChanged(_ sender: NSPopUpButton) {
        guard let selectedItem = sender.selectedItem,
              let rawValue = selectedItem.representedObject as? String,
              let channel = UpdateChannel(rawValue: rawValue) else {
            NSSound.beep()
            return
        }

        saveUpdateChannel(channel)
        applySelectedUpdateChannelToSparkle()
    }

    @objc private func openAboutSummonKit(_ sender: Any?) {
        let info = Bundle.main.infoDictionary ?? [:]
        let version = (info["CFBundleShortVersionString"] as? String) ?? "Unknown"
        let build = (info[kCFBundleVersionKey as String] as? String) ?? "Unknown"

        let repoURLString = "https://github.com/julianxhokaxhiu/SummonKit"
        let repoAttributed = NSMutableAttributedString(string: "Project Home")
        let fullRange = NSRange(location: 0, length: repoAttributed.length)
        repoAttributed.addAttribute(.link, value: repoURLString, range: fullRange)
        repoAttributed.addAttribute(.foregroundColor, value: NSColor.linkColor, range: fullRange)

        NSApp.orderFrontStandardAboutPanel(options: [
            NSApplication.AboutPanelOptionKey.applicationName: "SummonKit",
            NSApplication.AboutPanelOptionKey.applicationVersion: version,
            NSApplication.AboutPanelOptionKey.version: "Build \(build)",
            NSApplication.AboutPanelOptionKey.credits: repoAttributed
        ])
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func launchFromMenu(_ sender: NSMenuItem) {
        guard let productID = sender.representedObject as? String else {
            NSSound.beep()
            return
        }

        performMenuAction(productID: productID, action: "launch")
    }

    @objc private func openWinecfgFromMenu(_ sender: NSMenuItem) {
        guard let productID = sender.representedObject as? String else {
            NSSound.beep()
            return
        }

        performMenuAction(productID: productID, action: "winecfg")
    }

    @objc private func openGamePathFromMenu(_ sender: NSMenuItem) {
        guard let productID = sender.representedObject as? String else {
            NSSound.beep()
            return
        }

        performMenuAction(productID: productID, action: "gamePath")
    }

    @objc private func openSavePathFromMenu(_ sender: NSMenuItem) {
        guard let productID = sender.representedObject as? String else {
            NSSound.beep()
            return
        }

        performMenuAction(productID: productID, action: "savePath")
    }

    @objc private func openModLibraryPathFromMenu(_ sender: NSMenuItem) {
        guard let productID = sender.representedObject as? String else {
            NSSound.beep()
            return
        }

        performMenuAction(productID: productID, action: "modLibraryPath")
    }

    @objc private func openLogsPathFromMenu(_ sender: NSMenuItem) {
        guard let productID = sender.representedObject as? String else {
            NSSound.beep()
            return
        }

        performMenuAction(productID: productID, action: "logsPath")
    }

    @objc private func openRegeditFromMenu(_ sender: NSMenuItem) {
        guard let productID = sender.representedObject as? String else {
            NSSound.beep()
            return
        }

        performMenuAction(productID: productID, action: "regedit")
    }

    @objc private func openWinePrefixFromMenu(_ sender: NSMenuItem) {
        guard let productID = sender.representedObject as? String else {
            NSSound.beep()
            return
        }

        performMenuAction(productID: productID, action: "prefix")
    }

    @objc private func wipeInstallationFromMenu(_ sender: NSMenuItem) {
        guard let productID = sender.representedObject as? String else {
            NSSound.beep()
            return
        }

        performMenuAction(productID: productID, action: "wipeInstallation")
    }

    private func performMenuAction(productID: String, action: String) {
        guard let product = products.first(where: { $0.id == productID }) else {
            NSSound.beep()
            return
        }

        if runningProductIDs.contains(productID) {
            NSSound.beep()
            return
        }

        runningProductIDs.insert(productID)
        setProductMenuItemsEnabled(productID: productID, isEnabled: false)

        let engine = LauncherEngine(product: product)
        launchersByID[productID] = engine

        let completion = { [weak self] in
            guard let self = self else {
                return
            }
            self.runningProductIDs.remove(productID)
            self.launchersByID[productID] = nil
            self.setProductMenuItemsEnabled(productID: productID, isEnabled: true)
        }

        switch action {
        case "launch":
            engine.start(completion: completion)
        case "gamePath":
            engine.openGamePath(completion: completion)
        case "savePath":
            engine.openSavePath(completion: completion)
        case "modLibraryPath":
            engine.openModLibraryPath(completion: completion)
        case "logsPath":
            engine.openLogsPath(completion: completion)
        case "winecfg":
            engine.openWineTool("winecfg", completion: completion)
        case "regedit":
            engine.openWineTool("regedit", completion: completion)
        case "prefix":
            engine.openWinePrefix(completion: completion)
        case "wipeInstallation":
            engine.wipeInstallation(completion: completion)
        default:
            completion()
            NSSound.beep()
        }
    }

    private func setProductMenuItemsEnabled(productID: String, isEnabled: Bool) {
        for actionItems in menuItemsByActionAndProduct.values {
            actionItems[productID]?.isEnabled = isEnabled
        }
    }
}

let providers: [any LauncherProductProviding] = [
    SeventhHeavenProvider(),
    JunctionVIIIProvider()
]

let allProducts: [LauncherProduct] = providers.map { $0.product }

let application = NSApplication.shared
let delegate = MenuBarAppDelegate(products: allProducts)
application.setActivationPolicy(.regular)
application.delegate = delegate
application.run()
