import SwiftUI

/// Petite fête à l'écran quand une facture est soldée ou qu'un devis est signé :
/// coche animée, confettis aux couleurs de l'application et retour haptique.
struct CelebrationOverlay: View {
    let title: String
    let subtitle: String
    let onFinish: () -> Void

    @State private var appeared = false
    @State private var start = Date()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private struct Piece {
        let angle: Double
        let speed: Double
        let spin: Double
        let color: Color
        let size: CGSize
    }

    private static let colors: [Color] = [Theme.petrol, Theme.ochre, Theme.success, Color(red: 0.95, green: 0.78, blue: 0.42), Theme.ivory]
    @State private var pieces: [Piece] = (0..<70).map { index in
        Piece(
            angle: Double.random(in: -Double.pi * 0.95 ... -Double.pi * 0.05),
            speed: Double.random(in: 260...620),
            spin: Double.random(in: -8...8),
            color: CelebrationOverlay.colors[index % CelebrationOverlay.colors.count],
            size: CGSize(width: Double.random(in: 6...11), height: Double.random(in: 4...7))
        )
    }

    var body: some View {
        ZStack {
            Color.black.opacity(appeared ? 0.25 : 0).ignoresSafeArea()
            if !reduceMotion {
                TimelineView(.animation) { context in
                    let elapsed = context.date.timeIntervalSince(start)
                    Canvas { canvas, size in
                        let origin = CGPoint(x: size.width / 2, y: size.height * 0.45)
                        for piece in pieces {
                            let x = origin.x + cos(piece.angle) * piece.speed * elapsed
                            let y = origin.y + sin(piece.angle) * piece.speed * elapsed + 520 * elapsed * elapsed
                            var context = canvas
                            context.opacity = max(0, 1 - elapsed / 2.2)
                            context.translateBy(x: x, y: y)
                            context.rotate(by: .radians(piece.spin * elapsed))
                            context.fill(Path(CGRect(origin: CGPoint(x: -piece.size.width / 2, y: -piece.size.height / 2), size: piece.size)), with: .color(piece.color))
                        }
                    }
                }
                .ignoresSafeArea()
                .allowsHitTesting(false)
            }
            VStack(spacing: Theme.Space.m) {
                Image(systemName: "checkmark")
                    .font(.system(size: 40, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 88, height: 88)
                    .background(Theme.success, in: Circle())
                    .scaleEffect(appeared ? 1 : 0.3)
                Text(title).font(.title2.weight(.bold)).foregroundStyle(Theme.ink)
                Text(subtitle).font(.subheadline).foregroundStyle(Theme.neutral).multilineTextAlignment(.center)
            }
            .padding(Theme.Space.xxl)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 24))
            .scaleEffect(appeared ? 1 : 0.8)
            .opacity(appeared ? 1 : 0)
            .padding(Theme.Space.xxl)
            .accessibilityElement(children: .combine)
        }
        .sensoryFeedback(.success, trigger: appeared) { _, shown in shown }
        .onTapGesture(perform: onFinish)
        .task {
            start = Date()
            withAnimation(.spring(response: 0.45, dampingFraction: 0.6)) { appeared = true }
            try? await Task.sleep(for: .seconds(2.2))
            withAnimation(.easeOut(duration: 0.25)) { appeared = false }
            try? await Task.sleep(for: .milliseconds(260))
            onFinish()
        }
    }
}

/// Événement à fêter.
struct Celebration: Identifiable, Equatable {
    let id = UUID()
    let title: String
    let subtitle: String
}

extension View {
    /// Affiche `CelebrationOverlay` par-dessus la vue tant que `celebration` n'est pas nil.
    func celebration(_ celebration: Binding<Celebration?>) -> some View {
        overlay {
            if let current = celebration.wrappedValue {
                CelebrationOverlay(title: current.title, subtitle: current.subtitle) { celebration.wrappedValue = nil }
                    .id(current.id)
                    .transition(.opacity)
            }
        }
    }
}
