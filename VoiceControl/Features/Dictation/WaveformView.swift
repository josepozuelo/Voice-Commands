import SwiftUI

/// A real-time waveform visualization that displays audio amplitude levels
struct WaveformView: View {
    let amplitudes: [Float]
    let barCount: Int = 30
    let maxAmplitude: Float = 0.3 // Threshold for "good" audio level

    var body: some View {
        GeometryReader { geometry in
            VStack {
                Spacer()
                HStack(alignment: .center, spacing: 2) {
                    ForEach(0..<barCount, id: \.self) { index in
                        WaveformBar(
                            amplitude: amplitudeForIndex(index),
                            maxAmplitude: maxAmplitude,
                            height: geometry.size.height
                        )
                    }
                }
                Spacer()
            }
        }
    }

    private func amplitudeForIndex(_ index: Int) -> Float {
        // Display most recent amplitudes on the right
        let dataIndex = amplitudes.count - barCount + index
        guard dataIndex >= 0, dataIndex < amplitudes.count else {
            return 0.0
        }
        return amplitudes[dataIndex]
    }
}

/// Individual bar in the waveform
private struct WaveformBar: View {
    let amplitude: Float
    let maxAmplitude: Float
    let height: CGFloat

    var body: some View {
        RoundedRectangle(cornerRadius: 2)
            .fill(barColor)
            .frame(width: 3, height: barHeight)
            .frame(height: height, alignment: .center) // Center bar vertically within container
            .animation(.spring(response: 0.2, dampingFraction: 0.6), value: amplitude)
    }

    private var normalizedAmplitude: CGFloat {
        // Normalize to 0-1 range, with some scaling for better visual feedback
        let scaled = min(CGFloat(amplitude) / CGFloat(maxAmplitude), 1.0)
        // Add minimum height so bars are always visible
        return max(scaled, 0.05)
    }

    private var barHeight: CGFloat {
        // Scale bar height based on normalized amplitude
        return height * normalizedAmplitude
    }

    private var barColor: Color {
        let level = amplitude / maxAmplitude

        if level < 0.15 {
            // Too quiet - yellow warning
            return Color.yellow.opacity(0.7)
        } else if level > 1.5 {
            // Too loud - red warning (clipping)
            return Color.red.opacity(0.8)
        } else {
            // Good level - green
            return Color.green.opacity(0.8)
        }
    }
}

#Preview {
    VStack(spacing: 20) {
        // Example waveform with various levels
        WaveformView(amplitudes: Array(repeating: 0.1, count: 30))
            .background(Color.black.opacity(0.9))
            .padding()

        WaveformView(amplitudes: (0..<30).map { Float($0) * 0.02 })
            .background(Color.black.opacity(0.9))
            .padding()

        // Simulate varying audio levels
        WaveformView(amplitudes: (0..<30).map { i in
            Float.random(in: 0.05...0.35)
        })
        .background(Color.black.opacity(0.9))
        .padding()
    }
}
