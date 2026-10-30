import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:re_highlight/languages/bash.dart';
import 'package:re_highlight/languages/c.dart';
import 'package:re_highlight/languages/cpp.dart';
import 'package:re_highlight/languages/csharp.dart';
import 'package:re_highlight/languages/css.dart';
import 'package:re_highlight/languages/dart.dart';
import 'package:re_highlight/languages/diff.dart';
import 'package:re_highlight/languages/dockerfile.dart';
import 'package:re_highlight/languages/dos.dart';
import 'package:re_highlight/languages/go.dart';
import 'package:re_highlight/languages/ini.dart';
import 'package:re_highlight/languages/java.dart';
import 'package:re_highlight/languages/javascript.dart';
import 'package:re_highlight/languages/json.dart';
import 'package:re_highlight/languages/kotlin.dart';
import 'package:re_highlight/languages/lua.dart';
import 'package:re_highlight/languages/markdown.dart';
import 'package:re_highlight/languages/php.dart';
import 'package:re_highlight/languages/powershell.dart';
import 'package:re_highlight/languages/python.dart';
import 'package:re_highlight/languages/ruby.dart';
import 'package:re_highlight/languages/rust.dart';
import 'package:re_highlight/languages/scss.dart';
import 'package:re_highlight/languages/sql.dart';
import 'package:re_highlight/languages/swift.dart';
import 'package:re_highlight/languages/typescript.dart';
import 'package:re_highlight/languages/xml.dart';
import 'package:re_highlight/languages/yaml.dart';
import 'package:re_highlight/re_highlight.dart';
import 'package:url_launcher/url_launcher.dart';

import '../theme.dart';
import 'widgets.dart';

// ------------------------------------------------------------------ highlighting

/// Syntax highlighting with lazily registered grammars: a grammar is only built the first
/// time a code block in that language is shown.
class CodeHighlighter {
  CodeHighlighter._();
  static final instance = CodeHighlighter._();
  final Highlight _hl = Highlight();
  final Set<String> _registered = {};

  static final Map<String, Mode Function()> _grammars = {
    'bash': () => langBash, 'c': () => langC, 'cpp': () => langCpp, 'csharp': () => langCsharp,
    'css': () => langCss, 'dart': () => langDart, 'diff': () => langDiff,
    'dockerfile': () => langDockerfile, 'dos': () => langDos, 'go': () => langGo, 'ini': () => langIni,
    'java': () => langJava, 'javascript': () => langJavascript, 'json': () => langJson,
    'kotlin': () => langKotlin, 'lua': () => langLua, 'markdown': () => langMarkdown, 'php': () => langPhp,
    'powershell': () => langPowershell, 'python': () => langPython, 'ruby': () => langRuby,
    'rust': () => langRust, 'scss': () => langScss, 'sql': () => langSql, 'swift': () => langSwift,
    'typescript': () => langTypescript, 'xml': () => langXml, 'yaml': () => langYaml,
  };

  static const Map<String, String> _aliases = {
    'sh': 'bash', 'shell': 'bash', 'zsh': 'bash', 'console': 'bash', 'h': 'c', 'hpp': 'cpp', 'cc': 'cpp',
    'c++': 'cpp', 'cs': 'csharp', 'c#': 'csharp', 'js': 'javascript', 'jsx': 'javascript', 'mjs': 'javascript',
    'cjs': 'javascript', 'ts': 'typescript', 'tsx': 'typescript', 'mts': 'typescript', 'py': 'python',
    'rb': 'ruby', 'rs': 'rust', 'kt': 'kotlin', 'kts': 'kotlin', 'ps1': 'powershell', 'psm1': 'powershell',
    'pwsh': 'powershell', 'ps': 'powershell', 'bat': 'dos', 'cmd': 'dos', 'html': 'xml', 'htm': 'xml',
    'svg': 'xml', 'xaml': 'xml', 'csproj': 'xml', 'yml': 'yaml', 'md': 'markdown', 'toml': 'ini',
    'cfg': 'ini', 'conf': 'ini', 'jsonc': 'json', 'json5': 'json', 'patch': 'diff', 'docker': 'dockerfile',
    'sass': 'scss', 'less': 'scss', 'golang': 'go', 'mysql': 'sql', 'postgres': 'sql', 'psql': 'sql',
  };

  /// Canonical grammar name for a fence tag or file extension, or null.
  static String? resolve(String? lang) {
    if (lang == null) return null;
    final l = lang.toLowerCase().trim();
    final name = _aliases[l] ?? l;
    return _grammars.containsKey(name) ? name : null;
  }

  static String? forPath(String path) {
    final dot = path.lastIndexOf('.');
    if (dot < 0) return path.toLowerCase().endsWith('dockerfile') ? 'dockerfile' : null;
    return resolve(path.substring(dot + 1));
  }

  TextSpan highlight(String code, String? lang, TextStyle base) {
    final name = resolve(lang);
    if (name == null || code.length > 200000) return TextSpan(text: code, style: base);
    if (_registered.add(name)) _hl.registerLanguage(name, _grammars[name]!());
    try {
      final result = _hl.highlight(code: code, language: name);
      final renderer = TextSpanRenderer(base, P.dark ? _darkTheme : _lightTheme);
      result.render(renderer);
      return renderer.span ?? TextSpan(text: code, style: base);
    } catch (_) {
      return TextSpan(text: code, style: base);
    }
  }

  // VS Code "Dark Modern" / "Light Modern" token colours.
  static const _darkTheme = <String, TextStyle>{
    'keyword': TextStyle(color: Color(0xFF569CD6)),
    'literal': TextStyle(color: Color(0xFF569CD6)),
    'built_in': TextStyle(color: Color(0xFF4EC9B0)),
    'type': TextStyle(color: Color(0xFF4EC9B0)),
    'title.class_': TextStyle(color: Color(0xFF4EC9B0)),
    'title.class_.inherited__': TextStyle(color: Color(0xFF4EC9B0)),
    'title': TextStyle(color: Color(0xFFDCDCAA)),
    'title.function_': TextStyle(color: Color(0xFFDCDCAA)),
    'function': TextStyle(color: Color(0xFFDCDCAA)),
    'number': TextStyle(color: Color(0xFFB5CEA8)),
    'string': TextStyle(color: Color(0xFFCE9178)),
    'regexp': TextStyle(color: Color(0xFFD16969)),
    'subst': TextStyle(color: Color(0xFF9CDCFE)),
    'comment': TextStyle(color: Color(0xFF6A9955)),
    'doctag': TextStyle(color: Color(0xFF608B4E)),
    'meta': TextStyle(color: Color(0xFF569CD6)),
    'meta keyword': TextStyle(color: Color(0xFFC586C0)),
    'variable': TextStyle(color: Color(0xFF9CDCFE)),
    'variable.language_': TextStyle(color: Color(0xFF569CD6)),
    'params': TextStyle(color: Color(0xFF9CDCFE)),
    'property': TextStyle(color: Color(0xFF9CDCFE)),
    'attr': TextStyle(color: Color(0xFF9CDCFE)),
    'attribute': TextStyle(color: Color(0xFF9CDCFE)),
    'tag': TextStyle(color: Color(0xFF808080)),
    'name': TextStyle(color: Color(0xFF569CD6)),
    'selector-tag': TextStyle(color: Color(0xFFD7BA7D)),
    'selector-class': TextStyle(color: Color(0xFFD7BA7D)),
    'selector-id': TextStyle(color: Color(0xFFD7BA7D)),
    'symbol': TextStyle(color: Color(0xFFB5CEA8)),
    'bullet': TextStyle(color: Color(0xFF6796E6)),
    'section': TextStyle(color: Color(0xFF569CD6), fontWeight: FontWeight.bold),
    'code': TextStyle(color: Color(0xFFCE9178)),
    'emphasis': TextStyle(fontStyle: FontStyle.italic),
    'strong': TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF569CD6)),
    'addition': TextStyle(color: Color(0xFF81B88B)),
    'deletion': TextStyle(color: Color(0xFFE5534B)),
    'link': TextStyle(color: Color(0xFF4DAAFC)),
  };

  static const _lightTheme = <String, TextStyle>{
    'keyword': TextStyle(color: Color(0xFF0000FF)),
    'literal': TextStyle(color: Color(0xFF0000FF)),
    'built_in': TextStyle(color: Color(0xFF267F99)),
    'type': TextStyle(color: Color(0xFF267F99)),
    'title.class_': TextStyle(color: Color(0xFF267F99)),
    'title': TextStyle(color: Color(0xFF795E26)),
    'title.function_': TextStyle(color: Color(0xFF795E26)),
    'function': TextStyle(color: Color(0xFF795E26)),
    'number': TextStyle(color: Color(0xFF098658)),
    'string': TextStyle(color: Color(0xFFA31515)),
    'regexp': TextStyle(color: Color(0xFF811F3F)),
    'comment': TextStyle(color: Color(0xFF008000)),
    'meta': TextStyle(color: Color(0xFF0000FF)),
    'variable': TextStyle(color: Color(0xFF001080)),
    'params': TextStyle(color: Color(0xFF001080)),
    'property': TextStyle(color: Color(0xFF001080)),
    'attr': TextStyle(color: Color(0xFFE50000)),
    'attribute': TextStyle(color: Color(0xFFE50000)),
    'tag': TextStyle(color: Color(0xFF800000)),
    'name': TextStyle(color: Color(0xFF800000)),
    'selector-tag': TextStyle(color: Color(0xFF800000)),
    'selector-class': TextStyle(color: Color(0xFF800000)),
    'section': TextStyle(color: Color(0xFF0000FF), fontWeight: FontWeight.bold),
    'addition': TextStyle(color: Color(0xFF2E7D32)),
    'deletion': TextStyle(color: Color(0xFFC62828)),
    'emphasis': TextStyle(fontStyle: FontStyle.italic),
    'strong': TextStyle(fontWeight: FontWeight.bold),
  };
}

// ------------------------------------------------------------------ code block

class CodeBlock extends StatelessWidget {
  const CodeBlock({super.key, required this.code, this.language, this.maxHeight});
  final String code;
  final String? language;
  final double? maxHeight;

  @override
  Widget build(BuildContext context) {
    final text = code.endsWith('\n') ? code.substring(0, code.length - 1) : code;
    final span = CodeHighlighter.instance.highlight(text, language, monoText());
    Widget body = SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      child: Text.rich(span, softWrap: false),
    );
    if (maxHeight != null) {
      body = ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight!),
        child: SingleChildScrollView(child: body),
      );
    }
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      decoration: BoxDecoration(
        color: P.codeBg,
        borderRadius: BorderRadius.circular(5),
        border: Border.all(color: P.border),
      ),
      child: HoverReveal(
        overlay: (visible) => Positioned(
          right: 4,
          top: 4,
          child: IgnorePointer(
            ignoring: !visible,
            child: AnimatedOpacity(
              opacity: visible ? 1 : 0,
              duration: const Duration(milliseconds: 120),
              child: Container(
                decoration: BoxDecoration(color: P.codeBg, borderRadius: BorderRadius.circular(4)),
                child: CopyButton(() => text),
              ),
            ),
          ),
        ),
        child: body,
      ),
    );
  }
}

/// Stacks [overlay] over [child]; the overlay learns whether the pointer is over the
/// whole area (used for copy buttons that appear on hover, like in VS Code).
class HoverReveal extends StatefulWidget {
  const HoverReveal({super.key, required this.child, required this.overlay});
  final Widget child;
  final Widget Function(bool visible) overlay;
  @override
  State<HoverReveal> createState() => _HoverRevealState();
}

class _HoverRevealState extends State<HoverReveal> {
  bool _h = false;
  @override
  Widget build(BuildContext context) => MouseRegion(
        onEnter: (_) => setState(() => _h = true),
        onExit: (_) => setState(() => _h = false),
        child: Stack(children: [widget.child, widget.overlay(_h)]),
      );
}

class _PreBuilder extends MarkdownElementBuilder {
  @override
  bool isBlockElement() => true;

  @override
  Widget? visitElementAfterWithContext(
      BuildContext context, md.Element element, TextStyle? preferredStyle, TextStyle? parentStyle) {
    String? lang;
    final first = element.children?.isNotEmpty == true ? element.children!.first : null;
    if (first is md.Element) {
      final cls = first.attributes['class'];
      if (cls != null && cls.startsWith('language-')) lang = cls.substring(9);
    }
    return CodeBlock(code: element.textContent, language: lang);
  }
}

// ------------------------------------------------------------------ markdown

/// Assistant markdown, styled like the Claude Code panel.
class MarkdownView extends StatelessWidget {
  const MarkdownView(this.data, {super.key, this.onOpenPath, this.fontSize = chatFontSize});
  final String data;
  final void Function(String path)? onOpenPath;
  final double fontSize;

  static MarkdownStyleSheet sheet(double size) {
    final p = uiText(size: size);
    return MarkdownStyleSheet(
      p: p,
      pPadding: EdgeInsets.zero,
      a: p.copyWith(color: P.link, decoration: TextDecoration.none),
      strong: p.copyWith(fontWeight: FontWeight.w600),
      em: p.copyWith(fontStyle: FontStyle.italic),
      del: p.copyWith(decoration: TextDecoration.lineThrough),
      code: monoText(size: size - 1, color: P.inlineCodeFg).copyWith(backgroundColor: P.inlineCodeBg),
      h1: uiText(size: size + 7, weight: FontWeight.w600, height: 1.3),
      h2: uiText(size: size + 4, weight: FontWeight.w600, height: 1.3),
      h3: uiText(size: size + 2, weight: FontWeight.w600, height: 1.3),
      h4: uiText(size: size + 1, weight: FontWeight.w600),
      h5: uiText(size: size, weight: FontWeight.w600),
      h6: uiText(size: size, weight: FontWeight.w600, color: P.fgMuted),
      h1Padding: const EdgeInsets.only(top: 8, bottom: 2),
      h2Padding: const EdgeInsets.only(top: 8, bottom: 2),
      h3Padding: const EdgeInsets.only(top: 6, bottom: 2),
      blockSpacing: 8,
      listIndent: 20,
      listBullet: p.copyWith(color: P.fgMuted),
      listBulletPadding: const EdgeInsets.only(right: 4),
      blockquote: p.copyWith(color: P.fgMuted),
      blockquotePadding: const EdgeInsets.fromLTRB(10, 2, 6, 2),
      blockquoteDecoration: BoxDecoration(border: Border(left: BorderSide(color: P.inputBorder, width: 3))),
      codeblockPadding: EdgeInsets.zero,
      codeblockDecoration: const BoxDecoration(),
      tableHead: p.copyWith(fontWeight: FontWeight.w600),
      tableBody: p,
      tableBorder: TableBorder.all(color: P.inputBorder, width: 1),
      tableCellsPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      tableColumnWidth: const IntrinsicColumnWidth(),
      horizontalRuleDecoration: BoxDecoration(border: Border(top: BorderSide(color: P.border))),
      checkbox: p.copyWith(color: P.fgMuted),
    );
  }

  @override
  Widget build(BuildContext context) {
    return MarkdownBody(
      data: data,
      styleSheet: sheet(fontSize),
      extensionSet: md.ExtensionSet.gitHubFlavored,
      builders: {'pre': _PreBuilder()},
      softLineBreak: true,
      onTapLink: (text, href, title) => openLink(href, onOpenPath: onOpenPath),
    );
  }
}

Future<void> openLink(String? href, {void Function(String path)? onOpenPath}) async {
  if (href == null || href.isEmpty) return;
  final uri = Uri.tryParse(href);
  if (uri != null && (uri.scheme == 'http' || uri.scheme == 'https' || uri.scheme == 'mailto')) {
    await launchUrl(uri);
    return;
  }
  if (onOpenPath != null) {
    onOpenPath(href);
  } else {
    await launchUrl(Uri.file(href.split('#').first));
  }
}
