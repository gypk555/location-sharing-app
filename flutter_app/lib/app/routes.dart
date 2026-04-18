/// Centralized route-path constants used by `go_router` and all callers
/// of `context.push` / `context.go`.
///
/// Previously, every caller used raw strings (e.g. `context.push('/add-contact')`),
/// which (a) lets typos escape the compiler and (b) makes route-prefix changes
/// a scattershot find-and-replace (code-review finding §3.6).
abstract final class AppRoutes {
  AppRoutes._();

  static const splash = '/splash';
  static const auth = '/auth';
  static const otp = '/otp';

  static const home = '/';
  static const sos = '/sos';
  static const contacts = '/contacts';
  static const settings = '/settings';

  static const addContact = '/add-contact';
  static const fakeCall = '/fake-call';

  static const liveShareStart = '/live-share/start';
  static const liveShareActive = '/live-share/active';

  /// Pattern registered with go_router (contains `:id` placeholder).
  static const liveShareViewPattern = '/live-share/view/:id';

  /// Builds a concrete `/live-share/view/<id>` URL for navigation.
  static String liveShareView(String id) => '/live-share/view/$id';
}
