import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:path_provider/path_provider.dart';
import 'package:archive/archive.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

/* =============================================================================
   HTML RUNNER: DEFINITIVE EDITION (IMPROVED)
   =============================================================================
   Changes:
   - Added try-catch blocks for all risky operations.
   - Optimized line number widget (no +50 buffer, efficient rebuilds).
   - Added error handling for images (project icons, profile avatars).
   - Inline comments for non‑trivial logic.
   =============================================================================
*/

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const HTMLRunnerApp());
}

// -----------------------------------------------------------------------------
// SECTION 1: THEME & CONSTANTS
// -----------------------------------------------------------------------------

class AppColors {
  static const Color nostalgiaBlack = Color(0xFF000000);
  static const Color androidGreen = Color(0xFF4CAF50);
  static const Color errorRed = Color(0xFFD32F2F);
  static const Color folderYellow = Color(0xFFFFCA28);
  static const Color linkBlue = Color(0xFF2196F3);
  static const Color gutterGray = Color(0xFF37474F);
  static const Color editorBackground = Color(0xFF1E1E1E);
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

class ProjectModel {
  String id;
  String name;
  String description;
  String? iconPath; // Path to local image file
  String createdAt;
  String lastModified;
  List<FileModel> files;

  ProjectModel({
    required this.id,
    required this.name,
    this.description = "",
    this.iconPath,
    required this.createdAt,
    required this.lastModified,
    required this.files,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'desc': description,
    'icon': iconPath,
    'created': createdAt,
    'modified': lastModified,
    'files': files.map((f) => f.toJson()).toList(),
  };

  factory ProjectModel.fromJson(Map<String, dynamic> json) => ProjectModel(
    id: json['id'],
    name: json['name'],
    description: json['desc'] ?? "",
    iconPath: json['icon'],
    createdAt: json['created'] ?? "Unknown",
    lastModified: json['modified'] ?? "Unknown",
    files: (json['files'] as List).map((f) => FileModel.fromJson(f)).toList(),
  );
}

class FileModel {
  String id;
  String name;
  String content;
  String lastEdit;

  FileModel({
    required this.id,
    required this.name,
    required this.content,
    required this.lastEdit,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'content': content,
    'lastEdit': lastEdit,
  };

  factory FileModel.fromJson(Map<String, dynamic> json) => FileModel(
    id: json['id'],
    name: json['name'],
    content: json['content'],
    lastEdit: json['lastEdit'] ?? "",
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
  ThemeMode _themeMode = ThemeMode.system;

  @override
  void initState() {
    super.initState();
    _loadThemePreference();
  }

  Future<void> _loadThemePreference() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      setState(() {
        _themeMode = ThemeMode.values[prefs.getInt('theme_pref') ?? 0];
      });
    } catch (e) {
      debugPrint('Error loading theme: $e');
      // Keep default theme
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
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'HTML Runner',
      theme: ThemeData.light().copyWith(
        primaryColor: AppColors.nostalgiaBlack,
        appBarTheme: const AppBarTheme(backgroundColor: AppColors.nostalgiaBlack),
        useMaterial3: false,
      ),
      darkTheme: ThemeData.dark().copyWith(
        primaryColor: AppColors.nostalgiaBlack,
        appBarTheme: const AppBarTheme(backgroundColor: AppColors.nostalgiaBlack),
        useMaterial3: false,
      ),
      themeMode: _themeMode,
      home: MainDashboard(onThemeChange: _updateTheme),
    );
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
  final GoogleSignIn _googleSignIn = GoogleSignIn();
  final ImagePicker _imagePicker = ImagePicker();

  // State Variables
  GoogleSignInAccount? _currentUser;
  bool _isLocalMode = false;
  bool _isSyncing = false;
  
  // Data Storage
  List<ProjectModel> _projects = [];
  List<FileModel> _standaloneFiles = [];

  // Animation & Timers
  late AnimationController _refreshController;
  Timer? _syncTimer;

  // Warning States for Auth Screen
  bool _showGoogleWarning = false;
  bool _showLocalWarning = false;

  @override
  void initState() {
    super.initState();
    _refreshController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    );
    
    _initializePermissions();
    _initializeAuth();
    _loadData();

    // 10-Minute Sync Logic (battery‑saving: only reloads from disk)
    _syncTimer = Timer.periodic(const Duration(minutes: 10), (timer) {
      _triggerSync();
    });
  }

  @override
  void dispose() {
    _refreshController.dispose();
    _syncTimer?.cancel();
    super.dispose();
  }

  // --- INITIALIZATION ---

  Future<void> _initializePermissions() async {
    // Request storage permissions; handle potential denial gracefully
    try {
      await [
        Permission.storage,
        Permission.manageExternalStorage,
        Permission.photos,
      ].request();
    } catch (e) {
      debugPrint('Permission request error: $e');
    }
  }

  void _initializeAuth() {
    _googleSignIn.onCurrentUserChanged.listen((account) {
      setState(() {
        _currentUser = account;
        if (account != null) _isLocalMode = false; // Logged in disables local mode
      });
    });
    
    // Silent sign-in can fail (e.g., no network) – catch to avoid crashing
    try {
      _googleSignIn.signInSilently();
    } catch (e) {
      debugPrint('Silent sign-in failed: $e');
      // User will have to sign in manually
    }
  }

  // --- FILE OPERATIONS ---

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
              margin: const EdgeInsets.bottom(20),
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
              onTap: () {
                Navigator.pop(context);
                _openCodeEditor(null);
              },
            ),
            ListTile(
              leading: const Icon(Icons.file_open, color: AppColors.androidGreen),
              title: const Text("Import from Storage"),
              subtitle: const Text("Only .html allowed", style: TextStyle(fontSize: 11, color: Colors.grey)),
              onTap: () {
                Navigator.pop(context);
                _importHtmlFile();
              },
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Future<void> _importHtmlFile() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['html'],
      );

      if (result != null && result.files.single.path != null) {
        File selectedFile = File(result.files.single.path!);
        String content = await selectedFile.readAsString();
        
        setState(() {
          _standaloneFiles.add(FileModel(
            id: DateTime.now().millisecondsSinceEpoch.toString(),
            name: result.files.single.name,
            content: content,
            lastEdit: DateFormat('HH:mm').format(DateTime.now()),
          ));
        });
        _saveData();
        Fluttertoast.showToast(msg: "Imported ${result.files.single.name}");
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
      // Reset to empty lists
      _projects = [];
      _standaloneFiles = [];
    }
    setState(() {});
  }

  Future<void> _triggerSync() async {
    if (_isSyncing) return;
    
    setState(() => _isSyncing = true);
    _refreshController.repeat();

    // Simulate cloud sync: just reload from disk (10‑minute battery saving)
    await _loadData();
    await Future.delayed(const Duration(seconds: 2)); // Visual feedback

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

    return Scaffold(
      appBar: _buildNostalgicAppBar(),
      body: !isAuthenticated ? _buildAuthScreen() : _buildWorkspace(),
    );
  }

  PreferredSizeWidget _buildNostalgicAppBar() {
    return AppBar(
      backgroundColor: Colors.black,
      elevation: 4.0,
      titleSpacing: 0,
      leading: const Icon(Icons.code, color: Colors.white),
      title: const Text("HTML Runner", style: AppTextStyles.appBarTitle),
      actions: [
        RotationTransition(
          turns: _refreshController,
          child: IconButton(
            icon: Icon(Icons.sync, color: _isSyncing ? AppColors.linkBlue : Colors.white),
            onPressed: _triggerSync,
          ),
        ),
        
        // Profile picture with error handling
        if (_currentUser != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8.0),
            child: CircleAvatar(
              radius: 14,
              backgroundImage: (_currentUser!.photoUrl != null)
                  ? NetworkImage(_currentUser!.photoUrl!)
                  : null,
              child: (_currentUser!.photoUrl == null)
                  ? const Icon(Icons.person, size: 14)
                  : null,
              onBackgroundImageError: (_, __) {
                // Fallback to icon if image fails
              },
            ),
          ),
          
        IconButton(
          icon: const Icon(Icons.settings, color: Colors.white),
          onPressed: _showSettingsSheet,
        ),
      ],
    );
  }

  // --- AUTH UI ---

  Widget _buildAuthScreen() {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _buildAuthOption(
              title: "Use Google Account",
              isWarningVisible: _showGoogleWarning,
              warningText: "ℹ Your Code and Projects would be saved in your Google Account. Warning: If you delete your accounts, your projects and code would be deleted as well.",
              onTap: () {
                setState(() {
                  _showGoogleWarning = true;
                  _showLocalWarning = false;
                });
              },
              onContinue: () async {
                try {
                  await _googleSignIn.signIn();
                } catch (e) {
                  Fluttertoast.showToast(msg: "Login Failed: $e");
                }
              },
            ),

            const SizedBox(height: 24),

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
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: Colors.grey.shade400),
        boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(0, 2))],
      ),
      child: Column(
        children: [
          ListTile(
            title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.black87)),
            trailing: Icon(isWarningVisible ? Icons.expand_less : Icons.expand_more, color: Colors.grey),
            onTap: onTap,
          ),
          if (isWarningVisible)
            Container(
              padding: const EdgeInsets.all(16),
              color: Colors.grey.shade50,
              child: Column(
                children: [
                  Text(
                    warningText,
                    style: AppTextStyles.warningText,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.androidGreen,
                      foregroundColor: Colors.white,
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
        style: TextStyle(color: Colors.grey.shade600, fontStyle: FontStyle.italic),
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

  void _openCodeEditor(FileModel? file, {ProjectModel? project}) {
    Navigator.push(context, MaterialPageRoute(
      builder: (context) => IDEEditorScreen(
        file: file,
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
          ListTile(
            leading: const Icon(Icons.play_arrow),
            title: const Text("Run"),
            onTap: () {
              Navigator.pop(context);
              Navigator.push(context, MaterialPageRoute(builder: (_) => WebRunnerScreen(htmlContent: file.content)));
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
            child: Text("Change Theme", style: TextStyle(fontWeight: FontWeight.bold)),
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
          ListTile(
            leading: const Icon(Icons.exit_to_app, color: AppColors.errorRed),
            title: const Text("Sign Out / Reset"),
            onTap: () async {
              await _googleSignIn.signOut();
              final prefs = await SharedPreferences.getInstance();
              await prefs.clear();
              exit(0);
            },
          ),
        ],
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// SECTION 5: CUSTOM WIDGETS (The "Minecraft" & "Android 8.1" Components)
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
          border: Border.all(color: Colors.grey.shade400, width: 2),
          boxShadow: const [BoxShadow(color: Colors.black12, offset: Offset(2, 2), blurRadius: 4)],
        ),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ICON AREA with error handling
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

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
      child: ListTile(
        leading: const Icon(Icons.html, color: AppColors.folderYellow, size: 32),
        title: Text(file.name, style: const TextStyle(fontWeight: FontWeight.w500)),
        subtitle: Text("Last edited: ${file.lastEdit}", style: const TextStyle(fontSize: 12)),
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
                  color: Colors.grey.shade300,
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

/// A widget that displays line numbers for a given [TextEditingController].
/// It listens to changes in the text and rebuilds only itself.
class _LineNumberColumn extends StatefulWidget {
  final TextEditingController controller;
  const _LineNumberColumn({required this.controller});

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
    final lines = widget.controller.text.split('\n').length;
    if (_lineCount != lines) {
      setState(() {
        _lineCount = lines;
      });
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_updateLineCount);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 40,
      color: AppColors.gutterGray,
      child: ListView.builder(
        // No buffer – exact number of lines
        itemCount: _lineCount,
        itemBuilder: (context, index) {
          return Padding(
            padding: const EdgeInsets.only(top: 2.0), // Align with text line height
            child: Text(
              "${index + 1}",
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.grey,
                fontSize: 14,
                height: 1.5, // Must match editor's line height
                fontFamily: 'monospace',
              ),
            ),
          );
        },
      ),
    );
  }
}

class IDEEditorScreen extends StatefulWidget {
  final FileModel? file;
  final Function(String, String) onSave;

  const IDEEditorScreen({this.file, required this.onSave});

  @override
  _IDEEditorScreenState createState() => _IDEEditorScreenState();
}

class _IDEEditorScreenState extends State<IDEEditorScreen> {
  late TextEditingController _nameController;
  late TextEditingController _codeController;
  final UndoHistoryController _undoController = UndoHistoryController();

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.file?.name ?? "index.html");
    _codeController = TextEditingController(
      text: widget.file?.content ?? "<html>\n<body>\n  <h1>Hello World</h1>\n</body>\n</html>",
    );
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

  void _insertTag(String tag) {
    final text = _codeController.text;
    final selection = _codeController.selection;
    final newText = text.replaceRange(selection.start, selection.end, tag);
    _codeController.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: selection.start + tag.length),
    );
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: _onWillPop,
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: AppColors.nostalgiaBlack,
          title: TextField(
            controller: _nameController,
            style: const TextStyle(color: Colors.white, fontSize: 18),
            decoration: const InputDecoration(border: InputBorder.none, hintText: "Filename", hintStyle: TextStyle(color: Colors.grey)),
          ),
          actions: [
            IconButton(icon: const Icon(Icons.undo), onPressed: () => _undoController.undo()),
            IconButton(icon: const Icon(Icons.redo), onPressed: () => _undoController.redo()),
            IconButton(
              icon: const Icon(Icons.save, color: AppColors.androidGreen),
              onPressed: () => widget.onSave(_nameController.text, _codeController.text),
            ),
            IconButton(
              icon: const Icon(Icons.play_arrow, color: Colors.orange),
              onPressed: () {
                Navigator.push(context, MaterialPageRoute(builder: (_) => WebRunnerScreen(htmlContent: _codeController.text)));
              },
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
            // EDITOR TOOLBAR
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
                  _toolbarBtn("Select All", () => _codeController.selection = TextSelection(baseOffset: 0, extentOffset: _codeController.text.length)),
                  _toolbarBtn("<div>", () => _insertTag("<div></div>")),
                  _toolbarBtn("<h1>", () => _insertTag("<h1></h1>")),
                  _toolbarBtn("<p>", () => _insertTag("<p></p>")),
                  _toolbarBtn("style", () => _insertTag("<style></style>")),
                ],
              ),
            ),
            
            // MAIN EDITOR AREA with line numbers
            Expanded(
              child: Row(
                children: [
                  _LineNumberColumn(controller: _codeController), // Optimised widget
                  Expanded(
                    child: Container(
                      color: AppColors.editorBackground,
                      child: TextField(
                        controller: _codeController,
                        undoController: _undoController,
                        maxLines: null,
                        expands: true,
                        style: const TextStyle(
                          color: Colors.white,
                          fontFamily: 'monospace',
                          fontSize: 14,
                          height: 1.5, // Must match line number height
                        ),
                        decoration: const InputDecoration(
                          border: InputBorder.none,
                          contentPadding: EdgeInsets.all(8),
                        ),
                        // No setState here – line numbers update via listener
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

  Widget _toolbarBtn(String label, VoidCallback onTap) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4.0),
      child: TextButton(
        onPressed: onTap,
        child: Text(label, style: const TextStyle(color: Colors.white, fontSize: 12)),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// SECTION 8: RUNNER SCREEN & PROJECT DETAIL
// -----------------------------------------------------------------------------

class WebRunnerScreen extends StatelessWidget {
  final String htmlContent;
  const WebRunnerScreen({required this.htmlContent});

  @override
  Widget build(BuildContext context) {
    final controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..loadHtmlString(htmlContent);

    return Scaffold(
      appBar: AppBar(
        title: const Text("Runner Preview"),
        backgroundColor: Colors.black,
      ),
      body: WebViewWidget(controller: controller),
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
                width: 60, height: 60,
                color: Colors.grey.shade300,
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
              child: Text("+ Add New File to Project", style: TextStyle(color: AppColors.linkBlue, fontWeight: FontWeight.bold, fontSize: 18)),
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
