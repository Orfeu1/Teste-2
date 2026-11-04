import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

const apiBaseUrl = String.fromEnvironment(
  'API_BASE_URL',
  defaultValue: 'http://10.0.2.2:3000/api',
);

void main() => runApp(const CarteiraApp());

class CarteiraApp extends StatelessWidget {
  const CarteiraApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Carteira',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF5636A5)),
        useMaterial3: true,
      ),
      home: const AuthPage(),
    );
  }
}

class Api {
  String? token;
  bool isAdmin = false;

  Uri uri(String path) => Uri.parse('$apiBaseUrl$path');

  Map<String, String> get headers => {
    'Content-Type': 'application/json',
    if (token != null) 'Authorization': 'Bearer $token',
  };

  dynamic decode(http.Response r) {
    dynamic data;
    try {
      data = jsonDecode(r.body);
    } catch (_) {
      throw Exception('Resposta inválida do servidor.');
    }
    if (r.statusCode < 200 || r.statusCode >= 300) {
      throw Exception(data is Map ? (data['erro'] ?? 'Erro ${r.statusCode}') : 'Erro ${r.statusCode}');
    }
    return data;
  }

  Future<Map<String, dynamic>> register(String nome, String email, String senha) async {
    final r = await http.post(uri('/auth/register'), headers: headers,
      body: jsonEncode({'nome': nome, 'email': email, 'senha': senha}))
      .timeout(const Duration(seconds: 20));
    return Map<String, dynamic>.from(decode(r));
  }

  Future<String> login(String email, String senha) async {
    final r = await http.post(uri('/auth/login'), headers: headers,
      body: jsonEncode({'email': email, 'senha': senha}))
      .timeout(const Duration(seconds: 20));
    final data = Map<String, dynamic>.from(decode(r));
    token = data['token'] as String?;
    isAdmin = data['role'] == 'admin';
    if (token == null || token!.isEmpty) throw Exception('Token não recebido.');
    return data['nome']?.toString() ?? 'Pessoa';
  }

  Future<Map<String, dynamic>> publicConfig() async {
    final r = await http.get(uri('/config')).timeout(const Duration(seconds: 20));
    return Map<String, dynamic>.from(decode(r));
  }

  Future<Map<String, dynamic>> wallet() async {
    final r = await http.get(uri('/wallet'), headers: headers)
      .timeout(const Duration(seconds: 20));
    return Map<String, dynamic>.from(decode(r));
  }

  Future<List<dynamic>> transactions() async {
    final r = await http.get(uri('/transactions'), headers: headers)
      .timeout(const Duration(seconds: 20));
    final data = decode(r);
    return List<dynamic>.from(data['transactions'] ?? []);
  }

  Future<Map<String, dynamic>> claimReward() async {
    final r = await http.post(uri('/rewards/claim'), headers: headers,
      body: jsonEncode({'campaignId': 'welcome'}))
      .timeout(const Duration(seconds: 20));
    return Map<String, dynamic>.from(decode(r));
  }

  Future<Map<String, dynamic>> adminOverview() async {
    final r = await http.get(uri('/admin/overview'), headers: headers).timeout(const Duration(seconds: 20));
    return Map<String, dynamic>.from(decode(r));
  }
  Future<List<dynamic>> adminUsers() async {
    final r = await http.get(uri('/admin/users'), headers: headers).timeout(const Duration(seconds: 20));
    return List<dynamic>.from(decode(r)['users'] ?? []);
  }
  Future<void> adminSaveSettings(Map<String, dynamic> settings) async {
    final r = await http.put(uri('/admin/settings'), headers: headers, body: jsonEncode(settings)).timeout(const Duration(seconds: 20));
    decode(r);
  }
  Future<void> adminSetBlocked(String id, bool blocked) async {
    final r = await http.patch(uri('/admin/users/$id/block'), headers: headers, body: jsonEncode({'blocked': blocked})).timeout(const Duration(seconds: 20));
    decode(r);
  }
  Future<String> askAdminAssistant(String message) async {
    final r = await http.post(uri('/admin/ai/chat'), headers: headers, body: jsonEncode({'message': message})).timeout(const Duration(seconds: 60));
    return Map<String, dynamic>.from(decode(r))['reply']?.toString() ?? 'Sem resposta.';
  }

  Future<String> askAssistant(String message) async {
    final r = await http.post(uri('/ai/chat'), headers: headers,
      body: jsonEncode({'message': message}))
      .timeout(const Duration(seconds: 45));
    final data = Map<String, dynamic>.from(decode(r));
    return data['reply']?.toString() ?? 'Não consegui preparar uma resposta.';
  }

  void logout() { token = null; isAdmin = false; }
}

String money(dynamic value) {
  final n = value is num ? value.toDouble() : double.tryParse('$value') ?? 0;
  return 'R\$ ${n.toStringAsFixed(2).replaceAll('.', ',')}';
}

void snack(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
}

class AuthPage extends StatefulWidget {
  const AuthPage({super.key});
  @override
  State<AuthPage> createState() => _AuthPageState();
}

class _AuthPageState extends State<AuthPage> {
  final api = Api();
  final name = TextEditingController();
  final email = TextEditingController();
  final password = TextEditingController();
  bool createAccount = false;
  bool busy = false;
  bool hidePassword = true;

  Future<void> submit() async {
    if (busy) return;
    if (email.text.trim().isEmpty || password.text.isEmpty ||
        (createAccount && name.text.trim().length < 2)) {
      snack(context, 'Preencha os campos corretamente.');
      return;
    }
    setState(() => busy = true);
    try {
      if (createAccount) {
        await api.register(name.text.trim(), email.text.trim(), password.text);
      }
      final userName = await api.login(email.text.trim(), password.text);
      if (!mounted) return;
      Navigator.pushReplacement(context, MaterialPageRoute(
        builder: (_) => api.isAdmin ? AdminPanelPage(api: api, userName: userName) : HomePage(api: api, userName: userName)));
    } catch (e) {
      if (mounted) snack(context, e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  void dispose() {
    name.dispose(); email.dispose(); password.dispose(); super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(child: Center(child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          const Icon(Icons.account_balance_wallet_rounded, size: 76, color: Color(0xFF5636A5)),
          const SizedBox(height: 12),
          const Text('Minha Carteira', style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text(createAccount ? 'Crie sua conta' : 'Entre na sua conta'),
          const SizedBox(height: 28),
          if (createAccount) ...[
            TextField(controller: name, decoration: const InputDecoration(labelText: 'Nome', border: OutlineInputBorder())),
            const SizedBox(height: 12),
          ],
          TextField(controller: email, keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(labelText: 'E-mail', border: OutlineInputBorder(), prefixIcon: Icon(Icons.email_outlined))),
          const SizedBox(height: 12),
          TextField(controller: password, obscureText: hidePassword,
            decoration: InputDecoration(labelText: 'Senha', border: const OutlineInputBorder(),
              prefixIcon: const Icon(Icons.lock_outline),
              suffixIcon: IconButton(onPressed: () => setState(() => hidePassword = !hidePassword),
                icon: Icon(hidePassword ? Icons.visibility : Icons.visibility_off)))),
          const SizedBox(height: 8),
          if (createAccount)
            const Align(alignment: Alignment.centerLeft, child: Text('Use uma senha com pelo menos 10 caracteres.', style: TextStyle(fontSize: 12))),
          const SizedBox(height: 18),
          SizedBox(width: double.infinity, height: 50,
            child: FilledButton(onPressed: busy ? null : submit,
              child: busy ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : Text(createAccount ? 'Criar conta' : 'Entrar'))),
          TextButton(onPressed: busy ? null : () => setState(() => createAccount = !createAccount),
            child: Text(createAccount ? 'Já tenho conta' : 'Criar uma conta')),
          const SizedBox(height: 18),
          const Text('Carteira demonstrativa. Recompensas dependem de campanhas financiadas. Saques Pix ainda não habilitados.',
            textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: Colors.grey)),
        ]),
      ))),
    );
  }
}


class AdminPanelPage extends StatefulWidget {
  final Api api; final String userName;
  const AdminPanelPage({super.key, required this.api, required this.userName});
  @override State<AdminPanelPage> createState() => _AdminPanelPageState();
}

class _AdminPanelPageState extends State<AdminPanelPage> {
  bool loading = true, maintenance = false;
  int users = 0, blocked = 0, transactions = 0;
  String appName = 'Minha Carteira', banner = '', maintenanceMessage = 'Estamos realizando uma manutenção.';
  List<dynamic> userRows = [];
  final aiInput = TextEditingController();
  final aiMessages = <String>['Sou a IA privada do painel administrativo, separada do assistente dos usuários. Posso ajudar a planejar melhorias e interpretar informações.'] ;
  bool aiBusy = false;
  @override void initState() { super.initState(); load(); }
  Future<void> load() async {
    setState(() => loading = true);
    try {
      final data = await widget.api.adminOverview();
      final settings = Map<String, dynamic>.from(data['settings'] ?? {});
      final rows = await widget.api.adminUsers();
      if (!mounted) return;
      setState(() { users = data['users'] ?? 0; blocked = data['blocked'] ?? 0; transactions = data['transactions'] ?? 0;
        appName = settings['appName']?.toString() ?? 'Minha Carteira'; maintenance = settings['maintenance'] == true;
        banner = settings['bannerText']?.toString() ?? ''; maintenanceMessage = settings['maintenanceMessage']?.toString() ?? 'Estamos realizando uma manutenção.'; userRows = rows; });
    } catch (e) { if (mounted) snack(context, e.toString().replaceFirst('Exception: ', '')); }
    finally { if (mounted) setState(() => loading = false); }
  }
  Future<void> save() async {
    try { await widget.api.adminSaveSettings({'appName': appName, 'maintenance': maintenance, 'maintenanceMessage': maintenanceMessage, 'bannerText': banner});
      if (mounted) snack(context, 'Configurações salvas no servidor.');
    } catch (e) { if (mounted) snack(context, e.toString().replaceFirst('Exception: ', '')); }
  }
  Future<void> toggleBlock(Map<String, dynamic> user) async {
    try { await widget.api.adminSetBlocked(user['id'].toString(), user['blocked'] != true); await load(); }
    catch (e) { if (mounted) snack(context, e.toString().replaceFirst('Exception: ', '')); }
  }
  Future<void> sendAdminAI() async {
    final message = aiInput.text.trim(); if (message.isEmpty || aiBusy) return;
    aiInput.clear(); setState(() { aiMessages.add('Você: $message'); aiBusy = true; });
    try { final reply = await widget.api.askAdminAssistant(message); if (mounted) setState(() => aiMessages.add('IA administrativa: $reply')); }
    catch (e) { if (mounted) setState(() => aiMessages.add('Erro: ${e.toString().replaceFirst('Exception: ', '')}')); }
    finally { if (mounted) setState(() => aiBusy = false); }
  }
  void logout() { widget.api.logout(); Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (_) => const AuthPage()), (_) => false); }
  @override void dispose() { aiInput.dispose(); super.dispose(); }
  @override Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Painel administrativo'), actions: [IconButton(onPressed: load, icon: const Icon(Icons.refresh)), IconButton(onPressed: logout, icon: const Icon(Icons.logout))]),
    body: loading ? const Center(child: CircularProgressIndicator()) : DefaultTabController(length: 4, child: Column(children: [
      Material(color: Theme.of(context).colorScheme.primaryContainer, child: const TabBar(isScrollable: true, tabs: [Tab(icon: Icon(Icons.dashboard), text: 'Visão geral'), Tab(icon: Icon(Icons.tune), text: 'Configurações'), Tab(icon: Icon(Icons.people), text: 'Usuários'), Tab(icon: Icon(Icons.psychology), text: 'IA privada')])),
      Expanded(child: TabBarView(children: [
        ListView(padding: const EdgeInsets.all(16), children: [Text('Olá, ${widget.userName}', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)), const SizedBox(height: 12),
          _metric('Usuários cadastrados', '$users', Icons.people), _metric('Contas bloqueadas', '$blocked', Icons.block), _metric('Movimentações', '$transactions', Icons.receipt_long),
          const Card(child: ListTile(leading: Icon(Icons.security), title: Text('Acesso protegido'), subtitle: Text('As permissões são verificadas no servidor.')))]),
        ListView(padding: const EdgeInsets.all(16), children: [const Text('Personalização e controle', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)), const SizedBox(height: 12),
          TextFormField(initialValue: appName, onChanged: (v) => appName = v, decoration: const InputDecoration(labelText: 'Nome do aplicativo', border: OutlineInputBorder())), const SizedBox(height: 12),
          TextFormField(initialValue: banner, onChanged: (v) => banner = v, decoration: const InputDecoration(labelText: 'Aviso / banner para usuários', border: OutlineInputBorder())), const SizedBox(height: 12),
          SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('Modo de manutenção'), subtitle: const Text('Bloqueia recursos para usuários e mantém o acesso administrativo.'), value: maintenance, onChanged: (v) => setState(() => maintenance = v)),
          TextFormField(initialValue: maintenanceMessage, onChanged: (v) => maintenanceMessage = v, maxLines: 2, decoration: const InputDecoration(labelText: 'Mensagem de manutenção', border: OutlineInputBorder())), const SizedBox(height: 16),
          FilledButton.icon(onPressed: save, icon: const Icon(Icons.save), label: const Text('Salvar configurações'))]),
        RefreshIndicator(onRefresh: load, child: ListView(padding: const EdgeInsets.all(12), children: [for (final raw in userRows) ...[Builder(builder: (_) { final u = Map<String, dynamic>.from(raw); return Card(child: ListTile(leading: Icon(u['role'] == 'admin' ? Icons.admin_panel_settings : Icons.person), title: Text(u['name']?.toString() ?? ''), subtitle: Text('${u['email']} • ${u['role']}'), trailing: u['role'] == 'admin' ? const Icon(Icons.lock) : TextButton(onPressed: () => toggleBlock(u), child: Text(u['blocked'] == true ? 'Desbloquear' : 'Bloquear')))); })]])),
        Column(children: [Container(width: double.infinity, padding: const EdgeInsets.all(12), color: Theme.of(context).colorScheme.tertiaryContainer, child: const Text('IA PRIVADA DO ADMINISTRADOR • Separada da IA dos clientes', textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.bold))),
          Expanded(child: ListView(padding: const EdgeInsets.all(12), children: [for (final m in aiMessages) Card(child: Padding(padding: const EdgeInsets.all(12), child: Text(m)))])), if (aiBusy) const LinearProgressIndicator(),
          Padding(padding: const EdgeInsets.all(10), child: Row(children: [Expanded(child: TextField(controller: aiInput, minLines: 1, maxLines: 3, decoration: const InputDecoration(hintText: 'Peça ajuda para planejar uma melhoria...', border: OutlineInputBorder()))), const SizedBox(width: 8), IconButton.filled(onPressed: aiBusy ? null : sendAdminAI, icon: const Icon(Icons.send))]))])
      ]))
    ])),
  );
  Widget _metric(String label, String value, IconData icon) => Card(child: ListTile(leading: Icon(icon, size: 30), title: Text(label), trailing: Text(value, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold))));
}

class HomePage extends StatefulWidget {
  final Api api;
  final String userName;
  const HomePage({super.key, required this.api, required this.userName});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int tab = 0;
  bool loading = true;
  bool busy = false;
  double balance = 0;
  List<dynamic> history = [];
  String? error;
  String appTitle = 'Minha Carteira';
  String bannerText = '';

  @override
  void initState() { super.initState(); refresh(); }

  Future<void> refresh() async {
    setState(() { loading = true; error = null; });
    try {
      final config = await widget.api.publicConfig();
      final w = await widget.api.wallet();
      final t = await widget.api.transactions();
      if (!mounted) return;
      setState(() {
        balance = (w['saldo'] as num?)?.toDouble() ?? 0;
        history = t;
        appTitle = config['appName']?.toString() ?? 'Minha Carteira';
        bannerText = config['bannerText']?.toString() ?? ''; 
      });
    } catch (e) {
      if (mounted) setState(() => error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> reward() async {
    if (busy) return;
    setState(() => busy = true);
    try {
      final result = await widget.api.claimReward();
      await refresh();
      if (mounted) snack(context, result['mensagem']?.toString() ?? 'Solicitação concluída.');
    } catch (e) {
      if (mounted) snack(context, e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  void logout() {
    widget.api.logout();
    Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (_) => const AuthPage()), (_) => false);
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      dashboard(),
      HistoryPage(items: history),
      AssistantPage(api: widget.api),
      const HelpPage(),
    ];
    return Scaffold(
      appBar: AppBar(title: Text(appTitle), actions: [
        IconButton(onPressed: refresh, icon: const Icon(Icons.refresh)),
        IconButton(onPressed: logout, icon: const Icon(Icons.logout)),
      ]),
      body: loading ? const Center(child: CircularProgressIndicator())
        : error != null ? Center(child: Padding(padding: const EdgeInsets.all(24),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text(error!, textAlign: TextAlign.center),
              const SizedBox(height: 12), FilledButton(onPressed: refresh, child: const Text('Tentar novamente'))
            ])))
        : pages[tab],
      bottomNavigationBar: NavigationBar(selectedIndex: tab, onDestinationSelected: (v) => setState(() => tab = v),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.account_balance_wallet_outlined), selectedIcon: Icon(Icons.account_balance_wallet), label: 'Carteira'),
          NavigationDestination(icon: Icon(Icons.receipt_long), label: 'Histórico'),
          NavigationDestination(icon: Icon(Icons.smart_toy_outlined), label: 'Assistente IA'),
          NavigationDestination(icon: Icon(Icons.help_outline), label: 'Ajuda'),
        ]),
    );
  }

  Widget dashboard() => RefreshIndicator(
    onRefresh: refresh,
    child: ListView(padding: const EdgeInsets.all(18), children: [
      Text('Olá, ${widget.userName}', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
      if (bannerText.isNotEmpty) ...[const SizedBox(height: 10), Card(child: Padding(padding: const EdgeInsets.all(12), child: Text(bannerText)))],
      const SizedBox(height: 16),
      Card(color: Theme.of(context).colorScheme.primaryContainer,
        child: Padding(padding: const EdgeInsets.all(22), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Saldo virtual disponível'),
          const SizedBox(height: 8),
          Text(money(balance), style: const TextStyle(fontSize: 34, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          const Text('O saldo exibido é controlado pelo servidor.'),
        ]))),
      const SizedBox(height: 16),
      FilledButton.icon(onPressed: busy ? null : reward,
        icon: const Icon(Icons.card_giftcard),
        label: Text(busy ? 'Processando...' : 'Consultar recompensa disponível')),
      const SizedBox(height: 12),
      OutlinedButton.icon(onPressed: () => snack(context, 'Saques Pix ainda não estão habilitados nesta versão.'),
        icon: const Icon(Icons.pix), label: const Text('Saques Pix — em preparação')),
      const SizedBox(height: 20),
      Card(child: ListTile(leading: const Icon(Icons.smart_toy), title: const Text('Precisa de ajuda?'),
        subtitle: const Text('Converse com o assistente do aplicativo.'),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => setState(() => tab = 2))),
      const SizedBox(height: 20),
      const Text('Últimas movimentações', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
      ...history.take(3).map((e) => TransactionTile(item: Map<String, dynamic>.from(e))),
    ]),
  );
}

class TransactionTile extends StatelessWidget {
  final Map<String, dynamic> item;
  const TransactionTile({super.key, required this.item});
  @override
  Widget build(BuildContext context) {
    final value = (item['valor'] as num?)?.toDouble() ?? 0;
    return Card(child: ListTile(
      leading: Icon(value >= 0 ? Icons.south_west : Icons.north_east, color: value >= 0 ? Colors.green : Colors.red),
      title: Text(item['descricao']?.toString() ?? 'Movimentação'),
      subtitle: Text(item['data']?.toString() ?? ''),
      trailing: Text(money(value), style: TextStyle(fontWeight: FontWeight.bold, color: value >= 0 ? Colors.green : Colors.red)),
    ));
  }
}

class HistoryPage extends StatelessWidget {
  final List<dynamic> items;
  const HistoryPage({super.key, required this.items});
  @override
  Widget build(BuildContext context) => items.isEmpty
    ? const Center(child: Text('Nenhuma movimentação ainda.'))
    : ListView.builder(padding: const EdgeInsets.all(12), itemCount: items.length,
        itemBuilder: (_, i) => TransactionTile(item: Map<String, dynamic>.from(items[i])));
}

class AssistantPage extends StatefulWidget {
  final Api api;
  const AssistantPage({super.key, required this.api});
  @override
  State<AssistantPage> createState() => _AssistantPageState();
}

class _AssistantPageState extends State<AssistantPage> {
  final controller = TextEditingController();
  final scroll = ScrollController();
  final messages = <Map<String, String>>[
    {'role': 'assistant', 'text': 'Olá! Sou o assistente da Carteira. Posso explicar como usar o app, consultar orientações e ajudar com dúvidas. Não peço senha, código ou chave Pix.'}
  ];
  bool sending = false;

  Future<void> send() async {
    final text = controller.text.trim();
    if (text.isEmpty || sending) return;
    controller.clear();
    setState(() { messages.add({'role': 'user', 'text': text}); sending = true; });
    try {
      final answer = await widget.api.askAssistant(text);
      if (mounted) setState(() => messages.add({'role': 'assistant', 'text': answer}));
    } catch (e) {
      if (mounted) setState(() => messages.add({'role': 'assistant', 'text': 'Não consegui conectar ao assistente agora. Confira sua conexão ou tente novamente mais tarde. ${e.toString().replaceFirst('Exception: ', '')}'}));
    } finally {
      if (mounted) {
        setState(() => sending = false);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (scroll.hasClients) scroll.animateTo(scroll.position.maxScrollExtent, duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
        });
      }
    }
  }

  @override
  void dispose() { controller.dispose(); scroll.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) => Column(children: [
    Container(width: double.infinity, padding: const EdgeInsets.all(12), color: Theme.of(context).colorScheme.surfaceContainer,
      child: const Text('Assistente virtual • Não compartilhe senhas, códigos SMS ou dados bancários confidenciais.', textAlign: TextAlign.center, style: TextStyle(fontSize: 12))),
    Expanded(child: ListView.builder(controller: scroll, padding: const EdgeInsets.all(12), itemCount: messages.length,
      itemBuilder: (_, i) {
        final m = messages[i];
        final mine = m['role'] == 'user';
        return Align(alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(constraints: const BoxConstraints(maxWidth: 310), margin: const EdgeInsets.symmetric(vertical: 5),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: mine ? Theme.of(context).colorScheme.primaryContainer : Theme.of(context).colorScheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(16)),
            child: Text(m['text'] ?? '')));
      })),
    if (sending) const LinearProgressIndicator(),
    Padding(padding: const EdgeInsets.fromLTRB(10, 8, 10, 12), child: Row(children: [
      Expanded(child: TextField(controller: controller, minLines: 1, maxLines: 4,
        decoration: const InputDecoration(hintText: 'Digite sua dúvida...', border: OutlineInputBorder()))),
      const SizedBox(width: 8),
      IconButton.filled(onPressed: sending ? null : send, icon: const Icon(Icons.send)),
    ])),
  ]);
}

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

const apiBaseUrl = String.fromEnvironment(
  'API_BASE_URL',
  defaultValue: 'http://10.0.2.2:3000/api',
);

const purple = Color(0xFF7138D8);
const darkPurple = Color(0xFF21103F);

void main() {
  runApp(const NexusBankApp());
}

class NexusBankApp extends StatelessWidget {
  const NexusBankApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'NEXUS BANK',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: purple,
          brightness: Brightness.light,
        ),
        scaffoldBackgroundColor: const Color(0xFFF7F5FC),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFFF7F5FC),
          foregroundColor: darkPurple,
          elevation: 0,
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide.none,
          ),
        ),
      ),
      home: const AuthPage(),
    );
  }
}

class Api {
  String? token;
  bool isAdmin = false;

  Uri uri(String path) => Uri.parse('$apiBaseUrl$path');

  Map<String, String> get headers => {
    'Content-Type': 'application/json',
    if (token != null) 'Authorization': 'Bearer $token',
  };

  dynamic decode(http.Response response) {
    dynamic data;
    try {
      data = jsonDecode(response.body);
    } catch (_) {
      throw Exception('Resposta inválida do servidor.');
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(
        data is Map
            ? (data['erro'] ?? data['error'] ?? 'Erro ${response.statusCode}')
                .toString()
            : 'Erro ${response.statusCode}',
      );
    }
    return data;
  }

  Future<Map<String, dynamic>> register(
    String nome,
    String email,
    String senha,
  ) async {
    final response = await http.post(
      uri('/auth/register'),
      headers: headers,
      body: jsonEncode({
        'nome': nome,
        'email': email,
        'senha': senha,
      }),
    ).timeout(const Duration(seconds: 20));

    return Map<String, dynamic>.from(decode(response));
  }

  Future<String> login(String email, String senha) async {
    final response = await http.post(
      uri('/auth/login'),
      headers: headers,
      body: jsonEncode({'email': email, 'senha': senha}),
    ).timeout(const Duration(seconds: 20));

    final data = Map<String, dynamic>.from(decode(response));
    token = data['token']?.toString();
    isAdmin = data['role'] == 'admin';

    if (token == null || token!.isEmpty) {
      throw Exception('O servidor não enviou o token de acesso.');
    }

    return data['nome']?.toString() ?? 'Pessoa';
  }

  Future<Map<String, dynamic>> wallet() async {
    final response = await http.get(
      uri('/wallet'),
      headers: headers,
    ).timeout(const Duration(seconds: 20));

    return Map<String, dynamic>.from(decode(response));
  }

  Future<List<dynamic>> transactions() async {
    final response = await http.get(
      uri('/transactions'),
      headers: headers,
    ).timeout(const Duration(seconds: 20));

    final data = decode(response);
    return List<dynamic>.from(data['transactions'] ?? []);
  }

  Future<Map<String, dynamic>> publicConfig() async {
    final response = await http.get(
      uri('/config'),
    ).timeout(const Duration(seconds: 20));

    return Map<String, dynamic>.from(decode(response));
  }

  Future<Map<String, dynamic>> claimReward() async {
    final response = await http.post(
      uri('/rewards/claim'),
      headers: headers,
      body: jsonEncode({'campaignId': 'welcome'}),
    ).timeout(const Duration(seconds: 20));

    return Map<String, dynamic>.from(decode(response));
  }

  void logout() {
    token = null;
    isAdmin = false;
  }
}

String money(dynamic value) {
  final number = value is num
      ? value.toDouble()
      : double.tryParse(value?.toString() ?? '') ?? 0;
  return 'R\$ ${number.toStringAsFixed(2).replaceAll('.', ',')}';
}

void showMessage(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(message)),
  );
}

class AuthPage extends StatefulWidget {
  const AuthPage({super.key});

  @override
  State<AuthPage> createState() => _AuthPageState();
}

class _AuthPageState extends State<AuthPage> {
  final api = Api();
  final nameController = TextEditingController();
  final emailController = TextEditingController();
  final passwordController = TextEditingController();

  bool registering = false;
  bool loading = false;
  bool obscure = true;

  @override
  void dispose() {
    nameController.dispose();
    emailController.dispose();
    passwordController.dispose();
    super.dispose();
  }

  Future<void> submit() async {
    final name = nameController.text.trim();
    final email = emailController.text.trim();
    final password = passwordController.text;

    if (email.isEmpty || password.isEmpty ||
        (registering && name.isEmpty)) {
      showMessage(context, 'Preencha todos os campos.');
      return;
    }

    setState(() => loading = true);

    try {
      if (registering) {
        await api.register(name, email, password);
      }

      final userName = await api.login(email, password);

      if (!mounted) return;

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => BankHome(api: api, userName: userName),
        ),
      );
    } catch (e) {
      if (mounted) {
        showMessage(
          context,
          e.toString().replaceFirst('Exception: ', ''),
        );
      }
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [darkPurple, Color(0xFF482080), purple],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(26),
              child: Column(
                children: [
                  Container(
                    width: 88,
                    height: 88,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.13),
                      borderRadius: BorderRadius.circular(26),
                      border: Border.all(color: Colors.white24),
                    ),
                    child: const Icon(
                      Icons.account_balance,
                      color: Colors.white,
                      size: 48,
                    ),
                  ),
                  const SizedBox(height: 18),
                  const Text(
                    'NEXUS BANK',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 30,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 3,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Seu mundo financeiro, conectado.',
                    style: TextStyle(color: Colors.white70),
                  ),
                  const SizedBox(height: 35),
                  Container(
                    padding: const EdgeInsets.all(22),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF9F7FF),
                      borderRadius: BorderRadius.circular(25),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          registering ? 'Criar conta' : 'Bem-vindo de volta',
                          style: const TextStyle(
                            fontSize: 23,
                            fontWeight: FontWeight.bold,
                            color: darkPurple,
                          ),
                        ),
                        const SizedBox(height: 20),
                        if (registering) ...[
                          TextField(
                            controller: nameController,
                            decoration: const InputDecoration(
                              labelText: 'Nome completo',
                              prefixIcon: Icon(Icons.person_outline),
                            ),
                          ),
                          const SizedBox(height: 12),
                        ],
                        TextField(
                          controller: emailController,
                          keyboardType: TextInputType.emailAddress,
                          decoration: const InputDecoration(
                            labelText: 'E-mail',
                            prefixIcon: Icon(Icons.email_outlined),
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: passwordController,
                          obscureText: obscure,
                          decoration: InputDecoration(
                            labelText: 'Senha',
                            prefixIcon: const Icon(Icons.lock_outline),
                            suffixIcon: IconButton(
                              onPressed: () =>
                                  setState(() => obscure = !obscure),
                              icon: Icon(obscure
                                  ? Icons.visibility
                                  : Icons.visibility_off),
                            ),
                          ),
                        ),
                        const SizedBox(height: 22),
                        FilledButton(
                          onPressed: loading ? null : submit,
                          style: FilledButton.styleFrom(
                            backgroundColor: purple,
                            padding: const EdgeInsets.all(16),
                          ),
                          child: loading
                              ? const CircularProgressIndicator(
                                  color: Colors.white,
                                )
                              : Text(registering ? 'CADASTRAR' : 'ENTRAR'),
                        ),
                        TextButton(
                          onPressed: loading
                              ? null
                              : () => setState(
                                  () => registering = !registering,
                                ),
                          child: Text(
                            registering
                                ? 'Já tenho uma conta. Entrar'
                                : 'Ainda não tenho conta. Cadastrar',
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 22),
                  const Text(
                    'NEXUS BANK • Acesso seguro',
                    style: TextStyle(color: Colors.white60, fontSize: 12),
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

class BankHome extends StatefulWidget {
  final Api api;
  final String userName;

  const BankHome({
    super.key,
    required this.api,
    required this.userName,
  });

  @override
  State<BankHome> createState() => _BankHomeState();
}

class _BankHomeState extends State<BankHome> {
  int tab = 0;
  bool loading = true;
  bool busy = false;
  String? error;
  double balance = 0;
  String bannerText = '';
  List<dynamic> history = [];

  @override
  void initState() {
    super.initState();
    refresh();
  }

  Future<void> refresh() async {
    setState(() {
      loading = true;
      error = null;
    });

    try {
      final results = await Future.wait([
        widget.api.wallet(),
        widget.api.transactions(),
      ]);

      final wallet = results[0] as Map<String, dynamic>;
      final transactions = results[1] as List<dynamic>;

      final rawBalance = wallet['saldo'] ??
          wallet['balance'] ??
          wallet['saldoDisponivel'] ??
          0;

      final newBalance = rawBalance is num
          ? rawBalance.toDouble()
          : double.tryParse(rawBalance.toString()) ?? 0;

      if (!mounted) return;

      setState(() {
        balance = newBalance;
        history = transactions;
        bannerText = wallet['mensagem']?.toString() ?? '';
        loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        error = e.toString().replaceFirst('Exception: ', '');
        loading = false;
      });
    }
  }

  Future<void> reward() async {
    setState(() => busy = true);
    try {
      final result = await widget.api.claimReward();
      if (!mounted) return;

      showMessage(
        context,
        result['mensagem']?.toString() ??
            result['message']?.toString() ??
            'Solicitação processada pelo servidor.',
      );
      await refresh();
    } catch (e) {
      if (mounted) {
        showMessage(
          context,
          e.toString().replaceFirst('Exception: ', ''),
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  void logout() {
    widget.api.logout();
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const AuthPage()),
      (_) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final pages = <Widget>[
      dashboard(),
      HistoryPage(items: history),
      const AssistantPage(),
      const HelpPage(),
      if (widget.api.isAdmin) const AdminPage(),
    ];

    final destinations = <NavigationDestination>[
      const NavigationDestination(
        icon: Icon(Icons.account_balance_wallet_outlined),
        selectedIcon: Icon(Icons.account_balance_wallet),
        label: 'Carteira',
      ),
      const NavigationDestination(
        icon: Icon(Icons.receipt_long),
        label: 'Histórico',
      ),
      const NavigationDestination(
        icon: Icon(Icons.smart_toy_outlined),
        label: 'Assistente',
      ),
      const NavigationDestination(
        icon: Icon(Icons.help_outline),
        label: 'Ajuda',
      ),
      if (widget.api.isAdmin)
        const NavigationDestination(
          icon: Icon(Icons.admin_panel_settings_outlined),
          label: 'Admin',
        ),
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'NEXUS BANK',
          style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 1.5),
        ),
        actions: [
          IconButton(
            onPressed: refresh,
            icon: const Icon(Icons.refresh),
          ),
          IconButton(
            onPressed: logout,
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.cloud_off, size: 48),
                        const SizedBox(height: 12),
                        Text(error!, textAlign: TextAlign.center),
                        const SizedBox(height: 12),
                        FilledButton(
                          onPressed: refresh,
                          child: const Text('Tentar novamente'),
                        ),
                      ],
                    ),
                  ),
                )
              : IndexedStack(
                  index: tab,
                  children: pages,
                ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: tab,
        onDestinationSelected: (value) => setState(() => tab = value),
        destinations: destinations,
      ),
    );
  }

  Widget dashboard() {
    return RefreshIndicator(
      onRefresh: refresh,
      child: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          Text(
            'Olá, ${widget.userName}',
            style: const TextStyle(
              fontSize: 23,
              fontWeight: FontWeight.bold,
              color: darkPurple,
            ),
          ),
          const SizedBox(height: 5),
          const Text('Que bom ter você por aqui.'),
          if (bannerText.isNotEmpty) ...[
            const SizedBox(height: 12),
            Card(child: Padding(
              padding: const EdgeInsets.all(14),
              child: Text(bannerText),
            )),
          ],
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(23),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [darkPurple, purple, Color(0xFF9B68ED)],
              ),
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: purple.withValues(alpha: 0.22),
                  blurRadius: 18,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.account_balance_wallet, color: Colors.white70),
                    SizedBox(width: 8),
                    Text(
                      'SALDO VIRTUAL DISPONÍVEL',
                      style: TextStyle(color: Colors.white70, fontSize: 12),
                    ),
                  ],
                ),
                const SizedBox(height: 15),
                Text(
                  money(balance),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Valor informado pelo servidor.',
                  style: TextStyle(color: Colors.white70, fontSize: 12),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          FilledButton.icon(
            onPressed: busy ? null : reward,
            icon: const Icon(Icons.card_giftcard),
            label: Text(
              busy ? 'Processando...' : 'Consultar recompensa',
            ),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.all(15),
              backgroundColor: purple,
            ),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: () => showMessage(
              context,
              'Saques Pix ainda não estão habilitados nesta versão.',
            ),
            icon: const Icon(Icons.pix),
            label: const Text('Saques Pix — em preparação'),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.all(15),
            ),
          ),
          const SizedBox(height: 22),
          Card(
            child: ListTile(
              leading: const CircleAvatar(
                backgroundColor:
class HelpPage extends StatelessWidget {
  const HelpPage({super.key});
  @override
  Widget build(BuildContext context) => ListView(padding: const EdgeInsets.all(16), children: const [
    Text('Central de ajuda', style: TextStyle(fontSize: 23, fontWeight: FontWeight.bold)),
    SizedBox(height: 12),
    ExpansionTile(title: Text('Como funciona o saldo?'), children: [ListTile(title: Text('O saldo é informado pelo servidor e cada movimentação deve aparecer no histórico.'))]),
    ExpansionTile(title: Text('A recompensa é garantida?'), children: [ListTile(title: Text('Não. Recompensas dependem das regras e do orçamento disponível de cada campanha. Não existe multiplicação garantida de dinheiro.'))]),
    ExpansionTile(title: Text('Posso sacar via Pix?'), children: [ListTile(title: Text('Ainda não nesta versão. O saque só poderá ser ativado depois da integração com uma instituição de pagamento autorizada.'))]),
    ExpansionTile(title: Text('O assistente pede minha senha?'), children: [ListTile(title: Text('Nunca. Não envie senhas, códigos de autenticação ou chaves privadas no chat.'))]),
  ]);
}
