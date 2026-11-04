import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

const String apiBaseUrl = String.fromEnvironment('API_BASE_URL', defaultValue: '');
const Color ink = Color(0xFF0B0817);
const Color panel = Color(0xFF1B1530);
const Color violet = Color(0xFF9B7BFF);
const _storage = FlutterSecureStorage();

void main() => runApp(const NexusApp());

class ApiException implements Exception {
  final String message;
  ApiException(this.message);
  @override
  String toString() => message;
}

class Api {
  static Uri uri(String path) {
    if (apiBaseUrl.trim().isEmpty) {
      throw ApiException('A API ainda não foi configurada. Publique o servidor e compile com API_BASE_URL.');
    }
    final base = apiBaseUrl.trim().replaceFirst(RegExp(r'/+$'), '');
    return Uri.parse('$base$path');
  }

  static Future<dynamic> call(String path, {String method = 'GET', String? token, Map<String, dynamic>? body}) async {
    final headers = <String, String>{'Content-Type': 'application/json'};
    if (token != null) headers['Authorization'] = 'Bearer $token';
    http.Response response;
    try {
      final target = uri(path);
      final encoded = body == null ? null : jsonEncode(body);
      switch (method) {
        case 'POST':
          response = await http.post(target, headers: headers, body: encoded).timeout(const Duration(seconds: 25));
          break;
        case 'PATCH':
          response = await http.patch(target, headers: headers, body: encoded).timeout(const Duration(seconds: 25));
          break;
        default:
          response = await http.get(target, headers: headers).timeout(const Duration(seconds: 25));
      }
    } catch (e) {
      if (e is ApiException) rethrow;
      throw ApiException('Não foi possível conectar ao servidor. Confira a internet e a URL da API.');
    }
    dynamic data;
    try { data = response.body.isEmpty ? <String, dynamic>{} : jsonDecode(response.body); }
    catch (_) { throw ApiException('O servidor retornou uma resposta inválida.'); }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiException(data is Map ? (data['error']?.toString() ?? 'Erro ${response.statusCode}') : 'Erro ${response.statusCode}');
    }
    return data;
  }

  static Future<Map<String, dynamic>> login(String email, String password) async =>
      Map<String, dynamic>.from(await call('/auth/login', method: 'POST', body: {'email': email, 'password': password}));
  static Future<Map<String, dynamic>> register(String name, String email, String password) async =>
      Map<String, dynamic>.from(await call('/auth/register', method: 'POST', body: {'name': name, 'email': email, 'password': password}));
  static Future<Map<String, dynamic>> wallet(String token) async =>
      Map<String, dynamic>.from(await call('/wallet', token: token));
  static Future<List<dynamic>> transactions(String token) async =>
      List<dynamic>.from(await call('/transactions', token: token));
  static Future<Map<String, dynamic>> config() async => Map<String, dynamic>.from(await call('/config'));
}

class NexusApp extends StatefulWidget {
  const NexusApp({super.key});
  @override State<NexusApp> createState() => _NexusAppState();
}

class _NexusAppState extends State<NexusApp> {
  String? token;
  Map<String, dynamic>? user;
  bool restoring = true;

  @override void initState() { super.initState(); _restore(); }
  Future<void> _restore() async {
    try {
      final saved = await _storage.read(key: 'nexus_token');
      if (saved != null) {
        final me = await Api.call('/me', token: saved);
        token = saved;
        user = Map<String, dynamic>.from(me['user']);
      }
    } catch (_) { await _storage.delete(key: 'nexus_token'); }
    if (mounted) setState(() => restoring = false);
  }
  Future<void> _onAuth(Map<String, dynamic> result) async {
    token = result['token'] as String;
    user = Map<String, dynamic>.from(result['user']);
    await _storage.write(key: 'nexus_token', value: token);
    if (mounted) setState(() {});
  }
  Future<void> _logout() async {
    await _storage.delete(key: 'nexus_token');
    if (!mounted) return;
    setState(() { token = null; user = null; });
  }

  @override Widget build(BuildContext context) => MaterialApp(
    title: 'NEXUS BANK', debugShowCheckedModeBanner: false,
    theme: ThemeData(useMaterial3: true, brightness: Brightness.dark, scaffoldBackgroundColor: ink,
      colorScheme: ColorScheme.fromSeed(seedColor: violet, brightness: Brightness.dark),
      appBarTheme: const AppBarTheme(backgroundColor: ink, foregroundColor: Colors.white),
      inputDecorationTheme: InputDecorationTheme(filled: true, fillColor: panel,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none))),
    home: restoring ? const SplashPage() : token == null || user == null
      ? AuthPage(onAuth: _onAuth) : HomeShell(token: token!, user: user!, onLogout: _logout));
}

class SplashPage extends StatelessWidget {
  const SplashPage({super.key});
  @override Widget build(BuildContext context) => const Scaffold(body: Center(child: CircularProgressIndicator()));
}

class AuthPage extends StatefulWidget {
  final Future<void> Function(Map<String, dynamic>) onAuth;
  const AuthPage({super.key, required this.onAuth});
  @override State<AuthPage> createState() => _AuthPageState();
}
class _AuthPageState extends State<AuthPage> {
  final name = TextEditingController(); final email = TextEditingController(); final password = TextEditingController();
  bool creating = false; bool busy = false; String? error;
  Future<void> submit() async {
    setState(() { busy = true; error = null; });
    try {
      final result = creating
        ? await Api.register(name.text.trim(), email.text.trim(), password.text)
        : await Api.login(email.text.trim(), password.text);
      await widget.onAuth(result);
    } catch (e) { if (mounted) setState(() => error = e.toString()); }
    finally { if (mounted) setState(() => busy = false); }
  }
  @override void dispose() { name.dispose(); email.dispose(); password.dispose(); super.dispose(); }
  @override Widget build(BuildContext context) => Scaffold(body: SafeArea(child: Center(child: SingleChildScrollView(
    padding: const EdgeInsets.all(24), child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 430), child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const Icon(Icons.account_balance_wallet_rounded, size: 66, color: violet),
        const SizedBox(height: 12), const Text('NEXUS BANK', textAlign: TextAlign.center,
          style: TextStyle(fontSize: 29, fontWeight: FontWeight.w900, letterSpacing: 3)),
        const SizedBox(height: 6), const Text('SUA CARTEIRA VIRTUAL', textAlign: TextAlign.center,
          style: TextStyle(color: violet, letterSpacing: 2, fontSize: 11, fontWeight: FontWeight.bold)),
        const SizedBox(height: 32),
        if (creating) ...[TextField(controller: name, textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(labelText: 'Nome completo', prefixIcon: Icon(Icons.person_outline))), const SizedBox(height: 12)],
        TextField(controller: email, keyboardType: TextInputType.emailAddress,
          decoration: const InputDecoration(labelText: 'E-mail', prefixIcon: Icon(Icons.email_outlined))),
        const SizedBox(height: 12), TextField(controller: password, obscureText: true,
          decoration: const InputDecoration(labelText: 'Senha', prefixIcon: Icon(Icons.lock_outline))),
        if (creating) const Padding(padding: EdgeInsets.only(top: 8), child: Text('Use uma senha com pelo menos 10 caracteres.', style: TextStyle(color: Colors.white54, fontSize: 12))),
        if (error != null) Padding(padding: const EdgeInsets.only(top: 14), child: Text(error!, style: const TextStyle(color: Colors.redAccent))),
        const SizedBox(height: 20), FilledButton(onPressed: busy ? null : submit,
          child: Padding(padding: const EdgeInsets.all(13), child: busy ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2)) : Text(creating ? 'CRIAR CONTA' : 'ENTRAR'))),
        TextButton(onPressed: busy ? null : () => setState(() { creating = !creating; error = null; }),
          child: Text(creating ? 'Já tenho uma conta - entrar' : 'Criar minha conta')),
        const SizedBox(height: 18), const NoticeBox(text: 'Este aplicativo usa moedas virtuais NX para testes. Elas não são reais, não podem ser sacadas e não têm conversão para reais ou Pix.')
      ]))))));
}

class HomeShell extends StatefulWidget {
  final String token; final Map<String, dynamic> user; final Future<void> Function() onLogout;
  const HomeShell({super.key, required this.token, required this.user, required this.onLogout});
  @override State<HomeShell> createState() => _HomeShellState();
}
class _HomeShellState extends State<HomeShell> {
  int index = 0;
  @override Widget build(BuildContext context) {
    final isAdmin = widget.user['role'] == 'ADMIN';
    final pages = <Widget>[
      WalletTab(token: widget.token, user: widget.user),
      TransferTab(token: widget.token),
      RewardsTab(token: widget.token),
      HistoryTab(token: widget.token),
      if (isAdmin) AdminTab(token: widget.token, userId: widget.user['id'].toString())
    ];
    final labels = <NavigationDestination>[
      const NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home), label: 'Início'),
      const NavigationDestination(icon: Icon(Icons.swap_horiz), label: 'Transferir'),
      const NavigationDestination(icon: Icon(Icons.auto_awesome), label: 'Moedas'),
      const NavigationDestination(icon: Icon(Icons.receipt_long), label: 'Histórico'),
      if (isAdmin) const NavigationDestination(icon: Icon(Icons.admin_panel_settings_outlined), label: 'Admin')
    ];
    return Scaffold(
      appBar: AppBar(title: const Text('NEXUS BANK', style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 2)),
        actions: [IconButton(tooltip: 'Sair', onPressed: widget.onLogout, icon: const Icon(Icons.logout))]),
      body: IndexedStack(index: index, children: pages),
      bottomNavigationBar: NavigationBar(selectedIndex: index, onDestinationSelected: (v) => setState(() => index = v), destinations: labels),
    );
  }
}

class NoticeBox extends StatelessWidget {
  final String text;
  const NoticeBox({super.key, required this.text});
  @override Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14), decoration: BoxDecoration(color: const Color(0xFF2B2140), borderRadius: BorderRadius.circular(14), border: Border.all(color: violet.withOpacity(.35))),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [const Icon(Icons.info_outline, color: violet, size: 19), const SizedBox(width: 10), Expanded(child: Text(text, style: const TextStyle(fontSize: 12, color: Colors.white70)))]));
}

class WalletTab extends StatefulWidget {
  final String token; final Map<String, dynamic> user;
  const WalletTab({super.key, required this.token, required this.user});
  @override State<WalletTab> createState() => _WalletTabState();
}
class _WalletTabState extends State<WalletTab> {
  Map<String, dynamic>? wallet; Map<String, dynamic>? config; bool busy = true; String? error;
  @override void initState() { super.initState(); refresh(); }
  Future<void> refresh() async {
    setState(() { busy = true; error = null; });
    try { final values = await Future.wait([Api.wallet(widget.token), Api.config()]);
      if (!mounted) return; setState(() { wallet = Map<String, dynamic>.from(values[0]); config = Map<String, dynamic>.from(values[1]); });
    } catch (e) { if (mounted) setState(() => error = e.toString()); }
    finally { if (mounted) setState(() => busy = false); }
  }
  @override Widget build(BuildContext context) => RefreshIndicator(onRefresh: refresh, child: ListView(padding: const EdgeInsets.all(18), children: [
    Text('Olá, ${widget.user['name']}', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)), const SizedBox(height: 5),
    Text(config?['welcomeMessage']?.toString() ?? 'Bem-vindo ao NEXUS BANK.', style: const TextStyle(color: Colors.white60)),
    const SizedBox(height: 22),
    Container(padding: const EdgeInsets.all(24), decoration: BoxDecoration(gradient: const LinearGradient(colors: [Color(0xFF442C75), Color(0xFF211638)]), borderRadius: BorderRadius.circular(24)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(config?['bannerTitle']?.toString() ?? 'Sua carteira virtual NEXUS', style: const TextStyle(color: Colors.white70)),
        const SizedBox(height: 14), const Text('SALDO VIRTUAL', style: TextStyle(fontSize: 11, letterSpacing: 2, color: Colors.white60)),
        const SizedBox(height: 5), if (busy) const CircularProgressIndicator() else if (error != null) Text(error!, style: const TextStyle(color: Colors.redAccent))
          else Text('NX ${wallet?['balance'] ?? 0}', style: const TextStyle(fontSize: 36, fontWeight: FontWeight.w900)),
        const SizedBox(height: 6), const Text('Moedas virtuais - sem valor monetário', style: TextStyle(color: Colors.white60, fontSize: 12)),
        Align(alignment: Alignment.centerRight, child: IconButton(onPressed: refresh, icon: const Icon(Icons.refresh)))
      ])), const SizedBox(height: 18),
    const NoticeBox(text: 'O saldo exibido é apenas uma pontuação virtual interna. Não representa depósito, crédito, investimento ou dinheiro disponível para saque.'),
    const SizedBox(height: 18),
    const Text('O que você pode fazer', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17)), const SizedBox(height: 10),
    const FeatureRow(icon: Icons.swap_horiz, title: 'Transferir moedas', subtitle: 'Envie NX para outra conta NEXUS.'),
    const FeatureRow(icon: Icons.auto_awesome, title: 'Gerar recompensa', subtitle: 'Resgate a recompensa virtual configurada.'),
    if (widget.user['role'] == 'ADMIN') const FeatureRow(icon: Icons.admin_panel_settings, title: 'Painel administrativo', subtitle: 'Gerencie usuários e configurações.')
  ]));
}

class FeatureRow extends StatelessWidget {
  final IconData icon; final String title; final String subtitle;
  const FeatureRow({super.key, required this.icon, required this.title, required this.subtitle});
  @override Widget build(BuildContext context) => Card(color: panel, child: ListTile(leading: CircleAvatar(backgroundColor: violet.withOpacity(.18), child: Icon(icon, color: violet)), title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)), subtitle: Text(subtitle)));
}

class TransferTab extends StatefulWidget {
  final String token; const TransferTab({super.key, required this.token});
  @override State<TransferTab> createState() => _TransferTabState();
}
class _TransferTabState extends State<TransferTab> {
  final email = TextEditingController(); final amount = TextEditingController(); final description = TextEditingController(); bool busy = false; String? message; bool failed = false;
  Future<void> transfer() async {
    final number = int.tryParse(amount.text.trim());
    if (number == null || number <= 0 || email.text.trim().isEmpty) { setState(() { message = 'Informe e-mail e quantidade válida de moedas.'; failed = true; }); return; }
    setState(() { busy = true; message = null; });
    try { await Api.call('/transfers/internal', method: 'POST', token: widget.token, body: {'recipientEmail': email.text.trim(), 'amount': number, 'description': description.text.trim()});
      setState(() { message = 'Transferência virtual concluída: NX $number.'; failed = false; amount.clear(); description.clear(); });
    } catch (e) { setState(() { message = e.toString(); failed = true; }); }
    finally { if (mounted) setState(() => busy = false); }
  }
  @override void dispose() { email.dispose(); amount.dispose(); description.dispose(); super.dispose(); }
  @override Widget build(BuildContext context) => ListView(padding: const EdgeInsets.all(20), children: [
    const Text('Transferir moedas', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)), const SizedBox(height: 8),
    const NoticeBox(text: 'Esta função transfere somente moedas virtuais NX entre usuários. Não envia Pix e não movimenta dinheiro real.'), const SizedBox(height: 20),
    TextField(controller: email, keyboardType: TextInputType.emailAddress, decoration: const InputDecoration(labelText: 'E-mail do destinatário')),
    const SizedBox(height: 12), TextField(controller: amount, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Quantidade de NX')),
    const SizedBox(height: 12), TextField(controller: description, decoration: const InputDecoration(labelText: 'Descrição (opcional)')),
    const SizedBox(height: 18), FilledButton(onPressed: busy ? null : transfer, child: busy ? const CircularProgressIndicator() : const Text('TRANSFERIR NX')),
    if (message != null) Padding(padding: const EdgeInsets.only(top: 14), child: Text(message!, style: TextStyle(color: failed ? Colors.redAccent : Colors.greenAccent)))
  ]);
}

class RewardsTab extends StatefulWidget {
  final String token; const RewardsTab({super.key, required this.token});
  @override State<RewardsTab> createState() => _RewardsTabState();
}
class _RewardsTabState extends State<RewardsTab> {
  Map<String, dynamic>? config; bool busy = false; String? message; bool failed = false;
  @override void initState() { super.initState(); _load(); }
  Future<void> _load() async { try { final c = await Api.config(); if (mounted) setState(() => config = c); } catch (e) { if (mounted) setState(() { message = e.toString(); failed = true; }); } }
  Future<void> claim() async {
    setState(() { busy = true; message = null; });
    try { final r = await Api.call('/rewards/claim', method: 'POST', token: widget.token);
      setState(() { message = 'Você recebeu NX ${r['amount']}!'; failed = false; });
    } catch (e) { setState(() { message = e.toString(); failed = true; }); }
    finally { if (mounted) setState(() => busy = false); }
  }
  @override Widget build(BuildContext context) => ListView(padding: const EdgeInsets.all(20), children: [
    const Text('Gerador de moedas virtuais', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)), const SizedBox(height: 10),
    const NoticeBox(text: 'O gerador cria apenas créditos virtuais NX para uso dentro do aplicativo. Não gera reais, não promete lucro e não permite saque.'),
    const SizedBox(height: 22), Card(color: panel, child: Padding(padding: const EdgeInsets.all(22), child: Column(children: [
      const Icon(Icons.auto_awesome, color: violet, size: 48), const SizedBox(height: 12),
      Text('NX ${config?['dailyReward'] ?? '...'}', style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w900)),
      const Text('RECOMPENSA DIÁRIA VIRTUAL', style: TextStyle(color: Colors.white60, fontSize: 11, letterSpacing: 1.5)),
      const SizedBox(height: 18), FilledButton.icon(onPressed: busy || config?['rewardsEnabled'] != true ? null : claim,
        icon: const Icon(Icons.bolt), label: Text(busy ? 'PROCESSANDO...' : 'RESGATAR RECOMPENSA')),
      if (config?['rewardsEnabled'] == false) const Padding(padding: EdgeInsets.only(top: 8), child: Text('Recompensas desativadas pelo administrador.', style: TextStyle(color: Colors.white54)))
    ]))), if (message != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text(message!, style: TextStyle(color: failed ? Colors.redAccent : Colors.greenAccent)))
  ]);
}

class HistoryTab extends StatefulWidget {
  final String token; const HistoryTab({super.key, required this.token});
  @override State<HistoryTab> createState() => _HistoryTabState();
}
class _HistoryTabState extends State<HistoryTab> {
  late Future<List<dynamic>> future;
  @override void initState() { super.initState(); future = Api.transactions(widget.token); }
  void reload() => setState(() => future = Api.transactions(widget.token));
  String dateText(dynamic value) { try { final date = DateTime.parse(value.toString()).toLocal(); return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}'; } catch (_) { return ''; } }
  @override Widget build(BuildContext context) => FutureBuilder<List<dynamic>>(future: future, builder: (context, snapshot) {
    if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
    if (snapshot.hasError) return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [Text(snapshot.error.toString()), TextButton(onPressed: reload, child: const Text('Tentar novamente'))]));
    final rows = snapshot.data ?? [];
    if (rows.isEmpty) return const Center(child: Text('Nenhuma movimentação ainda.'));
    return RefreshIndicator(onRefresh: () async => reload(), child: ListView(padding: const EdgeInsets.all(12), children: [
      const Padding(padding: EdgeInsets.all(8), child: Text('Histórico virtual', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold))),
      for (final raw in rows) Builder(builder: (_) { final row = Map<String, dynamic>.from(raw as Map); final incoming = row['direction'] == 'IN';
        final type = row['type'] == 'REWARD' ? 'Recompensa' : row['type'] == 'ADMIN_CREDIT' ? 'Crédito do administrador' : 'Transferência';
        return Card(color: panel, child: ListTile(leading: CircleAvatar(backgroundColor: violet.withOpacity(.15), child: Icon(incoming ? Icons.south_west : Icons.north_east, color: incoming ? Colors.greenAccent : Colors.orangeAccent)),
          title: Text(row['description']?.toString() ?? type, maxLines: 2, overflow: TextOverflow.ellipsis), subtitle: Text('${dateText(row['createdAt'])} - $type'),
          trailing: Text('${incoming ? '+' : '-'}NX ${row['amount']}', style: TextStyle(fontWeight: FontWeight.bold, color: incoming ? Colors.greenAccent : Colors.orangeAccent))));
      })
    ]));
  });
}

class AdminTab extends StatefulWidget {
  final String token; final String userId;
  const AdminTab({super.key, required this.token, required this.userId});
  @override State<AdminTab> createState() => _AdminTabState();
}
class _AdminTabState extends State<AdminTab> {
  Map<String, dynamic>? dashboard; List<dynamic> users = []; bool busy = true; String? error;
  final reward = TextEditingController(); final welcome = TextEditingController(); final banner = TextEditingController(); bool enabled = true;
  @override void initState() { super.initState(); load(); }
  @override void dispose() { reward.dispose(); welcome.dispose(); banner.dispose(); super.dispose(); }
  Future<void> load() async {
    setState(() { busy = true; error = null; });
    try {
      final values = await Future.wait([Api.call('/admin/dashboard', token: widget.token), Api.call('/admin/users', token: widget.token)]);
      dashboard = Map<String, dynamic>.from(values[0]); users = List<dynamic>.from(values[1]);
      final cfg = Map<String, dynamic>.from(dashboard!['config']);
      reward.text = cfg['dailyReward'].toString(); welcome.text = cfg['welcomeMessage'].toString(); banner.text = cfg['bannerTitle'].toString(); enabled = cfg['rewardsEnabled'] == true;
    } catch (e) { error = e.toString(); }
    finally { if (mounted) setState(() => busy = false); }
  }
  Future<void> saveConfig() async {
    final amount = int.tryParse(reward.text.trim());
    if (amount == null || amount < 0) { _message('Informe uma recompensa válida.'); return; }
    try { await Api.call('/admin/config', method: 'PATCH', token: widget.token, body: {
      'dailyReward': amount, 'rewardsEnabled': enabled, 'welcomeMessage': welcome.text.trim(), 'bannerTitle': banner.text.trim()
    }); _message('Configurações salvas.'); await load(); }
    catch (e) { _message(e.toString()); }
  }
  void _message(String value) { if (!mounted) return; ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(value))); }
  Future<void> creditUser(Map<String, dynamic> user) async {
    final amountController = TextEditingController(); final reasonController = TextEditingController(text: 'Crédito promocional de teste');
    final ok = await showDialog<bool>(context: context, builder: (context) => AlertDialog(title: Text('Creditar NX para ${user['name']}'), content: Column(mainAxisSize: MainAxisSize.min, children: [
      TextField(controller: amountController, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Quantidade de moedas')),
      TextField(controller: reasonController, decoration: const InputDecoration(labelText: 'Motivo')),
      const SizedBox(height: 8), const Text('Crédito fictício, sem valor monetário.', style: TextStyle(color: Colors.white60, fontSize: 12))
    ]), actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')), FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Creditar'))]));
    if (ok != true) return;
    final amount = int.tryParse(amountController.text.trim());
    if (amount == null || amount <= 0) { _message('Quantidade inválida.'); return; }
    try { await Api.call('/admin/users/${user['id']}/credits', method: 'POST', token: widget.token, body: {'amount': amount, 'reason': reasonController.text.trim()}); _message('Créditos virtuais lançados.'); await load(); }
    catch (e) { _message(e.toString()); }
    finally { amountController.dispose(); reasonController.dispose(); }
  }
  Future<void> toggleUser(Map<String, dynamic> user) async {
    final active = user['isActive'] == true;
    try { await Api.call('/admin/users/${user['id']}/status', method: 'PATCH', token: widget.token, body: {'isActive': !active}); _message(active ? 'Conta desativada.' : 'Conta ativada.'); await load(); }
    catch (e) { _message(e.toString()); }
  }
  @override Widget build(BuildContext context) {
    if (busy) return const Center(child: CircularProgressIndicator());
    if (error != null) return Center(child: Padding(padding: const EdgeInsets.all(20), child: Column(mainAxisSize: MainAxisSize.min, children: [Text(error!), TextButton(onPressed: load, child: const Text('Tentar novamente'))])));
    final d = dashboard ?? {};
    return RefreshIndicator(onRefresh: load, child: ListView(padding: const EdgeInsets.all(16), children: [
      const Text('Painel administrativo', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
      const SizedBox(height: 6), const NoticeBox(text: 'Área restrita ao administrador. Os lançamentos deste painel são moedas virtuais de teste e não representam dinheiro real.'),
      const SizedBox(height: 14), Wrap(spacing: 8, runSpacing: 8, children: [
        _stat('Usuários', d['users']), _stat('Ativos', d['activeUsers']), _stat('NX em circulação', d['virtualCreditsInCirculation']), _stat('Movimentações', d['transactions'])
      ]),
      const SizedBox(height: 22), const Text('Configurações do aplicativo', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)), const SizedBox(height: 10),
      TextField(controller: banner, decoration: const InputDecoration(labelText: 'Título da carteira')),
      const SizedBox(height: 10), TextField(controller: welcome, maxLines: 2, decoration: const InputDecoration(labelText: 'Mensagem de boas-vindas')),
      const SizedBox(height: 10), TextField(controller: reward, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Recompensa diária em NX')),
      SwitchListTile(contentPadding: EdgeInsets.zero, value: enabled, onChanged: (v) => setState(() => enabled = v), title: const Text('Ativar gerador diário de NX')),
      FilledButton(onPressed: saveConfig, child: const Text('SALVAR CONFIGURAÇÕES')),
      const SizedBox(height: 22), Text('Usuários (${users.length})', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
      for (final raw in users) Builder(builder: (_) { final u = Map<String, dynamic>.from(raw as Map); final w = Map<String, dynamic>.from((u['wallet'] ?? {}) as Map); final isCurrent = u['id'] == widget.userId;
        return Card(color: panel, child: Padding(padding: const EdgeInsets.all(10), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(u['name'].toString(), style: const TextStyle(fontWeight: FontWeight.bold)), Text(u['email'].toString(), style: const TextStyle(color: Colors.white60, fontSize: 12)),
          const SizedBox(height: 4), Text('NX ${w['balance'] ?? 0} - ${u['isActive'] == true ? 'Ativo' : 'Desativado'}'),
          Wrap(children: [TextButton.icon(onPressed: () => creditUser(u), icon: const Icon(Icons.add_circle_outline), label: const Text('Creditar NX')),
            if (!isCurrent) TextButton.icon(onPressed: () => toggleUser(u), icon: Icon(u['isActive'] == true ? Icons.block : Icons.check_circle_outline), label: Text(u['isActive'] == true ? 'Desativar' : 'Ativar'))])
        ])));
      }),
      const SizedBox(height: 18), const Text('Todas as ações administrativas relevantes são registradas no banco de dados. Para consultar os registros, use GET /api/admin/audit.', style: TextStyle(color: Colors.white54, fontSize: 12))
    ]));
  }
  Widget _stat(String title, dynamic value) => SizedBox(width: 155, child: Card(color: panel, child: Padding(padding: const EdgeInsets.all(14), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(title, style: const TextStyle(color: Colors.white60, fontSize: 12)), const SizedBox(height: 7), Text('${value ?? 0}', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 20))]))));
}
