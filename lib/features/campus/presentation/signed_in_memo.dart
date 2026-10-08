/// Remembers the last value read while signed in.
///
/// After sign-out the business layer clears its data at once, but the home
/// screen is still fading out. Reading through a memo keeps the departing
/// screen showing its content instead of flashing empty/loading states.
class SignedInMemo<T> {
  T? _value;

  T read({required bool signedIn, required T Function() live}) {
    if (signedIn || _value == null) _value = live();
    return _value as T;
  }
}
