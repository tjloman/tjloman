package com.tjloman.logbook

import android.content.ComponentName
import android.content.Context
import android.media.AudioManager
import android.media.MediaMetadata
import android.media.session.MediaController
import android.media.session.MediaSessionManager
import android.media.session.PlaybackState
import android.view.KeyEvent
import org.godotengine.godot.Dictionary

/**
 * Transport control and now-playing metadata, through Android's own
 * MediaSession layer.
 *
 * Why not the Spotify SDK: this needs no account, no OAuth, no API key, no
 * network, and it is not Spotify-specific — it drives whatever is playing,
 * including a podcast app or offline files. It also works with the phone
 * locked and the app closed, which is the actual requirement: the phone lives
 * in the trailer on a charger and the handlebar is the only thing you can
 * reach.
 *
 * The catch, and it is worth knowing: reading other apps' sessions requires
 * either the system-only MEDIA_CONTENT_CONTROL permission or an enabled
 * NotificationListenerService. This app ships the latter anyway (for messenger
 * logging), so granting notification access is what lights up these controls.
 */
object MediaBridge {

    /** Set by the service so a track change becomes a logbook entry. */
    var onTrack: ((Dictionary) -> Unit)? = null

    private var listener: MediaController.Callback? = null
    private var watched: MediaController? = null
    private var lastKey = ""

    private fun manager(context: Context): MediaSessionManager? =
        context.getSystemService(Context.MEDIA_SESSION_SERVICE) as? MediaSessionManager

    private fun component(context: Context) =
        ComponentName(context, NotificationCapture::class.java)

    /** The session actually making noise, or the first one offered. */
    private fun activeController(context: Context): MediaController? {
        val sessions = try {
            manager(context)?.getActiveSessions(component(context))
        } catch (_: SecurityException) {
            null   // notification access not granted yet
        } ?: return null
        return sessions.firstOrNull {
            it.playbackState?.state == PlaybackState.STATE_PLAYING
        } ?: sessions.firstOrNull()
    }

    fun nowPlaying(context: Context): Dictionary {
        val d = Dictionary()
        val controller = activeController(context) ?: return d
        val meta = controller.metadata
        val state = controller.playbackState
        d["title"] = meta?.getString(MediaMetadata.METADATA_KEY_TITLE) ?: ""
        d["artist"] = meta?.getString(MediaMetadata.METADATA_KEY_ARTIST)
            ?: meta?.getString(MediaMetadata.METADATA_KEY_ALBUM_ARTIST) ?: ""
        d["album"] = meta?.getString(MediaMetadata.METADATA_KEY_ALBUM) ?: ""
        d["duration_ms"] = (meta?.getLong(MediaMetadata.METADATA_KEY_DURATION) ?: 0L).toDouble()
        d["position_ms"] = (state?.position ?: 0L).toDouble()
        d["playing"] = state?.state == PlaybackState.STATE_PLAYING
        d["app"] = appLabel(context, controller.packageName)
        return d
    }

    /**
     * Watch the active session so a track change reaches the logbook the
     * moment it happens, rather than whenever the app next polls. Re-attached
     * whenever the active session changes hands (a podcast app taking over
     * from a music app, say).
     */
    fun watch(context: Context) {
        val controller = activeController(context) ?: return
        if (watched?.sessionToken == controller.sessionToken) return
        listener?.let { watched?.unregisterCallback(it) }
        val callback = object : MediaController.Callback() {
            override fun onMetadataChanged(metadata: MediaMetadata?) = report(context)
            override fun onPlaybackStateChanged(state: PlaybackState?) = report(context)
        }
        controller.registerCallback(callback)
        watched = controller
        listener = callback
        report(context)
    }

    private fun report(context: Context) {
        val info = nowPlaying(context)
        val key = "${info["artist"]}|${info["title"]}"
        // Players emit several metadata updates per song as art and duration
        // resolve; only a genuinely different track is worth logging.
        if (key == lastKey) {
            onTrack?.invoke(info)
            return
        }
        lastKey = key
        onTrack?.invoke(info)
    }

    // ------------------------------------------------------------- controls

    fun playPause(context: Context) {
        val controller = activeController(context)
        if (controller != null) {
            if (controller.playbackState?.state == PlaybackState.STATE_PLAYING) {
                controller.transportControls.pause()
            } else {
                controller.transportControls.play()
            }
            return
        }
        // Nothing has a session yet (Spotify cold): a media button wakes the
        // last player the system remembers.
        sendMediaKey(context, KeyEvent.KEYCODE_MEDIA_PLAY_PAUSE)
    }

    fun next(context: Context) {
        activeController(context)?.transportControls?.skipToNext()
            ?: sendMediaKey(context, KeyEvent.KEYCODE_MEDIA_NEXT)
    }

    fun previous(context: Context) {
        activeController(context)?.transportControls?.skipToPrevious()
            ?: sendMediaKey(context, KeyEvent.KEYCODE_MEDIA_PREVIOUS)
    }

    fun volume(context: Context, delta: Int) {
        val am = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
        am.adjustStreamVolume(
            AudioManager.STREAM_MUSIC,
            if (delta > 0) AudioManager.ADJUST_RAISE else AudioManager.ADJUST_LOWER,
            AudioManager.FLAG_SHOW_UI
        )
    }

    /**
     * Start a player from nothing. This resumes whatever it last had — picking
     * a *specific* playlist is the one thing MediaSession cannot do, and would
     * need Spotify's own SDK and an account. Resuming is what you want at the
     * top of a ride anyway.
     */
    fun launchAndPlay(context: Context, packageName: String) {
        val intent = context.packageManager.getLaunchIntentForPackage(packageName)
        if (intent != null) {
            intent.addFlags(android.content.Intent.FLAG_ACTIVITY_NEW_TASK)
            try { context.startActivity(intent) } catch (_: Exception) {}
        }
        sendMediaKey(context, KeyEvent.KEYCODE_MEDIA_PLAY)
    }

    private fun sendMediaKey(context: Context, code: Int) {
        val am = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
        am.dispatchMediaKeyEvent(KeyEvent(KeyEvent.ACTION_DOWN, code))
        am.dispatchMediaKeyEvent(KeyEvent(KeyEvent.ACTION_UP, code))
    }

    private fun appLabel(context: Context, packageName: String?): String {
        if (packageName == null) return ""
        return try {
            val pm = context.packageManager
            pm.getApplicationLabel(pm.getApplicationInfo(packageName, 0)).toString()
        } catch (_: Exception) {
            packageName
        }
    }
}
