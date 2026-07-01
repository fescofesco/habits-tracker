import 'dart:convert';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

const defaultScriptUrl =
    'https://script.google.com/macros/s/AKfycby1swd2M1TqpzPSDcCV4aV-rXqDXZ0G3nS8V4lN0YqLGCSSUI00bh1tqUML_NjD9aox/exec';

const habits = <String, String>{
  'eat_before_19': 'Eating before 19:00',
  'up_before_8': 'Get up before 08:00',
  'phone_off_22': 'Shut off phone at 22:00',
  'call_close_one': 'Phone call to a close one / met a friend',
  'journaling': 'Journaling',
  'courage': 'Sich was trauen',
  'board_game': 'Play a board game',
  'sports': 'Sports',
  'contact_oma': 'Called or messaged Oma',
  'contact_mama': 'Called or messaged Mama',
  'contact_ambi': 'Called or messaged Ambi',
  'no_porn': 'No Prn',
  'shaved': 'Shaved',
  'lights_off_2245': 'Bedtime: lights off by 22:45',
  'cleaned_kitchen': 'Cleaned kitchen',
  'cleaned_table': 'Cleaned table',
  'cleaned_floor': 'Cleaned floor',
};
const uncleHabits = <String, String>{
  'uncle_exercise': 'Exercise',
  'uncle_call_meet_loved_one': 'Call / meet a loved one',
};
const repeatable = <String, String>{
  'reading': 'Reading',
  'pushups_10': 'Sets of 10 pushups',
  'got_her_number': 'Got her number',
  'stranger_conversation': 'Conversation with a stranger',
  'housework': 'Housework',
  'stretching': 'Stretching',
  'walking': 'Walk around',
};
const periodic = <String, (String, int)>{
  'contact_oma': ('Contact Oma', 14),
  'contact_mama': ('Contact Mama', 14),
  'contact_ambi': ('Contact Ambi', 14),
  'shaved': ('Shaving', 3),
};

final notifications = FlutterLocalNotificationsPlugin();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  tz.initializeTimeZones();
  try {
    tz.setLocalLocation(
      tz.getLocation((await FlutterTimezone.getLocalTimezone()).identifier),
    );
  } catch (_) {}
  await notifications.initialize(
    settings: const InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      iOS: DarwinInitializationSettings(),
    ),
  );
  runApp(const HabitsApp());
}

class HabitsApp extends StatelessWidget {
  const HabitsApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    title: 'Streak Tracker',
    theme: ThemeData(
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xff6842a0)),
      useMaterial3: true,
    ),
    home: const TrackerPage(),
  );
}

class TrackerPage extends StatefulWidget {
  const TrackerPage({super.key});
  @override
  State<TrackerPage> createState() => _TrackerPageState();
}

class _TrackerPageState extends State<TrackerPage> {
  SharedPreferences? prefs;
  final checks = <String, bool>{};
  final counts = <String, int>{};
  final controllers = <String, TextEditingController>{};
  final speech = SpeechToText();
  String today = DateFormat('yyyy-MM-dd').format(DateTime.now());
  String? appMode;
  String birthdayMessage = '';
  bool birthdayVisible = false;
  bool birthdayDone = false;
  String status = '';
  List<Map<String, dynamic>> books = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final c in controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  TextEditingController control(String key) =>
      controllers.putIfAbsent(key, TextEditingController.new);

  Future<void> _load() async {
    final p = await SharedPreferences.getInstance();
    prefs = p;
    appMode = p.getString('app_mode');
    if (!p.containsKey('tracking_started_at')) {
      await p.setInt(
        'tracking_started_at',
        DateTime.now().millisecondsSinceEpoch,
      );
    }
    for (final key in habits.keys) {
      checks[key] = p.getBool('$today:$key') ?? false;
    }
    for (final key in uncleHabits.keys) {
      checks[key] = p.getBool('$today:$key') ?? false;
    }
    for (final key in repeatable.keys) {
      counts[key] = p.getInt('$today:$key') ?? 0;
    }
    for (final key in [
      'close_one_comment',
      'stranger_comment',
      'courage_comment',
      'board_game_comment',
      'sports_comment',
      'birthday_comment',
      'uncle_exercise_comment',
    ]) {
      control(key).text = p.getString('$today:$key') ?? '';
    }
    control('script_url').text = p.getString('script_url') ?? defaultScriptUrl;
    birthdayDone = p.getBool('$today:birthday_done') ?? false;
    try {
      books = (jsonDecode(p.getString('finished_books') ?? '[]') as List)
          .cast<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    } catch (_) {}
    await _scheduleReminders();
    if (mounted) setState(() {});
    await _checkBirthdays();
  }

  Future<void> _save() async {
    final p = prefs;
    if (p == null) return;
    for (final e in checks.entries) {
      await p.setBool('$today:${e.key}', e.value);
    }
    for (final e in counts.entries) {
      await p.setInt('$today:${e.key}', e.value);
    }
    for (final e in controllers.entries.where((e) => e.key != 'script_url')) {
      await p.setString('$today:${e.key}', e.value.text);
    }
    await p.setString('script_url', control('script_url').text.trim());
    await p.setBool('$today:birthday_done', birthdayDone);
  }

  (int, int) _streaks() {
    final days = <DateTime>{};
    for (final key in prefs?.getKeys() ?? <String>{}) {
      if (!RegExp(r'^\d{4}-\d{2}-\d{2}:').hasMatch(key)) continue;
      final value = prefs!.get(key);
      if (value == true || (value is int && value > 0)) {
        days.add(DateTime.parse(key.substring(0, 10)));
      }
    }
    var cursor = DateTime.now();
    cursor = DateTime(cursor.year, cursor.month, cursor.day);
    if (!days.contains(cursor)) {
      cursor = cursor.subtract(const Duration(days: 1));
    }
    var current = 0;
    while (days.contains(cursor)) {
      current++;
      cursor = cursor.subtract(const Duration(days: 1));
    }
    final sorted = days.toList()..sort();
    var best = 0, run = 0;
    DateTime? prev;
    for (final d in sorted) {
      run = prev != null && d.difference(prev).inDays == 1 ? run + 1 : 1;
      if (run > best) best = run;
      prev = d;
    }
    return (current, best);
  }

  Map<String, String> get activeHabits =>
      appMode == 'uncle' ? uncleHabits : habits;
  int get done =>
      activeHabits.keys.where((key) => checks[key] == true).length +
      (appMode == 'uncle' ? 0 : counts.values.where((v) => v > 0).length) +
      (birthdayVisible && birthdayDone ? 1 : 0);
  int get total =>
      activeHabits.length +
      (appMode == 'uncle' ? 0 : counts.length) +
      (birthdayVisible ? 1 : 0);

  Future<void> _selectMode(String mode) async {
    await prefs!.setString('app_mode', mode);
    setState(() => appMode = mode);
    await _scheduleReminders();
  }

  Future<http.Response> _post(Map<String, dynamic> body) => http.post(
    Uri.parse(control('script_url').text.trim()),
    // text/plain avoids CORS preflight on web; Apps Script reads the body regardless
    headers: {'Content-Type': kIsWeb ? 'text/plain' : 'application/json'},
    body: jsonEncode(body),
  );
  Future<void> _checkBirthdays() async {
    try {
      final data =
          jsonDecode(
                (await _post({'action': 'getBirthdays', 'date': today})).body,
              )
              as Map<String, dynamic>;
      final found = (data['birthdays'] as List?) ?? [];
      if (mounted) {
        setState(() {
          birthdayVisible = found.isNotEmpty;
          birthdayMessage = data['message']?.toString() ?? 'Birthday today';
        });
      }
    } catch (_) {
      if (mounted) setState(() => birthdayVisible = false);
    }
  }

  Map<String, dynamic> _dailyJson() => {
    'action': 'saveDay',
    'date': today,
    'habits': {...checks, ...counts},
    for (final key in [
      'close_one_comment',
      'stranger_comment',
      'courage_comment',
      'board_game_comment',
      'sports_comment',
      'birthday_comment',
      'uncle_exercise_comment',
    ])
      key: control(key).text,
    'birthday_done': birthdayDone,
  };
  Future<void> _sync() async {
    await _save();
    try {
      await _post(_dailyJson());
      setState(() => status = 'Synced to Google Sheets.');
    } catch (e) {
      setState(() => status = 'Sync failed: $e');
    }
  }

  Future<void> _dictate(String key) async {
    if (!await speech.initialize()) return;
    await speech.listen(
      onResult: (r) {
        if (r.finalResult) {
          final c = control(key);
          c.text = '${c.text}${c.text.isEmpty ? '' : '\n'}${r.recognizedWords}';
          _save();
          setState(() {});
        }
      },
    );
  }

  Future<void> _addBook() async {
    final photo = await ImagePicker().pickImage(source: ImageSource.camera);
    if (photo == null) return;
    var guess = '';
    final recognizer = TextRecognizer();
    try {
      guess = (await recognizer.processImage(
        InputImage.fromFilePath(photo.path),
      )).text.split('\n').first;
    } finally {
      await recognizer.close();
    }
    if (!mounted) return;
    final title = TextEditingController(text: guess);
    final author = TextEditingController();
    final pages = TextEditingController();
    final save = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Finished book'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: title,
              decoration: const InputDecoration(labelText: 'Title'),
            ),
            TextField(
              controller: author,
              decoration: const InputDecoration(labelText: 'Author'),
            ),
            TextField(
              controller: pages,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Pages'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (save == true && title.text.trim().isNotEmpty) {
      books.add({
        'title': title.text.trim(),
        'author': author.text.trim(),
        'pages': int.tryParse(pages.text) ?? 0,
        'photoPath': photo.path,
        'finishedDate': today,
      });
      await prefs!.setString('finished_books', jsonEncode(books));
      setState(() {});
    }
  }

  Future<void> _scheduleReminders() async {
    try {
      await notifications
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.requestNotificationsPermission();
      await notifications
          .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin
          >()
          ?.requestPermissions(alert: true, badge: true, sound: true);
      for (final item in [(10, 0, 1000), (17, 30, 1001), (21, 0, 1002)]) {
        var date = tz.TZDateTime(
          tz.local,
          DateTime.now().year,
          DateTime.now().month,
          DateTime.now().day,
          item.$1,
          item.$2,
        );
        if (date.isBefore(tz.TZDateTime.now(tz.local))) {
          date = date.add(const Duration(days: 1));
        }
        await notifications.zonedSchedule(
          id: item.$3,
          title: 'Habits check-in',
          body: _overdueText(),
          scheduledDate: date,
          notificationDetails: const NotificationDetails(
            android: AndroidNotificationDetails(
              'streak_reminders',
              'Streak reminders',
              importance: Importance.high,
            ),
            iOS: DarwinNotificationDetails(),
          ),
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
          matchDateTimeComponents: DateTimeComponents.time,
        );
      }
    } catch (_) {
      // Notification platform channels are unavailable in widget tests.
    }
  }

  String _overdueText() {
    final p = prefs;
    if (p == null) return 'Keep your streak alive.';
    if (appMode == 'uncle') {
      return 'Exercise or connect with someone you love today. Keep your streak alive!';
    }
    final now = DateTime.now().millisecondsSinceEpoch,
        start = p.getInt('tracking_started_at') ?? now;
    final due = <String>[];
    for (final e in periodic.entries) {
      final last = p.getInt('last_done:${e.key}') ?? start;
      final missed = (now - last) ~/ (e.value.$2 * 86400000);
      if (missed > 0) {
        due.add(
          '${e.value.$1}: missed $missed ${missed == 1 ? 'time' : 'times'}',
        );
      }
    }
    return due.isEmpty
        ? 'Open the tracker and give today a little momentum.'
        : due.join(' · ');
  }

  Widget _note(String key, String hint, {bool speechButton = false}) => Padding(
    padding: const EdgeInsets.only(left: 16, bottom: 8),
    child: Row(
      children: [
        Expanded(
          child: TextField(
            controller: control(key),
            onChanged: (_) => _save(),
            decoration: InputDecoration(hintText: hint, isDense: true),
          ),
        ),
        if (speechButton)
          IconButton(
            onPressed: () => _dictate(key),
            icon: const Icon(Icons.mic),
          ),
      ],
    ),
  );
  @override
  Widget build(BuildContext context) {
    final s = _streaks();
    if (prefs != null && appMode == null) {
      return Scaffold(
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Icon(Icons.favorite, size: 72, color: Color(0xffff7043)),
                const SizedBox(height: 20),
                Text(
                  'Choose your tracker',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'You can change this later from the menu.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 28),
                FilledButton.icon(
                  onPressed: () => _selectMode('uncle'),
                  icon: const Icon(Icons.person),
                  label: const Padding(
                    padding: EdgeInsets.all(14),
                    child: Text('Uncle mode · 2 habits'),
                  ),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: () => _selectMode('full'),
                  icon: const Icon(Icons.checklist),
                  label: const Padding(
                    padding: EdgeInsets.all(14),
                    child: Text('Full tracker'),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }
    return Scaffold(
      appBar: AppBar(
        title: Text(appMode == 'uncle' ? 'Uncle Tracker' : 'Streak Tracker'),
        actions: [
          PopupMenuButton<String>(
            onSelected: _selectMode,
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'uncle', child: Text('Uncle mode')),
              PopupMenuItem(value: 'full', child: Text('Full tracker')),
            ],
          ),
        ],
      ),
      body: prefs == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text(
                  '$today · quick mode',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(22),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(22),
                    gradient: const LinearGradient(
                      colors: [Color(0xff4f2a83), Color(0xffff7043)],
                    ),
                  ),
                  child: Text(
                    '🔥 ${s.$1} day streak\n★ Best: ${s.$2} days   ·   Today: $done/$total',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 20,
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                ...activeHabits.entries.expand(
                  (e) => [
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      visualDensity: VisualDensity.compact,
                      title: Text(e.value, style: const TextStyle(fontSize: 15)),
                      subtitle: periodic[e.key] == null
                          ? null
                          : Text(
                              'Do this at least once every ${periodic[e.key]!.$2} days.',
                              style: const TextStyle(fontSize: 12),
                            ),
                      value: checks[e.key] ?? false,
                      onChanged: (v) async {
                        setState(() => checks[e.key] = v ?? false);
                        if (v == true && periodic.containsKey(e.key)) {
                          await prefs!.setInt(
                            'last_done:${e.key}',
                            DateTime.now().millisecondsSinceEpoch,
                          );
                        }
                        await _save();
                      },
                    ),
                    if (e.key == 'uncle_exercise')
                      _note('uncle_exercise_comment', 'What exercise did you do?', speechButton: true),
                    if (e.key == 'call_close_one')
                      _note('close_one_comment', 'Who did you call or meet?'),
                    if (e.key == 'courage')
                      _note('courage_comment', 'What did you dare to do?'),
                    if (e.key == 'board_game')
                      _note('board_game_comment', 'Which board game?'),
                    if (e.key == 'sports')
                      _note('sports_comment', 'What sport or exercise?'),
                  ],
                ),
                if (appMode != 'uncle') const _Heading('Repeatable habits'),
                if (appMode != 'uncle')
                  ...repeatable.entries.map(
                    (e) => ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(e.value),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            onPressed: () {
                              setState(
                                () => counts[e.key] = (counts[e.key]! - 1)
                                    .clamp(0, 999),
                              );
                              _save();
                            },
                            icon: const Icon(Icons.remove_circle_outline),
                          ),
                          Text(
                            '${counts[e.key]}',
                            style: const TextStyle(fontSize: 18),
                          ),
                          IconButton(
                            onPressed: () {
                              setState(
                                () => counts[e.key] = counts[e.key]! + 1,
                              );
                              _save();
                            },
                            icon: const Icon(Icons.add_circle_outline),
                          ),
                        ],
                      ),
                    ),
                  ),
                if (appMode != 'uncle')
                  _note(
                    'stranger_comment',
                    'What happened?',
                    speechButton: true,
                  ),
                if (birthdayVisible) ...[
                  const _Heading('Birthday'),
                  Text('🎂 $birthdayMessage'),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    visualDensity: VisualDensity.compact,
                    title: const Text('Birthday greeting done', style: TextStyle(fontSize: 15)),
                    value: birthdayDone,
                    onChanged: (v) {
                      setState(() => birthdayDone = v ?? false);
                      _save();
                    },
                  ),
                  if (appMode != 'uncle')
                    _note(
                      'birthday_comment',
                      'What did you send?',
                      speechButton: true,
                    ),
                ],
                if (appMode != 'uncle') const _Heading('Finished books'),
                if (appMode != 'uncle')
                  Text(
                    '${books.length} books · ${books.fold<int>(0, (sum, b) => sum + ((b['pages'] as num?)?.toInt() ?? 0))} pages',
                  ),
                if (appMode != 'uncle')
                  ...books.reversed
                      .take(3)
                      .map(
                        (b) => ListTile(
                          title: Text(b['title']),
                          subtitle: Text(b['author'] ?? ''),
                        ),
                      ),
                if (appMode != 'uncle')
                  FilledButton.icon(
                    onPressed: _addBook,
                    icon: const Icon(Icons.camera_alt),
                    label: const Text('Photograph a finished book'),
                  ),
                const _Heading('Sync + reminders'),
                TextField(
                  controller: control('script_url'),
                  onChanged: (_) => _save(),
                  decoration: const InputDecoration(
                    labelText: 'Google Apps Script URL',
                  ),
                ),
                const SizedBox(height: 8),
                FilledButton.icon(
                  onPressed: _sync,
                  icon: const Icon(Icons.sync),
                  label: const Text('Save + sync now'),
                ),
                if (status.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.all(8),
                    child: Text(status),
                  ),
              ],
            ),
    );
  }
}

class _Heading extends StatelessWidget {
  final String text;
  const _Heading(this.text);
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 24, bottom: 6),
    child: Text(
      text,
      style: Theme.of(
        context,
      ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
    ),
  );
}
