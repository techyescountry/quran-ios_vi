//
//  QuranAudioDownloaderTests.swift
//
//
//  Created by Mohamed Afifi on 2023-05-06.
//

@testable import BatchDownloader
@testable import QuranAudioKit
import QuranKit
import SnapshotTesting
import SystemDependenciesFake
import TestUtilities
import XCTest

class QuranAudioDownloaderTests: XCTestCase {
    private var downloader: QuranAudioDownloader!
    private var batchDownloader: DownloadManager!
    private var session: NetworkSessionFake!
    private var fileSystem: FileSystemFake!

    private static let baseURL = URL(validURL: "http://example.com")
    private let quran = Quran.hafsMadani1405
    private let suras = Quran.hafsMadani1405.suras

    private let request = DownloadRequest(url: baseURL.appendingPathComponent("mishari_alafasy/001.mp3"),
                                          destinationPath: "audio_files/mishari_alafasy/001.mp3")

    private let gappedReciter: Reciter = .gappedReciter
    private let gaplessReciter: Reciter = .gaplessReciter

    override func setUp() async throws {
        fileSystem = FileSystemFake()
        (batchDownloader, session) = await NetworkSessionFake.makeDownloader()
        downloader = QuranAudioDownloader(
            downloader: batchDownloader,
            fileListFactory: DefaultReciterAudioFileListRetrievalFactory(baseURL: Self.baseURL),
            fileSystem: fileSystem
        )
    }

    override func tearDownWithError() throws {
        NetworkSessionFake.tearDown()
        Reciter.cleanUpAudio()
    }

    // MARK: - Downloading

    func testDownloadGaplessReciter_1Sura_zip() async throws {
        let reciter = gaplessReciter
        let start = suras[0].firstVerse
        let end = suras[3].lastVerse

        let response = try await downloader.download(from: start, to: end, reciter: reciter)
        let suraPaths = start.sura.array(to: end.sura).map { suraRemoteURL($0, reciter: reciter) }
        await AsyncAssertEqual(Set(await response.urls), Set([databaseRemoteURL(reciter)] + suraPaths))
    }

    func testDownloadGaplessReciter_allSuras_noZip() async throws {
        let reciter = gaplessReciter
        try reciter.prepareGaplessReciterForTests()
        let start = quran.firstVerse
        let end = quran.lastVerse

        let response = try await downloader.download(from: start, to: end, reciter: reciter)

        let suraPaths = start.sura.array(to: end.sura).map { suraRemoteURL($0, reciter: reciter) }
        await AsyncAssertEqual(Set(await response.urls), Set(suraPaths))
    }

    func test_download_gappedReciter_firstSura() async throws {
        let reciter = gappedReciter
        let start = suras[0].firstVerse
        let end = suras[0].lastVerse

        let response = try await downloader.download(from: start, to: end, reciter: reciter)

        let ayahPaths = start.array(to: end).map { ayahRemoteURL($0, reciter: reciter) }
        await AsyncAssertEqual(Set(await response.urls), Set(ayahPaths))
    }

    func test_download_gappedReciter_allVerses() async throws {
        let reciter = gappedReciter
        let start = quran.firstVerse
        let end = quran.lastVerse

        let response = try await downloader.download(from: start, to: end, reciter: reciter)

        let ayahPaths = start.array(to: end).map { ayahRemoteURL($0, reciter: reciter) }
        await AsyncAssertEqual(Set(await response.urls), Set(ayahPaths))
    }

    func test_download_gappedReciter_fewMiddleVerses() async throws {
        let reciter = gappedReciter
        let start = quran.suras[1].verses[2]
        let end = quran.suras[1].verses[5]

        let response = try await downloader.download(from: start, to: end, reciter: reciter)

        let ayahPaths = start.array(to: end).map { ayahRemoteURL($0, reciter: reciter) }
        let firstVersePath = ayahRemoteURL(quran.firstVerse, reciter: reciter)
        await AsyncAssertEqual(Set(await response.urls), Set(ayahPaths + [firstVersePath]))
    }

    // MARK: - downloaded

    func test_downloaded_gaplessReciter() async {
        let reciter = gaplessReciter
        let start = suras[0].firstVerse
        let end = suras[3].lastVerse
        let suraPaths = start.sura.array(to: end.sura).map { suraLocalURL($0, reciter: reciter) }
        fileSystem.files = Set([reciter.gaplessDatabaseZipURL] + suraPaths)

        let downloaded = await downloader.downloaded(reciter: reciter, from: start, to: end)
        XCTAssertTrue(downloaded)

        // Try without the database file.
        fileSystem.files = Set(suraPaths)
        let downloaded2 = await downloader.downloaded(reciter: reciter, from: start, to: end)
        XCTAssertFalse(downloaded2)
    }

    func test_downloaded_gappedReciter() async {
        let reciter = gappedReciter
        let start = suras[0].firstVerse
        let end = suras[0].lastVerse
        let ayahPaths = start.array(to: end).map { ayahLocalURL($0, reciter: reciter) }
        fileSystem.files = Set(ayahPaths)

        let downloaded = await downloader.downloaded(reciter: reciter, from: start, to: end)
        XCTAssertTrue(downloaded)

        // Try without any files.
        fileSystem.files = []
        let downloaded2 = await downloader.downloaded(reciter: reciter, from: start, to: end)
        XCTAssertFalse(downloaded2)
    }

    // MARK: - runningAudioDownloads

    func test_runningAudioDownloads_empty() async {
        let downloads = await downloader.runningAudioDownloads()
        XCTAssertEqual(downloads, [])
    }

    func test_runningAudioDownloads_downloading() async throws {
        let start = suras[0].firstVerse
        let end = suras[0].lastVerse

        let gappedResponse = try await downloader.download(from: start, to: end, reciter: gappedReciter)
        let gaplessResponse = try await downloader.download(from: start, to: end, reciter: gaplessReciter)

        let downloads = await downloader.runningAudioDownloads()
        XCTAssertEqual(Set(downloads), Set([gappedResponse, gaplessResponse]))
    }

    func test_download_matching() async throws {
        let start = suras[0].firstVerse
        let end = suras[0].lastVerse

        let gappedResponse = try await downloader.download(from: start, to: end, reciter: gappedReciter)
        let gaplessResponse = try await downloader.download(from: start, to: end, reciter: gaplessReciter)
        let downloads = Set(await downloader.runningAudioDownloads())
        let reciters = [gappedReciter, gaplessReciter]

        await AsyncAssertEqual(await downloads.firstMatches(gappedReciter), gappedResponse)
        await AsyncAssertEqual(await downloads.firstMatches(gaplessReciter), gaplessResponse)
        await AsyncAssertEqual(await reciters.firstMatches(gappedResponse), gappedReciter)
        await AsyncAssertEqual(await reciters.firstMatches(gaplessResponse), gaplessReciter)
    }

    // MARK: - cancelAllAudioDownloads

    func test_cancelAllAudioDownloads() async throws {
        let start = suras[0].firstVerse
        let end = suras[0].lastVerse

        _ = try await downloader.download(from: start, to: end, reciter: gappedReciter)
        _ = try await downloader.download(from: start, to: end, reciter: gaplessReciter)

        await downloader.cancelAllAudioDownloads()
        await Task.megaYield()

        let downloads = await downloader.runningAudioDownloads()
        XCTAssertEqual(downloads, [])
    }

    // MARK: - Helpers

    private func databaseRemoteURL(_ reciter: Reciter) -> URL {
        Self.baseURL.appendingPathComponent(GaplessReciterAudioFileListRetrieval.path + reciter.gaplessDatabaseZip)
    }

    private func suraRemoteURL(_ sura: Sura, reciter: Reciter) -> URL {
        reciter.audioURL.appendingPathComponent(sura.suraNumber.as3DigitString() + ".mp3")
    }

    private func suraLocalURL(_ sura: Sura, reciter: Reciter) -> URL {
        reciter.localFolder().appendingPathComponent(sura.suraNumber.as3DigitString() + ".mp3")
    }

    private func ayahRemoteURL(_ ayah: AyahNumber, reciter: Reciter) -> URL {
        reciter.audioURL.appendingPathComponent(ayah.sura.suraNumber.as3DigitString() + ayah.ayah.as3DigitString() + ".mp3")
    }

    private func ayahLocalURL(_ ayah: AyahNumber, reciter: Reciter) -> URL {
        reciter.localFolder().appendingPathComponent(ayah.sura.suraNumber.as3DigitString() + ayah.ayah.as3DigitString() + ".mp3")
    }
}

private extension DownloadBatchResponse {
    var urls: [URL?] {
        get async {
            await responses.asyncMap { await $0.download.request.request.url }
        }
    }
}
