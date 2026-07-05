import 'dart:async';
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
  String? iconPath;
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
  ThemeMode _themeMode = ThemeMode.dark; // default to Holo Dark; user can switch to Light in settings

  @override
  void initState() {
    super.initState();
    _loadThemePreference();
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
      themeMode: _themeMode, // system → device picks; or user override via settings
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
              // Fallback: plain text header when image fails
              return Column(
                children: [
                  Text(
                    "Fish Gang Co.",
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: AppColors.linkBlue,
                      fontFamily: 'monospace', // Optional: system font
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
            _buildInfoRow("📱", "App Name", "HTML Runner"),
            _buildInfoRow("🔢", "Version", "1.6.7+1"),
            _buildInfoRow("📅", "Release Date", "Feb 20, 2025"),
            _buildInfoRow("⏱️", "Build Time", "2 hours"),
            _buildInfoRow("📝", "Lines of Code", "2001 lines"),
            _buildInfoRow("🎨", "UI Style", "Android 4.2 Jellybean"),
            _buildInfoRow("💚", "Framework", "Flutter/Dart"),
            _buildInfoRow("🔧", "Build Tools", "Android SDK 35"),
            _buildInfoRow("📦", "Package", "com.chirag.html_runner"),
            _buildInfoRow("👨‍💻", "Developer", "Chirag Shylendra"),
            _buildInfoRow("🐙", "GitHub", "@chirag7gaming"),
            _buildInfoRow("⚖️", "License", "MIT License"),
            _buildInfoRow("🎯", "Purpose", "Free HTML IDE"),
            _buildInfoRow("💡", "Inspiration", "Black India Day"),
            _buildInfoRow("🚀", "Features", "Projects, Editor, Sync"),
            _buildInfoRow("🎮", "Easter Egg", "You found it! 🎉"),
            const SizedBox(height: 16),
            const Text(
              "Made in 🇮🇳 with ❤️\nZero ads. Forever free.",
              textAlign: TextAlign.center,
              style: TextStyle(fontStyle: FontStyle.italic, fontSize: 12),
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
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Future<void> _importAnyFile() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.any,
      );
      if (result == null) return;

      final picked = result.files.first;
      final name = picked.name;
      final path = picked.path;

      // Non-HTML: hand off to Android's "Open with..." and don't import
      if (!name.toLowerCase().endsWith('.html')) {
        if (path != null) {
          await OpenFile.open(path);
        } else {
          Fluttertoast.showToast(msg: "Cannot open this file type.");
        }
        return;
      }

      // HTML: import into the editor as usual
      if (path == null) {
        Fluttertoast.showToast(msg: "Could not read file path.");
        return;
      }
      final content = await File(path).readAsString();
      _openCodeEditor(FileModel(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        name: name,
        content: content,
        lastEdit: DateFormat('HH:mm').format(DateTime.now()),
      ));
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final panelBg  = isDark ? AppColors.holoPanelBg  : AppColors.holoLightPanel;
    final panelBg2 = isDark ? AppColors.holoPanelBg2 : AppColors.holoLightPanel2;
    final divider  = isDark ? AppColors.holoDivider   : AppColors.holoLightDivider;
    final textPri  = isDark ? AppColors.holoTextPrimary : AppColors.holoLightTextPri;
    final textSec  = isDark ? AppColors.holoTextSecond  : AppColors.holoLightTextSec;

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
                color: panelBg,
                border: Border.all(color: divider),
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
                      "HTML Runner needs the following permissions to work correctly. "
                      "You'll only see this screen once.",
                      style: TextStyle(color: textSec, fontSize: 13),
                    ),
                  ),
                  // Permission rows
                  for (final perm in perms) ...[
                    Container(
                      color: panelBg2,
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
                                Text(perm['name'] as String, style: TextStyle(color: textPri, fontWeight: FontWeight.bold, fontSize: 14)),
                                const SizedBox(height: 2),
                                Text(perm['desc'] as String, style: TextStyle(color: textSec, fontSize: 12)),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    Divider(height: 1, color: divider),
                  ],
                  Padding(
                    padding: const EdgeInsets.all(14),
                    child: SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _requestAllPermissions,
                        child: const Text("Grant Permissions"),
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
          final offset = widget.scrollController.hasClients
              ? widget.scrollController.offset
              : 0.0;
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
  final Function(String, String) onSave;

  const IDEEditorScreen({this.file, required this.onSave});

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
          title: TextField(
            controller: _nameController,
            style: const TextStyle(color: Colors.white, fontSize: 18),
            decoration: const InputDecoration(
              border: InputBorder.none, 
              hintText: "Filename", 
              hintStyle: TextStyle(color: Colors.grey)
            ),
          ),
          actions: [
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
              onPressed: () {
                Navigator.push(
                  context, 
                  MaterialPageRoute(
                    builder: (_) => WebRunnerScreen(htmlContent: _codeController.text)
                  )
                );
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
  final String htmlContent;
  const WebRunnerScreen({required this.htmlContent});

  @override
  State<WebRunnerScreen> createState() => _WebRunnerScreenState();
}

class _WebRunnerScreenState extends State<WebRunnerScreen> {
  late final WebViewController controller;

  @override
  void initState() {
    super.initState();
    controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0xFFFFFFFF))
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (_) {
            controller.runJavaScript('''
              if (!document.querySelector('meta[name="viewport"]')) {
                const meta = document.createElement('meta');
                meta.name = 'viewport';
                meta.content = 'width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=yes';
                document.head.appendChild(meta);
              }
            ''');
          },
        ),
      )
      ..loadHtmlString(widget.htmlContent);
  }

  @override
  Widget build(BuildContext context) {
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
