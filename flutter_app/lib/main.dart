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
