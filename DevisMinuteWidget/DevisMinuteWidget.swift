import WidgetKit
import SwiftUI
import DevisCore

// MARK: - Données

struct SnapshotEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot
    let isPlaceholder: Bool
}

struct SnapshotProvider: TimelineProvider {
    static let appGroup = "group.com.devisminute.app"

    func placeholder(in context: Context) -> SnapshotEntry {
        SnapshotEntry(date: Date(), snapshot: .placeholder, isPlaceholder: true)
    }

    func getSnapshot(in context: Context, completion: @escaping (SnapshotEntry) -> Void) {
        completion(context.isPreview ? placeholder(in: context) : entry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SnapshotEntry>) -> Void) {
        // L'application redemande un rafraîchissement à chaque modification ;
        // une mise à jour horaire suffit pour faire évoluer les retards.
        completion(Timeline(entries: [entry()], policy: .after(Date().addingTimeInterval(3600))))
    }

    private func entry() -> SnapshotEntry {
        guard let url = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: Self.appGroup)?.appendingPathComponent(WidgetSnapshot.fileName),
              let data = try? Data(contentsOf: url),
              let snapshot = try? JSONDecoder().decode(WidgetSnapshot.self, from: data) else {
            return SnapshotEntry(date: Date(), snapshot: .empty, isPlaceholder: false)
        }
        return SnapshotEntry(date: Date(), snapshot: snapshot, isPlaceholder: false)
    }
}

extension WidgetSnapshot {
    static let empty = WidgetSnapshot(generatedAt: Date(), companyName: "", outstanding: 0, unpaidCount: 0, overdueAmount: 0, overdueCount: 0,
                                      monthInvoicedHT: 0, monthCollected: 0, monthGoal: nil, upcoming: [], isPrivate: false)
}

// MARK: - Couleurs (identiques à l'application)

enum WidgetColors {
    static let petrol = Color(red: 0.141, green: 0.353, blue: 0.392)
    static let petrolDark = Color(red: 0.106, green: 0.278, blue: 0.314)
    static let ivory = Color(red: 0.961, green: 0.953, blue: 0.933)
    static let ink = Color(red: 0.145, green: 0.165, blue: 0.169)
    static let ochre = Color(red: 0.816, green: 0.541, blue: 0.271)
    static let alert = Color(red: 0.93, green: 0.55, blue: 0.42)
}

private func amount(_ value: Decimal, hidden: Bool) -> String {
    hidden ? "•••• €" : Money.format(value)
}

// MARK: - Widget « À encaisser »

struct OutstandingWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: SnapshotEntry

    var body: some View {
        let snapshot = entry.snapshot
        switch family {
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 1) {
                Text("À encaisser").font(.caption2.weight(.semibold))
                Text(amount(snapshot.outstanding, hidden: snapshot.isPrivate)).font(.headline).minimumScaleFactor(0.6)
                if snapshot.overdueCount > 0 {
                    Text("\(snapshot.overdueCount) en retard").font(.caption2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .containerBackground(.clear, for: .widget)
        case .systemMedium:
            HStack(spacing: 14) {
                summary(snapshot)
                VStack(alignment: .leading, spacing: 6) {
                    Text("À suivre").font(.caption.weight(.semibold)).foregroundStyle(.white.opacity(0.7))
                    if snapshot.upcoming.isEmpty {
                        Text("Aucune facture en attente").font(.caption).foregroundStyle(.white.opacity(0.85))
                    }
                    ForEach(snapshot.upcoming.prefix(3)) { due in
                        VStack(alignment: .leading, spacing: 0) {
                            Text(due.customer).font(.caption.weight(.semibold)).lineLimit(1)
                            Text("\(amount(due.amount, hidden: snapshot.isPrivate)) · \(due.isOverdue ? "en retard" : "le " + due.dueDate.formatted(.dateTime.day().month(.abbreviated).locale(Locale(identifier: "fr_FR"))))")
                                .font(.caption2)
                                .foregroundStyle(due.isOverdue ? WidgetColors.alert : .white.opacity(0.75))
                                .lineLimit(1)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .foregroundStyle(.white)
            .containerBackground(for: .widget) { background }
        default:
            summary(snapshot)
                .foregroundStyle(.white)
                .containerBackground(for: .widget) { background }
        }
    }

    private var background: some View {
        LinearGradient(colors: [WidgetColors.petrol, WidgetColors.petrolDark], startPoint: .top, endPoint: .bottom)
    }

    private func summary(_ snapshot: WidgetSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label("À encaisser", systemImage: "eurosign.circle.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white.opacity(0.85))
            Text(amount(snapshot.outstanding, hidden: snapshot.isPrivate))
                .font(.system(size: 26, weight: .bold, design: .rounded))
                .minimumScaleFactor(0.5)
                .lineLimit(1)
            Text(snapshot.unpaidCount == 0 ? "Tout est encaissé" : "\(snapshot.unpaidCount) facture\(snapshot.unpaidCount > 1 ? "s" : "")")
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.8))
            Spacer(minLength: 0)
            if snapshot.overdueCount > 0 {
                Text("\(amount(snapshot.overdueAmount, hidden: snapshot.isPrivate)) en retard")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(WidgetColors.ink)
                    .padding(.horizontal, 7).padding(.vertical, 3)
                    .background(WidgetColors.alert, in: Capsule())
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct OutstandingWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "DevisMinuteOutstanding", provider: SnapshotProvider()) { entry in
            OutstandingWidgetView(entry: entry)
        }
        .configurationDisplayName("À encaisser")
        .description("Ce qui reste à encaisser et les factures en retard.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular])
    }
}

// MARK: - Widget « Objectif du mois »

struct GoalWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: SnapshotEntry

    var body: some View {
        let snapshot = entry.snapshot
        let progress = snapshot.goalProgress ?? 0
        switch family {
        case .accessoryCircular:
            Gauge(value: min(progress, 1)) {
                Text("Objectif")
            } currentValueLabel: {
                Text(snapshot.monthGoal == nil ? "—" : "\(Int((progress * 100).rounded()))%")
            }
            .gaugeStyle(.accessoryCircularCapacity)
            .containerBackground(.clear, for: .widget)
        default:
            VStack(alignment: .leading, spacing: 6) {
                Text("Objectif du mois").font(.caption.weight(.semibold)).foregroundStyle(WidgetColors.petrol)
                ZStack {
                    Circle().stroke(WidgetColors.petrol.opacity(0.15), lineWidth: 9)
                    Circle()
                        .trim(from: 0, to: min(progress, 1))
                        .stroke(progress >= 1 ? WidgetColors.ochre : WidgetColors.petrol, style: StrokeStyle(lineWidth: 9, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    Text(snapshot.monthGoal == nil ? "—" : "\(Int((progress * 100).rounded())) %")
                        .font(.system(.headline, design: .rounded, weight: .bold))
                        .foregroundStyle(WidgetColors.ink)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 2)
                Text(snapshot.monthGoal == nil ? "Fixez un objectif dans l'app" : "\(amount(snapshot.monthInvoicedHT, hidden: snapshot.isPrivate)) HT")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(WidgetColors.ink.opacity(0.75))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .frame(maxWidth: .infinity)
            }
            .containerBackground(WidgetColors.ivory, for: .widget)
        }
    }
}

struct GoalWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "DevisMinuteGoal", provider: SnapshotProvider()) { entry in
            GoalWidgetView(entry: entry)
        }
        .configurationDisplayName("Objectif du mois")
        .description("Votre chiffre d'affaires du mois face à votre objectif.")
        .supportedFamilies([.systemSmall, .accessoryCircular])
    }
}

@main
struct DevisMinuteWidgets: WidgetBundle {
    var body: some Widget {
        OutstandingWidget()
        GoalWidget()
    }
}
