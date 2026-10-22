package com.antigravity.auraplayer

import android.app.Application
import com.antigravity.auraplayer.service.NewPipeDownloader
import org.schabi.newpipe.extractor.NewPipe

class AuraPlayerApplication : Application() {
    override fun onCreate() {
        super.onCreate()
        // YouTube search + stream extraction
        NewPipe.init(NewPipeDownloader.instance)
    }
}
