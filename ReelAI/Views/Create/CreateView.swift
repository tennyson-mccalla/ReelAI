import SwiftUI

struct CreateView: View {
    @State private var showingUploadView = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Spacer()

                Button(action: {
                    showingUploadView = true
                }) {
                    VStack(spacing: 12) {
                        Image(systemName: "video.badge.plus")
                            .font(.system(size: 50))
                        Text("Upload Video")
                            .font(.headline)
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 30)
                    .background(Color.blue)
                    .cornerRadius(12)
                }
                .padding(.horizontal)

                Spacer()
            }
            .navigationTitle("Create")
            .sheet(isPresented: $showingUploadView) {
                VideoUploadView()
            }
        }
    }
}
