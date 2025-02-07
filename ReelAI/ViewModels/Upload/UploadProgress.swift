// Progress tracking and status updates
// ~50 lines

import FirebaseStorage

final class UploadProgress {
    func trackProgress(_ task: StorageUploadTask) -> AsyncStream<Double> {
        AsyncStream { continuation in
            task.observe(.progress) { snapshot in
                let progress = Double(snapshot.progress?.completedUnitCount ?? 0) /
                             Double(snapshot.progress?.totalUnitCount ?? 1)
                continuation.yield(progress)
            }
        }
    }
}
