import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:adhan/adhan.dart';
import 'package:geolocator/geolocator.dart';
import 'package:intl/intl.dart';
import 'package:http/http.dart' as http;

void main() {
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
        scaffoldBackgroundColor: const Color(0xFF132024),
        primaryColor: const Color(0xFFF2C94C),
        textTheme: GoogleFonts.cairoTextTheme(ThemeData.dark().textTheme),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF132024),
          elevation: 0,
          centerTitle: true,
        ),
      ),
      home: const MainNavigationWrapper(),
    );
  }
}

class MainNavigationWrapper extends StatefulWidget {
  const MainNavigationWrapper({super.key});

  @override
  State<MainNavigationWrapper> createState() => _MainNavigationWrapperState();
}

class _MainNavigationWrapperState extends State<MainNavigationWrapper> {
  int _selectedIndex = 0;

  final List<Widget> _pages = [
    const HomeDashboardScreen(),
    const QuranSurahsScreen(),
    const PrayerTimesScreen(),
    const AzkarScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      drawer: _buildSideDrawer(),
      appBar: AppBar(
        title: const Text('طريق الجنة', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 19)),
        actions: [
          Stack(
            alignment: Alignment.topRight,
            children: [
              IconButton(
                icon: const Icon(Icons.notifications, color: Colors.white),
                onPressed: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('تذكير: حافظ على أذكار الصباح والمساء')),
                  );
                },
              ),
              Container(
                margin: const EdgeInsets.only(top: 8, right: 8),
                padding: const EdgeInsets.all(4),
                decoration: const BoxDecoration(color: Color(0xFFF2994A), shape: BoxShape.circle),
                child: const Text('2', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
              )
            ],
          ),
        ],
      ),
      body: _pages[_selectedIndex],
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex,
        onTap: (index) => setState(() => _selectedIndex = index),
        backgroundColor: const Color(0xFF18272C),
        type: BottomNavigationBarType.fixed,
        selectedItemColor: const Color(0xFFF2C94C),
        unselectedItemColor: Colors.grey,
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.mosque), label: 'الرئيسية'),
          BottomNavigationBarItem(icon: Icon(Icons.menu_book), label: 'المصحف'),
          BottomNavigationBarItem(icon: Icon(Icons.access_time_filled), label: 'الصلاة'),
          BottomNavigationBarItem(icon: Icon(Icons.auto_stories), label: 'الأذكار'),
        ],
      ),
    );
  }

  Widget _buildSideDrawer() {
    return Drawer(
      backgroundColor: const Color(0xFF18272C),
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
          children: [
            Align(
              alignment: Alignment.topLeft,
              child: IconButton(
                icon: const Icon(Icons.close, color: Colors.grey),
                onPressed: () => Navigator.pop(context),
              ),
            ),
            const Icon(Icons.mosque, size: 55, color: Color(0xFFF2C94C)),
            const SizedBox(height: 8),
            const Center(
              child: Text('طريق الجنة', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white)),
            ),
            const Center(
              child: Text('القائمة الرئيسية', style: TextStyle(fontSize: 13, color: Color(0xFF27AE60))),
            ),
            const SizedBox(height: 20),
            _drawerTile('مواعيد صلاة العيد 2026', Icons.calendar_today, const Color(0xFFF2C94C), isHighlighted: true, onTap: () {
              Navigator.pop(context);
              setState(() => _selectedIndex = 2);
            }),
            _drawerTile('القرآن الكريم', Icons.menu_book, const Color(0xFF9B51E0), onTap: () {
              Navigator.pop(context);
              setState(() => _selectedIndex = 1);
            }),
            _drawerTile('أوقات الصلاة والأذان', Icons.access_time_filled, const Color(0xFF27AE60), onTap: () {
              Navigator.pop(context);
              setState(() => _selectedIndex = 2);
            }),
            _drawerTile('السبحة الإلكترونية', Icons.radio_button_checked, const Color(0xFF2F80ED), onTap: () {
              Navigator.pop(context);
              Navigator.push(context, MaterialPageRoute(builder: (_) => const TasbihScreen()));
            }),
            _drawerTile('أفضل الأذكار والأدعية', Icons.auto_stories, const Color(0xFF27AE60), onTap: () {
              Navigator.pop(context);
              setState(() => _selectedIndex = 3);
            }),
          ],
        ),
      ),
    );
  }

  Widget _drawerTile(String title, IconData icon, Color iconColor, {bool isHighlighted = false, required VoidCallback onTap}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      decoration: isHighlighted
          ? BoxDecoration(
              color: const Color(0xFF2B3527),
              borderRadius: BorderRadius.circular(12),
              border: const Border(right: BorderSide(color: Color(0xFFF2C94C), width: 3)),
            )
          : null,
      child: ListTile(
        leading: Icon(icon, color: iconColor),
        title: Text(title, style: const TextStyle(color: Colors.white, fontSize: 15)),
        onTap: onTap,
      ),
    );
  }
}

// 1. الشاشة الرئيسية (Grid مطابقة للصور)
class HomeDashboardScreen extends StatelessWidget {
  const HomeDashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final List> gridItems = [
      {'title': 'السبحة الإلكترونية', 'sub': '', 'icon': Icons.radio_button_checked, 'color': const Color(0xFF2F80ED), 'page': const TasbihScreen()},
      {'title': 'أسئلة دينية', 'sub': 'اختبر معلوماتك', 'icon': Icons.psychology, 'color': const Color(0xFFEB5757), 'page': const QuizScreen()},
      {'title': 'أوقات الصلاة', 'sub': 'حساب فلكي دقيق', 'icon': Icons.access_time_filled, 'color': const Color(0xFF27AE60), 'page': const Scaffold(body: SafeArea(child: PrayerTimesScreen()))},
      {'title': 'القرآن الكريم', 'sub': 'نص معتمد وتفسير', 'icon': Icons.menu_book, 'color': const Color(0xFF9B51E0), 'page': const Scaffold(body: SafeArea(child: QuranSurahsScreen()))},
      {'title': 'أذكار المسلم', 'sub': 'الصباح والمساء', 'icon': Icons.auto_stories, 'color': const Color(0xFF219653), 'page': const Scaffold(body: SafeArea(child: AzkarScreen()))},
      {'title': 'أدعية مختارة', 'sub': 'من الكتاب والسنة', 'icon': Icons.volunteer_activism, 'color': const Color(0xFFF2994A), 'page': const Scaffold(body: SafeArea(child: AzkarScreen()))},
    ];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0),
      child: Column(
        children: [
          Expanded(
            child: GridView.builder(
              itemCount: gridItems.length,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                crossAxisSpacing: 14,
                mainAxisSpacing: 14,
                childAspectRatio: 1.08,
              ),
              itemBuilder: (context, index) {
                final item = gridItems[index];
                return InkWell(
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => item['page'])),
                  borderRadius: BorderRadius.circular(18),
                  child: Container(
                    decoration: BoxDecoration(color: const Color(0xFF1C2C31), borderRadius: BorderRadius.circular(18)),
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(item['icon'], size: 42, color: item['color']),
                        const SizedBox(height: 12),
                        Text(item['title'], textAlign: TextAlign.center, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white)),
                        if (item['sub'].isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(item['sub'], textAlign: TextAlign.center, style: const TextStyle(fontSize: 11, color: Colors.grey)),
                        ]
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 10),
            child: Text('صدقة جارية لكل مسلم ومسلمة', style: TextStyle(color: Colors.grey, fontSize: 13)),
          ),
        ],
      ),
    );
  }
}

// 2. شاشة مواقيت الصلاة والأذان (بدون أخطاء - حساب فلكي محلي)
class PrayerTimesScreen extends StatefulWidget {
  const PrayerTimesScreen({super.key});

  @override
  State<PrayerTimesScreen> createState() => _PrayerTimesScreenState();
}

class _PrayerTimesScreenState extends State<PrayerTimesScreen> {
  PrayerTimes? _prayerTimes;
  String _locationName = 'القاهرة، مصر (الهيئة المصرية للمساحة)';
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _calculatePrayers();
  }

  Future<void> _calculatePrayers() async {
    // إحداثيات افتراضية (القاهرة) وتُحدّث تلقائياً إذا وافق المستخدم على الـ GPS
    double lat = 30.0444;
    double lng = 31.2357;

    try {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.whileInUse || permission == LocationPermission.always) {
        Position pos = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.low);
        lat = pos.latitude;
        lng = pos.longitude;
        _locationName = 'موقعك الحالي (GPS)';
      }
    } catch (_) {}

    final coordinates = Coordinates(lat, lng);
    final params = CalculationMethod.egyptian.getParameters();
    params.madhab = Madhab.shafi;
    final date = DateComponents.from(DateTime.now());

    setState(() {
      _prayerTimes = PrayerTimes(coordinates, date, params);
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading || _prayerTimes == null) {
      return const Center(child: CircularProgressIndicator(color: Color(0xFFF2C94C)));
    }

    final format = DateFormat('hh:mm a', 'ar');
    final next = _prayerTimes!.nextPrayer();
    final prayers = [
      {'name': 'الفجر', 'time': format.format(_prayerTimes!.fajr), 'isNext': next == Prayer.fajr},
      {'name': 'الشروق', 'time': format.format(_prayerTimes!.sunrise), 'isNext': next == Prayer.sunrise},
      {'name': 'الظهر', 'time': format.format(_prayerTimes!.dhuhr), 'isNext': next == Prayer.dhuhr},
      {'name': 'العصر', 'time': format.format(_prayerTimes!.asr), 'isNext': next == Prayer.asr},
      {'name': 'المغرب', 'time': format.format(_prayerTimes!.maghrib), 'isNext': next == Prayer.maghrib},
      {'name': 'العشاء', 'time': format.format(_prayerTimes!.isha), 'isNext': next == Prayer.isha},
    ];

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: const Color(0xFF1C2C31), borderRadius: BorderRadius.circular(16)),
            child: Row(
              children: [
                const Icon(Icons.location_on, color: Color(0xFFF2C94C)),
                const SizedBox(width: 8),
                Expanded(child: Text(_locationName, style: const TextStyle(fontSize: 13))),
                IconButton(icon: const Icon(Icons.refresh, color: Color(0xFF27AE60)), onPressed: _calculatePrayers),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: ListView.builder(
              itemCount: prayers.length,
              itemBuilder: (context, index) {
                final p = prayers[index];
                final isNext = p['isNext'] as bool;
                return Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                  decoration: BoxDecoration(
                    color: isNext ? const Color(0xFF2B3527) : const Color(0xFF1C2C31),
                    borderRadius: BorderRadius.circular(14),
                    border: isNext ? Border.all(color: const Color(0xFFF2C94C), width: 1.5) : null,
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(p['name'] as String, style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: isNext ? const Color(0xFFF2C94C) : Colors.white)),
                      Text(p['time'] as String, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// 3. شاشة السبحة الإلكترونية
class TasbihScreen extends StatefulWidget {
  const TasbihScreen({super.key});

  @override
  State<TasbihScreen> createState() => _TasbihScreenState();
}

class _TasbihScreenState extends State<TasbihScreen> {
  int _count = 0;
  int _zikrIndex = 0;
  final List<String> _azkar = ['سبحان الله', 'الحمد لله', 'لا إله إلا الله', 'الله أكبر', 'أستغفر الله العظيم'];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('السبحة الإلكترونية')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            DropdownButton<int>(
              value: _zikrIndex,
              dropdownColor: const Color(0xFF1C2C31),
              items: List.generate(_azkar.length, (i) => DropdownMenuItem(value: i, child: Text(_azkar[i], style: const TextStyle(fontSize: 18)))),
              onChanged: (val) => setState(() {
                _zikrIndex = val!;
                _count = 0;
              }),
            ),
            const SizedBox(height: 30),
            GestureDetector(
              onTap: () {
                HapticFeedback.lightImpact();
                setState(() => _count++);
              },
              child: Container(
                width: 220,
                height: 220,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFF1C2C31),
                  border: Border.all(color: const Color(0xFFF2C94C), width: 4),
                  boxShadow: [BoxShadow(color: const Color(0xFFF2C94C).withOpacity(0.2), blurRadius: 20)],
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text('$_count', style: const TextStyle(fontSize: 54, fontWeight: FontWeight.bold, color: Color(0xFFF2C94C))),
                    const Text('اضغط للتسبيح', style: TextStyle(color: Colors.grey, fontSize: 13)),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 30),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFEB5757)),
              onPressed: () => setState(() => _count = 0),
              icon: const Icon(Icons.refresh, color: Colors.white),
              label: const Text('تصفير العداد', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }
}

// 4. القرآن الكريم (من API الرسمي المدقق AlQuran Cloud)
class QuranSurahsScreen extends StatefulWidget {
  const QuranSurahsScreen({super.key});

  @override
  State<QuranSurahsScreen> createState() => _QuranSurahsScreenState();
}

class _QuranSurahsScreenState extends State<QuranSurahsScreen> {
  List<dynamic> _surahs = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _fetchSurahs();
  }

  Future<void> _fetchSurahs() async {
    try {
      final res = await http.get(Uri.parse('https://api.alquran.cloud/v1/surah'));
      if (res.statusCode == 200) {
        final data = json.decode(res.body);
        setState(() {
          _surahs = data['data'];
          _loading = false;
        });
      }
    } catch (_) {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator(color: Color(0xFFF2C94C)));
    if (_surahs.isEmpty) return const Center(child: Text('تأكد من الاتصال بالإنترنت لتحميل السور'));

    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: _surahs.length,
      itemBuilder: (context, index) {
        final s = _surahs[index];
        return Card(
          color: const Color(0xFF1C2C31),
          margin: const EdgeInsets.only(bottom: 8),
          child: ListTile(
            leading: CircleAvatar(backgroundColor: const Color(0xFFF2C94C), child: Text('${s['number']}', style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold))),
            title: Text(s['name'], style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            subtitle: Text('عدد الآيات: ${s['numberOfAyahs']}'),
            trailing: const Icon(Icons.arrow_forward_ios, size: 16, color: Colors.grey),
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => SurahDetailScreen(number: s['number'], name: s['name']))),
          ),
        );
      },
    );
  }
}

class SurahDetailScreen extends StatefulWidget {
  final int number;
  final String name;
  const SurahDetailScreen({super.key, required this.number, required this.name});

  @override
  State<SurahDetailScreen> createState() => _SurahDetailScreenState();
}

class _SurahDetailScreenState extends State<SurahDetailScreen> {
  List<dynamic> _ayahs = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadAyahs();
  }

  Future<void> _loadAyahs() async {
    final res = await http.get(Uri.parse('https://api.alquran.cloud/v1/surah/${widget.number}/quran-uthmani'));
    if (res.statusCode == 200) {
      setState(() {
        _ayahs = json.decode(res.body)['data']['ayahs'];
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.name)),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFFF2C94C)))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(18),
              child: Text(
                _ayahs.map((a) => '${a['text']} ﴿${a['numberInSurah']}﴾ ').join(''),
                textAlign: TextAlign.justify,
                style: const TextStyle(fontSize: 23, height: 2.0, color: Colors.white),
              ),
            ),
    );
  }
}

// 5. شاشة الأذكار
class AzkarScreen extends StatelessWidget {
  const AzkarScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final azkarList = [
      {'title': 'سيد الاستغفار', 'text': 'اللَّهُمَّ أَنْتَ رَبِّي لَا إِلَهَ إِلَّا أَنْتَ، خَلَقْتَنِي وَأَنَا عَبْدُكَ، وَأَنَا عَلَى عَهْدِكَ وَوَعْدِكَ مَا اسْتَطَعْتُ...'},
      {'title': 'أذكار الصباح', 'text': 'أَصْبَحْنَا وَأَصْبَحَ الْمُلْكُ لِلَّهِ، وَالْحَمْدُ لِلَّهِ، لَا إِلَهَ إِلَّا اللَّهُ وَحْدَهُ لَا شَرِيكَ لَهُ...'},
      {'title': 'أذكار المساء', 'text': 'أَمْسَيْنَا وَأَمْسَى الْمُلْكُ لِلَّهِ، وَالْحَمْدُ لِلَّهِ، لَا إِلَهَ إِلَّا اللَّهُ وَحْدَهُ لَا شَرِيكَ لَهُ...'},
      {'title': 'دعاء الكرب', 'text': 'لَا إِلَهَ إِلَّا اللَّهُ الْعَظِيمُ الْحَلِيمُ، لَا إِلَهَ إِلَّا اللَّهُ رَبُّ الْعَرْشِ الْعَظِيمِ...'},
    ];

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: azkarList.length,
      itemBuilder: (context, index) => Card(
        color: const Color(0xFF1C2C31),
        margin: const EdgeInsets.only(bottom: 12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(azkarList[index]['title']!, style: const TextStyle(color: Color(0xFFF2C94C), fontSize: 17, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Text(azkarList[index]['text']!, style: const TextStyle(fontSize: 16, height: 1.7)),
            ],
          ),
        ),
      ),
    );
  }
}

// 6. شاشة الأسئلة الدينية
class QuizScreen extends StatefulWidget {
  const QuizScreen({super.key});

  @override
  State<QuizScreen> createState() => _QuizScreenState();
}

class _QuizScreenState extends State<QuizScreen> {
  int _qIndex = 0;
  final List> _questions = [
    {'q': 'ما هي السورة التي تعدل ثلث القرآن؟', 'options': ['الإخلاص', 'الفاتحة', 'الكوثر'], 'ans': 0},
    {'q': 'كم عدد سور القرآن الكريم؟', 'options': ['110', '114', '120'], 'ans': 1},
  ];

  @override
  Widget build(BuildContext context) {
    final current = _questions[_qIndex];
    return Scaffold(
      appBar: AppBar(title: const Text('أسئلة دينية')),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(current['q'], textAlign: TextAlign.center, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 24),
            ...List.generate(3, (i) => Container(
              width: double.infinity,
              margin: const EdgeInsets.only(bottom: 12),
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1C2C31), padding: const EdgeInsets.all(16)),
                onPressed: () {
                  final correct = i == current['ans'];
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    backgroundColor: correct ? Colors.green : Colors.red,
                    content: Text(correct ? 'إجابة صحيحة! أحسنت' : 'إجابة خاطئة، حاول مرة أخرى'),
                  ));
                  if (correct && _qIndex < _questions.length - 1) setState(() => _qIndex++);
                },
                child: Text(current['options'][i], style: const TextStyle(fontSize: 16, color: Colors.white)),
              ),
            )),
          ],
        ),
      ),
    );
  }
}
