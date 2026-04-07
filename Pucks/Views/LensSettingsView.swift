import SwiftUI

struct LensSettingsView: View {
    @ObservedObject var config = LensConfiguration.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(.blue)

                Text("Liquid Glass Lens")
                    .font(.headline)
                    .foregroundColor(.white)

                Spacer()

                Toggle("", isOn: $config.isEnabled)
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .onChange(of: config.isEnabled) { _, enabled in
                        if enabled {
                            LensWindowManager.shared.show()
                        } else {
                            LensWindowManager.shared.hide()
                        }
                    }
            }

            if config.isEnabled {
                VStack(alignment: .leading, spacing: 12) {
                    // Magnification slider
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Magnification")
                                .font(.subheadline)
                                .foregroundColor(.white.opacity(0.7))
                            Spacer()
                            Text("\(config.magnification, specifier: "%.1f")×")
                                .font(.system(.subheadline, design: .monospaced))
                                .foregroundColor(.blue)
                        }
                        Slider(value: $config.magnification, in: 1.2...4.0, step: 0.1)
                            .tint(.blue)
                    }

                    // Diameter slider
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Lens Size")
                                .font(.subheadline)
                                .foregroundColor(.white.opacity(0.7))
                            Spacer()
                            Text("\(Int(config.diameter))px")
                                .font(.system(.subheadline, design: .monospaced))
                                .foregroundColor(.blue)
                        }
                        Slider(value: $config.diameter, in: 20...500, step: 5)
                            .tint(.blue)
                    }

                    // Glass opacity slider
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Glass Tint")
                                .font(.subheadline)
                                .foregroundColor(.white.opacity(0.7))
                            Spacer()
                            Text(config.glassTintAmount < 0.01
                                ? "Off"
                                : "\(config.glassTintAmount, specifier: "%.2f")")
                                .font(.system(.subheadline, design: .monospaced))
                                .foregroundColor(.blue)
                        }
                        Slider(value: $config.glassTintAmount, in: 0.0...1.0, step: 0.01)
                            .tint(.blue)
                    }

                    Text("Lower tint keeps the lens looking like glass instead of a solid overlay.")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.45))

                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("Tint Color")
                                .font(.subheadline)
                                .foregroundColor(.white.opacity(0.7))
                            Spacer()
                            RoundedRectangle(cornerRadius: 6)
                                .fill(config.glassTint)
                                .frame(width: 28, height: 18)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6)
                                        .stroke(Color.white.opacity(0.25), lineWidth: 1)
                                )
                        }

                        HStack(spacing: 8) {
                            Button("White") {
                                config.setGlassTint(.white)
                            }
                            .buttonStyle(.glassProminent)
                            .tint(.white)

                            Button("Cool") {
                                config.setGlassTint(Color(red: 0.85, green: 0.93, blue: 1.0))
                            }
                            .buttonStyle(.glass)
                            .tint(Color(red: 0.85, green: 0.93, blue: 1.0))

                            Button("Blue") {
                                config.setGlassTint(Color(red: 0.46, green: 0.70, blue: 1.0))
                            }
                            .buttonStyle(.glass)
                            .tint(Color(red: 0.46, green: 0.70, blue: 1.0))
                        }
                        .controlSize(.small)

                        tintChannelRow(title: "Red", value: $config.glassTintRed)
                        tintChannelRow(title: "Green", value: $config.glassTintGreen)
                        tintChannelRow(title: "Blue", value: $config.glassTintBlue)
                    }
                }
                .padding(.leading, 28)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(16)
        .glassEffect(.regular.tint(.white.opacity(0.08)), in: .rect(cornerRadius: 12))
        .animation(.easeInOut(duration: 0.2), value: config.isEnabled)
    }

    private func tintChannelRow(title: String, value: Binding<Double>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.65))
                Spacer()
                Text(value.wrappedValue, format: .number.precision(.fractionLength(2)))
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(.blue.opacity(0.9))
            }

            Slider(value: value, in: 0.0...1.0, step: 0.01)
                .tint(.blue)
        }
    }
}
