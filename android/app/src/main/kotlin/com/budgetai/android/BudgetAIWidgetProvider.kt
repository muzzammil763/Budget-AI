package com.budgetai.android

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.net.Uri
import android.view.View
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetPlugin
import es.antonborri.home_widget.HomeWidgetProvider
import java.text.SimpleDateFormat
import java.util.Locale

/**
 * Shared base for every Budget AI home-screen widget: reads the synced entries,
 * applies each instance's ‹ › month choice, and wires taps to app deep links.
 */
abstract class BudgetSnapshotWidget : HomeWidgetProvider() {
    abstract fun build(
        context: Context,
        snapshot: BudgetSnapshot,
        offset: Int,
        widgetId: Int,
    ): RemoteViews

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences,
    ) {
        val snapshot = BudgetSnapshot.load(widgetData)
        appWidgetIds.forEach { widgetId ->
            val offset = maxOf(WidgetMonthState.offset(context, widgetId), snapshot.earliestOffset)
            appWidgetManager.updateAppWidget(widgetId, build(context, snapshot, offset, widgetId))
        }
    }

    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action == ACTION_SHIFT_MONTH) {
            val widgetId = intent.getIntExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, -1)
            if (widgetId != -1) {
                WidgetMonthState.shift(context, widgetId, intent.getIntExtra(EXTRA_STEP, 0))
                onUpdate(
                    context,
                    AppWidgetManager.getInstance(context),
                    intArrayOf(widgetId),
                    HomeWidgetPlugin.getData(context),
                )
            }
            return
        }
        super.onReceive(context, intent)
    }

    override fun onDeleted(context: Context, appWidgetIds: IntArray) {
        WidgetMonthState.clear(context, appWidgetIds)
        super.onDeleted(context, appWidgetIds)
    }

    protected fun launch(context: Context, uri: Uri): PendingIntent =
        HomeWidgetLaunchIntent.getActivity(context, MainActivity::class.java, uri)

    protected fun color(context: Context, id: Int): Int = context.getColor(id)

    /** Fills the `‹ Oct ›` chip; arrows stop at the first month with data and today. */
    protected fun bindMonthSwitcher(
        context: Context,
        views: RemoteViews,
        snapshot: BudgetSnapshot,
        offset: Int,
        widgetId: Int,
    ) {
        views.setViewVisibility(R.id.month_switcher, View.VISIBLE)
        views.setTextViewText(R.id.month_label, WidgetFormat.month(snapshot.monthStart(offset)))
        bindArrow(context, views, R.id.month_prev, widgetId, -1, offset > snapshot.earliestOffset)
        bindArrow(context, views, R.id.month_next, widgetId, 1, offset < 0)
    }

    private fun bindArrow(
        context: Context,
        views: RemoteViews,
        viewId: Int,
        widgetId: Int,
        step: Int,
        enabled: Boolean,
    ) {
        views.setTextColor(
            viewId,
            color(context, if (enabled) R.color.widget_primary else R.color.widget_disabled),
        )
        if (!enabled) {
            views.setOnClickPendingIntent(viewId, null)
            return
        }
        val intent = Intent(context, javaClass).apply {
            action = ACTION_SHIFT_MONTH
            putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, widgetId)
            putExtra(EXTRA_STEP, step)
            data = Uri.parse("budgetai-widget://shift/$widgetId/$step")
        }
        val pending = PendingIntent.getBroadcast(
            context,
            0,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        views.setOnClickPendingIntent(viewId, pending)
    }

    companion object {
        const val ACTION_SHIFT_MONTH = "com.budgetai.android.widget.SHIFT_MONTH"
        private const val EXTRA_STEP = "step"
    }
}

/** The wide summary: this month's expenses, income, entry count, two newest expenses. */
class BudgetAIWidgetProvider : BudgetSnapshotWidget() {
    override fun build(
        context: Context,
        snapshot: BudgetSnapshot,
        offset: Int,
        widgetId: Int,
    ): RemoteViews {
        val month = snapshot.summary(0)
        val recent = snapshot.recentExpenses(2)
        val currency = snapshot.currency
        return RemoteViews(context.packageName, R.layout.budget_ai_widget).apply {
            setTextViewText(
                R.id.widget_month,
                SimpleDateFormat("MMMM", Locale.getDefault()).format(month.month.time),
            )
            WidgetDisplayText.bind(context, this, R.id.widget_title, R.id.widget_title_image, "Budget AI", 12f)
            WidgetDisplayText.bind(
                context,
                this,
                R.id.widget_balance,
                R.id.widget_balance_image,
                WidgetFormat.amount(month.expense, currency),
                24f,
            )
            setTextViewText(R.id.widget_income, WidgetFormat.amount(month.income, currency))
            setTextViewText(R.id.widget_entries, "${month.expenseCount + month.incomeCount}")
            setTextViewText(R.id.widget_latest, recent.getOrNull(0)?.title ?: "No entries yet")
            setTextViewText(
                R.id.widget_latest_amount,
                recent.getOrNull(0)?.let { WidgetFormat.amount(it.amount, currency, "−") } ?: "",
            )
            setTextColor(R.id.widget_latest_amount, color(context, R.color.widget_expense))
            setViewVisibility(
                R.id.widget_previous_row,
                if (recent.size > 1) View.VISIBLE else View.GONE,
            )
            recent.getOrNull(1)?.let {
                setTextViewText(R.id.widget_previous, it.title)
                setTextViewText(
                    R.id.widget_previous_amount,
                    WidgetFormat.amount(it.amount, currency, "−"),
                )
                setTextColor(R.id.widget_previous_amount, color(context, R.color.widget_expense))
            }
            setOnClickPendingIntent(R.id.widget_root, launch(context, WidgetLink.finances()))
        }
    }
}

/** Small expense or income total for a month, with ‹ › arrows. */
abstract class MonthTotalWidget(private val isIncome: Boolean) : BudgetSnapshotWidget() {
    override fun build(
        context: Context,
        snapshot: BudgetSnapshot,
        offset: Int,
        widgetId: Int,
    ): RemoteViews {
        val summary = snapshot.summary(offset)
        val total = if (isIncome) summary.income else summary.expense
        val count = if (isIncome) summary.incomeCount else summary.expenseCount
        return RemoteViews(context.packageName, R.layout.widget_month_total).apply {
            setImageViewResource(
                R.id.flow_badge,
                if (isIncome) R.drawable.ic_widget_arrow_down_left else R.drawable.ic_widget_arrow_up_right,
            )
            setInt(
                R.id.flow_badge,
                "setBackgroundResource",
                if (isIncome) R.drawable.widget_badge_income else R.drawable.widget_badge_expense,
            )
            setTextViewText(R.id.total_label, if (isIncome) "Income" else "Expenses")
            WidgetDisplayText.bind(
                context,
                this,
                R.id.total_amount,
                R.id.total_amount_image,
                WidgetFormat.amount(total, snapshot.currency),
                24f,
            )
            setTextViewText(R.id.total_count, WidgetFormat.entries(count))
            setTextColor(
                R.id.total_count,
                color(context, if (isIncome) R.color.widget_income else R.color.widget_expense),
            )
            setInt(
                R.id.total_count,
                "setBackgroundResource",
                if (isIncome) R.drawable.widget_pill_income else R.drawable.widget_pill_expense,
            )
            bindMonthSwitcher(context, this, snapshot, offset, widgetId)
            setOnClickPendingIntent(
                R.id.widget_root,
                launch(context, WidgetLink.finances(month = summary.month)),
            )
        }
    }
}

class ExpenseTotalWidgetProvider : MonthTotalWidget(isIncome = false)

class IncomeTotalWidgetProvider : MonthTotalWidget(isIncome = true)

/** Small income and expenses side by side, with proportion bars and ‹ ›. */
class MonthBalanceWidgetProvider : BudgetSnapshotWidget() {
    override fun build(
        context: Context,
        snapshot: BudgetSnapshot,
        offset: Int,
        widgetId: Int,
    ): RemoteViews {
        val summary = snapshot.summary(offset)
        val largest = maxOf(summary.income, summary.expense, 1.0)
        return RemoteViews(context.packageName, R.layout.widget_month_balance).apply {
            WidgetDisplayText.bind(
                context,
                this,
                R.id.balance_income,
                R.id.balance_income_image,
                WidgetFormat.amount(summary.income, snapshot.currency),
                16f,
            )
            WidgetDisplayText.bind(
                context,
                this,
                R.id.balance_expense,
                R.id.balance_expense_image,
                WidgetFormat.amount(summary.expense, snapshot.currency),
                16f,
            )
            setProgressBar(R.id.balance_income_bar, 1000, barValue(summary.income / largest), false)
            setProgressBar(R.id.balance_expense_bar, 1000, barValue(summary.expense / largest), false)
            bindMonthSwitcher(context, this, snapshot, offset, widgetId)
            setOnClickPendingIntent(
                R.id.widget_root,
                launch(context, WidgetLink.finances(month = summary.month)),
            )
        }
    }
}

/** Medium list of the five newest expenses; each row opens its entry. */
class RecentExpensesWidgetProvider : BudgetSnapshotWidget() {
    override fun build(
        context: Context,
        snapshot: BudgetSnapshot,
        offset: Int,
        widgetId: Int,
    ): RemoteViews {
        val recent = snapshot.recentExpenses(5)
        return RemoteViews(context.packageName, R.layout.widget_list).apply {
            setTextViewText(R.id.list_title, "Recent expenses")
            setTextViewText(R.id.list_trailing, "Last 5")
            setViewVisibility(R.id.month_switcher, View.GONE)
            setTextViewText(R.id.list_empty, "No expenses yet")
            bindRows(this, recent.isEmpty())
            recent.forEach { expense ->
                val row = RemoteViews(context.packageName, R.layout.widget_row_compact).apply {
                    setTextViewText(R.id.row_title, expense.title)
                    setTextViewText(R.id.row_detail, WidgetFormat.day(expense.date))
                    setTextViewText(
                        R.id.row_amount,
                        WidgetFormat.amount(expense.amount, snapshot.currency, "−"),
                    )
                    setOnClickPendingIntent(
                        R.id.row_root,
                        launch(context, WidgetLink.finances(entry = expense)),
                    )
                }
                addView(R.id.list_rows, row)
            }
            setOnClickPendingIntent(R.id.widget_root, launch(context, WidgetLink.finances()))
        }
    }
}

/** Large view of today's spending: total, count, and each expense. */
class TodayExpensesWidgetProvider : BudgetSnapshotWidget() {
    override fun build(
        context: Context,
        snapshot: BudgetSnapshot,
        offset: Int,
        widgetId: Int,
    ): RemoteViews {
        val today = snapshot.todayExpenses
        val shown = today.take(MAX_ROWS)
        return RemoteViews(context.packageName, R.layout.widget_today).apply {
            setTextViewText(
                R.id.today_date,
                SimpleDateFormat("EEEE, d MMM", Locale.getDefault()).format(java.util.Date()),
            )
            WidgetDisplayText.bind(
                context,
                this,
                R.id.today_total,
                R.id.today_total_image,
                WidgetFormat.amount(today.sumOf { it.amount }, snapshot.currency),
                30f,
            )
            setTextViewText(R.id.today_count, WidgetFormat.entries(today.size))
            bindRows(this, today.isEmpty())
            shown.forEach { expense ->
                val row = RemoteViews(context.packageName, R.layout.widget_row_detail).apply {
                    setTextViewText(R.id.row_title, expense.title)
                    setTextViewText(
                        R.id.row_detail,
                        if (expense.hasTime) WidgetFormat.time(expense.date) else expense.category,
                    )
                    setTextViewText(
                        R.id.row_amount,
                        WidgetFormat.amount(expense.amount, snapshot.currency, "−"),
                    )
                    setOnClickPendingIntent(
                        R.id.row_root,
                        launch(context, WidgetLink.finances(entry = expense)),
                    )
                }
                addView(R.id.list_rows, row)
            }
            setOnClickPendingIntent(R.id.widget_root, launch(context, WidgetLink.finances()))
        }
    }

    private companion object {
        const val MAX_ROWS = 6
    }
}

/** Small comparison of this month's expenses with last month's. */
class MonthComparisonWidgetProvider : BudgetSnapshotWidget() {
    override fun build(
        context: Context,
        snapshot: BudgetSnapshot,
        offset: Int,
        widgetId: Int,
    ): RemoteViews {
        val current = snapshot.summary(0)
        val previous = snapshot.summary(-1)
        val largest = maxOf(current.expense, previous.expense, 1.0)
        val currency = snapshot.currency
        return RemoteViews(context.packageName, R.layout.widget_comparison).apply {
            setTextViewText(R.id.compare_previous_month, WidgetFormat.month(previous.month))
            setTextViewText(R.id.compare_previous_amount, WidgetFormat.amount(previous.expense, currency))
            setProgressBar(R.id.compare_previous_bar, 1000, barValue(previous.expense / largest), false)
            setTextViewText(R.id.compare_current_month, WidgetFormat.month(current.month))
            setTextViewText(R.id.compare_current_amount, WidgetFormat.amount(current.expense, currency))
            setProgressBar(R.id.compare_current_bar, 1000, barValue(current.expense / largest), false)
            if (previous.expense > 0) {
                val change = (current.expense - previous.expense) / previous.expense
                // Spending more than last month is the warning case.
                val more = change > 0
                setViewVisibility(R.id.compare_change, View.VISIBLE)
                setTextViewText(
                    R.id.compare_change,
                    "${if (more) "↑" else "↓"} ${WidgetFormat.percent(kotlin.math.abs(change))}",
                )
                setTextColor(
                    R.id.compare_change,
                    color(context, if (more) R.color.widget_expense else R.color.widget_income),
                )
                setInt(
                    R.id.compare_change,
                    "setBackgroundResource",
                    if (more) R.drawable.widget_pill_expense else R.drawable.widget_pill_income,
                )
            } else {
                setViewVisibility(R.id.compare_change, View.GONE)
            }
            setOnClickPendingIntent(R.id.widget_root, launch(context, WidgetLink.insights()))
        }
    }
}

/** Medium list of the month's four largest expense categories, with ‹ ›. */
class TopCategoriesWidgetProvider : BudgetSnapshotWidget() {
    override fun build(
        context: Context,
        snapshot: BudgetSnapshot,
        offset: Int,
        widgetId: Int,
    ): RemoteViews {
        val categories = snapshot.categories(offset)
        val total = categories.sumOf { it.second }
        val largest = categories.firstOrNull()?.second ?: 1.0
        val month = snapshot.monthStart(offset)
        return RemoteViews(context.packageName, R.layout.widget_list).apply {
            setTextViewText(R.id.list_title, "Top categories")
            setViewVisibility(R.id.list_trailing, View.GONE)
            setTextViewText(R.id.list_empty, "No expenses this month")
            bindMonthSwitcher(context, this, snapshot, offset, widgetId)
            bindRows(this, categories.isEmpty())
            categories.take(4).forEach { (name, amount) ->
                val row = RemoteViews(context.packageName, R.layout.widget_row_category).apply {
                    setTextViewText(R.id.category_name, name)
                    setTextViewText(R.id.category_amount, WidgetFormat.amount(amount, snapshot.currency))
                    setTextViewText(R.id.category_share, WidgetFormat.percent(amount / maxOf(total, 1.0)))
                    setProgressBar(R.id.category_bar, 1000, barValue(amount / maxOf(largest, 1.0)), false)
                }
                addView(R.id.list_rows, row)
            }
            setOnClickPendingIntent(R.id.widget_root, launch(context, WidgetLink.insights(month)))
        }
    }
}

/** Clears the row container and shows the empty message when there is nothing to list. */
private fun bindRows(views: RemoteViews, isEmpty: Boolean) {
    views.removeAllViews(R.id.list_rows)
    views.setViewVisibility(R.id.list_rows, if (isEmpty) View.GONE else View.VISIBLE)
    views.setViewVisibility(R.id.list_empty, if (isEmpty) View.VISIBLE else View.GONE)
}

/** Progress for a 0..1 share, with a visible sliver for any non-zero amount. */
private fun barValue(fraction: Double): Int =
    if (fraction <= 0.0) 0 else maxOf(20, (fraction.coerceIn(0.0, 1.0) * 1000).toInt())
