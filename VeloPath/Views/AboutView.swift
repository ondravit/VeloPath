import SwiftUI

struct AboutView: View {
    var body: some View {
        NavigationStack {
            GeometryReader { geo in
                ScrollView {
                    VStack(spacing: 16) {
                        Image("VeloPath")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 80, height: 80)
                            .clipShape(RoundedRectangle(cornerRadius: 18))
                            .shadow(radius: 8)

                        Text("VeloPath")
                            .font(.title.bold())

                        Text("Cyklistická mapa kvality povrchu silnic.\nAplikace zobrazuje silnice podle jejich stavu povrchu, aby si cyklisté mohli plánovat bezpečnější a příjemnější trasy.")
                            .multilineTextAlignment(.center)
                            .foregroundStyle(.secondary)
                            .padding(.bottom, 4)

                        // MARK: Legend
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Legenda")
                                .font(.headline)
                                .padding(.bottom, 4)

                            ConditionRow(color: Color(red: 0.0, green: 0.3, blue: 0.0), label: "Výborný")
                            ConditionRow(color: .green,  label: "Dobrý")
                            ConditionRow(color: .yellow, label: "Vyhovující")
                            ConditionRow(color: .orange, label: "Nevyhovující")
                            ConditionRow(color: .red,    label: "Havarijní")
                            ConditionRow(color: .purple, label: "Superhavarijní")
                            ConditionRow(color: .gray,   label: "Neznámý")
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                        .background(Color(.systemGray6))
                        .clipShape(RoundedRectangle(cornerRadius: 12))

                        Spacer(minLength: 0)

                        // MARK: Footer
                        VStack(spacing: 4) {
                            Divider().padding(.vertical, 8)
                            if let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String {
                                Text("VeloPath \(version)")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                            Text("© Ondřej Vít 2025")
                                .font(.footnote)
                                .foregroundStyle(.secondary.opacity(0.7))
                        }
                        .padding(.top, 8)
                    }
                    .padding()
                    .frame(minHeight: geo.size.height, alignment: .top)
                }
            }
            .navigationTitle("O aplikaci")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

// MARK: - Condition legend row

struct ConditionRow: View {
    let color: Color
    let label: String

    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 3)
                .fill(color)
                .frame(width: 40, height: 6)
            Text(label)
                .font(.subheadline)
        }
    }
}
