import Foundation

struct MemoriaProvider: LauncherProductProviding {
    let product = LauncherProduct(
        id: "memoria",
        gameMenuTitle: "FF9",
        displayName: "Memoria",
        statusWindowTitle: "Memoria - Status",
        launchBanner: "Launching Memoria...",
        githubApiURL: "https://api.github.com/repos/julianxhokaxhiu/Memoria/releases/latest",
        installerFileBaseName: "Memoria.Patcher",
        targetExeRelativePath: "./FF9_Launcher.exe",
        targetExeProfilePath: "./",
        appSupportFolderName: "Memoria",
        gameDisplayName: "FINAL FANTASY IX",
        steamGameDirectoryName: "FINAL FANTASY IX",
        steamGameIDs: ["377840"],
        gogFallbackRelativePath: "drive_c/GOG Games/FINAL FANTASY IX",
        steamUserRelativePath: "drive_c/Users/\(NSUserName())/AppData/LocalLow/SquareEnix/FINAL FANTASY IX/Steam/EncryptedSavedData",
        wineAppDefaultExeName: "FF9_Launcher.exe",
        wineDLLOverrides: "xaudio2_9=n,b",
        allowsCustomGameInstaller: true
    )
}