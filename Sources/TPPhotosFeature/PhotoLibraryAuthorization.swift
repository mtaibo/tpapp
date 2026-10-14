import Photos

public enum PhotoLibraryAuthorization {
    public static var currentStatus: PHAuthorizationStatus {
        PHPhotoLibrary.authorizationStatus(for: .readWrite)
    }

    /// `PHAccessLevel` only offers `.addOnly`/`.readWrite` — there's no read-only tier, so
    /// even v1 (which never deletes or mutates the library) has to request `.readWrite`.
    @discardableResult
    public static func requestReadOnlyAccess() async -> PHAuthorizationStatus {
        await PHPhotoLibrary.requestAuthorization(for: .readWrite)
    }
}
