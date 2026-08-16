import 'dart:async';
import 'dart:math';
import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider/path_provider.dart';
import 'package:archive/archive.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:flutter/gestures.dart';
import 'package:http/http.dart' as http;
import 'package:open_file/open_file.dart';

/* =============================================================================
   HTML RUNNER: DEFINITIVE EDITION (IMPROVED)
   =============================================================================
   Changes:
   - Added try-catch blocks for all risky operations.
   - Optimized line number widget (no +50 buffer, efficient rebuilds).
   - Added error handling for images (project icons, profile avatars).
   - Inline comments for non‑trivial logic.
   - Added long-press on title for update checking.
   - Added version/copyright footer in settings.
   - FIXED: Line numbers now scroll in sync with code editor.
   - FIXED: WebView touch responsiveness (gestures, viewport, permissions).
   - ADDED: Real update checking from Fish Gang server.
   =============================================================================
*/

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  // In release mode, Flutter swallows build exceptions and shows blank.
  // Override ErrorWidget so crashes show a visible message instead.
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
  static const Color nostalgiaBlack   = Color(0xFF000000); // scaffold bg
  static const Color holoPanelBg      = Color(0xFF1B1B1B); // card/panel bg
  static const Color holoPanelBg2     = Color(0xFF262626); // slightly lighter panel
  static const Color holoBlue         = Color(0xFF33B5E5); // Holo Blue Light (on dark)
  static const Color holoBlueDark     = Color(0xFF0099CC); // pressed / Holo Blue (on light)
  static const Color holoDivider      = Color(0xFF3D3D3D); // borders/dividers
  static const Color holoTextPrimary  = Color(0xFFFFFFFF);
  static const Color holoTextSecond   = Color(0xFFAAAAAA);
  // ── Holo Light (Theme.Holo.Light) ────────────────────────────────────────
  static const Color holoLightBg      = Color(0xFFF2F2F2); // Holo.Light window bg
  static const Color holoLightPanel   = Color(0xFFFFFFFF); // card/panel
  static const Color holoLightPanel2  = Color(0xFFEBEBEB); // secondary panel
  static const Color holoLightDivider = Color(0xFFC8C8C8);
  static const Color holoLightTextPri = Color(0xFF1A1A1A);
  static const Color holoLightTextSec = Color(0xFF666666);
  // ── Shared ───────────────────────────────────────────────────────────────
  static const Color fishGangTeal     = Color(0xFF5FD4C7); // Fish Gang accent
  static const Color androidGreen     = Color(0xFF99CC00); // Holo green
  static const Color errorRed         = Color(0xFFFF4444);
  static const Color folderYellow     = Color(0xFFFFBB33);
  static const Color linkBlue         = Color(0xFF33B5E5);
  static const Color gutterGray       = Color(0xFF37474F);
  static const Color editorBackground = Color(0xFF1E1E1E);
  // ── Tutorial & WebRunner panel ────────────────────────────────────────────
  static const Color panelBg      = Color(0xE6000000); // webrunner tool panel
  static const Color tutorialBg   = Color(0xFF1a1a2e); // tutorial screen bg
  static const Color tutorialCard = Color(0xFF16213e); // tutorial card bg
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
// SECTION 2: DATA MODELS
// -----------------------------------------------------------------------------


// =============================================================================
// STORAGE HELPER
// =============================================================================

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

class ProjectModel {
  String id;
  String name;
  String description;
  String? iconPath;
  String createdAt;
  String lastModified;
  List<FileModel> files;
  List<String>    folders; // virtual folder paths (e.g. "pages", "pages/css")

  ProjectModel({
    required this.id,
    required this.name,
    this.description = "",
    this.iconPath,
    required this.createdAt,
    required this.lastModified,
    required this.files,
    this.folders = const [],
  });

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

  // ── Folder helpers ──────────────────────────────────────────────────────

  List<FileModel> getFilesInFolder(String folderPath) =>
      files.where((f) => f.path == folderPath).toList();

  List<String> getSubfolders(String parentPath) => folders.where((folder) {
    if (parentPath.isEmpty) return !folder.contains('/');
    return folder.startsWith('\$parentPath/') &&
        folder.substring(parentPath.length + 1).contains('/') == false;
  }).toList();

  /// Create a file at "pages/about.html" — auto-creates parent folders.
  void addFileWithPath(String fileNameWithPath, String content) {
    String path = "";
    String fileName = fileNameWithPath;
    if (fileNameWithPath.contains('/')) {
      path     = fileNameWithPath.substring(0, fileNameWithPath.lastIndexOf('/'));
      fileName = fileNameWithPath.substring(fileNameWithPath.lastIndexOf('/') + 1);
      // ensure every ancestor folder exists
      String cur = "";
      for (final part in path.split('/')) {
        cur = cur.isEmpty ? part : '\$cur/\$part';
        if (!folders.contains(cur)) folders.add(cur);
      }
    }
    files.add(FileModel(
      id:       DateTime.now().millisecondsSinceEpoch.toString(),
      name:     fileName,
      content:  content,
      lastEdit: DateFormat('HH:mm').format(DateTime.now()),
      path:     path,
    ));
  }

  void moveFile(FileModel file, String newPath) {
    files.remove(file);
    file.path     = newPath;
    file.lastEdit = DateFormat('HH:mm').format(DateTime.now());
    files.add(file);
    _updateFolders();
  }

  void moveFolder(String oldPath, String newPath) {
    for (final f in files) {
      if (f.path == oldPath) {
        f.path = newPath;
      } else if (f.path.startsWith('\$oldPath/')) {
        f.path = f.path.replaceFirst(oldPath, newPath);
      }
      f.lastEdit = DateFormat('HH:mm').format(DateTime.now());
    }
    _updateFolders();
  }

  void renameFile(FileModel file, String newNameWithPath) {
    String newPath = "";
    String newName = newNameWithPath;
    if (newNameWithPath.contains('/')) {
      newPath = newNameWithPath.substring(0, newNameWithPath.lastIndexOf('/'));
      newName = newNameWithPath.substring(newNameWithPath.lastIndexOf('/') + 1);
      String cur = "";
      for (final part in newPath.split('/')) {
        cur = cur.isEmpty ? part : '\$cur/\$part';
        if (!folders.contains(cur)) folders.add(cur);
      }
    }
    file.name     = newName;
    file.path     = newPath;
    file.lastEdit = DateFormat('HH:mm').format(DateTime.now());
    _updateFolders();
  }

  void _updateFolders() {
    final Set<String> rebuilt = {};
    for (final f in files) {
      if (f.path.isNotEmpty) {
        rebuilt.add(f.path);
        String cur = "";
        for (final part in f.path.split('/')) {
          cur = cur.isEmpty ? part : '\$cur/\$part';
          rebuilt.add(cur);
        }
      }
    }
    folders = rebuilt.toList();
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

  // Extensions editable in the IDE
  static const _editableExts = {'html', 'htm', 'html3', 'css', 'js'};

  bool get isEditable {
    final ext = name.contains('.') ? name.split('.').last.toLowerCase() : '';
    return _editableExts.contains(ext);
  }

  /// Binary files (images, pdfs, etc.) — open via Android "Open with..."
  bool get isBinary => externalPath != null;

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
// SECTION 3: CORE APP WIDGET
// -----------------------------------------------------------------------------

class HTMLRunnerApp extends StatefulWidget {
  const HTMLRunnerApp({Key? key}) : super(key: key);

  @override
  _HTMLRunnerAppState createState() => _HTMLRunnerAppState();
}

class _HTMLRunnerAppState extends State<HTMLRunnerApp> {
  ThemeMode _themeMode = ThemeMode.dark; // default to Holo Dark; user can switch to Light in settings

  @override
  void initState() {
    super.initState();
    _loadThemePreference();
    _setupStorage();
    _createReadmeFile();
    _checkFirstLaunch();
  }

  Future<void> _setupStorage() async {
    try {
      await StorageHelper.getBaseDirectory();
      await StorageHelper.getFilesDirectory();
      await StorageHelper.getZipsDirectory();
    } catch (e) {
      debugPrint('Storage setup error: \$e');
    }
  }

  Future<void> _createReadmeFile() async {
    try {
      final directory = await getExternalStorageDirectory();
      if (directory == null) return;
      final readmeFile = File('\${directory.path}/App Data/README.txt');
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
      debugPrint('README write error: \$e');
    }
  }

  Future<void> _checkFirstLaunch() async {
    final prefs = await SharedPreferences.getInstance();
    final seen  = prefs.getBool('has_seen_tutorial') ?? false;
    if (!seen && mounted) {
      await prefs.setBool('has_seen_tutorial', true);
      // Wait for the widget tree to settle before pushing
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          Navigator.push(context,
            MaterialPageRoute(builder: (_) => const TutorialScreen()));
        }
      });
    }
  }

  Future<void> _loadThemePreference() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      setState(() {
        _themeMode = ThemeMode.values[prefs.getInt('theme_pref') ?? 2];
      });
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

    // ── Theme.Holo.Light ──────────────────────────────────────────────────
    // AppBar stays dark even in Holo.Light (matches Theme.Holo.Light.DarkActionBar)
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
      // ActionBar is dark even on Holo.Light — same as Theme.Holo.Light.DarkActionBar
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
      themeMode: _themeMode == ThemeMode.light ? ThemeMode.light : ThemeMode.dark,
      home: MainDashboard(onThemeChange: _updateTheme),
    );
  }
}

// -----------------------------------------------------------------------------
// FISH GANG AUTH: User model & sign-in helper
// Uses Firebase Identity Toolkit REST API — no SDK, no google-services.json.
// Same Firebase project as the Fish Gang website (fish-gang-website).
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
  // Services
  final ImagePicker _imagePicker = ImagePicker();

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
  // move-file system
  ProjectModel? _activeProject; // project being moved within
  dynamic      _itemToMove;
  bool         _isMovingFile  = false;
  String       _movingItemName = '';
  String       _movingItemPath = '';
  
  // Data Storage
  List<ProjectModel> _projects = [];
  List<FileModel> _standaloneFiles = [];

  // Animation & Timers
  late AnimationController _refreshController;
  late AnimationController _logoSpinController;
  Timer? _syncTimer;

  // Warning States for Auth Screen
  bool _showGoogleWarning = false;
  bool _showLocalWarning = false;
  
  // --- New Security State Variables ---
  String _currentCaptchaTheme = "";
  List<int> _selectedCaptchaIndices = [];
  List<IconData> _captchaGridItems = [];
  List<IconData> _correctThemeIcons = [];
   
  // --- Easter Egg State ---
  int _logoTapCount = 0;
  Timer? _tapResetTimer;
  bool _isLogoSpinning = false;
  Color _logoColor = Colors.white;
  
  // --- Version order for update checking ---
  final List<String> _versionOrder = [
    "1.6.7",
    "2.0",
    "2.1",
    "2.4",
    "2.8",
    "3.0",
    "4.0 Beta",
    "4.5",
    "4.7",
    "5.0",
    "6.0",
    "6.7",
    "7.0",
    "8.0",
    "9.0",
    "10.0"
  ];

  bool _isNewerVersion(String current, String latest) {
    int currentIndex = _versionOrder.indexOf(current);
    int latestIndex = _versionOrder.indexOf(latest);
    if (currentIndex == -1 || latestIndex == -1) return false;
    return latestIndex > currentIndex;
  }
  
  @override
  void initState() {
    super.initState();
    _refreshController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    );
    _logoSpinController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 7),
    );

    _initializeAuth();
    _loadData();

    _syncTimer = Timer.periodic(const Duration(minutes: 10), (timer) {
      _triggerSync();
    });
  }

  @override
  void dispose() {
    _refreshController.dispose();
    _syncTimer?.cancel();
    _logoSpinController.dispose();
    _tapResetTimer?.cancel();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  // --- INITIALIZATION ---

  void _initializeAuth() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final permsDone = prefs.getBool('perms_done') ?? false;
      final uid   = prefs.getString('fg_uid');
      final email = prefs.getString('fg_email');
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
        setState(() {
          _currentUser = user;
          _isLocalMode = false;
        });
        _emailController.clear();
        _passwordController.clear();
      } else {
        final msg = (data['error']?['message'] as String?) ?? 'Login failed';
        // Make Firebase error messages friendlier
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
      setState(() => _isSigningIn = false);
    }
  }

  // --- UPDATE CHECK (REAL) ---
  Future<void> _checkForUpdates() async {
    const currentVersion = "1.6.7";
    const pageUrl = "https://fish-gang.netlify.app/appstore%E2%89%A0data=html_runner";

    try {
      final response = await http.get(Uri.parse(pageUrl));
      if (response.statusCode == 200) {
        final versionRegex = RegExp(r'<span id="fg-version"[^>]*>(.*?)</span>');
        final versionMatch = versionRegex.firstMatch(response.body);
        final linkRegex = RegExp(r"'1\.6\.7': '([^']+)'");
        final linkMatch = linkRegex.firstMatch(response.body);
        
        if (versionMatch != null && linkMatch != null) {
          final latestVersion = versionMatch.group(1)!.trim();
          final downloadUrl = linkMatch.group(1)!;
          
          if (_isNewerVersion(currentVersion, latestVersion)) {
            _showUpdateDialog(downloadUrl, latestVersion);
          } else {
            _showUpToDateDialog();
          }
        } else {
          _showErrorDialog("Could not find version info.");
        }
      } else {
        _showErrorDialog("Could not reach update server.");
      }
    } catch (e) {
      _showErrorDialog("Network error. Check your connection.");
    }
  }

  void _showUpdateDialog(String url, String version) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text("🐟 Update Available"),
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
                // ignore: use_build_context_synchronously
                Navigator.pop(context); // close progress
                // ignore: use_build_context_synchronously
                Navigator.pop(context); // close update dialog
                await OpenFile.open(file.path);
              } catch (e) {
                // ignore: use_build_context_synchronously
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
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("OK"),
          ),
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
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("OK"),
          ),
        ],
      ),
    );
  }

  void _onLogoTap() {
    setState(() {
      _logoColor = AppColors.linkBlue;
    });
    
    Future.delayed(const Duration(milliseconds: 100), () {
      if (mounted) setState(() => _logoColor = Colors.white);
    });

    _logoTapCount++;
    
    _tapResetTimer?.cancel();
    _tapResetTimer = Timer(const Duration(seconds: 2), () {
      setState(() => _logoTapCount = 0);
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
        title: const Text("🛠️ Build Info", style: TextStyle(fontWeight: FontWeight.bold)),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildInfoRow("📱", "App Name",    "HTML Runner"),
              _buildInfoRow("🔢", "Version",     "1.6.7+1"),
              _buildInfoRow("📝", "Lines",       "4125 lines"),
              _buildInfoRow("🎨", "UI Style",    "Android 4.2 Jellybean"),
              _buildInfoRow("💚", "Framework",   "Flutter/Dart"),
              _buildInfoRow("🔧", "SDK",         "Android SDK 36"),
              _buildInfoRow("📦", "Package",     "com.chirag.html_runner"),
              _buildInfoRow("👨\u200d💻", "Dev", "Chirag Shylendra"),
              _buildInfoRow("🐙", "GitHub",      "@chirag7gaming"),
              _buildInfoRow("⚖️", "License",     "MIT License"),
              _buildInfoRow("💡", "Inspiration", "Black India Day and also 67🤷🏼"),
              const SizedBox(height: 8),
              const Text(
                "Made in 🇮🇳 with ❤️  •  Zero ads. Forever free.",
                style: TextStyle(fontStyle: FontStyle.italic, fontSize: 11),
              ),
              const SizedBox(height: 12),
              Row(
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
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Close",
              style: TextStyle(color: AppColors.androidGreen)),
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
    if (resolved == null || resolved.isEmpty) {
      Fluttertoast.showToast(msg: "No file path — reimport this file to open with another app");
      return;
    }
    final result = await OpenFile.open(resolved);
    if (result.type != ResultType.done) {
      Fluttertoast.showToast(msg: "No app found to open this file type");
    }
  }

  // --- IMPORT PROJECT ZIP (folder-aware) ---

  Future<void> _importProjectZip() async {
    try {
      final result = await FilePicker.platform.pickFiles(
          type: FileType.custom, allowedExtensions: ['zip']);
      if (result == null || result.files.single.path == null) return;

      final zipFile = File(result.files.single.path!);
      final archive = ZipDecoder().decodeBytes(await zipFile.readAsBytes());

      final List<FileModel> extracted = [];
      final List<String>    skipped   = [];
      final Set<String>     folders   = {};

      for (final entry in archive) {
        if (!entry.isFile) continue;
        final fullPath  = entry.name;
        final fileName  = fullPath.split('/').last;
        final folderPath = fullPath.contains('/')
            ? fullPath.substring(0, fullPath.lastIndexOf('/'))
            : "";

        if (fileName.endsWith('.html') || fileName.endsWith('.htm')) {
          final content = utf8.decode(entry.content as List<int>);
          extracted.add(FileModel(
            id:       DateTime.now().millisecondsSinceEpoch.toString() + fullPath,
            name:     fileName,
            content:  content,
            lastEdit: DateFormat('HH:mm').format(DateTime.now()),
            path:     folderPath,
          ));
          if (folderPath.isNotEmpty) {
            folders.add(folderPath);
            String cur = "";
            for (final part in folderPath.split('/')) {
              cur = cur.isEmpty ? part : '\$cur/\$part';
              folders.add(cur);
            }
          }
        } else {
          skipped.add(fullPath);
        }
      }

      if (skipped.isNotEmpty && mounted) {
        showDialog(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text("Import Warning",
                style: TextStyle(color: AppColors.errorRed)),
            content: Text("\${skipped.length} non-HTML file(s) were skipped:\n"
                "\${skipped.take(5).join(', ')}"
                "\${skipped.length > 5 ? '...' : ''}"),
            actions: [TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text("OK"))],
          ),
        );
      }

      if (extracted.isNotEmpty) {
        final projectName =
            result.files.single.name.replaceAll('.zip', '');
        setState(() {
          _projects.add(ProjectModel(
            id:           DateTime.now().millisecondsSinceEpoch.toString(),
            name:         projectName,
            description:  "Imported from ZIP",
            createdAt:    DateFormat('yyyy-MM-dd').format(DateTime.now()),
            lastModified: DateFormat('HH:mm').format(DateTime.now()),
            files:   extracted,
            folders: folders.toList(),
          ));
        });
        _saveData();
        Fluttertoast.showToast(
            msg: "Imported \${extracted.length} files as '\$projectName'",
            backgroundColor: AppColors.androidGreen);
      } else if (skipped.isNotEmpty) {
        Fluttertoast.showToast(
            msg: "No HTML files found in ZIP",
            backgroundColor: AppColors.errorRed);
      }
    } catch (e) {
      Fluttertoast.showToast(msg: "Failed to import ZIP: \$e");
    }
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
                      f.path == folderPath || f.path.startsWith('\$folderPath/'));
                  project.folders.removeWhere((f) =>
                      f == folderPath || f.startsWith('\$folderPath/'));
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
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text("Cancel")),
          ElevatedButton(
            onPressed: () {
              final newName = ctrl.text.trim();
              if (newName.isEmpty) {
                Fluttertoast.showToast(msg: "Folder name cannot be empty");
                return;
              }
              final parent  = oldPath.contains('/')
                  ? oldPath.substring(0, oldPath.lastIndexOf('/'))
                  : "";
              final newPath = parent.isEmpty ? newName : '\$parent/\$newName';
              for (final f in project.files) {
                if (f.path == oldPath) f.path = newPath;
                else if (f.path.startsWith('\$oldPath/')) {
                  f.path = f.path.replaceFirst(oldPath, newPath);
                }
              }
              project.folders = project.folders.map((f) {
                if (f == oldPath) return newPath;
                if (f.startsWith('\$oldPath/')) return f.replaceFirst(oldPath, newPath);
                return f;
              }).toList();
              Navigator.pop(ctx);
              _saveData();
              setState(() {});
              Fluttertoast.showToast(msg: "Renamed to \$newName");
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
    if (_activeProject == null) return;
    final destinations = ["(Root)", ..._activeProject!.folders];
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text("Move \${_isMovingFile ? 'File' : 'Folder'}: \$_movingItemName"),
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
                  if (_movingItemPath == targetPath) {
                    Navigator.pop(context);
                    Fluttertoast.showToast(msg: "Already in this location");
                    return;
                  }
                  if (_isMovingFile && _itemToMove is FileModel) {
                    _activeProject!.moveFile(_itemToMove as FileModel, targetPath);
                  } else if (!_isMovingFile && _itemToMove is String) {
                    if (targetPath.startsWith(_movingItemPath) &&
                        _movingItemPath.isNotEmpty) {
                      Navigator.pop(context);
                      Fluttertoast.showToast(msg: "Cannot move a folder into itself");
                      return;
                    }
                    _activeProject!.moveFolder(_movingItemPath, targetPath);
                  }
                  Navigator.pop(context);
                  _saveData();
                  setState(() {});
                  Fluttertoast.showToast(msg: "Moved successfully!");
                },
              );
            }).toList(),
          ),
        ),
        actions: [TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Cancel"))],
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
        final subDir = f.path.isNotEmpty
            ? Directory('${projDir.path}/${f.path}')
            : projDir;
        await subDir.create(recursive: true);
        final dest = '${subDir.path}/${f.name}';

        if (f.isBinary && f.externalPath != null) {
          await File(f.externalPath!).copy(dest);
        } else {
          final content = (overrideContent != null && f.id == mainFile.id)
              ? overrideContent
              : f.content;
          await File(dest).writeAsString(content);
        }
      }

      // If the file being previewed isn't saved yet, write current content
      final mainInProject = project.files.any((f) => f.id == mainFile.id);
      final mainSubDir = mainFile.path.isNotEmpty
          ? Directory('${projDir.path}/${mainFile.path}')
          : projDir;
      await mainSubDir.create(recursive: true);
      final mainPath = '${mainSubDir.path}/${mainFile.name}';

      if (!mainInProject) {
        await File(mainPath).writeAsString(overrideContent ?? mainFile.content);
      }

      if (!mounted) return;
      Navigator.push(context, MaterialPageRoute(
        builder: (_) => WebRunnerScreen(filePath: mainPath),
      ));
    } catch (e) {
      Fluttertoast.showToast(msg: 'Preview failed: $e');
    }
  }

    void _showFileCreationMenu() {
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
                borderRadius: BorderRadius.circular(10)
              )
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
                _openCodeEditor(null);
              },
            ),
            ListTile(
              leading: const Icon(Icons.file_open, color: AppColors.androidGreen),
              title: const Text("Import from Storage"),
              subtitle: const Text("HTML → IDE · Other files → system app", style: TextStyle(fontSize: 11)),
              onTap: () {
                Navigator.pop(context);
                _importAnyFile();
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

  Future<void> _importAnyFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(type: FileType.any);
      if (result == null) return;
      final picked = result.files.first;
      final name   = picked.name;
      final path   = picked.path;
      if (path == null) { Fluttertoast.showToast(msg: "Could not get file path."); return; }

      final ext = name.contains('.') ? name.split('.').last.toLowerCase() : '';
      const editable = {'html', 'htm', 'html3', 'css', 'js'};

      if (editable.contains(ext)) {
        // Read as text and open in the IDE editor
        final content = await File(path).readAsString();
        _openCodeEditor(FileModel(
          id:       DateTime.now().millisecondsSinceEpoch.toString(),
          name:     name,
          content:  content,
          lastEdit: DateFormat('HH:mm').format(DateTime.now()),
        ));
      } else {
        // Binary file — add to standalone files with externalPath so it can
        // be tapped to open with the Android system chooser, or added to projects.
        final file = FileModel(
          id:           DateTime.now().millisecondsSinceEpoch.toString(),
          name:         name,
          content:      '',
          lastEdit:     DateFormat('HH:mm').format(DateTime.now()),
          externalPath: path,
        );
        setState(() => _standaloneFiles.add(file));
        _saveData();
        Fluttertoast.showToast(msg: "Added \"$name\" — tap to open with system");
      }
    } catch (e) {
      Fluttertoast.showToast(msg: "Import failed: $e");
    }
  }

  // --- DATA PERSISTENCE ---

  Future<void> _saveData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      
      String projectsJson = jsonEncode(_projects.map((p) => p.toJson()).toList());
      String filesJson = jsonEncode(_standaloneFiles.map((f) => f.toJson()).toList());
      
      await prefs.setString('projects_db', projectsJson);
      await prefs.setString('files_db', filesJson);
      await prefs.setBool('is_local_mode', _isLocalMode);
    } catch (e) {
      Fluttertoast.showToast(msg: "Failed to save data: $e");
      debugPrint('Save error: $e');
    }
  }

  Future<void> _loadData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      
      _isLocalMode = prefs.getBool('is_local_mode') ?? false;

      String? projectsJson = prefs.getString('projects_db');
      if (projectsJson != null) {
        Iterable list = jsonDecode(projectsJson);
        _projects = list.map((model) => ProjectModel.fromJson(model)).toList();
      }

      String? filesJson = prefs.getString('files_db');
      if (filesJson != null) {
        Iterable list = jsonDecode(filesJson);
        _standaloneFiles = list.map((model) => FileModel.fromJson(model)).toList();
      }
    } catch (e) {
      Fluttertoast.showToast(msg: "Failed to load data, starting fresh.");
      debugPrint('Load error: $e');
      _projects = [];
      _standaloneFiles = [];
    }
    setState(() {});
  }

  Future<void> _triggerSync() async {
    if (_isSyncing) return;
    
    setState(() => _isSyncing = true);
    _refreshController.repeat();

    await _loadData();
    await Future.delayed(const Duration(seconds: 2));

    _refreshController.stop();
    setState(() => _isSyncing = false);
    
    Fluttertoast.showToast(
      msg: "Data Synced",
      backgroundColor: Colors.black,
      textColor: Colors.white,
    );
  }

  // --- IO OPERATIONS ---

  Future<void> _exportProjectZip(ProjectModel project) async {
    try {
      var encoder = ZipEncoder();
      var archive = Archive();

      for (var file in project.files) {
        List<int> bytes = utf8.encode(file.content);
        archive.addFile(ArchiveFile(file.name, bytes.length, bytes));
      }

      var zipBytes = encoder.encode(archive);
      if (zipBytes == null) throw Exception("Zip encoding failed");
      
      final directory = await getExternalStorageDirectory();
      if (directory == null) throw Exception("Cannot access external storage");
      
      final file = File('${directory.path}/${project.name}.zip');
      await file.writeAsBytes(zipBytes);

      Fluttertoast.showToast(msg: "Saved as ${project.name}.zip");
    } catch (e) {
      Fluttertoast.showToast(msg: "Export Failed: $e");
    }
  }

  Future<void> _downloadFile(FileModel file) async {
    try {
      final directory = await getExternalStorageDirectory();
      if (directory == null) throw Exception("Cannot access external storage");
      
      final path = "${directory.path}/${file.name}";
      await File(path).writeAsString(file.content);
      Fluttertoast.showToast(msg: "Downloaded to $path");
    } catch (e) {
      Fluttertoast.showToast(msg: "Download failed: $e");
    }
  }

  Future<void> _downloadAllFiles() async {
    try {
      final directory = await getExternalStorageDirectory();
      if (directory == null) throw Exception("Cannot access external storage");
      
      int count = 0;
      for (var file in _standaloneFiles) {
        final path = "${directory.path}/${file.name}";
        await File(path).writeAsString(file.content);
        count++;
      }
      Fluttertoast.showToast(msg: "Downloaded $count files.");
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
    setState(() => _permsDone = true);
  }

  Widget _buildPermissionsScreen() {
    final _t     = Theme.of(context);
    final bg     = _t.scaffoldBackgroundColor;
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
            // Header card
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
                  const Padding(
                    padding: EdgeInsets.all(14),
                    child: Text(
                      "HTML Runner needs these permissions to work. "
                      "You'll only see this screen once.",
                      style: TextStyle(color: txtSec, fontSize: 13),
                    ),
                  ),
                  // Permission rows
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
                                Text(perm['name'] as String, style: const TextStyle(color: txtPri, fontWeight: FontWeight.bold, fontSize: 14)),
                                const SizedBox(height: 2),
                                Text(perm['desc'] as String, style: const TextStyle(color: txtSec, fontSize: 12)),
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
    final panelBg2  = isDark ? AppColors.holoPanelBg2 : AppColors.holoLightPanel2;
    final divider   = isDark ? AppColors.holoDivider   : AppColors.holoLightDivider;
    final textPri   = isDark ? AppColors.holoTextPrimary : AppColors.holoLightTextPri;
    final accent    = isDark ? AppColors.holoBlue      : AppColors.holoBlueDark;

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Fish Gang Auth card
            Container(
              decoration: BoxDecoration(
                color: panelBg,
                border: Border.all(color: divider),
              ),
              child: Column(
                children: [
                  // Header
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

            // Local storage option
            _buildAuthOption(
              title: "Use Application Storage",
              isWarningVisible: _showLocalWarning,
              warningText: "Your Projects and Files are going to be saved in the app. Warning: If you delete the app and reinstall it, your data will be lost forever",
              onTap: () {
                setState(() {
                  _showLocalWarning = true;
                  _showGoogleWarning = false;
                });
              },
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
        project: project,
        onFileTap: (f) => _openCodeEditor(f, project: project),
        onFileLongPress: (f) => _showFileOptions(f, project),
        onAddFile: () => _openCodeEditor(null, project: project),
      )
    ));
  }

  /// Open a file for editing. If the file is binary (image, pdf, etc.),
  /// hand it off to the Android "Open with..." dialog instead.
  void _openCodeEditor(FileModel? file, {ProjectModel? project}) {
    if (file != null && file.isBinary) { _openWithSystem(file); return; }
    if (file != null && !file.isEditable) { _openWithSystem(file); return; }
    Navigator.push(context, MaterialPageRoute(
      builder: (context) => IDEEditorScreen(
        file: file,
        project: project,
        onSave: (name, content) {
          setState(() {
            if (file == null) {
              final newFile = FileModel(
                id: DateTime.now().millisecondsSinceEpoch.toString(),
                name: name,
                content: content,
                lastEdit: DateFormat('HH:mm').format(DateTime.now()),
              );
              if (project != null) {
                project.files.add(newFile);
              } else {
                _standaloneFiles.add(newFile);
              }
              Fluttertoast.showToast(msg: "File Created");
            } else {
              file.name = name;
              file.content = content;
              file.lastEdit = DateFormat('HH:mm').format(DateTime.now());
              Fluttertoast.showToast(msg: "File Saved");
            }
          });
          _saveData();
        },
      )
    ));
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
                setState(() {
                  _projects.remove(project);
                });
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
            leading: const Icon(Icons.edit),
            title: const Text("Edit Code..."),
            onTap: () {
              Navigator.pop(context);
              _openCodeEditor(file, project: project);
            },
          ),
          ListTile(
            leading: const Icon(Icons.download),
            title: const Text("Download as .html"),
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
          if (!file.isBinary)
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

  void _showSettingsSheet() {
    showModalBottomSheet(
      context: context,
      builder: (context) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
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
            title: const Text("Sign Out / Reset"),
            onTap: () {
              Navigator.pop(context);
              _triggerSecurityVerification(); 
            },
          ),
        ],
      ),
    );
  }
  
  // --- START OF SECURITY GATE LOGIC ---

  void _triggerSecurityVerification() {
    if (_currentUser != null) {
      _showChallengeDialog(
        title: "Fish Gang Security Verification",
        hint: "Enter the code shown in your security alert: 552-881",
        correctCode: "552-881",
      );
    } else {
      _startSecurityScan();
    }
  }

  void _startSecurityScan() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        Future.delayed(const Duration(seconds: 2), () {
          Navigator.pop(context);
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
                  _handleSignOut(); 
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

  void _showChallengeDialog({required String title, required String hint, required String correctCode}) {
    TextEditingController input = TextEditingController();
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Text(title, style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(hint),
            const SizedBox(height: 15),
            TextField(controller: input, decoration: const InputDecoration(border: OutlineInputBorder(), labelText: "Verification Code")),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("CANCEL")),
          ElevatedButton(
            onPressed: () {
              if (input.text == correctCode) {
                Navigator.pop(context);
                _handleSignOut(); 
              } else {
                Fluttertoast.showToast(msg: "Incorrect code.");
              }
            },
            child: const Text("VERIFY & WIPE"),
          ),
        ],
      ),
    );
  }

  void _handleSignOut() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('fg_uid');
      await prefs.remove('fg_email');
      await prefs.remove('fg_token');
      await prefs.remove('fg_name');
      await prefs.remove('is_local_mode');
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
    if (f.isBinary) {
      final ext = f.name.contains('.') ? f.name.split('.').last.toLowerCase() : '';
      if ({'jpg','jpeg','png','gif','webp','bmp','svg'}.contains(ext)) return Icons.image;
      if ({'mp4','mov','avi','mkv','webm'}.contains(ext))              return Icons.videocam;
      if ({'mp3','wav','ogg','aac','flac'}.contains(ext))              return Icons.audiotrack;
      if (ext == 'pdf')                                                return Icons.picture_as_pdf;
      return Icons.attach_file;
    }
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
      if (image != null) {
        setState(() {
          _selectedIconPath = image.path;
        });
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
// SECTION 7: IDE EDITOR SCREEN (FIXED: LINE NUMBERS SYNC)
// -----------------------------------------------------------------------------

class _LineNumberColumn extends StatefulWidget {
  final TextEditingController controller;
  final ScrollController scrollController;

  const _LineNumberColumn({
    required this.controller,
    required this.scrollController,
  });

  @override
  __LineNumberColumnState createState() => __LineNumberColumnState();
}

class __LineNumberColumnState extends State<_LineNumberColumn> {
  int _lineCount = 1;

  @override
  void initState() {
    super.initState();
    _updateLineCount();
    widget.controller.addListener(_updateLineCount);
  }

  void _updateLineCount() {
    if (!mounted) return; // guard: listener can fire after dispose
    final lines = '\n'.allMatches(widget.controller.text).length + 1;
    if (_lineCount != lines) setState(() => _lineCount = lines);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_updateLineCount);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // lineH must match the TextField: fontSize(14) * height(1.5) = 21.0
    const double lineH = 21.0;
    return Container(
      width: 44,
      color: AppColors.gutterGray,
      clipBehavior: Clip.hardEdge,
      child: AnimatedBuilder(
        animation: widget.scrollController,
        builder: (context, _) {
          double offset = 0.0;
          try {
            if (widget.scrollController.hasClients) {
              offset = widget.scrollController.offset;
            }
          } catch (_) {}
          // Translate the whole column upward by the scroll offset —
          // no ListView gaps, no white bottom, perfectly in sync.
          return Transform.translate(
            offset: Offset(0, -offset),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: List.generate(_lineCount, (i) => SizedBox(
                height: lineH,
                child: Text(
                  '${i + 1}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.grey,
                    fontSize: 14,
                    height: 1.5,
                    fontFamily: 'monospace',
                  ),
                ),
              )),
            ),
          );
        },
      ),
    );
  }
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

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.file?.name ?? "index.html");
    _codeController = TextEditingController(
      text: widget.file?.content ?? "<html>\n<body>\n  <h1>Hello World</h1>\n</body>\n</html>",
    );
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _nameController.dispose();
    _codeController.dispose();
    super.dispose();
  }

  Future<bool> _onWillPop() async {
    bool shouldExit = false;
    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("⚠️ Warning⚠️"),
        content: const Text("If you exit now without saving it, Your changes will not be saved"),
        actions: [
          TextButton(
            onPressed: () {
              shouldExit = true;
              Navigator.pop(context);
            },
            child: const Text("Exit anyway", style: TextStyle(color: AppColors.errorRed)),
          ),
          TextButton(
            onPressed: () {
              widget.onSave(_nameController.text, _codeController.text);
              shouldExit = true;
              Navigator.pop(context);
            },
            child: const Text("Save & Exit", style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.androidGreen)),
          ),
        ],
      ),
    );
    return shouldExit;
  }

  Future<void> _runPreview() async {
    final project = widget.project;
    final file    = widget.file;

    // If editing within a project, write all assets to temp dir so relative
    // paths (images, stylesheets, scripts) resolve correctly in the WebView.
    if (project != null && file != null) {
      try {
        final tmpDir  = await getTemporaryDirectory();
        final projDir = Directory('${tmpDir.path}/htmlrunner_preview');
        if (await projDir.exists()) await projDir.delete(recursive: true);
        await projDir.create(recursive: true);

        for (final f in project.files) {
          final subDir = f.path.isNotEmpty
              ? Directory('${projDir.path}/${f.path}')
              : projDir;
          await subDir.create(recursive: true);
          final dest = '${subDir.path}/${f.name}';
          if (f.isBinary && f.externalPath != null) {
            await File(f.externalPath!).copy(dest);
          } else {
            // Use editor's live content for the file currently being edited
            final content = f.id == file.id ? _codeController.text : f.content;
            await File(dest).writeAsString(content);
          }
        }

        final mainSubDir = file.path.isNotEmpty
            ? Directory('${projDir.path}/${file.path}')
            : projDir;
        await mainSubDir.create(recursive: true);
        final mainPath = '${mainSubDir.path}/${_nameController.text}';

        // Write current editor content (may not be saved yet)
        await File(mainPath).writeAsString(_codeController.text);

        if (!mounted) return;
        Navigator.push(context, MaterialPageRoute(
          builder: (_) => WebRunnerScreen(filePath: mainPath),
        ));
      } catch (e) {
        Fluttertoast.showToast(msg: 'Preview error: $e');
      }
      return;
    }

    // Standalone file — no assets to resolve, use htmlContent
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
            const Text(
              "Use / to create folders, e.g. pages/about.html",
              style: TextStyle(fontSize: 12, color: Colors.grey),
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
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            onPressed: () {
              String newPath = renameCtrl.text.trim();
              if (newPath.isEmpty) return;
              if (!newPath.endsWith('.html')) newPath = '$newPath.html';
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

  void _insertTag(String tag) {
    final text = _codeController.text;
    final selection = _codeController.selection;
    final newText = text.replaceRange(selection.start, selection.end, tag);
    _codeController.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: selection.start + tag.length),
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
              icon: const Icon(Icons.undo), 
              onPressed: () => _undoController.undo()
            ),
            IconButton(
              icon: const Icon(Icons.redo), 
              onPressed: () => _undoController.redo()
            ),
            IconButton(
              icon: const Icon(Icons.save, color: AppColors.androidGreen),
              onPressed: () => widget.onSave(_nameController.text, _codeController.text),
            ),
            IconButton(
              icon: const Icon(Icons.play_arrow, color: Colors.orange),
              onPressed: _runPreview,
            ),
            IconButton(
              icon: const Icon(Icons.exit_to_app, color: AppColors.errorRed),
              onPressed: () async {
                if (await _onWillPop()) Navigator.pop(context);
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
                    if (data != null) _insertTag(data.text!);
                  }),
                  _toolbarBtn("Select All", () => _codeController.selection = TextSelection(
                    baseOffset: 0, 
                    extentOffset: _codeController.text.length
                  )),
                  _toolbarBtn("<div>", () => _insertTag("<div></div>")),
                  _toolbarBtn("<h1>", () => _insertTag("<h1></h1>")),
                  _toolbarBtn("<p>", () => _insertTag("<p></p>")),
                  _toolbarBtn("style", () => _insertTag("<style></style>")),
                ],
              ),
            ),
            
            Expanded(
              child: Row(
                children: [
                  _LineNumberColumn(
                    controller: _codeController,
                    scrollController: _scrollController,
                  ),
                  Expanded(
                    child: Container(
                      color: AppColors.editorBackground,
                      child: TextField(
                        controller: _codeController,
                        scrollController: _scrollController,
                        undoController: _undoController,
                        maxLines: null,
                        expands: true,
                        style: const TextStyle(
                          color: Colors.white,
                          fontFamily: 'monospace',
                          fontSize: 14,
                          height: 1.5,
                        ),
                        decoration: const InputDecoration(
                          border: InputBorder.none,
                          contentPadding: EdgeInsets.symmetric(horizontal: 8),
                        ),
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
}

// -----------------------------------------------------------------------------
// SECTION 8: RUNNER SCREEN & PROJECT DETAIL
// -----------------------------------------------------------------------------

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
    super.dispose();
  }

  Future<void> _initWebView() async {
    final wvc = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0xFFFFFFFF))
      ..setNavigationDelegate(NavigationDelegate(
        onPageStarted:  (_) => setState(() => _isLoading = true),
        onPageFinished: (_) {
          setState(() => _isLoading = false);
          _injectTouchHandling(wvc);
        },
        onNavigationRequest: (_) => NavigationDecision.navigate,
        onWebResourceError: (e) => debugPrint('WebView: \${e.description}'),
      ))
      ..enableZoom(true)
      ..loadHtmlString(''); // placeholder — actual load below
    ;
    if (widget.filePath != null) {
      await wvc.loadFile(widget.filePath!);
    } else {
      await wvc.loadHtmlString(widget.htmlContent ?? '');
    }

    if (Platform.isAndroid) await _setupAndroidFileUpload(wvc);
    setState(() => _controller = wvc);
  }

  Future<void> _setupAndroidFileUpload(WebViewController wvc) async {
    final androidCtrl = wvc.platform as AndroidWebViewController;
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
        final result = await FilePicker.platform.pickFiles(
            allowMultiple: isMultiple, allowedExtensions: exts, withData: false);
        if (result == null) return [];
        return result.files
            .where((f) => f.path != null)
            .map((f) => Uri.file(f.path!).toString())
            .toList();
      } catch (e) {
        debugPrint('File picker error: \$e');
        return [];
      }
    });
  }

  Future<bool> _requestPermission(Permission p) async {
    final prefs = await SharedPreferences.getInstance();
    final mode  = prefs.getString('permission_mode') ?? "ask";
    final alwaysAllow = prefs.getBool('perm_\${p.toString().split('.').last}') ?? false;
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
      final wild = '\${t.split('/')[0]}/*';
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

  void _sendKey(String key) => _controller.runJavaScript(
      "document.activeElement.dispatchEvent(new KeyboardEvent('keydown',{key:'\$key',bubbles:true}));");

  void _sendArrow(String dir) {
    final codes = {'up':38,'down':40,'left':37,'right':39};
    final keys  = {'up':'ArrowUp','down':'ArrowDown','left':'ArrowLeft','right':'ArrowRight'};
    _controller.runJavaScript(
        "document.activeElement.dispatchEvent(new KeyboardEvent('keydown',"
        "{key:'\${keys[dir]}',code:'\${keys[dir]}',keyCode:\${codes[dir]},bubbles:true}));");
  }

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
              icon: Icon(Icons.settings,
                  color: _showToolPanel ? AppColors.linkBlue : Colors.white),
              onPressed: _togglePanel,
              tooltip: "Keyboard Toolkit"),
        ],
      ),
      body: Stack(
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
                  child: Container(
                    decoration: BoxDecoration(
                      color: AppColors.panelBg,
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                      boxShadow: [BoxShadow(
                          color: Colors.black.withOpacity(0.4),
                          blurRadius: 12, offset: const Offset(0, -2))],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                            margin: const EdgeInsets.symmetric(vertical: 8),
                            width: 40, height: 4,
                            decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.4),
                                borderRadius: BorderRadius.circular(2))),
                        // Arrow keys
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                            _toolBtn("←", () => _sendArrow('left')),
                            const SizedBox(width: 16),
                            _toolBtn("↑", () => _sendArrow('up')),
                            const SizedBox(width: 16),
                            _toolBtn("↓", () => _sendArrow('down')),
                            const SizedBox(width: 16),
                            _toolBtn("→", () => _sendArrow('right')),
                          ]),
                        ),
                        // Number row
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          child: Wrap(spacing: 6, children:
                              '1234567890'.split('').map((c) => _toolBtn(c, () => _sendKey(c))).toList()),
                        ),
                        // QWERTY rows
                        for (final row in ['QWERTYUIOP','ASDFGHJKL','ZXCVBNM'])
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            child: Wrap(spacing: 6, children:
                                row.split('').map((c) => _toolBtn(c, () => _sendKey(c))).toList()),
                          ),
                        // Space / Enter / Backspace
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                            _toolBtn("Space",     () => _sendKey(' '), width: 110),
                            const SizedBox(width: 10),
                            _toolBtn("Enter",     () => _sendKey('Enter')),
                            const SizedBox(width: 10),
                            _toolBtn("⌫",        () => _sendKey('Backspace')),
                          ]),
                        ),
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: ElevatedButton(
                            onPressed: _togglePanel,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.red.shade700,
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(20)),
                            ),
                            child: const Text("Close",
                                style: TextStyle(fontWeight: FontWeight.bold)),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class ProjectDetailScreen extends StatelessWidget {
  final ProjectModel project;
  final Function(FileModel) onFileTap;
  final Function(FileModel) onFileLongPress;
  final VoidCallback onAddFile;

  const ProjectDetailScreen({
    required this.project,
    required this.onFileTap,
    required this.onFileLongPress,
    required this.onAddFile,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: Text(project.name),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(
            children: [
              Container(
                width: 60, 
                height: 60,
                color: Theme.of(context).cardColor,
                child: project.iconPath != null
                    ? Image.file(
                        File(project.iconPath!),
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => const Icon(Icons.terrain, size: 40),
                      )
                    : const Icon(Icons.terrain, size: 40),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(project.description, style: const TextStyle(fontStyle: FontStyle.italic)),
                    const SizedBox(height: 5),
                    Text("Created: ${project.createdAt}", style: const TextStyle(fontSize: 10)),
                  ],
                ),
              )
            ],
          ),
          const Divider(height: 30),
          
          InkWell(
            onTap: onAddFile,
            child: const Padding(
              padding: EdgeInsets.symmetric(vertical: 10),
              child: Text(
                "+ Add New File to Project", 
                style: TextStyle(
                  color: AppColors.linkBlue, 
                  fontWeight: FontWeight.bold, 
                  fontSize: 18
                ),
              ),
            ),
          ),
          
          if (project.files.isEmpty)
            const Text("No files in this project yet.", style: TextStyle(color: Colors.grey)),

          ...project.files.map((f) => FileTile(
            file: f,
            onTap: () => onFileTap(f),
            onLongPress: () => onFileLongPress(f),
          )),
        ],
      ),
    );
  }
}

// Wraps CSS/JS content in a minimal HTML page for preview.
// HTML/HTML3 is returned unchanged.
String _buildPreviewHtml(String filename, String content) {
  final ext = filename.contains('.') ? filename.split('.').last.toLowerCase() : 'html';
  if (ext == 'css') {
    return """<!DOCTYPE html>
<html>
<head>
<meta name="viewport" content="width=device-width,initial-scale=1">
<style>$content</style>
</head>
<body>
<h1>CSS Preview</h1>
<p class="example">Example paragraph</p>
<div class="box">Example div</div>
<button class="btn">Example button</button>
<a href="#" class="link">Example link</a>
<ul><li class="item">List item 1</li><li class="item">List item 2</li></ul>
</body>
</html>""";
  }
  if (ext == 'js') {
    return """<!DOCTYPE html>
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
  const _log = console.log.bind(console);
  console.log = function(...a){ 
    document.getElementById('output').textContent += a.join(' ') + '\n'; 
    _log(...a); 
  };
  try { $content } catch(e) { 
    document.getElementById('output').textContent += '\u274c ' + e; 
  }
})();
</script>
</body>
</html>""";
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

class _FlappyFishGameState extends State<FlappyFishGame>
    with SingleTickerProviderStateMixin {
  // ── Physics ────────────────────────────────────────────────────────────────
  double fishY        = 0.5;
  double velocity     = 0;
  final double gravity = 0.25;
  final double jump    = -4.5;

  // ── Pipe ───────────────────────────────────────────────────────────────────
  double pipeX         = 1.0;
  final double pipeWidth = 0.18;
  final double pipeGap   = 0.28;
  double pipeHeightTop   = 0.3;

  // ── Parallax ───────────────────────────────────────────────────────────────
  double bgOffsetFar  = 0;
  double bgOffsetMid  = 0;
  double bgOffsetFore = 0;

  // ── Game state ─────────────────────────────────────────────────────────────
  int   score       = 0;
  bool  gameOver    = false;
  bool  gameStarted = false;
  Timer? _gameTimer;

  // Fixed-timestep loop
  double _lastTs    = 0;
  double _accum     = 0;
  final double _dt  = 1 / 60;

  // ── Lifecycle ──────────────────────────────────────────────────────────────
  @override
  void dispose() {
    _gameTimer?.cancel();
    super.dispose();
  }

  // ── Game loop ──────────────────────────────────────────────────────────────
  void _startGame() {
    setState(() {
      gameStarted   = true;
      gameOver      = false;
      fishY         = 0.5;
      velocity      = 0;
      pipeX         = 1.0;
      score         = 0;
      pipeHeightTop = Random().nextDouble() * 0.45 + 0.2;
      bgOffsetFar   = 0;
      bgOffsetMid   = 0;
      bgOffsetFore  = 0;
      _lastTs       = DateTime.now().millisecondsSinceEpoch / 1000;
      _accum        = 0;
    });
    _gameTimer?.cancel();
    _gameTimer = Timer.periodic(const Duration(milliseconds: 16), (_) => _tick());
  }

  void _tick() {
    if (!gameStarted || gameOver) return;
    final now = DateTime.now().millisecondsSinceEpoch / 1000;
    final frame = (now - _lastTs).clamp(0.0, 0.033);
    _lastTs = now;
    _accum += frame;
    while (_accum >= _dt) {
      _updatePhysics();
      _updatePipe();
      _updateParallax();
      _checkCollision();
      _accum -= _dt;
    }
    if (mounted) setState(() {});
  }

  void _updatePhysics() {
    velocity += gravity * _dt;
    fishY    += velocity  * _dt;
    if (fishY < 0.05) { fishY = 0.05; velocity = 0; }
    if (fishY > 0.95) { fishY = 0.95; velocity = 0; }
  }

  void _updatePipe() {
    pipeX -= 2.5 * _dt;
    if (pipeX < -pipeWidth) {
      pipeX         = 1.0;
      pipeHeightTop = Random().nextDouble() * 0.45 + 0.2;
      score++;
    }
  }

  void _updateParallax() {
    bgOffsetFar  = (bgOffsetFar  - 0.001) % -1;
    bgOffsetMid  = (bgOffsetMid  - 0.003) % -1;
    bgOffsetFore = (bgOffsetFore - 0.005) % -1;
  }

  void _checkCollision() {
    final inPipeX = pipeX < 0.22 && pipeX + pipeWidth > 0.08;
    if (inPipeX) {
      final inGap = fishY >= pipeHeightTop && fishY + 0.08 <= pipeHeightTop + pipeGap;
      if (!inGap) _endGame();
    }
    if (fishY <= 0.05 || fishY >= 0.95) _endGame();
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
    setState(() => velocity = jump);
  }

  // ── Build ──────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final sw       = MediaQuery.of(context).size.width;
    final sh       = MediaQuery.of(context).size.height;
    final fishSize = sw * 0.1;
    final pipeW    = pipeWidth * sw;
    final gapPx    = pipeGap   * sh;

    // Fallback colour layers (no image assets needed)
    Widget bgLayer(Color c, double offset) => Positioned.fill(
      child: Transform.translate(
        offset: Offset(offset * sw, 0),
        child: Row(children: [
          Expanded(child: Container(color: c)),
          Expanded(child: Container(color: c)),
        ]),
      ),
    );

    return Scaffold(
      backgroundColor: Colors.cyan.shade800,
      body: GestureDetector(
        onTap: _jump,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Background layers
            bgLayer(Colors.cyan.shade700, bgOffsetFar),
            bgLayer(Colors.cyan.shade600, bgOffsetMid),
            bgLayer(Colors.cyan.shade500, bgOffsetFore),

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

            // Fish (emoji fallback — no asset needed)
            Positioned(
              left: sw * 0.12,
              top:  fishY * sh - fishSize / 2,
              child: Transform.rotate(
                angle: (velocity / 15).clamp(-0.8, 0.8),
                child: SizedBox(
                  width: fishSize, height: fishSize,
                  child: Center(
                    child: Text("🐟",
                      style: TextStyle(fontSize: fishSize * 0.8)),
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
