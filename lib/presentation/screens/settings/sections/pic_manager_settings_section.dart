import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/utils/localization_extension.dart';
import '../../../providers/pic_manager_push_provider.dart';
import '../../../utils/pic_manager_localization.dart';
import '../../../widgets/common/app_toast.dart';
import '../widgets/settings_card.dart';

class PicManagerSettingsSection extends ConsumerStatefulWidget {
  const PicManagerSettingsSection({super.key});

  @override
  ConsumerState<PicManagerSettingsSection> createState() =>
      _PicManagerSettingsSectionState();
}

class _PicManagerSettingsSectionState
    extends ConsumerState<PicManagerSettingsSection> {
  final _baseUrlController = TextEditingController();
  final _tokenController = TextEditingController();
  bool _seeded = false;
  bool _allowInsecureHttp = false;
  bool _autoPushOnFavorite = false;
  bool _obscureToken = true;
  bool _saving = false;
  bool _testing = false;

  @override
  void dispose() {
    _baseUrlController.dispose();
    _tokenController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      await ref
          .read(picManagerSettingsProvider.notifier)
          .save(
            baseUrl: _baseUrlController.text,
            allowInsecureHttp: _allowInsecureHttp,
            autoPushOnFavorite: _autoPushOnFavorite,
            token: _tokenController.text,
          );
      _tokenController.clear();
      if (mounted) {
        FocusScope.of(context).unfocus();
        AppToast.success(context, context.l10n.picManager_saveSuccess);
      }
    } catch (error) {
      if (mounted) {
        AppToast.error(context, localizePicManagerError(context.l10n, error));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _testConnection() async {
    if (_testing) return;
    setState(() => _testing = true);
    try {
      await ref
          .read(picManagerSettingsProvider.notifier)
          .testConnection(
            baseUrl: _baseUrlController.text,
            allowInsecureHttp: _allowInsecureHttp,
            token: _tokenController.text,
          );
      if (mounted) {
        AppToast.success(context, context.l10n.picManager_connectionSuccess);
      }
    } catch (error) {
      if (mounted) {
        AppToast.error(context, localizePicManagerError(context.l10n, error));
      }
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  Future<void> _clearToken() async {
    try {
      await ref.read(picManagerSettingsProvider.notifier).clearToken();
      _tokenController.clear();
      if (mounted) {
        AppToast.success(context, context.l10n.picManager_tokenCleared);
      }
    } catch (error) {
      if (mounted) {
        AppToast.error(context, localizePicManagerError(context.l10n, error));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final asyncConfig = ref.watch(picManagerSettingsProvider);
    final config = asyncConfig.valueOrNull;
    if (!_seeded && config != null) {
      _baseUrlController.text = config.baseUrl;
      _allowInsecureHttp = config.allowInsecureHttp;
      _autoPushOnFavorite = config.autoPushOnFavorite;
      _seeded = true;
    }
    final hasToken = config?.hasToken == true;
    final canSubmit =
        _baseUrlController.text.trim().isNotEmpty &&
        (hasToken || _tokenController.text.trim().isNotEmpty);

    return SettingsCard(
      title: 'Pic Manager',
      description: context.l10n.picManager_description,
      icon: Icons.cloud_upload_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _baseUrlController,
            keyboardType: TextInputType.url,
            autocorrect: false,
            enableSuggestions: false,
            textInputAction: TextInputAction.next,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              labelText: context.l10n.picManager_apiUrl,
              hintText: context.l10n.picManager_apiUrlHint,
              prefixIcon: const Icon(Icons.link),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _tokenController,
            obscureText: _obscureToken,
            autocorrect: false,
            enableSuggestions: false,
            textInputAction: TextInputAction.done,
            onChanged: (_) => setState(() {}),
            onSubmitted: (_) {
              if (canSubmit) unawaited(_save());
            },
            decoration: InputDecoration(
              labelText: 'Token',
              helperText: hasToken
                  ? context.l10n.picManager_tokenSavedHint
                  : null,
              prefixIcon: const Icon(Icons.key_outlined),
              suffixIcon: IconButton(
                onPressed: () => setState(() => _obscureToken = !_obscureToken),
                icon: Icon(
                  _obscureToken ? Icons.visibility : Icons.visibility_off,
                ),
              ),
            ),
          ),
          if (hasToken)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: _clearToken,
                icon: const Icon(Icons.key_off_outlined),
                label: Text(context.l10n.picManager_clearToken),
              ),
            ),
          const Divider(height: 24),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            secondary: const Icon(Icons.lock_open_outlined),
            title: Text(context.l10n.picManager_allowInsecureHttp),
            subtitle: Text(context.l10n.picManager_allowInsecureHttpHint),
            value: _allowInsecureHttp,
            onChanged: (value) => setState(() => _allowInsecureHttp = value),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            secondary: const Icon(Icons.favorite_outline),
            title: Text(context.l10n.picManager_autoPushFavorite),
            subtitle: Text(context.l10n.picManager_autoPushFavoriteHint),
            value: _autoPushOnFavorite,
            onChanged: (value) => setState(() => _autoPushOnFavorite = value),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.sell_outlined),
            title: Text(context.l10n.picManager_source),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            alignment: WrapAlignment.end,
            children: [
              OutlinedButton.icon(
                onPressed: canSubmit && !_testing ? _testConnection : null,
                icon: _testing
                    ? const SizedBox.square(
                        dimension: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.wifi_tethering_outlined),
                label: Text(context.l10n.settings_testConnection),
              ),
              FilledButton.icon(
                onPressed: canSubmit && !_saving ? _save : null,
                icon: _saving
                    ? const SizedBox.square(
                        dimension: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.save_outlined),
                label: Text(context.l10n.common_save),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
