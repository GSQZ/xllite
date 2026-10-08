/// Which controller call can recover from the current signed-out failure.
///
/// Derived from the explicit operation recorded in AuthFailure.
enum AuthRecovery {
  /// Failure belongs to the login form (or there is none).
  none,

  /// Restoring the saved session failed; `restore()` may succeed later.
  restore,

  /// Local credentials may not have been cleared; retry `signOut()`.
  signOut,
}
