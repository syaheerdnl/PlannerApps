import 'dart:ui';

import 'package:flutter/material.dart';

import '../core/theme.dart';

class NavItem {
  const NavItem(this.label, this.icon);

  final String label;
  final IconData icon;
}

/// A floating, translucent tab bar in the style of recent iOS releases.
///
/// Stack of ideas (outside in):
///  1. DecoratedBox  - draws the soft shadow
///  2. ClipRRect     - rounds the corners AND limits the blur to the pill
///  3. BackdropFilter- blurs whatever is painted behind the bar
///  4. Container     - the see-through white tint and thin border
class FloatingNavBar extends StatelessWidget {
  const FloatingNavBar({super.key, required this.items, required this.currentIndex, required this.onSelected});

  final List<NavItem> items;
  final int currentIndex;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(32);

    return SafeArea(
      // Keeps the bar off the very bottom edge even on phones with no gesture inset.
      minimum: const EdgeInsets.fromLTRB(16, 0, 16, 14),
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: radius,
          boxShadow: const [BoxShadow(color: Color(0x1A101828), blurRadius: 24, offset: Offset(0, 8))],
        ),
        child: ClipRRect(
          borderRadius: radius,
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
            child: Container(
              height: 64,
              padding: const EdgeInsets.symmetric(horizontal: 6),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.6),
                borderRadius: radius,
                border: Border.all(color: Colors.white.withValues(alpha: 0.75)),
              ),
              child: Material(
                type: MaterialType.transparency,
                child: Row(
                  children: [
                    for (var i = 0; i < items.length; i++)
                      Expanded(
                        child: _NavButton(item: items[i], selected: i == currentIndex, onTap: () => onSelected(i)),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _NavButton extends StatelessWidget {
  const _NavButton({required this.item, required this.selected, required this.onTap});

  final NavItem item;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected ? AppColors.brandDark : const Color(0xFF3C4650);

    return Semantics(
      button: true,
      selected: selected,
      label: item.label,
      child: ExcludeSemantics(
        child: InkWell(
          borderRadius: BorderRadius.circular(26),
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            height: 52,
            margin: const EdgeInsets.symmetric(horizontal: 2),
            decoration: BoxDecoration(
              color: selected ? AppColors.brand.withValues(alpha: 0.16) : Colors.transparent,
              borderRadius: BorderRadius.circular(26),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(item.icon, size: 24, color: color),
                const SizedBox(height: 2),
                Text(
                  item.label,
                  style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w500, color: color),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
