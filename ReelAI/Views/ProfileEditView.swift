import SwiftUI

struct ProfileEditView: View {
    @Binding var profile: UserProfile
    let isLoading: Bool
    let onSave: () -> Void
    let onCancel: () -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Display Name", text: $profile.displayName)
                        .textContentType(.name)

                    TextField("Bio", text: $profile.bio, axis: .vertical)
                        .lineLimit(3...6)
                }

                Section("Social Links") {
                    ForEach($profile.socialLinks) { $link in
                        SocialLinkRow(link: $link)
                    }

                    Button {
                        addSocialLink()
                    } label: {
                        Label("Add Social Link", systemImage: "plus.circle.fill")
                    }
                }
            }
            .navigationTitle("Edit Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel", action: onCancel)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save", action: onSave)
                        .disabled(isLoading || !isValid)
                }
            }
            .disabled(isLoading)
        }
    }

    private var isValid: Bool {
        !profile.displayName.isEmpty && profile.displayName.count >= 3
    }

    private func addSocialLink() {
        profile.socialLinks.append(
            UserProfile.SocialLink(
                platform: UserProfile.SocialLink.supportedPlatforms[0],
                url: ""
            )
        )
    }
}

private struct SocialLinkRow: View {
    @Binding var link: UserProfile.SocialLink

    var body: some View {
        HStack {
            Menu {
                ForEach(UserProfile.SocialLink.supportedPlatforms, id: \.self) { platform in
                    Button(platform) {
                        link = UserProfile.SocialLink(
                            platform: platform,
                            url: link.url
                        )
                    }
                }
            } label: {
                Text(link.platform)
                    .foregroundColor(.primary)
            }

            TextField("URL", text: $link.url)
                .textContentType(.URL)
                .keyboardType(.URL)
                .autocapitalization(.none)
        }
    }
}

#Preview {
    ProfileEditView(
        profile: .constant(.mock),
        isLoading: false,
        onSave: {},
        onCancel: {}
    )
}
