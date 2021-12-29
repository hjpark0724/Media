// swift-tools-version:5.5
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription
var dependencies: [Package.Dependency] = [
    .package(
         url: "https://github.com/apple/swift-atomics.git",
         .upToNextMajor(from: "1.0.0")
       ),
    .package(name: "Logging", url: "https://github.com/hjpark0724/Logging.git", branch: "main"),
    .package(name: "Utils", url: "https://github.com/hjpark0724/Utils.git", branch: "main")
    ]

var targetDependencies :[Target.Dependency] = [
    .product(name: "Atomics", package: "swift-atomics"),
    .byName(name: "Logging"),
    .byName(name: "Utils"),
    .byName(name: "libyuv"),
    .byName(name: "AudioCodecs"),
]

var targets: [Target] = [
    .target(name: "AudioCodecs",
            exclude: [
                "AmrWB/readme.txt",
                "AmrWB/makefile.gcc",
                "AmrWB/grid100.tab",
                "AmrWB/homing.tab",
                "AmrWB/ham_wind.tab",
                "AmrWB/isp_isf.tab",
                "AmrWB/lag_wind.tab",
                "AmrWB/p_med_ol.tab",
                "AmrWB/q_gain2.tab",
                "AmrWB/qisf_ns.tab",
                "AmrWB/qpisf_2s.tab",
    ]),
    .target(name: "libyuv"),
    .target(name: "Media", dependencies: targetDependencies),
    .testTarget(
        name: "MediaTests",
        dependencies: ["Media"]),
]

let package = Package(
    name: "Media",
    platforms: [.iOS(.v11)],
    products: [
        // Products define the executables and libraries a package produces, and make them visible to other packages.
        .library(
            name: "Media",
            targets: ["Media"]),
    ],
    dependencies: dependencies,
    targets: targets,
    cxxLanguageStandard: .cxx17
)
