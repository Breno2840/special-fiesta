import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // Força modo paisagem para TVs e Tablets
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.landscapeRight,
    DeviceOrientation.landscapeLeft,
  ]).then((_) {
    runApp(const NeonIPTVApp());
  });
}

// ==========================================
// 1. MODELOS
// ==========================================
class IptvChannel {
  final String name;
  final String url;

  IptvChannel({required this.name, required this.url});
}

// ==========================================
// 2. SERVIÇOS (Lógica, Parser e Storage)
// ==========================================
class IptvService {
  static const String _lastChannelKey = 'last_channel_url';

  // Parser super leve de M3U
  static List<IptvChannel> parseM3u(String m3uContent) {
    final lines = m3uContent.split('\n');
    final List<IptvChannel> channels = [];
    String currentName = '';

    for (var line in lines) {
      line = line.trim();
      if (line.startsWith('#EXTINF:')) {
        // Extrai o nome do canal (tudo após a última vírgula)
        final parts = line.split(',');
        currentName = parts.length > 1 ? parts.last.trim() : 'Canal Desconhecido';
      } else if (line.isNotEmpty && !line.startsWith('#')) {
        // É a URL do stream
        channels.add(IptvChannel(name: currentName, url: line));
        currentName = '';
      }
    }
    return channels;
  }

  // Busca a lista de uma URL
  static Future<List<IptvChannel>> fetchPlaylist(String url) async {
    try {
      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        return parseM3u(response.body);
      }
    } catch (e) {
      debugPrint('Erro ao carregar playlist: $e');
    }
    return [];
  }

  // Salvar e recuperar o último canal assistido
  static Future<void> saveLastChannel(String url) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_lastChannelKey, url);
  }

  static Future<String?> getLastChannel() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_lastChannelKey);
  }
}

// ==========================================
// 3. APLICATIVO E TEMAS
// ==========================================
class NeonIPTVApp extends StatelessWidget {
  const NeonIPTVApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Neon IPTV',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.deepPurple,
          brightness: Brightness.dark,
        ),
        scaffoldBackgroundColor: Colors.black,
      ),
      home: const PlayerScreen(),
    );
  }
}

// ==========================================
// 4. INTERFACE PRINCIPAL (UI / Player)
// ==========================================
class PlayerScreen extends StatefulWidget {
  const PlayerScreen({super.key});

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  VideoPlayerController? _controller;
  List<IptvChannel> _channels = [];
  IptvChannel? _currentChannel;
  
  bool _isMenuVisible = true;
  Timer? _uiHideTimer;
  final FocusNode _listFocusNode = FocusNode();

  // URL de teste (substitua pela sua lista M3U local ou remota)
  final String _playlistUrl = 'https://iptv-org.github.io/iptv/countries/br.m3u';

  @override
  void initState() {
    super.initState();
    _initApp();
  }

  Future<void> _initApp() async {
    final channels = await IptvService.fetchPlaylist(_playlistUrl);
    if (channels.isEmpty) return;

    setState(() {
      _channels = channels;
    });

    final lastUrl = await IptvService.getLastChannel();
    IptvChannel channelToPlay = channels.first;

    if (lastUrl != null) {
      final match = channels.where((c) => c.url == lastUrl).toList();
      if (match.isNotEmpty) channelToPlay = match.first;
    }

    _playChannel(channelToPlay);
    _startUiTimer();
  }

  void _playChannel(IptvChannel channel) async {
    if (_currentChannel?.url == channel.url) return;

    if (_controller != null) {
      await _controller!.dispose();
    }

    setState(() {
      _currentChannel = channel;
    });

    IptvService.saveLastChannel(channel.url);

    _controller = VideoPlayerController.networkUrl(Uri.parse(channel.url))
      ..initialize().then((_) {
        setState(() {
          _controller!.play();
        });
      });
  }

  // Gerenciamento da UI (esconder menu automaticamente na TV)
  void _startUiTimer() {
    _uiHideTimer?.cancel();
    _uiHideTimer = Timer(const Duration(seconds: 5), () {
      if (mounted && _isMenuVisible) {
        setState(() => _isMenuVisible = false);
      }
    });
  }

  void _toggleMenu() {
    setState(() {
      _isMenuVisible = !_isMenuVisible;
      if (_isMenuVisible) {
        _listFocusNode.requestFocus();
        _startUiTimer();
      }
    });
  }

  @override
  void dispose() {
    _controller?.dispose();
    _uiHideTimer?.cancel();
    _listFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // Atalhos de teclado/controle remoto (DPAD)
      body: CallbackShortcuts(
        bindings: <ShortcutActivator, VoidCallback>{
          const SingleActivator(LogicalKeyboardKey.select): _toggleMenu,
          const SingleActivator(LogicalKeyboardKey.enter): _toggleMenu,
          const SingleActivator(LogicalKeyboardKey.arrowRight): () => setState(() => _isMenuVisible = false),
          const SingleActivator(LogicalKeyboardKey.arrowLeft): () => setState(() => _isMenuVisible = true),
        },
        child: Focus(
          autofocus: true,
          child: GestureDetector(
            onTap: _toggleMenu,
            onPanUpdate: (_) => _startUiTimer(),
            child: Stack(
              children: [
                // 1. Layer do Player de Vídeo
                Container(
                  color: Colors.black,
                  child: Center(
                    child: _controller != null && _controller!.value.isInitialized
                        ? AspectRatio(
                            aspectRatio: _controller!.value.aspectRatio,
                            child: VideoPlayer(_controller!),
                          )
                        : const CircularProgressIndicator(color: Colors.deepPurpleAccent),
                  ),
                ),

                // 2. Layer de Gradiente Suave (Aparece quando o menu está visível)
                AnimatedOpacity(
                  opacity: _isMenuVisible ? 1.0 : 0.0,
                  duration: const Duration(milliseconds: 300),
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          Colors.black.withOpacity(0.9),
                          Colors.transparent,
                        ],
                        begin: Alignment.centerLeft,
                        end: Alignment.centerRight,
                        stops: const [0.0, 0.6],
                      ),
                    ),
                  ),
                ),

                // 3. Info do Canal Atual (Topo direito)
                if (_currentChannel != null)
                  AnimatedPositioned(
                    duration: const Duration(milliseconds: 300),
                    top: _isMenuVisible ? 24 : -100,
                    right: 24,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.black54,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        _currentChannel!.name,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),

                // 4. Overlay da Lista de Canais (Esquerda)
                AnimatedPositioned(
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeInOut,
                  left: _isMenuVisible ? 0 : -350,
                  top: 0,
                  bottom: 0,
                  child: Container(
                    width: 320,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade900.withOpacity(0.85),
                      border: Border(
                        right: BorderSide(color: Colors.deepPurple.withOpacity(0.3), width: 1),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Padding(
                          padding: EdgeInsets.all(24.0),
                          child: Text(
                            'Canais',
                            style: TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.w300,
                              color: Colors.white,
                              letterSpacing: 1.2,
                            ),
                          ),
                        ),
                        Expanded(
                          child: ListView.builder(
                            itemCount: _channels.length,
                            itemBuilder: (context, index) {
                              final channel = _channels[index];
                              final isSelected = _currentChannel?.url == channel.url;

                              return Material(
                                color: Colors.transparent,
                                child: InkWell(
                                  focusNode: index == 0 ? _listFocusNode : null,
                                  onFocusChange: (hasFocus) {
                                    if (hasFocus) _startUiTimer();
                                  },
                                  onTap: () {
                                    _playChannel(channel);
                                    _startUiTimer();
                                  },
                                  // Efeito de Highlight para DPAD (TV)
                                  focusColor: Colors.deepPurpleAccent.withOpacity(0.5),
                                  hoverColor: Colors.deepPurple.withOpacity(0.3),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                                    decoration: BoxDecoration(
                                      border: Border(
                                        left: BorderSide(
                                          color: isSelected ? Colors.deepPurpleAccent : Colors.transparent,
                                          width: 4,
                                        ),
                                      ),
                                    ),
                                    child: Text(
                                      channel.name,
                                      style: TextStyle(
                                        color: isSelected ? Colors.white : Colors.white70,
                                        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                        fontSize: 16,
                                      ),
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
