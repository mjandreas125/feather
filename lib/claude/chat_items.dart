import 'dart:convert';

/// Everything shown in the chat timeline is a [ChatItem]. Items are mutable while they
/// stream; [version] is bumped on every change so widgets can skip needless rebuilds.
abstract class ChatItem {
  ChatItem() : uid = _next++;
  static int _next = 0;
  final int uid;
  int version = 0;
  void touch() => version++;
}

class UserItem extends ChatItem {
  UserItem(this.text, {this.images = const []});
  final String text;
  final List<ImageAttachment> images;
}

class ImageAttachment {
  ImageAttachment(this.mediaType, this.base64Data);
  final String mediaType;
  final String base64Data;
  late final bytes = base64Decode(base64Data);
}

class TextItem extends ChatItem {
  TextItem({this.text = '', this.streaming = false, this.messageId});
  String text;
  bool streaming;
  String? messageId;
}

class ThinkingItem extends ChatItem {
  ThinkingItem({this.text = '', this.streaming = false, this.messageId}) : started = DateTime.now();
  String text;
  bool streaming;
  String? messageId;
  final DateTime started;
  Duration? took;
}

enum ToolStatus { running, done, error, denied }

class ToolItem extends ChatItem {
  ToolItem({required this.toolUseId, required this.name, Map<String, dynamic>? input, this.messageId})
      : input = input ?? {};
  final String toolUseId;
  final String name;
  Map<String, dynamic> input;
  String partialJson = '';
  bool inputComplete = false;
  String? messageId;
  ToolStatus status = ToolStatus.running;
  String? resultText;
  dynamic structured; // tool_use_result from the CLI (e.g. structuredPatch for edits)
  final List<ChatItem> children = []; // sub-agent activity (Task / Agent tool)
  bool expanded = false;

  /// MCP tools are called mcp__server__tool; show "server · tool".
  String get displayName {
    if (name.startsWith('mcp__')) {
      final parts = name.substring(5).split('__');
      if (parts.length >= 2) return '${parts.first} · ${parts.sublist(1).join('__')}';
    }
    return name;
  }
}

enum RequestKind { permission, question, plan }

enum RequestState { pending, allowed, denied, cancelled }

/// A control_request from the CLI that waits for the user (can_use_tool).
class RequestItem extends ChatItem {
  RequestItem({
    required this.requestId,
    required this.kind,
    required this.toolName,
    required this.input,
    this.toolUseId,
    this.suggestions = const [],
    this.decisionReason,
    this.blockedPath,
  });
  final String requestId;
  final RequestKind kind;
  final String toolName;
  final Map<String, dynamic> input;
  final String? toolUseId;
  final List<dynamic> suggestions;
  final String? decisionReason;
  final String? blockedPath;
  RequestState state = RequestState.pending;
  String? summary; // what the user chose, shown after resolving
  bool notified = false;
}

enum NoticeKind { info, error, interrupted, compact }

class NoticeItem extends ChatItem {
  NoticeItem(this.text, {this.kind = NoticeKind.info, this.detail});
  final String text;
  final NoticeKind kind;
  final String? detail;
}
