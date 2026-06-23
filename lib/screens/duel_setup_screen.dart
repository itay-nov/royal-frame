import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme_constants.dart';
import '../services/duel_service.dart';
import '../utils/localization.dart';
import 'board_screen.dart';

// ─────────────────────────────────────────────────────────────────────────────
// DUEL SETUP SCREEN — host or join a 1v1 duel via a 6-char code
// ─────────────────────────────────────────────────────────────────────────────
class DuelSetupScreen extends StatefulWidget {
  const DuelSetupScreen({super.key, required this.lang});
  final AppLang lang;

  @override
  State<DuelSetupScreen> createState() => _DuelSetupScreenState();
}

class _DuelSetupScreenState extends State<DuelSetupScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabCtrl;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isHe = widget.lang == AppLang.he;
    return Scaffold(
      backgroundColor: kBurgundy,
      appBar: AppBar(
        backgroundColor: kBurgundyLight,
        title: Text(
          isHe ? 'מצב דו-קרב' : 'Duel Mode',
          style: const TextStyle(
            color: kGold,
            fontWeight: FontWeight.w900,
            letterSpacing: 1.5,
          ),
        ),
        iconTheme: const IconThemeData(color: kGold),
        bottom: TabBar(
          controller: _tabCtrl,
          indicatorColor: kGold,
          labelColor: kGold,
          unselectedLabelColor: kGoldDark,
          tabs: [
            Tab(icon: const Icon(Icons.add_circle_outline), text: isHe ? 'מארח' : 'Host'),
            Tab(icon: const Icon(Icons.login),              text: isHe ? 'הצטרף' : 'Join'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabCtrl,
        children: [
          _HostTab(lang: widget.lang),
          _JoinTab(lang: widget.lang),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// HOST TAB — creates a duel and waits for opponent
// ─────────────────────────────────────────────────────────────────────────────
class _HostTab extends StatefulWidget {
  const _HostTab({required this.lang});
  final AppLang lang;

  @override
  State<_HostTab> createState() => _HostTabState();
}

class _HostTabState extends State<_HostTab> {
  DuelSession? _session;
  StreamSubscription<DuelSession?>? _sub;
  bool _creating = false;
  String? _error;

  bool get _isHe => widget.lang == AppLang.he;

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  Future<void> _createDuel() async {
    setState(() {
      _creating = true;
      _error = null;
    });
    try {
      final session = await DuelService.createDuel();
      if (!mounted) return;
      setState(() {
        _session = session;
        _creating = false;
      });
      _sub = DuelService.watchDuel(session.duelId).listen((updated) {
        if (!mounted) return;
        if (updated == null) return;
        if (updated.isActive && _session?.isWaiting == true) {
          setState(() => _session = updated);
          _launchGame(updated);
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
        _creating = false;
      });
    }
  }

  void _launchGame(DuelSession session) {
    _sub?.cancel();
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => BoardScreen(
          duelSession: session,
          isHost: true,
          initialLang: widget.lang,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.sports_kabaddi, color: kGold, size: 56),
            const SizedBox(height: 20),
            Text(
              _isHe ? 'אתגר חבר' : 'Challenge a Friend',
              style: const TextStyle(
                color: kGold,
                fontSize: 22,
                fontWeight: FontWeight.w900,
                letterSpacing: 1.5,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _isHe
                  ? 'צור דו-קרב ושתף את הקוד. שני השחקנים מתחילים עם אותה חפיסה.'
                  : 'Create a duel and share your code. Both players start with the same deck.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white60, fontSize: 13, height: 1.5),
            ),
            const SizedBox(height: 32),

            if (_session == null) ...[
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Text(
                    _error!,
                    style: const TextStyle(color: Colors.redAccent, fontSize: 13),
                    textAlign: TextAlign.center,
                  ),
                ),
              SizedBox(
                width: 220,
                height: 50,
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: kBurgundyLight,
                    foregroundColor: kGold,
                    side: const BorderSide(color: kGold),
                  ),
                  onPressed: _creating ? null : _createDuel,
                  icon: _creating
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            color: kGold, strokeWidth: 2),
                        )
                      : const Icon(Icons.add),
                  label: Text(_creating
                      ? (_isHe ? 'יוצר...' : 'Creating...')
                      : (_isHe ? 'צור דו-קרב' : 'Create Duel')),
                ),
              ),
            ] else ...[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
                decoration: BoxDecoration(
                  color: kBurgundyLight,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: kGold, width: 1.8),
                  boxShadow: [
                    BoxShadow(
                      color: kGold.withOpacity(0.25),
                      blurRadius: 20,
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    Text(
                      _isHe ? 'הקוד שלך' : 'Your Code',
                      style: const TextStyle(
                        color: kGoldLight,
                        fontSize: 13,
                        letterSpacing: 1.2,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      _session!.code,
                      style: const TextStyle(
                        color: kGold,
                        fontSize: 40,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 8,
                      ),
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: kGoldLight,
                        side: const BorderSide(color: kGoldDark),
                      ),
                      onPressed: () {
                        Clipboard.setData(
                          ClipboardData(text: _session!.code),
                        );
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(_isHe ? 'הקוד הועתק!' : 'Code copied!'),
                            duration: const Duration(seconds: 2),
                          ),
                        );
                      },
                      icon: const Icon(Icons.copy, size: 16),
                      label: Text(_isHe ? 'העתק קוד' : 'Copy Code'),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            color: kGoldLight,
                            strokeWidth: 2,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Text(
                          _isHe ? 'ממתין ליריב...' : 'Waiting for opponent...',
                          style: const TextStyle(
                            color: Colors.white60,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// JOIN TAB — enter a code to join an existing duel
// ─────────────────────────────────────────────────────────────────────────────
class _JoinTab extends StatefulWidget {
  const _JoinTab({required this.lang});
  final AppLang lang;

  @override
  State<_JoinTab> createState() => _JoinTabState();
}

class _JoinTabState extends State<_JoinTab> {
  final _ctrl = TextEditingController();
  bool _joining = false;
  String? _error;

  bool get _isHe => widget.lang == AppLang.he;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _joinDuel() async {
    final code = _ctrl.text.trim().toUpperCase();
    if (code.length < 6) {
      setState(() => _error = _isHe
          ? 'אנא הזן קוד בן 6 תווים.'
          : 'Please enter a 6-character code.');
      return;
    }
    setState(() {
      _joining = true;
      _error = null;
    });
    try {
      final session = await DuelService.joinDuel(code);
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => BoardScreen(
            duelSession: session,
            isHost: false,
            initialLang: widget.lang,
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
        _joining = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.login, color: kGold, size: 56),
            const SizedBox(height: 20),
            Text(
              _isHe ? 'הצטרף לדו-קרב' : 'Join a Duel',
              style: const TextStyle(
                color: kGold,
                fontSize: 22,
                fontWeight: FontWeight.w900,
                letterSpacing: 1.5,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _isHe
                  ? 'הזן את קוד 6 התווים ששיתף איתך היריב.'
                  : 'Enter the 6-character code your opponent shared with you.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white60, fontSize: 13, height: 1.5),
            ),
            const SizedBox(height: 32),

            TextField(
              controller: _ctrl,
              textCapitalization: TextCapitalization.characters,
              inputFormatters: [
                UpperCaseTextFormatter(),
              ],
              maxLength: 6,
              textAlign: TextAlign.center,
              onChanged: (value) {
                if (value.trim().length == 6 && !_joining) {
                  _joinDuel();
                }
              },
              style: const TextStyle(
                color: kGold,
                fontSize: 28,
                fontWeight: FontWeight.w900,
                letterSpacing: 8,
              ),
              decoration: InputDecoration(
                counterText: '',
                hintText: 'XXXXXX',
                hintStyle: TextStyle(
                  color: kGoldDark.withOpacity(0.5),
                  fontSize: 28,
                  letterSpacing: 8,
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: kGoldDark, width: 1.5),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: kGold, width: 2),
                ),
                filled: true,
                fillColor: kBurgundyLight,
              ),
              onSubmitted: (_) => _joinDuel(),
            ),

            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(
                  _error!,
                  style: const TextStyle(
                      color: Colors.redAccent, fontSize: 13),
                  textAlign: TextAlign.center,
                ),
              ),

            const SizedBox(height: 24),
            SizedBox(
              width: 220,
              height: 50,
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: kBurgundyLight,
                  foregroundColor: kGold,
                  side: const BorderSide(color: kGold),
                ),
                onPressed: _joining ? null : _joinDuel,
                icon: _joining
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            color: kGold, strokeWidth: 2),
                      )
                    : const Icon(Icons.play_arrow),
                label: Text(_joining
                    ? (_isHe ? 'מצטרף...' : 'Joining...')
                    : (_isHe ? 'הצטרף' : 'Join Duel')),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class UpperCaseTextFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue, TextEditingValue newValue) {
    return newValue.copyWith(text: newValue.text.toUpperCase());
  }
}
