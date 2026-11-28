import 'package:auto_route/auto_route.dart';
import 'package:flutter/widgets.dart';
import 'package:sail_ui/sail_ui.dart';

@RoutePage()
class ConsolePage extends StatefulWidget {
  const ConsolePage({super.key});

  @override
  State<ConsolePage> createState() => _ConsolePageState();
}

class _ConsolePageState extends State<ConsolePage> {
  @override
  Widget build(BuildContext context) {
    final theme = SailTheme.of(context);
    return QtPage(
      child: DecoratedBox(
        position: DecorationPosition.foreground,
        decoration: BoxDecoration(
          border: Border.all(color: theme.colors.border),
          borderRadius: theme.chrome.radiusLarge,
        ),
        child: ClipRRect(borderRadius: theme.chrome.radiusLarge, child: const CLIConsoleView()),
      ),
    );
  }
}
