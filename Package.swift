// swift-tools-version:5.1
 import PackageDescription

  let package = Package(
     name: "YYText",
     platforms: [.iOS(.v13)],
     products: [
         .library(
             name: "YYText",
             targets: ["YYText"]),
     ],
     targets: [
         .target(
             name: "YYText"//,
        )
//             cSettings: [
//                 .headerSearchPath("Component"),
//                 .headerSearchPath("String"),
//                 .headerSearchPath("Utility"),
//             ]),
     ]
 )