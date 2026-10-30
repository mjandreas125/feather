import 'dart:convert';
import 'dart:io';
import 'dart:async';
import 'dart:ui' as ui;
import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'claude/locate.dart';
import 'claude/session.dart';
import 'keys.dart';
import 'l10n.dart';
import 'lang_detect.dart';
import 'theme.dart';
import 'platform_window.dart';
import 'ui/shell.dart';
import 'ui/titlebar.dart';
import 'ui/widgets.dart';
import 'codicons.dart';

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  // Unhandled errors go to the FEATHER_LOG trace (if set) instead of vanishing.
  FlutterError.onError = (d) {
    ChatSession.debugLog('FLUTTER ERROR: ${d.exceptionAsString()}\n${d.stack}');
    FlutterError.presentError(d);
  };
  PlatformDispatcher.instance.onError = (e, st) {
    ChatSession.debugLog('UNCAUGHT: $e\n$st');
    return true;
  };
  await AppConfig.load();
  if (AppConfig.language != null) {
    setLanguage(AppConfig.language);
  } else {
    // Speak the language the user speaks to Claude (settings, then recent messages).
    final detected = await detectUserLanguage(availableLanguages);
    if (detected != null) setLanguage(detected);
  }
  // --lang=en|ru overrides the automatic/menu choice for this run.
  final langArg = args.where((a) => a.startsWith('--lang=')).map((a) => a.substring(7)).firstOrNull;
  if (langArg != null) setLanguage(langArg);
  final argDir = args.where((a) => !a.startsWith('-')).map((a) => a.trim()).firstWhere(
        (a) => a.isNotEmpty && Directory(a).existsSync(),
        orElse: () => '',
      );
  final cwd = argDir.isNotEmpty
      ? argDir
      : (AppConfig.lastFolder != null && Directory(AppConfig.lastFolder!).existsSync())
          ? AppConfig.lastFolder!
          : (homeDir ?? Directory.current.path);
  String? opt(String name) {
    final a = args.where((a) => a.startsWith('--$name=')).toList();
    return a.isEmpty ? null : a.first.substring(name.length + 3);
  }

  NativeWindow.setDark(P.dark);
  final snapDir = opt('snapshot-dir');
  runApp(RepaintBoundary(
    key: _rootKey,
    child: FeatherApp(
      initialFolder: cwd,
      startup: StartupOptions(prompt: opt('prompt'), model: opt('model'), mode: opt('mode'), agent: opt('agent')),
    ),
  ));
  if (snapDir != null) _watchSnapshotRequests(snapDir);
}

final _rootKey = GlobalKey();

/// Developer aid for visual checks (also when the monitor is asleep): with
/// --snapshot-dir=DIR the app renders itself to DIR/<name>.png whenever a file
/// DIR/request.txt containing <name> appears.
void _watchSnapshotRequests(String dir) {
  Timer.periodic(const Duration(milliseconds: 250), (_) async {
    final req = File(p.join(dir, 'request.txt'));
    if (!req.existsSync()) return;
    final name = req.readAsStringSync().trim();
    req.deleteSync();
    final boundary = _rootKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
    if (boundary == null) return;
    final image = await boundary.toImage(pixelRatio: 1);
    final png = await image.toByteData(format: ui.ImageByteFormat.png);
    if (png != null) File(p.join(dir, name.isEmpty ? 'snapshot.png' : name)).writeAsBytesSync(png.buffer.asUint8List());
  });
}

/// Small JSON settings file in the per-user app data folder.
class AppConfig {
  static String? lastFolder;

  /// Language picked by hand in the menu; null = automatic.
  static String? language;
  static File? _file;

  static Future<void> load() async {
    try {
      final dir = await getApplicationSupportDirectory();
      _file = File(p.join(dir.path, 'feather.json'));
      if (_file!.existsSync()) {
        final j = jsonDecode(_file!.readAsStringSync()) as Map<String, dynamic>;
        lastFolder = j['lastFolder'] as String?;
        language = j['languageManual'] as String?;
        if (j['theme'] == 'light') paletteNotifier.value = Palette.lightModern;
      }
    } catch (_) {}
  }

  static void save() {
    try {
      _file?.parent.createSync(recursive: true);
      _file?.writeAsStringSync(jsonEncode({
        'lastFolder': lastFolder,
        'languageManual': language,
        'theme': P.dark ? 'dark' : 'light',
      }));
    } catch (_) {}
  }

  static void setTheme(bool dark) {
    paletteNotifier.value = dark ? Palette.darkModern : Palette.lightModern;
    NativeWindow.setDark(dark);
    save();
  }

  /// Manual choice, or null to go back to automatic detection.
  static Future<void> chooseLanguage(String? code) async {
    language = code;
    save();
    if (code != null) {
      setLanguage(code);
    } else {
      setLanguage(await detectUserLanguage(availableLanguages));
    }
  }
}

/// Command-line options: feather [folder] [--prompt=text] [--model=alias] [--mode=plan|acceptEdits|…]
class StartupOptions {
  const StartupOptions({this.prompt, this.model, this.mode, this.agent});
  final String? prompt, model, mode, agent;
}

class FeatherApp extends StatelessWidget {
  const FeatherApp({super.key, required this.initialFolder, this.startup = const StartupOptions()});
  final String initialFolder;
  final StartupOptions startup;

  @override
  Widget build(BuildContext context) {
    // The Shell (and its Claude processes) must survive theme/language rebuilds,
    // so it is created once and only the MaterialApp around it is rebuilt.
    final home = _Home(initialFolder: initialFolder, startup: startup);
    return ListenableBuilder(
      listenable: Listenable.merge([paletteNotifier, languageNotifier]),
      builder: (context, _) => MaterialApp(
        title: 'Feather',
        debugShowCheckedModeBanner: false,
        theme: buildTheme(P),
        builder: (context, child) => Shortcuts(
          shortcuts: layoutIndependentTextShortcuts,
          child: child!,
        ),
        home: home,
      ),
    );
  }
}

class _Home extends StatefulWidget {
  const _Home({required this.initialFolder, required this.startup});
  final String initialFolder;
  final StartupOptions startup;
  @override
  State<_Home> createState() => _HomeState();
}

class _HomeState extends State<_Home> {
  final _shellKey = GlobalKey<ShellState>();

  // Theme and language are read from globals (P, S): rebuild the whole tree on change.
  void _restyle() => setState(() {});

  @override
  void initState() {
    super.initState();
    paletteNotifier.addListener(_restyle);
    languageNotifier.addListener(_restyle);
  }

  @override
  void dispose() {
    paletteNotifier.removeListener(_restyle);
    languageNotifier.removeListener(_restyle);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final o = widget.startup;
    return Scaffold(
      backgroundColor: P.panelBg,
      body: Column(children: [
        TitleBar(
          trailing: Row(mainAxisSize: MainAxisSize.min, children: [
            IconBtn(P.dark ? Codicons.colorMode : Codicons.colorMode,
                size: 15, tooltip: S.theme, onTap: () => AppConfig.setTheme(!P.dark)),
            Builder(builder: (c) => IconBtn(Codicons.globe, size: 15, tooltip: S.language, onTap: () => _languageMenu(c))),
          ]),
        ),
        Expanded(
          child: Shell(
            key: _shellKey,
            initialFolder: widget.initialFolder,
            defaults: TabDefaults(model: o.model, mode: o.mode, agent: o.agent),
            initialPrompt: o.prompt,
            onFolderChanged: (folder) {
              AppConfig.lastFolder = folder;
              AppConfig.save();
            },
          ),
        ),
      ]),
    );
  }

  Future<void> _languageMenu(BuildContext anchor) async {
    final box = anchor.findRenderObject() as RenderBox;
    final pos = box.localToGlobal(Offset(0, box.size.height));
    Widget item(String label, bool selected) => Row(children: [
          SizedBox(width: 20, child: selected ? Icon(Codicons.check, size: 14, color: P.fg) : null),
          Text(label, style: uiText()),
        ]);
    final picked = await showMenu<String>(
      context: anchor,
      position: RelativeRect.fromLTRB(pos.dx - 240, pos.dy + 2, pos.dx, 0),
      items: [
        PopupMenuItem(value: 'auto', height: 32, child: item(S.languageAuto, AppConfig.language == null)),
        for (final code in availableLanguages)
          PopupMenuItem(value: code, height: 32, child: item(languageNames[code] ?? code, AppConfig.language == code)),
      ],
    );
    if (picked != null) await AppConfig.chooseLanguage(picked == 'auto' ? null : picked);
  }
}
