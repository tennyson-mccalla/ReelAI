@MainActor
func loadProfile() async {
    guard let userId = authViewModel.currentUser?.uid else { return }

    do {
        let profile = try await profileService.fetchProfile(userId: userId)
        self.profile = profile

        // Create default profile photo if none exists
        if profile.photoURL == nil {
            try await createDefaultProfilePhoto()
        }

        // Load videos after profile is loaded
        await loadVideos()
    } catch {
        logger.error("Failed to load profile: \(error.localizedDescription)")
        errorMessage = "Failed to load profile"
    }
}

private func createDefaultProfilePhoto() async throws {
    guard let userId = authViewModel.currentUser?.uid else { return }

    // Create a default profile image
    let renderer = UIGraphicsImageRenderer(size: CGSize(width: 200, height: 200))
    let defaultImage = renderer.image { context in
        // Draw circle background
        UIColor.systemGray5.setFill()
        context.cgContext.fillEllipse(in: CGRect(x: 0, y: 0, width: 200, height: 200))

        // Draw person symbol
        let config = UIImage.SymbolConfiguration(pointSize: 100, weight: .medium)
        let personImage = UIImage(systemName: "person.fill", withConfiguration: config)?
            .withTintColor(.systemGray2, renderingMode: .alwaysOriginal)
        personImage?.draw(in: CGRect(x: 50, y: 50, width: 100, height: 100))
    }

    // Upload the default image
    if let imageData = defaultImage.jpegData(compressionQuality: 0.8) {
        let photoURL = try await storageService.uploadProfilePhoto(userId: userId, imageData: imageData)
        try await profileService.updateProfile(userId: userId, updates: ["photoURL": photoURL])

        // Update the local profile
        await MainActor.run {
            self.profile?.photoURL = photoURL
        }
    }
}
