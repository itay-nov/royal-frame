import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/update_service.dart';
import '../theme_constants.dart';
import '../utils/localization.dart';

typedef UpdateRequiredCheck = Future<bool> Function();
typedef PlayStoreLauncher = Future<bool> Function();

final Uri _playStoreUri = Uri.parse(
  'https://play.google.com/store/apps/details?id=com.itay.royalframegame',
);

Future<bool> _openPlayStore() {
  return launchUrl(_playStoreUri, mode: LaunchMode.externalApplication);
}

class UpdateRequiredScreen extends StatefulWidget {
  const UpdateRequiredScreen({
    super.key,
    required this.lang,
    required this.onUpdateSatisfied,
    this.checkUpdateRequired = UpdateService.isUpdateRequired,
    this.openPlayStore = _openPlayStore,
  });

  final AppLang lang;
  final VoidCallback onUpdateSatisfied;
  final UpdateRequiredCheck checkUpdateRequired;
  final PlayStoreLauncher openPlayStore;

  @override
  State<UpdateRequiredScreen> createState() => _UpdateRequiredScreenState();
}

class _UpdateRequiredScreenState extends State<UpdateRequiredScreen>
    with WidgetsBindingObserver {
  bool _waitingForStoreReturn = false;
  bool _checking = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _waitingForStoreReturn) {
      _waitingForStoreReturn = false;
      _recheckInstalledBuild();
    }
  }

  Future<void> _launchPlayStore() async {
    if (_waitingForStoreReturn) return;
    setState(() => _waitingForStoreReturn = true);

    try {
      final opened = await widget.openPlayStore();
      if (!opened && mounted) {
        setState(() => _waitingForStoreReturn = false);
      }
    } catch (error) {
      debugPrint('[UpdateRequiredScreen] Could not open Google Play: $error');
      if (mounted) setState(() => _waitingForStoreReturn = false);
    }
  }

  Future<void> _recheckInstalledBuild() async {
    if (_checking) return;
    setState(() => _checking = true);

    final stillBlocked = await widget.checkUpdateRequired();
    if (!mounted) return;

    if (stillBlocked) {
      setState(() => _checking = false);
    } else {
      setState(() => _checking = false);
      widget.onUpdateSatisfied();
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = L(widget.lang);

    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: kBurgundy,
        body: SafeArea(
          child: Directionality(
            textDirection: l.isHe ? TextDirection.rtl : TextDirection.ltr,
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('👑', style: TextStyle(fontSize: 72)),
                    const SizedBox(height: 16),
                    const Text(
                      'ROYAL FRAME',
                      style: TextStyle(
                        color: kGold,
                        fontSize: 28,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 3,
                      ),
                    ),
                    const SizedBox(height: 32),
                    Text(
                      l.updateRequiredMessage,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: kGoldLight,
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 24),
                    SizedBox(
                      width: 220,
                      height: 50,
                      child: FilledButton.icon(
                        onPressed: _checking || _waitingForStoreReturn
                            ? null
                            : _launchPlayStore,
                        icon: const Icon(Icons.system_update),
                        label: Text(l.btnUpdate),
                      ),
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
