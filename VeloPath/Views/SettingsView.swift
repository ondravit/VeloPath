import SwiftUI
import VeloCore

struct SettingsView: View {
    @Environment(PlannerStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        @Bindable var store = store
        NavigationStack {
            Form {
                Section {
                    LabeledContent("Průměrná rychlost") {
                        Stepper(value: $store.averageSpeed, in: 12...45, step: 1) {
                            Text("\(Int(store.averageSpeed)) km/h").monospacedDigit()
                        }
                    }
                } header: {
                    Text("Odhad času")
                } footer: {
                    Text("Čas jízdy počítá s rychlostí po rovině a přidává zhruba minutu na každých 12 výškových metrů stoupání.")
                }

                Section("Mapa") {
                    Picker("Styl mapy", selection: $store.mapStyle) {
                        ForEach(MapStyleChoice.allCases) { Text($0.title).tag($0) }
                    }
                    Toggle("Zobrazit stav povrchu silnic", isOn: $store.showsConditionLayer)
                }

                Section {
                    ForEach(RoadCondition.known, id: \.self) { c in
                        HStack(spacing: 12) {
                            Capsule().fill(c.color).frame(width: 28, height: 6)
                            Text(c.title)
                        }
                    }
                } header: {
                    Text("Legenda stavu povrchu")
                } footer: {
                    Text("Klasifikace podle TP 87. Silnice bez známého stavu se v mapě nebarví a router je hodnotí jako průměrné.")
                }

                Section("Jak plánovat") {
                    HelpRow(icon: "hand.tap", text: "Klepnutím do mapy přidáte bod – první je start, poslední cíl.")
                    HelpRow(icon: "hand.point.up.left.and.text", text: "Dlouhým stiskem na trase vložíte zastávku do správného úseku.")
                    HelpRow(icon: "arrow.up.and.down.and.arrow.left.and.right", text: "Body lze přetáhnout; klepnutím na bod ho můžete odebrat.")
                    HelpRow(icon: "square.and.arrow.up", text: "Hotovou trasu exportujte jako GPX do Garminu, Wahoo, Stravy nebo Komootu.")
                }

                if let meta = store.metadata {
                    Section {
                        LabeledContent("Oblast", value: meta.region)
                        LabeledContent("Data připravena", value: Self.formatBuildDate(meta.built))
                        ForEach(meta.sources) { source in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(source.name).font(.subheadline.weight(.semibold))
                                Text(source.attribution).font(.footnote).foregroundStyle(.secondary)
                                HStack(spacing: 8) {
                                    if let license = source.license { Text(license) }
                                    if let date = source.date { Text("stav k \(date)") }
                                    if let years = source.years, years.count == 2 { Text("měření \(String(years[0]))–\(String(years[1]))") }
                                }
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                if let s = source.url, let url = URL(string: s) {
                                    Link("Zdroj dat", destination: url).font(.footnote)
                                }
                            }
                            .padding(.vertical, 2)
                        }
                    } header: {
                        Text("Mapová data")
                    } footer: {
                        Text("Mapový podklad © Apple. Silniční síť © přispěvatelé OpenStreetMap (ODbL).")
                    }
                }

                Section("O aplikaci") {
                    LabeledContent("Verze", value: Self.appVersion)
                    Text("VeloPath plánuje trasy pro silniční kolo po silnicích s nejlepším povrchem. Trasa se počítá přímo v telefonu – nic se neodesílá na server.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Nastavení")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Hotovo") { dismiss() }
                }
            }
        }
    }

    static var appVersion: String {
        let info = Bundle.main.infoDictionary
        let v = info?["CFBundleShortVersionString"] as? String ?? "?"
        let b = info?["CFBundleVersion"] as? String ?? "?"
        return "\(v) (\(b))"
    }

    static func formatBuildDate(_ iso: String) -> String {
        let parser = ISO8601DateFormatter()
        guard let date = parser.date(from: iso) else { return iso }
        return date.formatted(.dateTime.day().month(.wide).year().locale(Locale(identifier: "cs_CZ")))
    }
}

private struct HelpRow: View {
    let icon: String
    let text: String

    var body: some View {
        Label {
            Text(text).font(.subheadline)
        } icon: {
            Image(systemName: icon).foregroundStyle(.tint)
        }
    }
}
