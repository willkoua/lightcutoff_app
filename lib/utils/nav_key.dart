import 'package:flutter/material.dart';

/// Clé globale du Navigator racine. Utilisée par les services hors widget
/// tree (notifications push, futurs deep links) pour déclencher une
/// navigation sans avoir de [BuildContext] sous la main.
///
/// Branchée sur le [MaterialApp] dans `app.dart`.
final navigatorKey = GlobalKey<NavigatorState>();
