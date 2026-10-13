package com.budgetai.android

import android.content.Context
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.Rect
import android.util.TypedValue
import android.view.View
import android.widget.RemoteViews
import kotlin.math.ceil

/**
 * Launchers do not load an app's own fonts inside widgets, so headline text is
 * drawn with Boldonse into a white bitmap. The ImageView's XML tint colors it,
 * which keeps Light and Dark mode resolved by the launcher.
 */
object WidgetDisplayText {
    // Rendered larger than shown so the ImageView scales down crisply.
    private const val OVERSAMPLE = 2f

    fun render(context: Context, text: String, sizeSp: Float): Bitmap {
        val paint = Paint(Paint.ANTI_ALIAS_FLAG or Paint.SUBPIXEL_TEXT_FLAG).apply {
            typeface = context.resources.getFont(R.font.boldonse)
            textSize = TypedValue.applyDimension(
                TypedValue.COMPLEX_UNIT_SP,
                sizeSp,
                context.resources.displayMetrics,
            ) * OVERSAMPLE
            color = Color.WHITE
        }
        val bounds = Rect()
        paint.getTextBounds(text, 0, text.length, bounds)
        val padding = (paint.textSize * 0.06f).toInt()
        val width = maxOf(1, ceil(paint.measureText(text)).toInt() + padding * 2)
        val height = maxOf(1, bounds.height() + padding * 2)
        return Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888).also { bitmap ->
            Canvas(bitmap).drawText(
                text,
                padding.toFloat(),
                (padding - bounds.top).toFloat(),
                paint,
            )
        }
    }

    /** Shows [text] in Boldonse in [imageId] and hides the plain [textId] fallback. */
    fun bind(
        context: Context,
        views: RemoteViews,
        textId: Int,
        imageId: Int,
        text: String,
        sizeSp: Float,
    ) {
        views.setTextViewText(textId, text)
        val bitmap = runCatching { render(context, text, sizeSp) }.getOrNull()
        if (bitmap == null) {
            views.setViewVisibility(textId, View.VISIBLE)
            views.setViewVisibility(imageId, View.GONE)
            return
        }
        views.setImageViewBitmap(imageId, bitmap)
        views.setContentDescription(imageId, text)
        views.setViewVisibility(imageId, View.VISIBLE)
        views.setViewVisibility(textId, View.GONE)
    }
}
