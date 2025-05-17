import SwiftUI

struct VoiceAssistantView: View {
    var body: some View {
        VStack {
            Spacer()
            Button(action: {
                print("Push-to-talk activated (placeholder)")
                // TODO: Integrate Goose-CLI and Whisper here
            }) {
                ZStack {
                    Circle()
                        .fill(Color.black)
                        .frame(width: 80, height: 80)
                        .shadow(radius: 10)
                    Image(systemName: "mic.circle.fill")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 60, height: 60)
                        .foregroundColor(.white)
                }
            }
            .buttonStyle(PlainButtonStyle())
            Text("Push to talk")
                .font(.headline)
                .foregroundColor(.gray)
                .padding(.top, 12)
            Spacer()
        }
    }
}

#Preview {
    VoiceAssistantView()
} 