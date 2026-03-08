// swift-tools-version:5.9

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

import PackageDescription

let package = Package(
    name: "SummonKit",
    platforms: [
        .macOS(.v13)
    ],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.0.0")
    ],
    targets: [
        .executableTarget(
            name: "SummonKit",
            dependencies: [
                .product(name: "Sparkle", package: "Sparkle")
            ],
            path: "src"
        )
    ]
)
