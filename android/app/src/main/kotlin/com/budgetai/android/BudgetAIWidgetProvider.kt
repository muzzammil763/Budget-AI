package com.budgetai.android

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.net.Uri
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetProvider
import java.text.NumberFormat
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Locale
import org.json.JSONArray

class BudgetAIWidgetProvider : HomeWidgetProvider() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action == ACTION_CHANGE_MONTH) {
            val widgetData = context.getSharedPreferences("HomeWidgetPreferences", Context.MODE_PRIVATE)
            moveMonth(widgetData, intent.getIntExtra(EXTRA_DIRECTION, 0))
            val manager = AppWidgetManager.getInstance(context)
            val component = ComponentName(context, BudgetAIWidgetProvider::class.java)
            onUpdate(context, manager, manager.getAppWidgetIds(component), widgetData)
            return
        }
        super.onReceive(context, intent)
    }

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences,
    ) {
        val summaries = summaries(widgetData)
        val current = currentMonthKey()
        val selected = widgetData.getString(KEY_SELECTED_MONTH, current)
            ?.takeIf { saved -> saved <= current && (saved == current || summaries.any { it.month == saved }) }
            ?: current
        val summary = summaries.firstOrNull { it.month == selected }
        val currency = widgetData.getString(KEY_CURRENCY, "USD") ?: "USD"
        val openApp = HomeWidgetLaunchIntent.getActivity(
            context,
            MainActivity::class.java,
            Uri.parse("budgetai://widget?homeWidget"),
        )

        appWidgetIds.forEach { widgetId ->
            val views = RemoteViews(context.packageName, R.layout.budget_ai_widget).apply {
                setTextViewText(
                    R.id.widget_title,
                    if (selected == current) "This Month" else longMonth(selected),
                )
                setTextViewText(R.id.widget_month, shortMonth(selected))
                setTextViewText(R.id.widget_income, formatAmount(summary?.income ?: 0.0, currency))
                setTextViewText(R.id.widget_expense, formatAmount(summary?.expense ?: 0.0, currency))
                setFloat(R.id.widget_next, "setAlpha", if (selected < current) 1f else 0.28f)
                setOnClickPendingIntent(R.id.widget_previous, monthIntent(context, widgetId, -1))
                if (selected < current) {
                    setOnClickPendingIntent(R.id.widget_next, monthIntent(context, widgetId, 1))
                } else {
                    setOnClickPendingIntent(R.id.widget_next, null)
                }
                setOnClickPendingIntent(R.id.widget_root, openApp)
            }
            appWidgetManager.updateAppWidget(widgetId, views)
        }
    }

    private fun monthIntent(context: Context, widgetId: Int, direction: Int): PendingIntent {
        val intent = Intent(context, BudgetAIWidgetProvider::class.java).apply {
            action = ACTION_CHANGE_MONTH
            putExtra(EXTRA_DIRECTION, direction)
        }
        return PendingIntent.getBroadcast(
            context,
            widgetId * 10 + direction + 2,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }

    private fun moveMonth(preferences: SharedPreferences, direction: Int) {
        val current = currentMonthKey()
        val selected = preferences.getString(KEY_SELECTED_MONTH, current) ?: current
        val ordered = (summaries(preferences).map { it.month } + current).distinct().sortedDescending()
        val index = ordered.indexOf(selected).takeIf { it >= 0 } ?: 0
        val target = (index - direction).coerceIn(0, ordered.lastIndex)
        preferences.edit().putString(KEY_SELECTED_MONTH, ordered[target]).apply()
    }

    private fun summaries(preferences: SharedPreferences): List<MonthSummary> {
        val raw = preferences.getString(KEY_SUMMARIES, "[]") ?: "[]"
        return runCatching {
            val array = JSONArray(raw)
            (0 until array.length()).map { index ->
                val item = array.getJSONObject(index)
                MonthSummary(item.getString("month"), item.optDouble("expense"), item.optDouble("income"))
            }
        }.getOrDefault(emptyList())
    }

    private fun currentMonthKey(): String =
        SimpleDateFormat("yyyy-MM", Locale.US).format(Calendar.getInstance().time)

    private fun shortMonth(key: String): String = monthFormat(key, "MMM yy")
    private fun longMonth(key: String): String = monthFormat(key, "MMMM yyyy")

    private fun monthFormat(key: String, pattern: String): String = runCatching {
        val source = SimpleDateFormat("yyyy-MM", Locale.US).apply { isLenient = false }
        SimpleDateFormat(pattern, Locale.getDefault()).format(source.parse(key)!!)
    }.getOrDefault(key)

    private fun formatAmount(amount: Double, currency: String): String {
        val formatter = NumberFormat.getNumberInstance().apply {
            maximumFractionDigits = if (amount % 1.0 == 0.0) 0 else 2
        }
        val value = formatter.format(amount)
        return if (currency in setOf("$", "€", "£", "₹", "¥")) "$currency$value" else "$value $currency"
    }

    private data class MonthSummary(val month: String, val expense: Double, val income: Double)

    companion object {
        private const val ACTION_CHANGE_MONTH = "com.budgetai.android.CHANGE_WIDGET_MONTH"
        private const val EXTRA_DIRECTION = "direction"
        private const val KEY_SUMMARIES = "budget_ai_widget_month_summaries"
        private const val KEY_SELECTED_MONTH = "budget_ai_widget_selected_month"
        private const val KEY_CURRENCY = "budget_ai_widget_currency"
    }
}
