package com.ryanheise.audioserviceexample

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.net.Uri
import android.util.Log
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetBackgroundIntent
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetProvider
import androidx.core.content.ContextCompat.startActivity
import androidx.core.content.FileProvider
import java.io.File

class AudioSmallWidget: HomeWidgetProvider() {
    private val PREV_CLICKED = "AudioSmallWidgetPrevButtonClick"
    private val REW_CLICKED = "AudioSmallWidgetRewButtonClick"
    private val PLAY_CLICKED = "AudioSmallWidgetPlayButtonClick"
    private val PAUSE_CLICKED = "AudioSmallWidgetPauseButtonClick"
    private val FF_CLICKED = "AudioSmallWidgetFfButtonClick"
    private val NEXT_CLICKED = "AudioSmallWidgetNextButtonClick"

    override fun onUpdate(context: Context, appWidgetManager: AppWidgetManager, appWidgetIds: IntArray, widgetData: SharedPreferences) {
        appWidgetIds.forEach { widgetId ->
            val views = RemoteViews(context.packageName, R.layout.audio_small_widget).apply {

                // title
                setOnClickPendingIntent(R.id.title, HomeWidgetLaunchIntent.getActivity(context, MainActivity::class.java))
                setTextViewText(R.id.title, widgetData.getString("title", "unknown"))

                // artwork
                setOnClickPendingIntent(R.id.thumb, HomeWidgetLaunchIntent.getActivity(context, MainActivity::class.java))
                val artPath = widgetData.getString("artwork", null)
                if(artPath == null) setImageViewResource(R.id.thumb, R.drawable.artwork)
                else {
//                     val bitmap = getBitmap(artPath)
                    val uri: Uri = Uri.parse(artPath)
                    setImageViewUri(R.id.thumb, uri)
//                    setImageViewBitmap(R.id.thumb, bitmap)
                }

                // prev button
                setOnClickPendingIntent(R.id.prev, HomeWidgetBackgroundIntent.getBroadcast(
                    context,
                    Uri.parse("audiosmallwidget://prev")
                ))

                // rew button
                setOnClickPendingIntent(R.id.rew, HomeWidgetBackgroundIntent.getBroadcast(
                    context,
                    Uri.parse("audiosmallwidget://rew")
                ))

                // play button
                setOnClickPendingIntent(R.id.play, HomeWidgetBackgroundIntent.getBroadcast(
                    context,
                    Uri.parse("audiosmallwidget://play")
                ))
                val playing = widgetData.getBoolean("playing", false)
                setImageViewResource(R.id.play, if(playing) R.drawable.ic_baseline_pause_24 else R.drawable.ic_baseline_play_arrow_24)

                // ff button
                setOnClickPendingIntent(R.id.ff, HomeWidgetBackgroundIntent.getBroadcast(
                    context,
                    Uri.parse("audiosmallwidget://ff")
                ))

                // next button
                setOnClickPendingIntent(R.id.next, HomeWidgetBackgroundIntent.getBroadcast(
                    context,
                    Uri.parse("audiosmallwidget://next")
                ))
            }

            appWidgetManager.updateAppWidget(widgetId, views)
        }
    }

    fun getBitmap(imageLocation: String?): Bitmap? {
        val options: BitmapFactory.Options = BitmapFactory.Options()
        options.inPreferredConfig = Bitmap.Config.ARGB_8888
        return BitmapFactory.decodeFile(imageLocation, options)
    }

}