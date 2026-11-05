
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';

const String apiBase = String.fromEnvironment(
  'API_BASE_URL',
  defaultValue: 'http://10.0.2.2:3000/api',
);

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const NexusBankApp());
}

// ============================================================
// CONFIGURAÇÃO E COMUNICAÇÃO COM O SERVIDOR
// ============================================================

class NexusApi {
  NexusApi._();

  static final NexusApi instance = NexusApi._();

  final HttpClient _client = HttpClient()
    ..connectionTimeout = const Duration(seconds: 15);

  String? token;

  Uri _uri(String path) {
    final base = apiBase.replaceAll(RegExp(r'/+$'), '');
    return Uri.parse('$base$path');
  }

  Future<dynamic> request(
    String method,
    String path, {
    Map<String, dynamic>? body,
    bool authenticated = true,
  }) async {
    final uri = _uri(path);
    final HttpClientRequest req;

    switch (method) {
      case 'POST':
        req = await _client.postUrl(uri);
        break;
      case 'PATCH':
        req = await _client.patchUrl(uri);
        break;
      case 'GET':
      default:
        req = await _client.getUrl(uri);
    }

    req.headers.set(HttpHeaders.acceptHeader, 'application/json');
    req.headers.set(HttpHeaders.contentTypeHeader, 'application/json');

    if (authenticated && token != null) {
      req.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
    }

    if (body != null) {
      req.add(utf8.encode(jsonEncode(body)));
    }

    final response = await req.close().timeout(
      const Duration(seconds: 25),
    );

    final responseText = await response.transform(utf8.decoder).join();

    dynamic data;
    if (responseText.trim().isNotEmpty) {
      try {
        data = jsonDecode(responseText);
      } catch (_) {
        data = {'message': responseText};
      }
    } else {
      data = <String, dynamic>{};
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      String message =
          'Erro ${response.statusCode} na comunicação com o servidor.';

      if (data is Map) {
        message = (
          data['message'] ??
          data['error'] ??
          data['detail'] ??
          message
        ).toString();
      }

      throw Exception(message);
    }

    return data;
  }

  Future<Map<String, dynamic>> login(
    String email,
    String password,
  ) async {
    final result = await request(
      'POST',
      '/auth/login',
      authenticated: false,
      body: {
        'email': email,
        'password': password,
      },
    );

    final map = _asMap(result);
    final receivedToken = map['token'] ??
        _asMap(map['data'])['token'] ??
        _asMap(map['user'])['token'];

    if (receivedToken == null) {
      throw Exception('O servidor não retornou o token de acesso.');
    }

    token = receivedToken.toString();
    return map;
  }

  Future<Map<String, dynamic>> register(
    String name,
    String email,
    String password,
  ) async {
    final result = await request(
      'POST',
      '/auth/register',
      authenticated: false,
      body: {
        'name': name,
        'email': email,
        'password': password,
      },
    );

    final map = _asMap(result);
    final receivedToken = map['token'] ?? _asMap(map['data'])['token'];

    if (receivedToken != null) {
      token = receivedToken.toString();
    }

    return map;
  }

  Future<Map<String, dynamic>> me() async {
    return _asMap(await request('GET', '/me'));
  }

  Future<Map<String, dynamic>> wallet() async {
    return _asMap(await request('GET', '/wallet'));
  }

  Future<List<dynamic>> transactions() async {
    final result = await request('GET', '/transactions');

    if (result is List) return result;

    final map = _asMap(result);
    final data = map['transactions'] ?? map['items'] ?? map['data'] ?? [];

    return data is List ? data : [];
  }

  Future<dynamic> transfer({
    required String email,
    required int amount,
    required String description,
  }) {
    return request(
      'POST',
      '/transfers/internal',
      body: {
        'receiverEmail': email,
        'amount': amount,
        'description': description,
      },
    );
  }

  Future<dynamic> claimReward() {
    return request('POST', '/rewards/claim', body: {});
  }

  Future<Map<String, dynamic>> config() async {
    return _asMap(
      await request(
        'GET',
        '/config',
        authenticated: false,
      ),
    );
  }

  Future<Map<String, dynamic>> adminDashboard() async {
    return _asMap(await request('GET', '/admin/dashboard'));
  }

  Future<List<dynamic>> adminUsers() async {
    final result = await request('GET', '/admin/users');

    if (result is List) return result;

    final map = _asMap(result);
    final data = map['users'] ?? map['items'] ?? map['data'] ?? [];

    return data is List ? data : [];
  }

  Future<dynamic> adminCredit({
    required String userId,
    required int amount,
    required String reason,
  }) {
    return request(
      'POST',
      '/admin/users/${Uri.encodeComponent(userId)}/credits',
      body: {
        'amount': amount,
        'reason': reason,
      },
    );
  }

  Future<dynamic> adminStatus(String userId, bool active) {
    return request(
      'PATCH',
      '/admin/users/${Uri.encodeComponent(userId)}/status',
      body: {'isActive': active},
    );
  }

  Future<dynamic> adminConfig(Map<String, dynamic> values) {
    return request('PATCH', '/admin/config', body: values);
  }

  void logout() {
    token = null;
  }
}

// ============================================================
// FUNÇÕES AUXILIARES
// ============================================================

Map<String, dynamic> _asMap(dynamic value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) return Map<String, dynamic>.from(value);
  return <String, dynamic>{};
}

dynamic _nested(Map<String, dynamic> map, String key) {
  if (map.containsKey(key)) return map[key];

  if (map['data'] is Map && (map['data'] as Map).containsKey(key)) {
    return map['data'][key];
  }

  return null;
}

String _text(dynamic value, [String fallback = '']) {
  if (value == null) return fallback;
  return value.toString();
}

int _number(dynamic value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '') ?? 0;
}

String _errorText(Object error) {
  return error.toString().replaceFirst('Exception: ', '');
}

// ============================================================
// APLICATIVO
// ============================================================

class NexusBankApp extends StatelessWidget {
  const NexusBankApp({super.key});

  @override
  Widget build(BuildContext context) {
    const purple = Color(0xFF7046D8);

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'NEXUS BANK',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: purple,
          primary: purple,
          brightness: Brightness.light,
        ),
        scaffoldBackgroundColor: const Color(0xFFF7F5FC),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFFF7F5FC),
          foregroundColor: Color(0xFF251B3D),
          elevation: 0,
          centerTitle: false,
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(15),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(15),
            borderSide: const BorderSide(
              color: Color(0xFFE8E1F3),
            ),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(15),
            borderSide: const BorderSide(
              color: purple,
              width: 1.5,
            ),
          ),
        ),
      ),
      home: const AuthPage(),
    );
  }
}

// ============================================================
// LOGIN E CADASTRO
// ============================================================

class AuthPage extends StatefulWidget {
  const AuthPage({super.key});

  @override
  State<AuthPage> createState() => _AuthPageState();
}

class _AuthPageState extends State<AuthPage> {
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();

  bool registering = false;
  bool loading = false;
  bool obscure = true;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  void message(String value) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(value)),
    );
  }

  Future<void> submit() async {
    final email = _email.text.trim().toLowerCase();
    final password = _password.text;

    if (registering && _name.text.trim().length < 2) {
      message('Informe seu nome completo.');
      return;
    }

    if (!email.contains('@') || !email.contains('.')) {
      message('Informe um e-mail válido.');
      return;
    }

    if (password.length < 8) {
      message('A senha deve ter pelo menos 8 caracteres.');
      return;
    }

    setState(() => loading = true);

    try {
      if (registering) {
        await NexusApi.instance.register(
          _name.text.trim(),
          email,
          password,
        );

        if (NexusApi.instance.token == null) {
          await NexusApi.instance.login(email, password);
        }
      } else {
        await NexusApi.instance.login(email, password);
      }

      if (!mounted) return;

      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => const HomePage(),
        ),
      );
    } catch (error) {
      message(_errorText(error));
    } finally {
      if (mounted) {
        setState(() => loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 20),
                  Container(
                    height: 88,
                    width: 88,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [
                          Color(0xFF8C62F0),
                          Color(0xFF5631B5),
                        ],
                      ),
                      borderRadius: BorderRadius.circular(27),
                      boxShadow: [
                        BoxShadow(
                          color: const Color.fromRGBO(112, 70, 216, 0.25),
                          blurRadius: 25,
                          offset: const Offset(0, 12),
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.account_balance_rounded,
                      color: Colors.white,
                      size: 45,
                    ),
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    'NEXUS BANK',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 29,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 2,
                      color: Color(0xFF30204F),
                    ),
                  ),
                  const SizedBox(height: 7),
                  const Text(
                    'Sua carteira virtual, em um só lugar.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.black54),
                  ),
                  const SizedBox(height: 36),
                  Text(
                    registering ? 'Criar sua conta' : 'Bem-vindo de volta',
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    registering
                        ? 'Preencha os dados para começar.'
                        : 'Entre para acessar sua carteira virtual.',
                    style: const TextStyle(color: Colors.black54),
                  ),
                  const SizedBox(height: 22),
                  if (registering) ...[
                    TextField(
                      controller: _name,
                      textCapitalization: TextCapitalization.words,
                      decoration: const InputDecoration(
                        labelText: 'Nome completo',
                        prefixIcon: Icon(Icons.person_outline),
                      ),
                    ),
                    const SizedBox(height: 14),
                  ],
                  TextField(
                    controller: _email,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(
                      labelText: 'E-mail',
                      prefixIcon: Icon(Icons.email_outlined),
                    ),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: _password,
                    obscureText: obscure,
                    decoration: InputDecoration(
                      labelText: 'Senha',
                      prefixIcon: const Icon(Icons.lock_outline),
                      suffixIcon: IconButton(
                        onPressed: () {
                          setState(() => obscure = !obscure);
                        },
                        icon: Icon(
                          obscure
                              ? Icons.visibility
                              : Icons.visibility_off,
                        ),
                      ),
                    ),
                    onSubmitted: (_) => submit(),
                  ),
                  const SizedBox(height: 22),
                  FilledButton(
                    onPressed: loading ? null : submit,
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(54),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(15),
                      ),
                    ),
                    child: loading
                        ? const SizedBox(
                            height: 22,
                            width: 22,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : Text(registering ? 'CRIAR CONTA' : 'ENTRAR'),
                  ),
                  const SizedBox(height: 12),
                  TextButton(
                    onPressed: loading
                        ? null
                        : () {
                            setState(() {
                              registering = !registering;
                            });
                          },
                    child: Text(
                      registering
                          ? 'Já tenho uma conta. Entrar'
                          : 'Ainda não tenho conta. Criar cadastro',
                    ),
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    'Ambiente de demonstração com créditos virtuais NX. '
                    'Os NX não representam dinheiro real.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.black45,
                    ),
                  ),
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
// TELA PRINCIPAL E NAVEGAÇÃO
// ============================================================

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int selected = 0;
  bool loading = true;

  String userName = 'Usuário';
  String userRole = 'USER';

  Map<String, dynamic> walletData = {};
  Map<String, dynamic> userData = {};
  List<dynamic> history = [];
  Map<String, dynamic> configData = {};

  @override
  void initState() {
    super.initState();
    refreshAll();
  }

  int get balance {
    final wallet = _asMap(
      _nested(walletData, 'wallet') ?? walletData,
    );

    return _number(
      wallet['balance'] ?? walletData['balance'],
    );
  }

  bool get isAdmin {
    return userRole.toUpperCase() == 'ADMIN' ||
        _text(userData['role']).toUpperCase() == 'ADMIN';
  }

  Future<void> refreshAll() async {
    if (mounted) {
      setState(() => loading = true);
    }

    try {
      final results = await Future.wait<dynamic>([
        NexusApi.instance.me(),
        NexusApi.instance.wallet(),
        NexusApi.instance.transactions(),
        NexusApi.instance.config(),
      ]);

      if (!mounted) return;

      userData = _asMap(results[0]);

      final user = _asMap(
        _nested(userData, 'user') ?? userData,
      );

      userName = _text(user['name'], 'Usuário');
      userRole = _text(user['role'], 'USER');

      walletData = _asMap(results[1]);
      history = results[2] as List<dynamic>;
      configData = _asMap(results[3]);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_errorText(error))),
        );
      }
    } finally {
      if (mounted) {
        setState(() => loading = false);
      }
    }
  }

  void logout() {
    NexusApi.instance.logout();

    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(
        builder: (_) => const AuthPage(),
      ),
      (_) => false,
    );
  }

  void openTransfer() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => TransferPage(
          onDone: refreshAll,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pages = <Widget>[
      DashboardPage(
        name: userName,
        balance: balance,
        history: history,
        config: configData,
        loading: loading,
        onRefresh: refreshAll,
        onTransfer: openTransfer,
      ),
      HistoryPage(
        items: history,
        loading: loading,
        onRefresh: refreshAll,
      ),
      const AssistantPage(),
      const HelpPage(),
      if (isAdmin) AdminPage(onRefresh: refreshAll),
    ];

    final destinations = <NavigationDestination>[
      const NavigationDestination(
        icon: Icon(Icons.account_balance_wallet_outlined),
        selectedIcon: Icon(Icons.account_balance_wallet),
        label: 'Carteira',
      ),
      const NavigationDestination(
        icon: Icon(Icons.receipt_long_outlined),
        selectedIcon: Icon(Icons.receipt_long),
        label: 'Histórico',
      ),
      const NavigationDestination(
        ico