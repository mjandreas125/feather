# Third-party notices

Feather includes or links the following third-party components.

| Component | Use | License |
|---|---|---|
| [Codicons](https://github.com/microsoft/vscode-codicons) (Microsoft) | UI icons, `assets/fonts/codicon.ttf` | Icons: [CC BY 4.0](third_party/codicons/LICENSE), code: [MIT](third_party/codicons/LICENSE-CODE) |
| [Flutter](https://flutter.dev) engine and framework | UI toolkit | BSD 3-Clause |
| [flutter_markdown_plus](https://pub.dev/packages/flutter_markdown_plus) | Markdown rendering | BSD 3-Clause |
| [markdown](https://pub.dev/packages/markdown) | Markdown parsing | BSD 3-Clause |
| [re_highlight](https://pub.dev/packages/re_highlight) (Reqable) | Syntax highlighting (grammars from highlight.js) | MIT |
| [path](https://pub.dev/packages/path), [path_provider](https://pub.dev/packages/path_provider) | File paths, app data folder | BSD 3-Clause |
| [url_launcher](https://pub.dev/packages/url_launcher) | Opening links | BSD 3-Clause |
| [file_selector](https://pub.dev/packages/file_selector) | Folder and file pickers | BSD 3-Clause |

Codicons are used unmodified; the glyph names in `lib/codicons.dart` are generated from the
package's `codicon.csv` by `tools/gen_codicons.py`.

Feather starts the Claude Code and Codex command-line tools that the user has installed; it
does not include or redistribute them.
