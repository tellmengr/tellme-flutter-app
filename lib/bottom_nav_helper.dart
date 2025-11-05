import 'package:flutter/material.dart';
import 'bottom_nav_helper.dart';

class BottomNavHelper {
  // Navigate to a named route (e.g., /signin)
  static void navigateToRoute(BuildContext context, String route, {Object? arguments}) {
    Navigator.pushNamed(context, route, arguments: arguments);
  }

  // Navigate to a specific bottom navigation tab
  static void navigateToTab(BuildContext context, int tabIndex, {Function(int)? onTabChange}) {
    if (onTabChange != null) {
      onTabChange(tabIndex);
    } else {
      Navigator.popUntil(context, (route) => route.isFirst);
    }
  }

  // Go back one screen safely
  static void goBack(BuildContext context) {
    if (Navigator.canPop(context)) {
      Navigator.pop(context);
    } else {
      Navigator.pushNamedAndRemoveUntil(context, '/', (route) => false);
    }
  }
}