import 'package:nai_launcher/presentation/widgets/common/horizontal_action_strip.dart';
import 'package:flutter/material.dart';

import '../../../../core/platform/platform_capabilities.dart';
import '../../../../core/utils/localization_extension.dart';
import 'comfyui_settings_section.dart';
import '../../dlss/dlss_settings_section.dart';
import 'krita_bridge_settings_section.dart';
import 'pic_manager_settings_section.dart';
import 'prompt_assistant_settings_section.dart';
import '../widgets/settings_page_layout.dart';

/// 集成设置板块
///
/// 汇总平台支持的外部工具与本地增强集成。
/// 顶部子导航切换，一次只渲染一个面板，避免长滚动页。
class IntegrationsSettingsSection extends StatefulWidget {
  /// 测试注入用面板构造器；非 null 时必须恰好包含四个构造器。
  ///
  /// 生产环境保持 null，按平台能力提供面板。
  @visibleForTesting
  final List<WidgetBuilder>? panelBuilders;

  final bool initiallyShowDlss;

  const IntegrationsSettingsSection({
    super.key,
    this.panelBuilders,
    this.initiallyShowDlss = false,
  }) : assert(
         panelBuilders == null || panelBuilders.length == 4,
         'panelBuilders must contain exactly four builders.',
       );

  @override
  State<IntegrationsSettingsSection> createState() =>
      _IntegrationsSettingsSectionState();
}

class _IntegrationsSettingsSectionState
    extends State<IntegrationsSettingsSection> {
  late final PlatformCapabilities _capabilities = PlatformCapabilities.current;
  late int _selectedIndex = widget.initiallyShowDlss &&
          _capabilities.supportsDlssEnhancement
      ? _dlssIndex
      : 0;

  int get _dlssIndex {
    final showKrita =
        widget.panelBuilders != null || _capabilities.supportsKritaBridge;
    return showKrita ? 4 : 3;
  }

  @override
  void didUpdateWidget(covariant IntegrationsSettingsSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initiallyShowDlss &&
        !oldWidget.initiallyShowDlss &&
        _capabilities.supportsDlssEnhancement) {
      _selectedIndex = _dlssIndex;
    }
  }

  @override
  Widget build(BuildContext context) {
    final supportsComfyUi = _capabilities.supportsComfyUiIntegration;
    final showKrita =
        widget.panelBuilders != null || _capabilities.supportsKritaBridge;
    final showDlss =
        widget.panelBuilders == null && _capabilities.supportsDlssEnhancement;
    final baseBuilders =
        widget.panelBuilders ??
        <WidgetBuilder>[
          (_) => const PromptAssistantSettingsSection(),
          (_) => const ComfyUISettingsSection(),
          if (showKrita) (_) => const KritaBridgeSettingsSection(),
          (_) => const PicManagerSettingsSection(),
        ];
    final builders = <WidgetBuilder>[
      ...baseBuilders,
      if (showDlss) (_) => const DlssSettingsSection(),
    ];
    final labels = [
      context.l10n.settings_promptAssistant,
      'ComfyUI',
      if (showKrita) 'Krita',
      'Pic Manager',
      if (showDlss) 'DLSSNR',
    ];
    final selectedIndex = _selectedIndex.clamp(0, builders.length - 1);

    return SettingsPageLayout(
      title: context.l10n.settings_integrations,
      children: [
        HorizontalActionStrip(
          child: SegmentedButton<int>(
            segments: [
              for (var i = 0; i < labels.length; i++)
                ButtonSegment(
                  value: i,
                  enabled: i != 1 || supportsComfyUi,
                  tooltip: i == 1 && !supportsComfyUi
                      ? context.l10n.settings_comfyUiDesktopOnly
                      : null,
                  label: Text(labels[i]),
                ),
            ],
            selected: {selectedIndex},
            showSelectedIcon: false,
            onSelectionChanged: (selection) {
              final nextIndex = selection.first;
              if (nextIndex == 1 && !supportsComfyUi) return;
              setState(() => _selectedIndex = nextIndex);
            },
          ),
        ),
        builders[selectedIndex](context),
      ],
    );
  }
}
