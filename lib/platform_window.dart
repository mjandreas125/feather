import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Native window helpers implemented in windows/runner/flutter_window.cpp and
/// notifications.cpp.
class NativeWindow {
  static const _ch = MethodChannel('feather/window');
  static String? _lastTitle;
  static void Function(String tag)? onToastActivated;
  static void Function(List<String> paths)? onFilesDropped;

  static void init() {
    _ch.setMethodCallHandler((call) async {
      if (call.method == 'toastActivated') onToastActivated?.call('${call.arguments}');
      if (call.method == 'maximizedChanged') maximized.value = call.arguments == true;
      if (call.method == 'filesDropped' && call.arguments is List) {
        onFilesDropped?.call([for (final a in call.arguments as List) '$a']);
      }
      return null;
    });
  }

  /// PNG of the image on the clipboard (e.g. a screenshot), or null.
  static Future<Uint8List?> clipboardImage() async {
    try {
      return await _ch.invokeMethod<Uint8List>('clipboardImage');
    } catch (_) {
      return null;
    }
  }

  /// Files copied in Explorer.
  static Future<List<String>> clipboardFiles() async {
    try {
      final r = await _ch.invokeMethod<List<Object?>>('clipboardFiles');
      return [for (final f in r ?? const []) '$f'];
    } catch (_) {
      return const [];
    }
  }

  /// Title shown in Feather's own title bar (and the taskbar).
  static final ValueNotifier<String> title = ValueNotifier('Feather');
  static final ValueNotifier<bool> maximized = ValueNotifier(false);

  static Future<void> _call(String method, [Object? arg]) async {
    try {
      await _ch.invokeMethod(method, arg);
    } catch (_) {}
  }

  static Future<void> startDrag() => _call('startDrag');
  static Future<void> startResize(String edge) => _call('startResize', edge);
  static Future<void> minimize() => _call('minimize');
  static Future<void> toggleMaximize() => _call('toggleMaximize');
  static Future<void> close() => _call('close');

  static Future<void> setTitle(String text) async {
    if (text == _lastTitle) return;
    _lastTitle = text;
    // Called during build: update listeners after the frame.
    WidgetsBinding.instance.addPostFrameCallback((_) => title.value = text);
    await _call('setTitle', text);
  }

  static Future<void> setDark(bool dark) async {
    try {
      await _ch.invokeMethod('setDark', dark);
    } catch (_) {}
  }

  /// Whether the Feather window is the active window right now.
  static Future<bool> isForeground() async {
    try {
      return await _ch.invokeMethod<bool>('isForeground') ?? true;
    } catch (_) {
      return true;
    }
  }

  /// Taskbar button flashes until the user comes back to the window.
  static Future<void> flash() async {
    try {
      await _ch.invokeMethod('flash');
    } catch (_) {}
  }

  /// A Windows notification that stays on screen until dismissed.
  static Future<bool> toast({
    required String tag,
    required String title,
    required String body,
    required String openLabel,
    required String dismissLabel,
  }) async {
    try {
      return await _ch.invokeMethod<bool>('toast', {
            'tag': tag,
            'title': title,
            'body': body,
            'open': openLabel,
            'dismiss': dismissLabel,
          }) ??
          false;
    } catch (_) {
      return false;
    }
  }

  static Future<void> hideToast(String tag) async {
    try {
      await _ch.invokeMethod('hideToast', tag);
    } catch (_) {}
  }
}
