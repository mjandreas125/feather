import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/foundation.dart';

/// UI strings. To add a language: copy [_en], translate, register it in [_all].
class Strings {
  const Strings({
    required this.code,
    required this.inputPlaceholder,
    required this.inputPlaceholderBusy,
    required this.send,
    required this.stop,
    required this.newChat,
    required this.modeDefault,
    required this.modeAcceptEdits,
    required this.modePlan,
    required this.modeAuto,
    required this.modeBypass,
    required this.modeDefaultHint,
    required this.modeAcceptEditsHint,
    required this.modePlanHint,
    required this.modeAutoHint,
    required this.modeBypassHint,
    required this.model,
    required this.effort,
    required this.allow,
    required this.allowAlways,
    required this.allowAlwaysFor,
    required this.deny,
    required this.denyHint,
    required this.permRunCommand,
    required this.permEditFile,
    required this.permWriteFile,
    required this.permReadFile,
    required this.permFetch,
    required this.permUseTool,
    required this.answered,
    required this.allowed,
    required this.denied,
    required this.cancelled,
    required this.submit,
    required this.other,
    required this.otherHint,
    required this.next,
    required this.back,
    required this.skip,
    required this.planTitle,
    required this.planApprove,
    required this.planApproveAuto,
    required this.planKeep,
    required this.planKeepHint,
    required this.thinking,
    required this.thoughtFor,
    required this.starting,
    required this.working,
    required this.compacting,
    required this.claudeNotFound,
    required this.claudeNotFoundHint,
    required this.processExited,
    required this.restart,
    required this.interrupted,
    required this.copy,
    required this.copied,
    required this.showMore,
    required this.showLess,
    required this.emptyTitle,
    required this.emptyHint,
    required this.turnError,
    required this.subagentSteps,
    required this.output,
    required this.noOutput,
    required this.linesAddedRemoved,
    required this.contextUsed,
    required this.openFolder,
    required this.costLabel,
    required this.language,
    required this.languageAuto,
    required this.history,
    required this.historyEmpty,
    required this.search,
    required this.close,
    required this.notifyWaiting,
    required this.notifyDone,
    required this.open,
    required this.dismiss,
    required this.waitingForYou,
    required this.ago,
    required this.attach,
    required this.mentionFile,
    required this.noFiles,
    required this.projects,
    required this.explorer,
    required this.searchFiles,
    required this.memory,
    required this.refresh,
    required this.collapseAll,
    required this.mentionInChat,
    required this.searchHint,
    required this.memoryEmpty,
    required this.memoryInstructions,
    required this.memoryNotes,
    required this.graph,
    required this.cancel,
    required this.save,
    required this.edit,
    required this.backlinks,
    required this.fileTooBig,
    required this.binaryFile,
    required this.openExternally,
    required this.projectsSoon,
    required this.toggleSidebar,
    required this.searchCount,
    required this.overview,
    required this.addProject,
    required this.review,
    required this.notNow,
    required this.noProjects,
    required this.addProjectsTitle,
    required this.addProjectsHint,
    required this.whereWeStopped,
    required this.noSessionsYet,
    required this.nextSteps,
    required this.noNextSteps,
    required this.recentFiles,
    required this.removeProject,
    required this.continueWork,
    required this.overviewHint,
    required this.allowSession,
    required this.theme,
    required this.codexNotFoundHint,
    required this.newChatWith,
    required this.foundFolders,
    required this.addSelected,
    required this.uncommitted,
  });

  final String code;
  final String inputPlaceholder, inputPlaceholderBusy, send, stop, newChat;
  final String modeDefault, modeAcceptEdits, modePlan, modeAuto, modeBypass;
  final String modeDefaultHint, modeAcceptEditsHint, modePlanHint, modeAutoHint, modeBypassHint;
  final String model, effort;
  final String allow, allowAlways, deny, denyHint;
  final String Function(String what) allowAlwaysFor;
  final String permRunCommand, permEditFile, permWriteFile, permReadFile, permFetch;
  final String Function(String tool) permUseTool;
  final String answered, allowed, denied, cancelled;
  final String submit, other, otherHint, next, back, skip;
  final String planTitle, planApprove, planApproveAuto, planKeep, planKeepHint;
  final String thinking;
  final String Function(int seconds) thoughtFor;
  final String starting, working, compacting;
  final String claudeNotFound, claudeNotFoundHint;
  final String Function(int code) processExited;
  final String restart, interrupted, copy, copied, showMore, showLess;
  final String emptyTitle, emptyHint, turnError;
  final String Function(int n) subagentSteps;
  final String output, noOutput;
  final String Function(int added, int removed) linesAddedRemoved;
  final String Function(int percent) contextUsed;
  final String openFolder, costLabel;
  final String language, languageAuto;
  final String history, historyEmpty, search, close;
  final String notifyWaiting, notifyDone, open, dismiss, waitingForYou;
  final String Function(DateTime t) ago;
  final String attach, mentionFile, noFiles;
  final String projects, explorer, searchFiles, memory, refresh, collapseAll, mentionInChat, searchHint, memoryEmpty, memoryInstructions, memoryNotes, graph, cancel, save, edit, backlinks, fileTooBig, binaryFile, openExternally, projectsSoon, toggleSidebar;
  final String Function(int hits, int files) searchCount;
  final String overview, addProject, review, notNow, noProjects, addProjectsTitle, addProjectsHint, whereWeStopped, noSessionsYet, nextSteps, noNextSteps, recentFiles, removeProject, continueWork, overviewHint;
  final String Function(int n) foundFolders, addSelected, uncommitted;
  final String allowSession, codexNotFoundHint, theme;
  final String Function(String agent) newChatWith;
}

final Strings _en = Strings(
  code: 'en',
  inputPlaceholder: 'Ask Claude to edit, explain or run something…',
  inputPlaceholderBusy: 'Queue another message…',
  send: 'Send',
  stop: 'Stop',
  newChat: 'New chat',
  modeDefault: 'Ask before edits',
  modeAcceptEdits: 'Edit automatically',
  modePlan: 'Plan mode',
  modeAuto: 'Auto mode',
  modeBypass: 'Bypass permissions',
  modeDefaultHint: 'Claude asks before every edit and command',
  modeAcceptEditsHint: 'Edits files without asking, still asks before commands',
  modePlanHint: 'Claude explores and writes a plan, changes nothing',
  modeAutoHint: 'Claude decides; risky actions are still checked',
  modeBypassHint: 'Never asks. Only for sandboxes',
  model: 'Model',
  effort: 'Effort',
  allow: 'Allow',
  allowAlways: 'Allow always',
  allowAlwaysFor: (w) => 'Yes, and don’t ask again for $w',
  deny: 'Deny',
  denyHint: 'Tell Claude what to do instead',
  permRunCommand: 'Allow Claude to run this command?',
  permEditFile: 'Allow Claude to edit this file?',
  permWriteFile: 'Allow Claude to create this file?',
  permReadFile: 'Allow Claude to read this?',
  permFetch: 'Allow Claude to fetch this?',
  permUseTool: (t) => 'Allow Claude to use $t?',
  answered: 'Answered',
  allowed: 'Allowed',
  denied: 'Denied',
  cancelled: 'Cancelled',
  submit: 'Submit',
  other: 'Other',
  otherHint: 'Type your own answer',
  next: 'Next',
  back: 'Back',
  skip: 'Skip',
  planTitle: 'Ready to code?',
  planApprove: 'Yes, and ask before edits',
  planApproveAuto: 'Yes, and edit automatically',
  planKeep: 'No, keep planning',
  planKeepHint: 'Tell Claude what to change in the plan',
  thinking: 'Thinking',
  thoughtFor: (s) => 'Thought for ${s}s',
  starting: 'Starting Claude Code…',
  working: 'Working…',
  compacting: 'Compacting conversation…',
  claudeNotFound: 'Claude Code was not found',
  claudeNotFoundHint:
      'Install it from claude.com/claude-code and sign in once in a terminal (run `claude`), then press Restart.',
  processExited: (c) => 'Claude Code exited (code $c).',
  restart: 'Restart',
  interrupted: 'Interrupted',
  copy: 'Copy',
  copied: 'Copied',
  showMore: 'Show more',
  showLess: 'Show less',
  emptyTitle: 'What should we do?',
  emptyHint: 'Claude can read and change files in this folder and run commands. Type @ to mention a file, / for commands.',
  turnError: 'Something went wrong',
  subagentSteps: (n) => '$n steps',
  output: 'Output',
  noOutput: '(no output)',
  linesAddedRemoved: (a, r) => '+$a −$r',
  contextUsed: (p) => '$p% of context used',
  openFolder: 'Open folder',
  costLabel: 'Cost',
  language: 'Language',
  languageAuto: 'Automatic (as you write to Claude)',
  history: 'Past conversations',
  historyEmpty: 'No past conversations in this folder yet',
  search: 'Search',
  close: 'Close',
  notifyWaiting: 'Claude is waiting for you',
  notifyDone: 'Claude has finished',
  open: 'Open',
  dismiss: 'Dismiss',
  waitingForYou: 'Waiting for your answer',
  ago: (t) => _agoEn(t),
  attach: 'Attach images or files (or paste a screenshot with Ctrl+V)',
  mentionFile: 'Mention a file',
  noFiles: 'No matching files',
  projects: 'Projects',
  explorer: 'Explorer',
  searchFiles: 'Search',
  memory: 'Memory',
  refresh: 'Refresh',
  collapseAll: 'Collapse all',
  mentionInChat: 'Mention in chat',
  searchHint: 'Search in files',
  memoryEmpty: 'Claude has no instructions or memory notes for this folder yet.',
  memoryInstructions: 'INSTRUCTIONS',
  memoryNotes: 'MEMORY NOTES',
  graph: 'Graph of links',
  cancel: 'Cancel',
  save: 'Save',
  edit: 'Edit',
  backlinks: 'LINKED FROM',
  fileTooBig: 'The file is too large to preview.',
  binaryFile: 'Binary file, no preview.',
  openExternally: 'Open in the default app',
  projectsSoon: 'Projects',
  toggleSidebar: 'Toggle side bar (Ctrl+B)',
  searchCount: (h, f) => '$h results in $f files',
  overview: 'Overview of all projects',
  addProject: 'Add a folder',
  review: 'Review',
  notNow: 'Not now',
  noProjects: 'No projects yet. Open a folder, or work in one with Claude or Codex and it will be offered here.',
  addProjectsTitle: 'Add projects',
  addProjectsHint: 'Folders where you worked with Claude Code or Codex. Pick the ones to keep in the list.',
  whereWeStopped: 'Where we stopped',
  noSessionsYet: 'No conversations here yet',
  nextSteps: 'Next steps',
  noNextSteps: 'No open items. Add "- [ ] task" lines to WORKLOG.md or TODO.md and they will show up here.',
  recentFiles: 'Recently changed',
  removeProject: 'Remove from projects',
  continueWork: 'Continue',
  overviewHint: 'Everything you work on, latest first.',
  allowSession: 'Yes, and don’t ask again this session',
  theme: 'Light / dark theme',
  codexNotFoundHint: 'Install the Codex CLI (npm i -g @openai/codex) or the ChatGPT extension for VS Code, sign in once (run `codex`), then press Restart.',
  newChatWith: (a) => 'New chat with $a',
  foundFolders: (n) => 'Found $n folders where you worked with an agent. Add them as projects?',
  addSelected: (n) => 'Add ($n)',
  uncommitted: (n) => n == 0 ? 'no uncommitted changes' : '$n uncommitted changes',
);

String _agoEn(DateTime t) {
  final d = DateTime.now().difference(t);
  if (d.inMinutes < 1) return 'just now';
  if (d.inMinutes < 60) return '${d.inMinutes} min ago';
  if (d.inHours < 24) return '${d.inHours} h ago';
  if (d.inDays == 1) return 'yesterday';
  if (d.inDays < 7) return '${d.inDays} days ago';
  return '${t.day.toString().padLeft(2, '0')}.${t.month.toString().padLeft(2, '0')}.${t.year}';
}

final Strings _ru = Strings(
  code: 'ru',
  inputPlaceholder: 'Попросите Claude что-то изменить, объяснить или запустить…',
  inputPlaceholderBusy: 'Можно написать следующее сообщение…',
  send: 'Отправить',
  stop: 'Остановить',
  newChat: 'Новый чат',
  modeDefault: 'Спрашивать перед правками',
  modeAcceptEdits: 'Править без вопросов',
  modePlan: 'Режим плана',
  modeAuto: 'Авто',
  modeBypass: 'Без разрешений',
  modeDefaultHint: 'Claude спрашивает перед каждой правкой и командой',
  modeAcceptEditsHint: 'Правит файлы сам, перед командами спрашивает',
  modePlanHint: 'Claude изучает проект и пишет план, ничего не меняя',
  modeAutoHint: 'Claude решает сам, рискованные действия проверяются',
  modeBypassHint: 'Никогда не спрашивает. Только для песочницы',
  model: 'Модель',
  effort: 'Усилие',
  allow: 'Разрешить',
  allowAlways: 'Разрешать всегда',
  allowAlwaysFor: (w) => 'Да, и больше не спрашивать для $w',
  deny: 'Запретить',
  denyHint: 'Скажите Claude, что сделать вместо этого',
  permRunCommand: 'Разрешить Claude выполнить команду?',
  permEditFile: 'Разрешить Claude изменить файл?',
  permWriteFile: 'Разрешить Claude создать файл?',
  permReadFile: 'Разрешить Claude прочитать это?',
  permFetch: 'Разрешить Claude загрузить это?',
  permUseTool: (t) => 'Разрешить Claude использовать $t?',
  answered: 'Отвечено',
  allowed: 'Разрешено',
  denied: 'Запрещено',
  cancelled: 'Отменено',
  submit: 'Ответить',
  other: 'Другое',
  otherHint: 'Свой вариант',
  next: 'Дальше',
  back: 'Назад',
  skip: 'Пропустить',
  planTitle: 'Приступить к работе?',
  planApprove: 'Да, но спрашивать перед правками',
  planApproveAuto: 'Да, и править без вопросов',
  planKeep: 'Нет, доработать план',
  planKeepHint: 'Что поменять в плане',
  thinking: 'Думает',
  thoughtFor: (s) => 'Думал $s с',
  starting: 'Запускаю Claude Code…',
  working: 'Работает…',
  compacting: 'Сжимаю разговор…',
  claudeNotFound: 'Claude Code не найден',
  claudeNotFoundHint:
      'Установите его с claude.com/claude-code и один раз войдите в терминале (команда `claude`), затем нажмите «Перезапустить».',
  processExited: (c) => 'Claude Code завершился (код $c).',
  restart: 'Перезапустить',
  interrupted: 'Прервано',
  copy: 'Копировать',
  copied: 'Скопировано',
  showMore: 'Показать всё',
  showLess: 'Свернуть',
  emptyTitle: 'Чем займёмся?',
  emptyHint: 'Claude может читать и менять файлы в этой папке и запускать команды. @ — упомянуть файл, / — команды.',
  turnError: 'Что-то пошло не так',
  subagentSteps: (n) => 'шагов: $n',
  output: 'Вывод',
  noOutput: '(пусто)',
  linesAddedRemoved: (a, r) => '+$a −$r',
  contextUsed: (p) => 'контекст занят на $p%',
  openFolder: 'Открыть папку',
  costLabel: 'Стоимость',
  language: 'Язык',
  languageAuto: 'Автоматически (как вы пишете Claude)',
  history: 'Прошлые разговоры',
  historyEmpty: 'В этой папке ещё нет разговоров',
  search: 'Поиск',
  close: 'Закрыть',
  notifyWaiting: 'Claude ждёт вашего ответа',
  notifyDone: 'Claude закончил',
  open: 'Открыть',
  dismiss: 'Скрыть',
  waitingForYou: 'Ждёт вашего ответа',
  ago: (t) => _agoRu(t),
  attach: 'Прикрепить картинки или файлы (скриншот можно вставить через Ctrl+V)',
  mentionFile: 'Упомянуть файл',
  noFiles: 'Подходящих файлов нет',
  projects: 'Проекты',
  explorer: 'Проводник',
  searchFiles: 'Поиск',
  memory: 'Память',
  refresh: 'Обновить',
  collapseAll: 'Свернуть всё',
  mentionInChat: 'Упомянуть в чате',
  searchHint: 'Найти в файлах',
  memoryEmpty: 'Для этой папки у Claude пока нет инструкций и записей памяти.',
  memoryInstructions: 'ИНСТРУКЦИИ',
  memoryNotes: 'ЗАПИСИ ПАМЯТИ',
  graph: 'Граф связей',
  cancel: 'Отмена',
  save: 'Сохранить',
  edit: 'Изменить',
  backlinks: 'ССЫЛАЮТСЯ СЮДА',
  fileTooBig: 'Файл слишком большой для просмотра.',
  binaryFile: 'Двоичный файл, просмотра нет.',
  openExternally: 'Открыть в программе по умолчанию',
  projectsSoon: 'Проекты',
  toggleSidebar: 'Боковая панель (Ctrl+B)',
  searchCount: (h, f) => 'Найдено: $h в файлах: $f',
  overview: 'Обзор всех проектов',
  addProject: 'Добавить папку',
  review: 'Посмотреть',
  notNow: 'Не сейчас',
  noProjects: 'Проектов пока нет. Откройте папку или поработайте в ней с Claude или Codex, и она появится здесь.',
  addProjectsTitle: 'Добавить проекты',
  addProjectsHint: 'Папки, в которых вы работали с Claude Code или Codex. Отметьте те, что нужны в списке.',
  whereWeStopped: 'Где остановились',
  noSessionsYet: 'Здесь ещё не было разговоров',
  nextSteps: 'Дальше',
  noNextSteps: 'Открытых пунктов нет. Строки «- [ ] задача» в WORKLOG.md или TODO.md появятся здесь.',
  recentFiles: 'Недавно изменённые',
  removeProject: 'Убрать из проектов',
  continueWork: 'Продолжить',
  overviewHint: 'Всё, над чем вы работаете, последние сверху.',
  allowSession: 'Да, и не спрашивать до конца сессии',
  theme: 'Светлая / тёмная тема',
  codexNotFoundHint: 'Установите Codex CLI (npm i -g @openai/codex) или расширение ChatGPT для VS Code, один раз войдите (команда `codex`) и нажмите «Перезапустить».',
  newChatWith: (a) => 'Новый чат: $a',
  foundFolders: (n) => 'Нашёл папки, где вы работали с агентом: $n. Добавить их в проекты?',
  addSelected: (n) => 'Добавить ($n)',
  uncommitted: (n) => n == 0 ? 'всё закоммичено' : 'незакоммиченных изменений: $n',
);

String _agoRu(DateTime t) {
  final d = DateTime.now().difference(t);
  if (d.inMinutes < 1) return 'только что';
  if (d.inMinutes < 60) return '${d.inMinutes} мин назад';
  if (d.inHours < 24) return '${d.inHours} ч назад';
  if (d.inDays == 1) return 'вчера';
  if (d.inDays < 7) return '${d.inDays} дн. назад';
  return '${t.day.toString().padLeft(2, '0')}.${t.month.toString().padLeft(2, '0')}.${t.year}';
}

final Map<String, Strings> _all = {'en': _en, 'ru': _ru};

Strings _pick() {
  for (final loc in PlatformDispatcher.instance.locales) {
    final s = _all[loc.languageCode];
    if (s != null) return s;
  }
  return _en;
}

/// Current UI strings (system language, English fallback).
Strings S = _pick();

/// Bumped when the language changes so the whole UI rebuilds.
final ValueNotifier<String> languageNotifier = ValueNotifier(S.code);

void setLanguage(String? code) {
  S = code == null ? _pick() : (_all[code] ?? _en);
  languageNotifier.value = S.code;
}

/// Native names for the language menu.
const Map<String, String> languageNames = {'en': 'English', 'ru': 'Русский'};
List<String> get availableLanguages => _all.keys.toList();
