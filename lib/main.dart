import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:video_player/video_player.dart';
import 'package:chewie/chewie.dart';
import 'package:flutter_spinkit/flutter_spinkit.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_animate/flutter_animate.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
    DeviceOrientation.portraitUp,
  ]);
  runApp(const ProviderScope(child: SmartTVApp()));
}

class Channel {
  final String name;
  final String url;
  final String logo;
  final String group;

  Channel({
    required this.name,
    required this.url,
    this.logo = '',
    this.group = 'General',
  });
}

final List<Channel> defaultChannels = [
  Channel(
    name: 'Big Buck Bunny (HLS HD)',
    url: 'https://test-streams.mux.dev/x36xhzz/x36xhzz.m3u8',
    group: 'Demo VOD',
    logo: 'https://images.unsplash.com/photo-1536440136628-849c177e76a1?w=200',
  ),
  Channel(
    name: 'Sintel (Cinema Stream)',
    url: 'https://bitdash-a.akamaihd.net/content/sintel/hls/playlist.m3u8',
    group: 'Demo VOD',
    logo: 'https://images.unsplash.com/photo-1489599849927-2ee91cede3ba?w=200',
  ),
  Channel(
    name: 'Tears of Steel (Sci-Fi)',
    url: 'https://test-streams.mux.dev/tos_simulcast/tos.m3u8',
    group: 'Demo VOD',
    logo: 'https://images.unsplash.com/photo-1518709268805-4e9042af9f23?w=200',
  ),
  Channel(
    name: 'Al Jazeera Arabic (Live)',
    url: 'https://live-hls-web-aja.getaj.net/AJA/03.m3u8',
    group: 'News',
    logo: 'https://upload.wikimedia.org/wikipedia/en/f/f2/Aljazeera_eng.svg',
  ),
  Channel(
    name: 'France 24 Arabic (Live)',
    url: 'https://stream.france24.com/hls/ar/main.m3u8',
    group: 'News',
    logo: 'https://upload.wikimedia.org/wikipedia/fr/8/87/France_24_logo_2013.png',
  ),
];

class SmartTVApp extends StatelessWidget {
  const SmartTVApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Smart TV Futuristic Player',
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.dark,
      darkTheme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF090D16),
        primaryColor: const Color(0xFF00E5FF),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF00E5FF),
          secondary: Color(0xFF7C4DFF),
          surface: Color(0xFF131A2A),
        ),
        textTheme: GoogleFonts.rajdhaniTextTheme(ThemeData.dark().textTheme),
      ),
      home: const HomeScreen(),
    );
  }
}

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  List<Channel> _channels = [];
  String _selectedGroup = 'All';
  String _searchQuery = '';
  bool _isLoading = false;
  final TextEditingController _urlController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _channels = List.from(defaultChannels);
    _loadSavedM3u();
  }

  Future<void> _loadSavedM3u() async {
    final prefs = await SharedPreferences.getInstance();
    final savedUrl = prefs.getString('saved_m3u_url');
    if (savedUrl != null && savedUrl.isNotEmpty) {
      _urlController.text = savedUrl;
      _fetchM3u(savedUrl, save: false);
    }
  }

  Future<void> _fetchM3u(String url, {bool save = true}) async {
    setState(() => _isLoading = true);
    try {
      final dio = Dio(BaseOptions(connectTimeout: const Duration(seconds: 15)));
      final response = await dio.get(url);
      final parsed = _parseM3u(response.data.toString());
      if (parsed.isNotEmpty) {
        setState(() {
          _channels = parsed;
          _selectedGroup = 'All';
        });
        if (save) {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString('saved_m3u_url', url);
        }
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              backgroundColor: const Color(0xFF00E5FF),
              content: Text(
                'Loaded ${parsed.length} channels successfully!',
                style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
              ),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: Colors.redAccent,
            content: Text('Error loading playlist: $e'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _pickLocalM3uFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['m3u', 'm3u8', 'txt'],
      );
      if (result != null && result.files.single.path != null) {
        setState(() => _isLoading = true);
        final file = File(result.files.single.path!);
        final content = await file.readAsString();
        final parsed = _parseM3u(content);
        if (parsed.isNotEmpty) {
          setState(() {
            _channels = parsed;
            _selectedGroup = 'All';
          });
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('File error: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  List<Channel> _parseM3u(String content) {
    final lines = const LineSplitter().convert(content);
    final List<Channel> list = [];
    String currentName = '';
    String currentLogo = '';
    String currentGroup = 'General';

    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.startsWith('#EXTINF:')) {
        final logoMatch = RegExp(r'tvg-logo="([^"]*)"').firstMatch(trimmed);
        currentLogo = logoMatch?.group(1) ?? '';

        final groupMatch = RegExp(r'group-title="([^"]*)"').firstMatch(trimmed);
        currentGroup = groupMatch?.group(1) ?? 'General';
        if (currentGroup.isEmpty) currentGroup = 'General';

        final commaIdx = trimmed.lastIndexOf(',');
        if (commaIdx != -1 && commaIdx < trimmed.length - 1) {
          currentName = trimmed.substring(commaIdx + 1).trim();
        } else {
          currentName = 'Channel ${list.length + 1}';
        }
      } else if (trimmed.isNotEmpty && !trimmed.startsWith('#')) {
        if (currentName.isEmpty) currentName = 'Channel ${list.length + 1}';
        list.add(Channel(
          name: currentName,
          url: trimmed,
          logo: currentLogo,
          group: currentGroup,
        ));
        currentName = '';
        currentLogo = '';
        currentGroup = 'General';
      }
    }
    return list;
  }

  void _showAddPlaylistDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF131A2A),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: Color(0xFF00E5FF), width: 1.5),
        ),
        title: Text(
          'Load IPTV Playlist (M3U)',
          style: GoogleFonts.orbitron(color: const Color(0xFF00E5FF), fontWeight: FontWeight.bold),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _urlController,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'https://example.com/playlist.m3u',
                hintStyle: TextStyle(color: Colors.white.withOpacity(0.4)),
                filled: true,
                fillColor: const Color(0xFF090D16),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                focusedBorder: const OutlineInputBorder(
                  borderSide: BorderSide(color: Color(0xFF00E5FF)),
                ),
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: () {
                Navigator.pop(ctx);
                _pickLocalM3uFile();
              },
              icon: const Icon(Icons.file_open),
              label: const Text('Pick Local M3U File'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF7C4DFF),
                foregroundColor: Colors.white,
                minimumSize: const Size(double.infinity, 44),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              if (_urlController.text.trim().isNotEmpty) {
                _fetchM3u(_urlController.text.trim());
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF00E5FF),
              foregroundColor: Colors.black,
            ),
            child: const Text('Download & Load'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final groups = ['All', ...{for (var c in _channels) c.group}];
    final filteredChannels = _channels.where((c) {
      final matchesGroup = _selectedGroup == 'All' || c.group == _selectedGroup;
      final matchesSearch = c.name.toLowerCase().contains(_searchQuery.toLowerCase());
      return matchesGroup && matchesSearch;
    }).toList();

    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF090D16),
        elevation: 0,
        title: Row(
          children: [
            const Icon(Icons.tv_rounded, color: Color(0xFF00E5FF), size: 28),
            const SizedBox(width: 10),
            Text(
              'SMART TV PRO',
              style: GoogleFonts.orbitron(
                letterSpacing: 2,
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Add Playlist',
            icon: const Icon(Icons.playlist_add_rounded, color: Color(0xFF00E5FF), size: 28),
            onPressed: _showAddPlaylistDialog,
          ),
          IconButton(
            tooltip: 'Reset Demo Channels',
            icon: const Icon(Icons.restore_rounded, color: Colors.white70),
            onPressed: () {
              setState(() {
                _channels = List.from(defaultChannels);
                _selectedGroup = 'All';
              });
            },
          ),
        ],
      ),
      body: _isLoading
          ? const Center(
              child: SpinKitFadingCube(color: Color(0xFF00E5FF), size: 50.0),
            )
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                  child: TextField(
                    onChanged: (val) => setState(() => _searchQuery = val),
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      hintText: 'Search Channel...',
                      hintStyle: TextStyle(color: Colors.white.withOpacity(0.4)),
                      prefixIcon: const Icon(Icons.search, color: Color(0xFF00E5FF)),
                      filled: true,
                      fillColor: const Color(0xFF131A2A),
                      contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 16),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ),
                SizedBox(
                  height: 48,
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    itemCount: groups.length,
                    itemBuilder: (ctx, i) {
                      final grp = groups[i];
                      final isSelected = grp == _selectedGroup;
                      return Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: ChoiceChip(
                          selected: isSelected,
                          label: Text(
                            grp,
                            style: TextStyle(
                              color: isSelected ? Colors.black : Colors.white70,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          selectedColor: const Color(0xFF00E5FF),
                          backgroundColor: const Color(0xFF131A2A),
                          onSelected: (_) => setState(() => _selectedGroup = grp),
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: filteredChannels.isEmpty
                      ? Center(
                          child: Text(
                            'No channels found',
                            style: GoogleFonts.rajdhani(color: Colors.white54, fontSize: 18),
                          ),
                        )
                      : GridView.builder(
                          padding: const EdgeInsets.all(16),
                          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                            maxCrossAxisExtent: 220,
                            childAspectRatio: 1.1,
                            crossAxisSpacing: 14,
                            mainAxisSpacing: 14,
                          ),
                          itemCount: filteredChannels.length,
                          itemBuilder: (ctx, i) {
                            final channel = filteredChannels[i];
                            return _ChannelCard(
                              channel: channel,
                              onTap: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => PlayerScreen(
                                      channel: channel,
                                      allChannels: filteredChannels,
                                    ),
                                  ),
                                );
                              },
                            ).animate().fadeIn(duration: 300.ms).scale(begin: const Offset(0.9, 0.9));
                          },
                        ),
                ),
              ],
            ),
    );
  }
}

class _ChannelCard extends StatefulWidget {
  final Channel channel;
  final VoidCallback onTap;

  const _ChannelCard({required this.channel, required this.onTap});

  @override
  State<_ChannelCard> createState() => _ChannelCardState();
}

class _ChannelCardState extends State<_ChannelCard> {
  bool _isFocused = false;

  @override
  Widget build(BuildContext context) {
    return FocusableActionDetector(
      onShowFocusHighlight: (val) => setState(() => _isFocused = val),
      child: InkWell(
        onTap: widget.onTap,
        borderRadius: BorderRadius.circular(14),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          decoration: BoxDecoration(
            color: _isFocused ? const Color(0xFF1E293B) : const Color(0xFF131A2A),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: _isFocused ? const Color(0xFF00E5FF) : Colors.white10,
              width: _isFocused ? 2.5 : 1.0,
            ),
            boxShadow: _isFocused
                ? [
                    BoxShadow(
                      color: const Color(0xFF00E5FF).withOpacity(0.4),
                      blurRadius: 12,
                      spreadRadius: 2,
                    )
                  ]
                : [],
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Expanded(
                flex: 3,
                child: Padding(
                  padding: const EdgeInsets.all(12.0),
                  child: widget.channel.logo.isNotEmpty
                      ? CachedNetworkImage(
                          imageUrl: widget.channel.logo,
                          fit: BoxFit.contain,
                          placeholder: (ctx, _) => const SpinKitRing(color: Color(0xFF00E5FF), size: 24),
                          errorWidget: (ctx, _, __) => const Icon(Icons.live_tv_rounded, color: Color(0xFF00E5FF), size: 40),
                        )
                      : const Icon(Icons.live_tv_rounded, color: Color(0xFF00E5FF), size: 40),
                ),
              ),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                decoration: const BoxDecoration(
                  color: Color(0xFF0D121D),
                  borderRadius: BorderRadius.vertical(bottom: Radius.circular(13)),
                ),
                child: Column(
                  children: [
                    Text(
                      widget.channel.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: GoogleFonts.rajdhani(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                    ),
                    Text(
                      widget.channel.group,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white38, fontSize: 11),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class PlayerScreen extends StatefulWidget {
  final Channel channel;
  final List<Channel> allChannels;

  const PlayerScreen({super.key, required this.channel, required this.allChannels});

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  late Channel _currentChannel;
  VideoPlayerController? _videoPlayerController;
  ChewieController? _chewieController;
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _currentChannel = widget.channel;
    _initializePlayer();
  }

  Future<void> _initializePlayer() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    _chewieController?.dispose();
    await _videoPlayerController?.dispose();

    try {
      _videoPlayerController = VideoPlayerController.networkUrl(
        Uri.parse(_currentChannel.url),
      );

      await _videoPlayerController!.initialize();

      _chewieController = ChewieController(
        videoPlayerController: _videoPlayerController!,
        autoPlay: true,
        looping: false,
        isLive: true,
        allowFullScreen: true,
        fullScreenByDefault: false,
        aspectRatio: _videoPlayerController!.value.aspectRatio > 0
            ? _videoPlayerController!.value.aspectRatio
            : 16 / 9,
        materialProgressColors: ChewieProgressColors(
          playedColor: const Color(0xFF00E5FF),
          handleColor: const Color(0xFF00E5FF),
          backgroundColor: Colors.white24,
          bufferedColor: Colors.white38,
        ),
      );

      if (mounted) {
        setState(() => _isLoading = false);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = e.toString();
        });
      }
    }
  }

  void _switchChannel(Channel channel) {
    if (_currentChannel.url != channel.url) {
      setState(() => _currentChannel = channel);
      _initializePlayer();
    }
  }

  @override
  void dispose() {
    _chewieController?.dispose();
    _videoPlayerController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: const Color(0xFF090D16),
        title: Text(
          _currentChannel.name,
          style: GoogleFonts.rajdhani(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Color(0xFF00E5FF)),
            onPressed: _initializePlayer,
          ),
        ],
      ),
      body: Row(
        children: [
          Expanded(
            flex: 3,
            child: Center(
              child: _isLoading
                  ? const Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        SpinKitFadingCube(color: Color(0xFF00E5FF), size: 45),
                        SizedBox(height: 16),
                        Text('Connecting to stream...', style: TextStyle(color: Colors.white70)),
                      ],
                    )
                  : _errorMessage != null
                      ? Padding(
                          padding: const EdgeInsets.all(24.0),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.error_outline_rounded, color: Colors.redAccent, size: 54),
                              const SizedBox(height: 12),
                              Text(
                                'Playback Failed',
                                style: GoogleFonts.orbitron(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                _errorMessage!,
                                textAlign: TextAlign.center,
                                style: const TextStyle(color: Colors.white54, fontSize: 13),
                              ),
                              const SizedBox(height: 16),
                              ElevatedButton.icon(
                                onPressed: _initializePlayer,
                                icon: const Icon(Icons.refresh),
                                label: const Text('Try Again'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF00E5FF),
                                  foregroundColor: Colors.black,
                                ),
                              ),
                            ],
                          ),
                        )
                      : (_chewieController != null && _chewieController!.videoPlayerController.value.isInitialized)
                          ? Chewie(controller: _chewieController!)
                          : const SizedBox(),
            ),
          ),
          Container(
            width: 250,
            color: const Color(0xFF090D16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.all(12.0),
                  child: Text(
                    'CHANNELS',
                    style: GoogleFonts.orbitron(
                      color: const Color(0xFF00E5FF),
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.5,
                      fontSize: 14,
                    ),
                  ),
                ),
                Expanded(
                  child: ListView.builder(
                    itemCount: widget.allChannels.length,
                    itemBuilder: (ctx, i) {
                      final ch = widget.allChannels[i];
                      final isCurrent = ch.url == _currentChannel.url;
                      return ListTile(
                        dense: true,
                        selected: isCurrent,
                        selectedTileColor: const Color(0xFF131A2A),
                        leading: Icon(
                          Icons.play_circle_fill_rounded,
                          color: isCurrent ? const Color(0xFF00E5FF) : Colors.white24,
                          size: 20,
                        ),
                        title: Text(
                          ch.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: isCurrent ? const Color(0xFF00E5FF) : Colors.white,
                            fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
                          ),
                        ),
                        onTap: () => _switchChannel(ch),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
