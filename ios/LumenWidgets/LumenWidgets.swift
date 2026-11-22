import SwiftUI
import WidgetKit

enum LumenWidgetPalette {
    static let accent = Color(red: 1.00, green: 0.761, blue: 0.290)
    static let accent2 = Color(red: 1.00, green: 0.541, blue: 0.239)
    static let ink = Color(red: 0.25, green: 0.14, blue: 0.05)
    static let inkSoft = Color(red: 0.35, green: 0.20, blue: 0.08)
    static let fieldTop = Color(red: 250 / 255, green: 220 / 255, blue: 150 / 255)
    static let fieldBottom = Color(red: 236 / 255, green: 192 / 255, blue: 88 / 255)
}

struct TalkEntry: TimelineEntry {
    let date: Date
}

struct TalkProvider: TimelineProvider {
    func placeholder(in context: Context) -> TalkEntry { TalkEntry(date: .now) }
    func getSnapshot(in context: Context, completion: @escaping (TalkEntry) -> Void) {
        completion(TalkEntry(date: .now))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<TalkEntry>) -> Void) {
        completion(Timeline(entries: [TalkEntry(date: .now)], policy: .never))
    }
}

struct TalkHomeView: View {
    var entry: TalkEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        Group {
            if family == .systemMedium {
                medium
            } else {
                small
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var small: some View {
        VStack(spacing: 8) {
            orb.frame(width: 72, height: 72)
            Text("Tap to talk")
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(LumenWidgetPalette.ink)
                .minimumScaleFactor(0.8)
                .lineLimit(1)
        }
        .padding(8)
    }

    private var medium: some View {
        HStack(spacing: 16) {
            orb.frame(width: 88, height: 88)
            VStack(alignment: .leading, spacing: 4) {
                Text("Lumen")
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                    .foregroundStyle(LumenWidgetPalette.ink)
                Text("Tap to talk")
                    .font(.system(size: 16, weight: .medium, design: .rounded))
                    .foregroundStyle(LumenWidgetPalette.inkSoft)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 16)
    }

    private var orb: some View {
        Image("LumenOrb")
            .resizable()
            .scaledToFit()
            .accessibilityHidden(true)
    }
}

struct TalkHomeWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "lumen.talk.homescreen", provider: TalkProvider()) { entry in
            TalkHomeView(entry: entry)
                .containerBackground(for: .widget) {
                    LinearGradient(
                        colors: [LumenWidgetPalette.fieldTop, LumenWidgetPalette.fieldBottom],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                }
                .widgetURL(URL(string: "lumenvoice://listen"))
        }
        .configurationDisplayName("Lumen")
        .description("Starts listening.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

@main
struct LumenWidgetsBundle: WidgetBundle {
    var body: some Widget {
        TalkHomeWidget()
    }
}
