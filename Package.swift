// swift-tools-version: 5.9
//
//  Package.swift
//  TKoolib
//
//  本地 SwiftPM 描述文件（由 PandoraLand 重构工程添加）：
//  上游原本只有 Xcode 工程，这里补一份 manifest，便于以本地包形式依赖。
//

import PackageDescription

let package = Package(
    name: "TKoolib",
    platforms: [.iOS(.v17)],
    products: [
        .library(name: "ListKit", targets: ["ListKit"]),
        .library(name: "RouterKit", targets: ["RouterKit"])
    ],
    targets: [
        .target(name: "ListKit", path: "ListKit"),
        .target(name: "RouterKit", path: "RouterKit")
    ]
)
