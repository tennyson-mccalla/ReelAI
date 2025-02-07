import SwiftUI
import PhotosUI

struct PhotoPicker: UIViewControllerRepresentable {
    let completion: (Result<Data, Error>) -> Void

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration()
        config.selectionLimit = 1
        config.filter = .images

        let picker = PHPickerViewController(configuration: config)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(completion: completion)
    }

    class Coordinator: PHPickerViewControllerDelegate {
        let completion: (Result<Data, Error>) -> Void

        init(completion: @escaping (Result<Data, Error>) -> Void) {
            self.completion = completion
        }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            picker.dismiss(animated: true)

            guard let provider = results.first?.itemProvider else {
                return
            }

            if provider.canLoadObject(ofClass: UIImage.self) {
                provider.loadObject(ofClass: UIImage.self) { [weak self] image, error in
                    if let error = error {
                        self?.completion(.failure(error))
                        return
                    }

                    guard let image = image as? UIImage,
                          let data = image.jpegData(compressionQuality: 0.8) else {
                        self?.completion(.failure(PhotoPickerError.invalidImage))
                        return
                    }

                    self?.completion(.success(data))
                }
            }
        }
    }

    enum PhotoPickerError: LocalizedError {
        case invalidImage

        var errorDescription: String? {
            switch self {
            case .invalidImage:
                return "Could not process the selected image"
            }
        }
    }
}

#Preview {
    // Wrap in a button to demonstrate typical usage
    Button("Select Photo") {
        // This view would normally be shown in a sheet
    }
    .sheet(isPresented: .constant(true)) {
        PhotoPicker { result in
            switch result {
            case .success(let data):
                print("✅ Photo selected: \(data.count) bytes")
            case .failure(let error):
                print("❌ Photo selection failed: \(error.localizedDescription)")
            }
        }
    }
}
