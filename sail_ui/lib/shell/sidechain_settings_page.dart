import 'package:auto_route/auto_route.dart';
import 'package:flutter/widgets.dart';
import 'package:get_it/get_it.dart';
import 'package:sail_ui/sail_ui.dart';
import 'package:sail_ui/shell/sidechain_module.dart';

@RoutePage()
class SidechainSettingsPage extends StatefulWidget {
  const SidechainSettingsPage({super.key});

  static SidechainSettingsPageState? _currentState;
  static int? _pendingSection;

  static void setSection(int index) {
    if (_currentState != null) {
      _currentState!.setSelectedIndex(index);
    } else {
      _pendingSection = index;
    }
  }

  @override
  State<SidechainSettingsPage> createState() => SidechainSettingsPageState();
}

class SidechainSettingsPageState extends State<SidechainSettingsPage> {
  static const _sectionCount = 3;

  late int _selectedIndex;

  @override
  void initState() {
    super.initState();
    SidechainSettingsPage._currentState = this;
    final pending = SidechainSettingsPage._pendingSection;
    SidechainSettingsPage._pendingSection = null;
    _selectedIndex = (pending ?? 0).clamp(0, _sectionCount - 1);
  }

  @override
  void dispose() {
    if (SidechainSettingsPage._currentState == this) {
      SidechainSettingsPage._currentState = null;
    }
    super.dispose();
  }

  void setSelectedIndex(int index) {
    if (index >= 0 && index < _sectionCount) {
      setState(() {
        _selectedIndex = index;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final module = GetIt.I.get<SidechainModule>();
    final version = module.version;

    final sections = [
      SailSettingsSection(label: 'Appearance', builder: (_) => const SettingsAppearance()),
      SailSettingsSection(
        label: 'Reset',
        builder: (_) => SettingsReset(binary: module.chain, appName: module.fullName),
      ),
      SailSettingsSection(
        label: 'About',
        builder: (_) => SettingsInfo(
          appName: module.fullName,
          versionString: version.versionString,
          buildDate: version.buildDate,
          commitFull: version.commitFull,
          applicationName: version.appName,
        ),
      ),
    ];
    final subtitle = 'Manage your ${module.appName} settings';

    if (SailTheme.of(context).isBitwindowV2 && !SailStyleValues.phoneLayout(context)) {
      return ChainSettingsCard(
        subtitle: subtitle,
        sections: sections,
        selectedIndex: _selectedIndex,
        onSectionSelected: setSelectedIndex,
      );
    }
    return SailSettingsScaffold(
      subtitle: subtitle,
      selectedIndex: _selectedIndex,
      onSectionSelected: setSelectedIndex,
      sections: sections,
    );
  }
}

/// The chain settings in one card: the title, a segmented control, and the selected section.
class ChainSettingsCard extends StatelessWidget {
  final String subtitle;
  final List<SailSettingsSection> sections;
  final int selectedIndex;
  final ValueChanged<int> onSectionSelected;

  const ChainSettingsCard({
    super.key,
    required this.subtitle,
    required this.sections,
    required this.selectedIndex,
    required this.onSectionSelected,
  });

  @override
  Widget build(BuildContext context) {
    final index = selectedIndex.clamp(0, sections.length - 1);
    return QtPage(
      child: Align(
        alignment: Alignment.topLeft,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: SailCard(
            title: 'Settings',
            subtitle: subtitle,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SailSpacing(SailStyleValues.padding08),
                SailSegments(
                  labels: [for (final section in sections) section.label],
                  activeIndex: index,
                  onSelect: onSectionSelected,
                ),
                const SailSpacing(SailStyleValues.padding16),
                Flexible(child: sections[index].builder(context)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
