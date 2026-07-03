import 'package:flutter/material.dart';
import 'package:budget_ai/app/theme/app_theme.dart';

/// A single tab item definition for [NavBar].
class NavBarItem {
  /// The label displayed under/beside the icon.
  final String label;

  /// Icon shown when this tab is selected.
  final IconData selectedIcon;

  /// Icon shown when this tab is not selected.
  /// Defaults to [selectedIcon] if not provided.
  final IconData? unselectedIcon;

  const NavBarItem({
    required this.label,
    required this.selectedIcon,
    this.unselectedIcon,
  });
}

class NavBar extends StatefulWidget {
  // ── Required ────────────────────────────────────────────────────────────────

  /// Tab definitions. Must contain at least 2 items.
  final List<NavBarItem> items;

  // ── Optional ─────────────────────────────────────────────────────────────────

  /// Initially selected index. Defaults to 0.
  final int initialIndex;

  /// Called whenever the selected tab changes.
  final ValueChanged<int>? onIndexChanged;

  /// Height of the nav bar pill. Defaults to 46.
  final double height;

  /// Background color of the nav bar container. Defaults to [Colors.white].
  final Color backgroundColor;

  /// Border color of the nav bar container. Defaults to [Colors.grey].
  final Color borderColor;

  /// Border width of the nav bar container. Defaults to 0.5.
  final double borderWidth;

  /// Background color of the selected tab indicator. Defaults to Color(0xFFEFF5FE).
  final Color selectedTabColor;

  /// Border color of the selected tab indicator. Defaults to Color(0xff4C79FF).
  final Color selectedTabBorderColor;

  /// Tint color for the selected icon and label. Defaults to Color(0xff4C79FF).
  final Color selectedColor;

  /// Color for unselected icons and labels. Defaults to [Colors.black87].
  final Color unselectedColor;

  /// Font size for the tab labels. Defaults to 14.
  final double labelFontSize;

  /// Gap between the icon and label. Defaults to 4.
  final double iconLabelSpacing;

  /// Icon size. Defaults to 16.
  final double iconSize;

  /// Duration of the slide animation. Defaults to 400 ms.
  final Duration animationDuration;

  /// Curve of the slide animation. Defaults to [Curves.fastOutSlowIn].
  final Curve animationCurve;

  /// Outer padding around the nav bar. Defaults to EdgeInsets.all(18).
  final EdgeInsetsGeometry padding;

  /// Top margin applied to the nav bar container. Defaults to 26.
  final double topMargin;

  const NavBar({
    super.key,
    // Required
    required this.items,
    // Optional
    this.initialIndex = 0,
    this.onIndexChanged,
    this.height = 46,
    this.backgroundColor = Colors.white,
    this.borderColor = Colors.grey,
    this.borderWidth = 0.5,
    this.selectedTabColor = const Color(0xFFEFF5FE),
    this.selectedTabBorderColor = const Color(0xff4C79FF),
    this.selectedColor = const Color(0xff4C79FF),
    this.unselectedColor = Colors.black87,
    this.labelFontSize = 14,
    this.iconLabelSpacing = 4,
    this.iconSize = 16,
    this.animationDuration = const Duration(milliseconds: 400),
    this.animationCurve = Curves.fastOutSlowIn,
    this.padding = const EdgeInsets.all(18.0),
    this.topMargin = 26,
  }) : assert(items.length >= 2, 'NavBar requires at least 2 items.');

  @override
  State<NavBar> createState() => _NavBarState();
}

class _NavBarState extends State<NavBar> {
  late int _selectedIndex;

  @override
  void initState() {
    super.initState();
    _selectedIndex = widget.initialIndex;
  }

  @override
  void didUpdateWidget(NavBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialIndex != oldWidget.initialIndex) {
      setState(() => _selectedIndex = widget.initialIndex);
    }
  }

  void _onTap(int index) {
    if (_selectedIndex == index) return;
    setState(() => _selectedIndex = index);
    widget.onIndexChanged?.call(index);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: widget.padding,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        height: widget.height,
        margin: EdgeInsets.only(top: widget.topMargin),
        width: double.infinity,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(100),
          color: widget.backgroundColor,
          border: Border.all(
            color: widget.borderColor,
            width: widget.borderWidth,
          ),
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.hasBoundedWidth
                ? constraints.maxWidth
                : MediaQuery.of(context).size.width;

            if (width <= 0) {
              return const SizedBox.shrink();
            }

            final segmentWidth = width / widget.items.length;

            return Stack(
              clipBehavior: Clip.none,
              children: [
                // ── Sliding indicator ──────────────────────────────────
                AnimatedPositioned(
                  duration: widget.animationDuration,
                  curve: widget.animationCurve,
                  left: _selectedIndex * segmentWidth,
                  top: -4,
                  child: Container(
                    width: segmentWidth,
                    height: widget.height + 9,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(100),
                      color: widget.selectedTabColor,
                      border: Border.all(
                        color: widget.selectedTabBorderColor,
                        width: 0.6,
                      ),
                    ),
                  ),
                ),

                // ── Tab row ────────────────────────────────────────────
                Row(
                  children: List.generate(widget.items.length, (index) {
                    final item = widget.items[index];
                    final isSelected = _selectedIndex == index;
                    final icon = isSelected
                        ? item.selectedIcon
                        : (item.unselectedIcon ?? item.selectedIcon);
                    final color =
                        isSelected ? widget.selectedColor : widget.unselectedColor;

                    return Expanded(
                      child: GestureDetector(
                        onTap: () => _onTap(index),
                        child: Container(
                          color: Colors.transparent,
                          height: widget.height + 4,
                          child: Center(
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(icon,
                                    size: widget.iconSize, color: color),
                                SizedBox(width: widget.iconLabelSpacing),
                                Text(
                                  item.label,
                                  style: TextStyle(
                                    color: color,
                                    fontSize: widget.labelFontSize,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  }),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// A simple horizontal pill-style navigation bar for text-only labels.
///
/// Shows a scrollable list of selectable pills. The selected pill is filled
/// with the primary color; unselected pills show an outline. Used for
/// compact spaces where icons are not needed (e.g. Finances month selector).
class PillNavBar extends StatelessWidget {
  final List<String> items;
  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final EdgeInsets padding;
  final double height;

  const PillNavBar({
    super.key,
    required this.items,
    required this.selectedIndex,
    required this.onSelected,
    this.padding = const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
    this.height = 44,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      height: height,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: padding,
        itemCount: items.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (ctx, i) {
          final selected = i == selectedIndex;
          return GestureDetector(
            onTap: () => onSelected(i),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
              decoration: BoxDecoration(
                color: selected ? theme.colorScheme.primary : Colors.transparent,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: selected
                      ? theme.colorScheme.primary
                      : theme.colorScheme.outline,
                ),
              ),
              child: Center(
                child: Text(
                  items[i],
                  style: AppTheme.bodySmall.copyWith(
                    color: selected
                        ? theme.colorScheme.onPrimary
                        : theme.colorScheme.onSurface,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    fontSize: 12,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
