import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:adhan/adhan.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_compass/flutter_compass.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart' hide TextDirection;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:record/record.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
    ),
  );
  runApp(const TareeqAlJannahApp());
}

class TareeqAlJannahApp extends StatelessWidget {
  const TareeqAlJannahApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'طريق الجنة',
      locale: const Locale('ar', 'EG'),
      supportedLocales: const [Locale('ar', 'EG')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF0A1210),
        primaryColor: const Color(0xFFD4AF37),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFFD4AF37),
          secondary: Color(0xFF10B981),
          surface: Color(0xFF12211D),
        ),
        textTheme: GoogleFonts.cairoTextTheme(ThemeData.dark().textTheme),
      ),
      home: const MainDashboardScreen(),
    );
  }
}

class MainDashboardScreen extends StatefulWidget {
  const MainDashboardScreen({super.key});

  @override
  State<MainDashboardScreen> createState() => _MainDashboardScreenState();
}

class _MainDashboardScreenState extends State<MainDashboardScreen> {
  int _selectedIndex = 0;

  double _lat = 26.1551;
  double _lng = 32.7160;
  String _cityName = "جاري تحديد الموقع...";
  PrayerTimes? _prayerTimes;
  Timer? _clockTimer;
  String _nextPrayerName = "";
  Duration _remainingTime = Duration.zero;

  final AudioPlayer _adhanPlayer = AudioPlayer();
  final AudioRecorder _audioRecorder = AudioRecorder();
  bool _isAdhanPlaying = false;
  bool _adhanEnabled = true;
  bool _fajrAlarmEnabled = true;
  String _selectedMuezzin = "مشاري راشد العفاسي";
  String? _customFajrAudioPath;
  bool _isRecordingFajr = false;
  bool _alarmTriggeredToday = false;

  final Map<String, String> _muezzinUrls = {
    "مشاري راشد العفاسي": "https://www.islamcan.com/audio/adhan/azan1.mp3",
    "أذان الحرم المكي": "https://www.islamcan.com/audio/adhan/azan2.mp3",
    "أذان المسجد النبوي": "https://www.islamcan.com/audio/adhan/azan3.mp3",
    "ناصر القطامي": "https://www.islamcan.com/audio/adhan/azan15.mp3",
  };

  @override
  void initState() {
    super.initState();
    _loadSettings();
    _calculatePrayers();
    _determinePosition();
    _startLiveClock();
  }

  @override
  void dispose() {
    _clockTimer?.cancel();
    _adhanPlayer.dispose();
    _audioRecorder.dispose();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _adhanEnabled = prefs.getBool('adhan_enabled') ?? true;
      _fajrAlarmEnabled = prefs.getBool('fajr_alarm_enabled') ?? true;
      _selectedMuezzin = prefs.getString('muezzin') ?? "مشاري راشد العفاسي";
      _customFajrAudioPath = prefs.getString('custom_fajr_path');
      _lat = prefs.getDouble('saved_lat') ?? 26.1551;
      _lng = prefs.getDouble('saved_lng') ?? 32.7160;
      _cityName = prefs.getString('saved_city') ?? "مصر";
    });
    _calculatePrayers();
  }

  Future<void> _determinePosition() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        setState(() => _cityName = "مصر (فعّل GPS للدقة)");
        return;
      }
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) return;
      }
      if (permission == LocationPermission.deniedForever) return;

      Position pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.medium),
      );
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble('saved_lat', pos.latitude);
      await prefs.setDouble('saved_lng', pos.longitude);
      await prefs.setString('saved_city', "موقعك الحالي (GPS)");

      setState(() {
        _lat = pos.latitude;
        _lng = pos.longitude;
        _cityName = "موقعك الحالي (GPS)";
      });
      _calculatePrayers();
    } catch (_) {
      setState(() => _cityName = "مصر");
    }
  }

  void _calculatePrayers() {
    final coordinates = Coordinates(_lat, _lng);
    final params = CalculationMethod.egyptian.getParameters();
    params.madhab = Madhab.shafi;
    final date = DateComponents.from(DateTime.now());
    setState(() {
      _prayerTimes = PrayerTimes(coordinates, date, params);
    });
    _updateCountdown();
  }

  void _startLiveClock() {
    _clockTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      _updateCountdown();
      _checkAlarmTriggers();
    });
  }

  void _updateCountdown() {
    if (_prayerTimes == null) return;
    final now = DateTime.now();
    final pt = _prayerTimes!;

    final list = [
      MapEntry("الفجر", pt.fajr),
      MapEntry("الشروق", pt.sunrise),
      MapEntry("الظهر", pt.dhuhr),
      MapEntry("العصر", pt.asr),
      MapEntry("المغرب", pt.maghrib),
      MapEntry("العشاء", pt.isha),
    ];

    DateTime? target;
    String name = "الفجر";
    for (var item in list) {
      if (item.value.isAfter(now)) {
        target = item.value;
        name = item.key;
        break;
      }
    }
    if (target == null) {
      target = pt.fajr.add(const Duration(days: 1));
      name = "الفجر";
    }

    if (mounted) {
      setState(() {
        _nextPrayerName = name;
        _remainingTime = target!.difference(now);
      });
    }
  }

  void _checkAlarmTriggers() {
    if (_prayerTimes == null || _alarmTriggeredToday) return;
    final now = DateTime.now();
    final pt = _prayerTimes!;

    bool isSameMinute(DateTime t) =>
        now.year == t.year && now.month == t.month && now.day == t.day && now.hour == t.hour && now.minute == t.minute && now.second == 0;

    if (isSameMinute(pt.fajr) && _fajrAlarmEnabled) {
      _alarmTriggeredToday = true;
      _playFajrAlarm();
    } else if ((isSameMinute(pt.dhuhr) || isSameMinute(pt.asr) || isSameMinute(pt.maghrib) || isSameMinute(pt.isha)) && _adhanEnabled) {
      _alarmTriggeredToday = true;
      _toggleAdhan();
    }
    if (now.second == 2) _alarmTriggeredToday = false;
  }

  Future<void> _toggleAdhan() async {
    if (_isAdhanPlaying) {
      await _adhanPlayer.stop();
      setState(() => _isAdhanPlaying = false);
    } else {
      final url = _muezzinUrls[_selectedMuezzin]!;
      setState(() => _isAdhanPlaying = true);
      await _adhanPlayer.play(UrlSource(url));
      _adhanPlayer.onPlayerComplete.listen((_) {
        if (mounted) setState(() => _isAdhanPlaying = false);
      });
    }
  }

  Future<void> _playFajrAlarm() async {
    await _adhanPlayer.stop();
    setState(() => _isAdhanPlaying = true);
    if (_customFajrAudioPath != null && File(_customFajrAudioPath!).existsSync()) {
      await _adhanPlayer.play(DeviceFileSource(_customFajrAudioPath!));
    } else {
      await _adhanPlayer.play(UrlSource(_muezzinUrls[_selectedMuezzin]!));
    }
    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF12211D),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: const BorderSide(color: Color(0xFFD4AF37))),
        title: const Text("🌅 منبه صلاة الفجر", textAlign: TextAlign.center, style: TextStyle(color: Color(0xFFD4AF37), fontWeight: FontWeight.bold)),
        content: const Text("الصلاة خير من النوم.. حان الآن موعد أذان الفجر", textAlign: TextAlign.center),
        actions: [
          Center(
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFD4AF37), foregroundColor: Colors.black),
              onPressed: () {
                _adhanPlayer.stop();
                setState(() => _isAdhanPlaying = false);
                Navigator.pop(ctx);
              },
              icon: const Icon(Icons.alarm_off),
              label: const Text("إيقاف المنبه", style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          )
        ],
      ),
    );
  }

  Future<void> _toggleRecordFajrVoice() async {
    if (_isRecordingFajr) {
      final path = await _audioRecorder.stop();
      setState(() {
        _isRecordingFajr = false;
        if (path != null) _customFajrAudioPath = path;
      });
      if (path != null) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('custom_fajr_path', path);
        _showToast("✅ تم حفظ تسجيلك الصوتي لمنبه الفجر بنجاح!");
      }
    } else {
      final status = await Permission.microphone.request();
      if (!status.isGranted) {
        _showToast("⚠️ يرجى السماح بصلاحية الميكروفون للتسجيل");
        return;
      }
      final dir = await getApplicationDocumentsDirectory();
      final filePath = '${dir.path}/custom_fajr_alarm_${DateTime.now().millisecondsSinceEpoch}.m4a';
      await _audioRecorder.start(const RecordConfig(), path: filePath);
      setState(() => _isRecordingFajr = true);
    }
  }

  Future<void> _pickAudioFileForFajr() async {
    final res = await FilePicker.platform.pickFiles(type: FileType.audio);
    if (res != null && res.files.single.path != null) {
      final path = res.files.single.path!;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('custom_fajr_path', path);
      setState(() => _customFajrAudioPath = path);
      _showToast("✅ تم تعيين الملف الصوتي لمنبه الفجر!");
    }
  }

  void _showToast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: const Color(0xFF10B981), behavior: SnackBarBehavior.floating),
    );
  }

  String _formatDuration(Duration d) {
    String two(int n) => n.toString().padLeft(2, '0');
    return "${two(d.inHours)}:${two(d.inMinutes.remainder(60))}:${two(d.inSeconds.remainder(60))}";
  }

  @override
  Widget build(BuildContext context) {
    final screens = [
      _buildHomeAndPrayersTab(),
      const QuranCompleteTab(),
      QiblaCompassTab(lat: _lat, lng: _lng),
      const AzkarAndTasbihTab(),
    ];

    return Scaffold(
      body: SafeArea(child: screens[_selectedIndex]),
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          color: Color(0xFF0F1C18),
          border: Border(top: BorderSide(color: Color(0x33D4AF37), width: 1)),
        ),
        child: BottomNavigationBar(
          currentIndex: _selectedIndex,
          onTap: (i) => setState(() => _selectedIndex = i),
          type: BottomNavigationBarType.fixed,
          backgroundColor: const Color(0xFF0F1C18),
          selectedItemColor: const Color(0xFFD4AF37),
          unselectedItemColor: Colors.white60,
          selectedFontSize: 12,
          unselectedFontSize: 11,
          items: const [
            BottomNavigationBarItem(icon: Icon(Icons.mosque_rounded), label: "المواقيت والفجر"),
            BottomNavigationBarItem(icon: Icon(Icons.menu_book_rounded), label: "المصحف الشريف"),
            BottomNavigationBarItem(icon: Icon(Icons.explore_rounded), label: "القبلة"),
            BottomNavigationBarItem(icon: Icon(Icons.volunteer_activism_rounded), label: "الأذكار والسبحة"),
          ],
        ),
      ),
    );
  }

  Widget _buildHomeAndPrayersTab() {
    final pt = _prayerTimes;
    final fmt = DateFormat('hh:mm a', 'ar');

    final prayersList = pt == null
        ? []
        : [
            {"name": "الفجر", "time": fmt.format(pt.fajr), "icon": Icons.nights_stay_rounded, "isNext": _nextPrayerName == "الفجر"},
            {"name": "الشروق", "time": fmt.format(pt.sunrise), "icon": Icons.wb_twilight_rounded, "isNext": _nextPrayerName == "الشروق"},
            {"name": "الظهر", "time": fmt.format(pt.dhuhr), "icon": Icons.wb_sunny_rounded, "isNext": _nextPrayerName == "الظهر"},
            {"name": "العصر", "time": fmt.format(pt.asr), "icon": Icons.sunny_snowing, "isNext": _nextPrayerName == "العصر"},
            {"name": "المغرب", "time": fmt.format(pt.maghrib), "icon": Icons.brightness_4_rounded, "isNext": _nextPrayerName == "المغرب"},
            {"name": "العشاء", "time": fmt.format(pt.isha), "icon": Icons.bedtime_rounded, "isNext": _nextPrayerName == "العشاء"},
          ];

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text("طريق الجنة", style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Color(0xFFD4AF37))),
                  Row(
                    children: [
                      const Icon(Icons.location_on, size: 14, color: Color(0xFF10B981)),
                      const SizedBox(width: 4),
                      Text(_cityName, style: const TextStyle(fontSize: 12, color: Colors.white70)),
                    ],
                  ),
                ],
              ),
              IconButton(
                onPressed: _determinePosition,
                icon: const Icon(Icons.my_location_rounded, color: Color(0xFFD4AF37)),
                tooltip: "تحديث الموقع",
              ),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF14362B), Color(0xFF0C201A)],
                begin: Alignment.topRight,
                end: Alignment.bottomLeft,
              ),
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: const Color(0x66D4AF37)),
              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.4), blurRadius: 12, offset: const Offset(0, 6))],
            ),
            child: Column(
              children: [
                Text("الصلاة القادمة: $_nextPrayerName", style: const TextStyle(fontSize: 16, color: Colors.white70)),
                const SizedBox(height: 6),
                Text(
                  _formatDuration(_remainingTime),
                  style: const TextStyle(fontSize: 36, fontWeight: FontWeight.bold, color: Color(0xFFD4AF37), letterSpacing: 2),
                ),
                const SizedBox(height: 12),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _isAdhanPlaying ? Colors.redAccent : const Color(0xFFD4AF37),
                    foregroundColor: _isAdhanPlaying ? Colors.white : Colors.black,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  onPressed: _toggleAdhan,
                  icon: Icon(_isAdhanPlaying ? Icons.stop_rounded : Icons.volume_up_rounded),
                  label: Text(_isAdhanPlaying ? "إيقاف صوت الأذان" : "تشغيل / تجربة صوت الأذان", style: const TextStyle(fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          ...prayersList.map((p) {
            final bool isNext = p["isNext"] as bool;
            return Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
              decoration: BoxDecoration(
                color: isNext ? const Color(0xFF1A3A30) : const Color(0xFF12211D),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: isNext ? const Color(0xFFD4AF37) : Colors.white10, width: isNext ? 1.5 : 1),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Icon(p["icon"] as IconData, color: isNext ? const Color(0xFFD4AF37) : const Color(0xFF10B981)),
                      const SizedBox(width: 12),
                      Text(
                        p["name"] as String,
                        style: TextStyle(fontSize: 16, fontWeight: isNext ? FontWeight.bold : FontWeight.w500, color: isNext ? const Color(0xFFD4AF37) : Colors.white),
                      ),
                    ],
                  ),
                  Text(
                    p["time"] as String,
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: isNext ? const Color(0xFFD4AF37) : Colors.white),
                  ),
                ],
              ),
            );
          }),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF12211D),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: const Color(0x44D4AF37)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.alarm_on_rounded, color: Color(0xFFD4AF37)),
                    SizedBox(width: 8),
                    Text("منبه صلاة الفجر بصوتك الخاص", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFFD4AF37))),
                  ],
                ),
                const SizedBox(height: 8),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text("تفعيل منبه الفجر الذكي", style: TextStyle(fontSize: 14)),
                  subtitle: Text(
                    _customFajrAudioPath != null ? "النغمة: صوتك المسجل / ملف مخصص ✅" : "النغمة: صوت المؤذن الافتراضي",
                    style: const TextStyle(fontSize: 12, color: Color(0xFF10B981)),
                  ),
                  value: _fajrAlarmEnabled,
                  activeColor: const Color(0xFFD4AF37),
                  onChanged: (v) async {
                    final prefs = await SharedPreferences.getInstance();
                    await prefs.setBool('fajr_alarm_enabled', v);
                    setState(() => _fajrAlarmEnabled = v);
                  },
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _isRecordingFajr ? Colors.red : const Color(0xFF10B981),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        onPressed: _toggleRecordFajrVoice,
                        icon: Icon(_isRecordingFajr ? Icons.stop_circle : Icons.mic_rounded),
                        label: Text(_isRecordingFajr ? "إيقاف وحفظ التسجيل" : "سجّل صوتك الآن", style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold)),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFFD4AF37),
                          side: const BorderSide(color: Color(0xFFD4AF37)),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        onPressed: _pickAudioFileForFajr,
                        icon: const Icon(Icons.audio_file_rounded, size: 18),
                        label: const Text("اختر ملف صوتي", style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold)),
                      ),
                    ),
                  ],
                ),
                if (_customFajrAudioPath != null) ...[
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      TextButton.icon(
                        onPressed: _playFajrAlarm,
                        icon: const Icon(Icons.play_arrow_rounded, color: Color(0xFFD4AF37)),
                        label: const Text("تجربة منبه الفجر", style: TextStyle(color: Color(0xFFD4AF37))),
                      ),
                      TextButton.icon(
                        onPressed: () async {
                          final prefs = await SharedPreferences.getInstance();
                          await prefs.remove('custom_fajr_path');
                          setState(() => _customFajrAudioPath = null);
                        },
                        icon: const Icon(Icons.delete_outline, color: Colors.redAccent, size: 18),
                        label: const Text("حذف الصوت المخصص", style: TextStyle(color: Colors.redAccent, fontSize: 12)),
                      ),
                    ],
                  ),
                ],
                const Divider(color: Colors.white12, height: 24),
                const Text("اختيار صوت المؤذن للصلوات:", style: TextStyle(fontSize: 13, color: Colors.white70)),
                const SizedBox(height: 6),
                DropdownButtonFormField<String>(
                  value: _selectedMuezzin,
                  dropdownColor: const Color(0xFF12211D),
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: const Color(0xFF0A1210),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                  ),
                  items: _muezzinUrls.keys.map((m) => DropdownMenuItem(value: m, child: Text(m))).toList(),
                  onChanged: (val) async {
                    if (val == null) return;
                    final prefs = await SharedPreferences.getInstance();
                    await prefs.setString('muezzin', val);
                    setState(() => _selectedMuezzin = val);
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class QiblaCompassTab extends StatelessWidget {
  final double lat;
  final double lng;

  const QiblaCompassTab({super.key, required this.lat, required this.lng});

  double _calculateQiblaAngle(double userLat, double userLng) {
    const double kaabaLat = 21.422487 * math.pi / 180.0;
    const double kaabaLng = 39.826206 * math.pi / 180.0;
    final double uLat = userLat * math.pi / 180.0;
    final double uLng = userLng * math.pi / 180.0;

    final double dLng = kaabaLng - uLng;
    final double y = math.sin(dLng) * math.cos(kaabaLat);
    final double x = math.cos(uLat) * math.sin(kaabaLat) - math.sin(uLat) * math.cos(kaabaLat) * math.cos(dLng);
    final double bearing = math.atan2(y, x) * 180.0 / math.pi;
    return (bearing + 360.0) % 360.0;
  }

  @override
  Widget build(BuildContext context) {
    final qiblaAngle = _calculateQiblaAngle(lat, lng);

    return StreamBuilder<CompassEvent>(
      stream: FlutterCompass.events,
      builder: (context, snapshot) {
        final double heading = snapshot.data?.heading ?? 0.0;
        final double needleRotation = (qiblaAngle - heading) * (math.pi / 180);
        final bool isAligned = (qiblaAngle - (heading % 360)).abs() < 5;

        return Center(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text("اتجاه القبلة المشرفة", style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Color(0xFFD4AF37))),
                const SizedBox(height: 8),
                Text(
                  isAligned ? "🕋 أنت الآن في اتجاه القبلة تماماً" : "قم بتدوير الهاتف حتى يشير السهم للكعبة",
                  style: TextStyle(fontSize: 15, color: isAligned ? const Color(0xFF10B981) : Colors.white70, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 36),
                Container(
                  width: 280,
                  height: 280,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: const Color(0xFF12211D),
                    border: Border.all(color: isAligned ? const Color(0xFF10B981) : const Color(0xFFD4AF37), width: 4),
                    boxShadow: [
                      BoxShadow(
                        color: (isAligned ? const Color(0xFF10B981) : const Color(0xFFD4AF37)).withOpacity(0.25),
                        blurRadius: 24,
                      ),
                    ],
                  ),
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      const Positioned(top: 12, child: Text("N", style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold))),
                      const Positioned(bottom: 12, child: Text("S", style: TextStyle(color: Colors.white54))),
                      const Positioned(right: 14, child: Text("E", style: TextStyle(color: Colors.white54))),
                      const Positioned(left: 14, child: Text("W", style: TextStyle(color: Colors.white54))),
                      Transform.rotate(
                        angle: needleRotation,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.mosque_rounded, size: 38, color: Color(0xFFD4AF37)),
                            Container(width: 6, height: 85, decoration: BoxDecoration(color: const Color(0xFFD4AF37), borderRadius: BorderRadius.circular(4))),
                            Container(width: 6, height: 55, decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(4))),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 28),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                  decoration: BoxDecoration(color: const Color(0xFF12211D), borderRadius: BorderRadius.circular(14)),
                  child: Text(
                    "زاوية القبلة: ${qiblaAngle.toStringAsFixed(1)}° | البوصلة: ${heading.toStringAsFixed(0)}°",
                    style: const TextStyle(color: Color(0xFFD4AF37), fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
class QuranCompleteTab extends StatefulWidget {
  const QuranCompleteTab({super.key});

  @override
  State<QuranCompleteTab> createState() => _QuranCompleteTabState();
}

class _QuranCompleteTabState extends State<QuranCompleteTab> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final AudioPlayer _quranPlayer = AudioPlayer();

  List _surahs = [];
  List _filteredSurahs = [];
  bool _isLoadingSurahs = true;

  String _selectedReciter = "ar.alafasy";
  int? _playingSurahNumber;
  String _playingSurahName = "";
  bool _isPlaying = false;
  Duration _duration = Duration.zero;
  Duration _position = Duration.zero;

  int _currentMushafPage = 1;
  final PageController _pageController = PageController();

  final Map _reciters = {
    "ar.alafasy": "مشاري راشد العفاسي",
    "ar.abdulbasitmurattal": "عبد الباسط عبد الصمد",
    "ar.husary": "محمود خليل الحصري",
    "ar.minshawi": "محمد صديق المنشاوي",
    "ar.mahermuaiqly": "ماهر المعيقلي",
  };

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadLastPage();
    _fetchSurahs();
    _setupAudioListeners();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _quranPlayer.dispose();
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _loadLastPage() async {
    final prefs = await SharedPreferences.getInstance();
    final savedPage = prefs.getInt('last_mushaf_page') ?? 1;
    setState(() => _currentMushafPage = savedPage);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_pageController.hasClients) {
        _pageController.jumpToPage(savedPage - 1);
      }
    });
  }

  Future<void> _saveLastPage(int page) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('last_mushaf_page', page);
  }

  void _setupAudioListeners() {
    _quranPlayer.onDurationChanged.listen((d) {
      if (mounted) setState(() => _duration = d);
    });
    _quranPlayer.onPositionChanged.listen((p) {
      if (mounted) setState(() => _position = p);
    });
    _quranPlayer.onPlayerComplete.listen((_) {
      if (mounted) {
        setState(() {
          _isPlaying = false;
          _position = Duration.zero;
        });
      }
    });
  }

  Future<void> _fetchSurahs() async {
    try {
      final res = await http.get(Uri.parse('https://api.alquran.cloud/v1/surah')).timeout(const Duration(seconds: 15));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        setState(() {
          _surahs = data['data'];
          _filteredSurahs = _surahs;
          _isLoadingSurahs = false;
        });
      }
    } catch (_) {
      setState(() => _isLoadingSurahs = false);
    }
  }

  void _filterSurahs(String query) {
    setState(() {
      _filteredSurahs = _surahs.where((s) {
        final name = s['name'].toString();
        final numStr = s['number'].toString();
        return name.contains(query) || numStr == query;
      }).toList();
    });
  }

  Future<void> _playSurahAudio(int surahNumber, String surahName) async {
    if (_playingSurahNumber == surahNumber && _isPlaying) {
      await _quranPlayer.pause();
      setState(() => _isPlaying = false);
      return;
    }

    final url = "https://cdn.islamic.network/quran/audio-surah/128/$_selectedReciter/$surahNumber.mp3";
    setState(() {
      _playingSurahNumber = surahNumber;
      _playingSurahName = surahName;
      _isPlaying = true;
    });
    await _quranPlayer.play(UrlSource(url));
  }

  void _openSurahTextSheet(int surahNumber, String surahName) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF0A1210),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.88,
        maxChildSize: 0.95,
        minChildSize: 0.5,
        expand: false,
        builder: (_, scrollCtrl) => SurahReaderView(
          surahNumber: surahNumber,
          surahName: surahName,
          scrollController: scrollCtrl,
          onPlayAudio: () => _playSurahAudio(surahNumber, surahName),
        ),
      ),
    );
  }

  void _showJumpToPageDialog() {
    final ctrl = TextEditingController(text: _currentMushafPage.toString());
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF12211D),
        title: const Text("الانتقال إلى صفحة", style: TextStyle(color: Color(0xFFD4AF37))),
        content: TextField(
          controller: ctrl,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(hintText: "أدخل رقم الصفحة (1 - 604)"),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("إلغاء")),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFD4AF37), foregroundColor: Colors.black),
            onPressed: () {
              final p = int.tryParse(ctrl.text) ?? 1;
              final validPage = p.clamp(1, 604);
              _pageController.jumpToPage(validPage - 1);
              Navigator.pop(ctx);
            },
            child: const Text("انتقال", style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          color: const Color(0xFF0F1C18),
          child: TabBar(
            controller: _tabController,
            indicatorColor: const Color(0xFFD4AF37),
            labelColor: const Color(0xFFD4AF37),
            unselectedLabelColor: Colors.white60,
            tabs: const [
              Tab(icon: Icon(Icons.auto_stories_rounded), text: "المصحف المصور (604)"),
              Tab(icon: Icon(Icons.headphones_rounded), text: "السور والتلاوات (114)"),
            ],
          ),
        ),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            physics: const NeverScrollableScrollPhysics(),
            children: [
              _buildMushafImagesView(),
              _buildSurahsListView(),
            ],
          ),
        ),
        if (_playingSurahNumber != null)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: const BoxDecoration(
              color: Color(0xFF14362B),
              border: Border(top: BorderSide(color: Color(0xFFD4AF37), width: 1)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    IconButton(
                      icon: Icon(_isPlaying ? Icons.pause_circle_filled : Icons.play_circle_fill, color: const Color(0xFFD4AF37), size: 34),
                      onPressed: () => _playSurahAudio(_playingSurahNumber!, _playingSurahName),
                    ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(_playingSurahName, style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFFD4AF37))),
                          Text(_reciters[_selectedReciter]?.toString() ?? "", style: const TextStyle(fontSize: 11, color: Colors.white70)),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.white60),
                      onPressed: () async {
                        await _quranPlayer.stop();
                        setState(() {
                          _playingSurahNumber = null;
                          _isPlaying = false;
                        });
                      },
                    ),
                  ],
                ),
                SliderTheme(
                  data: SliderTheme.of(context).copyWith(thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6), trackHeight: 2),
                  child: Slider(
                    activeColor: const Color(0xFFD4AF37),
                    inactiveColor: Colors.white24,
                    value: _position.inSeconds.toDouble().clamp(0, _duration.inSeconds.toDouble() > 0 ? _duration.inSeconds.toDouble() : 1),
                    max: _duration.inSeconds.toDouble() > 0 ? _duration.inSeconds.toDouble() : 1,
                    onChanged: (val) => _quranPlayer.seek(Duration(seconds: val.toInt())),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildMushafImagesView() {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          color: const Color(0xFF12211D),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text("صفحة $_currentMushafPage من 604", style: const TextStyle(color: Color(0xFFD4AF37), fontWeight: FontWeight.bold)),
              TextButton.icon(
                onPressed: _showJumpToPageDialog,
                icon: const Icon(Icons.find_in_page_rounded, size: 18, color: Color(0xFF10B981)),
                label: const Text("انتقال لصفحة", style: TextStyle(color: Color(0xFF10B981), fontSize: 12)),
              ),
            ],
          ),
        ),
        Expanded(
          child: PageView.builder(
            controller: _pageController,
            reverse: false,
            itemCount: 604,
            onPageChanged: (index) {
              setState(() => _currentMushafPage = index + 1);
              _saveLastPage(index + 1);
            },
            itemBuilder: (context, index) {
              final pageNum = (index + 1).toString().padLeft(3, '0');
              final imageUrl = "https://android.quran.com/data/width_1024/page$pageNum.png";

              return Container(
                color: const Color(0xFFFDF8E8),
                child: InteractiveViewer(
                  minScale: 1.0,
                  maxScale: 3.0,
                  child: Image.network(
                    imageUrl,
                    fit: BoxFit.contain,
                    loadingBuilder: (context, child, progress) {
                      if (progress == null) return child;
                      return const Center(child: CircularProgressIndicator(color: Color(0xFFD4AF37)));
                    },
                    errorBuilder: (_, __, ___) => const Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.wifi_off_rounded, size: 42, color: Colors.black54),
                          SizedBox(height: 8),
                          Text("يرجى الاتصال بالإنترنت لتحميل صفحة المصحف", style: TextStyle(color: Colors.black87)),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildSurahsListView() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            children: [
              DropdownButtonFormField<String>(
                value: _selectedReciter,
                dropdownColor: const Color(0xFF12211D),
                decoration: InputDecoration(
                  labelText: "اختر القارئ",
                  labelStyle: const TextStyle(color: Color(0xFFD4AF37)),
                  filled: true,
                  fillColor: const Color(0xFF12211D),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                ),
                items: _reciters.entries.map((e) => DropdownMenuItem<String>(value: e.key.toString(), child: Text(e.value.toString()))).toList(),
                onChanged: (val) {
                  if (val != null) setState(() => _selectedReciter = val);
                },
              ),
              const SizedBox(height: 8),
              TextField(
                onChanged: _filterSurahs,
                decoration: InputDecoration(
                  hintText: "ابحث باسم السورة أو رقمها...",
                  prefixIcon: const Icon(Icons.search, color: Color(0xFFD4AF37)),
                  filled: true,
                  fillColor: const Color(0xFF12211D),
                  contentPadding: const EdgeInsets.symmetric(vertical: 0),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: _isLoadingSurahs
              ? const Center(child: CircularProgressIndicator(color: Color(0xFFD4AF37)))
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  itemCount: _filteredSurahs.length,
                  itemBuilder: (context, i) {
                    final s = _filteredSurahs[i];
                    final int num = s['number'];
                    final String name = s['name'];
                    final int ayahs = s['numberOfAyahs'];
                    final String type = s['revelationType'] == 'Meccan' ? 'مكية' : 'مدنية';
                    final bool isThisPlaying = _playingSurahNumber == num && _isPlaying;

                    return Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      decoration: BoxDecoration(
                        color: const Color(0xFF12211D),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: isThisPlaying ? const Color(0xFFD4AF37) : Colors.white10),
                      ),
                      child: ListTile(
                        onTap: () => _openSurahTextSheet(num, name),
                        leading: CircleAvatar(
                          backgroundColor: const Color(0xFF1A3A30),
                          child: Text("$num", style: const TextStyle(color: Color(0xFFD4AF37), fontWeight: FontWeight.bold, fontSize: 13)),
                        ),
                        title: Text(name, style: GoogleFonts.amiri(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white)),
                        subtitle: Text("$type • $ayahs آية", style: const TextStyle(fontSize: 12, color: Colors.white60)),
                        trailing: IconButton(
                          icon: Icon(
                            isThisPlaying ? Icons.pause_circle_filled : Icons.play_circle_outline_rounded,
                            color: const Color(0xFFD4AF37),
                            size: 32,
                          ),
                          onPressed: () => _playSurahAudio(num, name),
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class SurahReaderView extends StatefulWidget {
  final int surahNumber;
  final String surahName;
  final ScrollController scrollController;
  final VoidCallback onPlayAudio;

  const SurahReaderView({
    super.key,
    required this.surahNumber,
    required this.surahName,
    required this.scrollController,
    required this.onPlayAudio,
  });

  @override
  State<SurahReaderView> createState() => _SurahReaderViewState();
}

class _SurahReaderViewState extends State<SurahReaderView> {
  List _ayahs = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadAyahs();
  }

  Future<void> _loadAyahs() async {
    try {
      final res = await http.get(Uri.parse('https://api.alquran.cloud/v1/surah/${widget.surahNumber}/quran-uthmani'));
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

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(widget.surahName, style: GoogleFonts.amiri(fontSize: 24, fontWeight: FontWeight.bold, color: const Color(0xFFD4AF37))),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFD4AF37), foregroundColor: Colors.black),
                onPressed: widget.onPlayAudio,
                icon: const Icon(Icons.volume_up_rounded),
                label: const Text("استماع للسورة", style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        ),
        const Divider(color: Colors.white12, height: 1),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator(color: Color(0xFFD4AF37)))
              : ListView(
                  controller: widget.scrollController,
                  padding: const EdgeInsets.all(18),
                  children: [
                    if (widget.surahNumber != 1 && widget.surahNumber != 9)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 16),
                        child: Text(
                          "بِسْمِ اللَّهِ الرَّحْمَٰنِ الرَّحِيمِ",
                          textAlign: TextAlign.center,
                          style: GoogleFonts.amiri(fontSize: 24, color: const Color(0xFF10B981), fontWeight: FontWeight.bold),
                        ),
                      ),
                    RichText(
                      textAlign: TextAlign.justify,
                      text: TextSpan(
                        style: GoogleFonts.amiri(fontSize: 24, height: 2.1, color: Colors.white),
                        children: _ayahs.map<TextSpan>((a) {
                          String txt = a['text'].toString();
                          if (widget.surahNumber != 1 && a['numberInSurah'] == 1) {
                            txt = txt.replaceFirst("بِسْمِ ٱللَّهِ ٱلرَّحْمَٰنِ ٱلرَّحِيمِ", "").trim();
                          }
                          return TextSpan(text: "$txt ﴿${a['numberInSurah']}﴾ ");
                        }).toList(),
                      ),
                    ),
                  ],
                ),
        ),
      ],
    );
  }
}

class AzkarAndTasbihTab extends StatefulWidget {
  const AzkarAndTasbihTab({super.key});

  @override
  State<AzkarAndTasbihTab> createState() => _AzkarAndTasbihTabState();
}

class _AzkarAndTasbihTabState extends State<AzkarAndTasbihTab> {
  int _tasbihCount = 0;
  int _totalTasbih = 0;
  String _selectedZikr = "سبحان الله وبحمده";

  final List _tasbihPhrases = [
    "سبحان الله وبحمده",
    "أستغفر الله العظيم وأتوب إليه",
    "اللهم صلِّ وسلم على نبينا محمد",
    "لا إله إلا الله وحده لا شريك له",
    "لا حول ولا قوة إلا بالله",
  ];

  final List _dailyAzkar = [
    {"title": "أذكار الصباح", "text": "أصبحنا وأصبح الملك لله، والحمد لله، لا إله إلا الله وحده لا شريك له، له الملك وله الحمد وهو على كل شيء قدير."},
    {"title": "أذكار المساء", "text": "أمسينا وأمسى الملك لله، والحمد لله، لا إله إلا الله وحده لا شريك له، له الملك وله الحمد وهو على كل شيء قدير."},
    {"title": "سيد الاستغفار", "text": "اللهم أنت ربي لا إله إلا أنت، خلقتني وأنا عبدك، وأنا على عهدك ووعدك ما استطعت، أعوذ بك من شر ما صنعت."},
    {"title": "أذكار النوم", "text": "باسمك ربي وضعت جنبي وبك أرفعه، فإن أمسكت نفسي فارحمها، وإن أرسلتها فاحفظها بما تحفظ به عبادك الصالحين."},
  ];

  @override
  void initState() {
    super.initState();
    _loadTotal();
  }

  Future<void> _loadTotal() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() => _totalTasbih = prefs.getInt('total_tasbih') ?? 0);
  }

  Future<void> _incrementTasbih() async {
    HapticFeedback.lightImpact();
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _tasbihCount++;
      _totalTasbih++;
    });
    await prefs.setInt('total_tasbih', _totalTasbih);
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text("السبحة الإلكترونية", style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Color(0xFFD4AF37))),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: const Color(0xFF12211D),
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: const Color(0x55D4AF37)),
            ),
            child: Column(
              children: [
                DropdownButtonFormField<String>(
                  value: _selectedZikr,
                  dropdownColor: const Color(0xFF12211D),
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: const Color(0xFF0A1210),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                  ),
                  items: _tasbihPhrases.map((p) => DropdownMenuItem<String>(value: p.toString(), child: Text(p.toString(), style: const TextStyle(fontSize: 13)))).toList(),
                  onChanged: (v) {
                    if (v != null) setState(() => _selectedZikr = v);
                  },
                ),
                const SizedBox(height: 20),
                GestureDetector(
                  onTap: _incrementTasbih,
                  child: Container(
                    width: 150,
                    height: 150,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: const LinearGradient(colors: [Color(0xFFD4AF37), Color(0xFFB38B1D)]),
                      boxShadow: [BoxShadow(color: const Color(0xFFD4AF37).withOpacity(0.35), blurRadius: 20)],
                    ),
                    child: Center(
                      child: Text(
                        "$_tasbihCount",
                        style: const TextStyle(fontSize: 42, fontWeight: FontWeight.bold, color: Colors.black),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text("الإجمالي الكلي: $_totalTasbih", style: const TextStyle(color: Color(0xFF10B981), fontWeight: FontWeight.bold)),
                    TextButton.icon(
                      onPressed: () => setState(() => _tasbihCount = 0),
                      icon: const Icon(Icons.refresh, color: Colors.white70, size: 18),
                      label: const Text("تصفير العداد", style: TextStyle(color: Colors.white70)),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 22),
          const Text("أذكار المسلم اليومية", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xFFD4AF37))),
          const SizedBox(height: 10),
          ..._dailyAzkar.map((z) => Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFF12211D),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.white10),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(z["title"]!.toString(), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF10B981))),
                    const SizedBox(height: 6),
                    Text(z["text"]!.toString(), style: GoogleFonts.amiri(fontSize: 19, height: 1.7, color: Colors.white)),
                  ],
                ),
              )),
        ],
      ),
    );
  }
}
