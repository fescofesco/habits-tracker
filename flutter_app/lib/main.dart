import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
const pendingSyncKey = 'pending_sync_v1';

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
  'oleovit_allergy': 'Oleovit / allergy medication',
  'delayed_gratification_bored':
      'Successfully delayed gratification when bored',
  'cook_own_meal': 'Cook my own meal',
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
const cookingRecipeKey = 'cooking_recipe';
const cookingPhotoKey = 'cooking_photo_base64';
const recipeSuggestionSourceUrl = 'https://nutritionfacts.org/recipes/';
const recipeSuggestionKey = 'recipe_suggestion';

final notifications = FlutterLocalNotificationsPlugin();
const communicationChannel = MethodChannel('habits_tracker/communication');

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
  String? cookingPhotoBase64;
  Map<String, String>? recipeSuggestion;
  List<Map<String, dynamic>> books = [];
  List<Map<String, dynamic>> delegatedTasks = [];

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
    _loadDayFromPrefs();
    _loadRecipeSuggestionFromPrefs();
    await p.remove('script_url');
    try {
      books = (jsonDecode(p.getString('finished_books') ?? '[]') as List)
          .cast<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    } catch (_) {}
    _loadTasksFromPrefs();
    await _pruneCompletedTaskPhotos();
    for (final task in delegatedTasks.where(
      (task) => task['completed'] != true,
    )) {
      unawaited(_scheduleDelegatedReminder(task));
    }
    await _scheduleReminders();
    if (mounted) setState(() {});
    if (!kIsWeb) {
      unawaited(_syncCommunicationHistory().then((_) => _scheduleReminders()));
    }
    if (appMode != null) {
      try {
        await _flushPending();
        await _pullDay();
        if (appMode != 'uncle') await _pullTasks();
      } catch (_) {
        if (mounted) {
          setState(
            () => status = 'Offline — changes stay safely on this device.',
          );
        }
      }
    }
    await _checkBirthdays();
    if (appMode != 'uncle') {
      unawaited(_fetchRecipeSuggestion());
    }
  }

  void _loadDayFromPrefs() {
    final p = prefs;
    if (p == null) return;
    for (final key in [...habits.keys, ...uncleHabits.keys]) {
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
      cookingRecipeKey,
    ]) {
      control(key).text = p.getString('$today:$key') ?? '';
    }
    cookingPhotoBase64 = p.getString('$today:$cookingPhotoKey');
    birthdayDone = p.getBool('$today:birthday_done') ?? false;
  }

  void _loadRecipeSuggestionFromPrefs() {
    final raw = prefs?.getString('$today:$recipeSuggestionKey');
    if (raw == null || raw.isEmpty) {
      recipeSuggestion = null;
      return;
    }
    try {
      recipeSuggestion = Map<String, String>.from(jsonDecode(raw) as Map);
    } catch (_) {
      recipeSuggestion = null;
    }
  }

  void _loadTasksFromPrefs() {
    try {
      delegatedTasks =
          (jsonDecode(prefs?.getString('delegated_tasks:Felix') ?? '[]')
                  as List)
              .cast<Map>()
              .map((task) => Map<String, dynamic>.from(task))
              .toList();
    } catch (_) {
      delegatedTasks = [];
    }
  }

  Future<void> _save({bool queue = true}) async {
    final p = prefs;
    if (p == null) return;
    for (final e in checks.entries) {
      await p.setBool('$today:${e.key}', e.value);
    }
    for (final e in counts.entries) {
      await p.setInt('$today:${e.key}', e.value);
    }
    for (final e in controllers.entries) {
      await p.setString('$today:${e.key}', e.value.text);
    }
    final cookingPhoto = cookingPhotoBase64;
    if (cookingPhoto == null || cookingPhoto.isEmpty) {
      await p.remove('$today:$cookingPhotoKey');
    } else {
      await p.setString('$today:$cookingPhotoKey', cookingPhoto);
    }
    await p.setBool('$today:birthday_done', birthdayDone);
    if (queue) await _queueCurrentDay();
  }

  Future<void> _syncCommunicationHistory() async {
    if (kIsWeb || prefs == null) return;
    try {
      final result = await communicationChannel
          .invokeMapMethod<String, dynamic>('scan');
      for (final entry
          in result?.entries ?? const <MapEntry<String, dynamic>>[]) {
        final timestamp = (entry.value as num?)?.toInt() ?? 0;
        final previous = prefs!.getInt('last_done:${entry.key}') ?? 0;
        if (timestamp > previous) {
          await prefs!.setInt('last_done:${entry.key}', timestamp);
        }
      }
    } catch (_) {
      // Communication history integration is Android-only and optional.
    }
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
    try {
      await _flushPending();
      await _pullDay();
      if (mode != 'uncle') await _pullTasks();
      if (mode != 'uncle') unawaited(_fetchRecipeSuggestion());
    } catch (_) {
      if (mounted) {
        setState(
          () => status = 'Offline — changes stay safely on this device.',
        );
      }
    }
  }

  bool get _showingToday =>
      today == DateFormat('yyyy-MM-dd').format(DateTime.now());

  Future<void> _switchDay({required bool yesterday}) async {
    await _save();
    final date = DateTime.now().subtract(Duration(days: yesterday ? 1 : 0));
    today = DateFormat('yyyy-MM-dd').format(date);
    birthdayVisible = false;
    _loadDayFromPrefs();
    _loadRecipeSuggestionFromPrefs();
    if (mounted) setState(() {});
    try {
      await _flushPending();
      await _pullDay();
    } catch (_) {
      if (mounted) {
        setState(() => status = 'Offline — editing $today locally.');
      }
    }
    await _checkBirthdays();
    if (appMode != 'uncle') {
      unawaited(_fetchRecipeSuggestion());
    }
  }

  Future<Map<String, dynamic>> _post(Map<String, dynamic> body) async {
    var response = await http
        .post(
          Uri.parse(defaultScriptUrl),
          // text/plain avoids a browser CORS preflight; Apps Script still reads JSON.
          headers: {'Content-Type': kIsWeb ? 'text/plain' : 'application/json'},
          body: jsonEncode(body),
        )
        .timeout(const Duration(seconds: 20));
    if (!kIsWeb &&
        const {301, 302, 303, 307, 308}.contains(response.statusCode)) {
      final location = response.headers['location'];
      if (location == null || location.isEmpty) {
        throw Exception('Server redirect had no destination');
      }
      response = await http
          .get(Uri.parse(location))
          .timeout(const Duration(seconds: 20));
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Server returned HTTP ${response.statusCode}');
    }
    late final Map<String, dynamic> data;
    try {
      data = jsonDecode(response.body) as Map<String, dynamic>;
    } on FormatException {
      throw Exception('Server returned an invalid response instead of JSON');
    }
    if (data['ok'] != true) throw Exception(data['error'] ?? 'Sync rejected');
    return data;
  }

  Future<void> _checkBirthdays() async {
    try {
      final data = await _post({'action': 'getBirthdays', 'date': today});
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
    'person': appMode == 'uncle' ? 'Uncle' : 'Felix',
    'habits': {...checks, ...counts},
    for (final key in [
      'close_one_comment',
      'stranger_comment',
      'courage_comment',
      'board_game_comment',
      'sports_comment',
      'birthday_comment',
      'uncle_exercise_comment',
      cookingRecipeKey,
    ])
      key: control(key).text,
    'birthday_done': birthdayDone,
  };

  String get _person => appMode == 'uncle' ? 'Uncle' : 'Felix';

  Future<void> _queueCurrentDay() async {
    final p = prefs;
    if (p == null || appMode == null) return;
    final pending = _readPending(p);
    pending['$_person:$today'] = _dailyJson();
    await p.setString(pendingSyncKey, jsonEncode(pending));
  }

  Future<void> _saveTasks({bool queue = true}) async {
    final p = prefs;
    if (p == null) return;
    await p.setString('delegated_tasks:Felix', jsonEncode(delegatedTasks));
    if (!queue) return;
    final pending = _readPending(p);
    pending['tasks:Felix'] = {
      'action': 'saveTasks',
      'person': 'Felix',
      'tasks': delegatedTasks
          .map((task) => Map<String, dynamic>.from(task)..remove('photoBase64'))
          .toList(),
    };
    await p.setString(pendingSyncKey, jsonEncode(pending));
  }

  Map<String, dynamic> _readPending(SharedPreferences p) {
    try {
      return Map<String, dynamic>.from(
        jsonDecode(p.getString(pendingSyncKey) ?? '{}') as Map,
      );
    } catch (_) {
      return {};
    }
  }

  Future<int> _flushPending() async {
    final p = prefs;
    if (p == null) return 0;
    final pending = _readPending(p);
    var synced = 0;
    for (final key in pending.keys.toList()) {
      await _post(Map<String, dynamic>.from(pending[key] as Map));
      pending.remove(key);
      synced++;
      await p.setString(pendingSyncKey, jsonEncode(pending));
    }
    return synced;
  }

  Future<void> _pullDay() async {
    final data = await _post({
      'action': 'getDay',
      'date': today,
      'person': _person,
    });
    if (data['found'] != true) return;
    final remoteHabits = Map<String, dynamic>.from(
      data['habits'] as Map? ?? {},
    );
    for (final key in activeHabits.keys) {
      if (remoteHabits.containsKey(key)) {
        checks[key] = remoteHabits[key] == true;
      }
    }
    if (appMode != 'uncle') {
      for (final key in repeatable.keys) {
        final value = remoteHabits[key];
        if (value is num) counts[key] = value.toInt();
      }
    }
    for (final key in [
      'close_one_comment',
      'stranger_comment',
      'courage_comment',
      'board_game_comment',
      'sports_comment',
      'birthday_comment',
      'uncle_exercise_comment',
      cookingRecipeKey,
    ]) {
      if (data.containsKey(key)) {
        control(key).text = data[key]?.toString() ?? '';
      }
    }
    birthdayDone = data['birthday_done'] == true;
    await _save(queue: false);
    if (mounted) setState(() {});
  }

  Future<void> _pullTasks() async {
    final data = await _post({'action': 'getTasks', 'person': 'Felix'});
    if (data['found'] != true) return;
    final localById = {
      for (final task in delegatedTasks) task['id'].toString(): task,
    };
    delegatedTasks = (data['tasks'] as List? ?? const []).cast<Map>().map((
      raw,
    ) {
      final remote = Map<String, dynamic>.from(raw);
      final photo = localById[remote['id'].toString()]?['photoBase64'];
      if (photo != null) remote['photoBase64'] = photo;
      return remote;
    }).toList();
    await _pruneCompletedTaskPhotos();
    await _saveTasks(queue: false);
    if (mounted) setState(() {});
  }

  DateTime _dayStart(DateTime date) =>
      DateTime(date.year, date.month, date.day);

  DateTime get _selectedDate => DateTime.parse(today);

  int get _selectedDayTimestamp =>
      _dayStart(_selectedDate).millisecondsSinceEpoch;

  bool _isBeforeToday(int millis) {
    final date = DateTime.fromMillisecondsSinceEpoch(millis);
    return _dayStart(date).isBefore(_dayStart(DateTime.now()));
  }

  Future<void> _pruneCompletedTaskPhotos() async {
    var changed = false;
    for (final task in delegatedTasks) {
      final completedAt = (task['completedAt'] as num?)?.toInt();
      if (task['completed'] == true &&
          completedAt != null &&
          task.containsKey('photoBase64') &&
          _isBeforeToday(completedAt)) {
        task.remove('photoBase64');
        changed = true;
      }
    }
    if (changed) await _saveTasks(queue: false);
  }

  Future<void> _sync() async {
    await _save();
    try {
      final count = await _flushPending();
      await _pullDay();
      if (appMode != 'uncle') await _pullTasks();
      setState(
        () => status =
            'Synced $count offline ${count == 1 ? 'change' : 'changes'} with Google Sheets.',
      );
    } catch (e) {
      setState(() => status = 'Offline — saved here and queued for sync. ($e)');
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

  Future<void> _takeCookingPhoto() async {
    final photo = await ImagePicker().pickImage(
      source: ImageSource.camera,
      imageQuality: 70,
      maxWidth: 1280,
    );
    if (photo == null) return;
    cookingPhotoBase64 = base64Encode(await photo.readAsBytes());
    await _save();
    if (mounted) setState(() {});
  }

  Future<void> _removeCookingPhoto() async {
    cookingPhotoBase64 = null;
    await _save();
    if (mounted) setState(() {});
  }

  String _decodeHtml(String value) => value
      .replaceAll('&amp;', '&')
      .replaceAll('&#038;', '&')
      .replaceAll('&quot;', '"')
      .replaceAll('&#039;', "'")
      .replaceAll('&apos;', "'")
      .replaceAll('&ndash;', '-')
      .replaceAll('&mdash;', '-')
      .replaceAll('&nbsp;', ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  Future<void> _fetchRecipeSuggestion({bool force = false}) async {
    final p = prefs;
    if (p == null) return;
    if (!force && recipeSuggestion != null) return;
    try {
      final response = await http
          .get(Uri.parse(recipeSuggestionSourceUrl))
          .timeout(const Duration(seconds: 15));
      if (response.statusCode < 200 || response.statusCode >= 300) return;
      final matches = RegExp(
        r'''<a[^>]+href=["'](https://nutritionfacts\.org/recipes/[^"']+)["'][^>]*>(.*?)</a>''',
        caseSensitive: false,
        dotAll: true,
      ).allMatches(response.body);
      final suggestions = <Map<String, String>>[];
      for (final match in matches) {
        final url = match.group(1);
        final rawTitle = match.group(2);
        if (url == null || rawTitle == null) continue;
        final title = _decodeHtml(rawTitle.replaceAll(RegExp(r'<[^>]+>'), ''));
        if (title.isEmpty || suggestions.any((item) => item['url'] == url)) {
          continue;
        }
        suggestions.add({'title': title, 'url': url});
      }
      if (suggestions.isEmpty) return;
      final daySeed = int.tryParse(today.replaceAll('-', '')) ?? 0;
      final suggestion = force
          ? suggestions[Random().nextInt(suggestions.length)]
          : suggestions[daySeed % suggestions.length];
      await p.setString('$today:$recipeSuggestionKey', jsonEncode(suggestion));
      recipeSuggestion = suggestion;
      if (mounted) setState(() {});
      unawaited(_scheduleReminders());
    } catch (_) {
      // Recipe suggestions are a nice-to-have and should never block tracking.
    }
  }

  int _taskNotificationId(Map<String, dynamic> task) =>
      20000 + ((task['id'] as num?)?.toInt() ?? 0) % 1000000000;

  Future<void> _scheduleDelegatedReminder(Map<String, dynamic> task) async {
    if (kIsWeb || task['completed'] == true) return;
    final dueMillis = (task['due'] as num?)?.toInt();
    if (dueMillis == null) return;
    final due = DateTime.fromMillisecondsSinceEpoch(dueMillis);
    if (!due.isAfter(DateTime.now())) return;
    try {
      await notifications.zonedSchedule(
        id: _taskNotificationId(task),
        title: 'Delegated task is due',
        body: task['name']?.toString() ?? 'Open Habits Tracker',
        scheduledDate: tz.TZDateTime.from(due, tz.local),
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails(
            'delegated_tasks',
            'Delegated tasks',
            importance: Importance.high,
          ),
          iOS: DarwinNotificationDetails(),
        ),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      );
    } catch (_) {}
  }

  Future<void> _addDelegatedTask() async {
    final photo = await ImagePicker().pickImage(
      source: ImageSource.camera,
      imageQuality: 70,
      maxWidth: 1280,
    );
    if (photo == null || !mounted) return;

    final name = TextEditingController();
    final accepted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delegate to yourself for later'),
        content: TextField(
          controller: name,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Task name'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Choose reminder'),
          ),
        ],
      ),
    );
    if (accepted != true || name.text.trim().isEmpty || !mounted) return;

    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: now,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: DateTime(now.year + 5),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(now.add(const Duration(hours: 1))),
    );
    if (time == null) return;

    final due = DateTime(
      date.year,
      date.month,
      date.day,
      time.hour,
      time.minute,
    );
    final task = <String, dynamic>{
      'id': DateTime.now().millisecondsSinceEpoch,
      'name': name.text.trim(),
      'created': DateTime.now().millisecondsSinceEpoch,
      'due': due.millisecondsSinceEpoch,
      'completed': false,
      'photoBase64': base64Encode(await photo.readAsBytes()),
    };
    delegatedTasks.add(task);
    await _saveTasks();
    await _scheduleDelegatedReminder(task);
    if (mounted) setState(() {});
  }

  Future<void> _setTaskCompleted(
    Map<String, dynamic> task,
    bool completed,
  ) async {
    task['completed'] = completed;
    task['completedAt'] = completed ? _selectedDayTimestamp : null;
    if (completed) {
      await notifications.cancel(id: _taskNotificationId(task));
    } else {
      await _scheduleDelegatedReminder(task);
    }
    await _saveTasks();
    if (mounted) setState(() {});
  }

  Widget _taskPhoto(Map<String, dynamic> task) {
    try {
      final encoded = task['photoBase64']?.toString();
      if (encoded == null || encoded.isEmpty) {
        return const Icon(Icons.image_not_supported);
      }
      return ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Image.memory(
          base64Decode(encoded),
          width: 64,
          height: 64,
          fit: BoxFit.cover,
        ),
      );
    } catch (_) {
      return const Icon(Icons.image_not_supported);
    }
  }

  Widget _cookingPhotoPreview() {
    final encoded = cookingPhotoBase64;
    if (encoded == null || encoded.isEmpty) {
      return OutlinedButton.icon(
        onPressed: _takeCookingPhoto,
        icon: const Icon(Icons.add_a_photo),
        label: const Text('Add cooking photo'),
      );
    }
    try {
      return Padding(
        padding: const EdgeInsets.only(left: 16, bottom: 8),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.memory(
                base64Decode(encoded),
                width: 72,
                height: 72,
                fit: BoxFit.cover,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(
                    onPressed: _takeCookingPhoto,
                    icon: const Icon(Icons.camera_alt),
                    label: const Text('Replace photo'),
                  ),
                  TextButton.icon(
                    onPressed: _removeCookingPhoto,
                    icon: const Icon(Icons.delete_outline),
                    label: const Text('Remove'),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    } catch (_) {
      return TextButton.icon(
        onPressed: _removeCookingPhoto,
        icon: const Icon(Icons.broken_image),
        label: const Text('Remove broken cooking photo'),
      );
    }
  }

  Widget _recipeSuggestionCard() {
    final suggestion = recipeSuggestion;
    return Padding(
      padding: const EdgeInsets.only(left: 16, bottom: 8),
      child: Card(
        child: ListTile(
          leading: const Icon(Icons.restaurant_menu),
          title: Text(suggestion?['title'] ?? 'Dr. Greger recipe suggestion'),
          subtitle: Text(
            suggestion == null
                ? 'Tap refresh to download today\'s idea.'
                : suggestion['url'] ?? recipeSuggestionSourceUrl,
          ),
          trailing: IconButton(
            tooltip: 'Refresh suggestion',
            onPressed: () => _fetchRecipeSuggestion(force: true),
            icon: const Icon(Icons.refresh),
          ),
          onTap: suggestion == null
              ? () => _fetchRecipeSuggestion(force: true)
              : () {
                  final url = suggestion['url'] ?? recipeSuggestionSourceUrl;
                  Clipboard.setData(ClipboardData(text: url));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Recipe link copied to clipboard'),
                    ),
                  );
                },
        ),
      ),
    );
  }

  void _showHabitEvaluation() {
    final completedHabits = activeHabits.entries
        .where((entry) => checks[entry.key] == true)
        .map((entry) => entry.value)
        .toList();
    final missedHabits = activeHabits.entries
        .where((entry) => checks[entry.key] != true)
        .map((entry) => entry.value)
        .toList();
    final repeatableTotal = appMode == 'uncle'
        ? 0
        : counts.values.fold<int>(0, (sum, value) => sum + value);
    final recipe = control(cookingRecipeKey).text.trim();

    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Habit evaluation for $today'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Score: $done/$total'),
              if (appMode != 'uncle')
                Text('Repeatable actions logged: $repeatableTotal'),
              if (completedHabits.isNotEmpty) ...[
                const SizedBox(height: 12),
                const Text(
                  'Done',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                Text(completedHabits.join('\n')),
              ],
              if (missedHabits.isNotEmpty) ...[
                const SizedBox(height: 12),
                const Text(
                  'Open',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                Text(missedHabits.join('\n')),
              ],
              if (recipe.isNotEmpty) ...[
                const SizedBox(height: 12),
                const Text(
                  'Cooking recipe',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                Text(recipe),
              ],
            ],
          ),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Done'),
          ),
        ],
      ),
    );
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
          body: item.$3 == 1000 ? _morningRecipeText() : _overdueText(),
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

  String _morningRecipeText() {
    final suggestion = recipeSuggestion;
    if (suggestion != null && suggestion['title']?.isNotEmpty == true) {
      return 'Today\'s cooking idea: ${suggestion['title']}';
    }
    return 'Open the tracker for today\'s Dr. Greger recipe idea.';
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
                Wrap(
                  spacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    ChoiceChip(
                      label: const Text('Today'),
                      selected: _showingToday,
                      onSelected: (_) => _switchDay(yesterday: false),
                    ),
                    ChoiceChip(
                      label: const Text('Yesterday'),
                      selected: !_showingToday,
                      onSelected: (_) => _switchDay(yesterday: true),
                    ),
                    Text(today, style: Theme.of(context).textTheme.bodyMedium),
                  ],
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
                      title: Text(
                        e.value,
                        style: const TextStyle(fontSize: 15),
                      ),
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
                            _selectedDayTimestamp,
                          );
                        }
                        await _save();
                      },
                    ),
                    if (e.key == 'uncle_exercise')
                      _note(
                        'uncle_exercise_comment',
                        'What exercise did you do?',
                        speechButton: true,
                      ),
                    if (e.key == 'call_close_one')
                      _note('close_one_comment', 'Who did you call or meet?'),
                    if (e.key == 'courage')
                      _note('courage_comment', 'What did you dare to do?'),
                    if (e.key == 'board_game')
                      _note('board_game_comment', 'Which board game?'),
                    if (e.key == 'sports')
                      _note('sports_comment', 'What sport or exercise?'),
                    if (e.key == 'cook_own_meal') ...[
                      _note(
                        cookingRecipeKey,
                        'Recipe or cooking notes',
                        speechButton: true,
                      ),
                      _recipeSuggestionCard(),
                      _cookingPhotoPreview(),
                    ],
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
                    title: const Text(
                      'Birthday greeting done',
                      style: TextStyle(fontSize: 15),
                    ),
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
                if (appMode != 'uncle')
                  const _Heading('Delegate to yourself for later'),
                if (appMode != 'uncle')
                  ...delegatedTasks.map((task) {
                    final due = DateTime.fromMillisecondsSinceEpoch(
                      (task['due'] as num?)?.toInt() ?? 0,
                    );
                    final completed = task['completed'] == true;
                    return Card(
                      child: ListTile(
                        leading: _taskPhoto(task),
                        title: Text(
                          task['name']?.toString() ?? 'Task',
                          style: TextStyle(
                            decoration: completed
                                ? TextDecoration.lineThrough
                                : null,
                          ),
                        ),
                        subtitle: Text(
                          'Reminder: ${DateFormat('yyyy-MM-dd HH:mm').format(due)}',
                        ),
                        trailing: Checkbox(
                          value: completed,
                          onChanged: (value) =>
                              _setTaskCompleted(task, value ?? false),
                        ),
                      ),
                    );
                  }),
                if (appMode != 'uncle')
                  FilledButton.icon(
                    onPressed: _addDelegatedTask,
                    icon: const Icon(Icons.add_a_photo),
                    label: const Text('Photograph and delegate a task'),
                  ),
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
                Text('Google Sheets person: $_person'),
                const SizedBox(height: 4),
                const Text(
                  'Works offline. Changes sync with Google Sheets when a connection is available.',
                ),
                const SizedBox(height: 10),
                FilledButton.icon(
                  onPressed: _showHabitEvaluation,
                  icon: const Icon(Icons.summarize),
                  label: const Text('Evaluate habits'),
                ),
                const SizedBox(height: 8),
                if (!kIsWeb)
                  OutlinedButton.icon(
                    onPressed: () => communicationChannel.invokeMethod<void>(
                      'openNotificationSettings',
                    ),
                    icon: const Icon(Icons.notifications_active),
                    label: const Text('WhatsApp notification access'),
                  ),
                if (!kIsWeb) const SizedBox(height: 8),
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
