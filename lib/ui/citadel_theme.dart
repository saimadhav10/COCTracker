import 'package:flutter/material.dart';

const amber = Color(0xfff59e0b);
const elixir = Color(0xffc084fc);
const darkElixir = Color(0xff22d3ee);
const readyGreen = Color(0xff34d399);
const muted = Color(0xffa8b3c7);

ThemeData citadelTheme(String variant) {
  final background = switch (variant) {
    'onyx' => const Color(0xff000000),
    'purple' => const Color(0xff120c20),
    _ => const Color(0xff0b111e),
  };
  final surface = switch (variant) {
    'onyx' => const Color(0xff131313),
    'purple' => const Color(0xff20182e),
    _ => const Color(0xff181e2c),
  };
  final scheme =
      ColorScheme.fromSeed(
        seedColor: amber,
        brightness: Brightness.dark,
      ).copyWith(
        primary: amber,
        onPrimary: const Color(0xff201300),
        surface: surface,
        onSurface: const Color(0xffedf0fb),
        onSurfaceVariant: muted,
        secondary: elixir,
      );
  final base = ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: scheme,
    fontFamily: 'PlusJakartaSans',
  );
  return base.copyWith(
    scaffoldBackgroundColor: background,
    textTheme: base.textTheme.copyWith(
      headlineMedium: base.textTheme.headlineMedium?.copyWith(
        fontFamily: 'SpaceGrotesk',
        fontWeight: FontWeight.w700,
      ),
      titleLarge: base.textTheme.titleLarge?.copyWith(
        fontFamily: 'SpaceGrotesk',
        fontWeight: FontWeight.w700,
      ),
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: surface,
      foregroundColor: scheme.onSurface,
      centerTitle: false,
      elevation: 0,
    ),
    cardTheme: CardThemeData(
      color: surface,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: Color(0xff36405a)),
      ),
    ),
    dividerTheme: const DividerThemeData(color: Color(0xff303748), space: 24),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: background,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: Color(0xff36405a)),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: amber,
        foregroundColor: const Color(0xff1b1304),
        textStyle: const TextStyle(
          fontFamily: 'SpaceGrotesk',
          fontWeight: FontWeight.w700,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
        minimumSize: const Size(0, 42),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: scheme.onSurface,
        side: const BorderSide(color: Color(0xff70532d)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
      ),
    ),
    chipTheme: base.chipTheme.copyWith(
      selectedColor: amber,
      side: const BorderSide(color: Color(0xff36405a)),
      showCheckmark: false,
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: surface,
      indicatorColor: amber.withValues(alpha: .13),
      labelTextStyle: WidgetStateProperty.resolveWith(
        (states) => TextStyle(
          fontSize: 11,
          fontFamily: 'SpaceGrotesk',
          color: states.contains(WidgetState.selected) ? amber : muted,
          fontWeight: FontWeight.w700,
        ),
      ),
      iconTheme: WidgetStateProperty.resolveWith(
        (states) => IconThemeData(
          color: states.contains(WidgetState.selected) ? amber : muted,
        ),
      ),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: amber,
      linearTrackColor: background,
    ),
  );
}

class CitadelPanel extends StatelessWidget {
  const CitadelPanel({
    super.key,
    required this.child,
    this.color,
    this.padding = 16,
  });
  final Widget child;
  final Color? color;
  final double padding;
  @override
  Widget build(BuildContext context) => Container(
    padding: EdgeInsets.all(padding),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surface,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(
        color: color?.withValues(alpha: .24) ?? const Color(0xff30384b),
      ),
      boxShadow: [
        BoxShadow(
          color: (color ?? Colors.black).withValues(alpha: .08),
          blurRadius: 16,
          offset: const Offset(0, 4),
        ),
      ],
    ),
    child: Material(type: MaterialType.transparency, child: child),
  );
}

class CitadelLabel extends StatelessWidget {
  const CitadelLabel(this.text, {super.key, this.color = amber});
  final String text;
  final Color color;
  @override
  Widget build(BuildContext context) => Text(
    text.toUpperCase(),
    style: TextStyle(
      color: color,
      fontSize: 10,
      fontFamily: 'SpaceGrotesk',
      fontWeight: FontWeight.w700,
      letterSpacing: .7,
    ),
  );
}
