// swift-tools-version:5.10
// DevisMinuteKit — moteur métier de DevisMinute, indépendant de l'interface.
//
// Aucun module n'importe UIKit/SwiftUI/SwiftData : tout le code est testable
// sur macOS, iOS et Linux (`swift test`).
//
// Dépendances : aucune sur les plateformes Apple (CryptoKit est utilisé).
// Sous Linux uniquement, swift-crypto (Apple, licence Apache 2.0) fournit la
// même API que CryptoKit pour pouvoir exécuter les tests en intégration continue.
import PackageDescription

let package = Package(
    name: "DevisMinuteKit",
    defaultLocalization: "fr",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "DevisCore", targets: ["DevisCore"]),
        .library(name: "DevisPDF", targets: ["DevisPDF"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-crypto.git", "3.0.0" ..< "4.0.0"),
    ],
    targets: [
        .target(
            name: "DevisCore",
            dependencies: [
                .product(name: "Crypto", package: "swift-crypto", condition: .when(platforms: [.linux])),
            ]
        ),
        .target(name: "DevisPDF", dependencies: ["DevisCore"]),
        .testTarget(name: "DevisCoreTests", dependencies: ["DevisCore"]),
        .testTarget(name: "DevisPDFTests", dependencies: ["DevisCore", "DevisPDF"]),
    ]
)
