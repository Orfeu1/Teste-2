umimport 'dart:async';
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
    final text = await response.transform(utf8.decoder).join();

    dynamic data;
    if (text.trim().isNotEmpty) {
      try {
        data = jsonDecode(text);
      } catch (_) {
        data = {'message': text};
      }
    } else {
      data = <String, dynamic>{};
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      String message = 'Erro ${response.statusCode} na comunicação com o servidor.';
      if (data is Map) {
        message = (data['message'] ??
                data['error'] ??
                data['detail'] ??
                message)
            .toString();
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
      body: {'email': email, 'password': password},
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

  Future<Map<String, dynamic>> me() async =>
      _asMap(await request('GET', '/me'));

  Future<Map<String, dynamic>> wallet() async =>
      _asMap(await request('GET', '/wallet'));

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

  Future<dynamic> claimReward() =>
      request('POST', '/rewards/claim', body: {});

  Future<Map<String, dynamic>> config() async =>
      _asMap(await request('GET', '/config', authenticated: false));

  Future<Map<String, dynamic>> adminDashboard() async =>
      _asMap(await request('GET', '/admin/dashboard'));

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
      body: {'amount': amount, 'reason': reason},
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
            borderSide: const BorderSide(color: Color(0xFFE8E1F3)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(15),
            borderSide: const BorderSide(color: purple, width: 1.5),
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
        MaterialPageRoute(builder: (_) => const HomePage()),
      );
    } catch (error) {
      message(_errorText(error));
    } finally {
      if (mounted) setState(() => loading = false);
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
                        colors: [Color(0xFF8C62F0), Color(0xFF5631B5)],
                      ),
                      borderRadius: BorderRadius.circular(27),
                      boxShadow: [
                        BoxShadow(
                    color: const Color(0xFF7046D8).withValues(alpha: 0.25),
                    blurRadius: 25,
                    offset: const Offset(0, 12),
                  ),
                                                                                           ],
                    child: const Icon(
                      Icons.account_balance_rounded,
                      color: Colors.white,
                      size: 45,
                    ),
                  ),
                  decoration: BoxDecoration(
  gradient: const LinearGradient(
    colors: [Color(0xFF8C62F0), Color(0xFF5631B5)],
  ),
  borderRadius: BorderRadius.circular(27),
  boxShadow: [
    BoxShadow(
      color: const Color(0xFF7046D8).withValues(alpha: 0.25),
      blurRadius: 25,
      offset: const Offset(0, 12),
    ),
  ],
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
                        onPressed: () => setState(() => obscure = !obscure),
                        icon: Icon(
                          obscure ? Icons.visibility : Icons.visibility_off,
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
                        : () => setState(() => registering = !registering),
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
                    style: TextStyle(fontSize: 12, color: Colors.black45),
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
    final wallet = _asMap(_nested(walletData, 'wallet') ?? walletData);
    return _number(wallet['balance'] ?? walletData['balance']);
  }

  bool get isAdmin =>
      userRole.toUpperCase() == 'ADMIN' ||
      _text(userData['role']).toUpperCase() == 'ADMIN';

  Future<void> refreshAll() async {
    if (mounted) setState(() => loading = true);

    try {
      final results = await Future.wait([
        NexusApi.instance.me(),
        NexusApi.instance.wallet(),
        NexusApi.instance.transactions(),
        NexusApi.instance.config(),
      ]);

      if (!mounted) return;

      userData = _asMap(results[0]);
      final user = _asMap(_nested(userData, 'user') ?? userData);
      userName = _text(user['name'], 'Usuário');
      userRole = _text(user['role'], 'USER');

      walletData = _asMap(results[1]);
      history = results[2] as List<dynamic>;
      configData = results[3] as Map<String, dynamic>;
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_errorText(error))),
        );
      }
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  void logout() {
    NexusApi.instance.logout();
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const AuthPage()),
      (_) => false,
    );
  }

  void openTransfer() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => TransferPage(onDone: refreshAll),
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
      HistoryPage(items: history, loading: loading, onRefresh: refreshAll),
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
        icon: Icon(Icons.smart_toy_outlined),
        selectedIcon: Icon(Icons.smart_toy),
        label: 'Assistente',
      ),
      const NavigationDestination(
        icon: Icon(Icons.help_outline),
        selectedIcon: Icon(Icons.help),
        label: 'Ajuda',
      ),
      if (isAdmin)
        const NavigationDestination(
          icon: Icon(Icons.admin_panel_settings_outlined),
          selectedIcon: Icon(Icons.admin_panel_settings),
          label: 'Admin',
        ),
    ];

    if (selected >= pages.length) selected = 0;

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'NEXUS BANK',
          style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 1),
        ),
        actions: [
          IconButton(
            tooltip: 'Atualizar',
            onPressed: refreshAll,
            icon: const Icon(Icons.refresh),
          ),
          IconButton(
            tooltip: 'Sair',
            onPressed: logout,
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: IndexedStack(
        index: selected,
        children: pages,
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: selected,
        onDestinationSelected: (value) {
          setState(() => selected = value);
        },
        destinations: destinations,
      ),
    );
  }
}

// ============================================================
// CARTEIRA
// ============================================================

class DashboardPage extends StatelessWidget {
  const DashboardPage({
    super.key,
    required this.name,
    required this.balance,😡😡😡😡
    required this.history,
    required this.config,
    required this.loading,
    required this.onRefresh,
    required this.onTransfer,
  });

  final String name;
  final int balance;
  final List<dynamic> history;
  final Map<String, dynamic> config;
  final bool loading;
  final Future<void> Function() onRefresh;
  final VoidCallback onTransfer;

  @override
  Widget build(BuildContext context) {
    final welcome = _text(
      config['welcomeMessage'],
      'Bem-vindo ao NEXUS BANK.',
    );
    final banner = _text(
      config['bannerTitle'],
      'Sua carteira virtual NEXUS',
    );

    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          Text(
            'Olá, $name 👋',
            style: const TextStyle(
              fontSize: 23,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 5),
          Text(welcome, style: const TextStyle(color: Colors.black54)),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(23),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF8A61EA), Color(0xFF4F2CA8)],
              ),
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  withOpacity.
                  blurRadius: 20,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  banner,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 22),
                const Text(
                  'SALDO DISPONÍVEL',
                  style: TextStyle(
                    color: Colors.white70,
                    letterSpacing: 1.2,
                    fontSize: 11,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  loading ? '...' : '$balance NX',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 34,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 18),
                const Text(
                  'Créditos virtuais de demonstração',
                  style: TextStyle(color: Colors.white70, fontSize: 12),
                ),
              ],
            ),
          ),
          const SizedBox(height: 23),
          const Text(
            'Acesso rápido',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 13),
          Row(
            children: [
              Expanded(
                child: _QuickAction(
                  icon: Icons.swap_horiz_rounded,
                  label: 'Transferir NX',
                  onTap: onTransfer,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _QuickAction(
                  icon: Icons.card_giftcard_rounded,
                  label: 'Recompensa',
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const RewardPage(),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _QuickAction(
                  icon: Icons.receipt_long_rounded,
                  label: 'Histórico',
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => HistoryPage(
                          items: history,
                          loading: loading,
                          onRefresh: onRefresh,
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 26),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Movimentações recentes',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              TextButton(
                onPressed: onRefresh,
                child: const Text('Atualizar'),
              ),
            ],
          ),
          if (loading)
            const Padding(
              padding: EdgeInsets.all(25),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (history.isEmpty)
            const _EmptyState(
              icon: Icons.receipt_long_outlined,
              title: 'Nenhuma movimentação',
              subtitle: 'Suas movimentações aparecerão aqui.',
            )
          else
            ...history.take(5).map(
                  (item) => TransactionTile(item: _asMap(item)),
                ),
          const SizedBox(height: 20),
          const Text(
            'NEXUS BANK é uma carteira virtual de teste. NX não possui '
            'valor monetário real e não pode ser sacado ou convertido.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 11, color: Colors.black45),
          ),
        ],
      ),
    );
  }
}

class _QuickAction extends StatelessWidget {
  const _QuickAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(17),
      child: InkWell(
        borderRadius: BorderRadius.circular(17),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 5),
          child: Column(
            children: [
              Icon(icon, color: const Color(0xFF7046D8), size: 27),
              const SizedBox(height: 8),
              Text(
                label,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================================
// HISTÓRICO E ITEM DE TRANSAÇÃO
// ============================================================

class HistoryPage extends StatelessWidget {
  const HistoryPage({
    super.key,
    required this.items,
    required this.loading,
    required this.onRefresh,
  });

  final List<dynamic> items;
  final bool loading;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          const Text(
            'Histórico',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 5),
          const Text(
            'Confira as movimentações da sua carteira virtual.',
            style: TextStyle(color: Colors.black54),
          ),
          const SizedBox(height: 18),
          if (loading)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(30),
                child: CircularProgressIndicator(),
              ),
            )
          else if (items.isEmpty)
            const _EmptyState(
              icon: Icons.history,
              title: 'Sem movimentações',
              subtitle: 'Quando houver movimentações, elas aparecerão aqui.',
            )
          else
            ...items.map(
              (item) => TransactionTile(item: _asMap(item)),
            ),
        ],
      ),
    );
  }
}

class TransactionTile extends StatelessWidget {
  const TransactionTile({super.key, required this.item});

  final Map<String, dynamic> item;

  @override
  Widget build(BuildContext context) {
    final amount = _number(item['amount'] ?? item['valor']);
    final description = _text(
      item['description'] ?? item['descricao'],
      'Movimentação',
    );
    final date = _text(item['createdAt'] ?? item['data']);
    final type = _text(item['type']).toUpperCase();
    final direction = _text(item['direction']).toUpperCase();

    final outgoing = direction == 'OUT' ||
        direction == 'SENT' ||
        type == 'TRANSFER_OUT';

    final icon = type == 'REWARD'
        ? Icons.card_giftcard
        : type == 'ADMIN_CREDIT'
            ? Icons.add_circle_outline
            : Icons.swap_horiz;

    return Card(
      color: Colors.white,
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(15),
        side: const BorderSide(color: Color(0xFFEDE8F4)),
      ),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: const Color(0xFFF0EAFE),
          child: Icon(icon, color: const Color(0xFF7046D8)),
        ),
        title: Text(
          description,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Text(date.isEmpty ? 'Data não informada' : date),
        trailing: Text(
          '${outgoing ? '-' : '+'}$amount NX',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: outgoing ? Colors.red.shade700 : Colors.green.shade700,
          ),
        ),
      ),
    );
  }
}

// ============================================================
// TRANSFERÊNCIA INTERNA
// ============================================================

class TransferPage extends StatefulWidget {
  const TransferPage({super.key, required this.onDone});

  final Future<void> Function() onDone;

  @override
  State<TransferPage> createState() => _TransferPageState();
}

class _TransferPageState extends State<TransferPage> {
  final email = TextEditingController();
  final amount = TextEditingController();
  final description = TextEditingController();

  bool sending = false;

  @override
  void dispose() {
    email.dispose();
    amount.dispose();
    description.dispose();
    super.dispose();
  }

  Future<void> send() async {
    final value = int.tryParse(amount.text.trim());

    if (!email.text.trim().contains('@')) {
      _show('Informe o e-mail da conta que receberá os NX.');
      return;
    }
    if (value == null || value <= 0) {
      _show('Informe uma quantidade válida de NX.');
      return;
    }

    setState(() => sending = true);

    try {
      await NexusApi.instance.transfer(
        email: email.text.trim().toLowerCase(),
        amount: value,
        description: description.text.trim().isEmpty
            ? 'Transferência interna NX'
            : description.text.trim(),
      );

      await widget.onDone();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Transferência realizada com sucesso.')),
      );
      Navigator.pop(context);
    } catch (error) {
      _show(_errorText(error));
    } finally {
      if (mounted) setState(() => sending = false);
    }
  }

  void _show(String value) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(value)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Transferir NX')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Icon(
            Icons.swap_horiz_rounded,
            size: 65,
            color: Color(0xFF7046D8),
          ),
          const SizedBox(height: 12),
          const Text(
            'Transferência interna',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 23, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          const Text(
            'Envie créditos virtuais para outra conta NEXUS BANK.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.black54),
          ),
          const SizedBox(height: 25),
          TextField(
            controller: email,
            keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(
              labelText: 'E-mail do destinatário',
              prefixIcon: Icon(Icons.person_outline),
            ),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: amount,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Quantidade de NX',
              prefixIcon: Icon(Icons.account_balance_wallet_outlined),
            ),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: description,
            maxLength: 100,
            decoration: const InputDecoration(
              labelText: 'Descrição (opcional)',
              prefixIcon: Icon(Icons.notes),
            ),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: sending ? null : send,
            icon: const Icon(Icons.send),
            label: Text(sending ? 'Enviando...' : 'Confirmar transferência'),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(54),
            ),
          ),
          const SizedBox(height: 15),
          const Text(
            'Esta função transfere somente créditos virtuais NX entre '
            'contas do aplicativo. Não realiza Pix nem transferência bancária.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: Colors.black45),
          ),
        ],
      ),
    );
  }
}

// ============================================================
// RECOMPENSA DIÁRIA
// ============================================================

class RewardPage extends StatefulWidget {
  const RewardPage({super.key});

  @override
  State<RewardPage> createState() => _RewardPageState();
}

class _RewardPageState extends State<RewardPage> {
  bool loading = false;

  Future<void> claim() async {
    setState(() => loading = true);

    try {
      final result = await NexusApi.instance.claimReward();
      final map = _asMap(result);
      final message = _text(
        map['message'],
        'Recompensa solicitada. Atualize sua carteira para conferir o saldo.',
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_errorText(error))),
        );
      }
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Recompensa diária')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(25),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.card_giftcard_rounded,
                color: Color(0xFF7046D8),
                size: 90,
              ),
              const SizedBox(height: 20),
              const Text(
                'Sua recompensa diária',
                style: TextStyle(fontSize: 25, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 10),
              const Text(
                'Resgate os créditos virtuais disponibilizados pelo NEXUS BANK. '
                'O limite diário é controlado pelo servidor.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.black54),
              ),
              const SizedBox(height: 25),
              FilledButton.icon(
                onPressed: loading ? null : claim,
                icon: const Icon(Icons.redeem),
                label: Text(
                  loading ? 'Processando...' : 'Resgatar recompensa',
                ),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(52),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================================
// ASSISTENTE
// ============================================================

class AssistantPage extends StatelessWidget {
  const AssistantPage({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const SizedBox(height: 25),
        const CircleAvatar(
          radius: 42,
          backgroundColor: Color(0xFFEDE5FF),
          child: Icon(
            Icons.smart_toy_rounded,
            color: Color(0xFF7046D8),
            size: 45,
          ),
        ),
        const SizedBox(height: 18),
        const Text(
          'Assistente NEXUS',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 10),
        const Text(
          'O espaço do assistente está preparado na interface. '
          'Para conversar com uma IA de verdade, o servidor precisa oferecer '
          'uma rota de atendimento e estar configurado com o serviço de IA.',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.black54, height: 1.5),
        ),
        const SizedBox(height: 25),
        const _InfoCard(
          icon: Icons.lock_outline,
          title: 'Conexão protegida',
          description:
              'Chaves de IA devem ficar no servidor, nunca dentro do APK.',
        ),
        const _InfoCard(
          icon: Icons.chat_bubble_outline,
          title: 'Atendimento',
          description:
              'Quando a rota de IA estiver disponível, esta tela poderá '
              'ser conectada ao atendimento.',
        ),
      ],
    );
  }
}

// ============================================================
// AJUDA
// ============================================================

class HelpPage extends StatelessWidget {
  const HelpPage({super.key});

  @override
  Widget build(BuildContext context) {
    final items = <Map<String, String>>[
      {
        'q': 'O que são os NX?',
        'a': 'NX são créditos virtuais usados dentro do aplicativo para '
            'testar a carteira e suas funcionalidades. Não são dinheiro real.',
      },
      {
        'q': 'Posso sacar ou converter meus NX?',
        'a': 'Não. A versão atual não oferece saque, conversão ou depósito '
            'em dinheiro.',
      },
      {
        'q': 'Como faço uma transferência?',
        'a': 'Use a opção Transferir NX e informe o e-mail de outra conta '
            'cadastrada no NEXUS BANK.',
      },
      {
        'q': 'O aplicativo faz Pix?',
        'a': 'Não. Pix real está desativado. A versão atual oferece somente '
            'transferências internas de créditos virtuais NX.',
      },
      {
        'q': 'Como recebo a recompensa diária?',
        'a': 'Entre na opção Recompensa diária. O servidor controla o limite '
            'de um resgate por dia.',
      },
      {
        'q': 'Esqueci minha senha. O que faço?',
        'a': 'Entre em contato com o responsável pelo ambiente de teste. '
            'Não compartilhe sua senha com ninguém.',
      },
    ];

    return ListView(
      padding: const EdgeInsets.all(18),
      children: [
        const Text(
          'Central de ajuda',
          style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        const Text(
          'Encontre respostas para as dúvidas mais comuns.',
          style: TextStyle(color: Colors.black54),
        ),
        const SizedBox(height: 18),
        ...items.map(
          (item) => Card(
            color: Colors.white,
            elevation: 0,
            margin: const EdgeInsets.only(bottom: 10),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(15),
              side: const BorderSide(color: Color(0xFFEDE8F4)),
            ),
            child: ExpansionTile(
              leading: const Icon(
                Icons.help_outline,
                color: Color(0xFF7046D8),
              ),
              title: Text(
                item['q']!,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              childrenPadding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
              children: [
                Text(
                  item['a']!,
                  style: const TextStyle(color: Colors.black54, height: 1.4),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// ============================================================
// PAINEL ADMINISTRATIVO
// ============================================================

class AdminPage extends StatefulWidget {
  const AdminPage({super.key, required this.onRefresh});

  final Future<void> Function() onRefresh;

  @override
  State<AdminPage> createState() => _AdminPageState();
}

class _AdminPageState extends State<AdminPage> {
  bool loading = true;
  Map<String, dynamic> dashboard = {};
  List<dynamic> users = [];

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    setState(() => loading = true);
    try {
      final results = await Future.wait([
        NexusApi.instance.adminDashboard(),
        NexusApi.instance.adminUsers(),
      ]);
      if (!mounted) return;
      dashboard = results[0] as Map<String, dynamic>;
      users = results[1] as List<dynamic>;
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_errorText(error))),
        );
      }
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> creditUser(Map<String, dynamic> user) async {
    final id = _text(user['id']);
    if (id.isEmpty) return;

    final amountController = TextEditingController();
    final reasonController = TextEditingController();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Adicionar créditos NX'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Conta: ${_text(user['name'], user['email']?.toString() ?? '')}'),
            const SizedBox(height: 12),
            TextField(
              controller: amountController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Quantidade NX'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: reasonController,
              decoration: const InputDecoration(labelText: 'Motivo'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Confirmar'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    final value = int.tryParse(amountController.text.trim());
    if (value == null || value <= 0 || reasonController.text.trim().isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Informe quantidade e motivo válidos.')),
        );
      }
      return;
    }

    try {
      await NexusApi.instance.adminCredit(
        userId: id,
        amount: value,
        reason: reasonController.text.trim(),
      );
      await load();
      await widget.onRefresh();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_errorText(error))),
        );
      }
    } finally {
      amountController.dispose();
      reasonController.dispose();
    }
  }

  Future<void> changeStatus(Map<String, dynamic> user) async {
    final id = _text(user['id']);
    if (id.isEmpty) return;

    final active = user['isActive'] != false;

    try {
      await NexusApi.instance.adminStatus(id, !active);
      await load();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_errorText(error))),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: load,
      child: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          const Text(
            'Painel administrativo',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 6),
          const Text(
            'Área disponível somente para contas com função ADMIN.',
            style: TextStyle(color: Colors.black54),
          ),
          const SizedBox(height: 18),
          if (loading)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(25),
                child: CircularProgressIndicator(),
              ),
            )
          else ...[
            _InfoCard(
              icon: Icons.people_outline,
              title: 'Usuários carregados',
              description: '${users.length} contas retornadas pelo servidor.',
            ),
            _InfoCard(
              icon: Icons.dashboard_outlined,
              title: 'Resumo do servidor',
              description: dashboard.isEmpty
                  ? 'O servidor não retornou dados adicionais.'
                  : dashboard.entries
                      .where((e) => e.value is! Map && e.value is! List)
                      .map((e) => '${e.key}: ${e.value}')
                      .take(5)
                      .join(' • '),
            ),
            const SizedBox(height: 15),
            const Text(
              'Gerenciar usuários',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            ...users.map((item) {
              final user = _asMap(item);
              final active = user['isActive'] != false;
              return Card(
                color: Colors.white,
                elevation: 0,
                child: ListTile(
                  title: Text(_text(user['name'], 'Usuário')),
                  subtitle: Text(
                    '${_text(user['email'])}\n'
                    'Função: ${_text(user['role'], 'USER')} • '
                    '${active ? 'Ativo' : 'Desativado'}',
                  ),
                  isThreeLine: true,
                  trailing: PopupMenuButton<String>(
                    onSelected: (value) {
                      if (value == 'credit') creditUser(user);
                      if (value == 'status') changeStatus(user);
                    },
                    itemBuilder: (_) => [
                      const PopupMenuItem(
                        value: 'credit',
                        child: Text('Adicionar NX'),
                      ),
                      PopupMenuItem(
                        value: 'status',
                        child: Text(active ? 'Desativar conta' : 'Ativar conta'),
                      ),
                    ],
                  ),
                ),
              );
            }),
          ],
        ],
      ),
    );
  }
}

// ============================================================
// COMPONENTES VISUAIS
// ============================================================

class _InfoCard extends StatelessWidget {
  const _InfoCard({
    required this.icon,
    required this.title,
    required this.description,
  });

  final IconData icon;
  final String title;
  final String description;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: Colors.white,
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: Color(0xFFEDE8F4)),
      ),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: const Color(0xFFF0EAFE),
          child: Icon(icon, color: const Color(0xFF7046D8)),
        ),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text(description),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 45, horizontal: 15),
      child: Column(
        children: [
          Icon(icon, size: 55, color: Colors.black26),
          const SizedBox(height: 12),
          Text(
            title,
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 5),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.black54),
          ),
        ],
      ),
    );
  }
}