import Foundation
import Testing
import TPCore
@testable import TPPhotosFeature

private func makeUpload(id: String = "checksum-1", totalChunks: Int = 3, tempFileURL: URL) -> PendingPhotoUpload {
    PendingPhotoUpload(
        uploadId: id,
        assetLocalIdentifier: "asset-1",
        folderPath: "photos/user@example.com/2026/01",
        filename: "\(id).jpg",
        fileSize: 1024,
        chunkSize: 256,
        totalChunks: totalChunks,
        tempFileURL: tempFileURL,
        registration: PhotosClient.Registration(
            path: "photos/user@example.com/2026/01/\(id).jpg",
            checksum: id,
            originalFilename: "IMG_0001.jpg",
            fileSize: 1024
        )
    )
}

private func makeTempFile() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("ledger-test-\(UUID().uuidString)")
    try Data("fake photo bytes".utf8).write(to: url)
    return url
}

private func makeLedger() -> (PhotoUploadLedger, URL) {
    let file = FileManager.default.temporaryDirectory.appendingPathComponent("ledger-\(UUID().uuidString).json")
    return (PhotoUploadLedger(fileURL: file), file)
}

@Test func beginOrResumeStoresAndListsAnUpload() async throws {
    let (ledger, _) = makeLedger()
    let temp = try makeTempFile()
    defer { try? FileManager.default.removeItem(at: temp) }

    let upload = makeUpload(tempFileURL: temp)
    await ledger.beginOrResume(upload)

    let active = await ledger.activeUploads()
    #expect(active == [upload])
    #expect(await ledger.upload(for: upload.uploadId) == upload)
}

@Test func beginOrResumeDoesNotResetAnAlreadyTrackedUpload() async throws {
    let (ledger, _) = makeLedger()
    let temp = try makeTempFile()
    defer { try? FileManager.default.removeItem(at: temp) }

    let upload = makeUpload(tempFileURL: temp)
    await ledger.beginOrResume(upload)
    await ledger.markChunkComplete(uploadId: upload.uploadId, chunkIndex: 0)

    // Re-planning the same photo (e.g. a later refill pass scanning the library again) must not
    // wipe out the chunk already marked complete.
    await ledger.beginOrResume(upload)

    let current = await ledger.upload(for: upload.uploadId)
    #expect(current?.completedChunks == [0])
}

@Test func markChunkCompleteAccumulatesAndReportsCompletion() async throws {
    let (ledger, _) = makeLedger()
    let temp = try makeTempFile()
    defer { try? FileManager.default.removeItem(at: temp) }

    let upload = makeUpload(totalChunks: 3, tempFileURL: temp)
    await ledger.beginOrResume(upload)

    let afterFirst = await ledger.markChunkComplete(uploadId: upload.uploadId, chunkIndex: 0)
    #expect(afterFirst?.isComplete == false)

    _ = await ledger.markChunkComplete(uploadId: upload.uploadId, chunkIndex: 1)
    let afterThird = await ledger.markChunkComplete(uploadId: upload.uploadId, chunkIndex: 2)
    #expect(afterThird?.isComplete == true)
    #expect(afterThird?.completedChunks == [0, 1, 2])
}

@Test func markChunkCompleteOnUnknownUploadReturnsNil() async {
    let (ledger, _) = makeLedger()
    let result = await ledger.markChunkComplete(uploadId: "does-not-exist", chunkIndex: 0)
    #expect(result == nil)
}

@Test func removeDeletesTheEntryAndItsTempFile() async throws {
    let (ledger, _) = makeLedger()
    let temp = try makeTempFile()

    let upload = makeUpload(tempFileURL: temp)
    await ledger.beginOrResume(upload)
    await ledger.remove(uploadId: upload.uploadId)

    #expect(await ledger.upload(for: upload.uploadId) == nil)
    #expect(!FileManager.default.fileExists(atPath: temp.path))
}

@Test func stateSurvivesAFreshLedgerInstancePointedAtTheSameFile() async throws {
    let file = FileManager.default.temporaryDirectory.appendingPathComponent("ledger-\(UUID().uuidString).json")
    let temp = try makeTempFile()
    defer { try? FileManager.default.removeItem(at: temp) }

    let first = PhotoUploadLedger(fileURL: file)
    let upload = makeUpload(tempFileURL: temp)
    await first.beginOrResume(upload)
    await first.markChunkComplete(uploadId: upload.uploadId, chunkIndex: 0)

    // A new instance (as if the process had been relaunched purely to handle a background
    // URLSession callback, with none of `first`'s in-memory state) must see the same progress.
    let second = PhotoUploadLedger(fileURL: file)
    let resumed = await second.upload(for: upload.uploadId)
    #expect(resumed?.completedChunks == [0])
}
