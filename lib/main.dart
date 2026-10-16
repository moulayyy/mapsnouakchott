import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import 'config.dart';
import 'repo.dart';
import 'screens/auth_page.dart';
import 'screens/shell.dart';
import 'services.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  runApp(const MapsApp());
}

class MapsApp extends StatelessWidget {
  const MapsApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: AppConfig.appName,
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: const Color(0xFF2E6B7B),
        useMaterial3: true,
      ),
      home: const Gate(),
    );
  }
}

class Gate extends StatelessWidget {
  const Gate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        final user = snap.data;
        if (user == null) return const AuthPage();
        return Loader(key: ValueKey(user.uid), user: user);
      },
    );
  }
}

class Loader extends StatefulWidget {
  final User user;
  const Loader({super.key, required this.user});

  @override
  State<Loader> createState() => _LoaderState();
}

class _LoaderState extends State<Loader> {
  late Future<void> _f;

  @override
  void initState() {
    super.initState();
    _f = _load();
  }

  Future<void> _load() async {
    final admin = await AuthService.isAdmin(widget.user.uid);
    await repo.load(admin: admin);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<void>(
      future: _f,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Scaffold(
            body: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('Chargement de la carte…'),
                ],
              ),
            ),
          );
        }
        if (snap.hasError) {
          return Scaffold(
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.error_outline, size: 48),
                    const SizedBox(height: 12),
                    Text('${snap.error}', textAlign: TextAlign.center),
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: () => setState(() => _f = _load()),
                      child: const Text('Réessayer'),
                    ),
                    TextButton(
                      onPressed: AuthService.signOut,
                      child: const Text('Se déconnecter'),
                    ),
                  ],
                ),
              ),
            ),
          );
        }
        return const Shell();
      },
    );
  }
}
