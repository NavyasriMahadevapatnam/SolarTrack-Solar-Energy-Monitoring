import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'firebase_options.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  runApp(const SolarTrackApp());
}

class SolarTrackApp extends StatelessWidget {
  const SolarTrackApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'SolarTrack',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF16865B),
        ),
        scaffoldBackgroundColor: const Color(0xFFF5F8F6),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFFF5F8F6),
        ),
        inputDecorationTheme: const InputDecorationTheme(
          border: OutlineInputBorder(),
        ),
      ),
      home: const AuthGate(),
    );
  }
}

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        if (snapshot.data != null) {
          return SolarHome(key: ValueKey(snapshot.data!.uid));
        }

        return const LoginPage();
      },
    );
  }
}

// ---------------- LOGIN AND REGISTRATION ----------------

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final email = TextEditingController();
  final password = TextEditingController();

  bool isRegister = false;
  bool loading = false;
  String error = '';

  Future<void> submit() async {
    if (email.text.trim().isEmpty || password.text.isEmpty) {
      setState(() => error = 'Enter your email and password.');
      return;
    }

    if (isRegister && password.text.length < 6) {
      setState(() => error = 'Password must be at least 6 characters.');
      return;
    }

    setState(() {
      loading = true;
      error = '';
    });

    try {
      if (isRegister) {
        final result =
            await FirebaseAuth.instance.createUserWithEmailAndPassword(
          email: email.text.trim(),
          password: password.text,
        );

        await FirebaseFirestore.instance
            .collection('users')
            .doc(result.user!.uid)
            .set({
          'name': email.text.trim().split('@').first,
          'capacity': 5.0,
          'rate': 8.0,
          'batteryCapacity': 10.0,
          'createdAt': FieldValue.serverTimestamp(),
        });
      } else {
        await FirebaseAuth.instance.signInWithEmailAndPassword(
          email: email.text.trim(),
          password: password.text,
        );
      }
    } on FirebaseAuthException catch (e) {
      if (mounted) {
        setState(() => error = '${e.code}: ${e.message}');
      }
    } catch (e) {
      if (mounted) {
        setState(() => error = 'Error: $e');
      }
    } finally {
      if (mounted) {
        setState(() => loading = false);
      }
    }
  }

  @override
  void dispose() {
    email.dispose();
    password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: SizedBox(
            width: 410,
            child: Card(
              elevation: 0,
              child: Padding(
                padding: const EdgeInsets.all(26),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Icon(
                      Icons.wb_sunny_rounded,
                      color: Color(0xFF16865B),
                      size: 70,
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'SolarTrack',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 32,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const Text(
                      'Your solar energy, at a glance.',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 28),
                    TextField(
                      controller: email,
                      keyboardType: TextInputType.emailAddress,
                      decoration: const InputDecoration(
                        labelText: 'Email address',
                        prefixIcon: Icon(Icons.email_outlined),
                      ),
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: password,
                      obscureText: true,
                      decoration: const InputDecoration(
                        labelText: 'Password (6+ characters)',
                        prefixIcon: Icon(Icons.lock_outline),
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (error.isNotEmpty)
                      Text(
                        error,
                        style: const TextStyle(color: Colors.red),
                      ),
                    const SizedBox(height: 12),
                    FilledButton(
                      onPressed: loading ? null : submit,
                      child: Text(
                        loading
                            ? 'Please wait...'
                            : isRegister
                                ? 'Create account'
                                : 'Login',
                      ),
                    ),
                    TextButton(
                      onPressed: () {
                        setState(() {
                          isRegister = !isRegister;
                          error = '';
                        });
                      },
                      child: Text(
                        isRegister
                            ? 'Already registered? Login'
                            : 'New user? Create an account',
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------- MAIN APPLICATION ----------------

class SolarHome extends StatefulWidget {
  const SolarHome({super.key});

  @override
  State<SolarHome> createState() => _SolarHomeState();
}

class _SolarHomeState extends State<SolarHome> {
  final db = FirebaseFirestore.instance;
  final random = Random();

  int selectedTab = 0;
  bool busy = false;
  bool settingsLoading = true;

  String userName = 'Solar User';

  double capacity = 5;
  double rate = 8;
  double batteryCapacity = 10;

  double power = 2.8;
  double battery = 72;
  double todayEnergy = 0;
  double todaySavings = 0;
  double todayCO2 = 0;

  Timer? timer;

  // Time when the previous reading interval ended.
  DateTime lastSaved = DateTime.now();

  User get user => FirebaseAuth.instance.currentUser!;

  DocumentReference<Map<String, dynamic>> get profile =>
      db.collection('users').doc(user.uid);

  CollectionReference<Map<String, dynamic>> get readings =>
      profile.collection('readings');

  @override
  void initState() {
    super.initState();
    loadSettings();
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  Future<void> loadSettings() async {
    try {
      final doc = await profile.get();

      if (doc.exists) {
        final data = doc.data()!;

        userName = data['name'] ?? userName;
        capacity = (data['capacity'] as num?)?.toDouble() ?? capacity;
        rate = (data['rate'] as num?)?.toDouble() ?? rate;
        batteryCapacity =
            (data['batteryCapacity'] as num?)?.toDouble() ?? batteryCapacity;
      } else {
        await profile.set({
          'name': user.email?.split('@').first ?? 'Solar User',
          'capacity': capacity,
          'rate': rate,
          'batteryCapacity': batteryCapacity,
          'createdAt': FieldValue.serverTimestamp(),
        });
      }

      // Start a fresh interval when monitoring begins.
      lastSaved = DateTime.now();

      await calculateToday();

      if (mounted) {
        setState(() => settingsLoading = false);
        startMonitoring();
      }
    } catch (e) {
      if (mounted) {
        setState(() => settingsLoading = false);
        showMessage('Could not load profile: $e');
      }
    }
  }

  Future<void> calculateToday() async {
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day);

    final snapshot = await readings
        .where(
          'recordedAt',
          isGreaterThanOrEqualTo: Timestamp.fromDate(start),
        )
        .get();

    double total = 0;

    for (final doc in snapshot.docs) {
      total += (doc.data()['energyKwh'] as num?)?.toDouble() ?? 0;
    }

    todayEnergy = total;
    todaySavings = total * rate;
    todayCO2 = total * 0.7;
  }

  // Update simulated power every 5 seconds.
  // Save an energy reading approximately every 30 seconds.
  void startMonitoring() {
    timer?.cancel();

    timer = Timer.periodic(const Duration(seconds: 5), (t) {
      if (!mounted) return;

      setState(() {
        power = capacity * (0.25 + random.nextDouble() * 0.65);

        battery = min(
          100,
          max(10, battery + random.nextDouble() * 2 - 0.7),
        );
      });

      if (DateTime.now().difference(lastSaved).inSeconds >= 30) {
        saveReading();
      }
    });
  }

  // Save energy based on the actual elapsed time.
  // Power is measured in kW, time in hours, and energy in kWh.
  Future<bool> saveReading() async {
    if (busy) return false;

    busy = true;

    try {
      final readingTime = DateTime.now();
      final elapsedSeconds = readingTime.difference(lastSaved).inSeconds;

      // Avoid negative time if the device clock changes.
      final safeSeconds = max(0, elapsedSeconds);

      // Energy (kWh) = Power (kW) x Time (hours).
      final energy = power * (safeSeconds / 3600.0);

      await readings.add({
        'powerKw': double.parse(power.toStringAsFixed(2)),
        'energyKwh': double.parse(energy.toStringAsFixed(4)),
        'batteryPercent': double.parse(battery.toStringAsFixed(1)),
        'recordedAt': FieldValue.serverTimestamp(),
        'source': 'simulated',
        'intervalSeconds': safeSeconds,
      });

      // Reset the interval only after the Firebase write succeeds.
      lastSaved = readingTime;

      await calculateToday();

      if (mounted) {
        setState(() {});
      }

      return true;
    } catch (e) {
      if (mounted) {
        showMessage('Could not save reading: $e');
      }

      return false;
    } finally {
      busy = false;
    }
  }

  Future<void> recordNow() async {
    final saved = await saveReading();

    if (!mounted) return;

    if (saved) {
      showMessage('Reading saved to Firebase.');
    }
  }

  Future<void> saveSettings(
    String name,
    double newCapacity,
    double newRate,
    double newBatteryCapacity,
  ) async {
    if (name.trim().isEmpty ||
        newCapacity <= 0 ||
        newRate < 0 ||
        newBatteryCapacity <= 0) {
      showMessage('Please enter valid settings.');
      return;
    }

    try {
      await profile.set({
        'name': name.trim(),
        'capacity': newCapacity,
        'rate': newRate,
        'batteryCapacity': newBatteryCapacity,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      if (!mounted) return;

      setState(() {
        userName = name.trim();
        capacity = newCapacity;
        rate = newRate;
        batteryCapacity = newBatteryCapacity;
        power = min(power, capacity);
        todaySavings = todayEnergy * rate;
      });

      showMessage('Settings saved successfully.');
    } catch (e) {
      showMessage('Could not save settings: $e');
    }
  }

  void showMessage(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (settingsLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final pages = [
      dashboard(),
      historyPage(),
      settingsPage(),
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Row(
          children: [
            Icon(
              Icons.wb_sunny_rounded,
              color: Color(0xFF16865B),
            ),
            SizedBox(width: 8),
            Text(
              'SolarTrack',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Logout',
            onPressed: () => FirebaseAuth.instance.signOut(),
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: IndexedStack(
        index: selectedTab,
        children: pages,
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: selectedTab,
        onDestinationSelected: (index) {
          setState(() => selectedTab = index);
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.dashboard_outlined),
            selectedIcon: Icon(Icons.dashboard),
            label: 'Dashboard',
          ),
          NavigationDestination(
            icon: Icon(Icons.history),
            label: 'History',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            label: 'Settings',
          ),
        ],
      ),
    );
  }

  // ---------------- DASHBOARD ----------------

  Widget dashboard() {
    return ListView(
      padding: const EdgeInsets.all(18),
      children: [
        Text(
          'Hello, $userName 👋',
          style: const TextStyle(
            fontSize: 25,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 5),
        const Text(
          'Here is your solar energy overview.',
          style: TextStyle(color: Colors.black54),
        ),
        const SizedBox(height: 18),

        // Current power card.
        Container(
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            color: const Color(0xFF126B4A),
            borderRadius: BorderRadius.circular(22),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(Icons.bolt, color: Colors.white),
                  SizedBox(width: 8),
                  Text(
                    'CURRENT SOLAR POWER',
                    style: TextStyle(color: Colors.white70),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                '${power.toStringAsFixed(2)} kW',
                style: const TextStyle(
                  fontSize: 36,
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '${(power / capacity * 100).clamp(0, 100).toStringAsFixed(0)}% of your ${capacity.toStringAsFixed(1)} kW system capacity',
                style: const TextStyle(color: Colors.white70),
              ),
              const SizedBox(height: 16),
              LinearProgressIndicator(
                value: (power / capacity).clamp(0, 1),
                minHeight: 8,
                backgroundColor: Colors.white24,
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
              ),
              const SizedBox(height: 12),
              const Text(
                'Simulated monitoring • Refreshes every 5 seconds',
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 16),

        // Dashboard metric cards.
        GridView.count(
          crossAxisCount: MediaQuery.of(context).size.width > 600 ? 4 : 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          childAspectRatio: 1.35,
          children: [
            metricCard(
              'Energy today',
              '${todayEnergy.toStringAsFixed(2)} kWh',
              Icons.solar_power,
              Colors.orange,
            ),
            metricCard(
              'Estimated savings',
              '₹${todaySavings.toStringAsFixed(2)}',
              Icons.currency_rupee,
              Colors.green,
            ),
            metricCard(
              'Battery level',
              '${battery.toStringAsFixed(0)}%',
              Icons.battery_charging_full,
              Colors.blue,
            ),
            metricCard(
              'CO₂ avoided',
              '${todayCO2.toStringAsFixed(2)} kg',
              Icons.eco,
              Colors.teal,
            ),
          ],
        ),

        const SizedBox(height: 20),
        sectionTitle('Recent energy readings'),
        const SizedBox(height: 10),

        Card(
          elevation: 0,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: readings
                  .orderBy('recordedAt', descending: true)
                  .limit(6)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Text('Readings error: ${snapshot.error}');
                }

                if (!snapshot.hasData) {
                  return const Center(
                    child: CircularProgressIndicator(),
                  );
                }

                final docs = snapshot.data!.docs;

                if (docs.isEmpty) {
                  return const Text(
                    'Your readings will appear here as monitoring runs.',
                  );
                }

                return Column(
                  children: [
                    for (final doc in docs)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const CircleAvatar(
                          backgroundColor: Color(0xFFE1F3E9),
                          child: Icon(
                            Icons.bolt,
                            color: Color(0xFF16865B),
                          ),
                        ),
                        title: Text(
                          '${((doc.data()['powerKw'] as num?)?.toDouble() ?? 0).toStringAsFixed(2)} kW',
                        ),
                        subtitle: Text(
                          '${((doc.data()['energyKwh'] as num?)?.toDouble() ?? 0).toStringAsFixed(4)} kWh produced',
                        ),
                        trailing: const Icon(Icons.check_circle_outline),
                      ),
                  ],
                );
              },
            ),
          ),
        ),

        const SizedBox(height: 16),

        // SDG information.
        Card(
          elevation: 0,
          child: ListTile(
            leading: const Icon(
              Icons.public,
              color: Colors.green,
              size: 35,
            ),
            title: const Text('UN Sustainable Development Goal 7'),
            subtitle: const Text(
              'Affordable and Clean Energy — monitor renewable energy production and understand its environmental impact.',
            ),
          ),
        ),

        const SizedBox(height: 12),

        FilledButton.icon(
          onPressed: busy ? null : recordNow,
          icon: const Icon(Icons.save_alt),
          label: const Text('Record reading now'),
        ),

        const SizedBox(height: 8),

        const Text(
          'Demo data only. Connect compatible solar hardware for real measurements.',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 11,
            color: Colors.black54,
          ),
        ),
      ],
    );
  }

  Widget metricCard(
    String title,
    String value,
    IconData icon,
    Color color,
  ) {
    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: color, size: 26),
            const SizedBox(height: 10),
            Text(
              value,
              style: const TextStyle(
                fontSize: 19,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              title,
              style: const TextStyle(
                fontSize: 12,
                color: Colors.black54,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget sectionTitle(String text) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 20,
        fontWeight: FontWeight.bold,
      ),
    );
  }

  // ---------------- HISTORY ----------------

  Widget historyPage() {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: readings.orderBy('recordedAt', descending: true).snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
            child: Text('History error: ${snapshot.error}'),
          );
        }

        if (!snapshot.hasData) {
          return const Center(
            child: CircularProgressIndicator(),
          );
        }

        final docs = snapshot.data!.docs;

        final total = docs.fold<double>(
          0,
          (sum, doc) =>
              sum + ((doc.data()['energyKwh'] as num?)?.toDouble() ?? 0),
        );

        return ListView(
          padding: const EdgeInsets.all(18),
          children: [
            sectionTitle('Energy history'),
            const SizedBox(height: 6),
            const Text('All readings saved to your Firebase account.'),
            const SizedBox(height: 16),
            Card(
              elevation: 0,
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Total energy in saved readings'),
                    const SizedBox(height: 8),
                    Text(
                      '${total.toStringAsFixed(3)} kWh',
                      style: const TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text('${docs.length} saved records'),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 14),
            if (docs.isEmpty)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'No history yet. Start monitoring to collect readings.',
                ),
              ),
            for (final doc in docs)
              Card(
                elevation: 0,
                child: ListTile(
                  leading: const CircleAvatar(
                    child: Icon(Icons.solar_power),
                  ),
                  title: Text(
                    '${((doc.data()['energyKwh'] as num?)?.toDouble() ?? 0).toStringAsFixed(4)} kWh',
                  ),
                  subtitle: Text(
                    'Power: ${((doc.data()['powerKw'] as num?)?.toDouble() ?? 0).toStringAsFixed(2)} kW\n'
                    '${formatTime(doc.data()['recordedAt'])}',
                  ),
                  isThreeLine: true,
                ),
              ),
          ],
        );
      },
    );
  }

  String formatTime(dynamic value) {
    if (value is Timestamp) {
      return value.toDate().toLocal().toString().substring(0, 16);
    }

    return 'Saving timestamp...';
  }

  // ---------------- SETTINGS ----------------

  Widget settingsPage() {
    return SettingsForm(
      name: userName,
      capacity: capacity,
      rate: rate,
      batteryCapacity: batteryCapacity,
      onSave: saveSettings,
    );
  }
}

// ---------------- SETTINGS FORM ----------------

class SettingsForm extends StatefulWidget {
  final String name;
  final double capacity;
  final double rate;
  final double batteryCapacity;

  final Future<void> Function(
    String,
    double,
    double,
    double,
  ) onSave;

  const SettingsForm({
    super.key,
    required this.name,
    required this.capacity,
    required this.rate,
    required this.batteryCapacity,
    required this.onSave,
  });

  @override
  State<SettingsForm> createState() => _SettingsFormState();
}

class _SettingsFormState extends State<SettingsForm> {
  late final TextEditingController name;
  late final TextEditingController capacity;
  late final TextEditingController rate;
  late final TextEditingController batteryCapacity;

  bool saving = false;

  @override
  void initState() {
    super.initState();

    name = TextEditingController(text: widget.name);
    capacity = TextEditingController(text: widget.capacity.toString());
    rate = TextEditingController(text: widget.rate.toString());
    batteryCapacity =
        TextEditingController(text: widget.batteryCapacity.toString());
  }

  @override
  void dispose() {
    name.dispose();
    capacity.dispose();
    rate.dispose();
    batteryCapacity.dispose();
    super.dispose();
  }

  Future<void> save() async {
    final c = double.tryParse(capacity.text);
    final r = double.tryParse(rate.text);
    final b = double.tryParse(batteryCapacity.text);

    if (c == null ||
        r == null ||
        b == null ||
        c <= 0 ||
        r < 0 ||
        b <= 0 ||
        name.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Enter valid settings values.'),
        ),
      );
      return;
    }

    setState(() => saving = true);

    try {
      await widget.onSave(
        name.text,
        c,
        r,
        b,
      );
    } finally {
      if (mounted) {
        setState(() => saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(18),
      children: [
        const Text(
          'System settings',
          style: TextStyle(
            fontSize: 25,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 6),
        const Text('Personalise your solar system.'),
        const SizedBox(height: 20),
        TextField(
          controller: name,
          decoration: const InputDecoration(
            labelText: 'Your name',
            prefixIcon: Icon(Icons.person_outline),
          ),
        ),
        const SizedBox(height: 14),
        TextField(
          controller: capacity,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(
            labelText: 'Solar panel capacity (kW)',
            prefixIcon: Icon(Icons.solar_power),
          ),
        ),
        const SizedBox(height: 14),
        TextField(
          controller: rate,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(
            labelText: 'Electricity price (₹ per kWh)',
            prefixIcon: Icon(Icons.currency_rupee),
          ),
        ),
        const SizedBox(height: 14),
        TextField(
          controller: batteryCapacity,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(
            labelText: 'Battery capacity (kWh)',
            prefixIcon: Icon(Icons.battery_charging_full),
          ),
        ),
        const SizedBox(height: 20),
        FilledButton.icon(
          onPressed: saving ? null : save,
          icon: const Icon(Icons.save),
          label: Text(saving ? 'Saving...' : 'Save settings'),
        ),
        const SizedBox(height: 20),
        const Card(
          elevation: 0,
          child: Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              'How estimates work\n\n'
              '• Savings = saved energy × your electricity price.\n'
              '• Avoided CO₂ is estimated at 0.7 kg per kWh.\n'
              '• Power, battery and generated energy are simulated for this demo.\n\n'
              'Actual output and savings depend on your location, weather, '
              'system efficiency and electricity tariff.',
            ),
          ),
        ),
      ],
    );
  }
}
