import 'package:flutter/material.dart';

class _SettingsInherited extends InheritedWidget {
  const _SettingsInherited({
    required this.data,
    required super.child,
  });

  final SettingsProviderState data;

  @override
  bool updateShouldNotify(_SettingsInherited oldWidget) {
    return data.fontSizeMultiplier != oldWidget.data.fontSizeMultiplier;
  }
}
class SettingsProvider extends StatefulWidget {
  const SettingsProvider({required this.child, super.key});
  final Widget child;

  static SettingsProviderState of(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<_SettingsInherited>()!.data;
  }

  @override
  State<SettingsProvider> createState() => SettingsProviderState();
}

class SettingsProviderState extends State<SettingsProvider> {
  double _fontSizeMultiplier = 1.0;

  double get fontSizeMultiplier => _fontSizeMultiplier;

  void updateFontSize(double newMultiplier) {
    setState(() {
      _fontSizeMultiplier = newMultiplier;
    });
  }

  @override
  Widget build(BuildContext context) {
    return _SettingsInherited(
      data: this,
      child: widget.child,
    );
  }
}