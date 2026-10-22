package com.antigravity.auraplayer.utils

import android.app.DownloadManager
import android.content.Context
import android.net.Uri
import android.os.Environment
import android.widget.Toast
import com.antigravity.auraplayer.model.MediaTrack
import com.antigravity.auraplayer.service.YouTubeService
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

object DownloadHelper {
    fun downloadTrack(context: Context, track: MediaTrack, scope: CoroutineScope) {
        val yId = track.youtubeId
        if (yId == null) {
            Toast.makeText(context, "Cannot download: No YouTube ID", Toast.LENGTH_SHORT).show()
            return
        }
        
        Toast.makeText(context, "Fetching download URL...", Toast.LENGTH_SHORT).show()
        
        scope.launch {
            val url = YouTubeService.audioStreamUrl(yId)
            withContext(Dispatchers.Main) {
                if (url == null) {
                    Toast.makeText(context, "Failed to get stream URL", Toast.LENGTH_SHORT).show()
                    return@withContext
                }
                
                try {
                    val request = DownloadManager.Request(Uri.parse(url))
                        .setTitle(track.title)
                        .setDescription(track.artist)
                        .setNotificationVisibility(DownloadManager.Request.VISIBILITY_VISIBLE_NOTIFY_COMPLETED)
                        .setDestinationInExternalPublicDir(
                            Environment.DIRECTORY_MUSIC, 
                            "AuraPlayer/${track.title}.m4a"
                        )
                        
                    val downloadManager = context.getSystemService(Context.DOWNLOAD_SERVICE) as DownloadManager
                    downloadManager.enqueue(request)
                    Toast.makeText(context, "Download started", Toast.LENGTH_SHORT).show()
                } catch (e: Exception) {
                    Toast.makeText(context, "Download failed: ${e.message}", Toast.LENGTH_SHORT).show()
                }
            }
        }
    }
}
