import 'package:shared_preferences/shared_preferences.dart';
import '../models/game_model.dart';

// ─────────────────────────────────────────────────────────────────────────────
// LOCALIZATION
// ─────────────────────────────────────────────────────────────────────────────
enum AppLang { he, en }

class L {
  final AppLang lang;
  const L(this.lang);
  bool get isHe => lang == AppLang.he;

  static const String _langPrefKey = 'appLang';

  static Future<void> saveLang(AppLang lang) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_langPrefKey, lang.name);
  }

  static Future<AppLang> loadLang() async {
    final prefs = await SharedPreferences.getInstance();
    final s = prefs.getString(_langPrefKey);
    return s == 'he' ? AppLang.he : AppLang.en;
  }

  String get phaseInstructFill => isHe ? 'הנח קלף' : 'Place a Card';
  String get phaseInstructClear =>
      isHe ? 'מצא זוגות של 11' : 'Find pairs of 11';
  String get langToggleLabel => isHe ? 'English' : 'עברית';

  String get tooltipPeekAvail => isHe ? 'הצצה (חד-פעמי)' : 'Peek (one-time)';
  String get tooltipPeekUsed => isHe ? 'הצצה נוצלה' : 'Peek used';
  String get tooltipMoveAvail => isHe ? 'הזזה (חד-פעמי)' : 'Move (one-time)';
  String get tooltipMoveCancl => isHe ? 'בטל הזזה' : 'Cancel move';
  String get tooltipMoveUsed => isHe ? 'הזזה נוצלה' : 'Move used';
  String get tooltipUndo => isHe ? 'בטל' : 'Undo';
  String get tooltipRedo => isHe ? 'חזור' : 'Redo';
  String get tooltipNewGame => isHe ? 'משחק חדש' : 'New Game';
  String get tooltipRules => isHe ? 'חוקים' : 'Rules';
  String get tooltipMore => isHe ? 'עוד' : 'More';
  String get tooltipHome => isHe ? 'תפריט ראשי' : 'Main menu';
  String get tooltipDailyGoal => isHe ? 'יעד יומי' : 'Daily goal';

  String get menuDebugShow => isHe ? 'הצג כלי פיתוח' : 'Show debug tools';
  String get menuDebugHide => isHe ? 'הסתר כלי פיתוח' : 'Hide debug tools';

  String get labelDeck => isHe ? 'חפיסה' : 'Deck';
  String get labelClearPile => isHe ? 'ניקוי' : 'Clear';
  String get labelCurrent => isHe ? 'נוכחי' : 'Current';
  String get labelHidden => isHe ? 'מוסתר' : 'Hidden';
  String get labelEmpty => isHe ? 'ריק' : 'Empty';
  String peekNext(String card) => isHe ? 'הבא: $card' : 'Next: $card';

  String get dbgPhase => isHe ? 'פאזה' : 'Phase';
  String get dbgCurrent => isHe ? 'נוכחי' : 'Current';
  String get dbgDeck => isHe ? 'חפיסה' : 'Deck';
  String get dbgRoyals => isHe ? 'מלוכה' : 'Royals';
  String get dbgGodMode => isHe ? 'God Mode' : 'God Mode';
  String get dbgInstantWin => isHe ? 'Instant Win ⚡' : 'Instant Win ⚡';

  String get snackIllegal => isHe ? 'מהלך לא חוקי' : 'Illegal move';
  String get snackIllegalMove => isHe ? 'מהלך הזזה לא חוקי' : 'Illegal move';

  String get movePick => isHe ? 'בחר קלף להזזה' : 'Pick a card to move';
  String get moveDrop => isHe ? 'בחר תא יעד ריק' : 'Pick an empty target';

  // Scoring Text
  String get uiScore => isHe ? 'ניקוד' : 'SCORE';
  String get uiTime => isHe ? 'זמן' : 'TIME';
  String get winBaseScore => isHe ? 'ניקוד בסיס:' : 'Base Score:';
  String get winBonus => isHe ? 'בונוס ניצחון:' : 'Win Bonus:';
  String get speedBonus => isHe ? 'בונוס מהירות:' : 'Speed Bonus:';
  String get effBonus => isHe ? 'יעילות מסגרת:' : 'Frame Efficiency:';
  String get totalScore => isHe ? 'סך הכל ניקוד' : 'TOTAL SCORE';

  String get winTitle => isHe ? '!ניצחת' : 'ROYAL WINNER!';
  String get winSub =>
      isHe ? '.המסגרת המלכותית הושלמה' : 'The Royal Frame is complete.';
  String get winBtn => isHe ? 'משחק חדש' : 'New Game';
  String get lossTitle => isHe ? 'Game Over' : 'GAME OVER';

  String get lossSub =>
      isHe ? 'לא נותרו מהלכים חוקיים.' : 'No legal moves remaining.';

  String get lossBtn => isHe ? 'נסה שוב' : 'Try Again';
  String lossCardsLeft(int n) =>
      isHe ? 'קלפים שנשארו בחפיסה: $n' : 'Cards remaining in deck: $n';
  String get lossSuddenDeath =>
      isHe ? 'מהלך אחד שגוי — וזהו.' : 'One wrong move — and that\'s it.';
  String difficultyMultiplier(String m) =>
      isHe ? 'רמת קושי ×$m' : 'Difficulty ×$m';

  // Duel HUD & result screen
  String get duelYou => isHe ? 'אתה' : 'YOU';
  String get duelOpponentFallback => isHe ? 'יריב' : 'Opponent';
  String get duelGuestFallback => isHe ? 'אורח' : 'Guest';
  String get duelYouWinBanner =>
      isHe ? '  ניצחת בדו-קרב!' : '  You Win the Duel!';
  String get duelOpponentWinsBanner =>
      isHe ? '  היריב ניצח בדו-קרב' : '  Opponent Wins the Duel';
  String get duelOpponentReady =>
      isHe ? 'היריב מוכן!' : 'Opponent is ready!';
  String get duelWaitingOpponent =>
      isHe ? 'ממתין ליריב...' : 'Waiting for opponent...';
  String get btnPlayAgain => isHe ? 'שחק שוב' : 'Play Again';
  String get duelOpponentCaps => isHe ? 'יריב' : 'OPPONENT';
  String get duelResultWinTitle =>
      isHe ? '👑 ניצחת בדו-קרב!' : '👑 You Win the Duel!';
  String get duelResultLossTitle =>
      isHe ? '💀 היריב ניצח' : '💀 Opponent Wins';
  String get duelSyncFailed => isHe
      ? 'בעיית חיבור — ייתכן שתוצאת הדו-קרב לא נשמרה.'
      : 'Connection issue — your duel result may not be recorded.';

  // Cosmetics shop
  String get cosmeticsTitle => isHe ? 'גלריית ערכות' : 'Theme Gallery';
  String get cosmeticsCardBacks => isHe ? 'גבי קלפים' : 'Card Backs';
  String get cosmeticsBoardColors => isHe ? 'צבעי לוח' : 'Board Colors';

  // Welcome screen
  String get btnPlayAsGuest => isHe ? 'שחק כאורח' : 'Play as Guest';
  String get btnContinueGoogle =>
      isHe ? 'המשך עם Google' : 'Continue with Google';
  String get btnContinuePhone =>
      isHe ? 'המשך עם טלפון' : 'Continue with Phone';
  String get errEnterName => isHe ? 'נא להזין שם' : 'Please enter a name';

  String get rulesTitle => isHe ? 'חוקים' : 'Rules';
  String get rulesBody => isHe
      ? 'קלפי מלוכה (מלך, מלכה, נסיך) חובה למקם במסגרת החיצונית בלבד. '
            'קלפי מספרים אפשר לשים בכל מקום פנוי. '
            'כשהלוח מתמלא, יש למצוא ולפנות זוגות של קלפי מספרים שסכומם 11. '
            'חובה לפנות את כל הקלפים האפשריים לפני שחוזרים להניח שוב! '
            'הניצחון מוכרז כשהמסגרת מלאה במלוכה ולא נותר מהלך חוקי. '
            'אם יש זוגות 11 לפנות, ממשיכים לפנות אותם לפני סיום המשחק. '
            'המטרה: למלא את כל 12 משבצות המסגרת בקלפי מלוכה. תהנו!'
      : 'King, Queen, Jack must go in the outer frame. '
            'Match pairs of numbers that sum to 11 to clear space. '
            'You must clear all possible pairs before you can proceed to place cards again! '
            'Win is declared when the frame holds 12 royals and no legal action remains. '
            'If any 11-pairs remain, clear them before the game can end. '
            'Fill the frame to win. Enjoy!';
  String get btnReplayTutorial => isHe ? 'מדריך אינטראקטיבי' : 'Interactive Tutorial';
  // Main Menu & Leaderboard Strings
  String get menuResume => isHe ? 'המשך משחק' : 'Resume Game';
  String get menuNewGame => isHe ? 'משחק חדש' : 'New Game';
  String get menuLeaderboard => isHe ? 'טבלת מובילים' : 'Leaderboard';
  String get menuTutorial => isHe ? 'הדרכה' : 'Tutorial';
  String get menuDuelMode => isHe ? 'מצב דו-קרב' : 'Duel Mode';
  String get menuChangePlayer => isHe ? 'החלף שחקן' : 'Change Player';
  // Welcome Screen Strings
  String get welcomeHint => isHe ? 'הזן את השם שלך' : 'Enter your name';
  String get welcomeBtn => isHe ? 'התחל לשחק' : 'Start Playing';
  String get welcomeTagline =>
      isHe ? 'אתגר הקלפים המלכותי' : 'The royal card challenge';

  // Share strings
  String shareVictory(String time, int score, String link) => isHe
      ? 'ניצחתי את Royal Frame! זמן: $time, ניקוד: $score. נסו לעקוף אותי... שחקו עכשיו: $link'
      : 'I just won Royal Frame! Time: $time, Score: $score. Think you can beat me? Play now: $link';

  String shareGameOver(int score, String link) => isHe
      ? 'השגתי $score נקודות ב-Royal Frame! נראה אם תצליחו לעקוף אותי... שחקו עכשיו: $link'
      : 'I scored $score points in Royal Frame! Think you can beat me? Play now: $link';

  String get shareVictoryBtn => isHe ? 'שתף ניצחון' : 'Share Victory';
  String get shareScoreBtn   => isHe ? 'שתף ניקוד' : 'Share Score';

  String get dialogHomeTitle => isHe ? 'חזרה לתפריט' : 'Return to Menu';
  String get dialogHomeBody => isHe
      ? 'המשחק ימתין לך ברקע. האם להמשיך?'
      : 'The game will pause and wait in the background. Return to menu?';
  String get btnYes => isHe ? 'כן' : 'Yes';
  String get btnNo => isHe ? 'לא' : 'No';

  String get tabHighScore => isHe ? 'שיא (משחק בודד)' : 'High Score';
  String get tabTotalScore => isHe ? 'סך הכל נקודות' : 'Total Score';
  String welcomeBack(String name) =>
      isHe ? 'ברוך שובך, $name' : 'Welcome back, $name';

  String slotLabel(SlotType t) {
    if (isHe) {
      return switch (t) {
        SlotType.kingCorner => 'מלך',
        SlotType.queenEdge => 'מלכה',
        SlotType.jackEdge => 'נסיך',
        SlotType.innerDump => '',
      };
    }
    return switch (t) {
      SlotType.kingCorner => 'K',
      SlotType.queenEdge => 'Q',
      SlotType.jackEdge => 'J',
      SlotType.innerDump => '',
    };
  }
}
