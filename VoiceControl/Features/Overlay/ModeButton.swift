import SwiftUI

struct ModeButton: View {
    let icon: String
    let action: () -> Void
    @State private var isHovered = false
    
    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .foregroundColor(.primary.opacity(isHovered ? 0.8 : 0.4))
                .font(.system(size: 16, weight: .medium))
                .frame(width: 32, height: 32)
                .background(
                    Circle()
                        .fill(Color.white.opacity(isHovered ? 0.1 : 0))
                        .overlay(
                            Circle()
                                .stroke(Color.white.opacity(isHovered ? 0.2 : 0), lineWidth: 1)
                        )
                )
                .shadow(color: .accentColor.opacity(isHovered ? 0.3 : 0), radius: 3)
                // Removed scale effect to prevent layout shifts
                .animation(.easeInOut(duration: 0.15), value: isHovered)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            // Direct state change without explicit animation wrapper
            isHovered = hovering
        }
    }
}