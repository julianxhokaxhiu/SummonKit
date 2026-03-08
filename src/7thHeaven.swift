import Foundation

struct SeventhHeavenProvider: LauncherProductProviding {
    let product = LauncherProduct(
        id: "7th-heaven",
        gameMenuTitle: "FF7",
        displayName: "7th Heaven",
        statusWindowTitle: "7th Heaven - Status",
        launchBanner: "Launching 7th Heaven...",
        githubApiURL: "https://api.github.com/repos/tsunamods-codes/7th-Heaven/releases/latest",
        installerFileBaseName: "7thHeaven-installer",
        targetExeRelativePath: "drive_c/Users/\(NSUserName())/AppData/Local/Programs/7th Heaven/7th Heaven.exe",
        targetExeProfilePath: "drive_c/Users/\(NSUserName())/AppData/Local/Programs/7th Heaven/7thWorkshop",
        appSupportFolderName: "7th Heaven",
        gameDisplayName: "Final Fantasy VII",
        steamGameDirectoryName: "FINAL FANTASY VII",
        steamGameIDs: ["39140", "3837340"],
        gogFallbackRelativePath: "drive_c/GOG Games/Final Fantasy VII",
        steamUserRelativePath: "Documents/Square Enix/FINAL FANTASY VII Steam/user_12345678",
        wineAppDefaultExeName: "7th Heaven.exe",
        allowsCustomGameInstaller: true
    )
}
