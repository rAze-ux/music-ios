import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("automixEnabled") private var automix = true
    @AppStorage("crossfadeSeconds") private var fade = 4.0
    @AppStorage("eqEnabled") private var eqOn = false
    @AppStorage("eqPreset") private var preset = "Flat"
    @AppStorage("eqCustom") private var custom = "0,0,0,0,0,0,0,0,0,0"
    @State private var customGains: [Double] = Array(repeating: 0, count: EQPresets.frequencies.count)

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("Автомикс", isOn: $automix)
                    if automix {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Длина перехода: \(Int(fade)) сек")
                                .font(.subheadline)
                            Slider(value: $fade, in: 1...8, step: 1)
                                .tint(.amRed)
                        }
                        Text("Перед концом трека плеер ищет похожую песню — по темпу (BPM) или жанру — и плавно сращивает их, как диджей.")
                            .font(.footnote)
                            .foregroundColor(.secondary)
                    }
                } header: {
                    Text("Автомикс")
                }

                Section {
                    Toggle("Эквалайзер", isOn: $eqOn)
                    Picker("Пресет", selection: $preset) {
                        ForEach(EQPresets.names, id: \.self) { Text($0) }
                    }
                    if preset == "Custom" {
                        ForEach(0..<EQPresets.frequencies.count, id: \.self) { i in
                            HStack(spacing: 10) {
                                Text(EQPresets.labels[i])
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                    .frame(width: 32, alignment: .leading)
                                Slider(
                                    value: Binding(
                                        get: { customGains.indices.contains(i) ? customGains[i] : 0 },
                                        set: { customGains[i] = $0; saveCustom() }
                                    ),
                                    in: -12...12,
                                    step: 1
                                )
                                .tint(.amRed)
                                Text("\(Int(customGains.indices.contains(i) ? customGains[i] : 0))")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                    .frame(width: 26, alignment: .trailing)
                            }
                        }
                    } else {
                        Text("10 полос: 31 Гц – 16 кГц. Для ручной настройки полос выберите пресет «Custom».")
                            .font(.footnote)
                            .foregroundColor(.secondary)
                    }
                } header: {
                    Text("Эквалайзер")
                }

                Section {
                    Button(role: .destructive) {
                        NotificationCenter.default.post(name: .amResetPlayStats, object: nil)
                    } label: {
                        Text("Сбросить статистику прослушиваний")
                    }
                } footer: {
                    Text("Плеер: «Музыка» 1.1. Исходники: github.com/rAze-ux/music-ios")
                }
            }
            .navigationTitle("Настройки")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Готово") { dismiss() }
                }
            }
            .onAppear { loadCustom() }
            .onChange(of: preset) { _ in loadCustom() }
        }
    }

    private func loadCustom() {
        let parts = custom.split(separator: ",").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
        if parts.count == EQPresets.frequencies.count {
            customGains = parts
        } else {
            customGains = Array(repeating: 0, count: EQPresets.frequencies.count)
        }
    }

    private func saveCustom() {
        custom = customGains.map { String(Int($0)) }.joined(separator: ",")
    }
}
