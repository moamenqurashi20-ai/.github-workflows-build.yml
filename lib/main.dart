import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:adhan/adhan.dart';
import 'package:geolocator/geolocator.dart';
import 'package:intl/intl.dart' hide TextDirection;
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:audioplayers/audioplayers.dart';
import 'package:record/record.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_compass/flutter_compass.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
  ));

  const AndroidInitializationSettings initAndroid = AndroidInitializationSettings('@mipmap/ic_launcher');
  const InitializationSettings initSettings = InitializationSettings(android: initAndroid);
  await flutterLocalNotificationsPlugin.initialize(initSettings);

  runApp(const TareeqAlJannahApp());
}

class TareeqAlJannahApp extends StatelessWidget {
  const TareeqAlJannahApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'طريق الجنة',
      debugShowCheckedModeBanner: false,
      locale: const Locale('ar', 'EG'),
      supportedLocales: const [Locale('ar', 'EG')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF0F2027),
        primaryColor: const Color(0xFFFFD700),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFFFFD700),
          secondary: Color(0xFF1FC0A0),
          surface: Color(0xFF162A33),
        ),
        textTheme: GoogleFonts.cairoTextTheme(ThemeData.dark().textTheme),
      ),
      home: const MainDashboard(),
    );
  }
}

class MainDashboard extends StatefulWidget {
  const MainDashboard({super.key});

  @override
  State<MainDashboard> createState() => _MainDashboardState();
}

class _MainDashboardState extends State<MainDashboard> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  int _currentIndex = 0;

  // بيانات المواقيت والموقع
  double _lat = 30.0444;
  double _lng = 31.2357;
  String _cityName = "القاهرة، مصر";
  PrayerTimes? _prayerTimes;
  String _nextPrayerName = "الفجر";
  DateTime? _nextPrayerTime;
  String _lastPrayerName = "العشاء";
  DateTime? _lastPrayerTime;
  Duration _remaining = Duration.zero;
  Timer? _clockTimer;

  // إعدادات الأذان ومنبه الفجر
  final AudioPlayer _adhanPlayer = AudioPlayer();
  final AudioRecorder _audioRecorder = AudioRecorder();
  bool _isAdhanPlaying = false;
  bool _isRecording = false;
  bool _fajrAlarmEnabled = true;
  String? _customFajrAudioPath;
  String _selectedMuezzin = "afasy";
  String _lastTriggeredMinute = "";

  // تفعيل الأذان لكل صلاة
  Map<String, bool> _prayerAlerts = {
    'fajr': true,
    'dhuhr': true,
    'asr': true,
    'maghrib': true,
    'isha': true,
  };

  final Map<String, Map<String, String>> _muezzinList = {
    "afasy": {"name": "مشاري راشد العفاسي", "url": "https://www.islamcan.com/audio/adhan/azan1.mp3"},
    "makkah": {"name": "أذان الحرم المكي", "url": "https://www.islamcan.com/audio/adhan/azan2.mp3"},
    "madinah": {"name": "أذان المسجد النبوي", "url": "https://www.islamcan.com/audio/adhan/azan3.mp3"},
    "qatami": {"name": "ناصر القطامي", "url": "https://www.islamcan.com/audio/adhan/azan12.mp3"},
  };

  final List<String> _dailyZikrList = [
    "\"أَسْتَغْفِرُ اللَّهَ الْعَظِيمَ الَّذِي لَا إِلَهَ إِلَّا هُوَ الْحَيُّ الْقَيُّومُ وَأَتُوبُ إِلَيْهِ\"",
    "\"سُبْحَانَ اللَّهِ وَبِحَمْدِهِ ، سُبْحَانَ اللَّهِ الْعَظِيمِ\"",
    "\"لَا إِلَهَ إِلَّا أَنْتَ سُبْحَانَكَ إِنِّي كُنْتُ مِنَ الظَّالِمِينَ\"",
    "\"اللَّهُمَّ صَلِّ وَسَلِّمْ وَبَارِكْ عَلَى نَبِيِّنَا مُحَمَّدٍ\"",
    "\"لَا حَوْلَ وَلَا قُوَّةَ إِلَّا بِاللَّهِ الْعَلِيِّ الْعَظِيمِ\"",
  ];

  @override
  void initState() {
    super.initState();
    _loadSettings();
    _calculatePrayers();
    _initLocation();
    _startLiveClock();
    _requestNotificationPermission();
  }

  @override
  void dispose() {
    _clockTimer?.cancel();
    _adhanPlayer.dispose();
    _audioRecorder.dispose();
    super.dispose();
  }

  Future<void> _requestNotificationPermission() async {
    await Permission.notification.request();
  }

  Future<void> _showAdhanNotification(String prayerTitle) async {
    const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
      'adhan_channel_id',
      'تنبيهات الأذان',
      channelDescription: 'إشعارات مواقيت الصلاة والأذان',
      importance: Importance.max,
      priority: Priority.high,
      playSound: false,
      icon: '@mipmap/ic_launcher',
    );
    const NotificationDetails details = NotificationDetails(android: androidDetails);
    await flutterLocalNotificationsPlugin.show(
      DateTime.now().millisecond,
      'حان الآن موعد أذان $prayerTitle',
      'حيّ على الصلاة • تطبيق طريق الجنة',
      details,
    );
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _fajrAlarmEnabled = prefs.getBool('fajr_alarm_enabled') ?? true;
      _customFajrAudioPath = prefs.getString('custom_fajr_audio');
      _selectedMuezzin = prefs.getString('selected_muezzin') ?? 'afasy';
      _prayerAlerts['fajr'] = prefs.getBool('alert_fajr') ?? true;
      _prayerAlerts['dhuhr'] = prefs.getBool('alert_dhuhr') ?? true;
      _prayerAlerts['asr'] = prefs.getBool('alert_asr') ?? true;
      _prayerAlerts['maghrib'] = prefs.getBool('alert_maghrib') ?? true;
      _prayerAlerts['isha'] = prefs.getBool('alert_isha') ?? true;
    });
  }

  Future<void> _togglePrayerAlert(String key, bool val) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('alert_$key', val);
    setState(() => _prayerAlerts[key] = val);
  }

  Future<void> _initLocation() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) return;
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.whileInUse || permission == LocationPermission.always) {
        Position pos = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.medium);
        setState(() {
          _lat = pos.latitude;
          _lng = pos.longitude;
          _cityName = "موقعك الحالي (${_lat.toStringAsFixed(2)}, ${_lng.toStringAsFixed(2)})";
        });
        _calculatePrayers();
      }
    } catch (_) {}
  }

  void _calculatePrayers() {
    final coords = Coordinates(_lat, _lng);
    final params = CalculationMethod.egyptian.getParameters();
    params.madhab = Madhab.shafi;
    final now = DateTime.now();
    final todayPrayers = PrayerTimes.today(coords, params);
    final yesterdayPrayers = PrayerTimes(coords, DateComponents.from(now.subtract(const Duration(days: 1))), params);

    final list = [
      {'name': 'الفجر', 'time': todayPrayers.fajr},
      {'name': 'الشروق', 'time': todayPrayers.sunrise},
      {'name': 'الظهر', 'time': todayPrayers.dhuhr},
      {'name': 'العصر', 'time': todayPrayers.asr},
      {'name': 'المغرب', 'time': todayPrayers.maghrib},
      {'name': 'العشاء', 'time': todayPrayers.isha},
    ];

    DateTime? nextT;
    String nextN = "الفجر";
    DateTime lastT = yesterdayPrayers.isha;
    String lastN = "العشاء";

    for (int i = 0; i < list.length; i++) {
      final t = list[i]['time'] as DateTime;
      final n = list[i]['name'] as String;
      if (t.isBefore(now)) {
        lastT = t;
        lastN = n;
      } else if (nextT == null) {
        nextT = t;
        nextN = n;
      }
    }

    if (nextT == null) {
      final tomorrowPrayers = PrayerTimes(coords, DateComponents.from(now.add(const Duration(days: 1))), params);
      nextT = tomorrowPrayers.fajr;
      nextN = "الفجر";
    }

    setState(() {
      _prayerTimes = todayPrayers;
      _nextPrayerName = nextN;
      _nextPrayerTime = nextT;
      _lastPrayerName = lastN;
      _lastPrayerTime = lastT;
      _remaining = nextT!.difference(now);
    });
  }

  void _startLiveClock() {
    _clockTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_nextPrayerTime == null || _prayerTimes == null) return;
      final now = DateTime.now();
      final diff = _nextPrayerTime!.difference(now);

      if (diff.isNegative) {
        _calculatePrayers();
      } else {
        setState(() => _remaining = diff);
      }

      final currentKey = "${now.hour}:${now.minute}";
      if (_lastTriggeredMinute != currentKey) {
        _checkAndTriggerAdhan(now, currentKey);
      }
    });
  }

  void _checkAndTriggerAdhan(DateTime now, String currentKey) {
    if (_prayerTimes == null) return;
    bool isSameMinute(DateTime t) => t.hour == now.hour && t.minute == now.minute && now.second < 3;

    if (isSameMinute(_prayerTimes!.fajr) && (_prayerAlerts['fajr'] ?? true)) {
      _lastTriggeredMinute = currentKey;
      _playAdhanOrFajrAlarm(isFajr: true, prayerTitle: "الفجر");
    } else if (isSameMinute(_prayerTimes!.dhuhr) && (_prayerAlerts['dhuhr'] ?? true)) {
      _lastTriggeredMinute = currentKey;
      _playAdhanOrFajrAlarm(isFajr: false, prayerTitle: "الظهر");
    } else if (isSameMinute(_prayerTimes!.asr) && (_prayerAlerts['asr'] ?? true)) {
      _lastTriggeredMinute = currentKey;
      _playAdhanOrFajrAlarm(isFajr: false, prayerTitle: "العصر");
    } else if (isSameMinute(_prayerTimes!.maghrib) && (_prayerAlerts['maghrib'] ?? true)) {
      _lastTriggeredMinute = currentKey;
      _playAdhanOrFajrAlarm(isFajr: false, prayerTitle: "المغرب");
    } else if (isSameMinute(_prayerTimes!.isha) && (_prayerAlerts['isha'] ?? true)) {
      _lastTriggeredMinute = currentKey;
      _playAdhanOrFajrAlarm(isFajr: false, prayerTitle: "العشاء");
    }
  }

  Future<void> _playAdhanOrFajrAlarm({required bool isFajr, String prayerTitle = "الصلاة"}) async {
    await _adhanPlayer.stop();
    await _showAdhanNotification(prayerTitle);
    setState(() => _isAdhanPlaying = true);

    try {
      if (isFajr && _fajrAlarmEnabled && _customFajrAudioPath != null && File(_customFajrAudioPath!).existsSync()) {
        await _adhanPlayer.play(DeviceFileSource(_customFajrAudioPath!));
      } else {
        final url = _muezzinList[_selectedMuezzin]!['url']!;
        await _adhanPlayer.play(UrlSource(url));
      }
      _adhanPlayer.onPlayerComplete.listen((_) {
        if (mounted) setState(() => _isAdhanPlaying = false);
      });
    } catch (_) {
      if (mounted) setState(() => _isAdhanPlaying = false);
    }
  }

  Future<void> _stopAdhan() async {
    await _adhanPlayer.stop();
    setState(() => _isAdhanPlaying = false);
  }

  Future<void> _toggleRecordFajrVoice() async {
    if (_isRecording) {
      final path = await _audioRecorder.stop();
      setState(() => _isRecording = false);
      if (path != null) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('custom_fajr_audio', path);
        setState(() => _customFajrAudioPath = path);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("تم حفظ تسجيل صوتك لمنبه الفجر بنجاح"), backgroundColor: Color(0xFF1FC0A0)),
          );
        }
      }
    } else {
      final status = await Permission.microphone.request();
      if (!status.isGranted) return;
      final dir = await getApplicationDocumentsDirectory();
      final filePath = '${dir.path}/fajr_custom_${DateTime.now().millisecondsSinceEpoch}.m4a';
      await _audioRecorder.start(const RecordConfig(), path: filePath);
      setState(() => _isRecording = true);
    }
  }

  Future<void> _pickAudioFile() async {
    final result = await FilePicker.platform.pickFiles(type: FileType.audio);
    if (result != null && result.files.single.path != null) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('custom_fajr_audio', result.files.single.path!);
      setState(() => _customFajrAudioPath = result.files.single.path!);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("تم اختيار ملف الصوت لمنبه الفجر"), backgroundColor: Color(0xFF1FC0A0)),
        );
      }
    }
  }

  String _formatDuration(Duration d) {
    String two(int n) => n.toString().padLeft(2, '0');
    return "${two(d.inHours)}:${two(d.inMinutes.remainder(60))}:${two(d.inSeconds.remainder(60))}";
  }

  String _formatLastPrayerElapsed() {
    if (_lastPrayerTime == null) return "";
    final diff = DateTime.now().difference(_lastPrayerTime!);
    if (diff.inHours > 0) {
      return "منذ ${diff.inHours} س و ${diff.inMinutes.remainder(60)} د";
    }
    return "منذ ${diff.inMinutes} دقيقة";
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      _buildHomeDashboard(),
      const QuranCompleteTab(),
      const QiblaCompassTab(),
      const ReligiousQuizTab(),
    ];

    return Scaffold(
      key: _scaffoldKey,
      drawer: _buildSideDrawer(),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F2027),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.menu_rounded, color: Colors.white, size: 28),
          onPressed: () => _scaffoldKey.currentState?.openDrawer(),
        ),
        title: Text(
          _currentIndex == 0
              ? "طريق الجنة"
              : _currentIndex == 1
                  ? "المصحف الشريف"
                  : _currentIndex == 2
                      ? "اتجاه القبلة"
                      : "أسئلة دينية",
          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 19, color: Colors.white),
        ),
        centerTitle: true,
        actions: [
          Stack(
            alignment: Alignment.center,
            children: [
              IconButton(
                icon: Icon(
                  _isAdhanPlaying ? Icons.volume_off_rounded : Icons.notifications_active_rounded,
                  color: _isAdhanPlaying ? Colors.redAccent : Colors.white,
                ),
                onPressed: () {
                  if (_isAdhanPlaying) {
                    _stopAdhan();
                  } else {
                    _openPrayerTimesSheet();
                  }
                },
              ),
              Positioned(
                top: 10,
                right: 10,
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: const BoxDecoration(color: Color(0xFFFF9800), shape: BoxShape.circle),
                  child: const Text("5", style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.white)),
                ),
              ),
            ],
          ),
        ],
      ),
      body: pages[_currentIndex],
      bottomNavigationBar: _buildCustomBottomNav(),
    );
  }

  Widget _buildCustomBottomNav() {
    final items = [
      {'icon': Icons.mosque_rounded, 'label': 'الرئيسية'},
      {'icon': Icons.menu_book_rounded, 'label': 'المصحف'},
      {'icon': Icons.explore_rounded, 'label': 'القبلة'},
      {'icon': Icons.psychology_rounded, 'label': 'الأسئلة'},
    ];

    return Container(
      height: 72,
      decoration: const BoxDecoration(
        color: Color(0xFF142A33),
        border: Border(top: BorderSide(color: Colors.white10)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: List.generate(items.length, (index) {
          final isSelected = _currentIndex == index;
          return GestureDetector(
            onTap: () => setState(() => _currentIndex = index),
            behavior: HitTestBehavior.opaque,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 220),
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
                  decoration: BoxDecoration(
                    color: isSelected ? const Color(0x33FFD700) : Colors.transparent,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(
                    items[index]['icon'] as IconData,
                    color: isSelected ? const Color(0xFFFFD700) : const Color(0xFF8A9EA6),
                    size: 24,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  items[index]['label'] as String,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                    color: isSelected ? const Color(0xFFFFD700) : const Color(0xFF8A9EA6),
                  ),
                ),
              ],
            ),
          );
        }),
      ),
    );
  }

  Widget _buildSideDrawer() {
    final drawerItems = [
      {'title': 'أوقات الصلاة ومنبه الفجر', 'icon': Icons.access_time_filled_rounded, 'color': const Color(0xFF4CAF50), 'action': () => _openPrayerTimesSheet()},
      {'title': 'القرآن الكريم كاملاً', 'icon': Icons.menu_book_rounded, 'color': const Color(0xFF9C27B0), 'action': () => setState(() => _currentIndex = 1)},
      {'title': 'معرفة القبلة', 'icon': Icons.explore_rounded, 'color': const Color(0xFFFF9800), 'action': () => setState(() => _currentIndex = 2)},
      {'title': 'السبحة الإلكترونية', 'icon': Icons.radio_button_checked_rounded, 'color': const Color(0xFF2196F3), 'action': () => _openAzkarSheet(initialTab: 0)},
      {'title': 'أسئلة دينية', 'icon': Icons.psychology_rounded, 'color': const Color(0xFFFF5252), 'action': () => setState(() => _currentIndex = 3)},
      {'title': 'أفضل الأذكار والأدعية', 'icon': Icons.volunteer_activism_rounded, 'color': const Color(0xFFFFD700), 'action': () => _openAzkarSheet(initialTab: 1)},
    ];

    return Drawer(
      backgroundColor: const Color(0xFF0F2027),
      child: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0x22FFD700),
                borderRadius: BorderRadius.circular(18),
              ),
              child: const Icon(Icons.mosque_rounded, color: Color(0xFFFFD700), size: 44),
            ),
            const SizedBox(height: 12),
            const Text("طريق الجنة", style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: Colors.white)),
            const Text("القائمة الرئيسية", style: TextStyle(fontSize: 13, color: Color(0xFF1FC0A0), fontWeight: FontWeight.bold)),
            const SizedBox(height: 18),
            const Divider(color: Colors.white10),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                itemCount: drawerItems.length,
                itemBuilder: (context, i) {
                  final item = drawerItems[i];
                  return ListTile(
                    onTap: () {
                      Navigator.pop(context);
                      (item['action'] as VoidCallback)();
                    },
                    leading: Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        color: (item['color'] as Color).withOpacity(0.18),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(item['icon'] as IconData, color: item['color'] as Color, size: 20),
                    ),
                    title: Text(item['title'] as String, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Colors.white)),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHomeDashboard() {
    final zikrOfToday = _dailyZikrList[DateTime.now().day % _dailyZikrList.length];
    final lastTimeFormatted = _lastPrayerTime != null ? DateFormat('hh:mm a', 'ar').format(_lastPrayerTime!) : "--:--";
    final nextTimeFormatted = _nextPrayerTime != null ? DateFormat('hh:mm a', 'ar').format(_nextPrayerTime!) : "--:--";

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 1. بطاقة الصلاة القادمة + وقت آخر صلاة + تفعيل الأذان
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF163832), Color(0xFF142A33)],
                begin: Alignment.topRight,
                end: Alignment.bottomLeft,
              ),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: const Color(0x55FFD700)),
            ),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.location_on, size: 14, color: Color(0xFF1FC0A0)),
                            const SizedBox(width: 4),
                            Text(_cityName, style: const TextStyle(fontSize: 11, color: Colors.white70)),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text("الصلاة القادمة: $_nextPrayerName", style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: Color(0xFFFFD700))),
                        Text("الموعد: $nextTimeFormatted", style: const TextStyle(fontSize: 13, color: Colors.white70)),
                      ],
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: Colors.black38,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: const Color(0xFF1FC0A0)),
                          ),
                          child: Text(
                            _formatDuration(_remaining),
                            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: Color(0xFF1FC0A0), fontFamily: 'monospace'),
                          ),
                        ),
                        const SizedBox(height: 6),
                        GestureDetector(
                          onTap: () => _isAdhanPlaying ? _stopAdhan() : _playAdhanOrFajrAlarm(isFajr: false, prayerTitle: _nextPrayerName),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: _isAdhanPlaying ? Colors.redAccent : const Color(0xFFFFD700),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(_isAdhanPlaying ? Icons.stop_rounded : Icons.volume_up_rounded, size: 14, color: Colors.black),
                                const SizedBox(width: 4),
                                Text(_isAdhanPlaying ? "إيقاف الأذان" : "تجربة الأذان", style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.black)),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                const Divider(color: Colors.white12, height: 22),
                // شريط وقت آخر صلاة
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.history_rounded, size: 16, color: Color(0xFFFF9800)),
                        const SizedBox(width: 6),
                        Text(
                          "آخر صلاة: $_lastPrayerName ($lastTimeFormatted)",
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.white),
                        ),
                      ],
                    ),
                    Text(
                      _formatLastPrayerElapsed(),
                      style: const TextStyle(fontSize: 11, color: Color(0xFF1FC0A0), fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(height: 14),

          // 2. شريط "ذِكْرُ اليوم" بنفس تصميم الصورة تماماً
          Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                width: double.infinity,
                margin: const EdgeInsets.only(top: 12),
                padding: const EdgeInsets.fromLTRB(16, 22, 16, 16),
                decoration: BoxDecoration(
                  color: const Color(0xFF1A2E35),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.white12),
                ),
                child: Text(
                  zikrOfToday,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.amiri(fontSize: 20, fontWeight: FontWeight.bold, height: 1.6, color: Colors.white),
                ),
              ),
              Positioned(
                top: 0,
                right: 16,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(colors: [Color(0xFFFF9800), Color(0xFFF57C00)]),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Text(
                    "ذِكْرُ اليوم",
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w900, color: Colors.white),
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 18),

          // 3. شبكة البطاقات الرئيسية (2 أعمدة بنفس ألوان وأيقونات الصورة)
          GridView.count(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisCount: 2,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 1.18,
            children: [
              _buildGridCard(
                title: "أفضل الأذكار",
                icon: Icons.menu_book_rounded,
                iconColor: const Color(0xFF4CAF50),
                bgColor: const Color(0xFF1B3B32),
                onTap: () => _openAzkarSheet(initialTab: 1),
              ),
              _buildGridCard(
                title: "المصحف الشريف",
                icon: Icons.auto_stories_rounded,
                iconColor: const Color(0xFFFFD700),
                bgColor: const Color(0xFF1B3B32),
                onTap: () => setState(() => _currentIndex = 1),
              ),
              _buildGridCard(
                title: "السبحة الإلكترونية",
                icon: Icons.radio_button_checked_rounded,
                iconColor: const Color(0xFF2196F3),
                bgColor: const Color(0xFF162A33),
                onTap: () => _openAzkarSheet(initialTab: 0),
              ),
              _buildGridCard(
                title: "أسئلة دينية",
                icon: Icons.psychology_rounded,
                iconColor: const Color(0xFFFF5252),
                bgColor: const Color(0xFF162A33),
                onTap: () => setState(() => _currentIndex = 3),
              ),
              _buildGridCard(
                title: "اعرف القبلة",
                icon: Icons.explore_rounded,
                iconColor: const Color(0xFFFF9800),
                bgColor: const Color(0xFF162A33),
                onTap: () => setState(() => _currentIndex = 2),
              ),
              _buildGridCard(
                title: "أوقات الصلاة والأذان",
                icon: Icons.access_time_filled_rounded,
                iconColor: const Color(0xFF1FC0A0),
                bgColor: const Color(0xFF162A33),
                onTap: () => _openPrayerTimesSheet(),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildGridCard({
    required String title,
    required IconData icon,
    required Color iconColor,
    required Color bgColor,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Colors.white10),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: iconColor.withOpacity(0.15),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: iconColor, size: 32),
            ),
            const SizedBox(height: 10),
            Text(
              title,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white),
            ),
          ],
        ),
      ),
    );
  }

  // نافذة مواقيت الصلاة وتفعيل/تعطيل كل صلاة واختيار نوع الأذان ومنبه الفجر
  void _openPrayerTimesSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF0F2027),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) {
          final prayers = _prayerTimes == null
              ? []
              : [
                  {'key': 'fajr', 'name': 'الفجر', 'time': _prayerTimes!.fajr, 'icon': Icons.nights_stay_rounded, 'hasAlert': true},
                  {'key': 'sunrise', 'name': 'الشروق', 'time': _prayerTimes!.sunrise, 'icon': Icons.wb_twilight_rounded, 'hasAlert': false},
                  {'key': 'dhuhr', 'name': 'الظهر', 'time': _prayerTimes!.dhuhr, 'icon': Icons.wb_sunny_rounded, 'hasAlert': true},
                  {'key': 'asr', 'name': 'العصر', 'time': _prayerTimes!.asr, 'icon': Icons.wb_sunny_outlined, 'hasAlert': true},
                  {'key': 'maghrib', 'name': 'المغرب', 'time': _prayerTimes!.maghrib, 'icon': Icons.wb_shade_rounded, 'hasAlert': true},
                  {'key': 'isha', 'name': 'العشاء', 'time': _prayerTimes!.isha, 'icon': Icons.dark_mode_rounded, 'hasAlert': true},
                ];

          return DraggableScrollableSheet(
            initialChildSize: 0.88,
            maxChildSize: 0.95,
            minChildSize: 0.5,
            expand: false,
            builder: (_, scrollCtrl) => ListView(
              controller: scrollCtrl,
              padding: const EdgeInsets.all(18),
              children: [
                Center(
                  child: Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(4))),
                ),
                const SizedBox(height: 14),
                const Text("أوقات الصلاة وإعدادات الأذان", textAlign: TextAlign.center, style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xFFFFD700))),
                const SizedBox(height: 14),

                // اختيار صوت المؤذن
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(color: const Color(0xFF162A33), borderRadius: BorderRadius.circular(16)),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text("اختيار نوع الأذان (صوت المؤذن):", style: TextStyle(fontSize: 13, color: Color(0xFF1FC0A0), fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      DropdownButtonFormField<String>(
                        value: _selectedMuezzin,
                        dropdownColor: const Color(0xFF162A33),
                        decoration: InputDecoration(
                          filled: true,
                          fillColor: const Color(0xFF0F2027),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                        ),
                        items: _muezzinList.entries
                            .map((e) => DropdownMenuItem<String>(value: e.key, child: Text(e.value['name']!)))
                            .toList(),
                        onChanged: (val) async {
                          if (val != null) {
                            final prefs = await SharedPreferences.getInstance();
                            await prefs.setString('selected_muezzin', val);
                            setState(() => _selectedMuezzin = val);
                            setSheetState(() {});
                          }
                        },
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 14),

                // قائمة الصلوات مع زر التفعيل/الإلغاء
                ...prayers.map((p) {
                  final key = p['key'] as String;
                  final t = p['time'] as DateTime;
                  final hasAlert = p['hasAlert'] as bool;
                  final isEnabled = _prayerAlerts[key] ?? true;

                  return Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: const Color(0xFF162A33),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: _nextPrayerName == p['name'] ? const Color(0xFFFFD700) : Colors.white10),
                    ),
                    child: Row(
                      children: [
                        Icon(p['icon'] as IconData, color: const Color(0xFF1FC0A0)),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(p['name'] as String, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                        ),
                        Text(DateFormat('hh:mm a', 'ar').format(t), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Color(0xFFFFD700))),
                        const SizedBox(width: 10),
                        if (hasAlert)
                          Switch(
                            value: isEnabled,
                            activeColor: const Color(0xFF1FC0A0),
                            onChanged: (val) async {
                              await _togglePrayerAlert(key, val);
                              setSheetState(() {});
                            },
                          )
                        else
                          const SizedBox(width: 48),
                      ],
                    ),
                  );
                }),

                const SizedBox(height: 14),

                // منبه الفجر بصوتك الخاص
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFF162A33),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: const Color(0x44FFD700)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text("منبه صلاة الفجر بصوتك الخاص", style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Color(0xFFFFD700))),
                          Switch(
                            value: _fajrAlarmEnabled,
                            activeColor: const Color(0xFFFFD700),
                            onChanged: (v) async {
                              final prefs = await SharedPreferences.getInstance();
                              await prefs.setBool('fajr_alarm_enabled', v);
                              setState(() => _fajrAlarmEnabled = v);
                              setSheetState(() {});
                            },
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: _isRecording ? Colors.redAccent : const Color(0xFF1FC0A0),
                                foregroundColor: Colors.black,
                              ),
                              onPressed: () async {
                                await _toggleRecordFajrVoice();
                                setSheetState(() {});
                              },
                              icon: Icon(_isRecording ? Icons.stop : Icons.mic),
                              label: Text(_isRecording ? "إيقاف وحفظ" : "سجّل صوتك", style: const TextStyle(fontWeight: FontWeight.bold)),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: OutlinedButton.icon(
                              style: OutlinedButton.styleFrom(foregroundColor: const Color(0xFFFFD700), side: const BorderSide(color: Color(0xFFFFD700))),
                              onPressed: () async {
                                await _pickAudioFile();
                                setSheetState(() {});
                              },
                              icon: const Icon(Icons.audio_file),
                              label: const Text("اختر ملف صوتي"),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  void _openAzkarSheet({int initialTab = 0}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF0F2027),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.88,
        maxChildSize: 0.95,
        minChildSize: 0.5,
        expand: false,
        builder: (_, __) => const AzkarAndTasbihTab(),
      ),
    );
  }
}
class QuranCompleteTab extends StatefulWidget {
  const QuranCompleteTab({super.key});

  @override
  State<QuranCompleteTab> createState() => _QuranCompleteTabState();
}

class _QuranCompleteTabState extends State<QuranCompleteTab> {
  int _subNavIndex = 0;
  String _filterType = 'all';
  String _searchQuery = '';

  double _fontSize = 24.0;
  String _selectedReciter = 'afasy';
  bool _nightMode = true;
  bool _showAyahNumbers = true;
  bool _showTashkeel = true;
  List<String> _bookmarks = [];

  final Map _reciters = {
    'abdulbasit': {'name': 'عبدالباسط عبدالصمد (مجود)', 'url': 'https://server7.mp3quran.net/basit/Almusshaf-Al-Mojawwad'},
    'minshawi': {'name': 'المنشاوي (مجود)', 'url': 'https://server11.mp3quran.net/minsh_mjwd'},
    'husary': {'name': 'محمود خليل الحصري', 'url': 'https://server13.mp3quran.net/husr'},
    'afasy': {'name': 'مشاري راشد العفاسي', 'url': 'https://server8.mp3quran.net/afs'},
    'ghamdi': {'name': 'سعد الغامدي', 'url': 'https://server7.mp3quran.net/s_gmd'},
    'sudais': {'name': 'عبدالرحمن السديس', 'url': 'https://server11.mp3quran.net/sds'},
    'shuraim': {'name': 'سعود الشريم', 'url': 'https://server7.mp3quran.net/shur'},
  };

  final List _surahsData = [
    {'id': 1, 'name': 'الفاتحة', 'verses': 7, 'type': 'meccan', 'juz': 1},
    {'id': 2, 'name': 'البقرة', 'verses': 286, 'type': 'medinan', 'juz': 1},
    {'id': 3, 'name': 'آل عمران', 'verses': 200, 'type': 'medinan', 'juz': 3},
    {'id': 4, 'name': 'النساء', 'verses': 176, 'type': 'medinan', 'juz': 4},
    {'id': 5, 'name': 'المائدة', 'verses': 120, 'type': 'medinan', 'juz': 6},
    {'id': 6, 'name': 'الأنعام', 'verses': 165, 'type': 'meccan', 'juz': 7},
    {'id': 7, 'name': 'الأعراف', 'verses': 206, 'type': 'meccan', 'juz': 8},
    {'id': 8, 'name': 'الأنفال', 'verses': 75, 'type': 'medinan', 'juz': 9},
    {'id': 9, 'name': 'التوبة', 'verses': 129, 'type': 'medinan', 'juz': 10},
    {'id': 10, 'name': 'يونس', 'verses': 109, 'type': 'meccan', 'juz': 11},
    {'id': 11, 'name': 'هود', 'verses': 123, 'type': 'meccan', 'juz': 11},
    {'id': 12, 'name': 'يوسف', 'verses': 111, 'type': 'meccan', 'juz': 12},
    {'id': 13, 'name': 'الرعد', 'verses': 43, 'type': 'medinan', 'juz': 13},
    {'id': 14, 'name': 'إبراهيم', 'verses': 52, 'type': 'meccan', 'juz': 13},
    {'id': 15, 'name': 'الحجر', 'verses': 99, 'type': 'meccan', 'juz': 14},
    {'id': 16, 'name': 'النحل', 'verses': 128, 'type': 'meccan', 'juz': 14},
    {'id': 17, 'name': 'الإسراء', 'verses': 111, 'type': 'meccan', 'juz': 15},
    {'id': 18, 'name': 'الكهف', 'verses': 110, 'type': 'meccan', 'juz': 15},
    {'id': 19, 'name': 'مريم', 'verses': 98, 'type': 'meccan', 'juz': 16},
    {'id': 20, 'name': 'طه', 'verses': 135, 'type': 'meccan', 'juz': 16},
    {'id': 21, 'name': 'الأنبياء', 'verses': 112, 'type': 'meccan', 'juz': 17},
    {'id': 22, 'name': 'الحج', 'verses': 78, 'type': 'medinan', 'juz': 17},
    {'id': 23, 'name': 'المؤمنون', 'verses': 118, 'type': 'meccan', 'juz': 18},
    {'id': 24, 'name': 'النور', 'verses': 64, 'type': 'medinan', 'juz': 18},
    {'id': 25, 'name': 'الفرقان', 'verses': 77, 'type': 'meccan', 'juz': 18},
    {'id': 26, 'name': 'الشعراء', 'verses': 227, 'type': 'meccan', 'juz': 19},
    {'id': 27, 'name': 'النمل', 'verses': 93, 'type': 'meccan', 'juz': 19},
    {'id': 28, 'name': 'القصص', 'verses': 88, 'type': 'meccan', 'juz': 20},
    {'id': 29, 'name': 'العنكبوت', 'verses': 69, 'type': 'meccan', 'juz': 20},
    {'id': 30, 'name': 'الروم', 'verses': 60, 'type': 'meccan', 'juz': 21},
    {'id': 31, 'name': 'لقمان', 'verses': 34, 'type': 'meccan', 'juz': 21},
    {'id': 32, 'name': 'السجدة', 'verses': 30, 'type': 'meccan', 'juz': 21},
    {'id': 33, 'name': 'الأحزاب', 'verses': 73, 'type': 'medinan', 'juz': 21},
    {'id': 34, 'name': 'سبأ', 'verses': 54, 'type': 'meccan', 'juz': 22},
    {'id': 35, 'name': 'فاطر', 'verses': 45, 'type': 'meccan', 'juz': 22},
    {'id': 36, 'name': 'يس', 'verses': 83, 'type': 'meccan', 'juz': 22},
    {'id': 37, 'name': 'الصافات', 'verses': 182, 'type': 'meccan', 'juz': 23},
    {'id': 38, 'name': 'ص', 'verses': 88, 'type': 'meccan', 'juz': 23},
    {'id': 39, 'name': 'الزمر', 'verses': 75, 'type': 'meccan', 'juz': 23},
    {'id': 40, 'name': 'غافر', 'verses': 85, 'type': 'meccan', 'juz': 24},
    {'id': 41, 'name': 'فصلت', 'verses': 54, 'type': 'meccan', 'juz': 24},
    {'id': 42, 'name': 'الشورى', 'verses': 53, 'type': 'meccan', 'juz': 25},
    {'id': 43, 'name': 'الزخرف', 'verses': 89, 'type': 'meccan', 'juz': 25},
    {'id': 44, 'name': 'الدخان', 'verses': 59, 'type': 'meccan', 'juz': 25},
    {'id': 45, 'name': 'الجاثية', 'verses': 37, 'type': 'meccan', 'juz': 25},
    {'id': 46, 'name': 'الأحقاف', 'verses': 35, 'type': 'meccan', 'juz': 26},
    {'id': 47, 'name': 'محمد', 'verses': 38, 'type': 'medinan', 'juz': 26},
    {'id': 48, 'name': 'الفتح', 'verses': 29, 'type': 'medinan', 'juz': 26},
    {'id': 49, 'name': 'الحجرات', 'verses': 18, 'type': 'medinan', 'juz': 26},
    {'id': 50, 'name': 'ق', 'verses': 45, 'type': 'meccan', 'juz': 26},
    {'id': 51, 'name': 'الذاريات', 'verses': 60, 'type': 'meccan', 'juz': 26},
    {'id': 52, 'name': 'الطور', 'verses': 49, 'type': 'meccan', 'juz': 27},
    {'id': 53, 'name': 'النجم', 'verses': 62, 'type': 'meccan', 'juz': 27},
    {'id': 54, 'name': 'القمر', 'verses': 55, 'type': 'meccan', 'juz': 27},
    {'id': 55, 'name': 'الرحمن', 'verses': 78, 'type': 'medinan', 'juz': 27},
    {'id': 56, 'name': 'الواقعة', 'verses': 96, 'type': 'meccan', 'juz': 27},
    {'id': 57, 'name': 'الحديد', 'verses': 29, 'type': 'medinan', 'juz': 27},
    {'id': 58, 'name': 'المجادلة', 'verses': 22, 'type': 'medinan', 'juz': 28},
    {'id': 59, 'name': 'الحشر', 'verses': 24, 'type': 'medinan', 'juz': 28},
    {'id': 60, 'name': 'الممتحنة', 'verses': 13, 'type': 'medinan', 'juz': 28},
    {'id': 61, 'name': 'الصف', 'verses': 14, 'type': 'medinan', 'juz': 28},
    {'id': 62, 'name': 'الجمعة', 'verses': 11, 'type': 'medinan', 'juz': 28},
    {'id': 63, 'name': 'المنافقون', 'verses': 11, 'type': 'medinan', 'juz': 28},
    {'id': 64, 'name': 'التغابن', 'verses': 18, 'type': 'medinan', 'juz': 28},
    {'id': 65, 'name': 'الطلاق', 'verses': 12, 'type': 'medinan', 'juz': 28},
    {'id': 66, 'name': 'التحريم', 'verses': 12, 'type': 'medinan', 'juz': 28},
    {'id': 67, 'name': 'الملك', 'verses': 30, 'type': 'meccan', 'juz': 29},
    {'id': 68, 'name': 'القلم', 'verses': 52, 'type': 'meccan', 'juz': 29},
    {'id': 69, 'name': 'الحاقة', 'verses': 52, 'type': 'meccan', 'juz': 29},
    {'id': 70, 'name': 'المعارج', 'verses': 44, 'type': 'meccan', 'juz': 29},
    {'id': 71, 'name': 'نوح', 'verses': 28, 'type': 'meccan', 'juz': 29},
    {'id': 72, 'name': 'الجن', 'verses': 28, 'type': 'meccan', 'juz': 29},
    {'id': 73, 'name': 'المزمل', 'verses': 20, 'type': 'meccan', 'juz': 29},
    {'id': 74, 'name': 'المدثر', 'verses': 56, 'type': 'meccan', 'juz': 29},
    {'id': 75, 'name': 'القيامة', 'verses': 40, 'type': 'meccan', 'juz': 29},
    {'id': 76, 'name': 'الإنسان', 'verses': 31, 'type': 'medinan', 'juz': 29},
    {'id': 77, 'name': 'المرسلات', 'verses': 50, 'type': 'meccan', 'juz': 29},
    {'id': 78, 'name': 'النبأ', 'verses': 40, 'type': 'meccan', 'juz': 30},
    {'id': 79, 'name': 'النازعات', 'verses': 46, 'type': 'meccan', 'juz': 30},
    {'id': 80, 'name': 'عبس', 'verses': 42, 'type': 'meccan', 'juz': 30},
    {'id': 81, 'name': 'التكوير', 'verses': 29, 'type': 'meccan', 'juz': 30},
    {'id': 82, 'name': 'الإنفطار', 'verses': 19, 'type': 'meccan', 'juz': 30},
    {'id': 83, 'name': 'المطففين', 'verses': 36, 'type': 'meccan', 'juz': 30},
    {'id': 84, 'name': 'الإنشقاق', 'verses': 25, 'type': 'meccan', 'juz': 30},
    {'id': 85, 'name': 'البروج', 'verses': 22, 'type': 'meccan', 'juz': 30},
    {'id': 86, 'name': 'الطارق', 'verses': 17, 'type': 'meccan', 'juz': 30},
    {'id': 87, 'name': 'الأعلى', 'verses': 19, 'type': 'meccan', 'juz': 30},
    {'id': 88, 'name': 'الغاشية', 'verses': 26, 'type': 'meccan', 'juz': 30},
    {'id': 89, 'name': 'الفجر', 'verses': 30, 'type': 'meccan', 'juz': 30},
    {'id': 90, 'name': 'البلد', 'verses': 20, 'type': 'meccan', 'juz': 30},
    {'id': 91, 'name': 'الشمس', 'verses': 15, 'type': 'meccan', 'juz': 30},
    {'id': 92, 'name': 'الليل', 'verses': 21, 'type': 'meccan', 'juz': 30},
    {'id': 93, 'name': 'الضحى', 'verses': 11, 'type': 'meccan', 'juz': 30},
    {'id': 94, 'name': 'الشرح', 'verses': 8, 'type': 'meccan', 'juz': 30},
    {'id': 95, 'name': 'التين', 'verses': 8, 'type': 'meccan', 'juz': 30},
    {'id': 96, 'name': 'العلق', 'verses': 19, 'type': 'meccan', 'juz': 30},
    {'id': 97, 'name': 'القدر', 'verses': 5, 'type': 'meccan', 'juz': 30},
    {'id': 98, 'name': 'البينة', 'verses': 8, 'type': 'medinan', 'juz': 30},
    {'id': 99, 'name': 'الزلزلة', 'verses': 8, 'type': 'medinan', 'juz': 30},
    {'id': 100, 'name': 'العاديات', 'verses': 11, 'type': 'meccan', 'juz': 30},
    {'id': 101, 'name': 'القارعة', 'verses': 11, 'type': 'meccan', 'juz': 30},
    {'id': 102, 'name': 'التكاثر', 'verses': 8, 'type': 'meccan', 'juz': 30},
    {'id': 103, 'name': 'العصر', 'verses': 3, 'type': 'meccan', 'juz': 30},
    {'id': 104, 'name': 'الهمزة', 'verses': 9, 'type': 'meccan', 'juz': 30},
    {'id': 105, 'name': 'الفيل', 'verses': 5, 'type': 'meccan', 'juz': 30},
    {'id': 106, 'name': 'قريش', 'verses': 4, 'type': 'meccan', 'juz': 30},
    {'id': 107, 'name': 'الماعون', 'verses': 7, 'type': 'meccan', 'juz': 30},
    {'id': 108, 'name': 'الكوثر', 'verses': 3, 'type': 'meccan', 'juz': 30},
    {'id': 109, 'name': 'الكافرون', 'verses': 6, 'type': 'meccan', 'juz': 30},
    {'id': 110, 'name': 'النصر', 'verses': 3, 'type': 'medinan', 'juz': 30},
    {'id': 111, 'name': 'المسد', 'verses': 5, 'type': 'meccan', 'juz': 30},
    {'id': 112, 'name': 'الإخلاص', 'verses': 4, 'type': 'meccan', 'juz': 30},
    {'id': 113, 'name': 'الفلق', 'verses': 5, 'type': 'meccan', 'juz': 30},
    {'id': 114, 'name': 'الناس', 'verses': 6, 'type': 'meccan', 'juz': 30},
  ];

  @override
  void initState() {
    super.initState();
    _loadQuranPrefs();
  }

  Future<void> _loadQuranPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _bookmarks = prefs.getStringList('quran_bookmarks') ?? [];
      _fontSize = prefs.getDouble('quran_font_size') ?? 24.0;
      _selectedReciter = prefs.getString('quran_reciter') ?? 'afasy';
      _showAyahNumbers = prefs.getBool('quran_show_ayah_num') ?? true;
      _showTashkeel = prefs.getBool('quran_show_tashkeel') ?? true;
    });
  }

  Future<void> _saveBookmarks() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('quran_bookmarks', _bookmarks);
  }

  void _openSurahReader(Map surah, {int? targetAyah}) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SurahFullReaderPage(
          surah: surah,
          allSurahs: _surahsData,
          reciters: _reciters,
          selectedReciter: _selectedReciter,
          fontSize: _fontSize,
          nightMode: _nightMode,
          showAyahNumbers: _showAyahNumbers,
          showTashkeel: _showTashkeel,
          bookmarks: _bookmarks,
          targetAyah: targetAyah,
          onBookmarksChanged: (updated) {
            setState(() => _bookmarks = updated);
            _saveBookmarks();
          },
          onSettingsChanged: (newSize, newReciter, newNight, newAyahNum, newTashkeel) async {
            final prefs = await SharedPreferences.getInstance();
            await prefs.setDouble('quran_font_size', newSize);
            await prefs.setString('quran_reciter', newReciter);
            await prefs.setBool('quran_show_ayah_num', newAyahNum);
            await prefs.setBool('quran_show_tashkeel', newTashkeel);
            setState(() {
              _fontSize = newSize;
              _selectedReciter = newReciter;
              _nightMode = newNight;
              _showAyahNumbers = newAyahNum;
              _showTashkeel = newTashkeel;
            });
          },
        ),
      ),
    );
  }

  void _openReadingSettingsSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF142A33),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) => Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.tune_rounded, color: Color(0xFFFFD700)),
                  SizedBox(width: 8),
                  Text("إعدادات القراءة", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFFFFD700))),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text("حجم الخط", style: TextStyle(fontWeight: FontWeight.bold)),
                  Row(
                    children: [
                      _fontPresetBtn("ص", 19.0, setSheetState),
                      _fontPresetBtn("ط", 24.0, setSheetState),
                      _fontPresetBtn("ك", 29.0, setSheetState),
                      _fontPresetBtn("ك+", 34.0, setSheetState),
                    ],
                  ),
                ],
              ),
              const Divider(color: Colors.white10, height: 22),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text("القارئ الصوتي", style: TextStyle(fontWeight: FontWeight.bold)),
                  SizedBox(
                    width: 210,
                    child: DropdownButtonFormField<String>(
                      value: _selectedReciter,
                      dropdownColor: const Color(0xFF162A33),
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: const Color(0xFF0F2027),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                      ),
                      items: _reciters.entries
                          .map((e) => DropdownMenuItem<String>(value: e.key.toString(), child: Text(e.value['name'].toString(), style: const TextStyle(fontSize: 12))))
                          .toList(),
                      onChanged: (v) async {
                        if (v != null) {
                          final prefs = await SharedPreferences.getInstance();
                          await prefs.setString('quran_reciter', v);
                          setState(() => _selectedReciter = v);
                          setSheetState(() {});
                        }
                      },
                    ),
                  ),
                ],
              ),
              const Divider(color: Colors.white10, height: 20),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text("عرض أرقام الآيات"),
                value: _showAyahNumbers,
                activeColor: const Color(0xFF1FC0A0),
                onChanged: (v) async {
                  final prefs = await SharedPreferences.getInstance();
                  await prefs.setBool('quran_show_ayah_num', v);
                  setState(() => _showAyahNumbers = v);
                  setSheetState(() {});
                },
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text("التشكيل"),
                value: _showTashkeel,
                activeColor: const Color(0xFF1FC0A0),
                onChanged: (v) async {
                  final prefs = await SharedPreferences.getInstance();
                  await prefs.setBool('quran_show_tashkeel', v);
                  setState(() => _showTashkeel = v);
                  setSheetState(() {});
                },
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text("الانتقال للعلامة", style: TextStyle(fontWeight: FontWeight.bold)),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF162A33), foregroundColor: Colors.white),
                    onPressed: () {
                      Navigator.pop(ctx);
                      setState(() => _subNavIndex = 1);
                    },
                    icon: const Icon(Icons.bookmark, size: 16, color: Color(0xFFFFD700)),
                    label: const Text("اذهب"),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _fontPresetBtn(String label, double size, StateSetter setSheetState) {
    final active = (_fontSize - size).abs() < 1.0;
    return GestureDetector(
      onTap: () async {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setDouble('quran_font_size', size);
        setState(() => _fontSize = size);
        setSheetState(() {});
      },
      child: Container(
        margin: const EdgeInsets.only(right: 6),
        width: 36,
        height: 36,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: active ? const Color(0xFF1FC0A0) : const Color(0xFF0F2027),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.white12),
        ),
        child: Text(label, style: TextStyle(fontWeight: FontWeight.bold, color: active ? Colors.black : Colors.white)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _surahsData.where((s) {
      final matchesType = _filterType == 'all' || s['type'] == _filterType;
      final matchesSearch = _searchQuery.isEmpty || s['name'].toString().contains(_searchQuery) || s['id'].toString() == _searchQuery;
      return matchesType && matchesSearch;
    }).toList();

    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  IconButton(
                    icon: const Icon(Icons.settings_rounded, color: Colors.white70),
                    onPressed: _openReadingSettingsSheet,
                  ),
                ],
              ),
              const Icon(Icons.menu_book_rounded, size: 48, color: Color(0xFFFFD700)),
              const SizedBox(height: 6),
              const Text("المصحف الشريف", textAlign: TextAlign.center, style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900)),
              const Text("اقرأ واستمع للقرآن الكريم كاملاً", textAlign: TextAlign.center, style: TextStyle(fontSize: 13, color: Colors.white70)),
              const SizedBox(height: 16),

              if (_subNavIndex == 0) ...[
                TextField(
                  onChanged: (v) => setState(() => _searchQuery = v),
                  decoration: InputDecoration(
                    hintText: "ابحث في السور...",
                    prefixIcon: const Icon(Icons.search, color: Color(0xFF8A9EA6)),
                    filled: true,
                    fillColor: const Color(0xFF162A33),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide.none),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    _buildFilterChip("الكل", "all"),
                    const SizedBox(width: 8),
                    _buildFilterChip("مكية", "meccan"),
                    const SizedBox(width: 8),
                    _buildFilterChip("مدنية", "medinan"),
                  ],
                ),
                const SizedBox(height: 14),
                ...filtered.map((s) {
                  final isMeccan = s['type'] == 'meccan';
                  return GestureDetector(
                    onTap: () => _openSurahReader(s),
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: const Color(0xFF162A33),
                        borderRadius: BorderRadius.circular(15),
                        border: Border.all(color: Colors.white10),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 44,
                            height: 44,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(colors: [Color(0xFF1FC0A0), Color(0xFF13C2C2)]),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text("${s['id']}", style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: Color(0xFF0F2027))),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(s['name'].toString(), style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
                                const SizedBox(height: 3),
                                Text(
                                  "${s['verses']} آية  •  الجزء ${s['juz']}  •  ${isMeccan ? 'مكية' : 'مدنية'}",
                                  style: const TextStyle(fontSize: 12, color: Color(0xFF8A9EA6)),
                                ),
                              ],
                            ),
                          ),
                          Icon(
                            isMeccan ? Icons.account_balance_rounded : Icons.mosque_rounded,
                            color: const Color(0xFFFFD700),
                            size: 24,
                          ),
                        ],
                      ),
                    ),
                  );
                }),
              ] else ...[
                const Padding(
                  padding: EdgeInsets.only(bottom: 12),
                  child: Row(
                    children: [
                      Icon(Icons.bookmark, color: Color(0xFFFFD700), size: 20),
                      SizedBox(width: 6),
                      Text("الآيات والسور المحفوظة:", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFFFFD700))),
                    ],
                  ),
                ),
                if (_bookmarks.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(40),
                    child: Center(child: Text("لا توجد علامات محفوظة حالياً", style: TextStyle(color: Colors.white60))),
                  )
                else
                  ..._bookmarks.map((b) {
                    if (b.startsWith('surah-')) {
                      final id = int.tryParse(b.replaceFirst('surah-', '')) ?? 1;
                      final s = _surahsData.firstWhere((e) => e['id'] == id);
                      return _buildBookmarkCard(
                        title: "سورة ${s['name']}",
                        subtitle: "علامة على السورة كاملة",
                        isSurah: true,
                        onTap: () => _openSurahReader(s),
                      );
                    } else {
                      final parts = b.split('-');
                      final sId = int.tryParse(parts[0]) ?? 1;
                      final aNum = int.tryParse(parts[1]) ?? 1;
                      final s = _surahsData.firstWhere((e) => e['id'] == sId);
                      return _buildBookmarkCard(
                        title: "سورة ${s['name']} (الآية $aNum)",
                        subtitle: "الانتقال المباشر للآية",
                        isSurah: false,
                        onTap: () => _openSurahReader(s, targetAyah: aNum),
                      );
                    }
                  }),
              ],
            ],
          ),
        ),
        Container(
          height: 54,
          decoration: const BoxDecoration(
            color: Color(0xFF142A33),
            border: Border(top: BorderSide(color: Colors.white10)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildSubNavBtn(0, Icons.menu_book_rounded, "السور"),
              _buildSubNavBtn(1, Icons.bookmark_rounded, "العلامات"),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildFilterChip(String label, String type) {
    final active = _filterType == type;
    return GestureDetector(
      onTap: () => setState(() => _filterType = type),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        decoration: BoxDecoration(
          color: active ? const Color(0xFF1FC0A0) : const Color(0xFF162A33),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: active ? const Color(0xFF1FC0A0) : Colors.white12),
        ),
        child: Text(
          label,
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: active ? const Color(0xFF0F2027) : Colors.white70),
        ),
      ),
    );
  }

  Widget _buildSubNavBtn(int idx, IconData icon, String label) {
    final active = _subNavIndex == idx;
    return GestureDetector(
      onTap: () => setState(() => _subNavIndex = idx),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: active ? const Color(0xFFFFD700) : const Color(0xFF8A9EA6), size: 22),
          Text(label, style: TextStyle(fontSize: 11, color: active ? const Color(0xFFFFD700) : const Color(0xFF8A9EA6), fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _buildBookmarkCard({required String title, required String subtitle, required bool isSurah, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFF162A33),
          borderRadius: BorderRadius.circular(15),
          border: Border.all(color: Colors.white10),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: isSurah ? const Color(0xFFFFB300) : const Color(0xFF1FC0A0),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.bookmark, color: Color(0xFF0F2027)),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  Text(subtitle, style: const TextStyle(fontSize: 12, color: Color(0xFF8A9EA6))),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: Color(0xFFFFD700)),
          ],
        ),
      ),
    );
  }
}

class SurahFullReaderPage extends StatefulWidget {
  final Map surah;
  final List allSurahs;
  final Map reciters;
  final String selectedReciter;
  final double fontSize;
  final bool nightMode;
  final bool showAyahNumbers;
  final bool showTashkeel;
  final List<String> bookmarks;
  final int? targetAyah;
  final ValueChanged<List<String>> onBookmarksChanged;
  final Function(double, String, bool, bool, bool) onSettingsChanged;

  const SurahFullReaderPage({
    super.key,
    required this.surah,
    required this.allSurahs,
    required this.reciters,
    required this.selectedReciter,
    required this.fontSize,
    required this.nightMode,
    required this.showAyahNumbers,
    required this.showTashkeel,
    required this.bookmarks,
    this.targetAyah,
    required this.onBookmarksChanged,
    required this.onSettingsChanged,
  });

  @override
  State<SurahFullReaderPage> createState() => _SurahFullReaderPageState();
}

class _SurahFullReaderPageState extends State<SurahFullReaderPage> {
  late Map _currentSurah;
  late String _reciter;
  late double _fontSize;
  late bool _showAyahNum;
  late bool _showTashkeel;
  late List<String> _bookmarks;

  List _ayahs = [];
  bool _loading = true;

  final AudioPlayer _player = AudioPlayer();
  bool _isPlaying = false;
  Duration _duration = Duration.zero;
  Duration _position = Duration.zero;

  @override
  void initState() {
    super.initState();
    _currentSurah = widget.surah;
    _reciter = widget.selectedReciter;
    _fontSize = widget.fontSize;
    _showAyahNum = widget.showAyahNumbers;
    _showTashkeel = widget.showTashkeel;
    _bookmarks = List<String>.from(widget.bookmarks);

    _fetchAyahs();
    _player.onDurationChanged.listen((d) {
      if (mounted) setState(() => _duration = d);
    });
    _player.onPositionChanged.listen((p) {
      if (mounted) setState(() => _position = p);
    });
    _player.onPlayerComplete.listen((_) {
      if (mounted) setState(() => _isPlaying = false);
    });
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  Future<void> _fetchAyahs() async {
    setState(() => _loading = true);
    try {
      final res = await http.get(Uri.parse('https://api.alquran.cloud/v1/surah/${_currentSurah['id']}/quran-uthmani'));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        setState(() {
          _ayahs = data['data']['ayahs'];
          _loading = false;
        });
      }
    } catch (_) {
      setState(() => _loading = false);
    }
  }

  Future<void> _togglePlay() async {
    if (_isPlaying) {
      await _player.pause();
      setState(() => _isPlaying = false);
    } else {
      final padded = _currentSurah['id'].toString().padLeft(3, '0');
      final url = "${widget.reciters[_reciter]['url']}/$padded.mp3";
      await _player.play(UrlSource(url));
      setState(() => _isPlaying = true);
    }
  }

  void _toggleSurahBookmark() {
    final key = "surah-${_currentSurah['id']}";
    setState(() {
      if (_bookmarks.contains(key)) {
        _bookmarks.remove(key);
      } else {
        _bookmarks.add(key);
      }
    });
    widget.onBookmarksChanged(_bookmarks);
  }

  void _toggleAyahBookmark(int ayahNum) {
    final key = "${_currentSurah['id']}-$ayahNum";
    setState(() {
      if (_bookmarks.contains(key)) {
        _bookmarks.remove(key);
      } else {
        _bookmarks.add(key);
      }
    });
    widget.onBookmarksChanged(_bookmarks);
  }

  String _stripTashkeel(String input) {
    return input.replaceAll(RegExp(r'[\u064B-\u065F\u0670\u0640]'), '');
  }

  @override
  Widget build(BuildContext context) {
    final isSurahBookmarked = _bookmarks.contains("surah-${_currentSurah['id']}");

    return Scaffold(
      backgroundColor: const Color(0xFF0F2027),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F2027),
        title: Text("سورة ${_currentSurah['name']}", style: const TextStyle(color: Color(0xFFFFD700), fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            icon: Icon(isSurahBookmarked ? Icons.bookmark : Icons.bookmark_border, color: const Color(0xFFFFD700)),
            onPressed: _toggleSurahBookmark,
          ),
          IconButton(
            icon: Icon(_showTashkeel ? Icons.text_fields : Icons.title, color: Colors.white70),
            onPressed: () {
              setState(() => _showTashkeel = !_showTashkeel);
              widget.onSettingsChanged(_fontSize, _reciter, true, _showAyahNum, _showTashkeel);
            },
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator(color: Color(0xFFFFD700)))
                : ListView(
                    padding: const EdgeInsets.all(18),
                    children: [
                      if (_currentSurah['id'] != 9)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 18),
                          child: Text(
                            "بِسْمِ اللَّهِ الرَّحْمَٰنِ الرَّحِيمِ",
                            textAlign: TextAlign.center,
                            style: GoogleFonts.amiri(fontSize: 26, color: const Color(0xFFFFD700), fontWeight: FontWeight.bold),
                          ),
                        ),
                      Wrap(
                        alignment: WrapAlignment.center,
                        children: _ayahs.map((a) {
                          final int num = a['numberInSurah'];
                          String txt = a['text'].toString();
                          if (_currentSurah['id'] != 1 && num == 1) {
                            txt = txt.replaceFirst("بِسْمِ ٱللَّهِ ٱلرَّحْمَٰنِ ٱلرَّحِيمِ", "").trim();
                          }
                          if (!_showTashkeel) txt = _stripTashkeel(txt);
                          final isBookmarked = _bookmarks.contains("${_currentSurah['id']}-$num");

                          return GestureDetector(
                            onTap: () => _toggleAyahBookmark(num),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 2),
                              decoration: BoxDecoration(
                                color: isBookmarked ? const Color(0x33FFD700) : Colors.transparent,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text.rich(
                                TextSpan(
                                  style: GoogleFonts.amiri(fontSize: _fontSize, height: 2.1, color: Colors.white),
                                  children: [
                                    TextSpan(text: "$txt "),
                                    if (_showAyahNum)
                                      TextSpan(
                                        text: "﴿$num﴾ ",
                                        style: TextStyle(
                                          color: isBookmarked ? const Color(0xFFFFD700) : const Color(0xFF1FC0A0),
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ],
                  ),
          ),
          Container(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 14),
            decoration: const BoxDecoration(
              color: Color(0xFF142A33),
              border: Border(top: BorderSide(color: Colors.white10)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  "القارئ: ${widget.reciters[_reciter]['name']} | اضغط على أي آية لحفظ علامة",
                  style: const TextStyle(fontSize: 11, color: Color(0xFF8A9EA6)),
                ),
                SliderTheme(
                  data: SliderTheme.of(context).copyWith(thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6), trackHeight: 2),
                  child: Slider(
                    activeColor: const Color(0xFF1FC0A0),
                    inactiveColor: Colors.white24,
                    value: _position.inSeconds.toDouble().clamp(0, _duration.inSeconds.toDouble() > 0 ? _duration.inSeconds.toDouble() : 1),
                    max: _duration.inSeconds.toDouble() > 0 ? _duration.inSeconds.toDouble() : 1,
                    onChanged: (v) => _player.seek(Duration(seconds: v.toInt())),
                  ),
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.text_decrease_rounded),
                      onPressed: () => setState(() => _fontSize = (_fontSize - 2).clamp(16, 38)),
                    ),
                    IconButton(
                      icon: const Icon(Icons.skip_previous_rounded),
                      onPressed: _currentSurah['id'] > 1
                          ? () {
                              _player.stop();
                              setState(() {
                                _isPlaying = false;
                                _currentSurah = widget.allSurahs.firstWhere((e) => e['id'] == _currentSurah['id'] - 1);
                              });
                              _fetchAyahs();
                            }
                          : null,
                    ),
                    CircleAvatar(
                      radius: 24,
                      backgroundColor: const Color(0xFF1FC0A0),
                      child: IconButton(
                        icon: Icon(_isPlaying ? Icons.pause : Icons.play_arrow, color: const Color(0xFF0F2027), size: 28),
                        onPressed: _togglePlay,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.skip_next_rounded),
                      onPressed: _currentSurah['id'] < 114
                          ? () {
                              _player.stop();
                              setState(() {
                                _isPlaying = false;
                                _currentSurah = widget.allSurahs.firstWhere((e) => e['id'] == _currentSurah['id'] + 1);
                              });
                              _fetchAyahs();
                            }
                          : null,
                    ),
                    IconButton(
                      icon: const Icon(Icons.text_increase_rounded),
                      onPressed: () => setState(() => _fontSize = (_fontSize + 2).clamp(16, 38)),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class ReligiousQuizTab extends StatefulWidget {
  const ReligiousQuizTab({super.key});

  @override
  State<ReligiousQuizTab> createState() => _ReligiousQuizTabState();
}

class _ReligiousQuizTabState extends State<ReligiousQuizTab> {
  int _qIndex = 0;
  int _score = 0;
  int? _selectedOption;

  final List _questions = [
    {
      'q': 'ما هي السورة التي تُسمى قلب القرآن؟',
      'options': ['سورة البقرة', 'سورة يس', 'سورة الملك', 'سورة الرحمن'],
      'answer': 1,
    },
    {
      'q': 'كم عدد سور القرآن الكريم؟',
      'options': ['112 سورة', '114 سورة', '116 سورة', '120 سورة'],
      'answer': 1,
    },
    {
      'q': 'ما هي أطول آية في القرآن الكريم؟',
      'options': ['آية الكرسي', 'آية الدين', 'آية النور', 'آية المواريث'],
      'answer': 1,
    },
    {
      'q': 'في أي شهر أُنزل القرآن الكريم؟',
      'options': ['شهر رجب', 'شهر شعبان', 'شهر رمضان', 'شهر محرم'],
      'answer': 2,
    },
    {
      'q': 'ما هي السورة التي تخلو من البسملة في بدايتها؟',
      'options': ['سورة الأنفال', 'سورة التوبة', 'سورة الحج', 'سورة النمل'],
      'answer': 1,
    },
    {
      'q': 'من هو الصحابي الذي ذُكر اسمه صراحةً في القرآن الكريم؟',
      'options': ['أبو بكر الصديق', 'عمر بن الخطاب', 'زيد بن حارثة', 'علي بن أبي طالب'],
      'answer': 2,
    },
  ];

  void _selectAnswer(int idx) {
    if (_selectedOption != null) return;
    setState(() {
      _selectedOption = idx;
      if (idx == _questions[_qIndex]['answer']) _score++;
    });
  }

  void _nextQuestion() {
    setState(() {
      _selectedOption = null;
      _qIndex = (_qIndex + 1) % _questions.length;
      if (_qIndex == 0) _score = 0;
    });
  }

  @override
  Widget build(BuildContext context) {
    final current = _questions[_qIndex];
    final int correctIdx = current['answer'];
    final List options = current['options'];

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text("السؤال ${_qIndex + 1} من ${_questions.length}", style: const TextStyle(color: Color(0xFF1FC0A0), fontWeight: FontWeight.bold)),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(color: const Color(0x22FFD700), borderRadius: BorderRadius.circular(12)),
                child: Text("النقاط: $_score", style: const TextStyle(color: Color(0xFFFFD700), fontWeight: FontWeight.bold)),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: const Color(0xFF162A33),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: Colors.white12),
            ),
            child: Text(
              current['q'].toString(),
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 19, fontWeight: FontWeight.bold, height: 1.5),
            ),
          ),
          const SizedBox(height: 18),
          ...List.generate(options.length, (idx) {
            final opt = options[idx].toString();
            Color cardColor = const Color(0xFF162A33);
            Color borderColor = Colors.white10;

            if (_selectedOption != null) {
              if (idx == correctIdx) {
                cardColor = const Color(0xFF1B4332);
                borderColor = const Color(0xFF1FC0A0);
              } else if (idx == _selectedOption) {
                cardColor = const Color(0xFF4A1818);
                borderColor = Colors.redAccent;
              }
            }

            return GestureDetector(
              onTap: () => _selectAnswer(idx),
              child: Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: cardColor,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: borderColor, width: 1.5),
                ),
                child: Text(opt, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
              ),
            );
          }),
          const Spacer(),
          if (_selectedOption != null)
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFFD700),
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              onPressed: _nextQuestion,
              child: Text(_qIndex + 1 == _questions.length ? "إعادة الاختبار" : "السؤال التالي", style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            ),
        ],
      ),
    );
  }
}

class QiblaCompassTab extends StatefulWidget {
  const QiblaCompassTab({super.key});

  @override
  State<QiblaCompassTab> createState() => _QiblaCompassTabState();
}

class _QiblaCompassTabState extends State<QiblaCompassTab> {
  double _qiblaAngle = 136.0;

  @override
  void initState() {
    super.initState();
    _calcQibla();
  }

  Future<void> _calcQibla() async {
    try {
      final pos = await Geolocator.getCurrentPosition();
      const kaabaLat = 21.4225 * math.pi / 180;
      const kaabaLng = 39.8262 * math.pi / 180;
      final uLat = pos.latitude * math.pi / 180;
      final uLng = pos.longitude * math.pi / 180;
      final dLng = kaabaLng - uLng;
      final y = math.sin(dLng);
      final x = math.cos(uLat) * math.tan(kaabaLat) - math.sin(uLat) * math.cos(dLng);
      setState(() => _qiblaAngle = (math.atan2(y, x) * 180 / math.pi + 360) % 360);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<CompassEvent>(
      stream: FlutterCompass.events,
      builder: (context, snapshot) {
        final heading = snapshot.data?.heading ?? 0;
        final diff = ((_qiblaAngle - heading) + 360) % 360;
        final aligned = diff < 5 || diff > 355;

        return Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text("زاوية القبلة: ${_qiblaAngle.toStringAsFixed(1)}°", style: const TextStyle(fontSize: 18, color: Color(0xFFFFD700), fontWeight: FontWeight.bold)),
              const SizedBox(height: 24),
              Container(
                width: 240,
                height: 240,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFF162A33),
                  border: Border.all(color: aligned ? const Color(0xFF1FC0A0) : const Color(0xFFFFD700), width: 3),
                ),
                child: Transform.rotate(
                  angle: (_qiblaAngle - heading) * (math.pi / 180),
                  child: const Icon(Icons.navigation_rounded, size: 95, color: Color(0xFFFFD700)),
                ),
              ),
              const SizedBox(height: 20),
              Text(
                aligned ? "أنت الآن باتجاه القبلة تماماً" : "أدِر الهاتف حتى يشير السهم للأعلى",
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: aligned ? const Color(0xFF1FC0A0) : Colors.white70),
              ),
            ],
          ),
        );
      },
    );
  }
}

class AzkarAndTasbihTab extends StatefulWidget {
  const AzkarAndTasbihTab({super.key});

  @override
  State<AzkarAndTasbihTab> createState() => _AzkarAndTasbihTabState();
}

class _AzkarAndTasbihTabState extends State<AzkarAndTasbihTab> {
  int _count = 0;
  int _total = 0;

  final List _azkar = [
    {"title": "أذكار الصباح", "text": "أصبحنا وأصبح الملك لله، والحمد لله، لا إله إلا الله وحده لا شريك له، له الملك وله الحمد وهو على كل شيء قدير."},
    {"title": "أذكار المساء", "text": "أمسينا وأمسى الملك لله، والحمد لله، لا إله إلا الله وحده لا شريك له، له الملك وله الحمد وهو على كل شيء قدير."},
    {"title": "سيد الاستغفار", "text": "اللهم أنت ربي لا إله إلا أنت، خلقتني وأنا عبدك، وأنا على عهدك ووعدك ما استطعت، أعوذ بك من شر ما صنعت."},
  ];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() => _total = prefs.getInt('total_tasbih') ?? 0);
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text("السبحة الإلكترونية", textAlign: TextAlign.center, style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xFFFFD700))),
        const SizedBox(height: 14),
        GestureDetector(
          onTap: () async {
            HapticFeedback.lightImpact();
            final prefs = await SharedPreferences.getInstance();
            setState(() {
              _count++;
              _total++;
            });
            await prefs.setInt('total_tasbih', _total);
          },
          child: Container(
            width: 140,
            height: 140,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(colors: [Color(0xFF1FC0A0), Color(0xFF13C2C2)]),
            ),
            child: Center(
              child: Text("$_count", style: const TextStyle(fontSize: 42, fontWeight: FontWeight.bold, color: Color(0xFF0F2027))),
            ),
          ),
        ),
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text("الإجمالي: $_total", style: const TextStyle(color: Color(0xFFFFD700), fontWeight: FontWeight.bold)),
            TextButton(onPressed: () => setState(() => _count = 0), child: const Text("تصفير")),
          ],
        ),
        const Divider(color: Colors.white12, height: 24),
        const Text("أفضل الأذكار", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFFFFD700))),
        const SizedBox(height: 10),
        ..._azkar.map((z) => Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: const Color(0xFF162A33), borderRadius: BorderRadius.circular(14)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(z["title"].toString(), style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF1FC0A0))),
                  const SizedBox(height: 6),
                  Text(z["text"].toString(), style: GoogleFonts.amiri(fontSize: 19, height: 1.7)),
                ],
              ),
            )),
      ],
    );
  }
}
