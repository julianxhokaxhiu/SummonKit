import Foundation

struct JunctionVIIIProvider: LauncherProductProviding {
    let product = LauncherProduct(
        id: "junction-viii",
        gameMenuTitle: "FF8",
        displayName: "Junction VIII",
        statusWindowTitle: "Junction VIII - Status",
        launchBanner: "Launching Junction VIII...",
        githubApiURL: "https://api.github.com/repos/tsunamods-codes/Junction-VIII/releases/latest",
        installerFileBaseName: "JunctionVIII-installer",
        targetExeRelativePath: "drive_c/Users/\(NSUserName())/AppData/Local/Programs/Junction VIII/Junction VIII.exe",
        targetExeProfilePath: "drive_c/Users/\(NSUserName())/AppData/Local/Programs/Junction VIII/J8Workshop",
        appSupportFolderName: "Junction VIII",
        gameDisplayName: "FINAL FANTASY VIII",
        steamGameDirectoryName: "FINAL FANTASY VIII",
        steamGameIDs: ["39150"],
        gogFallbackRelativePath: "drive_c/GOG Games/FINAL FANTASY VIII",
        steamUserRelativePath: "Documents/Square Enix/FINAL FANTASY VIII Steam/user_12345678",
        wineAppDefaultExeName: "Junction VIII.exe",
        allowsCustomGameInstaller: false
    )
}