import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart'; // בשביל לזהות שאנחנו על כרום

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;

  User? get currentUser => _auth.currentUser;

  Future<UserCredential?> signInAnonymously(String displayName) async {
    try {
      UserCredential credential = await _auth.signInAnonymously();
      await credential.user?.updateDisplayName(displayName);
      return credential;
    } catch (e) {
      print("Error signing in anonymously: $e");
      return null;
    }
  }

  Future<UserCredential?> signInWithGoogle() async {
    try {
      if (kIsWeb) {
        // הקסם של כרום: פופאפ מובנה של פיירבייס בלי ספריות חיצוניות!
        GoogleAuthProvider googleProvider = GoogleAuthProvider();
        return await _auth.signInWithPopup(googleProvider);
      } else {
        // כרגע אנחנו בודקים על כרום, נטפל באנדרואיד בנפרד בהמשך
        print("Android Google Login is pending");
        return null;
      }
    } catch (e) {
      print("Error during Google Sign In: $e");
      return null;
    }
  }

  Future<void> signOut() async {
    try {
      await _auth.signOut();
    } catch (e) {
      print("Error signing out: $e");
    }
  }
}