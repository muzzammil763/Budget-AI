package com.budgetai.android

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.net.Uri
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetProvider
import java.text.NumberFormat

class BudgetAIWidgetProvider : HomeWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences,
    ) {
        val expense = number(widgetData, "budget_ai_widget_month_expense")
        val income = number(widgetData, "budget_ai_widget_month_income")
        val currency = widgetData.getString("budget_ai_widget_currency", "USD") ?: "USD"
        val latest = widgetData.getString(
            "budget_ai_widget_latest_description",
            "No entries yet",
        ) ?: "No entries yet"
        val openApp = HomeWidgetLaunchIntent.getActivity(
            context,
            MainActivity::class.java,
            Uri.parse("budgetai://widget?homeWidget"),
        )

        appWidgetIds.forEach { widgetId ->
            val views = RemoteViews(context.packageName, R.layout.budget_ai_widget).apply {
                setTextViewText(
                    R.id.widget_balance,
                    formatAmount(income - expense, currency, signed = true),
                )
                setTextViewText(R.id.widget_income, "IN ${formatAmount(income, currency)}")
                setTextViewText(R.id.widget_expense, "OUT ${formatAmount(expense, currency)}")
                setTextViewText(R.id.widget_latest, latest)
                setOnClickPendingIntent(R.id.widget_root, openApp)
                setOnClickPendingIntent(R.id.widget_mic, openApp)
            }
            appWidgetManager.updateAppWidget(widgetId, views)
        }
    }

    private fun number(preferences: SharedPreferences, key: String): Double =
        (preferences.all[key] as? Number)?.toDouble() ?: 0.0

    private fun formatAmount(
        amount: Double,
        currency: String,
        signed: Boolean = false,
    ): String {
        val formatter = NumberFormat.getNumberInstance().apply {
            maximumFractionDigits = if (amount % 1.0 == 0.0) 0 else 2
        }
        val sign = when {
            amount < 0 -> "-"
            signed && amount > 0 -> "+"
            else -> ""
        }
        val value = formatter.format(kotlin.math.abs(amount))
        return if (currency in setOf("$", "€", "£", "₹", "¥")) {
            "$sign$currency$value"
        } else {
            "$sign$value $currency"
        }
    }
}
