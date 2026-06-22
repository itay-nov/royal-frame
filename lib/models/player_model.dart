class PlayerModel {
  final String uid;
  final String displayName;
  int highScore;
  int totalScore;
  int wins;
  int totalGames;
  DateTime lastUpdated;

  PlayerModel({
    required this.uid,
    required this.displayName,
    this.highScore = 0,
    this.totalScore = 0,
    this.wins = 0,
    this.totalGames = 0,
    required this.lastUpdated,
  });

  // הפיכה של הנתונים למפה (כדי לשלוח לפיירבייס)
  Map<String, dynamic> toMap() {
    return {
      'uid': uid,
      'displayName': displayName,
      'highScore': highScore,
      'totalScore': totalScore,
      'wins': wins,
      'totalGames': totalGames,
      'lastUpdated': lastUpdated,
    };
  }

  // יצירת אובייקט מתוך נתונים שהגיעו מהענן
  factory PlayerModel.fromMap(Map<String, dynamic> map) {
    final ts = map['lastUpdated'];
    return PlayerModel(
      uid: map['uid'] as String? ?? '',
      displayName: map['displayName'] as String? ?? 'Player',
      highScore: (map['highScore'] as num?)?.toInt() ?? 0,
      totalScore: (map['totalScore'] as num?)?.toInt() ?? 0,
      wins: (map['wins'] as num?)?.toInt() ?? 0,
      totalGames: (map['totalGames'] as num?)?.toInt() ?? 0,
      lastUpdated: ts != null ? ts.toDate() : DateTime(2020),
    );
  }
}
