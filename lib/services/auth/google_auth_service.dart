import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../../core/bootstrap/firebase_bootstrap.dart';

/// Thrown when the user closes the Google account picker.
class GoogleSignInCancelled implements Exception {
  const GoogleSignInCancelled();
}

/// Google account → Firebase Auth → Firebase ID token for our backend
/// (`POST /auth/google`). The backend never sees Google credentials.
class GoogleAuthService {
  GoogleAuthService();

  Future<void>? _init;

  Future<void> _ensureInit() => _init ??= () async {
    if (!await FirebaseBootstrap.ensureInitialized()) {
      throw StateError('Google sign-in is not available on this build.');
    }
    // serverClientId comes from google-services.json (default_web_client_id).
    await GoogleSignIn.instance.initialize();
  }();

  /// Shows the Google account picker and returns a fresh Firebase ID token.
  Future<String> signIn() async {
    await _ensureInit();
    final GoogleSignInAccount account;
    try {
      account = await GoogleSignIn.instance.authenticate();
    } on GoogleSignInException catch (e) {
      if (e.code == GoogleSignInExceptionCode.canceled) {
        throw const GoogleSignInCancelled();
      }
      rethrow;
    }
    final googleIdToken = account.authentication.idToken;
    if (googleIdToken == null) {
      throw StateError('Google did not return an ID token.');
    }
    final cred = await FirebaseAuth.instance.signInWithCredential(
      GoogleAuthProvider.credential(idToken: googleIdToken),
    );
    final token = await cred.user?.getIdToken();
    if (token == null) throw StateError('Firebase sign-in failed.');
    return token;
  }

  /// ID token of the user already signed in to Firebase (refreshed if needed).
  Future<String?> currentIdToken() async {
    await _ensureInit();
    return FirebaseAuth.instance.currentUser?.getIdToken();
  }

  Future<void> signOut() async {
    try {
      // Nothing to sign out of when Firebase never started (tests, dev).
      if (Firebase.apps.isEmpty) return;
      await _ensureInit();
      await FirebaseAuth.instance.signOut();
      await GoogleSignIn.instance.signOut();
    } catch (_) {
      // Local app logout must succeed even if Google is unreachable.
    }
  }
}
