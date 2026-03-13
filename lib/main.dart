import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
    FlutterLocalNotificationsPlugin();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
  const darwinSettings = DarwinInitializationSettings();
  const initSettings = InitializationSettings(
    android: androidSettings,
    iOS: darwinSettings,
    macOS: darwinSettings,
  );

  await flutterLocalNotificationsPlugin.initialize(initSettings);

  runApp(const RicordameloApp());
}

class RicordameloApp extends StatelessWidget {
  const RicordameloApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Ricordamelo',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF007AFF),
          brightness: Brightness.light,
        ),
        scaffoldBackgroundColor: const Color(0xFFF2F2F7),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFFF2F2F7),
          foregroundColor: Colors.black,
          elevation: 0,
          centerTitle: true,
          titleTextStyle: TextStyle(
            color: Colors.black,
            fontSize: 28,
            fontWeight: FontWeight.w700,
          ),
        ),
        cardTheme: CardThemeData(
          color: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(22),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 14,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide.none,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(
              color: Color(0xFF007AFF),
              width: 1.2,
            ),
          ),
        ),
        floatingActionButtonTheme: const FloatingActionButtonThemeData(
          backgroundColor: Color(0xFF007AFF),
          foregroundColor: Colors.white,
        ),
      ),
      home: const HomePage(),
    );
  }
}

class Task {
  final String title;
  final String category;
  final DateTime? deadline;
  bool completed;

  Task({
    required this.title,
    required this.category,
    this.deadline,
    this.completed = false,
  });

  Map<String, dynamic> toMap() {
    return {
      'title': title,
      'category': category,
      'deadline': deadline?.toIso8601String(),
      'completed': completed,
    };
  }

  factory Task.fromMap(Map<String, dynamic> map) {
    return Task(
      title: map['title'] ?? '',
      category: map['category'] ?? 'Altro',
      deadline: map['deadline'] != null
          ? DateTime.tryParse(map['deadline'])
          : null,
      completed: map['completed'] ?? false,
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final _notifications = flutterLocalNotificationsPlugin;
  late stt.SpeechToText _speech;
  bool _isListening = false;
  int _selectedIndex = 0;
  final List<Task> tasks = [];

  @override
  void initState() {
    super.initState();
    _speech = stt.SpeechToText();
    _loadTasks();
  }

  Future<void> _loadTasks() async {
    final prefs = await SharedPreferences.getInstance();
    final savedTasks = prefs.getStringList('tasks');

    if (savedTasks == null || savedTasks.isEmpty) {
      setState(() {
        tasks.addAll([
          Task(
            title: 'Comprare il pane',
            category: 'Spesa',
            deadline: DateTime.now().add(const Duration(hours: 3)),
          ),
          Task(
            title: 'Pagare bolletta luce',
            category: 'Bollette',
            deadline: DateTime.now().add(const Duration(days: 1)),
          ),
        ]);
      });
      await _saveTasks();
      return;
    }

    setState(() {
      tasks.clear();
      tasks.addAll(
        savedTasks.map((taskString) {
          final map = jsonDecode(taskString) as Map<String, dynamic>;
          return Task.fromMap(map);
        }),
      );
    });
  }

  Future<void> _saveTasks() async {
    final prefs = await SharedPreferences.getInstance();
    final encodedTasks = tasks.map((task) => jsonEncode(task.toMap())).toList();
    await prefs.setStringList('tasks', encodedTasks);
  }

  Future<void> _scheduleNotification(Task task) async {
    if (task.deadline == null) return;

    final notificationTime = task.deadline!.subtract(const Duration(minutes: 10));
    if (notificationTime.isBefore(DateTime.now())) return;

    const androidDetails = AndroidNotificationDetails(
      'ricordamelo_channel',
      'Promemoria Ricordamelo',
      channelDescription: 'Notifiche per i promemoria salvati',
      importance: Importance.max,
      priority: Priority.high,
    );

    const iosDetails = DarwinNotificationDetails();
    const notificationDetails = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
      macOS: iosDetails,
    );

    await _notifications.show(
      task.hashCode,
      'Promemoria in arrivo',
      task.title,
      notificationDetails,
    );
  }

  DateTime? _parseItalianDeadline(String text) {
    final lower = text.toLowerCase();
    final now = DateTime.now();
    DateTime baseDate = now;

    if (lower.contains('dopodomani')) {
      baseDate = now.add(const Duration(days: 2));
    } else if (lower.contains('domani')) {
      baseDate = now.add(const Duration(days: 1));
    } else if (lower.contains('oggi')) {
      baseDate = now;
    }

    int? hour;
    int minute = 0;

    final words = lower.split(' ');
    for (int i = 0; i < words.length; i++) {
      if ((words[i] == 'alle' || words[i] == 'ore') && i + 1 < words.length) {
        final rawTime = words[i + 1].trim();

        if (rawTime.contains(':')) {
          final parts = rawTime.split(':');
          hour = int.tryParse(parts.first);
          minute = parts.length > 1 ? int.tryParse(parts[1]) ?? 0 : 0;
        } else {
          hour = int.tryParse(rawTime);
        }
        break;
      }
    }

    if (hour == null) return null;

    return DateTime(
      baseDate.year,
      baseDate.month,
      baseDate.day,
      hour,
      minute,
    );
  }

  String _cleanVoiceTitle(String text) {
    var cleaned = text.toLowerCase();

    cleaned = cleaned.replaceAll('domani', '');
    cleaned = cleaned.replaceAll('dopodomani', '');
    cleaned = cleaned.replaceAll('oggi', '');
    cleaned = cleaned.replaceAll('scade', '');
    cleaned = cleaned.replaceAll('scalea', '');
    cleaned = cleaned.replaceAll('avvisami', '');
    cleaned = cleaned.replaceAll('ricordamelo', '');
    cleaned = cleaned.replaceAll('ricordami', '');

    final words = cleaned.split(' ');
    final filtered = <String>[];

    for (int i = 0; i < words.length; i++) {
      if ((words[i] == 'alle' || words[i] == 'ore') && i + 1 < words.length) {
        i++;
        continue;
      }

      if (words[i].trim().isNotEmpty) {
        filtered.add(words[i].trim());
      }
    }

    cleaned = filtered.join(' ').trim();

    if (cleaned.isEmpty) return text.trim();

    return cleaned[0].toUpperCase() + cleaned.substring(1);
  }

  Future<void> _listenVoice() async {
    if (!_isListening) {
      final available = await _speech.initialize();
      if (!available) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Microfono non disponibile su questo dispositivo.'),
          ),
        );
        return;
      }

      setState(() {
        _isListening = true;
      });

      _speech.listen(
        onResult: (result) {
          if (result.finalResult && result.recognizedWords.trim().isNotEmpty) {
            final spokenText = result.recognizedWords.trim();
            final parsedDeadline = _parseItalianDeadline(spokenText);
            final cleanTitle = _cleanVoiceTitle(spokenText);
            _addTask(cleanTitle, 'Altro', parsedDeadline);

            setState(() {
              _isListening = false;
            });
          }
        },
      );
    } else {
      setState(() {
        _isListening = false;
      });
      await _speech.stop();
    }
  }

  void _addTask(String title, String category, DateTime? deadline) {
    if (title.trim().isEmpty) return;

    final task = Task(
      title: title.trim(),
      category: category,
      deadline: deadline,
    );

    setState(() {
      tasks.add(task);
    });

    _saveTasks();
    _scheduleNotification(task);
  }

  void _toggleTask(int index) {
    setState(() {
      tasks[index].completed = !tasks[index].completed;
    });

    _saveTasks();
  }

  void _deleteTask(int index) {
    setState(() {
      tasks.removeAt(index);
    });

    _saveTasks();
  }

  void _showAddTaskSheet() {
    final titleController = TextEditingController();
    String selectedCategory = 'Altro';
    DateTime? selectedDeadline;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFFF2F2F7),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Padding(
              padding: EdgeInsets.only(
                left: 16,
                right: 16,
                top: 18,
                bottom: MediaQuery.of(context).viewInsets.bottom + 18,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Center(
                    child: SizedBox(
                      width: 42,
                      child: Divider(thickness: 4),
                    ),
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'Nuovo promemoria',
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: titleController,
                    decoration: const InputDecoration(labelText: 'Titolo'),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: selectedCategory,
                    decoration: const InputDecoration(labelText: 'Categoria'),
                    items: const [
                      DropdownMenuItem(value: 'Spesa', child: Text('Spesa')),
                      DropdownMenuItem(value: 'Casa', child: Text('Casa')),
                      DropdownMenuItem(value: 'Salute', child: Text('Salute')),
                      DropdownMenuItem(value: 'Bollette', child: Text('Bollette')),
                      DropdownMenuItem(value: 'Lavoro', child: Text('Lavoro')),
                      DropdownMenuItem(value: 'Altro', child: Text('Altro')),
                    ],
                    onChanged: (value) {
                      if (value != null) {
                        setModalState(() {
                          selectedCategory = value;
                        });
                      }
                    },
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        backgroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        side: BorderSide.none,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                      onPressed: () async {
                        final now = DateTime.now();
                        final pickedDate = await showDatePicker(
                          context: context,
                          initialDate: now,
                          firstDate: now,
                          lastDate: DateTime(now.year + 5),
                        );

                        if (pickedDate == null) return;
                        if (!mounted) return;

                        final pickedTime = await showTimePicker(
                          context: context,
                          initialTime: TimeOfDay.now(),
                        );

                        if (pickedTime == null) return;

                        setModalState(() {
                          selectedDeadline = DateTime(
                            pickedDate.year,
                            pickedDate.month,
                            pickedDate.day,
                            pickedTime.hour,
                            pickedTime.minute,
                          );
                        });
                      },
                      icon: const Icon(Icons.calendar_month),
                      label: Text(
                        selectedDeadline == null
                            ? 'Scegli data e ora'
                            : 'Scadenza: ${selectedDeadline!.day}/${selectedDeadline!.month}/${selectedDeadline!.year}  ${selectedDeadline!.hour.toString().padLeft(2, '0')}:${selectedDeadline!.minute.toString().padLeft(2, '0')}',
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF007AFF),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                      onPressed: () {
                        _addTask(
                          titleController.text,
                          selectedCategory,
                          selectedDeadline,
                        );
                        Navigator.pop(context);
                      },
                      child: const Text('Salva'),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  String _formatDeadline(DateTime? dateTime) {
    if (dateTime == null) return 'Nessuna scadenza';
    return '${dateTime.day}/${dateTime.month}/${dateTime.year} - ${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}';
  }

  List<Task> _visibleTasks() {
    if (_selectedIndex == 1) {
      final now = DateTime.now();
      return tasks.where((task) {
        if (task.completed) return false;
        if (task.deadline == null) return false;
        return task.deadline!.year == now.year &&
            task.deadline!.month == now.month &&
            task.deadline!.day == now.day;
      }).toList();
    }

    if (_selectedIndex == 2) {
      return tasks.where((task) => task.completed).toList();
    }

    return tasks;
  }

  @override
  Widget build(BuildContext context) {
    final pendingTasks = tasks.where((task) => !task.completed).toList();
    final completedTasks = tasks.where((task) => task.completed).toList();
    final visibleTasks = _visibleTasks();

    return Scaffold(
      appBar: AppBar(title: const Text('Ricordamelo')),
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          FloatingActionButton.extended(
            heroTag: 'voice',
            onPressed: _listenVoice,
            icon: Icon(_isListening ? Icons.mic_off : Icons.mic),
            label: Text(_isListening ? 'Stop' : 'Voce'),
          ),
          const SizedBox(height: 12),
          FloatingActionButton.extended(
            heroTag: 'add',
            onPressed: _showAddTaskSheet,
            icon: const Icon(Icons.add),
            label: const Text('Aggiungi'),
          ),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        height: 74,
        backgroundColor: Colors.white,
        indicatorColor: const Color(0x1A007AFF),
        selectedIndex: _selectedIndex,
        onDestinationSelected: (index) {
          setState(() {
            _selectedIndex = index;
          });
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.list_alt_outlined),
            selectedIcon: Icon(Icons.list_alt),
            label: 'Tutti',
          ),
          NavigationDestination(
            icon: Icon(Icons.today_outlined),
            selectedIcon: Icon(Icons.today),
            label: 'Oggi',
          ),
          NavigationDestination(
            icon: Icon(Icons.check_circle_outline),
            selectedIcon: Icon(Icons.check_circle),
            label: 'Fatti',
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(30),
              gradient: const LinearGradient(
                colors: [Color(0xFF007AFF), Color(0xFF5AC8FA)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x33007AFF),
                  blurRadius: 24,
                  offset: Offset(0, 10),
                ),
              ],
            ),
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Promemoria smart',
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
                SizedBox(height: 8),
                Text(
                  'Parla e scrivi frasi come: domani alle 12 scade assicurazione avvisami',
                  style: TextStyle(
                    fontSize: 15,
                    color: Colors.white,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          Card(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 18),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _StatBox(
                    label: 'Da fare',
                    value: pendingTasks.length.toString(),
                  ),
                  _StatBox(
                    label: 'Fatte',
                    value: completedTasks.length.toString(),
                  ),
                  _StatBox(label: 'Totale', value: tasks.length.toString()),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          Padding(
            padding: const EdgeInsets.only(left: 4),
            child: Text(
              _selectedIndex == 0
                  ? 'Promemoria'
                  : _selectedIndex == 1
                      ? 'Oggi'
                      : 'Completati',
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
            ),
          ),
          const SizedBox(height: 12),
          if (visibleTasks.isEmpty)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(20),
                child: Text('Nessun promemoria in questa sezione.'),
              ),
            )
          else
            ...List.generate(visibleTasks.length, (index) {
              final task = visibleTasks[index];
              final originalIndex = tasks.indexOf(task);
              return Dismissible(
                key: ValueKey('${task.title}-${task.deadline?.toIso8601String()}-$originalIndex'),
                direction: DismissDirection.endToStart,
                background: Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: Colors.redAccent,
                    borderRadius: BorderRadius.circular(22),
                  ),
                  alignment: Alignment.centerRight,
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Icon(Icons.delete_outline, color: Colors.white, size: 28),
                      SizedBox(width: 8),
                      Text(
                        'Elimina',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
                onDismissed: (_) {
                  _deleteTask(originalIndex);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Promemoria eliminato')),
                  );
                },
                child: Card(
                margin: const EdgeInsets.only(bottom: 12),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                  child: ListTile(
                    leading: Transform.scale(
                      scale: 1.1,
                      child: Checkbox(
                        value: task.completed,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(6),
                        ),
                        onChanged: (_) => _toggleTask(originalIndex),
                      ),
                    ),
                    title: Text(
                      task.title,
                      style: TextStyle(
                        decoration: task.completed
                            ? TextDecoration.lineThrough
                            : null,
                        fontWeight: FontWeight.w700,
                        fontSize: 20,
                      ),
                    ),
                    subtitle: Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          _InfoChip(
                            icon: Icons.folder_outlined,
                            text: task.category,
                          ),
                          _InfoChip(
                            icon: Icons.schedule,
                            text: _formatDeadline(task.deadline),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            );
            }),
        ],
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String text;

  const _InfoChip({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: const Color(0xFFF2F2F7),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: const Color(0xFF007AFF)),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              text,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatBox extends StatelessWidget {
  final String label;
  final String value;

  const _StatBox({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          value,
          style: const TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.w800,
            color: Colors.black,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          label,
          style: const TextStyle(
            fontSize: 15,
            color: Color(0xFF6E6E73),
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}
