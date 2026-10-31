package com.antigravity.auraplayer

import android.app.Application
import com.antigravity.auraplayer.service.ArtistPhotoService
import com.antigravity.auraplayer.service.CustomLyricsStore
import com.antigravity.auraplayer.service.NewPipeDownloader
import com.antigravity.auraplayer.service.RecommendationService
import com.antigravity.auraplayer.service.TrackArtworkService
import org.schabi.newpipe.extractor.NewPipe

class AuraPlayerApplication : Application() {
    override fun onCreate() {
        super.onCreate()
        // YouTube search + stream extraction
        NewPipe.init(NewPipeDownloader.instance)
        // Saved artist photos, album covers, For You picks, and custom lyrics
        ArtistPhotoService.init(this)
        TrackArtworkService.init(this)
        RecommendationService.init(this)
        CustomLyricsStore.init(this)
    }
}
