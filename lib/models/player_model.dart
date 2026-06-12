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
    return PlayerModel(
      uid: map['uid'],
      displayName: map['displayName'],
      highScore: map['highScore'] ?? 0,
      totalScore: map['totalScore'] ?? 0,
      wins: map['wins'] ?? 0,
      totalGames: map['totalGames'] ?? 0,
      lastUpdated: map['lastUpdated'].toDate(),
    );
  }
}
