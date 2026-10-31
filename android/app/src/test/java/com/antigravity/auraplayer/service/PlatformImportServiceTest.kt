package com.antigravity.auraplayer.service

import kotlinx.coroutines.runBlocking
import org.junit.Assert.*
import org.junit.BeforeClass
import org.junit.Test
import org.schabi.newpipe.extractor.NewPipe

class PlatformImportServiceTest {

    companion object {
        @BeforeClass
        @JvmStatic
        fun setUp() {
            NewPipe.init(NewPipeDownloader.instance)
        }
    }

    @Test
    fun testDetectPlatform() {
        assertEquals(PlatformType.YOUTUBE, PlatformImportService.detectPlatform("https://www.youtube.com/playlist?list=PL12345"))
        assertEquals(PlatformType.YOUTUBE, PlatformImportService.detectPlatform("https://youtu.be/abc123xyz89"))
        assertEquals(PlatformType.SPOTIFY, PlatformImportService.detectPlatform("https://open.spotify.com/playlist/37i9dQZF1DXcBWIGoYBM5M"))
        assertEquals(PlatformType.SPOTIFY, PlatformImportService.detectPlatform("https://open.spotify.com/track/7bxaFZ1O3cHkgLKMsdC3xR"))
        assertEquals(PlatformType.JIOSAAVN, PlatformImportService.detectPlatform("https://www.jiosaavn.com/featured/lets-play/JlH8CvDTC1RTHgJw1pi47A__"))
        assertEquals(PlatformType.GAANA, PlatformImportService.detectPlatform("https://gaana.com/song/samajavaragamana"))
        assertEquals(PlatformType.AMAZON_MUSIC, PlatformImportService.detectPlatform("https://music.amazon.in/albums/B09Z295P3Y"))
        assertEquals(PlatformType.TEXT, PlatformImportService.detectPlatform("Song One - Artist One\nSong Two - Artist Two"))
    }

    @Test
    fun testTextImport() = runBlocking {
        val input = """
            1. In the End - Linkin Park
            2) Numb - Linkin Park
            3 - Faint - Linkin Park
            Chaleya - Anirudh Ravichander
        """.trimIndent()

        val result = PlatformImportService.parseLinkOrText(input)
        assertTrue(result.isSuccess)
        val playlist = result.getOrNull()
        assertNotNull(playlist)
        assertEquals(4, playlist!!.tracks.size)
        assertEquals("In the End", playlist.tracks[0].title)
        assertEquals("Linkin Park", playlist.tracks[0].artist)
        assertEquals("Numb", playlist.tracks[1].title)
        assertEquals("Faint", playlist.tracks[2].title)
        assertEquals("Chaleya", playlist.tracks[3].title)
    }

    @Test
    fun testSpotifyEmbedImport() = runBlocking {
        // Today's Top Hits embed
        val url = "https://open.spotify.com/playlist/37i9dQZF1DXcBWIGoYBM5M"
        val result = PlatformImportService.parseLinkOrText(url)
        if (result.isFailure) {
            result.exceptionOrNull()?.printStackTrace()
        }
        assertTrue(result.isSuccess)
        val playlist = result.getOrNull()
        assertNotNull(playlist)
        assertEquals(PlatformType.SPOTIFY, playlist!!.platform)
        assertTrue(playlist.tracks.isNotEmpty())
        println("Spotify import test passed: fetched ${playlist.tracks.size} tracks from \"${playlist.name}\"")
    }

    @Test
    fun testYouTubeVideoImport() = runBlocking {
        val url = "https://youtu.be/eztr0Gmy8CE?si=BIDKJbCwp8NIBXbC"
        val result = PlatformImportService.parseLinkOrText(url)
        assertTrue(result.isSuccess)
        val playlist = result.getOrNull()
        assertNotNull(playlist)
        assertEquals(PlatformType.YOUTUBE, playlist!!.platform)
        assertEquals(1, playlist.tracks.size)
        assertEquals("eztr0Gmy8CE", playlist.tracks[0].youtubeId)
        println("YouTube import test passed: fetched track \"${playlist.tracks[0].title}\" by ${playlist.tracks[0].artist}")
    }

    @Test
    fun testJioSaavnImport() = runBlocking {
        // Devara album on JioSaavn
        val url = "https://www.jiosaavn.com/album/devara-part-1-telugu/kArqawD7cKk_"
        val result = PlatformImportService.parseLinkOrText(url)
        if (result.isFailure) {
            result.exceptionOrNull()?.printStackTrace()
        }
        assertTrue(result.isSuccess)
        val playlist = result.getOrNull()
        assertNotNull(playlist)
        assertEquals(PlatformType.JIOSAAVN, playlist!!.platform)
        assertTrue(playlist.tracks.isNotEmpty())
        println("JioSaavn import test passed: fetched ${playlist.tracks.size} tracks from \"${playlist.name}\"")
    }
}
