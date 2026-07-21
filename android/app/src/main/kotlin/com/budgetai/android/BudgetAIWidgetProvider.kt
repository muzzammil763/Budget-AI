package com.budgetai.android

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.graphics.Color
import android.net.Uri
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetProvider
import java.text.DateFormatSymbols
import java.text.NumberFormat
import java.util.Calendar

class BudgetAIWidgetProvider : HomeWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences,
    ) {
        val expense = number(widgetData, "budget_ai_widget_month_expense")
        val income = number(widgetData, "budget_ai_widget_month_income")
        val latestAmount = number(widgetData, "budget_ai_widget_latest_amount")
        val latestType = widgetData.getString(
            "budget_ai_widget_latest_type",
            "expense",
        ) ?: "expense"
        val currency = widgetData.getString("budget_ai_widget_currency", "USD") ?: "USD"
        val latest = widgetData.getString(
            "budget_ai_widget_latest_description",
            "No entries yet",
        ) ?: "No entries yet"
        val month = DateFormatSymbols.getInstance().months[
            Calendar.getInstance().get(Calendar.MONTH)
        ].uppercase()
        val openApp = HomeWidgetLaunchIntent.getActivity(
            context,
            MainActivity::class.java,
            Uri.parse("budgetai://widget?homeWidget"),
        )

        appWidgetIds.forEach { widgetId ->
            val views = RemoteViews(context.packageName, R.layout.budget_ai_widget).apply {
                setTextViewText(R.id.widget_month, month)
                setTextViewText(
                    R.id.widget_balance,
                    formatAmount(income - expense, currency, signed = true),
                )
                setTextViewText(R.id.widget_income, formatAmount(income, currency))
                setTextViewText(R.id.widget_expense, formatAmount(expense, currency))
                setTextViewText(R.id.widget_latest, latest)
                setTextViewText(
                    R.id.widget_latest_amount,
                    if (latestAmount > 0) {
                        formatAmount(
                            latestAmount,
                            currency,
                            signed = true,
                            positive = latestType == "income",
                        )
                    } else {
                        ""
                    },
                )
                setTextColor(
                    R.id.widget_latest_amount,
                    Color.parseColor(if (latestType == "income") "#59C879" else "#FF6B6B"),
                )
                setOnClickPendingIntent(R.id.widget_root, openApp)
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
        positive: Boolean = true,
    ): String {
        val formatter = NumberFormat.getNumberInstance().apply {
            maximumFractionDigits = if (amount % 1.0 == 0.0) 0 else 2
        }
        val sign = when {
            amount < 0 -> "-"
            signed && amount > 0 -> if (positive) "+" else "−"
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
