import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import 'package:llama_flutter_android/llama_flutter_android.dart' as llama;

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const LocalMindApp());
}

class LocalMindApp extends StatelessWidget {
  const LocalMindApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'LocalMind',
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF101114),
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF9B8AFF),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: const ChatPage(),
    );
  }
}

class ChatMessage {
  final int? id;
  final String text;
  final bool isUser;
  final int createdAt;
  final String conversationId;

  const ChatMessage({
    this.id,
    required this.text,
    required this.isUser,
    required this.createdAt,
    this.conversationId = 'default',
  });

  Map<String, Object?> toMap() {
    return {
      'text': text,
      'is_user': isUser ? 1 : 0,
      'created_at': createdAt,
      'conversation_id': conversationId,
    };
  }

  factory ChatMessage.fromMap(Map<String, Object?> map) {
    return ChatMessage(
      id: map['id'] as int,
      text: map['text'] as String,
      isUser: map['is_user'] == 1,
      createdAt: map['created_at'] as int,
      conversationId: map['conversation_id'] as String? ?? 'default',
    );
  }
}

class ChatDatabase {
  static final ChatDatabase instance = ChatDatabase._();
  ChatDatabase._();

  Database? _database;

  Future<Database> get database async {
    if (_database != null) return _database!;

    final databasePath = p.join(await getDatabasesPath(), 'localmind.db');

    _database = await openDatabase(
      databasePath,
      version: 3,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE conversations (
            id TEXT PRIMARY KEY,
            title TEXT NOT NULL,
            created_at INTEGER NOT NULL
          )
        ''');

        await db.execute('''
          CREATE TABLE messages (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            text TEXT NOT NULL,
            is_user INTEGER NOT NULL,
            created_at INTEGER NOT NULL,
            conversation_id TEXT NOT NULL DEFAULT 'default'
          )
        ''');

        await db.execute('''
          CREATE TABLE memories (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            fact TEXT NOT NULL UNIQUE,
            created_at INTEGER NOT NULL
          )
        ''');

        await db.insert('conversations', {
          'id': 'default',
          'title': 'My first chat',
          'created_at': DateTime.now().millisecondsSinceEpoch,
        });
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await db.execute('''
            CREATE TABLE memories (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              fact TEXT NOT NULL UNIQUE,
              created_at INTEGER NOT NULL
            )
          ''');
        }

        if (oldVersion < 3) {
          await db.execute('''
            CREATE TABLE conversations (
              id TEXT PRIMARY KEY,
              title TEXT NOT NULL,
              created_at INTEGER NOT NULL
            )
          ''');

          await db.execute('''
            ALTER TABLE messages
            ADD COLUMN conversation_id TEXT NOT NULL
            DEFAULT 'default'
          ''');

          await db.insert('conversations', {
            'id': 'default',
            'title': 'My first chat',
            'created_at': DateTime.now().millisecondsSinceEpoch,
          });
        }
      },
    );

    return _database!;
  }

  Future<List<ChatMessage>> getMessages({
    String conversationId = 'default',
  }) async {
    final db = await database;
    final rows = await db.query(
      'messages',
      where: 'conversation_id = ?',
      whereArgs: [conversationId],
      orderBy: 'id ASC',
    );

    return rows.map(ChatMessage.fromMap).toList();
  }

  Future<void> insertMessage(ChatMessage message) async {
    final db = await database;
    await db.insert('messages', message.toMap());
  }

  Future<void> clearMessages({String conversationId = 'default'}) async {
    final db = await database;
    await db.delete(
      'messages',
      where: 'conversation_id = ?',
      whereArgs: [conversationId],
    );
  }

  Future<List<Map<String, Object?>>> getConversations() async {
    final db = await database;
    return db.query('conversations', orderBy: 'created_at DESC');
  }

  Future<String> createConversation() async {
    final db = await database;
    final id = DateTime.now().microsecondsSinceEpoch.toString();

    await db.insert('conversations', {
      'id': id,
      'title': 'New conversation',
      'created_at': DateTime.now().millisecondsSinceEpoch,
    });

    return id;
  }

  Future<void> updateConversationTitle(
    String conversationId,
    String title,
  ) async {
    final db = await database;
    await db.update(
      'conversations',
      {'title': title},
      where: 'id = ?',
      whereArgs: [conversationId],
    );
  }

  // Delete one conversation and all its messages.
  Future<void> deleteConversation(String conversationId) async {
    final db = await database;

    await db.transaction((txn) async {
      await txn.delete(
        'messages',
        where: 'conversation_id = ?',
        whereArgs: [conversationId],
      );

      await txn.delete(
        'conversations',
        where: 'id = ?',
        whereArgs: [conversationId],
      );
    });
  }

  // Delete every conversation and all associated messages.
  Future<void> deleteAllConversations() async {
    final db = await database;

    await db.transaction((txn) async {
      await txn.delete('messages');
      await txn.delete('conversations');
    });
  }

  Future<List<Map<String, Object?>>> getMemories() async {
    final db = await database;
    return db.query('memories', orderBy: 'id ASC');
  }

  Future<void> saveMemory(String fact) async {
    final cleanedFact = fact.trim();
    if (cleanedFact.isEmpty) return;

    final db = await database;
    await db.insert('memories', {
      'fact': cleanedFact,
      'created_at': DateTime.now().millisecondsSinceEpoch,
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
  }

  Future<void> deleteMemory(int id) async {
    final db = await database;
    await db.delete('memories', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> clearMemories() async {
    final db = await database;
    await db.delete('memories');
  }
}

class ChatPage extends StatefulWidget {
  const ChatPage({super.key});

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  final TextEditingController _input = TextEditingController();
  final ScrollController _scroll = ScrollController();
  final ChatDatabase _database = ChatDatabase.instance;
  final llama.LlamaController _ai = llama.LlamaController();

  final List<ChatMessage> _messages = [];

  bool _isTyping = false;
  bool _isLoading = true;
  bool _isModelLoading = true;
  bool _modelReady = false;
  String _modelStatus = 'Loading local AI model...';

  String _currentConversationId = 'default';

  static const String _modelFileName = 'Llama-3.2-1B-Instruct-Q4_K_M.gguf';

  @override
  void initState() {
    super.initState();
    _loadMessages();
    _loadAiModel();
  }

  Future<void> _openConversation(String conversationId) async {
    if (_isTyping) return;

    setState(() {
      _currentConversationId = conversationId;
      _isLoading = true;
    });

    try {
      final savedMessages = await _database.getMessages(
        conversationId: conversationId,
      );

      if (!mounted) return;

      setState(() {
        _messages
          ..clear()
          ..addAll(savedMessages);
        _isLoading = false;
      });

      _scrollToBottom();
    } catch (e) {
      if (!mounted) return;

      setState(() => _isLoading = false);
      _showError('Could not open conversation: $e');
    }
  }

  Future<void> _newConversation() async {
    if (_isTyping) return;

    try {
      final conversationId = await _database.createConversation();

      if (!mounted) return;

      setState(() {
        _currentConversationId = conversationId;
        _messages.clear();
      });

      _scrollToBottom();

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('New conversation started!'),
          duration: Duration(seconds: 2),
        ),
      );
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not create conversation: $e')),
      );
    }
  }

  Future<void> _loadMessages() async {
    try {
      final savedMessages = await _database.getMessages(
        conversationId: _currentConversationId,
      );

      if (!mounted) return;

      setState(() {
        _messages
          ..clear()
          ..addAll(savedMessages);
        _isLoading = false;
      });

      _scrollToBottom();
    } catch (e) {
      if (!mounted) return;

      setState(() => _isLoading = false);
      _showError('Could not load messages: $e');
    }
  }

  Future<void> _loadAiModel() async {
    try {
      // The model was copied into <app-private-dir>/files/models by ADB.
      // getDatabasesPath() ends in /databases, so its parent is the app-private dir.
      final appPrivateDir = p.dirname(await getDatabasesPath());
      final modelPath = p.join(
        appPrivateDir,
        'files',
        'models',
        _modelFileName,
      );

      await _ai.loadModel(modelPath: modelPath, threads: 2, contextSize: 1024);

      if (!mounted) return;
      setState(() {
        _modelReady = true;
        _isModelLoading = false;
        _modelStatus = 'Offline AI ready · messages stay on this device';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _modelReady = false;
        _isModelLoading = false;
        _modelStatus = 'AI model failed to load';
      });
      _showError('Could not load the local AI model: $e');
    }
  }

  Future<void> _sendMessage() async {
    final text = _input.text.trim();

    if (text.isEmpty || _isTyping || _isLoading) return;

    if (!_modelReady) {
      _showError(
        _isModelLoading ? 'The offline AI is still loading. Please wait.' : 'The AI model is not ready. Check the model file and restart LocalMind.',
      );
      return;
    }

    // Save an explicit memory command.
    final rememberMatch = RegExp(
      r'^remember that\s+(.+?)[.! ]*$',
      caseSensitive: false,
    ).firstMatch(text);

    if (rememberMatch != null) {
      final fact = rememberMatch.group(1)?.trim() ?? '';

      if (fact.isNotEmpty) {
        try {
          await _database.saveMemory(fact);

          final userMessage = ChatMessage(
            text: text,
            isUser: true,
            createdAt: DateTime.now().millisecondsSinceEpoch,
            conversationId: _currentConversationId,
          );

          final reply = ChatMessage(
            text:
                'I saved that in my on-device memory: "$fact". '
                'You can view or delete it using the memory icon.',
            isUser: false,
            createdAt: DateTime.now().millisecondsSinceEpoch,
            conversationId: _currentConversationId,
          );

          await _database.insertMessage(userMessage);
          await _database.insertMessage(reply);

          if (!mounted) return;

          _input.clear();
          setState(() => _messages.addAll([userMessage, reply]));
          _scrollToBottom();
        } catch (e) {
          _showError('Could not save memory: $e');
        }

        return;
      }
    }

    _input.clear();

    final userMessage = ChatMessage(
      text: text,
      isUser: true,
      createdAt: DateTime.now().millisecondsSinceEpoch,
      conversationId: _currentConversationId,
    );

    final assistantPlaceholder = ChatMessage(
      text: '',
      isUser: false,
      createdAt: DateTime.now().millisecondsSinceEpoch,
      conversationId: _currentConversationId,
    );

    setState(() {
      _messages.add(userMessage);
      _messages.add(assistantPlaceholder);
      _isTyping = true;
    });

    _scrollToBottom();

    final placeholderIndex = _messages.length - 1;

    try {
      await _database.insertMessage(userMessage);

      // Set the conversation title using the first user message.
      final userMessages = _messages
          .where((message) => message.isUser && message.text.isNotEmpty)
          .toList();

      if (userMessages.length == 1) {
        final title = text.length > 35 ? '${text.substring(0, 35)}...' : text;

        await _database.updateConversationTitle(_currentConversationId, title);
      }

      // Keep only recent messages to reduce memory usage.

      // Keep only recent messages to reduce memory usage.
      final recentMessages = _messages
          .where((message) => message.text.isNotEmpty)
          .toList();

      final conversation = recentMessages.length > 8
          ? recentMessages.sublist(recentMessages.length - 8)
          : recentMessages;

      // Add long-term memories to the AI prompt.
      final savedMemories = await _database.getMemories();

      final memoryContext = savedMemories.isEmpty
          ? 'No long-term memories have been saved.'
          : savedMemories.map((memory) => '- ${memory['fact']}').join('\n');

      final promptMessages = <llama.ChatMessage>[
        llama.ChatMessage(
          role: 'system',
          content:
              "You are LocalMind, a friendly and helpful offline AI assistant. "
              "Answer clearly and concisely. Use saved memories when relevant. "
              "Do not invent personal facts.\n\n"
              "Saved long-term memories:\n$memoryContext",
        ),
        ...conversation.map(
          (message) => llama.ChatMessage(
            role: message.isUser ? 'user' : 'assistant',
            content: message.text,
          ),
        ),
      ];

      final response = StringBuffer();

      await for (final token in _ai.generateChat(
        messages: promptMessages,
        maxTokens: 120,
        temperature: 0.3,
        topP: 0.85,
        topK: 40,
        repeatPenalty: 1.15,
      )) {
        response.write(token);

        if (!mounted) return;

        setState(() {
          _messages[placeholderIndex] = ChatMessage(
            text: response.toString(),
            isUser: false,
            createdAt: assistantPlaceholder.createdAt,
            conversationId: _currentConversationId,
          );
        });

        _scrollToBottom();
      }

      final replyText = response.toString().trim();

      if (replyText.isEmpty) {
        throw Exception('The model returned an empty response.');
      }

      final reply = ChatMessage(
        text: replyText,
        isUser: false,
        createdAt: DateTime.now().millisecondsSinceEpoch,
        conversationId: _currentConversationId,
      );

      await _database.insertMessage(reply);

      if (!mounted) return;

      setState(() {
        _messages[placeholderIndex] = reply;
        _isTyping = false;
      });

      _scrollToBottom();
    } catch (e) {
      if (!mounted) return;

      setState(() {
        if (placeholderIndex < _messages.length) {
          _messages.removeAt(placeholderIndex);
        }
        _isTyping = false;
      });

      _showError('AI response failed: $e');
    }
  }

  Future<void> _showMemories() async {
    final memories = await _database.getMemories();
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, refreshDialog) => AlertDialog(
          title: const Text('LocalMind memory'),
          content: SizedBox(
            width: double.maxFinite,
            child: memories.isEmpty
                ? const Text(
                    'No saved facts yet. Try: Remember that my name is Clark.',
                  )
                : ListView.builder(
                    shrinkWrap: true,
                    itemCount: memories.length,
                    itemBuilder: (context, index) {
                      final memory = memories[index];
                      return ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(memory['fact'] as String),
                        trailing: IconButton(
                          tooltip: 'Delete memory',
                          icon: const Icon(Icons.delete_outline),
                          onPressed: () async {
                            await _database.deleteMemory(memory['id'] as int);
                            memories.removeAt(index);
                            refreshDialog(() {});
                          },
                        ),
                      );
                    },
                  ),
          ),
          actions: [
            if (memories.isNotEmpty)
              TextButton(
                onPressed: () async {
                  await _database.clearMemories();
                  memories.clear();
                  refreshDialog(() {});
                },
                child: const Text('Clear all memories'),
              ),
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Close'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _clearChat() async {
    if (_isTyping || _isLoading) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear conversation?'),
        content: const Text(
          'This will permanently delete the saved messages on this device.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await _database.clearMessages(conversationId: _currentConversationId);

      if (!mounted) return;

      setState(() => _messages.clear());
    } catch (e) {
      _showError('Could not clear messages: $e');
    }
  }

  void _showError(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;

      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    });
  }

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    _ai.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.sizeOf(context).width;

    final drawerWidth = (screenWidth * 0.82).clamp(280.0, 420.0);

    return Scaffold(
      drawer: Drawer(
        backgroundColor: const Color(0xFF17181C),
        width: drawerWidth,
        child: SafeArea(
          child: Column(
            children: [
              // Sidebar header
              Padding(
                padding: const EdgeInsets.all(20),
                child: Row(
                  children: [
                    const CircleAvatar(
                      backgroundColor: Color(0xFF29243F),
                      child: Icon(Icons.auto_awesome, color: Color(0xFFB6A8FF)),
                    ),
                    const SizedBox(width: 12),
                    const Text(
                      'LocalMind',
                      style: TextStyle(
                        fontSize: 21,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
              ),

              // New conversation button
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: () {
                      Navigator.pop(context);
                      _newConversation();
                    },
                    icon: const Icon(Icons.add),
                    label: const Text('New conversation'),
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF51458A),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                  ),
                ),
              ),

              const Padding(
                padding: EdgeInsets.fromLTRB(20, 25, 20, 10),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'YOUR CHATS',
                    style: TextStyle(
                      color: Colors.white54,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.2,
                    ),
                  ),
                ),
              ),

              // Conversation history
              Expanded(
                child: FutureBuilder<List<Map<String, Object?>>>(
                  future: _database.getConversations(),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }

                    if (snapshot.hasError) {
                      return const Center(
                        child: Text('Could not load conversations.'),
                      );
                    }

                    final conversations = snapshot.data ?? [];

                    if (conversations.isEmpty) {
                      return const Center(
                        child: Text(
                          'No conversations yet.',
                          style: TextStyle(color: Colors.white54),
                        ),
                      );
                    }

                    return ListView.builder(
                      itemCount: conversations.length,
                      itemBuilder: (context, index) {
                        final conversation = conversations[index];
                        final id = conversation['id'] as String;
                        final title = conversation['title'] as String;

                        final isCurrent = id == _currentConversationId;

                        return ListTile(
                          selected: isCurrent,
                          selectedTileColor: const Color(0xFF29243F),

                          leading: const Icon(
                            Icons.chat_bubble_outline,
                            size: 20,
                          ),

                          title: Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 14),
                          ),

                          onTap: () {
                            Navigator.pop(context);
                            _openConversation(id);
                          },

                          trailing: PopupMenuButton<String>(
                            icon: const Icon(
                              Icons.more_vert,
                              color: Colors.white70,
                              size: 20,
                            ),
                            color: const Color(0xFF29232F),

                            onSelected: (value) {
                              if (value == 'rename') {
                                _renameConversation(id, title);
                              } else if (value == 'delete') {
                                _deleteOneConversation(id);
                              }
                            },

                            itemBuilder: (context) => [
                              const PopupMenuItem<String>(
                                value: 'rename',
                                child: Row(
                                  children: [
                                    Icon(Icons.edit_outlined, size: 18),
                                    SizedBox(width: 10),
                                    Text('Rename'),
                                  ],
                                ),
                              ),

                              const PopupMenuItem<String>(
                                value: 'delete',
                                child: Row(
                                  children: [
                                    Icon(
                                      Icons.delete_outline,
                                      color: Colors.redAccent,
                                      size: 18,
                                    ),
                                    SizedBox(width: 10),
                                    Text(
                                      'Delete',
                                      style: TextStyle(color: Colors.redAccent),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    );
                  },
                ),
              ),

              const Divider(color: Colors.white12),

              // Delete current conversation messages
              ListTile(
                leading: const Icon(
                  Icons.delete_sweep_outlined,
                  color: Colors.redAccent,
                ),
                title: const Text(
                  'Delete all conversations',
                  style: TextStyle(color: Colors.redAccent),
                ),
                onTap: () {
                  Navigator.pop(context);
                  _deleteAllConversations();
                },
              ),

              ListTile(
                leading: const Icon(Icons.cleaning_services_outlined),
                title: const Text('Clear current chat'),
                onTap: () {
                  Navigator.pop(context);
                  _clearChat();
                },
              ),

              // Memory access
              ListTile(
                leading: const Icon(Icons.psychology_alt_outlined),
                title: const Text('Long-term memory'),
                onTap: () {
                  Navigator.pop(context);
                  _showMemories();
                },
              ),

              const Padding(
                padding: EdgeInsets.all(16),
                child: Text(
                  'LocalMind · Offline AI',
                  style: TextStyle(color: Colors.white38, fontSize: 11),
                ),
              ),
            ],
          ),
        ),
      ),
      appBar: AppBar(
        title: const Row(
          children: [
            CircleAvatar(
              radius: 20,
              backgroundColor: Color(0xFF29243F),
              child: Icon(Icons.auto_awesome, color: Color(0xFFB6A8FF)),
            ),
            SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'LocalMind',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 19),
                ),
                Text(
                  'Your private AI · on-device memory',
                  style: TextStyle(fontSize: 11, color: Colors.white54),
                ),
              ],
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Long-term memory',
            onPressed: _showMemories,
            icon: const Icon(Icons.psychology_alt_outlined),
          ),
        ],
      ),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            color: const Color(0xFF19191F),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(
              children: [
                const Icon(
                  Icons.offline_bolt,
                  size: 17,
                  color: Color(0xFFB6A8FF),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _modelStatus,
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _messages.isEmpty
                ? const Center(
                    child: Padding(
                      padding: EdgeInsets.all(28),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.auto_awesome,
                            size: 58,
                            color: Color(0xFFB6A8FF),
                          ),
                          SizedBox(height: 20),
                          Text(
                            'Your AI. Your device.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 25,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          SizedBox(height: 10),
                          Text(
                            'Your conversations will stay on this device.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Colors.white60,
                              height: 1.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                : ListView.builder(
                    controller: _scroll,
                    padding: EdgeInsets.symmetric(
                      horizontal: MediaQuery.sizeOf(context).width < 360
                          ? 10
                          : 16,
                      vertical: 16,
                    ),
                    itemCount: _messages.length + (_isTyping ? 1 : 0),
                    itemBuilder: (context, index) {
                      if (index == _messages.length) {
                        return Align(
                          alignment: Alignment.centerLeft,
                          child: Padding(
                            padding: EdgeInsets.all(12),
                            child: Text(
                              _modelReady
                                  ? 'LocalMind is thinking...'
                                  : 'Loading offline AI...',
                              style: TextStyle(color: Colors.white54),
                            ),
                          ),
                        );
                      }

                      final message = _messages[index];

                      return LayoutBuilder(
                        builder: (context, constraints) {
                          final bubbleMaxWidth = constraints.maxWidth > 700
                              ? 560.0
                              : constraints.maxWidth * 0.88;

                          return Align(
                            alignment: message.isUser
                                ? Alignment.centerRight
                                : Alignment.centerLeft,
                            child: Container(
                              constraints: BoxConstraints(
                                maxWidth: bubbleMaxWidth,
                              ),
                              margin: const EdgeInsets.only(bottom: 14),
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: message.isUser
                                    ? const Color(0xFF51458A)
                                    : const Color(0xFF22232A),
                                borderRadius: BorderRadius.circular(18),
                              ),
                              child: Text(
                                message.text,
                                style: const TextStyle(
                                  fontSize: 15,
                                  height: 1.5,
                                ),
                              ),
                            ),
                          );
                        },
                      );
                    },
                  ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                MediaQuery.sizeOf(context).width < 360 ? 8 : 12,
                8,
                MediaQuery.sizeOf(context).width < 360 ? 8 : 12,
                12,
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: TextField(
                      controller: _input,
                      minLines: 1,
                      maxLines: 5,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _sendMessage(),
                      decoration: InputDecoration(
                        hintText: 'Message LocalMind...',
                        filled: true,
                        fillColor: const Color(0xFF22232A),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(25),
                          borderSide: BorderSide.none,
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 18,
                          vertical: 14,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    onPressed: _isTyping || _isLoading ? null : _sendMessage,
                    icon: const Icon(Icons.arrow_upward),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _renameConversation(
    String conversationId,
    String currentTitle,
  ) async {
    final newTitle = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return _RenameConversationDialog(currentTitle: currentTitle);
      },
    );

    if (newTitle == null || !mounted) return;

    try {
      await _database.updateConversationTitle(conversationId, newTitle);

      if (!mounted) return;

      setState(() {});

      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Conversation renamed!')));
    } catch (e) {
      if (mounted) {
        _showError('Could not rename conversation: $e');
      }
    }
  }

  Future<void> _deleteOneConversation(String conversationId) async {
    if (_isTyping || _isLoading) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete conversation?'),
        content: const Text(
          'This will permanently delete this conversation '
          'and all its messages. This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await _database.deleteConversation(conversationId);

      if (!mounted) return;

      if (conversationId == _currentConversationId) {
        final newId = await _database.createConversation();

        if (!mounted) return;

        setState(() {
          _currentConversationId = newId;
          _messages.clear();
        });
      } else {
        setState(() {});
      }

      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Conversation deleted.')));
    } catch (e) {
      _showError('Could not delete conversation: $e');
    }
  }

  Future<void> _deleteAllConversations() async {
    if (_isTyping || _isLoading) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete all conversations?'),
        content: const Text(
          'This will permanently delete ALL conversations '
          'and their messages. Your long-term memories will '
          'not be deleted. This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Delete All'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await _database.deleteAllConversations();

      final newId = await _database.createConversation();

      if (!mounted) return;

      setState(() {
        _currentConversationId = newId;
        _messages.clear();
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('All conversations deleted.')),
      );
    } catch (e) {
      _showError('Could not delete conversations: $e');
    }
  }
}

class _RenameConversationDialog extends StatefulWidget {
  final String currentTitle;

  const _RenameConversationDialog({required this.currentTitle});

  @override
  State<_RenameConversationDialog> createState() =>
      _RenameConversationDialogState();
}

class _RenameConversationDialogState extends State<_RenameConversationDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.currentTitle);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Rename conversation'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        maxLength: 60,
        decoration: const InputDecoration(
          hintText: 'Enter conversation name',
          border: OutlineInputBorder(),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () {
            Navigator.pop(context);
          },
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            final title = _controller.text.trim();

            if (title.isNotEmpty) {
              Navigator.pop(context, title);
            }
          },
          child: const Text('Save'),
        ),
      ],
    );
  }
}
