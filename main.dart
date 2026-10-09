import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

const supabaseUrl = 'https://dttfyzshlhbzdnqblixi.supabase.co';
const supabaseKey = 'sb_publishable_XCUDBRh58A0PBqN9PitwzQ_oWu2d_UK';

const authUrl = '$supabaseUrl/auth/v1';
const eventsUrl = '$supabaseUrl/rest/v1/events';
const messagesUrl = '$supabaseUrl/rest/v1/messages';
const votesUrl = '$supabaseUrl/rest/v1/votes';

const pollOptions = ['Hackathon', 'Workshop', 'Turneu'];

http.Client apiClient = http.Client();

void main() => runApp(const CampusApp());

// ============================================================
// SESIONI DHE AUTENTIKIMI
// ============================================================

class Session {
  final String accessToken;
  final String userId;
  final String email;

  const Session({
    required this.accessToken,
    required this.userId,
    required this.email,
  });

  factory Session.fromJson(Map<String, dynamic> json) {
    final user = json['user'] as Map<String, dynamic>;

    return Session(
      accessToken: json['access_token'] as String,
      userId: user['id'] as String,
      email: user['email'] as String,
    );
  }
}

Session? currentSession;

Map<String, String> authHeaders() {
  return {
    'apikey': supabaseKey,
    'Content-Type': 'application/json',
    if (currentSession != null)
      'Authorization': 'Bearer ${currentSession!.accessToken}',
  };
}

String errorText(Object error) {
  return error.toString().replaceFirst('Exception: ', '');
}

String responseError(http.Response response) {
  if (response.statusCode == 401) {
    return 'Sesioni skadoi. Dilni dhe kyçuni përsëri.';
  }

  try {
    final json = jsonDecode(response.body) as Map<String, dynamic>;

    return (json['msg'] ??
            json['message'] ??
            json['error_description'] ??
            json['error'] ??
            'Gabim: ${response.statusCode}')
        .toString();
  } catch (_) {
    return 'Gabim: ${response.statusCode}';
  }
}

// K18 — SnackBar dhe feedback.
void feedback(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(message),
      duration: const Duration(seconds: 5),
    ),
  );
}

// K7 — Login dhe regjistrim.
Future<Session> authenticate(
  String email,
  String password,
  bool register,
) async {
  final response = await apiClient
      .post(
        Uri.parse(
          register ? '$authUrl/signup' : '$authUrl/token?grant_type=password',
        ),
        headers: {
          'apikey': supabaseKey,
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'email': email,
          'password': password,
        }),
      )
      .timeout(const Duration(seconds: 20));

  if (response.statusCode != 200 && response.statusCode != 201) {
    throw Exception(responseError(response));
  }

  final json = jsonDecode(response.body) as Map<String, dynamic>;

  if (json['access_token'] == null) {
    throw Exception(
      'Regjistrimi u krye. Konfirmoni email-in, pastaj kyçuni.',
    );
  }

  return Session.fromJson(json);
}

// K17 — Dalja.
Future<void> signOut() async {
  final response = await apiClient
      .post(
        Uri.parse('$authUrl/logout'),
        headers: authHeaders(),
      )
      .timeout(const Duration(seconds: 20));

  if (response.statusCode != 200 && response.statusCode != 204) {
    throw Exception(responseError(response));
  }
}

// ============================================================
// K3 — MODELI I EVENTIT
// ============================================================

class Event {
  final int id;
  final int likes;
  final String title;
  final String date;
  final String location;
  final String? userId;
  final String? author;

  const Event({
    required this.id,
    required this.title,
    required this.date,
    required this.location,
    required this.likes,
    this.userId,
    this.author,
  });

  factory Event.fromJson(Map<String, dynamic> json) {
    return Event(
      id: (json['id'] as num).toInt(),
      title: json['title'] as String,
      date: json['date'] as String,
      location: json['location'] as String,
      likes: (json['likes'] as num?)?.toInt() ?? 0,
      userId: json['user_id'] as String?,
      author: json['author'] as String?,
    );
  }

  bool get isMine {
    return userId != null && userId == currentSession?.userId;
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'date': date,
      'location': location,
      'likes': likes,
      'user_id': userId,
      'author': author,
    };
  }
}

// K14 — Kërkimi dhe filtri i pronarit.
List<Event> filterEvents(
  List<Event> events,
  String query,
  bool onlyMine,
) {
  final q = query.trim().toLowerCase();

  return events.where((event) {
    final text =
        '${event.title} ${event.location} ${event.date} ${event.author ?? ''}'
            .toLowerCase();

    return (!onlyMine || event.isMine) && text.contains(q);
  }).toList();
}

// ============================================================
// K4 — LEXIMI NGA SUPABASE
// ============================================================

Future<List<Event>> fetchEvents() async {
  final response = await apiClient
      .get(
        Uri.parse('$eventsUrl?select=*&order=id.desc'),
        headers: authHeaders(),
      )
      .timeout(const Duration(seconds: 20));

  if (response.statusCode != 200) {
    throw Exception(responseError(response));
  }

  final rows = jsonDecode(response.body) as List;

  return rows
      .map((row) => Event.fromJson(row as Map<String, dynamic>))
      .toList();
}

Future<Event> fetchEvent(int id) async {
  final response = await apiClient
      .get(
        Uri.parse('$eventsUrl?select=*&id=eq.$id'),
        headers: authHeaders(),
      )
      .timeout(const Duration(seconds: 20));

  if (response.statusCode != 200) {
    throw Exception(responseError(response));
  }

  final rows = jsonDecode(response.body) as List;

  if (rows.isEmpty) {
    throw Exception('Eventi nuk ekziston më.');
  }

  return Event.fromJson(rows.first as Map<String, dynamic>);
}

// K10 — Shtimi.
// K11 — Ndryshimi nga pronari.
Future<Event> saveEvent(
  String title,
  String date,
  String location, {
  Event? existing,
}) async {
  final session = currentSession;

  if (session == null) {
    throw Exception('Duhet të kyçeni.');
  }

  if (existing != null && !existing.isMine) {
    throw Exception('Vetëm pronari mund ta ndryshojë eventin.');
  }

  final data = {
    'title': title.trim(),
    'date': date.trim(),
    'location': location.trim(),
  };

  if (existing == null) {
    data['author'] = session.email;
  }

  final headers = {
    ...authHeaders(),
    'Prefer': 'return=representation',
  };

  final http.Response response;

  if (existing == null) {
    response = await apiClient
        .post(
          Uri.parse(eventsUrl),
          headers: headers,
          body: jsonEncode(data),
        )
        .timeout(const Duration(seconds: 20));
  } else {
    response = await apiClient
        .patch(
          Uri.parse('$eventsUrl?id=eq.${existing.id}'),
          headers: headers,
          body: jsonEncode(data),
        )
        .timeout(const Duration(seconds: 20));
  }

  if (response.statusCode != 200 && response.statusCode != 201) {
    throw Exception(responseError(response));
  }

  final rows = jsonDecode(response.body) as List;

  if (rows.isEmpty) {
    throw Exception('Nuk u ruajt. Kontrolloni pronarin dhe RLS.');
  }

  return Event.fromJson(rows.first as Map<String, dynamic>);
}

// K12 — Fshirja nga pronari.
Future<void> deleteEvent(Event event) async {
  if (!event.isMine) {
    throw Exception('Mund të fshini vetëm eventet tuaja.');
  }

  final response = await apiClient.delete(
    Uri.parse('$eventsUrl?id=eq.${event.id}'),
    headers: {
      ...authHeaders(),
      'Prefer': 'return=representation',
    },
  ).timeout(const Duration(seconds: 20));

  if (response.statusCode != 200) {
    throw Exception(responseError(response));
  }

  final deleted = jsonDecode(response.body) as List;

  if (deleted.isEmpty) {
    throw Exception('Eventi nuk u fshi. Kontrolloni lejet.');
  }
}

Future<void> likeEvent(Event event) async {
  if (!event.isMine) {
    throw Exception('Vetëm pronari mund ta ndryshojë eventin.');
  }

  final response = await apiClient
      .patch(
        Uri.parse('$eventsUrl?id=eq.${event.id}'),
        headers: {
          ...authHeaders(),
          'Prefer': 'return=representation',
        },
        body: jsonEncode({'likes': event.likes + 1}),
      )
      .timeout(const Duration(seconds: 20));

  if (response.statusCode != 200) {
    throw Exception(responseError(response));
  }

  if ((jsonDecode(response.body) as List).isEmpty) {
    throw Exception('Pëlqimi nuk u ruajt.');
  }
}

// ============================================================
// APP-I DHE DARK MODE
// ============================================================

class CampusApp extends StatefulWidget {
  const CampusApp({super.key});

  @override
  State<CampusApp> createState() => _CampusAppState();
}

class _CampusAppState extends State<CampusApp> {
  bool _dark = false;
  bool _loggingOut = false;

  void _login(Session session) {
    setState(() => currentSession = session);
  }

  Future<void> _logout() async {
    if (_loggingOut) return;

    _loggingOut = true;

    try {
      await signOut();
    } catch (_) {
      // Sesioni lokal mbyllet edhe nëse kërkesa dështon.
    } finally {
      _loggingOut = false;

      if (mounted) {
        setState(() => currentSession = null);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'BGT Campus',
      debugShowCheckedModeBanner: false,

      // K15 — Tema dhe dark mode.
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.deepPurple,
        ),
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.deepPurple,
          brightness: Brightness.dark,
        ),
      ),
      themeMode: _dark ? ThemeMode.dark : ThemeMode.light,

      home: currentSession == null
          ? LoginPage(onLogin: _login)
          : HomeShell(
              key: ValueKey(currentSession!.userId),
              onLogout: _logout,
              isDark: _dark,
              onThemeChanged: (value) {
                setState(() => _dark = value);
              },
            ),
    );
  }
}

// ============================================================
// K7 — LOGIN / REGJISTRIM
// ============================================================

class LoginPage extends StatefulWidget {
  final ValueChanged<Session> onLogin;

  const LoginPage({
    super.key,
    required this.onLogin,
  });

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();

  bool _busy = false;
  String? _error;

  Future<void> _submit(bool register) async {
    if (_busy || !_form.currentState!.validate()) return;

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      final session = await authenticate(
        _email.text.trim(),
        _password.text,
        register,
      );

      if (!mounted) return;

      widget.onLogin(session);
    } catch (error) {
      if (mounted) {
        setState(() => _error = errorText(error));
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('BGT Campus – Kyçu'),
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Form(
              key: _form,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.school, size: 64),
                  const SizedBox(height: 24),
                  TextFormField(
                    controller: _email,
                    enabled: !_busy,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(
                      labelText: 'Email',
                      border: OutlineInputBorder(),
                    ),
                    validator: (value) {
                      final email = value?.trim() ?? '';

                      if (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$')
                          .hasMatch(email)) {
                        return 'Shkruani email të vlefshëm.';
                      }

                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _password,
                    enabled: !_busy,
                    obscureText: true,
                    decoration: const InputDecoration(
                      labelText: 'Fjalëkalimi',
                      border: OutlineInputBorder(),
                    ),
                    validator: (value) {
                      if (value == null || value.length < 6) {
                        return 'Së paku 6 karaktere.';
                      }

                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  if (_error != null)
                    Text(
                      _error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  if (_busy)
                    const CircularProgressIndicator()
                  else ...[
                    FilledButton(
                      onPressed: () => _submit(false),
                      child: const Text('Kyçu'),
                    ),
                    OutlinedButton(
                      onPressed: () => _submit(true),
                      child: const Text('Regjistrohu'),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ============================================================
// K16 — NAVIGIMI ME KATËR TAB-A
// ============================================================

class HomeShell extends StatefulWidget {
  final VoidCallback onLogout;
  final bool isDark;
  final ValueChanged<bool> onThemeChanged;

  const HomeShell({
    super.key,
    required this.onLogout,
    required this.isDark,
    required this.onThemeChanged,
  });

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _index,
        children: [
          const HomePage(),
          const EventsPage(),
          const ChatPage(),
          ProfilePage(
            onLogout: widget.onLogout,
            isDark: widget.isDark,
            onThemeChanged: widget.onThemeChanged,
          ),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (value) {
          setState(() => _index = value);
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home),
            label: 'Home',
          ),
          NavigationDestination(
            icon: Icon(Icons.event),
            label: 'Eventet',
          ),
          NavigationDestination(
            icon: Icon(Icons.chat),
            label: 'Chat',
          ),
          NavigationDestination(
            icon: Icon(Icons.person),
            label: 'Profili',
          ),
        ],
      ),
    );
  }
}

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('BGT Campus')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          ListTile(
            leading: const Icon(Icons.school, size: 48),
            title: const Text('Mirë se vini!'),
            subtitle: Text(currentSession?.email ?? ''),
          ),
          const Padding(
            padding: EdgeInsets.all(12),
            child: Text(
              'Organizo eventet, komuniko në chat dhe voto '
              'për aktivitetin e radhës.',
            ),
          ),
          const PollCard(),
        ],
      ),
    );
  }
}

// ============================================================
// K17 — PROFILI DHE DALJA
// ============================================================

class ProfilePage extends StatelessWidget {
  final VoidCallback onLogout;
  final bool isDark;
  final ValueChanged<bool> onThemeChanged;

  const ProfilePage({
    super.key,
    required this.onLogout,
    required this.isDark,
    required this.onThemeChanged,
  });

  @override
  Widget build(BuildContext context) {
    final email = currentSession?.email ?? '';

    return Scaffold(
      appBar: AppBar(title: const Text('Profili')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Center(
            child: CircleAvatar(
              radius: 40,
              child: Text(
                email.isEmpty ? '?' : email[0].toUpperCase(),
                style: const TextStyle(fontSize: 32),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Center(child: Text(email)),
          const SizedBox(height: 24),

          // K15
          SwitchListTile(
            title: const Text('Tema e errët'),
            secondary: const Icon(Icons.dark_mode),
            value: isDark,
            onChanged: onThemeChanged,
          ),

          ListTile(
            leading: const Icon(Icons.list_alt),
            title: const Text('Postimet e mia'),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const EventsPage(onlyMine: true),
                ),
              );
            },
          ),

          ListTile(
            leading: const Icon(Icons.logout),
            title: const Text('Dil'),
            onTap: onLogout,
          ),
        ],
      ),
    );
  }
}

// ============================================================
// K5, K6, K13, K14 — LISTA E EVENTEVE
// ============================================================

class EventsPage extends StatefulWidget {
  final bool onlyMine;

  const EventsPage({
    super.key,
    this.onlyMine = false,
  });

  @override
  State<EventsPage> createState() => _EventsPageState();
}

class _EventsPageState extends State<EventsPage> {
  // K13 — Lista live me polling çdo 3 sekonda.
  final _controller = StreamController<List<Event>>();
  Timer? _timer;

  bool _loading = false;
  bool _onlyMine = false;
  String _query = '';

  @override
  void initState() {
    super.initState();

    _onlyMine = widget.onlyMine;
    _load();

    _timer = Timer.periodic(
      const Duration(seconds: 3),
      (_) => _load(),
    );
  }

  Future<void> _load() async {
    if (_loading || _controller.isClosed) return;

    _loading = true;

    try {
      final events = await fetchEvents();

      if (!_controller.isClosed) {
        _controller.add(events);
      }
    } catch (error) {
      if (!_controller.isClosed) {
        _controller.addError(error);
      }
    } finally {
      _loading = false;
    }
  }

  Future<void> _add() async {
    final event = await Navigator.push<Event>(
      context,
      MaterialPageRoute(
        builder: (_) => const EventFormPage(),
      ),
    );

    if (event != null && mounted) {
      feedback(context, 'Eventi u shtua.');
      await _load();
    }
  }

  Future<void> _open(Event event) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => EventDetailPage(event: event),
      ),
    );

    if (mounted) {
      await _load();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.onlyMine ? 'Postimet e mia' : 'Eventet'),
      ),
      body: Column(
        children: [
          // K14 — Kërkimi.
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              decoration: const InputDecoration(
                labelText: 'Kërko eventin ose vendin',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
              ),
              onChanged: (value) {
                setState(() => _query = value);
              },
            ),
          ),

          // K14 — Të gjitha / Të miat.
          if (!widget.onlyMine)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: [
                  ChoiceChip(
                    label: const Text('Të gjitha'),
                    selected: !_onlyMine,
                    onSelected: (_) {
                      setState(() => _onlyMine = false);
                    },
                  ),
                  const SizedBox(width: 8),
                  ChoiceChip(
                    label: const Text('Të miat'),
                    selected: _onlyMine,
                    onSelected: (_) {
                      setState(() => _onlyMine = true);
                    },
                  ),
                ],
              ),
            ),

          Expanded(
            child: StreamBuilder<List<Event>>(
              stream: _controller.stream,
              builder: (context, snapshot) {
                // K6 — Gjendja e gabimit.
                if (snapshot.hasError) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.cloud_off, size: 48),
                          Text(
                            errorText(snapshot.error!),
                            textAlign: TextAlign.center,
                          ),
                          FilledButton(
                            onPressed: _load,
                            child: const Text('Provo përsëri'),
                          ),
                        ],
                      ),
                    ),
                  );
                }

                // K6 — Gjendja e ngarkimit.
                if (!snapshot.hasData) {
                  return const Center(
                    child: CircularProgressIndicator(),
                  );
                }

                final all = snapshot.data!;
                final events = filterEvents(
                  all,
                  _query,
                  _onlyMine,
                );

                return RefreshIndicator(
                  onRefresh: _load,

                  // K6 — Lista bosh.
                  child: events.isEmpty
                      ? ListView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          children: [
                            Padding(
                              padding: const EdgeInsets.all(40),
                              child: Text(
                                all.isEmpty
                                    ? 'Nuk ka evente ende. '
                                        'Shto eventin e parë!'
                                    : 'Nuk u gjet asnjë event '
                                        'për këtë filtër.',
                                textAlign: TextAlign.center,
                              ),
                            ),
                          ],
                        )

                      // K5, K6 — Lista me të dhëna.
                      : ListView.builder(
                          physics: const AlwaysScrollableScrollPhysics(),
                          itemCount: events.length,
                          itemBuilder: (context, index) {
                            final event = events[index];

                            return Card(
                              child: ListTile(
                                leading: Icon(
                                  event.isMine ? Icons.person : Icons.event,
                                ),
                                title: Text(event.title),
                                subtitle: Text(
                                  '${event.date} · ${event.location}\n'
                                  'Postuar nga: ${event.author ?? 'BGT'}',
                                ),
                                isThreeLine: true,
                                trailing: const Icon(Icons.chevron_right),
                                onTap: () => _open(event),
                              ),
                            );
                          },
                        ),
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _add,
        icon: const Icon(Icons.add),
        label: const Text('Shto event'),
      ),
    );
  }
}

// ============================================================
// K9, K10, K11 — FORMA E SHTIMIT / NDRYSHIMIT
// ============================================================

class EventFormPage extends StatefulWidget {
  final Event? event;

  const EventFormPage({
    super.key,
    this.event,
  });

  @override
  State<EventFormPage> createState() => _EventFormPageState();
}

class _EventFormPageState extends State<EventFormPage> {
  final _form = GlobalKey<FormState>();
  final _title = TextEditingController();
  final _date = TextEditingController();
  final _location = TextEditingController();

  bool _saving = false;

  @override
  void initState() {
    super.initState();

    final event = widget.event;

    if (event != null) {
      _title.text = event.title;
      _date.text = event.date;
      _location.text = event.location;
    }
  }

  String? _validate(
    String? value,
    String label,
    int max,
  ) {
    final text = value?.trim() ?? '';

    if (text.isEmpty) {
      return 'Shkruani $label.';
    }

    if (text.length > max) {
      return 'Maksimumi $max karaktere.';
    }

    return null;
  }

  Future<void> _save() async {
    if (_saving || !_form.currentState!.validate()) return;

    setState(() => _saving = true);

    try {
      final event = await saveEvent(
        _title.text,
        _date.text,
        _location.text,
        existing: widget.event,
      );

      if (mounted) {
        Navigator.pop(context, event);
      }
    } catch (error) {
      if (mounted) {
        feedback(context, errorText(error));
      }
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  @override
  void dispose() {
    _title.dispose();
    _date.dispose();
    _location.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.event == null ? 'Event i ri' : 'Ndrysho eventin',
        ),
      ),
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            TextFormField(
              controller: _title,
              enabled: !_saving,
              decoration: const InputDecoration(
                labelText: 'Titulli',
              ),
              validator: (value) {
                return _validate(value, 'titullin', 120);
              },
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _date,
              enabled: !_saving,
              decoration: const InputDecoration(
                labelText: 'Data',
                hintText: 'p.sh. 15 tetor 2026',
              ),
              validator: (value) {
                return _validate(value, 'datën', 80);
              },
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _location,
              enabled: !_saving,
              decoration: const InputDecoration(
                labelText: 'Vendi',
              ),
              validator: (value) {
                return _validate(value, 'vendin', 120);
              },
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _saving ? null : _save,
              child: Text(
                _saving ? 'Duke ruajtur…' : 'Ruaj',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================
// K8 — DETAJET; K11 / K12 — VEPRIMET E PRONARIT
// ============================================================

class EventDetailPage extends StatefulWidget {
  final Event event;

  const EventDetailPage({
    super.key,
    required this.event,
  });

  @override
  State<EventDetailPage> createState() => _EventDetailPageState();
}

class _EventDetailPageState extends State<EventDetailPage> {
  late Event _event;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _event = widget.event;
  }

  // K11
  Future<void> _edit() async {
    final updated = await Navigator.push<Event>(
      context,
      MaterialPageRoute(
        builder: (_) => EventFormPage(event: _event),
      ),
    );

    if (mounted && updated != null) {
      setState(() => _event = updated);
      feedback(context, 'Eventi u ndryshua.');
    }
  }

  // K12
  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Fshi eventin?'),
          content: Text(_event.title),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(dialogContext, false);
              },
              child: const Text('Anulo'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.pop(dialogContext, true);
              },
              child: const Text('Fshi'),
            ),
          ],
        );
      },
    );

    if (!mounted || confirmed != true || _busy) return;

    setState(() => _busy = true);

    try {
      await deleteEvent(_event);

      if (!mounted) return;

      feedback(context, 'Eventi u fshi.');
      Navigator.pop(context);
    } catch (error) {
      if (mounted) {
        feedback(context, errorText(error));
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _like() async {
    if (_busy) return;

    setState(() => _busy = true);

    try {
      await likeEvent(_event);
      final updated = await fetchEvent(_event.id);

      if (mounted) {
        setState(() => _event = updated);
      }
    } catch (error) {
      if (mounted) {
        feedback(context, errorText(error));
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_event.title)),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            _event.title,
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 20),

          ListTile(
            leading: const Icon(Icons.calendar_today),
            title: Text(_event.date),
          ),
          ListTile(
            leading: const Icon(Icons.place),
            title: Text(_event.location),
          ),
          ListTile(
            leading: const Icon(Icons.person),
            title: Text(
              'Postuar nga: ${_event.author ?? 'BGT'}',
            ),
          ),
          ListTile(
            leading: const Icon(Icons.thumb_up),
            title: Text('Pëlqime: ${_event.likes}'),
          ),

          // K11, K12 — Butonat shfaqen vetëm për pronarin.
          if (_event.isMine) ...[
            FilledButton.icon(
              onPressed: _busy ? null : _edit,
              icon: const Icon(Icons.edit),
              label: const Text('Ndrysho'),
            ),
            OutlinedButton.icon(
              onPressed: _busy ? null : _delete,
              icon: const Icon(Icons.delete),
              label: const Text('Fshi'),
            ),
            TextButton.icon(
              onPressed: _busy ? null : _like,
              icon: const Icon(Icons.thumb_up),
              label: const Text('Rrit pëlqimet'),
            ),
          ] else
            const Text(
              'Ndryshimin dhe fshirjen mund t’i bëjë vetëm pronari.',
            ),

          if (_busy) const LinearProgressIndicator(),
        ],
      ),
    );
  }
}

// ============================================================
// DAY 4 — CHAT-I
// ============================================================

// Task 4
class Message {
  final int id;
  final String userId;
  final String author;
  final String content;
  final DateTime createdAt;

  const Message({
    required this.id,
    required this.userId,
    required this.author,
    required this.content,
    required this.createdAt,
  });

  factory Message.fromJson(Map<String, dynamic> json) {
    return Message(
      id: (json['id'] as num).toInt(),
      userId: json['user_id'] as String,
      author: json['author'] as String,
      content: json['content'] as String,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  bool get isMine => userId == currentSession?.userId;
}

// Task 5
// Task 19 — Filtri “Të miat”.
Future<List<Message>> fetchMessages({
  bool onlyMine = false,
}) async {
  if (currentSession == null) {
    throw Exception('Duhet të kyçeni.');
  }

  final filter = onlyMine ? '&user_id=eq.${currentSession!.userId}' : '';

  final response = await apiClient
      .get(
        Uri.parse(
          '$messagesUrl?select=*&order=created_at.desc,id.desc'
          '&limit=50$filter',
        ),
        headers: authHeaders(),
      )
      .timeout(const Duration(seconds: 20));

  if (response.statusCode != 200) {
    throw Exception(responseError(response));
  }

  final rows = jsonDecode(response.body) as List;

  return rows
      .map((row) => Message.fromJson(row as Map<String, dynamic>))
      .toList();
}

// Task 6
Future<void> sendMessage(String content) async {
  final session = currentSession;

  if (session == null) {
    throw Exception('Duhet të kyçeni.');
  }

  if (content.trim().isEmpty) return;

  final response = await apiClient
      .post(
        Uri.parse(messagesUrl),
        headers: authHeaders(),
        body: jsonEncode({
          'author': session.email,
          'content': content.trim(),
        }),
      )
      .timeout(const Duration(seconds: 20));

  if (response.statusCode != 201) {
    throw Exception(responseError(response));
  }
}

// Task 7
class ChatPage extends StatefulWidget {
  const ChatPage({super.key});

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  // Task 7
  final _controller = StreamController<List<Message>>();

  // Task 12
  final _text = TextEditingController();

  // Task 14
  Timer? _timer;

  bool _loading = false;
  bool _sending = false;

  // Task 19
  bool _onlyMine = false;
  int _version = 0;
  int _displayedVersion = -1;

  @override
  void initState() {
    super.initState();
    _load();

    // Task 14
    _timer = Timer.periodic(
      const Duration(seconds: 3),
      (_) => _load(),
    );
  }

  // Task 8, Task 19
  Future<void> _load() async {
    if (_loading || _controller.isClosed) return;

    _loading = true;
    final version = _version;

    try {
      final messages = await fetchMessages(
        onlyMine: _onlyMine,
      );

      if (mounted && !_controller.isClosed && version == _version) {
        _displayedVersion = version;
        _controller.add(messages);
      }
    } catch (error) {
      if (mounted && !_controller.isClosed && version == _version) {
        _displayedVersion = version;
        _controller.addError(error);
      }
    } finally {
      _loading = false;

      if (mounted && !_controller.isClosed && version != _version) {
        unawaited(_load());
      }
    }
  }

  // Task 19
  void _filter(bool mine) {
    if (_onlyMine == mine) return;

    setState(() {
      _onlyMine = mine;
      _version++;
    });

    _load();
  }

  // Task 13
  Future<void> _send() async {
    final content = _text.text.trim();

    if (_sending || content.isEmpty) return;

    setState(() => _sending = true);
    _text.clear();

    try {
      await sendMessage(content);

      if (mounted) {
        await _load();
      }
    } catch (error) {
      if (mounted) {
        if (_text.text.isEmpty) {
          _text.text = content;
        }

        feedback(context, errorText(error));
      }
    } finally {
      if (mounted) {
        setState(() => _sending = false);
      }
    }
  }

  // Task 7, Task 14
  @override
  void dispose() {
    _timer?.cancel();
    _controller.close();
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Chat')),
      body: Column(
        children: [
          // Task 19
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                ChoiceChip(
                  label: const Text('Të gjitha'),
                  selected: !_onlyMine,
                  onSelected: (_) => _filter(false),
                ),
                const SizedBox(width: 8),
                ChoiceChip(
                  label: const Text('Të miat'),
                  selected: _onlyMine,
                  onSelected: (_) => _filter(true),
                ),
              ],
            ),
          ),

          // Task 9
          Expanded(
            child: StreamBuilder<List<Message>>(
              stream: _controller.stream,
              builder: (context, snapshot) {
                if (_displayedVersion != _version ||
                    (!snapshot.hasData && !snapshot.hasError)) {
                  return const Center(
                    child: CircularProgressIndicator(),
                  );
                }

                if (snapshot.hasError) {
                  return Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Chat-i nuk u ngarkua. '
                          '${errorText(snapshot.error!)}',
                        ),
                        TextButton(
                          onPressed: _load,
                          child: const Text('Provo përsëri'),
                        ),
                      ],
                    ),
                  );
                }

                final messages = snapshot.data!;

                if (messages.isEmpty) {
                  return Center(
                    child: Text(
                      _onlyMine
                          ? 'Nuk keni mesazhe ende.'
                          : 'Ende pa mesazhe. Shkruani i pari!',
                    ),
                  );
                }

                // Task 10
                return ListView.builder(
                  reverse: true,
                  padding: const EdgeInsets.all(12),
                  itemCount: messages.length,
                  itemBuilder: (context, index) {
                    final message = messages[index];

                    // Task 11
                    return Align(
                      alignment: message.isMine
                          ? Alignment.centerRight
                          : Alignment.centerLeft,
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          maxWidth: MediaQuery.of(context).size.width * 0.8,
                        ),
                        child: Card(
                          color: message.isMine
                              ? Theme.of(context).colorScheme.primaryContainer
                              : null,
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  message.author,
                                  style: Theme.of(context).textTheme.labelSmall,
                                ),
                                const SizedBox(height: 6),
                                Text(message.content),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),

          // Task 12, Task 13
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _text,
                      decoration: const InputDecoration(
                        hintText: 'Mesazhi',
                        border: OutlineInputBorder(),
                      ),
                      onSubmitted: (_) => _send(),
                    ),
                  ),
                  IconButton(
                    onPressed: _sending ? null : _send,
                    icon: const Icon(Icons.send),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================
// DAY 4 — VOTIMI
// ============================================================

// Task 15
Future<Map<String, int>> fetchVoteCounts() async {
  final response = await apiClient
      .get(
        Uri.parse('$votesUrl?select=option'),
        headers: authHeaders(),
      )
      .timeout(const Duration(seconds: 20));

  if (response.statusCode != 200) {
    throw Exception(responseError(response));
  }

  final counts = <String, int>{
    for (final option in pollOptions) option: 0,
  };

  final rows = jsonDecode(response.body) as List;

  for (final row in rows) {
    final option = row['option'] as String;

    if (counts.containsKey(option)) {
      counts[option] = counts[option]! + 1;
    }
  }

  return counts;
}

// Task 16
Future<void> vote(String option) async {
  if (currentSession == null) {
    throw Exception('Duhet të kyçeni.');
  }

  final response = await apiClient
      .post(
        Uri.parse(votesUrl),
        headers: authHeaders(),
        body: jsonEncode({'option': option}),
      )
      .timeout(const Duration(seconds: 20));

  if (response.statusCode == 409) {
    throw Exception('Keni votuar tashmë.');
  }

  if (response.statusCode != 201) {
    throw Exception(responseError(response));
  }
}

// Task 17, Task 18
class PollCard extends StatefulWidget {
  const PollCard({super.key});

  @override
  State<PollCard> createState() => _PollCardState();
}

class _PollCardState extends State<PollCard> {
  final _controller = StreamController<Map<String, int>>();
  Timer? _timer;

  bool _loading = false;
  bool _voting = false;

  @override
  void initState() {
    super.initState();
    _load();

    // Task 18
    _timer = Timer.periodic(
      const Duration(seconds: 3),
      (_) => _load(),
    );
  }

  Future<void> _load() async {
    if (_loading || _controller.isClosed) return;

    _loading = true;

    try {
      final counts = await fetchVoteCounts();

      if (!_controller.isClosed) {
        _controller.add(counts);
      }
    } catch (error) {
      if (!_controller.isClosed) {
        _controller.addError(error);
      }
    } finally {
      _loading = false;
    }
  }

  Future<void> _vote(String option) async {
    if (_voting) return;

    setState(() => _voting = true);

    try {
      await vote(option);
      await _load();

      if (mounted) {
        feedback(context, 'Votuat: $option');
      }
    } catch (error) {
      if (mounted) {
        feedback(context, errorText(error));
      }
    } finally {
      if (mounted) {
        setState(() => _voting = false);
      }
    }
  }

  // Task 18
  @override
  void dispose() {
    _timer?.cancel();
    _controller.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Cilin aktivitet preferoni?',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            StreamBuilder<Map<String, int>>(
              stream: _controller.stream,
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Column(
                    children: [
                      Text(errorText(snapshot.error!)),
                      TextButton(
                        onPressed: _load,
                        child: const Text('Provo përsëri'),
                      ),
                    ],
                  );
                }

                if (!snapshot.hasData) {
                  return const Center(
                    child: CircularProgressIndicator(),
                  );
                }

                final counts = snapshot.data!;
                final total = counts.values.fold<int>(
                  0,
                  (sum, count) => sum + count,
                );

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final option in pollOptions)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Column(
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(option),
                                ),
                                Text('${counts[option] ?? 0}'),
                                TextButton(
                                  onPressed:
                                      _voting ? null : () => _vote(option),
                                  child: const Text('Voto'),
                                ),
                              ],
                            ),
                            LinearProgressIndicator(
                              value: total == 0
                                  ? 0
                                  : (counts[option] ?? 0) / total,
                            ),
                          ],
                        ),
                      ),
                    Text('Gjithsej: $total vota'),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
