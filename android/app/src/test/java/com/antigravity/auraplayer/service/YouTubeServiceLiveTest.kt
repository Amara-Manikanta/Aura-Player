package com.antigravity.auraplayer.service

import kotlinx.coroutines.runBlocking
import okhttp3.OkHttpClient
import okhttp3.Request
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.BeforeClass
import org.junit.Test
import org.schabi.newpipe.extractor.NewPipe

/**
 * Hits the real YouTube: checks search ranking and that audio stream URLs are downloadable.
 * Run with: ./gradlew :app:testDebugUnitTest --tests '*YouTubeServiceLiveTest*'
 */
class YouTubeServiceLiveTest {
    companion object {
        @BeforeClass @JvmStatic
        fun setUp() = NewPipe.init(NewPipeDownloader.instance)
    }

    private fun top(query: String): YouTubeSearchResult = runBlocking {
        val results = YouTubeService.search(query, limit = 5)
        println("\"$query\" =>")
        results.forEach { println("    ${it.durationSec.toInt()}s | ${it.channel} | ${it.title}") }
        assertTrue("no results for $query", results.isNotEmpty())
        results.first()
    }

    @Test fun rankingPicksOfficialVideos() {
        val cases = mapOf(
            "naatu naatu" to "t-series",
            "blinding lights" to "the weeknd",
            "samajavaragamana" to "aditya",
            "valukanuladana" to "shalimar",
        )
        for ((q, channel) in cases) {
            val best = top(q)
            assertTrue("$q picked ${best.channel}: ${best.title}", best.channel.lowercase().contains(channel))
            assertTrue("$q picked a lyric video", !best.title.lowercase().contains("lyric"))
        }
    }

    @Test fun pastedLinkLoadsRealDetails() = runBlocking {
        val t = YouTubeService.fetchTrack("https://youtu.be/eztr0Gmy8CE?si=BIDKJbCwp8NIBXbC")
        assertNotNull(t)
        println("link => ${t!!.title} | ${t.artist} | ${t.duration}s")
        assertEquals("eztr0Gmy8CE", t.youtubeId)
        assertTrue("duration should be real, not the old 210s placeholder", t.duration > 0 && t.duration != 210.0)
    }

    @Test fun audioStreamIsDownloadable() = runBlocking {
        val url = YouTubeService.audioStreamUrl("91EzD9VgwGk")
        assertNotNull("no audio stream", url)
        // Fetch the first bytes like ExoPlayer would
        val res = OkHttpClient().newCall(Request.Builder().url(url!!).header("Range", "bytes=0-1023").build()).execute()
        println("audio stream HTTP ${res.code}, ${res.header("Content-Type")}")
        assertTrue("stream HTTP ${res.code}", res.code == 200 || res.code == 206)
    }
}
