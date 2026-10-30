import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'history_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int water = 0;
  int goal = 2000;

  @override
  void initState() {
    super.initState();
    loadWater();
  }

  // Load saved water from phone
  void loadWater() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();

    setState(() {
      water = prefs.getInt('water') ?? 0;
    });
  }

  // Save water to phone
  void saveWater() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    prefs.setInt('water', water);
  }

  // Add water
  void addWater(int amount) {
    setState(() {
      water = water + amount;
    });

    saveWater();
  }

  // Reset water
  void resetWater() {
    setState(() {
      water = 0;
    });

    saveWater();
  }

  @override
  Widget build(BuildContext context) {
    double progress = water / goal;

    if (progress > 1) {
      progress = 1;
    }

    int remaining = goal - water;

    if (remaining < 0) {
      remaining = 0;
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Water Tracker'),
        centerTitle: true,
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            const SizedBox(height: 20),
            const Icon(
              Icons.water_drop,
              size: 80,
              color: Colors.blue,
            ),
            const SizedBox(height: 10),
            const Text(
              'Daily Water Intake',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              '$water ml / $goal ml',
              style: const TextStyle(
                fontSize: 28,
                color: Colors.blue,
              ),
            ),
            const SizedBox(height: 20),
            LinearProgressIndicator(
              value: progress,
              minHeight: 15,
            ),
            const SizedBox(height: 15),
            Text(
              '$remaining ml remaining',
              style: const TextStyle(fontSize: 18),
            ),
            const SizedBox(height: 30),
            const Text(
              'Add Water',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 15),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                ElevatedButton(
                  onPressed: () {
                    addWater(250);
                  },
                  child: const Text('250 ml'),
                ),
                ElevatedButton(
                  onPressed: () {
                    addWater(500);
                  },
                  child: const Text('500 ml'),
                ),
                ElevatedButton(
                  onPressed: () {
                    addWater(750);
                  },
                  child: const Text('750 ml'),
                ),
              ],
            ),
            const SizedBox(height: 30),
            ElevatedButton(
              onPressed: resetWater,
              child: const Text('Reset Today'),
            ),
            const SizedBox(height: 15),
            OutlinedButton(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const HistoryPage(),
                  ),
                );
              },
              child: const Text('View History'),
            ),
          ],
        ),
      ),
    );
  }
}
