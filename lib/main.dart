import 'dart:async';
import 'dart:math';
import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider/path_provider.dart';
import 'package:archive/archive.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'package:http/http.dart' as http;
import 'package:open_file/open_file.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Current app version — keep in sync with pubspec.yaml (version: x.y.z+build).
const String kAppVersion = '1.6.7+3';

/// Compares versions like "1.6.7+3" or "4.0 Beta": main numbers first, then the
/// +build number; a "Beta" counts as older than the same release.
int _compareVersions(String a, String b) {
  List<int> nums(String v) => RegExp(r'\d+').allMatches(v.split('+').first)
      .map((m) => int.parse(m.group(0)!)).toList();
  int build(String v) =>
      v.contains('+') ? (int.tryParse(RegExp(r'\d+').firstMatch(v.split('+')[1])?.group(0) ?? '') ?? 0) : 0;
  final na = nums(a), nb = nums(b);
  for (int i = 0; i < max(na.length, nb.length); i++) {
    final x = i < na.length ? na[i] : 0;
    final y = i < nb.length ? nb[i] : 0;
    if (x != y) return x.compareTo(y);
  }
  final ba = a.toLowerCase().contains('beta'), bb = b.toLowerCase().contains('beta');
  if (ba != bb) return ba ? -1 : 1;
  return build(a).compareTo(build(b));
}

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  ErrorWidget.builder = (FlutterErrorDetails details) {
    return Material(
      color: const Color(0xFF1B1B1B),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, color: Color(0xFFFF4444), size: 48),
            const SizedBox(height: 12),
            const Text('HTML Runner crashed', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text(details.exceptionAsString(), style: const TextStyle(color: Color(0xFFAAAAAA), fontSize: 12, fontFamily: 'monospace'), textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  };

  runApp(const HTMLRunnerApp());
}

// -----------------------------------------------------------------------------
// SECTION 1: THEME & CONSTANTS
// -----------------------------------------------------------------------------

class AppColors {
  // ── Holo Dark (Theme.Holo.Dark) ──────────────────────────────────────────
  static const Color nostalgiaBlack   = Color(0xFF000000);
  static const Color holoPanelBg      = Color(0xFF1B1B1B);
  static const Color holoPanelBg2     = Color(0xFF262626);
  static const Color holoBlue         = Color(0xFF33B5E5);
  static const Color holoBlueDark     = Color(0xFF0099CC);
  static const Color holoDivider      = Color(0xFF3D3D3D);
  static const Color holoTextPrimary  = Color(0xFFFFFFFF);
  static const Color holoTextSecond   = Color(0xFFAAAAAA);
  // ── Holo Light (Theme.Holo.Light) ────────────────────────────────────────
  static const Color holoLightBg      = Color(0xFFF2F2F2);
  static const Color holoLightPanel   = Color(0xFFFFFFFF);
  static const Color holoLightPanel2  = Color(0xFFEBEBEB);
  static const Color holoLightDivider = Color(0xFFC8C8C8);
  static const Color holoLightTextPri = Color(0xFF1A1A1A);
  static const Color holoLightTextSec = Color(0xFF666666);
  // ── Shared ───────────────────────────────────────────────────────────────
  static const Color fishGangTeal     = Color(0xFF5FD4C7);
  static const Color androidGreen     = Color(0xFF99CC00);
  static const Color errorRed         = Color(0xFFFF4444);
  static const Color folderYellow     = Color(0xFFFFBB33);
  static const Color linkBlue         = Color(0xFF33B5E5);
  static const Color gutterGray       = Color(0xFF37474F);
  static const Color editorBackground = Color(0xFF1E1E1E);
  // ── Tutorial & WebRunner panel ────────────────────────────────────────────
  static const Color panelBg      = Color(0xE6000000);
  static const Color tutorialBg   = Color(0xFF1a1a2e);
  static const Color tutorialCard = Color(0xFF16213e);
}

class AppTextStyles {
  static const TextStyle appBarTitle = TextStyle(
    color: Colors.white,
    fontWeight: FontWeight.bold,
    fontSize: 20,
    letterSpacing: 0.5,
  );

  static const TextStyle codeFont = TextStyle(
    fontFamily: 'monospace',
    fontSize: 14,
    height: 1.5,
  );

  static const TextStyle warningText = TextStyle(
    color: AppColors.errorRed,
    fontSize: 13,
    fontWeight: FontWeight.w500,
  );
}

// -----------------------------------------------------------------------------
// SECTION 2: HELPERS (storage, paths, security code)
// -----------------------------------------------------------------------------

class StorageHelper {
  static Future<Directory> getBaseDirectory() async {
    final externalDir = await getExternalStorageDirectory();
    if (externalDir == null) throw Exception("Cannot access external storage");
    String path = externalDir.path;
    final androidIndex = path.indexOf('/Android/');
    if (androidIndex != -1) path = path.substring(0, androidIndex);
    final baseDir = Directory('$path/HTML Files');
    if (!await baseDir.exists()) await baseDir.create(recursive: true);
    return baseDir;
  }

  static Future<Directory> getFilesDirectory() async {
    final base = await getBaseDirectory();
    final dir  = Directory('${base.path}/Files');
    if (!await dir.exists()) await dir.create();
    return dir;
  }

  static Future<Directory> getZipsDirectory() async {
    final base = await getBaseDirectory();
    final dir  = Directory('${base.path}/ZIPs');
    if (!await dir.exists()) await dir.create();
    return dir;
  }

  static Future<String> getFilesPath() async => (await getFilesDirectory()).path;
  static Future<String> getZipsPath()  async => (await getZipsDirectory()).path;
}

/// FIX 35: projects/files live in JSON files in the app's documents dir
/// (atomic write: temp file + rename) instead of one giant SharedPreferences string.
class DataStore {
  static Future<File> _file(String name) async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/$name');
  }

  static Future<String?> read(String name) async {
    final f = await _file(name);
    if (await f.exists()) return f.readAsString();
    return null;
  }

  static Future<void> delete(String name) async {
    final f = await _file(name);
    if (await f.exists()) await f.delete();
  }

  static Future<void> write(String name, String data) async {
    final f   = await _file(name);
    final tmp = File('${f.path}.tmp');
    await tmp.writeAsString(data, flush: true);
    await tmp.rename(f.path);
  }
}

/// FIX 30: returns a cleaned relative path, or null if it tries to escape
/// the destination (".." segments).
String? _safeRelPath(String raw) {
  final parts = raw
      .replaceAll('\\', '/')
      .split('/')
      .where((p) => p.isNotEmpty && p != '.')
      .toList();
  if (parts.isEmpty || parts.any((p) => p == '..')) return null;
  return parts.join('/');
}

String _extOf(String name) =>
    name.contains('.') ? name.split('.').last.toLowerCase() : '';

/// FIX 32: random one-time security code. Stored in the app's private dir for
/// one hour and delivered as a real notification.
class SecurityCodeService {
  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  static bool _inited = false;
  static const int _notifId = 5528;

  static Future<void> _init() async {
    if (_inited) return;
    const android = AndroidInitializationSettings('notification_icon');
    await _plugin.initialize(
      const InitializationSettings(android: android),
      onDidReceiveNotificationResponse: UploadNotifier.handleResponse,
    );
    _inited = true;
  }

  static Future<File> _file() async {
    final dir = await getApplicationSupportDirectory(); // app-private
    return File('${dir.path}/security_code.json');
  }

  static String _generate() =>
      (100000 + Random.secure().nextInt(900000)).toString();

  /// Creates a new code, saves it for 1 hour and posts the notification.
  /// Returns false if notifications are not allowed (code is discarded).
  static Future<bool> issue() async {
    final code = _generate();
    final f = await _file();
    await f.writeAsString(
      jsonEncode({
        'code': code,
        'expires': DateTime.now().add(const Duration(hours: 1)).millisecondsSinceEpoch,
      }),
      flush: true,
    );

    final status = await Permission.notification.request();
    if (!status.isGranted) {
      await clear();
      return false;
    }
    await _init();
    final shown = '${code.substring(0, 3)}-${code.substring(3)}';
    await _plugin.show(
      _notifId,
      'HTML Runner security code',
      'Your verification code is $shown. It expires in 1 hour.',
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'security_code_channel',
          'Security codes',
          channelDescription: 'One-time codes for Sign Out / Reset',
          importance: Importance.max,
          priority: Priority.high,
          icon: 'notification_icon',
          timeoutAfter: 3600000,
        ),
      ),
    );
    return true;
  }

  static Future<bool> verify(String input) async {
    try {
      final f = await _file();
      if (!await f.exists()) return false;
      final data = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
      final expires = data['expires'] as int;
      if (DateTime.now().millisecondsSinceEpoch > expires) {
        await clear();
        return false;
      }
      final digits = input.replaceAll(RegExp(r'\D'), '');
      if (digits == data['code']) {
        await clear();
        return true;
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  static Future<void> clear() async {
    try {
      final f = await _file();
      if (await f.exists()) await f.delete();
      if (_inited) await _plugin.cancel(_notifId);
    } catch (_) {}
  }
}

// =============================================================================
// BIG-FILE UPLOAD (files > 1 MB): progress screen + background notification
// =============================================================================

String _fmtBytes(int b) {
  if (b < 1024) return '$b B';
  if (b < 1024 * 1024) return '${(b / 1024).toStringAsFixed(1)} KB';
  return '${(b / (1024 * 1024)).toStringAsFixed(1)} MB';
}

class _ZipImport {
  final List<FileModel> files;
  final Set<String> folders;
  final int skipped;
  final Directory projDir;
  _ZipImport(this.files, this.folders, this.skipped, this.projDir);
}

/// Streams [src] into [dest] (binary files) or into memory (text files),
/// reporting progress and supporting cancel.
class TransferTask {
  final String fileName;
  final String src;
  final String? dest;   // null -> keep the bytes in memory (text files)
  final int total;

  final ValueNotifier<double> progress = ValueNotifier<double>(0);
  bool cancelled = false;
  bool inBackground = false;
  Future<void> Function()? onBackground;
  bool screenOpen = false; // is the progress screen currently visible?
  Uint8List? result;    // bytes of text files

  final Completer<void> _done = Completer<void>();
  final BytesBuilder _bytes = BytesBuilder(copy: false);
  StreamSubscription<List<int>>? _sub;
  IOSink? _sink;
  int _read = 0;

  TransferTask({
    required this.fileName,
    required this.src,
    required this.dest,
    required this.total,
  });

  Future<void> get future => _done.future;

  /// For work that isn't a plain file copy (ZIP extraction): the caller drives
  /// [progress] itself and calls finish()/fail() when done.
  void finish() {
    progress.value = 1.0;
    if (!_done.isCompleted) _done.complete();
  }

  void fail(Object e) {
    if (!_done.isCompleted) _done.completeError(e);
  }

  void start() {
    if (dest != null) _sink = File(dest!).openWrite();
    _sub = File(src).openRead().listen(
      (chunk) {
        _read += chunk.length;
        if (_sink != null) {
          _sink!.add(chunk);
        } else {
          _bytes.add(chunk);
        }
        progress.value = total == 0 ? 1.0 : (_read / total).clamp(0.0, 1.0);
      },
      onDone: () async {
        try {
          await _sink?.flush();
          await _sink?.close();
          if (dest == null) result = _bytes.takeBytes();
          progress.value = 1.0;
          if (!_done.isCompleted) _done.complete();
        } catch (e) {
          if (!_done.isCompleted) _done.completeError(e);
        }
      },
      onError: (Object e) async {
        await _abort();
        if (!_done.isCompleted) _done.completeError(e);
      },
      cancelOnError: true,
    );
  }

  Future<void> cancel() async {
    if (_done.isCompleted) return;
    cancelled = true;
    await _sub?.cancel();
    await _abort();
    if (!_done.isCompleted) _done.complete();
  }

  Future<void> _abort() async {
    try {
      await _sink?.close();
      if (dest != null) {
        final f = File(dest!);
        if (await f.exists()) await f.delete(); // remove the partial file
      }
    } catch (_) {}
  }
}

/// Progress notification: "Uploading {file_name}... {n} %" with a progress bar.
class UploadNotifier {
  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  static bool _inited = false;
  static final Map<int, int> _lastPct = {};

  /// Set by the dashboard: opens the progress screen of the upload with [id].
  static void Function(int id)? onOpen;

  /// Notification tapped. The payload of a progress notification is its id.
  static void handleResponse(NotificationResponse response) {
    final id = int.tryParse(response.payload ?? '');
    if (id != null) onOpen?.call(id);
  }

  static Future<void> init() => _init();

  static Future<void> _init() async {
    if (_inited) return;
    const android = AndroidInitializationSettings('notification_icon');
    await _plugin.initialize(
      const InitializationSettings(android: android),
      onDidReceiveNotificationResponse: handleResponse,
    );
    _inited = true;
  }

  static Future<bool> ensurePermission() async =>
      (await Permission.notification.request()).isGranted;

  static AndroidNotificationDetails _details({bool progress = false, int pct = 0}) =>
      AndroidNotificationDetails(
        'upload_channel',
        'Uploads',
        channelDescription: 'Progress of large file uploads',
        importance: Importance.low,
        priority: Priority.low,
        icon: 'notification_icon',
        showProgress: progress,
        maxProgress: 100,
        progress: pct,
        onlyAlertOnce: true,
        ongoing: progress,
        autoCancel: !progress,
      );

  static Future<void> progress(int id, String name, int pct) async {
    if (_lastPct[id] == pct) return; // only when the number changes
    _lastPct[id] = pct;
    await _init();
    await _plugin.show(
      id,
      'Uploading $name... $pct %',
      null,
      NotificationDetails(android: _details(progress: true, pct: pct)),
      payload: id.toString(),
    );
  }

  static Future<void> done(int id, String name) async {
    _lastPct.remove(id);
    await _init();
    await _plugin.show(
      id,
      'Upload complete',
      '$name was added',
      NotificationDetails(android: _details()),
    );
  }

  static Future<void> cancel(int id) async {
    _lastPct.remove(id);
    if (_inited) await _plugin.cancel(id);
  }
}

class UploadProgressScreen extends StatefulWidget {
  final TransferTask task;
  const UploadProgressScreen({Key? key, required this.task}) : super(key: key);

  @override
  State<UploadProgressScreen> createState() => _UploadProgressScreenState();
}

class _UploadProgressScreenState extends State<UploadProgressScreen> {
  bool _closed = false;

  @override
  void initState() {
    super.initState();
    widget.task.screenOpen = true;
    // finished (or failed) while this screen is open -> close it
    widget.task.future.then((_) => _close(), onError: (_) => _close());
  }

  @override
  void dispose() {
    widget.task.screenOpen = false;
    super.dispose();
  }

  void _close() {
    if (_closed || !mounted) return;
    _closed = true;
    Navigator.of(context).pop();
  }

  void _background() {
    widget.task.inBackground = true;
    widget.task.onBackground?.call();
    _close();
  }

  Future<void> _cancel() async {
    await widget.task.cancel();
    _close();
  }

  @override
  Widget build(BuildContext context) {
    final task = widget.task;
    return WillPopScope(
      // the back button behaves like "Run in Background"
      onWillPop: () async {
        _background();
        return false;
      },
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: Colors.black,
          automaticallyImplyLeading: false,
          title: const Text('Uploading'),
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: ValueListenableBuilder<double>(
              valueListenable: task.progress,
              builder: (context, value, _) {
                final pct = (value * 100).floor();
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Icon(Icons.cloud_upload, size: 56, color: AppColors.linkBlue),
                    const SizedBox(height: 16),
                    Text(task.fileName,
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    Text(_fmtBytes(task.total),
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
                    const SizedBox(height: 24),
                    LinearProgressIndicator(
                      value: value,
                      minHeight: 10,
                      backgroundColor: Colors.grey.shade800,
                      valueColor: const AlwaysStoppedAnimation<Color>(AppColors.linkBlue),
                    ),
                    const SizedBox(height: 10),
                    Text('$pct %',
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 28),
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton(
                            onPressed: _background,
                            child: const Text('Run in Background'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: _cancel,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.red.shade700,
                              foregroundColor: Colors.white,
                            ),
                            child: const Text('Cancel'),
                          ),
                        ),
                      ],
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

// =============================================================================
// TUTORIAL
// =============================================================================

class TutorialItem {
  final IconData  icon;
  final String    title;
  final String    description;
  final List<String> steps;
  const TutorialItem({required this.icon, required this.title,
    required this.description, required this.steps});
}

class TutorialCard extends StatelessWidget {
  final TutorialItem item;
  const TutorialCard({Key? key, required this.item}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          Container(
            width: 80, height: 80,
            decoration: BoxDecoration(
              color: AppColors.linkBlue.withOpacity(0.2),
              shape: BoxShape.circle,
            ),
            child: Icon(item.icon, size: 40, color: AppColors.linkBlue),
          ),
          const SizedBox(height: 20),
          Text(item.title,
            style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: Colors.white),
            textAlign: TextAlign.center),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.tutorialCard,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.linkBlue.withOpacity(0.3)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text("📝 What is this?",
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.linkBlue)),
                const SizedBox(height: 8),
                Text(item.description,
                  style: const TextStyle(color: Colors.white70, height: 1.5)),
                const SizedBox(height: 20),
                const Text("📋 Step-by-Step:",
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.linkBlue)),
                const SizedBox(height: 12),
                ...item.steps.asMap().entries.map((e) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Container(
                      width: 24, height: 24,
                      decoration: const BoxDecoration(color: AppColors.linkBlue, shape: BoxShape.circle),
                      child: Center(child: Text("${e.key + 1}",
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12))),
                    ),
                    const SizedBox(width: 12),
                    Expanded(child: Text(e.value,
                      style: const TextStyle(color: Colors.white70, height: 1.4))),
                  ]),
                )),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.linkBlue.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Row(children: [
              Icon(Icons.lightbulb, color: AppColors.folderYellow, size: 20),
              SizedBox(width: 8),
              Expanded(child: Text(
                "💡 Access this tutorial anytime from ⚙️ Settings.",
                style: TextStyle(color: Colors.white70, fontSize: 12))),
            ]),
          ),
        ],
      ),
    );
  }
}

class TutorialScreen extends StatefulWidget {
  const TutorialScreen({Key? key}) : super(key: key);
  @override
  _TutorialScreenState createState() => _TutorialScreenState();
}

class _TutorialScreenState extends State<TutorialScreen> {
  int _currentPage = 0;
  final PageController _pageController = PageController();

  static const _items = [
    TutorialItem(
      icon: Icons.folder_open, title: "📁 Creating Projects",
      description: "Tap '+ Create Project' to start a new project.\n\nYou can import existing ZIP files as projects.\n\nProjects can have custom icons and descriptions.",
      steps: ["Tap '+ Create Project' on the dashboard", "Choose 'Make New Project' or 'Import ZIP'",
              "Enter project name and description", "Add existing files or start fresh", "Tap 'Create' to save"],
    ),
    TutorialItem(
      icon: Icons.create_new_folder, title: "📂 Files & Folders",
      description: "Create HTML files in your projects.\n\nUse '/' in filenames to create folders!\n\nExample: 'pages/about.html' creates a 'pages' folder.",
      steps: ["Open a project or go to Files section", "Tap '+ Create File'",
              "Enter filename (use / for folders)", "Write your HTML code", "Tap Save"],
    ),
    TutorialItem(
      icon: Icons.drive_file_move, title: "🔄 Moving Files & Folders",
      description: "Organize projects by moving files between folders.\n\nLong-press any file or folder to see options.",
      steps: ["Long-press a file or folder", "Select 'Move' from the menu",
              "Choose a destination folder", "Tap to confirm", "Item relocates instantly"],
    ),
    TutorialItem(
      icon: Icons.edit_document, title: "✏️ Editing Code",
      description: "The built-in editor has line numbers and a toolbar for quick HTML tags.\n\nSave your work with the 💾 button.",
      steps: ["Tap any file to open the editor", "Write or paste HTML/CSS/JS",
              "Use toolbar buttons for quick tags", "Tap 💾 Save", "Tap ▶️ Run to preview"],
    ),
    TutorialItem(
      icon: Icons.preview, title: "🌐 HTML Preview",
      description: "Preview HTML with a full WebView.\n\nButtons and scripts work like a real browser!\n\nTap ⚙️ for the floating keyboard toolkit.",
      steps: ["Open any HTML file and tap Run", "View your page in the WebView",
              "Tap ⚙️ for keyboard toolkit (great for games)", "Tap Refresh to reload", "Fullscreen mode available"],
    ),
    TutorialItem(
      icon: Icons.settings, title: "⚙️ Settings & Themes",
      description: "Customize your experience.\n\nSwitch between Light / Dark / System themes.\n\nManage permissions for privacy.",
      steps: ["Tap your profile avatar in the app bar", "Select ⚙️ Settings",
              "Change Theme", "Manage Permissions", "Download All Files to storage"],
    ),
    TutorialItem(
      icon: Icons.celebration, title: "🎮 Easter Eggs",
      description: "Tap the </> logo in the app bar 5 times to unlock Flappy Fish.\n\nMore secrets hidden throughout the app...",
      steps: ["Tap the </> logo 5× quickly", "Watch it spin 🌀",
              "Build info dialog appears", "Tap 'Play Flappy Fish'", "Try to beat the high score!"],
    ),
  ];

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.tutorialBg,
      appBar: AppBar(
        title: const Text("📖 HTML Runner Tutorial",
          style: TextStyle(color: Colors.white)),
        backgroundColor: AppColors.nostalgiaBlack,
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Skip", style: TextStyle(color: Colors.white70)),
          ),
        ],
      ),
      body: Column(
        children: [
          LinearProgressIndicator(
            value: (_currentPage + 1) / _items.length,
            backgroundColor: Colors.grey.shade800,
            valueColor: const AlwaysStoppedAnimation<Color>(AppColors.linkBlue),
          ),
          Expanded(
            child: PageView.builder(
              controller: _pageController,
              onPageChanged: (p) => setState(() => _currentPage = p),
              itemCount: _items.length,
              itemBuilder: (_, i) => TutorialCard(item: _items[i]),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                TextButton(
                  onPressed: _currentPage > 0 ? () => _pageController.previousPage(
                    duration: const Duration(milliseconds: 300), curve: Curves.easeInOut) : null,
                  child: const Text("← Prev", style: TextStyle(color: Colors.white70)),
                ),
                Row(
                  children: List.generate(_items.length, (i) => Container(
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    width: 8, height: 8,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _currentPage == i ? AppColors.linkBlue : Colors.grey.shade600,
                    ),
                  )),
                ),
                if (_currentPage < _items.length - 1)
                  TextButton(
                    onPressed: () => _pageController.nextPage(
                      duration: const Duration(milliseconds: 300), curve: Curves.easeInOut),
                    child: const Text("Next →", style: TextStyle(color: Colors.white70)),
                  )
                else
                  ElevatedButton(
                    onPressed: () => Navigator.pop(context),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.androidGreen,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                    ),
                    child: const Text("Get Started!"),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// DATA MODELS
// -----------------------------------------------------------------------------

class ProjectModel {
  String id;
  String name;
  String description;
  String? iconPath;
  String createdAt;
  String lastModified;
  List<FileModel> files;
  List<String>    folders;

  ProjectModel({
    required this.id,
    required this.name,
    this.description = "",
    this.iconPath,
    required this.createdAt,
    required this.lastModified,
    required this.files,
    List<String>? folders,
  }) : folders = folders ?? <String>[];

  Map<String, dynamic> toJson() => {
    'id':       id,
    'name':     name,
    'desc':     description,
    'icon':     iconPath,
    'created':  createdAt,
    'modified': lastModified,
    'files':    files.map((f) => f.toJson()).toList(),
    'folders':  folders,
  };

  factory ProjectModel.fromJson(Map<String, dynamic> json) => ProjectModel(
    id:           json['id'],
    name:         json['name'],
    description:  json['desc'] ?? "",
    iconPath:     json['icon'],
    createdAt:    json['created'] ?? "Unknown",
    lastModified: json['modified'] ?? "Unknown",
    files:   (json['files'] as List).map((f) => FileModel.fromJson(f)).toList(),
    folders: List<String>.from(json['folders'] ?? []),
  );

  static String _now() => DateFormat('HH:mm').format(DateTime.now());

  // ── Folder helpers ──────────────────────────────────────────────────────

  List<FileModel> getFilesInFolder(String folderPath) =>
      files.where((f) => f.path == folderPath).toList();

  // FIX 8: real interpolation ('$parentPath/'), not the literal text.
  List<String> getSubfolders(String parentPath) => folders.where((folder) {
    if (parentPath.isEmpty) return !folder.contains('/');
    return folder.startsWith('$parentPath/') &&
        !folder.substring(parentPath.length + 1).contains('/');
  }).toList();

  /// Makes sure [path] and all of its ancestors exist in [folders].
  void ensureFolder(String path) {
    if (path.isEmpty) return;
    String cur = "";
    for (final part in path.split('/')) {
      cur = cur.isEmpty ? part : '$cur/$part';
      if (!folders.contains(cur)) folders.add(cur);
    }
  }

  /// Create a file at "pages/about.html" — auto-creates parent folders.
  void addFileWithPath(String fileNameWithPath, String content) {
    String path = "";
    String fileName = fileNameWithPath;
    if (fileNameWithPath.contains('/')) {
      path     = fileNameWithPath.substring(0, fileNameWithPath.lastIndexOf('/'));
      fileName = fileNameWithPath.substring(fileNameWithPath.lastIndexOf('/') + 1);
      ensureFolder(path);
    }
    files.add(FileModel(
      id:       DateTime.now().millisecondsSinceEpoch.toString(),
      name:     fileName,
      content:  content,
      lastEdit: _now(),
      path:     path,
    ));
  }

  void moveFile(FileModel file, String newPath) {
    files.remove(file);
    file.path     = newPath;
    file.lastEdit = _now();
    files.add(file);
    ensureFolder(newPath);
  }

  void relocateFolder(String oldPath, String newPath) {
    String remap(String p) {
      if (p == oldPath) return newPath;
      if (p.startsWith('$oldPath/')) return newPath + p.substring(oldPath.length);
      return p;
    }
    for (final f in files) {
      final np = remap(f.path);
      if (np != f.path) {
        f.path = np;
        f.lastEdit = _now();
      }
    }
    folders = folders.map(remap).toSet().toList();
    ensureFolder(newPath);
  }

  /// Moves a folder INTO [newParent] — keeps the folder's own name.
  void moveFolder(String oldPath, String newParent) {
    final name = oldPath.split('/').last;
    relocateFolder(oldPath, newParent.isEmpty ? name : '$newParent/$name');
  }

  void renameFile(FileModel file, String newNameWithPath) {
    String newPath = "";
    String newName = newNameWithPath;
    if (newNameWithPath.contains('/')) {
      newPath = newNameWithPath.substring(0, newNameWithPath.lastIndexOf('/'));
      newName = newNameWithPath.substring(newNameWithPath.lastIndexOf('/') + 1);
      ensureFolder(newPath);
    }
    file.name     = newName;
    file.path     = newPath;
    file.lastEdit = _now();
  }
}

class FileModel {
  String id;
  String name;
  String content;
  String lastEdit;
  String path;         // virtual folder path within a project, e.g. "pages"
  String? externalPath; // real fs path — for imported binary files (images, etc.)

  FileModel({
    required this.id,
    required this.name,
    required this.content,
    required this.lastEdit,
    this.path = "",
    this.externalPath,
  });

  /// Opened in the full code editor (and runnable).
  static const ideExts  = {'html', 'htm', 'html3', 'css', 'js'};
  /// Plain-text files opened in the small black edit box.
  static const textExts = {'txt', 'json', 'xml', 'svg', 'md'};

  String get ext => _extOf(name);

  /// Binary files (images, pdfs, etc.) — open via Android "Open with..."
  bool get isBinary => externalPath != null;

  bool get isIdeFile => !isBinary && ideExts.contains(ext);

  /// Anything that can be edited inside the app (IDE or the small text box).
  bool get isEditable => !isBinary;

  String get fullPath => path.isEmpty ? name : '$path/$name';

  Map<String, dynamic> toJson() => {
    'id':           id,
    'name':         name,
    'content':      content,
    'lastEdit':     lastEdit,
    'path':         path,
    'externalPath': externalPath,
  };

  factory FileModel.fromJson(Map<String, dynamic> json) => FileModel(
    id:           json['id'],
    name:         json['name'],
    content:      json['content'] ?? '',
    lastEdit:     json['lastEdit'] ?? '',
    path:         json['path'] ?? '',
    externalPath: json['externalPath'],
  );
}

// -----------------------------------------------------------------------------
// SECTION 3: CORE APP WIDGET
// -----------------------------------------------------------------------------

class HTMLRunnerApp extends StatefulWidget {
  const HTMLRunnerApp({Key? key}) : super(key: key);

  @override
  _HTMLRunnerAppState createState() => _HTMLRunnerAppState();
}

class _HTMLRunnerAppState extends State<HTMLRunnerApp> {
  ThemeMode _themeMode = ThemeMode.dark; // default to Holo Dark

  @override
  void initState() {
    super.initState();
    _loadThemePreference();
    _createReadmeFile();
    // FIX 3 / 36: tutorial + storage setup now live in MainDashboard
    // (this widget sits ABOVE MaterialApp, so it has no Navigator).
  }

  Future<void> _createReadmeFile() async {
    try {
      final directory = await getExternalStorageDirectory();
      if (directory == null) return;
      final readmeFile = File('${directory.path}/App Data/README.txt');
      await readmeFile.parent.create(recursive: true);
      if (!await readmeFile.exists()) {
        const content =
          "# HTML Runner v1.6.7\n"
          "A local HTML IDE with projects, folders, and a code editor.\n\n"
          "## Exported files\n"
          "  HTML Files/Files/   — individual downloaded HTML files\n"
          "  HTML Files/ZIPs/    — exported project ZIP archives\n\n"
          "## License\n"
          "MIT License — credit: Chirag Shylendra (@chirag7gaming)\n";
        await readmeFile.writeAsString(content);
      }
    } catch (e) {
      debugPrint('README write error: $e');
    }
  }

  Future<void> _loadThemePreference() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final idx = (prefs.getInt('theme_pref') ?? 2).clamp(0, ThemeMode.values.length - 1);
      if (!mounted) return;
      setState(() => _themeMode = ThemeMode.values[idx]);
    } catch (e) {
      debugPrint('Error loading theme: $e');
    }
  }

  Future<void> _updateTheme(ThemeMode mode) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('theme_pref', mode.index);
    } catch (e) {
      debugPrint('Error saving theme: $e');
    }
    if (!mounted) return;
    setState(() => _themeMode = mode);
  }

  @override
  Widget build(BuildContext context) {
    // ── Theme.Holo.Dark ───────────────────────────────────────────────────
    final holoDark = ThemeData(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: AppColors.nostalgiaBlack,
      canvasColor: AppColors.nostalgiaBlack,
      cardColor: AppColors.holoPanelBg,
      dividerColor: AppColors.holoDivider,
      primaryColor: AppColors.holoBlue,
      colorScheme: const ColorScheme.dark(
        primary: AppColors.holoBlue,
        secondary: AppColors.fishGangTeal,
        surface: AppColors.holoPanelBg,
        background: AppColors.nostalgiaBlack,
        error: AppColors.errorRed,
        onPrimary: Colors.black,
        onSecondary: Colors.black,
        onSurface: AppColors.holoTextPrimary,
        onBackground: AppColors.holoTextPrimary,
        onError: Colors.white,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.nostalgiaBlack,
        elevation: 0,
        foregroundColor: AppColors.holoTextPrimary,
        iconTheme: IconThemeData(color: AppColors.holoTextPrimary),
        titleTextStyle: AppTextStyles.appBarTitle,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.holoPanelBg2,
        labelStyle: const TextStyle(color: AppColors.holoTextSecond),
        hintStyle: const TextStyle(color: AppColors.holoTextSecond),
        border: OutlineInputBorder(
          borderSide: const BorderSide(color: AppColors.holoDivider),
          borderRadius: BorderRadius.circular(2),
        ),
        enabledBorder: OutlineInputBorder(
          borderSide: const BorderSide(color: AppColors.holoDivider),
          borderRadius: BorderRadius.circular(2),
        ),
        focusedBorder: OutlineInputBorder(
          borderSide: const BorderSide(color: AppColors.holoBlue, width: 2),
          borderRadius: BorderRadius.circular(2),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.holoBlue,
          foregroundColor: Colors.black,
          shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
          elevation: 0,
          textStyle: const TextStyle(fontWeight: FontWeight.bold, letterSpacing: 0.5),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: AppColors.holoBlue),
      ),
      listTileTheme: const ListTileThemeData(
        textColor: AppColors.holoTextPrimary,
        iconColor: AppColors.holoTextSecond,
      ),
      dividerTheme: const DividerThemeData(color: AppColors.holoDivider, thickness: 1),
      useMaterial3: false,
    );

    // ── Theme.Holo.Light (dark action bar) ────────────────────────────────
    final holoLight = ThemeData(
      brightness: Brightness.light,
      scaffoldBackgroundColor: AppColors.holoLightBg,
      canvasColor: AppColors.holoLightBg,
      cardColor: AppColors.holoLightPanel,
      dividerColor: AppColors.holoLightDivider,
      primaryColor: AppColors.holoBlueDark,
      colorScheme: const ColorScheme.light(
        primary: AppColors.holoBlueDark,
        secondary: AppColors.fishGangTeal,
        surface: AppColors.holoLightPanel,
        background: AppColors.holoLightBg,
        error: AppColors.errorRed,
        onPrimary: Colors.white,
        onSecondary: Colors.black,
        onSurface: AppColors.holoLightTextPri,
        onBackground: AppColors.holoLightTextPri,
        onError: Colors.white,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.nostalgiaBlack,
        elevation: 0,
        foregroundColor: AppColors.holoTextPrimary,
        iconTheme: IconThemeData(color: AppColors.holoTextPrimary),
        titleTextStyle: AppTextStyles.appBarTitle,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.holoLightPanel,
        labelStyle: const TextStyle(color: AppColors.holoLightTextSec),
        hintStyle: const TextStyle(color: AppColors.holoLightTextSec),
        border: OutlineInputBorder(
          borderSide: const BorderSide(color: AppColors.holoLightDivider),
          borderRadius: BorderRadius.circular(2),
        ),
        enabledBorder: OutlineInputBorder(
          borderSide: const BorderSide(color: AppColors.holoLightDivider),
          borderRadius: BorderRadius.circular(2),
        ),
        focusedBorder: OutlineInputBorder(
          borderSide: const BorderSide(color: AppColors.holoBlueDark, width: 2),
          borderRadius: BorderRadius.circular(2),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.holoBlueDark,
          foregroundColor: Colors.white,
          shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
          elevation: 0,
          textStyle: const TextStyle(fontWeight: FontWeight.bold, letterSpacing: 0.5),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: AppColors.holoBlueDark),
      ),
      listTileTheme: const ListTileThemeData(
        textColor: AppColors.holoLightTextPri,
        iconColor: AppColors.holoLightTextSec,
      ),
      dividerTheme: const DividerThemeData(color: AppColors.holoLightDivider, thickness: 1),
      useMaterial3: false,
    );

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'HTML Runner',
      theme: holoLight,
      darkTheme: holoDark,
      themeMode: _themeMode,
      home: MainDashboard(onThemeChange: _updateTheme),
    );
  }
}

// -----------------------------------------------------------------------------
// FISH GANG AUTH: User model
// -----------------------------------------------------------------------------

class FishGangUser {
  final String uid;
  final String email;
  final String? displayName;

  FishGangUser({required this.uid, required this.email, this.displayName});

  /// Initials for avatar (e.g. "CS" from "Chirag Shylendra" or "C" from email)
  String get initials {
    if (displayName != null && displayName!.trim().isNotEmpty) {
      final parts = displayName!.trim().split(' ').where((p) => p.isNotEmpty).toList();
      if (parts.length >= 2) return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
      return parts[0][0].toUpperCase();
    }
    return email[0].toUpperCase();
  }
}

// -----------------------------------------------------------------------------
// SECTION 4: MAIN DASHBOARD & LOGIC
// -----------------------------------------------------------------------------

class MainDashboard extends StatefulWidget {
  final Function(ThemeMode) onThemeChange;
  const MainDashboard({required this.onThemeChange});

  @override
  _MainDashboardState createState() => _MainDashboardState();
}

class _MainDashboardState extends State<MainDashboard> with TickerProviderStateMixin {
  // Fish Gang Auth controllers
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  bool _isSigningIn = false;
  bool _obscurePassword = true;

  // First-run permissions gate
  bool _permsDone = false;

  // State Variables
  FishGangUser? _currentUser;
  bool _isLocalMode = false;
  bool _isSyncing = false;
  List<Map<String,String>> _recentFiles = [];

  // move-file system
  ProjectModel? _activeProject;
  dynamic      _itemToMove;
  bool         _isMovingFile  = false;
  String       _movingItemName = '';
  String       _movingItemPath = '';

  // Data Storage
  List<ProjectModel> _projects = [];
  List<FileModel> _standaloneFiles = [];

  final ValueNotifier<int> _rev = ValueNotifier<int>(0);

  Future<void> _saveChain = Future.value();

  // uploads that are still running, by notification id
  final Map<int, TransferTask> _runningTasks = {};

  // Animation & Timers
  late AnimationController _refreshController;
  late AnimationController _logoSpinController;
  Timer? _syncTimer;

  // Warning States for Auth Screen
  bool _showLocalWarning = false;

  // --- Easter Egg State ---
  int _logoTapCount = 0;
  Timer? _tapResetTimer;
  bool _isLogoSpinning = false;
  Color _logoColor = Colors.white;

  // --- Version comparison for update checking ---
  bool _isNewerVersion(String current, String latest) =>
      _compareVersions(latest, current) > 0;

  @override
  void initState() {
    super.initState();
    _refreshController = AnimationController(vsync: this, duration: const Duration(seconds: 2));
    _logoSpinController = AnimationController(vsync: this, duration: const Duration(seconds: 7));

    _initializeAuth();
    _loadData();

    // notification taps -> upload screen (initialised now so the tap callback exists)
    UploadNotifier.onOpen = _openUploadScreen;
    UploadNotifier.init().catchError((_) {});

    WidgetsBinding.instance.addPostFrameCallback((_) => _checkFirstLaunch());

    _syncTimer = Timer.periodic(const Duration(minutes: 10), (timer) {
      _triggerSync();
    });
  }

  @override
  void dispose() {
    UploadNotifier.onOpen = null;
    _refreshController.dispose();
    _syncTimer?.cancel();
    _logoSpinController.dispose();
    _tapResetTimer?.cancel();
    _emailController.dispose();
    _passwordController.dispose();
    _rev.dispose();
    super.dispose();
  }

  // --- INITIALIZATION ---

  Future<void> _checkFirstLaunch() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final seen  = prefs.getBool('has_seen_tutorial') ?? false;
      if (!seen && mounted) {
        await prefs.setBool('has_seen_tutorial', true);
        if (!mounted) return;
        Navigator.push(context, MaterialPageRoute(builder: (_) => const TutorialScreen()));
      }
    } catch (e) {
      debugPrint('First launch check failed: $e');
    }
  }

  /// after the permissions are granted.
  Future<void> _setupStorage() async {
    try {
      await StorageHelper.getBaseDirectory();
      await StorageHelper.getFilesDirectory();
      await StorageHelper.getZipsDirectory();
    } catch (e) {
      debugPrint('Storage setup error: $e');
    }
  }

  void _initializeAuth() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final permsDone = prefs.getBool('perms_done') ?? false;
      final uid   = prefs.getString('fg_uid');
      final email = prefs.getString('fg_email');
      if (!mounted) return;
      setState(() {
        _permsDone = permsDone;
        if (uid != null && email != null) {
          _currentUser = FishGangUser(
            uid: uid,
            email: email,
            displayName: prefs.getString('fg_name'),
          );
          _isLocalMode = false;
        }
      });
      if (permsDone) _setupStorage();
    } catch (e) {
      debugPrint('Auth restore failed: $e');
    }
  }

  /// Sign in with Fish Gang (Firebase Auth REST API — no SDK needed).
  Future<void> _signInWithFishGang() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text;
    if (email.isEmpty || password.isEmpty) {
      Fluttertoast.showToast(msg: "Please enter your email and password.");
      return;
    }
    setState(() => _isSigningIn = true);
    try {
      const apiKey = 'AIzaSyCFnf-0frEB7jSQhPLbDQxcm3Qgbi3o77M';
      final url = Uri.parse(
        'https://identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=$apiKey',
      );
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'email': email, 'password': password, 'returnSecureToken': true}),
      );
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      if (response.statusCode == 200) {
        final user = FishGangUser(
          uid: data['localId'] as String,
          email: data['email'] as String,
          displayName: data['displayName'] as String?,
        );
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('fg_uid', user.uid);
        await prefs.setString('fg_email', user.email);
        await prefs.setString('fg_token', data['idToken'] as String);
        if (user.displayName != null) await prefs.setString('fg_name', user.displayName!);
        if (!mounted) return;
        setState(() {
          _currentUser = user;
          _isLocalMode = false;
        });
        _emailController.clear();
        _passwordController.clear();
      } else {
        final msg = (data['error']?['message'] as String?) ?? 'Login failed';
        final friendly = msg.contains('EMAIL_NOT_FOUND') || msg.contains('INVALID_LOGIN_CREDENTIALS')
            ? 'Invalid email or password.'
            : msg.contains('INVALID_EMAIL')
                ? 'Please enter a valid email.'
                : msg.contains('TOO_MANY_ATTEMPTS')
                    ? 'Too many attempts. Try again later.'
                    : msg;
        Fluttertoast.showToast(msg: friendly);
      }
    } catch (e) {
      Fluttertoast.showToast(msg: "Sign-in error: $e");
    } finally {
      if (mounted) setState(() => _isSigningIn = false);
    }
  }

  // --- UPDATE CHECK (REAL) ---
  Future<void> _checkForUpdates() async {
    const currentVersion = kAppVersion;
    const pageUrl = "https://fish-gang.netlify.app/appstore%E2%89%A0data=html_runner";

    try {
      final response = await http.get(Uri.parse(pageUrl));
      if (!mounted) return;
      if (response.statusCode == 200) {
        final versionRegex = RegExp(r'<span id="fg-version"[^>]*>(.*?)</span>');
        final versionMatch = versionRegex.firstMatch(response.body);

        if (versionMatch != null) {
          final latestVersion = versionMatch.group(1)!.trim();

          // download link: the entry for the latest version, then for the
          // current one, then the first .apk URL on the page
          String? downloadUrl;
          for (final key in [latestVersion, currentVersion]) {
            final m = RegExp("['\"]${RegExp.escape(key)}['\"]\\s*:\\s*['\"]([^'\"]+)['\"]")
                .firstMatch(response.body);
            if (m != null) { downloadUrl = m.group(1); break; }
          }
          downloadUrl ??= RegExp(r"""https?://[^'"\s]+\.apk""").firstMatch(response.body)?.group(0);

          if (!_isNewerVersion(currentVersion, latestVersion)) {
            _showUpToDateDialog();
          } else if (downloadUrl == null) {
            _showErrorDialog("Version $latestVersion is available, but no download link was found.");
          } else {
            _showUpdateDialog(downloadUrl, latestVersion);
          }
        } else {
          _showErrorDialog("Could not find version info.");
        }
      } else {
        _showErrorDialog("Could not reach update server.");
      }
    } catch (e) {
      if (mounted) _showErrorDialog("Network error. Check your connection.");
    }
  }

  void _showUpdateDialog(String url, String version) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text("🆙 Update Available"),
        content: Text("Version $version is ready to download."),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Later"),
          ),
          ElevatedButton(
            onPressed: () async {
              showDialog(
                context: context,
                barrierDismissible: false,
                builder: (context) => AlertDialog(
                  content: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const CircularProgressIndicator(),
                      const SizedBox(height: 16),
                      Text("Downloading version $version..."),
                    ],
                  ),
                ),
              );

              try {
                final appDir = await getApplicationDocumentsDirectory();
                final file = File('${appDir.path}/HTMLRunner_${version.replaceAll(' ', '_')}.apk');
                final request = await http.get(Uri.parse(url));
                await file.writeAsBytes(request.bodyBytes);
                if (!context.mounted) return;
                Navigator.pop(context); // close progress
                Navigator.pop(context); // close update dialog
                await OpenFile.open(file.path);
              } catch (e) {
                if (!context.mounted) return;
                Navigator.pop(context); // close progress
                _showErrorDialog("Download failed. Try again.");
              }
            },
            child: const Text("Update Now"),
          ),
        ],
      ),
    );
  }

  void _showUpToDateDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("✅ Up to Date"),
        content: const Text("You're running the latest version of HTML Runner."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("OK")),
        ],
      ),
    );
  }

  void _showErrorDialog(String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("⚠️ Update Check Failed"),
        content: Text(message),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("OK")),
        ],
      ),
    );
  }

  void _onLogoTap() {
    setState(() => _logoColor = AppColors.linkBlue);

    Future.delayed(const Duration(milliseconds: 100), () {
      if (mounted) setState(() => _logoColor = Colors.white);
    });

    _logoTapCount++;

    _tapResetTimer?.cancel();
    _tapResetTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => _logoTapCount = 0); // FIX 34
    });

    if (_logoTapCount >= 5) {
      _triggerEasterEgg();
      _logoTapCount = 0;
      _tapResetTimer?.cancel();
    }
  }

  void _triggerEasterEgg() {
    setState(() => _isLogoSpinning = true);
    _logoSpinController.repeat();

    Future.delayed(const Duration(seconds: 7), () {
      if (!mounted) return; // FIX 34
      _logoSpinController.stop();
      setState(() => _isLogoSpinning = false);
      _showBuildInfoDialog();
    });
  }

  void _showBuildInfoDialog() {
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Column(
          children: [
            Image.network(
              'https://i.postimg.cc/44BvYKKb/1771592172406.png',
              height: 60,
              fit: BoxFit.contain,
              errorBuilder: (context, error, stackTrace) {
                return Column(
                  children: [
                    Text(
                      "Fish Gang Co.",
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: AppColors.linkBlue,
                        fontFamily: 'monospace',
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      "(Image failed to load)",
                      style: TextStyle(fontSize: 10, color: Colors.grey),
                    ),
                  ],
                );
              },
            ),
            const SizedBox(height: 8),
            const Text("🛠️ Build Information", style: TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildInfoRow("📱", "App Name",    "HTML Runner"),
              _buildInfoRow("🔢", "Version",     kAppVersion),
              _buildInfoRow("📝", "Lines",       "5059 lines"),
              _buildInfoRow("🎨", "UI Style",    "Holo Inspired"),
              _buildInfoRow("💚", "Framework",   "Flutter/Dart"),
              _buildInfoRow("🔧", "SDK",         "Android SDK 36"),
              _buildInfoRow("📦", "Package",     "com.chirag.html_runner"),
              _buildInfoRow("👨‍💻", "Dev",         "Chirag Shylendra"),
              _buildInfoRow("🐙", "GitHub",      "@chirag7gaming"),
              _buildInfoRow("🌪️", "Company",     "Fish Gang"),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  children: [
                    const Text("🎮 ", style: TextStyle(fontSize: 16)),
                    const Text("Easter Egg: ",
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                    GestureDetector(
                      onTap: () {
                        Navigator.pop(context);
                        Navigator.push(context, MaterialPageRoute(
                          builder: (_) => const FlappyFishGame(),
                        ));
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                        decoration: BoxDecoration(
                          color: AppColors.linkBlue,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text("Play Flappy Fish",
                          style: TextStyle(color: Colors.white,
                            fontWeight: FontWeight.bold, fontSize: 12)),
                      ),
                    ),
                  ],
                ),
              ),
              _buildInfoRow("⚖️", "License",     "MIT License"),
              _buildInfoRow("💡", "Inspiration", "Black India Day and also 67"),
              const SizedBox(height: 8),
              const Text(
                "Made in 🇮🇳 with ❤️  •  Zero ads. Forever free. Forever Open-source.",
                style: TextStyle(fontStyle: FontStyle.italic, fontSize: 11),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Close", style: TextStyle(color: AppColors.androidGreen)),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(String emoji, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text("$emoji ", style: const TextStyle(fontSize: 16)),
          Expanded(
            child: RichText(
              text: TextSpan(
                style: TextStyle(fontSize: 13, color: Theme.of(context).colorScheme.onSurface),
                children: [
                  TextSpan(text: "$label: ", style: const TextStyle(fontWeight: FontWeight.bold)),
                  TextSpan(text: value),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // --- FILE OPERATIONS ---

  void _openWithSystem(FileModel file) async {
    final resolved = file.externalPath;
    if (resolved == null || resolved.isEmpty || !await File(resolved).exists()) {
      Fluttertoast.showToast(msg: "File not found — reimport it to open with another app");
      return;
    }
    final result = await OpenFile.open(resolved);
    if (result.type != ResultType.done) {
      Fluttertoast.showToast(msg: "No app found to open this file type");
    }
  }

  // --- IMPORT PROJECT ZIP (all file types) ---

  Future<void> _importProjectZip() async {
    try {
      final result = await FilePicker.platform.pickFiles(
          type: FileType.custom, allowedExtensions: ['zip']);
      if (result == null || result.files.single.path == null) return;

      final zipPath     = result.files.single.path!;
      final projectName = result.files.single.name.replaceAll('.zip', '');
      final projectId   = DateTime.now().millisecondsSinceEpoch.toString();
      final size        = await File(zipPath).length();

      // Files above 1 MB get the progress screen (cancel / run in background)
      TransferTask? task;
      Future<void>? tracking;
      if (size > _bigFileBytes) {
        task = TransferTask(
            fileName: result.files.single.name, src: zipPath, dest: null, total: size);
        tracking = _trackTask(task).catchError((_) {});
      }

      _ZipImport? data;
      try {
        data = await _extractZip(zipPath, projectId, task);
        task?.finish();
      } catch (e) {
        task?.fail(e);
        rethrow;
      } finally {
        if (tracking != null) await tracking;
      }

      if (data == null || (task?.cancelled ?? false)) {
        if (data != null) {
          try { await data.projDir.delete(recursive: true); } catch (_) {}
        }
        Fluttertoast.showToast(msg: 'Import of "$projectName" cancelled');
        return;
      }

      final extracted = data.files;
      if (extracted.isEmpty) {
        Fluttertoast.showToast(msg: 'No files found in ZIP',
            backgroundColor: AppColors.errorRed);
        return;
      }
      if (!mounted) return;
      setState(() {
        _projects.add(ProjectModel(
          id:           projectId,
          name:         projectName,
          description:  'Imported from ZIP',
          createdAt:    DateFormat('yyyy-MM-dd').format(DateTime.now()),
          lastModified: DateFormat('HH:mm').format(DateTime.now()),
          files:        extracted,
          folders:      data!.folders.toList(),
        ));
      });
      _saveData();
      final txt = extracted.where((f) => !f.isBinary).length;
      final bin = extracted.where((f) =>  f.isBinary).length;
      Fluttertoast.showToast(
          msg: 'Imported "$projectName": $txt text + $bin binary files'
              '${data.skipped > 0 ? ' (${data.skipped} unsafe entries skipped)' : ''}',
          backgroundColor: AppColors.androidGreen);
    } catch (e) {
      Fluttertoast.showToast(msg: 'Failed to import ZIP: $e');
    }
  }

  /// Reads + extracts a ZIP, reporting progress on [task] (if any):
  /// 0-20% reading the file, 25-100% extracting entries.
  /// Returns null if the user cancelled.
  Future<_ZipImport?> _extractZip(
      String zipPath, String projectId, TransferTask? task) async {
    bool cancelled() => task?.cancelled ?? false;

    final zipFile = File(zipPath);
    final size = await zipFile.length();

    final builder = BytesBuilder(copy: false);
    int read = 0;
    await for (final chunk in zipFile.openRead()) {
      if (cancelled()) return null;
      builder.add(chunk);
      read += chunk.length;
      if (task != null && size > 0) task.progress.value = 0.2 * read / size;
    }
    final archive = ZipDecoder().decodeBytes(builder.takeBytes());
    if (cancelled()) return null;
    task?.progress.value = 0.25;
    await Future.delayed(Duration.zero);

    // Destination for binary assets so they can be previewed / opened
    final baseDir = await StorageHelper.getFilesDirectory();
    final projDir = Directory('${baseDir.path}/$projectId');
    await projDir.create(recursive: true);

    final List<FileModel> extracted = [];
    final Set<String>     folders   = {};
    const editableExts = {'html','htm','html3','css','js','txt','json','xml','svg','md'};
    int skipped = 0;
    final total = archive.length;
    int index = 0;

    for (final entry in archive) {
      index++;
      if (cancelled()) {
        try { await projDir.delete(recursive: true); } catch (_) {}
        return null;
      }
      if (task != null) {
        task.progress.value = 0.25 + 0.75 * index / max(1, total);
        if (index % 5 == 0) await Future.delayed(Duration.zero); // let the UI repaint
      }
      if (!entry.isFile) continue;
      // reject "../" and absolute paths (zip-slip)
      final rawPath = _safeRelPath(entry.name);
      if (rawPath == null) { skipped++; continue; }
      final fileName = rawPath.split('/').last;
      if (fileName.startsWith('.') || rawPath.contains('__MACOSX')) continue;
      final folderPath = rawPath.contains('/')
          ? rawPath.substring(0, rawPath.lastIndexOf('/'))
          : '';
      if (folderPath.isNotEmpty) {
        String cur = '';
        for (final part in folderPath.split('/')) {
          cur = cur.isEmpty ? part : '$cur/$part';
          folders.add(cur);
        }
      }
      final bytes = entry.content as List<int>;
      final ext   = _extOf(fileName);
      if (editableExts.contains(ext)) {
        extracted.add(FileModel(
          id:       '${projectId}_${rawPath.hashCode}',
          name:     fileName,
          content:  utf8.decode(bytes, allowMalformed: true),
          lastEdit: DateFormat('HH:mm').format(DateTime.now()),
          path:     folderPath,
        ));
      } else {
        final subDir = folderPath.isNotEmpty
            ? Directory('${projDir.path}/$folderPath')
            : projDir;
        await subDir.create(recursive: true);
        final destPath = '${subDir.path}/$fileName';
        await File(destPath).writeAsBytes(bytes);
        extracted.add(FileModel(
          id:           '${projectId}_${rawPath.hashCode}',
          name:         fileName,
          content:      '',
          lastEdit:     DateFormat('HH:mm').format(DateTime.now()),
          path:         folderPath,
          externalPath: destPath,
        ));
      }
    }
    return _ZipImport(extracted, folders, skipped, projDir);
  }

  // --- FOLDER OPTIONS ---

  void _showFolderOptions(ProjectModel project, String folderPath) {
    showModalBottomSheet(
      context: context,
      builder: (_) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.drive_file_rename_outline),
            title: const Text("Rename Folder"),
            onTap: () { Navigator.pop(context); _renameFolder(project, folderPath); },
          ),
          ListTile(
            leading: const Icon(Icons.drive_folder_upload),
            title: const Text("Move Folder"),
            onTap: () { Navigator.pop(context); _startMoveFolder(project, folderPath); },
          ),
          ListTile(
            leading: const Icon(Icons.delete, color: AppColors.errorRed),
            title: const Text("Delete Folder", style: TextStyle(color: AppColors.errorRed)),
            onTap: () {
              Navigator.pop(context);
              _showDeleteConfirmation(() {
                setState(() {
                  project.files.removeWhere((f) =>
                      f.path == folderPath || f.path.startsWith('$folderPath/'));
                  project.folders.removeWhere((f) =>
                      f == folderPath || f.startsWith('$folderPath/'));
                });
                _saveData();
                Fluttertoast.showToast(msg: "Folder deleted");
              });
            },
          ),
        ],
      ),
    );
  }

  void _renameFolder(ProjectModel project, String oldPath) {
    final ctrl = TextEditingController(text: oldPath.split('/').last);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Rename Folder"),
        content: TextField(
          controller: ctrl, autofocus: true,
          decoration: const InputDecoration(
              labelText: "New folder name", border: OutlineInputBorder())),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Cancel")),
          ElevatedButton(
            onPressed: () {
              final newName = ctrl.text.trim();
              if (newName.isEmpty || newName.contains('/')) {
                Fluttertoast.showToast(msg: "Enter a folder name without '/'");
                return;
              }
              final parent  = oldPath.contains('/')
                  ? oldPath.substring(0, oldPath.lastIndexOf('/'))
                  : "";
              final newPath = parent.isEmpty ? newName : '$parent/$newName';
              if (newPath != oldPath && project.folders.contains(newPath)) {
                Fluttertoast.showToast(msg: "A folder with that name already exists");
                return;
              }
              setState(() => project.relocateFolder(oldPath, newPath));
              Navigator.pop(ctx);
              _saveData();
              Fluttertoast.showToast(msg: "Renamed to $newName");
            },
            child: const Text("Rename"),
          ),
        ],
      ),
    );
  }

  // --- MOVE FILE / FOLDER WITHIN PROJECT ---

  void _startMoveFile(ProjectModel project, FileModel file) {
    _activeProject  = project;
    _itemToMove     = file;
    _isMovingFile   = true;
    _movingItemName = file.name;
    _movingItemPath = file.path;
    _showMoveDestinationPicker();
  }

  void _startMoveFolder(ProjectModel project, String folderPath) {
    _activeProject  = project;
    _itemToMove     = folderPath;
    _isMovingFile   = false;
    _movingItemName = folderPath.split('/').last;
    _movingItemPath = folderPath;
    _showMoveDestinationPicker();
  }

  void _showMoveDestinationPicker() {
    final project = _activeProject;
    if (project == null) return;
    final movingFolder = !_isMovingFile;
    // Where the item currently lives (for "already in this location")
    final currentParent = _isMovingFile
        ? _movingItemPath
        : (_movingItemPath.contains('/')
            ? _movingItemPath.substring(0, _movingItemPath.lastIndexOf('/'))
            : '');
    final destinations = <String>[
      "(Root)",
      ...project.folders.where((d) =>
          !movingFolder ||
          (d != _movingItemPath && !d.startsWith('$_movingItemPath/'))),
    ];
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text("Move ${_isMovingFile ? 'File' : 'Folder'}: $_movingItemName"),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView(
            shrinkWrap: true,
            children: destinations.map((dest) {
              final targetPath = dest == "(Root)" ? "" : dest;
              return ListTile(
                leading: Icon(
                    dest == "(Root)" ? Icons.folder_open : Icons.folder,
                    color: AppColors.folderYellow),
                title: Text(dest == "(Root)" ? "Root Directory" : dest),
                onTap: () {
                  if (targetPath == currentParent) {
                    Navigator.pop(ctx);
                    Fluttertoast.showToast(msg: "Already in this location");
                    return;
                  }
                  if (_isMovingFile && _itemToMove is FileModel) {
                    project.moveFile(_itemToMove as FileModel, targetPath);
                  } else if (movingFolder && _itemToMove is String) {
                    final name = _movingItemPath.split('/').last;
                    final newPath = targetPath.isEmpty ? name : '$targetPath/$name';
                    if (project.folders.contains(newPath)) {
                      Navigator.pop(ctx);
                      Fluttertoast.showToast(msg: 'A folder named "$name" already exists there');
                      return;
                    }
                    project.moveFolder(_movingItemPath, targetPath);
                  }
                  Navigator.pop(ctx);
                  _saveData();
                  setState(() {});
                  Fluttertoast.showToast(msg: "Moved successfully!");
                },
              );
            }).toList(),
          ),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Cancel"))],
      ),
    );
  }

  /// Writes all project files (including binary assets) to a temp directory,
  /// then opens WebRunnerScreen using loadFile() so relative paths resolve.
  Future<void> _writeProjectToTempAndRun(
      ProjectModel project, FileModel mainFile, String? overrideContent) async {
    try {
      final tmpDir  = await getTemporaryDirectory();
      final projDir = Directory('${tmpDir.path}/htmlrunner_preview');
      if (await projDir.exists()) await projDir.delete(recursive: true);
      await projDir.create(recursive: true);

      for (final f in project.files) {
        final dest = File('${projDir.path}/${f.fullPath}');
        await dest.parent.create(recursive: true); // FIX 6
        if (f.isBinary && f.externalPath != null) {
          if (await File(f.externalPath!).exists()) {
            await File(f.externalPath!).copy(dest.path);
          }
        } else {
          final content = (overrideContent != null && f.id == mainFile.id)
              ? overrideContent
              : f.content;
          await dest.writeAsString(content);
        }
      }

      final mainInProject = project.files.any((f) => f.id == mainFile.id);
      final mainDest = File('${projDir.path}/${mainFile.fullPath}');
      await mainDest.parent.create(recursive: true);
      if (!mainInProject) {
        await mainDest.writeAsString(overrideContent ?? mainFile.content);
      }

      if (!mounted) return;
      Navigator.push(context, MaterialPageRoute(
        builder: (_) => WebRunnerScreen(filePath: mainDest.path),
      ));
    } catch (e) {
      Fluttertoast.showToast(msg: 'Preview failed: $e');
    }
  }

  void _trackRecentFile(FileModel file, {ProjectModel? project}) {
    final entry = {
      'id':       file.id,
      'name':     file.name,
      'project':  project?.name ?? '',
      'lastEdit': file.lastEdit,
    };
    _recentFiles.removeWhere((e) => e['id'] == file.id);
    _recentFiles.insert(0, entry);
    if (_recentFiles.length > 5) _recentFiles = _recentFiles.sublist(0, 5);
    SharedPreferences.getInstance().then((p) =>
        p.setString('recent_files', jsonEncode(_recentFiles)));
  }

  void _showFileCreationMenu({ProjectModel? project}) {
    final theme = Theme.of(context);
    showModalBottomSheet(
      context: context,
      backgroundColor: theme.scaffoldBackgroundColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Container(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40, height: 4,
              margin: const EdgeInsets.only(bottom: 20),
              decoration: BoxDecoration(
                color: Colors.grey[600],
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            const Text("New File Options",
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 20),
            ListTile(
              leading: const Icon(Icons.edit_document, color: AppColors.linkBlue),
              title: const Text("Create New HTML"),
              subtitle: const Text("Also supports .css  .js  .html3", style: TextStyle(fontSize: 11)),
              onTap: () {
                Navigator.pop(context);
                _openCodeEditor(null, project: project);
              },
            ),
            ListTile(
              leading: const Icon(Icons.file_open, color: AppColors.androidGreen),
              title: const Text("Import from Storage"),
              subtitle: const Text("HTML → IDE · Other files → system app", style: TextStyle(fontSize: 11)),
              onTap: () {
                Navigator.pop(context);
                _importAnyFile(project: project);
              },
            ),
            ListTile(
              leading: const Icon(Icons.folder_zip, color: AppColors.folderYellow),
              title: const Text("Import ZIP as Project"),
              subtitle: const Text("Extracts HTML files + folders from a .zip", style: TextStyle(fontSize: 11)),
              onTap: () {
                Navigator.pop(context);
                _importProjectZip();
              },
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  static const int _bigFileBytes = 1024 * 1024; // files above 1 MB get the progress screen

  /// Notification tapped: bring the upload's progress screen back.
  void _openUploadScreen(int id) {
    final task = _runningTasks[id];
    if (task == null || !mounted || task.screenOpen) return;
    task.inBackground = false; // visible again; "Run in Background" re-enables it
    Navigator.push(context, MaterialPageRoute(
      builder: (_) => UploadProgressScreen(task: task),
    ));
  }

  /// Shows the progress screen for [task] and keeps the background
  /// notification in sync. Completes when the task finishes, fails or is
  /// cancelled.
  Future<void> _trackTask(TransferTask task) async {
    final name = task.fileName;
    final notifId = 6000 + (DateTime.now().millisecondsSinceEpoch % 90000).toInt();
    bool notifOk = false;
    _runningTasks[notifId] = task; // lets a notification tap find this upload

    void onProgress() {
      if (task.inBackground && notifOk) {
        UploadNotifier.progress(notifId, name, (task.progress.value * 100).floor());
      }
    }

    task.progress.addListener(onProgress);
    task.onBackground = () async {
      notifOk = await UploadNotifier.ensurePermission();
      if (notifOk) {
        onProgress();
      } else {
        Fluttertoast.showToast(
            msg: "Notifications are blocked — the upload continues without a progress notification");
      }
    };

    if (mounted) {
      Navigator.push(context, MaterialPageRoute(
        builder: (_) => UploadProgressScreen(task: task),
      ));
    }

    try {
      await task.future;
    } catch (_) {
      _runningTasks.remove(notifId);
      task.progress.removeListener(onProgress);
      if (notifOk) await UploadNotifier.cancel(notifId);
      rethrow;
    }
    _runningTasks.remove(notifId);
    task.progress.removeListener(onProgress);
    if (task.inBackground && notifOk) {
      if (task.cancelled) {
        await UploadNotifier.cancel(notifId);
      } else {
        await UploadNotifier.done(notifId, name);
      }
    }
  }

  /// Copies [src] with a progress screen (cancel / run in background).
  Future<TransferTask> _runBigTransfer(
      String name, String src, String? dest, int size) async {
    final task = TransferTask(fileName: name, src: src, dest: dest, total: size);
    task.start();
    await _trackTask(task);
    return task;
  }

  Future<void> _importAnyFile({ProjectModel? project}) async {
    try {
      final result = await FilePicker.platform.pickFiles(type: FileType.any);
      if (result == null) return;
      final picked = result.files.first;
      final name   = picked.name;
      final path   = picked.path;
      if (path == null) { Fluttertoast.showToast(msg: "Could not get file path."); return; }

      final ext = _extOf(name);
      final id  = DateTime.now().millisecondsSinceEpoch.toString();
      final stamp = DateFormat('HH:mm').format(DateTime.now());
      final isText = FileModel.ideExts.contains(ext) || FileModel.textExts.contains(ext);
      final size = await File(path).length();

      // Binary files are copied into the app's own dir so a cache clean can't break them
      String? dest;
      if (!isText) {
        final docs = await getApplicationDocumentsDirectory();
        final dir  = Directory('${docs.path}/imports');
        await dir.create(recursive: true);
        dest = '${dir.path}/${id}_$name';
      }

      Uint8List? bytes;
      if (size > _bigFileBytes) {
        final task = await _runBigTransfer(name, path, dest, size);
        if (task.cancelled) {
          Fluttertoast.showToast(msg: 'Upload of "$name" cancelled');
          return;
        }
        bytes = task.result;
      } else if (isText) {
        bytes = await File(path).readAsBytes();
      } else {
        await File(path).copy(dest!);
      }

      final FileModel model = isText
          ? FileModel(
              id: id, name: name, lastEdit: stamp,
              content: utf8.decode(bytes!, allowMalformed: true),
            )
          : FileModel(
              id: id, name: name, content: '', lastEdit: stamp, externalPath: dest,
            );

      if (!mounted) return;
      setState(() {
        if (project != null) {
          project.files.add(model);
        } else {
          _standaloneFiles.add(model);
        }
      });
      _saveData();

      if (model.isBinary) {
        Fluttertoast.showToast(msg: "Added \"$name\" — tap to open with system");
      } else {
        Fluttertoast.showToast(msg: "Imported \"$name\"");
        _openCodeEditor(model, project: project);
      }
    } catch (e) {
      Fluttertoast.showToast(msg: "Import failed: $e");
    }
  }

  // --- DATA PERSISTENCE ---

  Future<bool> _saveData() async {
    _rev.value++;
    try {
      final projectsJson = jsonEncode(_projects.map((p) => p.toJson()).toList());
      final filesJson    = jsonEncode(_standaloneFiles.map((f) => f.toJson()).toList());
      final isLocal      = _isLocalMode;

      final job = _saveChain.then((_) async {
        await DataStore.write('projects_db.json', projectsJson);
        await DataStore.write('files_db.json', filesJson);
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool('is_local_mode', isLocal);
      });
      _saveChain = job.catchError((_) {}); // a failed write must not block later ones
      await job;
      return true;
    } catch (e) {
      Fluttertoast.showToast(msg: "Failed to save data: $e");
      debugPrint('Save error: $e');
      return false;
    }
  }

  Future<void> _loadData() async {
    final prefs = await SharedPreferences.getInstance();
    try {
      _isLocalMode = prefs.getBool('is_local_mode') ?? false;

      String? projectsJson = await DataStore.read('projects_db.json');
      String? filesJson    = await DataStore.read('files_db.json');
      bool migrate = false;

      // One-time migration from the old SharedPreferences storage
      if (projectsJson == null && filesJson == null) {
        projectsJson = prefs.getString('projects_db');
        filesJson    = prefs.getString('files_db');
        migrate = projectsJson != null || filesJson != null;
      }

      if (projectsJson != null) {
        _projects = (jsonDecode(projectsJson) as List)
            .map((m) => ProjectModel.fromJson(m as Map<String, dynamic>))
            .toList();
      }
      if (filesJson != null) {
        _standaloneFiles = (jsonDecode(filesJson) as List)
            .map((m) => FileModel.fromJson(m as Map<String, dynamic>))
            .toList();
      }
      if (migrate && await _saveData()) {
        await prefs.remove('projects_db');
        await prefs.remove('files_db');
      }
    } catch (e) {
      Fluttertoast.showToast(msg: "Failed to load data, starting fresh.");
      debugPrint('Load error: $e');
      _projects = [];
      _standaloneFiles = [];
    }
    try {
      final rf = prefs.getString('recent_files');
      if (rf != null) {
        _recentFiles = List<Map<String,String>>.from(
          (jsonDecode(rf) as List).map((e) => Map<String,String>.from(e)));
      }
    } catch (_) {}
    if (mounted) setState(() {});
  }

  /// "Sync" now writes the in-memory data to disk. It no longer re-reads and
  /// replaces every object (that left open editors / detail screens holding
  /// stale copies, so their edits were lost).
  Future<void> _triggerSync() async {
    if (_isSyncing || !mounted) return;

    setState(() => _isSyncing = true);
    _refreshController.repeat();

    await _saveData();
    await Future.delayed(const Duration(seconds: 1));

    if (!mounted) return; // FIX 34
    _refreshController.stop();
    setState(() => _isSyncing = false);

    Fluttertoast.showToast(
      msg: "Data Synced",
      backgroundColor: Colors.black,
      textColor: Colors.white,
    );
  }

  // --- IO OPERATIONS ---

  String _safeFileName(String s) => s.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');

  Future<void> _exportProjectZip(ProjectModel project) async {
    try {
      final archive = Archive();

      for (final file in project.files) {
        List<int> bytes;
        if (file.isBinary && file.externalPath != null) {
          final src = File(file.externalPath!);
          if (!await src.exists()) continue;
          bytes = await src.readAsBytes();
        } else {
          bytes = utf8.encode(file.content);
        }
        // fullPath keeps the folder structure inside the zip
        archive.addFile(ArchiveFile(file.fullPath, bytes.length, bytes));
      }

      var zipBytes = ZipEncoder().encode(archive);
      if (zipBytes == null) throw Exception("Zip encoding failed");

      final dir  = await StorageHelper.getZipsDirectory();
      final name = '${_safeFileName(project.name)}.zip';
      await File('${dir.path}/$name').writeAsBytes(zipBytes);

      Fluttertoast.showToast(msg: "Saved to HTML Files/ZIPs/$name");
    } catch (e) {
      Fluttertoast.showToast(msg: "Export Failed: $e");
    }
  }

  Future<void> _writeFileToDownloads(Directory dir, FileModel file) async {
    final dest = '${dir.path}/${_safeFileName(file.name)}';
    if (file.isBinary && file.externalPath != null) {
      final src = File(file.externalPath!);
      if (await src.exists()) await src.copy(dest);
    } else {
      await File(dest).writeAsString(file.content);
    }
  }

  Future<void> _downloadFile(FileModel file) async {
    try {
      final dir = await StorageHelper.getFilesDirectory();
      await _writeFileToDownloads(dir, file);
      Fluttertoast.showToast(msg: "Saved to HTML Files/Files/${file.name}");
    } catch (e) {
      Fluttertoast.showToast(msg: "Download failed: $e");
    }
  }

  Future<void> _downloadAllFiles() async {
    try {
      final dir = await StorageHelper.getFilesDirectory();
      int count = 0;
      for (final file in _standaloneFiles) {
        await _writeFileToDownloads(dir, file);
        count++;
      }
      Fluttertoast.showToast(msg: "Saved $count files to HTML Files/Files/");
    } catch (e) {
      Fluttertoast.showToast(msg: "Bulk download failed: $e");
    }
  }

  // --- UI BUILDING ---

  @override
  Widget build(BuildContext context) {
    bool isAuthenticated = _currentUser != null || _isLocalMode;

    Widget body;
    if (!_permsDone) {
      body = _buildPermissionsScreen();
    } else if (!isAuthenticated) {
      body = _buildAuthScreen();
    } else {
      body = _buildWorkspace();
    }

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: _buildNostalgicAppBar(),
      body: body,
    );
  }

  PreferredSizeWidget _buildNostalgicAppBar() {
    return AppBar(
      backgroundColor: Colors.black,
      elevation: 4.0,
      titleSpacing: 0,
      leading: GestureDetector(
        onTap: _onLogoTap,
        child: RotationTransition(
          turns: _isLogoSpinning ? _logoSpinController : const AlwaysStoppedAnimation(0),
          child: Icon(Icons.code, color: _logoColor),
        ),
      ),
      title: GestureDetector(
        onLongPress: _checkForUpdates,
        child: const Text("HTML Runner", style: AppTextStyles.appBarTitle),
      ),
      actions: [
        RotationTransition(
          turns: _refreshController,
          child: IconButton(
            icon: Icon(Icons.sync, color: _isSyncing ? AppColors.linkBlue : Colors.white),
            onPressed: _triggerSync,
          ),
        ),

        if (_currentUser != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8.0),
            child: CircleAvatar(
              radius: 14,
              backgroundColor: const Color(0xFF5FD4C7),
              child: Text(
                _currentUser!.initials,
                style: const TextStyle(
                  color: Colors.black,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),

        IconButton(
          icon: const Icon(Icons.settings, color: Colors.white),
          onPressed: _showSettingsSheet,
        ),
      ],
    );
  }

  // --- PERMISSIONS SCREEN (first run only) ---

  Future<void> _requestAllPermissions() async {
    try {
      await [
        Permission.storage,
        Permission.manageExternalStorage,
        Permission.photos,
      ].request();
    } catch (e) {
      debugPrint('Permission request error: $e');
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('perms_done', true);
    await _setupStorage(); // FIX 36: retry now that permissions exist
    if (!mounted) return;
    setState(() => _permsDone = true);
  }

  Widget _buildPermissionsScreen() {
    final _t     = Theme.of(context);
    final panel  = _t.cardColor;
    final panel2 = _t.colorScheme.surface;
    final div    = _t.dividerColor;
    final txtPri = _t.colorScheme.onSurface;
    final txtSec = _t.colorScheme.onSurface.withOpacity(0.6);

    final perms = [
      {'icon': Icons.folder_open,   'name': 'Storage',         'desc': 'Read and write files for your HTML projects and exports.'},
      {'icon': Icons.sd_storage,    'name': 'Manage Storage',  'desc': 'Access all files so HTML Runner can open projects from any folder.'},
      {'icon': Icons.photo_library, 'name': 'Photos / Media',  'desc': 'Insert images into your projects from your gallery.'},
    ];

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Container(
              width: double.infinity,
              decoration: BoxDecoration(
                color: panel,
                border: Border.all(color: div),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: double.infinity,
                    color: AppColors.holoBlue,
                    padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                    child: const Row(
                      children: [
                        Icon(Icons.security, color: Colors.black, size: 20),
                        SizedBox(width: 8),
                        Text("App Permissions",
                            style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 15)),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(14),
                    child: Text(
                      "HTML Runner needs these permissions to work. "
                      "You'll only see this screen once.",
                      style: TextStyle(color: txtSec, fontSize: 13),
                    ),
                  ),
                  for (final perm in perms) ...[
                    Container(
                      color: panel2,
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(perm['icon'] as IconData, color: AppColors.holoBlue, size: 28),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(perm['name'] as String, style: TextStyle(color: txtPri, fontWeight: FontWeight.bold, fontSize: 14)),
                                const SizedBox(height: 2),
                                Text(perm['desc'] as String, style: TextStyle(color: txtSec, fontSize: 12)),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    Divider(height: 1, color: div),
                  ],
                  Padding(
                    padding: const EdgeInsets.all(14),
                    child: SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.holoBlue,
                          foregroundColor: Colors.black,
                          shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
                          elevation: 0,
                        ),
                        onPressed: _requestAllPermissions,
                        child: const Text("Grant Permissions", style: TextStyle(fontWeight: FontWeight.bold)),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // --- AUTH UI ---
  Widget _buildAuthScreen() {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final panelBg   = isDark ? AppColors.holoPanelBg  : AppColors.holoLightPanel;
    final divider   = isDark ? AppColors.holoDivider   : AppColors.holoLightDivider;
    final textPri   = isDark ? AppColors.holoTextPrimary : AppColors.holoLightTextPri;
    final accent    = isDark ? AppColors.holoBlue      : AppColors.holoBlueDark;

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              decoration: BoxDecoration(
                color: panelBg,
                border: Border.all(color: divider),
              ),
              child: Column(
                children: [
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
                    color: AppColors.fishGangTeal,
                    child: Row(
                      children: const [
                        Icon(Icons.water, color: Colors.black, size: 20),
                        SizedBox(width: 8),
                        Text(
                          "Fish Gang Account",
                          style: TextStyle(
                            color: Colors.black,
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        TextField(
                          controller: _emailController,
                          keyboardType: TextInputType.emailAddress,
                          style: TextStyle(color: textPri),
                          decoration: const InputDecoration(
                            labelText: "Email",
                            prefixIcon: Icon(Icons.email_outlined),
                            isDense: true,
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _passwordController,
                          obscureText: _obscurePassword,
                          style: TextStyle(color: textPri),
                          onSubmitted: (_) => _signInWithFishGang(),
                          decoration: InputDecoration(
                            labelText: "Password",
                            prefixIcon: const Icon(Icons.lock_outline),
                            isDense: true,
                            suffixIcon: IconButton(
                              icon: Icon(_obscurePassword ? Icons.visibility_off : Icons.visibility),
                              onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        ElevatedButton(
                          onPressed: _isSigningIn ? null : _signInWithFishGang,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.fishGangTeal,
                            foregroundColor: Colors.black,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
                            elevation: 0,
                          ),
                          child: _isSigningIn
                              ? const SizedBox(
                                  height: 18, width: 18,
                                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black),
                                )
                              : const Text("Sign In", style: TextStyle(fontWeight: FontWeight.bold)),
                        ),
                        const SizedBox(height: 8),
                        Center(
                          child: TextButton(
                            onPressed: () {
                              Fluttertoast.showToast(
                                msg: "Register at fish-gang.netlify.app",
                                toastLength: Toast.LENGTH_LONG,
                              );
                            },
                            child: Text(
                              "No account? Register on Fish Gang ↗",
                              style: TextStyle(fontSize: 12, color: accent),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            _buildAuthOption(
              title: "Use Application Storage",
              isWarningVisible: _showLocalWarning,
              warningText: "Your Projects and Files are going to be saved in the app. Warning: If you delete the app and reinstall it, your data will be lost forever",
              onTap: () => setState(() => _showLocalWarning = true),
              onContinue: () async {
                setState(() => _isLocalMode = true);
                await _saveData();
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAuthOption({
    required String title,
    required bool isWarningVisible,
    required String warningText,
    required VoidCallback onTap,
    required VoidCallback onContinue,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final panelBg  = isDark ? AppColors.holoPanelBg  : AppColors.holoLightPanel;
    final panelBg2 = isDark ? AppColors.holoPanelBg2 : AppColors.holoLightPanel2;
    final divider  = isDark ? AppColors.holoDivider   : AppColors.holoLightDivider;
    final textPri  = isDark ? AppColors.holoTextPrimary : AppColors.holoLightTextPri;
    final textSec  = isDark ? AppColors.holoTextSecond  : AppColors.holoLightTextSec;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      decoration: BoxDecoration(
        color: panelBg,
        border: Border.all(color: divider),
      ),
      child: Column(
        children: [
          ListTile(
            title: Text(title, style: TextStyle(fontWeight: FontWeight.bold, color: textPri)),
            trailing: Icon(
              isWarningVisible ? Icons.expand_less : Icons.expand_more,
              color: textSec,
            ),
            onTap: onTap,
          ),
          if (isWarningVisible)
            Container(
              padding: const EdgeInsets.all(16),
              color: panelBg2,
              child: Column(
                children: [
                  Text(
                    warningText,
                    style: const TextStyle(color: AppColors.errorRed, fontSize: 13, fontWeight: FontWeight.w500),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.androidGreen,
                      foregroundColor: Colors.black,
                      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
                      elevation: 0,
                    ),
                    onPressed: onContinue,
                    child: const Text("Continue?", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  // --- WORKSPACE UI ---

  Widget _buildWorkspace() {
    return ListView(
      padding: const EdgeInsets.all(16.0),
      children: [
        _buildSectionHeader("+ Create Project", () => _showProjectWizard(null)),
        if (_projects.isEmpty)
          _buildEmptyIndicator("No Projects found."),

        ..._projects.map((p) => ProjectTile(
          project: p,
          onTap: () => _openProject(p),
          onLongPress: () => _showProjectOptions(p),
        )),

        const SizedBox(height: 32),

        _buildSectionHeader("+ Create File", () => _showFileCreationMenu()),
        if (_standaloneFiles.isEmpty)
          _buildEmptyIndicator("No Files Found."),

        ..._standaloneFiles.map((f) => FileTile(
          file: f,
          onTap: () => _openCodeEditor(f),
          onLongPress: () => _showFileOptions(f, null),
        )),
      ],
    );
  }

  Widget _buildSectionHeader(String title, VoidCallback onTap) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: InkWell(
        onTap: onTap,
        child: Text(
          title,
          style: const TextStyle(
            color: AppColors.linkBlue,
            fontSize: 22,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyIndicator(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16.0, left: 8.0),
      child: Text(
        text,
        style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withOpacity(0.45), fontStyle: FontStyle.italic),
      ),
    );
  }

  // --- NAVIGATION & DIALOGS ---

  void _showProjectWizard(ProjectModel? existing) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => ProjectWizardDialog(
        existingProject: existing,
        availableFiles: _standaloneFiles,
        onSave: (name, desc, iconPath, selectedFiles) {
          setState(() {
            if (existing == null) {
              _projects.add(ProjectModel(
                id: DateTime.now().millisecondsSinceEpoch.toString(),
                name: name,
                description: desc,
                iconPath: iconPath,
                createdAt: DateFormat('yyyy-MM-dd').format(DateTime.now()),
                lastModified: DateFormat('HH:mm').format(DateTime.now()),
                files: selectedFiles,
              ));
              Fluttertoast.showToast(msg: "Project Created");
            } else {
              existing.name = name;
              existing.description = desc;
              existing.iconPath = iconPath;
              existing.files = selectedFiles;
              existing.lastModified = DateFormat('HH:mm').format(DateTime.now());
              Fluttertoast.showToast(msg: "Edits Saved");
            }
          });
          _saveData();
        },
      ),
    );
  }

  void _openProject(ProjectModel project) {
    Navigator.push(context, MaterialPageRoute(
      builder: (context) => ProjectDetailScreen(
        project:           project,
        refresh:           _rev,
        onFileTap:         (f) => _openCodeEditor(f, project: project),
        onFileLongPress:   (f) => _showFileOptions(f, project),
        onFolderLongPress: (folder) => _showFolderOptions(project, folder),
        onAddFile:         () => _showFileCreationMenu(project: project),
      ),
    ));
  }

  String? _validateName(String raw, ProjectModel? project) {
    final name = raw.trim();
    if (name.isEmpty) return "Name cannot be empty";
    if (project == null && name.contains('/')) {
      return "Standalone files can't have '/' in the name";
    }
    if (_safeRelPath(name) == null) return "Invalid file name";
    return null;
  }

  void _renameBinaryFile(FileModel file, ProjectModel? project) {
    final ctrl = TextEditingController(text: file.name);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Rename"),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(
              labelText: "File name", border: OutlineInputBorder()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Cancel")),
          ElevatedButton(
            onPressed: () {
              final newName = ctrl.text.trim();
              final err = _validateName(newName, project);
              if (err != null) {
                Fluttertoast.showToast(msg: err);
                return;
              }
              setState(() => _applyNameAndPath(file, newName, project));
              _saveData();
              Navigator.pop(ctx);
              Fluttertoast.showToast(msg: 'Renamed to "${file.name}"');
            },
            child: const Text("Rename"),
          ),
        ],
      ),
    );
  }

  void _applyNameAndPath(FileModel f, String rawName, ProjectModel? project) {
    var name = rawName.trim();
    if (name.isEmpty) name = 'untitled.html';
    if (name.contains('/')) {
      final clean = _safeRelPath(name) ?? name.split('/').last;
      final i = clean.lastIndexOf('/');
      final dir  = i >= 0 ? clean.substring(0, i) : '';
      final base = i >= 0 ? clean.substring(i + 1) : clean;
      f.name = base;
      if (project != null) {
        f.path = dir;
        project.ensureFolder(dir);
      } else {
        f.path = '';
      }
    } else {
      f.name = name;
    }
  }

  void _openCodeEditor(FileModel? file, {ProjectModel? project}) {
    if (file != null) {
      if (file.isBinary) { _openWithSystem(file); return; }
      if (!file.isIdeFile) { _showTextEditDialog(file, project: project); return; }
      _trackRecentFile(file, project: project);
    }

    FileModel? target = file;

    Navigator.push(context, MaterialPageRoute(
      builder: (context) => IDEEditorScreen(
        file: file,
        project: project,
        onSave: (name, content) {
          setState(() {
            if (target == null) {
              final newFile = FileModel(
                id: DateTime.now().millisecondsSinceEpoch.toString(),
                name: name,
                content: content,
                lastEdit: DateFormat('HH:mm').format(DateTime.now()),
              );
              _applyNameAndPath(newFile, name, project);
              if (project != null) {
                project.files.add(newFile);
              } else {
                _standaloneFiles.add(newFile);
              }
              target = newFile;
              Fluttertoast.showToast(msg: "File Created");
            } else {
              _applyNameAndPath(target!, name, project);
              target!.content = content;
              target!.lastEdit = DateFormat('HH:mm').format(DateTime.now());
              Fluttertoast.showToast(msg: "File Saved");
            }
          });
          _saveData();
        },
      ),
    ));
  }

  void _showTextEditDialog(FileModel file, {ProjectModel? project}) {
    final original = file.content;
    final nameCtrl = TextEditingController(text: file.name);
    bool editingName = false;
    final ctrl = TextEditingController(text: original);

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) {
          final changed = ctrl.text != original || nameCtrl.text.trim() != file.name;
          return Dialog(
            backgroundColor: Colors.black,
            insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(6),
              side: const BorderSide(color: AppColors.holoDivider),
            ),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(ctx).size.height * 0.6,
              ),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    editingName
                        ? TextField(
                            controller: nameCtrl,
                            autofocus: true,
                            maxLines: 1,
                            cursorColor: Colors.white,
                            style: const TextStyle(
                                color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                            decoration: const InputDecoration.collapsed(hintText: null),
                            onChanged: (_) => setLocal(() {}),
                            onSubmitted: (_) => setLocal(() => editingName = false),
                          )
                        : GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onDoubleTap: () => setLocal(() => editingName = true),
                            child: Text(
                              nameCtrl.text.trim().isEmpty ? file.name : nameCtrl.text,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                            ),
                          ),
                    const SizedBox(height: 8),
                    Flexible(
                      child: Container(
                        constraints: const BoxConstraints(minHeight: 120),
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.black,
                          border: Border.all(color: Colors.grey.shade700),
                        ),
                        child: SingleChildScrollView(
                          child: TextField(
                            controller: ctrl,
                            maxLines: null,
                            keyboardType: TextInputType.multiline,
                            onChanged: (_) => setLocal(() {}),
                            style: const TextStyle(
                                color: Colors.white, fontFamily: 'monospace', fontSize: 13),
                            decoration: const InputDecoration.collapsed(hintText: null),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        ElevatedButton(
                          onPressed: () => Navigator.pop(ctx),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.red.shade700,
                            foregroundColor: Colors.white,
                          ),
                          child: const Text("Cancel"),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton(
                          onPressed: changed
                              ? () {
                                  final newName = nameCtrl.text.trim();
                                  if (newName != file.name) {
                                    final err = _validateName(newName, project);
                                    if (err != null) {
                                      Fluttertoast.showToast(msg: err);
                                      return;
                                    }
                                  }
                                  setState(() {
                                    if (newName != file.name) {
                                      _applyNameAndPath(file, newName, project);
                                    }
                                    file.content = ctrl.text;
                                    file.lastEdit = DateFormat('HH:mm').format(DateTime.now());
                                  });
                                  _saveData();
                                  Navigator.pop(ctx);
                                  Fluttertoast.showToast(msg: '"${file.name}" saved');
                                }
                              : null,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.androidGreen,
                            foregroundColor: Colors.black,
                            disabledBackgroundColor: Colors.grey.shade700,
                            disabledForegroundColor: Colors.white54,
                          ),
                          child: const Text("Save"),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  // --- CONTEXT MENUS ---

  void _showProjectOptions(ProjectModel project) {
    showModalBottomSheet(
      context: context,
      builder: (context) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.add_box),
            title: const Text("Add Files here"),
            onTap: () {
              Navigator.pop(context);
              _openCodeEditor(null, project: project);
            },
          ),
          ListTile(
            leading: const Icon(Icons.edit),
            title: const Text("Edit"),
            onTap: () {
              Navigator.pop(context);
              _showProjectWizard(project);
            },
          ),
          ListTile(
            leading: const Icon(Icons.archive),
            title: const Text("Download Project as .zip"),
            onTap: () {
              Navigator.pop(context);
              _exportProjectZip(project);
            },
          ),
          ListTile(
            leading: const Icon(Icons.delete, color: AppColors.errorRed),
            title: const Text("Delete", style: TextStyle(color: AppColors.errorRed)),
            onTap: () {
              Navigator.pop(context);
              _showDeleteConfirmation(() {
                setState(() => _projects.remove(project));
                _saveData();
              });
            },
          ),
        ],
      ),
    );
  }

  void _showFileOptions(FileModel file, ProjectModel? project) {
    showModalBottomSheet(
      context: context,
      builder: (context) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: Icon(file.isBinary ? Icons.open_in_new : Icons.edit),
            title: Text(file.isBinary ? "Open with..." : "Edit..."),
            onTap: () {
              Navigator.pop(context);
              _openCodeEditor(file, project: project);
            },
          ),
          if (file.isBinary)
            ListTile(
              leading: const Icon(Icons.drive_file_rename_outline),
              title: const Text("Rename"),
              onTap: () {
                Navigator.pop(context);
                _renameBinaryFile(file, project);
              },
            ),
          ListTile(
            leading: const Icon(Icons.download),
            title: const Text("Download to HTML Files/Files"),
            onTap: () {
              Navigator.pop(context);
              _downloadFile(file);
            },
          ),
          if (project != null)
            ListTile(
              leading: const Icon(Icons.drive_file_move, color: AppColors.linkBlue),
              title: const Text("Move to folder..."),
              onTap: () {
                Navigator.pop(context);
                _startMoveFile(project, file);
              },
            ),
          if (project == null && _projects.isNotEmpty)
            ListTile(
              leading: const Icon(Icons.drive_file_move, color: AppColors.folderYellow),
              title: const Text("Add to existing project..."),
              onTap: () {
                Navigator.pop(context);
                _showAddToProjectDialog(file);
              },
            ),
          if (file.isIdeFile)
            ListTile(
              leading: const Icon(Icons.play_arrow),
              title: const Text("Run"),
              onTap: () {
                Navigator.pop(context);
                if (project != null) {
                  _writeProjectToTempAndRun(project, file, null);
                } else {
                  Navigator.push(context, MaterialPageRoute(
                    builder: (_) => WebRunnerScreen(
                      htmlContent: _buildPreviewHtml(file.name, file.content))));
                }
              },
            ),
          ListTile(
            leading: const Icon(Icons.delete, color: AppColors.errorRed),
            title: const Text("Delete", style: TextStyle(color: AppColors.errorRed)),
            onTap: () {
              Navigator.pop(context);
              _showDeleteConfirmation(() {
                setState(() {
                  if (project != null) {
                    project.files.remove(file);
                  } else {
                    _standaloneFiles.remove(file);
                  }
                });
                _saveData();
                Fluttertoast.showToast(msg: '"${file.name}" deleted');
              });
            },
          ),
        ],
      ),
    );
  }

  void _showAddToProjectDialog(FileModel file) {
    showModalBottomSheet(
      context: context,
      builder: (context) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const ListTile(
            title: Text("Add to project", style: TextStyle(fontWeight: FontWeight.bold)),
          ),
          const Divider(height: 0),
          ..._projects.map((p) => ListTile(
            leading: const Icon(Icons.folder, color: AppColors.folderYellow),
            title: Text(p.name),
            onTap: () {
              Navigator.pop(context);
              setState(() {
                if (!p.files.contains(file)) {
                  p.files.add(file);
                  _standaloneFiles.remove(file);
                }
              });
              _saveData();
              Fluttertoast.showToast(msg: "Added \"${file.name}\" to ${p.name}");
            },
          )),
        ],
      ),
    );
  }

  void _showDeleteConfirmation(VoidCallback onConfirm) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Warning"),
        content: const Text(
          "When you delete a project or a file you can never get it back (except if it's on your internal storage)",
        ),
        actions: [
          TextButton(
            onPressed: () {
              onConfirm();
              Navigator.pop(context);
            },
            child: const Text("Delete", style: TextStyle(color: AppColors.errorRed, fontWeight: FontWeight.bold)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Nevermind"),
          ),
        ],
      ),
    );
  }

  void _showRecentFilesDialog() {
    showModalBottomSheet(
      context: context,
      builder: (_) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const ListTile(
            leading: Icon(Icons.history),
            title: Text('Recent Files',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          ),
          const Divider(height: 0),
          if (_recentFiles.isEmpty)
            const Padding(
              padding: EdgeInsets.all(20),
              child: Text('No recent files yet.',
                style: TextStyle(color: Colors.grey)),
            )
          else
            ..._recentFiles.map((e) => ListTile(
              leading: const Icon(Icons.insert_drive_file, color: AppColors.linkBlue),
              title: Text(e['name'] ?? 'Unknown'),
              subtitle: Text(
                (e['project'] ?? '').isNotEmpty ? 'In: ${e['project']}  •  ${e['lastEdit']}' : e['lastEdit'] ?? '',
                style: const TextStyle(fontSize: 11)),
              onTap: () {
                Navigator.pop(context);
                final id = e['id'];
                FileModel? found;
                ProjectModel? proj;
                for (final f in _standaloneFiles) {
                  if (f.id == id) { found = f; break; }
                }
                if (found == null) {
                  for (final p in _projects) {
                    for (final f in p.files) {
                      if (f.id == id) { found = f; proj = p; break; }
                    }
                    if (found != null) break;
                  }
                }
                if (found != null) {
                  _openCodeEditor(found, project: proj);
                } else {
                  Fluttertoast.showToast(msg: 'File no longer exists');
                  setState(() => _recentFiles.removeWhere((r) => r['id'] == id));
                }
              },
            )).toList(),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  void _showSettingsSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => SingleChildScrollView(child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.history, color: AppColors.androidGreen),
            title: const Text("Recent Files"),
            onTap: () {
              Navigator.pop(context);
              _showRecentFilesDialog();
            },
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.menu_book, color: AppColors.linkBlue),
            title: const Text("Help / Tutorial"),
            onTap: () {
              Navigator.pop(context);
              Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const TutorialScreen()));
            },
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.file_download),
            title: const Text("Download All Files"),
            subtitle: const Text("Saves to Internal Storage"),
            onTap: () {
              Navigator.pop(context);
              _downloadAllFiles();
            },
          ),
          const Divider(),
          const Padding(
            padding: EdgeInsets.all(8.0),
            child: Text("Change Themes", style: TextStyle(fontWeight: FontWeight.bold)),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              ElevatedButton(onPressed: () => widget.onThemeChange(ThemeMode.light), child: const Text("White")),
              ElevatedButton(onPressed: () => widget.onThemeChange(ThemeMode.dark), child: const Text("Black")),
              ElevatedButton(onPressed: () => widget.onThemeChange(ThemeMode.system), child: const Text("System")),
            ],
          ),
          const SizedBox(height: 10),
          const Divider(),
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Text(
              "HTML Runner v1.6.7 © (made by Chirag on 2026)",
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurface.withOpacity(0.45),
                fontSize: 12,
                fontFamily: 'monospace',
                letterSpacing: 0.5,
              ),
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: 5),
          ListTile(
            leading: const Icon(Icons.exit_to_app, color: AppColors.errorRed),
            title: Text(_currentUser == null ? "Erase Data & Sign Out" : "Sign Out / Reset"),
            subtitle: _currentUser == null
                ? const Text("Local storage — deletes all projects and files")
                : null,
            onTap: () {
              Navigator.pop(context);
              _triggerSecurityVerification();
            },
          ),
        ],
      )),
    );
  }

  // --- START OF SECURITY GATE LOGIC ---

  void _triggerSecurityVerification() {
    if (_currentUser != null) {
      _showChallengeDialog();
    } else {
      // Local users: confirm first — this deletes everything stored in the app
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text("Erase all data?",
              style: TextStyle(color: AppColors.errorRed, fontWeight: FontWeight.bold)),
          content: const Text(
              "This leaves local mode and permanently deletes every project and file stored in this app."),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Cancel")),
            TextButton(
              onPressed: () {
                Navigator.pop(ctx);
                _startSecurityScan();
              },
              child: const Text("Continue",
                  style: TextStyle(color: AppColors.errorRed, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      );
    }
  }

  void _startSecurityScan() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogCtx) {
        Future.delayed(const Duration(seconds: 2), () {
          if (!mounted) return; // FIX 34
          Navigator.pop(dialogCtx);
          _showMegaCaptcha();
        });
        return const AlertDialog(
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 20),
              Text("Performing Security Analysis..."),
              Text("Checking for automated behavior", style: TextStyle(fontSize: 12, color: Colors.grey)),
            ],
          ),
        );
      },
    );
  }

  void _showMegaCaptcha() {
    Map<String, List<IconData>> themes = {
      "Vehicles": [Icons.directions_car, Icons.pedal_bike, Icons.bus_alert, Icons.train],
      "Nature": [Icons.local_florist, Icons.eco, Icons.landscape, Icons.wb_sunny],
      "Technology": [Icons.laptop, Icons.smartphone, Icons.mouse, Icons.watch],
    };
    String randomTheme = (themes.keys.toList()..shuffle()).first;
    List<IconData> correctIcons = themes[randomTheme]!;
    List<IconData> allOtherIcons = themes.values.expand((v) => v).where((i) => !correctIcons.contains(i)).toList();
    List<IconData> gridItems = ((correctIcons..shuffle()).take(3).toList() + (allOtherIcons..shuffle()).take(6).toList())..shuffle();
    List<int> selectedIndices = [];

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Container(
            color: Colors.blue,
            padding: const EdgeInsets.all(10),
            child: Text("Select all squares with $randomTheme", style: const TextStyle(color: Colors.white, fontSize: 16)),
          ),
          content: SizedBox(
            width: 300,
            height: 300,
            child: GridView.builder(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3, crossAxisSpacing: 4, mainAxisSpacing: 4),
              itemCount: 9,
              itemBuilder: (context, index) {
                bool isSelected = selectedIndices.contains(index);
                return InkWell(
                  onTap: () => setState(() => isSelected ? selectedIndices.remove(index) : selectedIndices.add(index)),
                  child: Container(
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: isSelected ? Theme.of(context).colorScheme.primary : Theme.of(context).dividerColor,
                        width: isSelected ? 3 : 1,
                      ),
                      color: isSelected
                          ? Theme.of(context).colorScheme.primary.withOpacity(0.15)
                          : Theme.of(context).cardColor,
                    ),
                    child: Icon(gridItems[index], size: 40,
                      color: isSelected
                          ? Theme.of(context).colorScheme.primary
                          : Theme.of(context).colorScheme.onSurface.withOpacity(0.6)),
                  ),
                );
              },
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text("CANCEL")),
            ElevatedButton(
              onPressed: () {
                bool success = selectedIndices.isNotEmpty && selectedIndices.every((idx) => correctIcons.contains(gridItems[idx]));
                int totalCorrectInGrid = gridItems.where((i) => correctIcons.contains(i)).length;
                if (success && selectedIndices.length == totalCorrectInGrid) {
                  Navigator.pop(context);
                  _handleSignOut(eraseData: true);
                  Fluttertoast.showToast(msg: "Identity Confirmed");
                } else {
                  Fluttertoast.showToast(msg: "Try again. Select ALL matching items.");
                  Navigator.pop(context);
                  _showMegaCaptcha();
                }
              },
              child: const Text("VERIFY"),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showChallengeDialog() async {
    bool sent;
    try {
      sent = await SecurityCodeService.issue();
    } catch (e) {
      Fluttertoast.showToast(msg: "Could not send the security code: $e");
      return;
    }
    if (!mounted) return;
    if (!sent) {
      Fluttertoast.showToast(
        msg: "Allow notifications for HTML Runner to receive your security code.",
        toastLength: Toast.LENGTH_LONG,
      );
      return;
    }

    final input = TextEditingController();
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text("Fish Gang Security Verification",
            style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text("A 6-digit security code was sent to your notifications. "
                "It stays valid for 1 hour."),
            const SizedBox(height: 15),
            TextField(
              controller: input,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                  border: OutlineInputBorder(), labelText: "Verification Code"),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () async {
                  final ok = await SecurityCodeService.issue();
                  Fluttertoast.showToast(
                      msg: ok ? "New code sent" : "Notifications are blocked");
                },
                child: const Text("Send a new code"),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              SecurityCodeService.clear();
              Navigator.pop(ctx);
            },
            child: const Text("CANCEL"),
          ),
          ElevatedButton(
            onPressed: () async {
              if (await SecurityCodeService.verify(input.text)) {
                if (ctx.mounted) Navigator.pop(ctx);
                _handleSignOut();
              } else {
                Fluttertoast.showToast(msg: "Incorrect or expired code.");
              }
            },
            child: const Text("VERIFY & WIPE"),
          ),
        ],
      ),
    );
  }

  void _handleSignOut({bool eraseData = false}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('fg_uid');
      await prefs.remove('fg_email');
      await prefs.remove('fg_token');
      await prefs.remove('fg_name');
      await prefs.remove('is_local_mode');
      await SecurityCodeService.clear();
      if (eraseData) {
        // local users: wipe projects, standalone files, imported binaries, recents
        await DataStore.delete('projects_db.json');
        await DataStore.delete('files_db.json');
        final docs = await getApplicationDocumentsDirectory();
        final imports = Directory('${docs.path}/imports');
        if (await imports.exists()) await imports.delete(recursive: true);
        await prefs.remove('projects_db');
        await prefs.remove('files_db');
        await prefs.remove('recent_files');
      }
    } catch (e) {
      debugPrint('Sign-out cleanup error: $e');
    }
    exit(0);
  }
}

// -----------------------------------------------------------------------------
// SECTION 5: CUSTOM WIDGETS
// -----------------------------------------------------------------------------

class ProjectTile extends StatelessWidget {
  final ProjectModel project;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  const ProjectTile({
    required this.project,
    required this.onTap,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          border: Border.all(color: Theme.of(context).dividerColor, width: 2),
          boxShadow: const [BoxShadow(color: Colors.black12, offset: Offset(2, 2), blurRadius: 4)],
        ),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                width: 80,
                color: Colors.brown.shade200,
                child: project.iconPath != null
                    ? Image.file(
                        File(project.iconPath!),
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => const Icon(Icons.terrain, size: 40, color: Colors.green),
                      )
                    : const Icon(Icons.terrain, size: 40, color: Colors.green),
              ),

              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(12.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        project.name,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 18,
                          fontFamily: 'monospace',
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        project.description.isEmpty ? "No Description" : project.description,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Colors.grey, fontSize: 13),
                      ),
                      const Spacer(),
                      Text(
                        "Created: ${project.createdAt} | Files: ${project.files.length}",
                        style: const TextStyle(fontSize: 10, color: Colors.blueGrey),
                      ),
                    ],
                  ),
                ),
              ),

              const Center(
                child: Padding(
                  padding: EdgeInsets.all(8.0),
                  child: Icon(Icons.chevron_right, color: Colors.grey),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class FileTile extends StatelessWidget {
  final FileModel file;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  const FileTile({
    required this.file,
    required this.onTap,
    required this.onLongPress,
  });

  static IconData _iconFor(FileModel f) {
    final ext = f.ext;
    if (f.isBinary) {
      if ({'jpg','jpeg','png','gif','webp','bmp','svg'}.contains(ext)) return Icons.image;
      if ({'mp4','mov','avi','mkv','webm'}.contains(ext))              return Icons.videocam;
      if ({'mp3','wav','ogg','aac','flac'}.contains(ext))              return Icons.audiotrack;
      if (ext == 'pdf')                                                return Icons.picture_as_pdf;
      if ({'zip','tar','gz','rar'}.contains(ext))                      return Icons.folder_zip;
      return Icons.attach_file;
    }
    if (ext == 'css')  return Icons.palette;
    if (ext == 'js')   return Icons.javascript;
    if (ext == 'json') return Icons.data_object;
    if (ext == 'txt' || ext == 'md') return Icons.description;
    if (ext == 'xml' || ext == 'svg') return Icons.code;
    return Icons.html;
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
      child: ListTile(
        leading: Icon(_iconFor(file),
          color: file.isBinary ? Colors.grey.shade400 : AppColors.folderYellow, size: 32),
        title: Text(file.name, style: const TextStyle(fontWeight: FontWeight.w500)),
        subtitle: Text(
          file.isBinary ? "Tap to open with system app" : "Last edited: ${file.lastEdit}",
          style: const TextStyle(fontSize: 12)),
        onTap: onTap,
        onLongPress: onLongPress,
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// SECTION 6: DIALOGS & WIZARDS
// -----------------------------------------------------------------------------

class ProjectWizardDialog extends StatefulWidget {
  final ProjectModel? existingProject;
  final List<FileModel> availableFiles;
  final Function(String, String, String?, List<FileModel>) onSave;

  const ProjectWizardDialog({
    this.existingProject,
    required this.availableFiles,
    required this.onSave,
  });

  @override
  _ProjectWizardDialogState createState() => _ProjectWizardDialogState();
}

class _ProjectWizardDialogState extends State<ProjectWizardDialog> {
  late TextEditingController _nameCtrl;
  late TextEditingController _descCtrl;
  String? _selectedIconPath;
  List<FileModel> _selectedFiles = [];

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.existingProject?.name ?? "");
    _descCtrl = TextEditingController(text: widget.existingProject?.description ?? "");
    _selectedIconPath = widget.existingProject?.iconPath;
    if (widget.existingProject != null) {
      _selectedFiles = List.from(widget.existingProject!.files);
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickIcon() async {
    try {
      final XFile? image = await ImagePicker().pickImage(source: ImageSource.gallery);
      if (image != null && mounted) {
        setState(() => _selectedIconPath = image.path);
      }
    } catch (e) {
      Fluttertoast.showToast(msg: "Failed to pick image: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
      contentPadding: const EdgeInsets.all(0),
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              GestureDetector(
                onTap: _pickIcon,
                child: Container(
                  height: 120,
                  color: Theme.of(context).cardColor,
                  child: _selectedIconPath != null
                      ? Image.file(
                          File(_selectedIconPath!),
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => const Icon(Icons.broken_image, size: 50),
                        )
                      : Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: const [
                            Icon(Icons.edit, size: 30, color: Colors.grey),
                            SizedBox(height: 8),
                            Text("✏ Add a Project Icon (Optional)", style: TextStyle(color: Colors.grey)),
                          ],
                        ),
                ),
              ),

              Padding(
                padding: const EdgeInsets.all(20.0),
                child: Column(
                  children: [
                    TextField(
                      controller: _nameCtrl,
                      decoration: const InputDecoration(
                        labelText: "Enter Project Name",
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (v) => setState(() {}),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _descCtrl,
                      decoration: const InputDecoration(
                        labelText: "Enter Project Description (Optional)",
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 24),
                    const Align(
                      alignment: Alignment.centerLeft,
                      child: Text("Add Files in this project (Optional for now)", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                    ),
                    const Divider(),
                    if (widget.availableFiles.isEmpty)
                      const Padding(padding: EdgeInsets.all(8.0), child: Text("No standalone files available to add.", style: TextStyle(color: Colors.grey))),

                    ...widget.availableFiles.map((f) => CheckboxListTile(
                      title: Text(f.name),
                      value: _selectedFiles.contains(f),
                      activeColor: AppColors.androidGreen,
                      onChanged: (bool? selected) {
                        setState(() {
                          if (selected == true) {
                            _selectedFiles.add(f);
                          } else {
                            _selectedFiles.remove(f);
                          }
                        });
                      },
                    )),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: _nameCtrl.text.isEmpty ? Colors.grey : AppColors.androidGreen,
              foregroundColor: Colors.white,
              shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
            onPressed: _nameCtrl.text.isEmpty
                ? null
                : () {
                    widget.onSave(
                      _nameCtrl.text,
                      _descCtrl.text,
                      _selectedIconPath,
                      _selectedFiles,
                    );
                    Navigator.pop(context);
                  },
            child: Text(
              widget.existingProject == null ? "Create" : "Save Edits",
              style: const TextStyle(fontSize: 18),
            ),
          ),
        ),
      ],
    );
  }
}

// -----------------------------------------------------------------------------
// SECTION 7: IDE EDITOR SCREEN
// -----------------------------------------------------------------------------

class _LineNumberColumn extends StatefulWidget {
  final TextEditingController controller;
  final ScrollController scrollController;
  final TextStyle textStyle;   // fully resolved style used by the editor
  final TextScaler textScaler;
  final double textWidth;      // width available to the text inside the field

  const _LineNumberColumn({
    required this.controller,
    required this.scrollController,
    required this.textStyle,
    required this.textScaler,
    required this.textWidth,
  });

  @override
  State<_LineNumberColumn> createState() => _LineNumberColumnState();
}

class _LineNumberColumnState extends State<_LineNumberColumn> {
  List<int> _visual = const [1];          // visual rows per logical line
  final Map<String, int> _cache = {};
  String _lastText = '';

  double get _lineH =>
      widget.textScaler.scale(widget.textStyle.fontSize ?? 14) *
      (widget.textStyle.height ?? 1.0);

  @override
  void initState() {
    super.initState();
    _lastText = widget.controller.text;
    _visual = _compute();
    widget.controller.addListener(_onChanged);
  }

  @override
  void didUpdateWidget(covariant _LineNumberColumn old) {
    super.didUpdateWidget(old);
    if (old.textWidth != widget.textWidth || old.textScaler != widget.textScaler) {
      _cache.clear();
      _visual = _compute();
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    if (!mounted) return;
    final t = widget.controller.text;
    if (t == _lastText) return; // caret moves also fire this listener
    _lastText = t;
    setState(() => _visual = _compute());
  }

  List<int> _compute() {
    final lineH = _lineH;
    final tp = TextPainter(
      textDirection: TextDirection.ltr,
      textScaler: widget.textScaler,
    );
    if (_cache.length > 4000) _cache.clear();
    final out = <int>[];
    for (final line in widget.controller.text.split('\n')) {
      if (line.isEmpty) { out.add(1); continue; }
      out.add(_cache.putIfAbsent(line, () {
        tp.text = TextSpan(text: line, style: widget.textStyle);
        tp.layout(maxWidth: widget.textWidth);
        return max(1, (tp.height / lineH).round());
      }));
    }
    tp.dispose();
    return out;
  }

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: Container(
        width: 44,
        color: AppColors.gutterGray,
        child: CustomPaint(
          size: Size.infinite,
          painter: _GutterPainter(
            visual: _visual,
            scroll: widget.scrollController,
            style: widget.textStyle.copyWith(color: Colors.grey),
            lineH: _lineH,
            scaler: widget.textScaler,
          ),
        ),
      ),
    );
  }
}

class _GutterPainter extends CustomPainter {
  final List<int> visual;
  final ScrollController scroll;
  final TextStyle style;
  final double lineH;
  final TextScaler scaler;

  _GutterPainter({
    required this.visual,
    required this.scroll,
    required this.style,
    required this.lineH,
    required this.scaler,
  }) : super(repaint: scroll); // repaint on scroll without setState

  @override
  void paint(Canvas canvas, Size size) {
    final off = scroll.hasClients ? scroll.offset : 0.0;
    double y = -off;
    final tp = TextPainter(
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.center,
      textScaler: scaler,
    );
    for (int i = 0; i < visual.length; i++) {
      final h = visual[i] * lineH;
      if (y + h < 0) { y += h; continue; }
      if (y > size.height) break;
      tp.text = TextSpan(text: '${i + 1}', style: style);
      tp.layout(minWidth: size.width, maxWidth: size.width);
      tp.paint(canvas, Offset(0, y));
      y += h;
    }
    tp.dispose();
  }

  @override
  bool shouldRepaint(covariant _GutterPainter old) =>
      old.visual != visual || old.style != style || old.lineH != lineH;
}

class IDEEditorScreen extends StatefulWidget {
  final FileModel? file;
  final ProjectModel? project; // if set, Run writes all files to temp for relative-path support
  final Function(String, String) onSave;

  const IDEEditorScreen({this.file, this.project, required this.onSave});

  @override
  _IDEEditorScreenState createState() => _IDEEditorScreenState();
}

class _IDEEditorScreenState extends State<IDEEditorScreen> {
  late TextEditingController _nameController;
  late TextEditingController _codeController;
  final UndoHistoryController _undoController = UndoHistoryController();
  final ScrollController _scrollController = ScrollController();

  // last values handed to onSave — exit only auto-saves if something changed
  late String _savedName;
  late String _savedCode;

  // find & replace
  final FocusNode _focusNode = FocusNode();
  String _lastQuery   = '';
  String _lastReplace = '';
  TextStyle? _resolvedStyle;   // set in build(); used to locate a match on screen
  TextScaler? _scaler;
  double _editorTextWidth = 300;

  static const TextStyle _codeStyle = TextStyle(
    color: Colors.white,
    fontFamily: 'monospace',
    fontSize: 14,
    height: 1.5,
  );

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.file?.name ?? "index.html");
    _codeController = TextEditingController(
      text: widget.file?.content ?? "<html>\n<body>\n  <h1>Hello World</h1>\n</body>\n</html>",
    );
    _savedName = _nameController.text;
    _savedCode = _codeController.text;
  }

  @override
  void dispose() {
    _focusNode.dispose();
    _scrollController.dispose();
    _nameController.dispose();
    _codeController.dispose();
    super.dispose();
  }

  void _save() {
    widget.onSave(_nameController.text, _codeController.text);
    _savedName = _nameController.text;
    _savedCode = _codeController.text;
  }

  Future<bool> _onWillPop() async {
    // Auto-save on exit — only when something changed (an untouched new file
    // no longer gets created just by opening and leaving the editor)
    if (_nameController.text != _savedName || _codeController.text != _savedCode) {
      _save();
    }
    return true;
  }

  /// Path of the file being edited, relative to the project root (FIX 6).
  String _effectiveRelPath() {
    final typed = _nameController.text.trim();
    if (typed.contains('/')) {
      return _safeRelPath(typed) ?? typed.split('/').last;
    }
    final dir = widget.file?.path ?? '';
    return dir.isEmpty ? typed : '$dir/$typed';
  }

  Future<void> _runPreview() async {
    final project = widget.project;
    final file    = widget.file;
    final ext     = _extOf(_nameController.text);
    final isPage  = {'html', 'htm', 'html3'}.contains(ext);

    // Inside a project: write all assets to a temp dir so relative paths
    // (images, stylesheets, scripts) resolve in the WebView.
    if (project != null && isPage) {
      try {
        final tmpDir  = await getTemporaryDirectory();
        final projDir = Directory('${tmpDir.path}/htmlrunner_preview');
        if (await projDir.exists()) await projDir.delete(recursive: true);
        await projDir.create(recursive: true);

        for (final f in project.files) {
          if (file != null && f.id == file.id) continue; // written below from the live editor
          final dest = File('${projDir.path}/${f.fullPath}');
          await dest.parent.create(recursive: true);
          if (f.isBinary && f.externalPath != null) {
            if (await File(f.externalPath!).exists()) {
              await File(f.externalPath!).copy(dest.path);
            }
          } else {
            await dest.writeAsString(f.content);
          }
        }

        final main = File('${projDir.path}/${_effectiveRelPath()}');
        await main.parent.create(recursive: true);
        await main.writeAsString(_codeController.text);

        if (!mounted) return;
        Navigator.push(context, MaterialPageRoute(
          builder: (_) => WebRunnerScreen(filePath: main.path),
        ));
      } catch (e) {
        Fluttertoast.showToast(msg: 'Preview error: $e');
      }
      return;
    }

    // Standalone file (or css/js) — no assets to resolve, use htmlContent
    if (!mounted) return;
    Navigator.push(context, MaterialPageRoute(
      builder: (_) => WebRunnerScreen(
        htmlContent: _buildPreviewHtml(_nameController.text, _codeController.text)),
    ));
  }

  void _showRenameDialog() {
    final renameCtrl = TextEditingController(text: _nameController.text);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Rename / Move File"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              widget.project == null
                  ? "Standalone files can't contain '/'"
                  : "Use / to create folders, e.g. pages/about.html",
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: renameCtrl,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: "File path",
                hintText: "e.g. index.html or pages/about.html",
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Cancel")),
          ElevatedButton(
            onPressed: () {
              String newPath = renameCtrl.text.trim();
              if (newPath.isEmpty) return;
              if (widget.project == null && newPath.contains('/')) {
                Fluttertoast.showToast(msg: "Standalone files can't have '/' in the name");
                return;
              }
              final base = newPath.split('/').last;
              if (!base.contains('.')) newPath = '$newPath.html';
              setState(() => _nameController.text = newPath);
              Navigator.pop(ctx);
              Fluttertoast.showToast(msg: "Renamed to $newPath");
            },
            child: const Text("Rename"),
          ),
        ],
      ),
    );
  }

  // ── Find & Replace ───────────────────────────────────────────────────────
  void _showSearchDialog() {
    final findCtrl = TextEditingController(text: _lastQuery);
    final replCtrl = TextEditingController(text: _lastReplace);
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) {
          final hasFind = findCtrl.text.isNotEmpty;
          final hasRepl = replCtrl.text.isNotEmpty;
          final label   = hasRepl ? 'Replace' : 'Search';
          final enabled = hasFind;
          return AlertDialog(
            title: const Text('Find & Replace'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: findCtrl,
                  autofocus: true,
                  onChanged: (_) => setLocal(() {}),
                  decoration: const InputDecoration(
                    labelText: 'Search for',
                    prefixIcon: Icon(Icons.search),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: replCtrl,
                  onChanged: (_) => setLocal(() {}),
                  decoration: const InputDecoration(
                    labelText: 'Replace with (optional)',
                    prefixIcon: Icon(Icons.find_replace),
                    isDense: true,
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: enabled
                    ? () {
                        final f = findCtrl.text;
                        final r = replCtrl.text;
                        Navigator.pop(ctx);
                        if (r.isNotEmpty) {
                          _replaceAll(f, r);
                        } else {
                          _findNext(f);
                        }
                      }
                    : null,
                style: ElevatedButton.styleFrom(
                  disabledBackgroundColor: Colors.grey.shade700,
                  disabledForegroundColor: Colors.white54,
                ),
                child: Text(label),
              ),
            ],
          );
        },
      ),
    );
  }

  /// Selects the next match after the caret (wraps around). Searching again with
  /// the same text keeps moving to the next match.
  void _findNext(String q) {
    _lastQuery = q;
    final hay    = _codeController.text.toLowerCase();
    final needle = q.toLowerCase();
    final starts = <int>[];
    int i = hay.indexOf(needle);
    while (i != -1) {
      starts.add(i);
      i = hay.indexOf(needle, i + needle.length);
    }
    if (starts.isEmpty) {
      Fluttertoast.showToast(msg: 'No matches for "$q"');
      return;
    }
    final sel  = _codeController.selection;
    final from = sel.isValid ? sel.end : 0;
    int idx = starts.indexWhere((st) => st >= from);
    if (idx == -1) idx = 0; // wrap to the first match
    _selectMatch(starts[idx], starts[idx] + needle.length);
    Fluttertoast.showToast(msg: 'Match ${idx + 1} of ${starts.length}');
  }

  void _replaceAll(String find, String replacement) {
    _lastQuery   = find;
    _lastReplace = replacement;
    final re    = RegExp(RegExp.escape(find), caseSensitive: false);
    final text  = _codeController.text;
    final count = re.allMatches(text).length;
    if (count == 0) {
      Fluttertoast.showToast(msg: 'No matches for "$find"');
      return;
    }
    final newText = text.replaceAllMapped(re, (_) => replacement);
    final sel = _codeController.selection;
    _codeController.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(
          offset: min(sel.isValid ? sel.baseOffset : 0, newText.length)),
    );
    Fluttertoast.showToast(
        msg: 'Replaced $count occurrence${count == 1 ? '' : 's'} (undo available)');
  }

  void _selectMatch(int start, int end) {
    // give the dialog time to close, then focus the editor, select and scroll
    Future.delayed(const Duration(milliseconds: 200), () {
      if (!mounted) return;
      _focusNode.requestFocus();
      _codeController.selection = TextSelection(baseOffset: start, extentOffset: end);
      if (!_scrollController.hasClients || _resolvedStyle == null || _scaler == null) return;
      final tp = TextPainter(
        text: TextSpan(text: _codeController.text, style: _resolvedStyle),
        textDirection: TextDirection.ltr,
        textScaler: _scaler!,
      )..layout(maxWidth: _editorTextWidth);
      final dy = tp.getOffsetForCaret(TextPosition(offset: start), Rect.zero).dy;
      tp.dispose();
      final pos = _scrollController.position;
      final target = (dy - pos.viewportDimension / 3).clamp(0.0, pos.maxScrollExtent);
      _scrollController.animateTo(target,
          duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
    });
  }

  void _insertTag(String tag) {
    final text = _codeController.text;
    final sel  = _codeController.selection;
    // FIX 4: selection is (-1,-1) until the field was focused once
    final start = sel.isValid ? sel.start : text.length;
    final end   = sel.isValid ? sel.end   : text.length;
    final newText = text.replaceRange(start, end, tag);
    _codeController.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: start + tag.length),
    );
  }

  Widget _toolbarBtn(String label, VoidCallback onTap) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4.0),
      child: TextButton(
        onPressed: onTap,
        style: TextButton.styleFrom(
          foregroundColor: Colors.white,
          minimumSize: const Size(50, 30),
        ),
        child: Text(label, style: const TextStyle(fontSize: 12)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // The TextField merges its style onto the theme's titleMedium; measure the
    // gutter with the SAME resolved style so wrapped lines match exactly.
    final resolvedStyle =
        (Theme.of(context).textTheme.titleMedium ?? const TextStyle()).merge(_codeStyle);
    final scaler = MediaQuery.textScalerOf(context);
    _resolvedStyle = resolvedStyle;
    _scaler = scaler;

    return WillPopScope(
      onWillPop: _onWillPop,
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: AppColors.nostalgiaBlack,
          title: Text(
            _nameController.text.isNotEmpty ? _nameController.text : "index.html",
            style: const TextStyle(color: Colors.white, fontSize: 16),
            overflow: TextOverflow.ellipsis,
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.drive_file_rename_outline, color: AppColors.linkBlue),
              tooltip: "Rename / Move File",
              onPressed: _showRenameDialog,
            ),
            IconButton(
              icon: const Icon(Icons.search),
              tooltip: "Find & Replace",
              onPressed: _showSearchDialog,
            ),
            IconButton(icon: const Icon(Icons.undo), onPressed: () => _undoController.undo()),
            IconButton(icon: const Icon(Icons.redo), onPressed: () => _undoController.redo()),
            IconButton(
              icon: const Icon(Icons.save, color: AppColors.androidGreen),
              onPressed: _save,
            ),
            IconButton(
              icon: const Icon(Icons.play_arrow, color: Colors.orange),
              onPressed: _runPreview,
            ),
            IconButton(
              icon: const Icon(Icons.exit_to_app, color: AppColors.errorRed),
              onPressed: () async {
                if (await _onWillPop() && mounted) Navigator.pop(context);
              },
            ),
          ],
        ),
        body: Column(
          children: [
            Container(
              height: 40,
              color: Colors.grey.shade900,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  _toolbarBtn("Copy", () => Clipboard.setData(ClipboardData(text: _codeController.text))),
                  _toolbarBtn("Paste", () async {
                    final data = await Clipboard.getData('text/plain');
                    final t = data?.text;
                    if (t != null) _insertTag(t);
                  }),
                  _toolbarBtn("Select All", () => _codeController.selection = TextSelection(
                    baseOffset: 0,
                    extentOffset: _codeController.text.length,
                  )),
                  _toolbarBtn("<div>", () => _insertTag("<div></div>")),
                  _toolbarBtn("<h1>", () => _insertTag("<h1></h1>")),
                  _toolbarBtn("<p>", () => _insertTag("<p></p>")),
                  _toolbarBtn("style", () => _insertTag("<style></style>")),
                ],
              ),
            ),

            Expanded(
              child: LayoutBuilder(
                builder: (context, c) {
                  const gutterW = 44.0;
                  const hPad = 8.0;
                  final textWidth = max(10.0, c.maxWidth - gutterW - hPad * 2);
                  _editorTextWidth = textWidth;
                  return Row(
                    children: [
                      _LineNumberColumn(
                        controller: _codeController,
                        scrollController: _scrollController,
                        textStyle: resolvedStyle,
                        textScaler: scaler,
                        textWidth: textWidth,
                      ),
                      Expanded(
                        child: Container(
                          color: AppColors.editorBackground,
                          child: TextField(
                            controller: _codeController,
                            focusNode: _focusNode,
                            scrollController: _scrollController,
                            undoController: _undoController,
                            maxLines: null,
                            expands: true,
                            textAlignVertical: TextAlignVertical.top, // code starts at the top, next to line 1
                            style: _codeStyle,
                            cursorColor: Colors.white,
                            decoration: const InputDecoration(
                              // the light theme's input fill (white) made white text invisible
                              filled: false,
                              border: InputBorder.none,
                              enabledBorder: InputBorder.none,
                              focusedBorder: InputBorder.none,
                              contentPadding: EdgeInsets.symmetric(horizontal: hPad),
                            ),
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// SECTION 8: RUNNER SCREEN & PROJECT DETAIL
// -----------------------------------------------------------------------------

class _ConsoleLine {
  final String level; // log | info | warn | error | debug | input | result
  final String text;
  const _ConsoleLine(this.level, this.text);
}

class WebRunnerScreen extends StatefulWidget {
  final String? htmlContent;
  final String? filePath; // when set, loaded via loadFile() for relative-path support
  const WebRunnerScreen({this.htmlContent, this.filePath})
      : assert(htmlContent != null || filePath != null, 'Provide either htmlContent or filePath');

  @override
  State<WebRunnerScreen> createState() => _WebRunnerScreenState();
}

class _WebRunnerScreenState extends State<WebRunnerScreen>
    with TickerProviderStateMixin {
  late final WebViewController _controller;
  bool _isLoading    = true;
  bool _showToolPanel = false;
  bool _isWinMode    = false;
  bool _showConsole  = false;
  final List<_ConsoleLine> _consoleLines = [
    const _ConsoleLine('info', 'Console ready. Type JavaScript below ("clear" empties the log).'),
  ];
  final ScrollController _consoleScroll = ScrollController();
  final TextEditingController _consoleInput = TextEditingController();
  late AnimationController _panelAnimation;
  late Animation<double>   _panelSlide;
  final ImagePicker _imagePicker = ImagePicker();

  @override
  void initState() {
    super.initState();
    _panelAnimation = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 300));
    _panelSlide = Tween<double>(begin: 0, end: 1).animate(
        CurvedAnimation(parent: _panelAnimation, curve: Curves.easeOut));
    _initWebView();
  }

  @override
  void dispose() {
    _panelAnimation.dispose();
    _consoleScroll.dispose();
    _consoleInput.dispose();
    super.dispose();
  }

  Future<void> _initWebView() async {
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0xFFFFFFFF))
      ..addJavaScriptChannel('FGConsole', onMessageReceived: _onConsoleMessage)
      ..setNavigationDelegate(NavigationDelegate(
        onPageStarted:  (_) {
          if (mounted) setState(() => _isLoading = true);
          _controller.runJavaScript(_consoleJs); // catch logs as early as possible
        },
        onPageFinished: (_) {
          if (!mounted) return;
          setState(() => _isLoading = false);
          _controller.runJavaScript(_consoleJs); // no-op if already installed
          _injectTouchHandling(_controller);
        },
        onNavigationRequest: (_) => NavigationDecision.navigate,
        onWebResourceError: (e) => debugPrint('WebView: ${e.description}'),
      ))
      ..enableZoom(true);

    if (Platform.isAndroid) await _setupAndroidFileUpload(_controller);

    if (widget.filePath != null) {
      await _controller.loadFile(widget.filePath!);
    } else {
      await _controller.loadHtmlString(widget.htmlContent ?? '');
    }

    if (mounted) setState(() {});
  }

  Future<void> _setupAndroidFileUpload(WebViewController controller) async {
    final androidCtrl = controller.platform as AndroidWebViewController;
    androidCtrl.setOnShowFileSelector((params) async {
      try {
        final isCapture  = params.isCaptureEnabled;
        final isMultiple = params.mode.toString().contains('MULTIPLE');
        final types      = params.acceptTypes;

        if (isCapture) {
          if (types.any((t) => t.contains('image'))) {
            if (!await _requestPermission(Permission.camera)) return [];
            final photo = await _imagePicker.pickImage(
                source: ImageSource.camera, maxWidth: 4096, maxHeight: 4096, imageQuality: 85);
            return photo != null ? [Uri.file(photo.path).toString()] : [];
          } else if (types.any((t) => t.contains('video'))) {
            if (!await _requestPermission(Permission.camera)) return [];
            if (!await _requestPermission(Permission.microphone)) return [];
            final video = await _imagePicker.pickVideo(
                source: ImageSource.camera, maxDuration: const Duration(minutes: 30));
            return video != null ? [Uri.file(video.path).toString()] : [];
          }
        }

        final exts = _extensionsFrom(types);
        if (!await _requestPermission(Permission.storage)) return [];
        // FIX 5: allowedExtensions requires FileType.custom
        final result = await FilePicker.platform.pickFiles(
          type: exts == null ? FileType.any : FileType.custom,
          allowMultiple: isMultiple,
          allowedExtensions: exts,
          withData: false,
        );
        if (result == null) return [];
        return result.files
            .where((f) => f.path != null)
            .map((f) => Uri.file(f.path!).toString())
            .toList();
      } catch (e) {
        debugPrint('File picker error: $e');
        return [];
      }
    });
  }

  Future<bool> _requestPermission(Permission p) async {
    final prefs = await SharedPreferences.getInstance();
    final mode  = prefs.getString('permission_mode') ?? "ask";
    final alwaysAllow = prefs.getBool('perm_${p.toString().split(".").last}') ?? false;
    if (mode == "always" && alwaysAllow) {
      return (await p.request()).isGranted;
    }
    return (await p.request()).isGranted;
  }

  List<String>? _extensionsFrom(List<String> types) {
    if (types.isEmpty) return null;
    const map = <String, List<String>>{
      'image/*':  ['jpg','jpeg','png','gif','webp','bmp','svg'],
      'video/*':  ['mp4','mov','avi','mkv','webm'],
      'audio/*':  ['mp3','wav','ogg','aac','flac'],
      'text/html':['html','htm'],
      'text/css': ['css'],
      'text/javascript': ['js'],
      'application/pdf': ['pdf'],
      'application/zip': ['zip'],
    };
    final exts = <String>{};
    for (final t in types) {
      if (map.containsKey(t)) { exts.addAll(map[t]!); continue; }
      final wild = '${t.split("/")[0]}/*';
      if (map.containsKey(wild)) { exts.addAll(map[wild]!); continue; }
      if (t.startsWith('.')) exts.add(t.substring(1));
    }
    return exts.isEmpty ? null : exts.toList();
  }

  void _injectTouchHandling(WebViewController wvc) {
    wvc.runJavaScript("""
      if (!document.querySelector('meta[name="viewport"]')) {
        const m = document.createElement('meta');
        m.name = 'viewport';
        m.content = 'width=device-width, initial-scale=1.0, maximum-scale=5.0, user-scalable=yes';
        document.head.appendChild(m);
      }
      document.body.style.touchAction = 'manipulation';
    """);
  }

  // ── Console ──────────────────────────────────────────────────────────────
  // Forwards console.* calls and uncaught errors from the page to Flutter.
  static const String _consoleJs = r'''
(function() {
  if (window.__fgConsole) return;
  window.__fgConsole = true;
  function send(level, args) {
    try {
      var text = Array.prototype.map.call(args, function(a) {
        try { return (typeof a === 'object') ? JSON.stringify(a) : String(a); }
        catch (e) { return String(a); }
      }).join(' ');
      FGConsole.postMessage(JSON.stringify({l: level, m: text}));
    } catch (e) {}
  }
  ['log', 'info', 'warn', 'error', 'debug'].forEach(function(k) {
    var orig = console[k];
    console[k] = function() {
      send(k, arguments);
      if (orig) orig.apply(console, arguments);
    };
  });
  window.addEventListener('error', function(e) {
    send('error', [e.message + (e.lineno ? ' (line ' + e.lineno + ')' : '')]);
  });
  window.addEventListener('unhandledrejection', function(e) {
    send('error', ['Unhandled promise rejection: ' + e.reason]);
  });
})();
''';

  void _onConsoleMessage(JavaScriptMessage msg) {
    try {
      final data = jsonDecode(msg.message) as Map<String, dynamic>;
      _addConsole((data['l'] ?? 'log').toString(), (data['m'] ?? '').toString());
    } catch (_) {
      _addConsole('log', msg.message);
    }
  }

  void _addConsole(String level, String text) {
    if (!mounted) return;
    setState(() {
      _consoleLines.add(_ConsoleLine(level, text));
      if (_consoleLines.length > 500) _consoleLines.removeAt(0);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_consoleScroll.hasClients) {
        _consoleScroll.jumpTo(_consoleScroll.position.maxScrollExtent);
      }
    });
  }

  void _copyConsole() {
    final text = _consoleLines.map((l) => l.text).join('\n');
    Clipboard.setData(ClipboardData(text: text));
    Fluttertoast.showToast(msg: 'Console copied');
  }

  Future<void> _runConsoleInput() async {
    final code = _consoleInput.text.trim();
    if (code.isEmpty) return;
    _consoleInput.clear();
    if (code == 'clear' || code == 'clear()') {
      setState(() => _consoleLines.clear());
      return;
    }
    _addConsole('input', '> $code');
    try {
      final r = await _controller.runJavaScriptReturningResult(code);
      _addConsole('result', r.toString());
    } catch (e) {
      _addConsole('error', e.toString());
    }
  }

  Color _consoleColor(String level) {
    switch (level) {
      case 'error':  return const Color(0xFFFF5555);
      case 'warn':   return const Color(0xFFFFD700);
      case 'debug':  return const Color(0xFF909090);
      case 'input':  return const Color(0xFF55FF55);
      case 'result': return const Color(0xFF55FFFF);
      default:       return const Color(0xFFE0E0E0);
    }
  }

  // Windows 95 bevels
  static const Color _w95Face   = Color(0xFFC0C0C0);
  static const Color _w95Light  = Colors.white;
  static const Color _w95Shadow = Color(0xFF404040);

  BoxDecoration _w95Raised() => const BoxDecoration(
        color: _w95Face,
        border: Border(
          top:    BorderSide(color: _w95Light,  width: 2),
          left:   BorderSide(color: _w95Light,  width: 2),
          right:  BorderSide(color: _w95Shadow, width: 2),
          bottom: BorderSide(color: _w95Shadow, width: 2),
        ),
      );

  BoxDecoration _w95Sunken() => const BoxDecoration(
        color: Colors.black,
        border: Border(
          top:    BorderSide(color: _w95Shadow, width: 2),
          left:   BorderSide(color: _w95Shadow, width: 2),
          right:  BorderSide(color: _w95Light,  width: 2),
          bottom: BorderSide(color: _w95Light,  width: 2),
        ),
      );

  Widget _buildConsolePanel(double height) {
    const mono = TextStyle(fontFamily: 'monospace', fontSize: 12);
    return Positioned(
      left: 0, right: 0, bottom: 0, height: height,
      child: Container(
        decoration: _w95Raised(),
        padding: const EdgeInsets.all(3),
        child: Column(
          children: [
            // title bar with the small X
            Container(
              height: 22,
              padding: const EdgeInsets.only(left: 4, right: 2),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xFF000080), Color(0xFF1084D0)],
                ),
              ),
              child: Row(
                children: [
                  const Icon(Icons.terminal, size: 14, color: Colors.white),
                  const SizedBox(width: 5),
                  const Expanded(
                    child: Text('Console',
                        style: TextStyle(
                            color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
                  ),
                  InkWell(
                    onTap: _copyConsole,
                    child: Container(
                      height: 16,
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      alignment: Alignment.center,
                      decoration: _w95Raised(),
                      child: const Text('Copy',
                          style: TextStyle(
                              color: Colors.black,
                              fontWeight: FontWeight.bold,
                              fontSize: 10,
                              height: 1.0)),
                    ),
                  ),
                  const SizedBox(width: 4),
                  InkWell(
                    onTap: () => setState(() => _showConsole = false),
                    child: Container(
                      width: 18,
                      height: 16,
                      alignment: Alignment.center,
                      decoration: _w95Raised(),
                      child: const Text('x',
                          style: TextStyle(
                              color: Colors.black,
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                              height: 1.0)),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 3),
            // log output
            Expanded(
              child: Container(
                decoration: _w95Sunken(),
                child: ListView.builder(
                  controller: _consoleScroll,
                  padding: const EdgeInsets.all(4),
                  itemCount: _consoleLines.length,
                  itemBuilder: (_, i) {
                    final l = _consoleLines[i];
                    return Text(l.text, style: mono.copyWith(color: _consoleColor(l.level)));
                  },
                ),
              ),
            ),
            const SizedBox(height: 3),
            // input line
            Container(
              height: 32,
              padding: const EdgeInsets.symmetric(horizontal: 6),
              decoration: _w95Sunken(),
              child: Row(
                children: [
                  Text('> ', style: mono.copyWith(color: const Color(0xFF55FF55))),
                  Expanded(
                    child: TextField(
                      controller: _consoleInput,
                      style: mono.copyWith(color: Colors.white),
                      cursorColor: const Color(0xFF55FF55),
                      textInputAction: TextInputAction.send,
                      autocorrect: false,
                      enableSuggestions: false,
                      decoration: const InputDecoration.collapsed(hintText: null),
                      onSubmitted: (_) => _runConsoleInput(),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Keyboard toolkit (FIX 9 + 23) ────────────────────────────────────────
  // One dispatcher: fires keydown/keypress/keyup AND, if a text field or
  // contenteditable has focus (and the page didn't cancel keydown), really
  // inserts / deletes text there.
  static const String _keyJs = r'''
(function(k, c, kc) {
  var el = document.activeElement || document.body;
  var o = {key: k, code: c, keyCode: kc, which: kc, bubbles: true, cancelable: true};
  var ok = el.dispatchEvent(new KeyboardEvent('keydown', o));
  if (k.length === 1) el.dispatchEvent(new KeyboardEvent('keypress', o));
  var isField = el.tagName === 'INPUT' || el.tagName === 'TEXTAREA';
  if (ok && (isField || el.isContentEditable)) {
    try {
      if (k.length === 1 || (k === 'Enter' && el.tagName !== 'INPUT')) {
        var t = (k === 'Enter') ? '\n' : k;
        if (el.isContentEditable) {
          document.execCommand('insertText', false, t);
        } else {
          el.setRangeText(t, el.selectionStart, el.selectionEnd, 'end');
          el.dispatchEvent(new Event('input', {bubbles: true}));
        }
      } else if (k === 'Backspace' || k === 'Delete') {
        if (el.isContentEditable) {
          document.execCommand(k === 'Backspace' ? 'delete' : 'forwardDelete');
        } else {
          var s = el.selectionStart, e = el.selectionEnd;
          if (s === e) {
            if (k === 'Backspace') s = Math.max(0, s - 1);
            else e = Math.min(el.value.length, e + 1);
          }
          el.setRangeText('', s, e, 'end');
          el.dispatchEvent(new Event('input', {bubbles: true}));
        }
      }
    } catch (err) {}
  }
  setTimeout(function() { el.dispatchEvent(new KeyboardEvent('keyup', o)); }, 60);
})(__K__, __C__, __KC__);
''';

  void _dispatchKey(String key, String code, int keyCode) {
    final js = _keyJs
        .replaceFirst('__K__', jsonEncode(key))
        .replaceFirst('__C__', jsonEncode(code))
        .replaceFirst('__KC__', keyCode.toString());
    _controller.runJavaScript(js);
  }

  void _sendKey(String key) {
    String code = key;
    int kc = 0;
    if (key.length == 1) {
      final cu = key.toUpperCase().codeUnitAt(0);
      if (cu >= 65 && cu <= 90) {
        code = 'Key${key.toUpperCase()}'; kc = cu;
      } else if (cu >= 48 && cu <= 57) {
        code = 'Digit$key'; kc = cu;
      } else if (key == ' ') {
        code = 'Space'; kc = 32;
      } else {
        code = ''; kc = key.codeUnitAt(0);
      }
    } else if (key == 'Enter') {
      kc = 13;
    } else if (key == 'Backspace') {
      kc = 8;
    }
    _dispatchKey(key, code, kc);
  }

  void _sendArrow(String dir) {
    const codes = {'up': 38, 'down': 40, 'left': 37, 'right': 39};
    const keys  = {'up': 'ArrowUp', 'down': 'ArrowDown', 'left': 'ArrowLeft', 'right': 'ArrowRight'};
    _dispatchKey(keys[dir]!, keys[dir]!, codes[dir]!);
  }

  void _sendSpecialKey(String key, String code, int keyCode) =>
      _dispatchKey(key, code, keyCode);

  void _togglePanel() {
    setState(() {
      _showToolPanel = !_showToolPanel;
      _showToolPanel ? _panelAnimation.forward() : _panelAnimation.reverse();
    });
  }

  Widget _toolBtn(String label, VoidCallback onTap, {double width = 50}) =>
      SizedBox(
        width: width,
        child: TextButton(
          style: TextButton.styleFrom(
            backgroundColor: Colors.white.withOpacity(0.2),
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            padding: const EdgeInsets.symmetric(vertical: 12),
          ),
          onPressed: onTap,
          child: Text(label, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
        ),
      );

  Widget _imgBtn(String asset, VoidCallback onTap) => SizedBox(
    width: 52, height: 46,
    child: TextButton(
      style: TextButton.styleFrom(
        backgroundColor: Colors.white.withOpacity(0.25),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        padding: EdgeInsets.zero,
      ),
      onPressed: onTap,
      child: Image.asset(asset, width: 30, height: 30, fit: BoxFit.contain),
    ),
  );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("HTML Preview"),
        backgroundColor: Colors.black,
        actions: [
          IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: () { setState(() => _isLoading = true); _controller.reload(); }),
          IconButton(
              icon: Icon(Icons.terminal,
                  color: _showConsole ? AppColors.linkBlue : Colors.white),
              onPressed: () => setState(() => _showConsole = !_showConsole),
              tooltip: "Console"),
          IconButton(
              icon: Icon(Icons.settings,
                  color: _showToolPanel ? AppColors.linkBlue : Colors.white),
              onPressed: _togglePanel,
              tooltip: "Keyboard Toolkit"),
        ],
      ),
      body: LayoutBuilder(builder: (context, bc) => Stack(
        children: [
          WebViewWidget(controller: _controller),
          if (_isLoading)
            Container(color: Colors.white,
                child: const Center(child: CircularProgressIndicator())),
          if (_showToolPanel)
            Positioned(
              bottom: 0, left: 0, right: 0,
              child: AnimatedBuilder(
                animation: _panelSlide,
                builder: (_, __) => Transform.translate(
                  offset: Offset(0, (1 - _panelSlide.value) * 320),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      maxHeight: MediaQuery.of(context).size.height * 0.48,
                    ),
                    child: Container(
                      decoration: BoxDecoration(
                        color: AppColors.panelBg,
                        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                        boxShadow: [BoxShadow(
                            color: Colors.black.withOpacity(0.4),
                            blurRadius: 12, offset: const Offset(0, -2))],
                      ),
                      child: SingleChildScrollView(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // drag handle
                            Container(
                                margin: const EdgeInsets.symmetric(vertical: 8),
                                width: 40, height: 4,
                                decoration: BoxDecoration(
                                    color: Colors.white.withOpacity(0.4),
                                    borderRadius: BorderRadius.circular(2))),
                            if (!_isWinMode) ...[
                              // ── Normal keyboard ──────────────────────────
                              Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                                child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                                  _toolBtn('←', () => _sendArrow('left')),
                                  const SizedBox(width: 16),
                                  _toolBtn('↑', () => _sendArrow('up')),
                                  const SizedBox(width: 16),
                                  _toolBtn('↓', () => _sendArrow('down')),
                                  const SizedBox(width: 16),
                                  _toolBtn('→', () => _sendArrow('right')),
                                ]),
                              ),
                              Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                child: Wrap(spacing: 6, children:
                                    '1234567890'.split('').map((c) => _toolBtn(c, () => _sendKey(c))).toList()),
                              ),
                              for (final row in ['QWERTYUIOP', 'ASDFGHJKL', 'ZXCVBNM'])
                                Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                  child: Wrap(spacing: 6, children:
                                      row.split('').map((c) => _toolBtn(c, () => _sendKey(c))).toList()),
                                ),
                              Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                                child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                                  _toolBtn('Space', () => _sendKey(' '), width: 100),
                                  const SizedBox(width: 8),
                                  _toolBtn('Enter', () => _sendKey('Enter')),
                                  const SizedBox(width: 8),
                                  _toolBtn('⌫', () => _sendKey('Backspace')),
                                  const SizedBox(width: 8),
                                  _imgBtn('assets/ic_aero_windows.png',
                                    () => setState(() => _isWinMode = true)),
                                ]),
                              ),
                            ] else ...[
                              // ── Special / Windows keyboard ────────────────
                              Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                child: Wrap(spacing: 6, children: [
                                  _toolBtn('Esc',  () => _sendSpecialKey('Escape', 'Escape', 27)),
                                  _toolBtn('F1',   () => _sendSpecialKey('F1',  'F1',  112)),
                                  _toolBtn('F2',   () => _sendSpecialKey('F2',  'F2',  113)),
                                  _toolBtn('F3',   () => _sendSpecialKey('F3',  'F3',  114)),
                                  _toolBtn('F4',   () => _sendSpecialKey('F4',  'F4',  115)),
                                  _toolBtn('F5',   () => _sendSpecialKey('F5',  'F5',  116)),
                                ]),
                              ),
                              Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                child: Wrap(spacing: 6, children: [
                                  _toolBtn('F6',   () => _sendSpecialKey('F6',  'F6',  117)),
                                  _toolBtn('F7',   () => _sendSpecialKey('F7',  'F7',  118)),
                                  _toolBtn('F8',   () => _sendSpecialKey('F8',  'F8',  119)),
                                  _toolBtn('F9',   () => _sendSpecialKey('F9',  'F9',  120)),
                                  _toolBtn('F10',  () => _sendSpecialKey('F10', 'F10', 121)),
                                ]),
                              ),
                              Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                child: Wrap(spacing: 6, children: [
                                  _toolBtn('Ctrl',  () => _sendSpecialKey('Control', 'ControlLeft', 17), width: 62),
                                  _toolBtn('Shift', () => _sendSpecialKey('Shift',   'ShiftLeft',   16), width: 62),
                                  _toolBtn('Alt',   () => _sendSpecialKey('Alt',     'AltLeft',     18)),
                                  _toolBtn('Tab',   () => _sendSpecialKey('Tab',     'Tab',          9)),
                                  _toolBtn('Caps',  () => _sendSpecialKey('CapsLock','CapsLock',    20)),
                                ]),
                              ),
                              Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                child: Wrap(spacing: 6, children: [
                                  _toolBtn('Ins',   () => _sendSpecialKey('Insert',  'Insert',   45)),
                                  _toolBtn('Del',   () => _sendSpecialKey('Delete',  'Delete',   46)),
                                  _toolBtn('Home',  () => _sendSpecialKey('Home',    'Home',     36)),
                                  _toolBtn('End',   () => _sendSpecialKey('End',     'End',      35)),
                                  _toolBtn('PgUp',  () => _sendSpecialKey('PageUp',  'PageUp',   33)),
                                  _toolBtn('PgDn',  () => _sendSpecialKey('PageDown','PageDown', 34)),
                                ]),
                              ),
                              Padding(
                                padding: const EdgeInsets.symmetric(vertical: 6),
                                child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                                  _imgBtn('assets/ic_aero_android.png',
                                    () => setState(() => _isWinMode = false)),
                                  const SizedBox(width: 10),
                                  const Text('Back to keyboard',
                                    style: TextStyle(color: Colors.white70, fontSize: 12)),
                                ]),
                              ),
                            ],
                            Padding(
                              padding: const EdgeInsets.only(bottom: 12, top: 4),
                              child: ElevatedButton(
                                onPressed: _togglePanel,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.red.shade700,
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(20)),
                                ),
                                child: const Text('Close',
                                    style: TextStyle(fontWeight: FontWeight.bold)),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          if (_showConsole) _buildConsolePanel(bc.maxHeight * 0.5),
        ],
      )),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// FOLDER TREE VIEW
// ─────────────────────────────────────────────────────────────────────────────

class FileTreeView extends StatefulWidget {
  final ProjectModel project;
  final Function(FileModel) onFileTap;
  final Function(FileModel) onFileLongPress;
  final Function(String folderPath) onFolderLongPress;

  const FileTreeView({
    Key? key,
    required this.project,
    required this.onFileTap,
    required this.onFileLongPress,
    required this.onFolderLongPress,
  }) : super(key: key);

  @override
  State<FileTreeView> createState() => _FileTreeViewState();
}

class _FileTreeViewState extends State<FileTreeView> {
  final Set<String> _expanded = {};

  @override
  void initState() {
    super.initState();
    for (final f in widget.project.folders) {
      if (!f.contains('/')) _expanded.add(f);
    }
  }

  static IconData _fileIcon(FileModel f) {
    final ext = f.ext;
    if (f.isBinary) {
      if ({'jpg','jpeg','png','gif','webp','bmp','svg'}.contains(ext)) return Icons.image;
      if ({'mp4','mov','avi','mkv','webm'}.contains(ext))              return Icons.videocam;
      if ({'mp3','wav','ogg','aac','flac'}.contains(ext))              return Icons.audiotrack;
      if (ext == 'pdf')                                                return Icons.picture_as_pdf;
      if ({'zip','tar','gz','rar'}.contains(ext))                      return Icons.folder_zip;
      return Icons.attach_file;
    }
    if (ext == 'css')  return Icons.palette;
    if (ext == 'js')   return Icons.javascript;
    if (ext == 'json') return Icons.data_object;
    if (ext == 'svg')  return Icons.auto_awesome_mosaic;
    if (ext == 'txt' || ext == 'md') return Icons.description;
    if (ext == 'xml')  return Icons.code;
    return Icons.html;
  }

  Color _fileIconColor(FileModel f) {
    if (f.isBinary) return Colors.grey.shade400;
    final ext = f.ext;
    if (ext == 'css')  return Colors.blue.shade300;
    if (ext == 'js')   return Colors.yellow.shade600;
    return AppColors.folderYellow;
  }

  List<Widget> _buildLevel(String parentPath, int depth) {
    final indent = depth * 20.0;
    final widgets = <Widget>[];

    final subfolders = widget.project.getSubfolders(parentPath);
    for (final folder in subfolders) {
      final name       = folder.split('/').last;
      final isExpanded = _expanded.contains(folder);
      final childCount = widget.project.getFilesInFolder(folder).length
                       + widget.project.getSubfolders(folder).length;

      widgets.add(InkWell(
        onTap:      () => setState(() => isExpanded ? _expanded.remove(folder) : _expanded.add(folder)),
        onLongPress: () => widget.onFolderLongPress(folder),
        child: Padding(
          padding: EdgeInsets.fromLTRB(indent + 8, 10, 8, 10),
          child: Row(children: [
            Icon(
              isExpanded ? Icons.folder_open : Icons.folder,
              color: AppColors.folderYellow,
              size: 22,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(name,
                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
            ),
            Text('$childCount item${childCount == 1 ? '' : 's'}',
              style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
            const SizedBox(width: 6),
            Icon(isExpanded ? Icons.expand_less : Icons.expand_more,
              size: 18, color: Colors.grey),
          ]),
        ),
      ));

      if (isExpanded) {
        widgets.add(IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                width: indent + 20,
                child: Center(
                  child: Container(
                    width: 1.5,
                    color: AppColors.folderYellow.withOpacity(0.35),
                  ),
                ),
              ),
              Expanded(child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: _buildLevel(folder, depth + 1),
              )),
            ],
          ),
        ));
      }
    }

    final files = widget.project.getFilesInFolder(parentPath);
    for (final file in files) {
      widgets.add(InkWell(
        onTap:       () => widget.onFileTap(file),
        onLongPress: () => widget.onFileLongPress(file),
        child: Padding(
          padding: EdgeInsets.fromLTRB(indent + 8, 8, 8, 8),
          child: Row(children: [
            Icon(_fileIcon(file), color: _fileIconColor(file), size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                file.name,
                style: TextStyle(
                  fontSize: 13,
                  color: file.isBinary ? Colors.grey.shade500 : null,
                  fontStyle: file.isBinary ? FontStyle.italic : FontStyle.normal,
                ),
              ),
            ),
            if (file.isBinary)
              Tooltip(
                message: 'Opens with a system app',
                child: Icon(Icons.open_in_new, size: 14, color: Colors.grey.shade500),
              ),
            if (file.lastEdit.isNotEmpty)
              Text(file.lastEdit,
                style: TextStyle(fontSize: 10, color: Colors.grey.shade600)),
          ]),
        ),
      ));
    }

    if (widgets.isEmpty) {
      widgets.add(Padding(
        padding: EdgeInsets.fromLTRB(indent + 12, 6, 8, 6),
        child: Text('Empty folder',
          style: TextStyle(fontSize: 12, color: Colors.grey.shade500,
            fontStyle: FontStyle.italic)),
      ));
    }

    return widgets;
  }

  @override
  Widget build(BuildContext context) {
    if (widget.project.files.isEmpty && widget.project.folders.isEmpty) {
      return const Center(
        child: Text('No files yet.\nTap "+ Add New File" to get started.',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.grey)));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: _buildLevel('', 0),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// PROJECT DETAIL SCREEN
// ─────────────────────────────────────────────────────────────────────────────

class ProjectDetailScreen extends StatefulWidget {
  final ProjectModel project;
  final Listenable refresh;
  final Function(FileModel) onFileTap;
  final Function(FileModel) onFileLongPress;
  final Function(String)    onFolderLongPress;
  final VoidCallback onAddFile;

  const ProjectDetailScreen({
    Key? key,
    required this.project,
    required this.refresh,
    required this.onFileTap,
    required this.onFileLongPress,
    required this.onFolderLongPress,
    required this.onAddFile,
  }) : super(key: key);

  @override
  State<ProjectDetailScreen> createState() => _ProjectDetailScreenState();
}

class _ProjectDetailScreenState extends State<ProjectDetailScreen> {
  /// Search by file name. "Related files" are files that reference a match
  /// (e.g. an HTML page that uses style.css) or that a match references.
  void _showSearch() {
    final ctrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) {
          final q = ctrl.text.trim().toLowerCase();
          final files = widget.project.files;
          final matches = q.isEmpty
              ? <FileModel>[]
              : files.where((f) => f.fullPath.toLowerCase().contains(q)).toList();

          final related = <FileModel, String>{};
          for (final g in files) {
            if (matches.contains(g)) continue;
            for (final m in matches) {
              if (!g.isBinary && g.content.toLowerCase().contains(m.name.toLowerCase())) {
                related[g] = 'uses ${m.name}';
                break;
              }
              if (!m.isBinary && m.content.toLowerCase().contains(g.name.toLowerCase())) {
                related[g] = 'linked from ${m.name}';
                break;
              }
            }
          }

          Widget header(String t) => Padding(
                padding: const EdgeInsets.fromLTRB(4, 10, 4, 4),
                child: Text(t,
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 12, color: AppColors.linkBlue)),
              );

          Widget tile(FileModel f, String subtitle) => ListTile(
                dense: true,
                leading: Icon(_FileTreeViewState._fileIcon(f),
                    color: f.isBinary ? Colors.grey.shade400 : AppColors.folderYellow),
                title: Text(f.name, overflow: TextOverflow.ellipsis),
                subtitle: Text(subtitle,
                    style: const TextStyle(fontSize: 11), overflow: TextOverflow.ellipsis),
                onTap: () {
                  Navigator.pop(ctx);
                  widget.onFileTap(f);
                },
              );

          final results = <Widget>[];
          if (q.isEmpty) {
            results.add(const Padding(
              padding: EdgeInsets.all(12),
              child: Text('Type part of a file name…',
                  style: TextStyle(color: Colors.grey, fontStyle: FontStyle.italic)),
            ));
          } else if (matches.isEmpty) {
            results.add(const Padding(
              padding: EdgeInsets.all(12),
              child: Text('No files found',
                  style: TextStyle(color: Colors.grey, fontStyle: FontStyle.italic)),
            ));
          } else {
            results.add(header('FILES (${matches.length})'));
            for (final f in matches) {
              results.add(tile(f, f.path.isEmpty ? 'Project root' : f.path));
            }
            if (related.isNotEmpty) {
              results.add(header('RELATED FILES (${related.length})'));
              related.forEach((f, why) => results.add(tile(f, why)));
            }
          }

          return AlertDialog(
            title: const Text('Search files'),
            content: SizedBox(
              width: double.maxFinite,
              height: MediaQuery.of(ctx).size.height * 0.5,
              child: Column(
                children: [
                  TextField(
                    controller: ctrl,
                    autofocus: true,
                    onChanged: (_) => setLocal(() {}),
                    decoration: const InputDecoration(
                      hintText: 'File name',
                      prefixIcon: Icon(Icons.search),
                      isDense: true,
                    ),
                  ),
                  Expanded(child: ListView(children: results)),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close')),
            ],
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.refresh,
      builder: (context, _) => Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        appBar: AppBar(
          backgroundColor: Colors.black,
          title: Text(widget.project.name),
          actions: [
            IconButton(
              icon: const Icon(Icons.search),
              tooltip: 'Search files',
              onPressed: _showSearch,
            ),
            IconButton(
              icon: const Icon(Icons.create_new_folder_outlined),
              tooltip: 'Add file',
              onPressed: widget.onAddFile,
            ),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.all(12),
          children: [
            Card(
              margin: const EdgeInsets.only(bottom: 16),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Row(children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: SizedBox(
                      width: 56, height: 56,
                      child: widget.project.iconPath != null
                          ? Image.file(File(widget.project.iconPath!),
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) =>
                                  const Icon(Icons.terrain, size: 36))
                          : const Icon(Icons.terrain, size: 36),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (widget.project.description.isNotEmpty)
                        Text(widget.project.description,
                          style: const TextStyle(fontStyle: FontStyle.italic, fontSize: 13)),
                      const SizedBox(height: 4),
                      Text('Created ${widget.project.createdAt}  •  '
                           '${widget.project.files.length} file(s)',
                        style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
                    ],
                  )),
                ]),
              ),
            ),

            InkWell(
              onTap: widget.onAddFile,
              borderRadius: BorderRadius.circular(8),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                margin: const EdgeInsets.only(bottom: 14),
                decoration: BoxDecoration(
                  border: Border.all(color: AppColors.linkBlue.withOpacity(0.5),
                    style: BorderStyle.solid),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Row(children: [
                  Icon(Icons.add, color: AppColors.linkBlue, size: 20),
                  SizedBox(width: 8),
                  Text('Add New File to Project',
                    style: TextStyle(color: AppColors.linkBlue,
                      fontWeight: FontWeight.w600)),
                ]),
              ),
            ),

            FileTreeView(
              project: widget.project,
              onFileTap:         widget.onFileTap,
              onFileLongPress:   widget.onFileLongPress,
              onFolderLongPress: widget.onFolderLongPress,
            ),
          ],
        ),
      ),
    );
  }
}



String _fillTemplate(String template, String content) {
  final parts = template.split('%%CONTENT%%');
  return parts[0] + content + parts[1];
}

const String _cssPreviewTemplate = r'''<!DOCTYPE html>
<html>
<head>
<meta name="viewport" content="width=device-width,initial-scale=1">
<style>%%CONTENT%%</style>
</head>
<body>
<h1>CSS Preview</h1>
<p class="example">Example paragraph</p>
<div class="box">Example div</div>
<button class="btn">Example button</button>
<a href="#" class="link">Example link</a>
<ul><li class="item">List item 1</li><li class="item">List item 2</li></ul>
</body>
</html>''';

const String _jsPreviewTemplate = r'''<!DOCTYPE html>
<html>
<head>
<meta name="viewport" content="width=device-width,initial-scale=1">
<style>body{font-family:monospace;padding:12px;background:#1e1e1e;color:#d4d4d4}
#output{white-space:pre-wrap;border-top:1px solid #444;margin-top:12px;padding-top:8px}</style>
</head>
<body>
<b>JavaScript Preview</b>
<div id="output"></div>
<script>
(function(){
  var out = document.getElementById('output');
  function show(prefix, args) {
    out.textContent += prefix + Array.prototype.map.call(args, function(a) {
      try { return (typeof a === 'object') ? JSON.stringify(a) : String(a); }
      catch (e) { return String(a); }
    }).join(' ') + '\n';
  }
  ['log', 'info', 'warn', 'error'].forEach(function(level) {
    var orig = console[level].bind(console);
    console[level] = function() {
      show(level === 'log' || level === 'info' ? '' : level.toUpperCase() + ': ', arguments);
      orig.apply(null, arguments);
    };
  });
  window.onerror = function(msg, src, line) {
    out.textContent += '\u274c ' + msg + (line ? ' (line ' + line + ')' : '') + '\n';
    return true;
  };
})();
</script>
<script>
%%CONTENT%%
</script>
</body>
</html>''';

// Wraps CSS/JS content in a minimal HTML page for preview.
// HTML/HTML3 is returned unchanged.
String _buildPreviewHtml(String filename, String content) {
  final ext = filename.contains('.') ? filename.split('.').last.toLowerCase() : 'html';
  if (ext == 'css') {
    return _fillTemplate(_cssPreviewTemplate, content);
  }
  if (ext == 'js') {
    // a literal </script> inside user code would end the block early
    return _fillTemplate(_jsPreviewTemplate, content.replaceAll('</script', r'<\/script'));
  }
  return content; // html / html3 — use as-is
}

// =============================================================================
// FLAPPY FISH — Easter Egg Game
// Tap the app logo 5× to unlock. No assets required (emoji fallbacks built in).
// =============================================================================

class FlappyFishGame extends StatefulWidget {
  const FlappyFishGame({Key? key}) : super(key: key);
  @override
  _FlappyFishGameState createState() => _FlappyFishGameState();
}

class _FlappyFishGameState extends State<FlappyFishGame> {
  double fishY    = 0.5;
  double velocity = 0;
  static const double gravity    = 2.4;   // screen-heights / s²
  static const double jumpV      = -0.85; // screen-heights / s
  static const double pipeSpeed  = 0.55;  // screen-widths  / s
  static const double pipeWidth  = 0.18;
  static const double pipeGap    = 0.30;

  double pipeX         = 1.0;
  double pipeHeightTop = 0.3;
  bool   _scored       = false;

  // ── Parallax: progress 0..1 of one screen width ──────────────────
  double bgFar  = 0;
  double bgMid  = 0;
  double bgFore = 0;

  // ── Game state ─────────────────────────────────────────────────────────────
  int   score       = 0;
  bool  gameOver    = false;
  bool  gameStarted = false;
  Timer? _gameTimer;

  // Fixed-timestep loop
  double _lastTs = 0;
  double _accum  = 0;
  static const double _dt = 1 / 60;

  // Screen size in px (updated in build) — used by the pixel-space hitbox
  double _sw = 400;
  double _sh = 800;
  double get _fishSize => _sw * 0.1;

  @override
  void dispose() {
    _gameTimer?.cancel();
    super.dispose();
  }

  double _newPipeTop() => Random().nextDouble() * 0.4 + 0.12;

  void _startGame() {
    setState(() {
      gameStarted   = true;
      gameOver      = false;
      fishY         = 0.5;
      velocity      = 0;
      pipeX         = 1.0;
      _scored       = false;
      score         = 0;
      pipeHeightTop = _newPipeTop();
      bgFar = bgMid = bgFore = 0;
      _lastTs       = DateTime.now().millisecondsSinceEpoch / 1000;
      _accum        = 0;
    });
    _gameTimer?.cancel();
    _gameTimer = Timer.periodic(const Duration(milliseconds: 16), (_) => _tick());
  }

  void _tick() {
    if (!gameStarted || gameOver) return;
    final now = DateTime.now().millisecondsSinceEpoch / 1000;
    final frame = (now - _lastTs).clamp(0.0, 0.05);
    _lastTs = now;
    _accum += frame;
    while (_accum >= _dt && !gameOver) {
      _step();
      _accum -= _dt;
    }
    if (mounted) setState(() {});
  }

  void _step() {
    // physics
    velocity += gravity * _dt;
    fishY    += velocity * _dt;

    // pipe
    pipeX -= pipeSpeed * _dt;
    if (pipeX < -pipeWidth) {
      pipeX         = 1.0;
      pipeHeightTop = _newPipeTop();
      _scored       = false;
    }

    // parallax (slow far layer, fast foreground)
    bgFar  = (bgFar  + 0.03 * _dt) % 1.0;
    bgMid  = (bgMid  + 0.08 * _dt) % 1.0;
    bgFore = (bgFore + 0.15 * _dt) % 1.0;

    _checkCollision();
  }

  void _checkCollision() {
    final r  = _fishSize * 0.38;
    final fx = _sw * 0.12 + _fishSize / 2;
    final fy = fishY * _sh;

    // floor / ceiling
    if (fy - r <= 0 || fy + r >= _sh) { _endGame(); return; }

    final pipeLeft  = pipeX * _sw;
    final pipeRight = pipeLeft + pipeWidth * _sw;
    if (fx + r > pipeLeft && fx - r < pipeRight) {
      final gapTop    = pipeHeightTop * _sh;
      final gapBottom = gapTop + pipeGap * _sh;
      if (fy - r < gapTop || fy + r > gapBottom) { _endGame(); return; }
    }

    // score when the pipe has fully passed the fish
    if (!_scored && pipeRight < fx - r) {
      _scored = true;
      score++;
    }
  }

  void _endGame() {
    if (!gameOver && mounted) {
      setState(() { gameOver = true; gameStarted = false; });
      _gameTimer?.cancel();
    }
  }

  void _jump() {
    if (gameOver) return;
    if (!gameStarted) { _startGame(); return; }
    setState(() => velocity = jumpV);
  }

  @override
  Widget build(BuildContext context) {
    final sw       = MediaQuery.of(context).size.width;
    final sh       = MediaQuery.of(context).size.height;
    _sw = sw;
    _sh = sh;
    final fishSize = _fishSize;
    final pipeW    = pipeWidth * sw;
    final gapPx    = pipeGap   * sh;

    Widget bgLayer(String asset, Color fallback, double progress) {
      Widget img() => Image.asset(asset,
          width: sw, height: sh, fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => Container(width: sw, height: sh, color: fallback));
      return Positioned.fill(
        child: Stack(children: [
          Positioned(left: -progress * sw,      top: 0, width: sw, height: sh, child: img()),
          Positioned(left: sw - progress * sw,  top: 0, width: sw, height: sh, child: img()),
        ]),
      );
    }

    return Scaffold(
      backgroundColor: Colors.cyan.shade800,
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _jump,
        child: Stack(
          fit: StackFit.expand,
          children: [
            bgLayer('assets/background_far.png', Colors.cyan.shade700, bgFar),
            bgLayer('assets/background_mid.png', Colors.cyan.shade600, bgMid),
            bgLayer('assets/background.png',     Colors.cyan.shade500, bgFore),

            // Top pipe
            Positioned(
              left: pipeX * sw, top: 0,
              width: pipeW, height: pipeHeightTop * sh,
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Colors.green.shade800, Colors.green.shade600]),
                  borderRadius: const BorderRadius.only(
                    bottomLeft: Radius.circular(16),
                    bottomRight: Radius.circular(16)),
                ),
              ),
            ),

            // Bottom pipe
            Positioned(
              left: pipeX * sw,
              top:  (pipeHeightTop * sh) + gapPx,
              width: pipeW,
              height: sh - (pipeHeightTop * sh + gapPx),
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Colors.green.shade800, Colors.green.shade600]),
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(16),
                    topRight: Radius.circular(16)),
                ),
              ),
            ),

            // Fish (drawn centered on fishY — same point the hitbox uses)
            Positioned(
              left: sw * 0.12,
              top:  fishY * sh - fishSize / 2,
              child: Transform.rotate(
                angle: (velocity * 0.6).clamp(-0.5, 0.8),
                child: Image.asset(
                  'assets/fish.png',
                  width: fishSize, height: fishSize, fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) => SizedBox(
                    width: fishSize, height: fishSize,
                    child: Center(
                      child: Text('🐟',
                        style: TextStyle(fontSize: fishSize * 0.8))),
                  ),
                ),
              ),
            ),

            // Score
            Positioned(
              top: 40, left: 0, right: 0,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.65),
                    borderRadius: BorderRadius.circular(40),
                  ),
                  child: Text("Score: $score",
                    style: const TextStyle(color: Colors.white,
                      fontSize: 28, fontWeight: FontWeight.bold)),
                ),
              ),
            ),

            // Start screen
            if (!gameStarted && !gameOver)
              Center(
                child: Container(
                  padding: const EdgeInsets.all(28),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.85),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.cyanAccent, width: 2),
                  ),
                  child: Column(mainAxisSize: MainAxisSize.min, children: const [
                    Text("🐟 FLAPPY FISH 🐟",
                      style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold,
                        color: Colors.cyanAccent)),
                    SizedBox(height: 16),
                    Text("Tap to start!",
                      style: TextStyle(fontSize: 18, color: Colors.white)),
                    SizedBox(height: 8),
                    Text("Tap anywhere to jump",
                      style: TextStyle(fontSize: 13, color: Colors.white70)),
                  ]),
                ),
              ),

            // Game over screen
            if (gameOver)
              Center(
                child: Container(
                  padding: const EdgeInsets.all(28),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.9),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.red, width: 2),
                  ),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    const Text("💀 GAME OVER 💀",
                      style: TextStyle(color: Colors.red,
                        fontSize: 28, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 16),
                    Text("Score: $score",
                      style: const TextStyle(color: Colors.white,
                        fontSize: 26, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 20),
                    ElevatedButton(
                      onPressed: _startGame,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.androidGreen,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 36, vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(30)),
                      ),
                      child: const Text("Play Again",
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    ),
                    const SizedBox(height: 10),
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text("Back to app",
                        style: TextStyle(color: Colors.white70)),
                    ),
                  ]),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
