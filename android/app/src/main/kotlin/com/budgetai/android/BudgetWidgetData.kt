package com.budgetai.android

import android.content.Context
import android.content.SharedPreferences
import android.net.Uri
import org.json.JSONArray
import java.text.NumberFormat
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Date
import java.util.Locale

/** One actual expense or income entry synced by Flutter's BudgetHomeWidgetSync. */
data class WidgetEntry(
    val id: String,
    val isIncome: Boolean,
    val date: Date,
    val hasTime: Boolean,
    val description: String,
    val amount: Double,
    val category: String,
) {
    val title: String get() = description.ifBlank { category }
}

data class MonthSummary(
    val month: Calendar,
    val expense: Double,
    val income: Double,
    val expenseCount: Int,
    val incomeCount: Int,
)

/** Everything the widgets render, read once per update. */
class BudgetSnapshot(val entries: List<WidgetEntry>, val currency: String) {
    private val now: Calendar = Calendar.getInstance()

    fun monthStart(offset: Int): Calendar = (now.clone() as Calendar).apply {
        set(Calendar.DAY_OF_MONTH, 1)
        set(Calendar.HOUR_OF_DAY, 0)
        set(Calendar.MINUTE, 0)
        set(Calendar.SECOND, 0)
        set(Calendar.MILLISECOND, 0)
        add(Calendar.MONTH, offset)
    }

    private fun inMonth(entry: WidgetEntry, month: Calendar): Boolean {
        val date = Calendar.getInstance().apply { time = entry.date }
        return date.get(Calendar.YEAR) == month.get(Calendar.YEAR) &&
            date.get(Calendar.MONTH) == month.get(Calendar.MONTH)
    }

    fun summary(offset: Int): MonthSummary {
        val month = monthStart(offset)
        val inMonth = entries.filter { inMonth(it, month) }
        val expenses = inMonth.filterNot { it.isIncome }
        val incomes = inMonth.filter { it.isIncome }
        return MonthSummary(
            month = month,
            expense = expenses.sumOf { it.amount },
            income = incomes.sumOf { it.amount },
            expenseCount = expenses.size,
            incomeCount = incomes.size,
        )
    }

    /** The oldest month offset with entries, so the ‹ arrow stops at the data. */
    val earliestOffset: Int
        get() {
            val oldest = entries.minByOrNull { it.date } ?: return 0
            val date = Calendar.getInstance().apply { time = oldest.date }
            val months = (now.get(Calendar.YEAR) - date.get(Calendar.YEAR)) * 12 +
                now.get(Calendar.MONTH) - date.get(Calendar.MONTH)
            return -maxOf(0, months)
        }

    fun categories(offset: Int): List<Pair<String, Double>> {
        val month = monthStart(offset)
        return entries
            .filter { !it.isIncome && inMonth(it, month) }
            .groupBy { it.category.trim().ifEmpty { "Other" } }
            .map { (name, items) -> name to items.sumOf { it.amount } }
            .sortedByDescending { it.second }
    }

    fun recentExpenses(limit: Int): List<WidgetEntry> =
        entries.filterNot { it.isIncome }.sortedByDescending { it.date }.take(limit)

    val todayExpenses: List<WidgetEntry>
        get() = entries.filter { entry ->
            if (entry.isIncome) return@filter false
            val date = Calendar.getInstance().apply { time = entry.date }
            date.get(Calendar.YEAR) == now.get(Calendar.YEAR) &&
                date.get(Calendar.DAY_OF_YEAR) == now.get(Calendar.DAY_OF_YEAR)
        }.sortedByDescending { it.date }

    companion object {
        private const val ENTRIES_KEY = "budget_ai_widget_entries"
        private const val CURRENCY_KEY = "budget_ai_widget_currency"

        fun load(preferences: SharedPreferences): BudgetSnapshot {
            val parser = SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss", Locale.US)
            val entries = mutableListOf<WidgetEntry>()
            runCatching {
                val array = JSONArray(preferences.getString(ENTRIES_KEY, "[]") ?: "[]")
                for (index in 0 until array.length()) {
                    val item = array.getJSONObject(index)
                    // Flutter writes wall-clock times; only yyyy-MM-ddTHH:mm:ss matters.
                    val date = parser.parse(item.optString("date").take(19)) ?: continue
                    entries += WidgetEntry(
                        id = item.optString("id"),
                        isIncome = item.optString("type") == "income",
                        date = date,
                        hasTime = item.optBoolean("has_time"),
                        description = item.optString("description"),
                        amount = item.optDouble("amount", 0.0),
                        category = item.optString("category", "Other"),
                    )
                }
            }
            return BudgetSnapshot(
                entries,
                preferences.getString(CURRENCY_KEY, "USD") ?: "USD",
            )
        }
    }
}

object WidgetFormat {
    private val prefixSymbols = setOf("$", "€", "£", "₹", "¥")

    fun amount(value: Double, currency: String, sign: String = ""): String {
        // Whole amounts drop the decimals; others always show cents ($40.80).
        val digits = if (value % 1.0 == 0.0) 0 else 2
        val formatter = NumberFormat.getNumberInstance().apply {
            minimumFractionDigits = digits
            maximumFractionDigits = digits
        }
        val text = formatter.format(kotlin.math.abs(value))
        return if (currency in prefixSymbols) "$sign$currency$text" else "$sign$text $currency"
    }

    fun month(month: Calendar): String {
        val sameYear = month.get(Calendar.YEAR) == Calendar.getInstance().get(Calendar.YEAR)
        val pattern = if (sameYear) "MMM" else "MMM yy"
        // English short names (Sep, not Sept), matching the iOS widgets.
        return SimpleDateFormat(pattern, Locale.US).format(month.time)
    }

    fun day(date: Date): String {
        val today = Calendar.getInstance()
        val value = Calendar.getInstance().apply { time = date }
        val days = today.get(Calendar.DAY_OF_YEAR) - value.get(Calendar.DAY_OF_YEAR)
        return when {
            today.get(Calendar.YEAR) != value.get(Calendar.YEAR) ->
                SimpleDateFormat("d MMM", Locale.getDefault()).format(date)
            days == 0 -> "Today"
            days == 1 -> "Yesterday"
            else -> SimpleDateFormat("d MMM", Locale.getDefault()).format(date)
        }
    }

    fun time(date: Date): String =
        SimpleDateFormat("h:mm a", Locale.getDefault()).format(date)

    fun entries(count: Int): String = if (count == 1) "1 entry" else "$count entries"

    fun percent(value: Double): String = "${Math.round(value * 100)}%"
}

/** Deep links the app's HomeWidgetLaunch understands. */
object WidgetLink {
    private fun build(path: String, month: Calendar?, entryId: String?): Uri {
        val builder = Uri.Builder().scheme("budgetai").authority("widget").path(path)
            .appendQueryParameter("homeWidget", "")
        if (month != null) {
            builder.appendQueryParameter(
                "month",
                SimpleDateFormat("yyyy-MM", Locale.US).format(month.time),
            )
        }
        if (entryId != null) builder.appendQueryParameter("entry", entryId)
        return builder.build()
    }

    fun finances(month: Calendar? = null, entry: WidgetEntry? = null): Uri {
        val entryMonth = entry?.let { Calendar.getInstance().apply { time = it.date } }
        return build("finances", entryMonth ?: month, entry?.id)
    }

    fun insights(month: Calendar? = null): Uri = build("insights", month, null)
}

/** Month offsets chosen with each widget's ‹ › arrows, per widget instance. */
object WidgetMonthState {
    private const val PREFERENCES = "budget_ai_widget_state"

    private fun key(widgetId: Int) = "month_offset_$widgetId"

    fun offset(context: Context, widgetId: Int): Int =
        context.getSharedPreferences(PREFERENCES, Context.MODE_PRIVATE)
            .getInt(key(widgetId), 0).coerceAtMost(0)

    fun shift(context: Context, widgetId: Int, step: Int) {
        val next = (offset(context, widgetId) + step).coerceIn(-120, 0)
        context.getSharedPreferences(PREFERENCES, Context.MODE_PRIVATE)
            .edit().putInt(key(widgetId), next).apply()
    }

    fun clear(context: Context, widgetIds: IntArray) {
        val editor = context.getSharedPreferences(PREFERENCES, Context.MODE_PRIVATE).edit()
        widgetIds.forEach { editor.remove(key(it)) }
        editor.apply()
    }
}
