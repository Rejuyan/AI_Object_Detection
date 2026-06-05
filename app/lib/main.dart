import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'widgets/overlay_painter.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  List<CameraDescription> cameras = [];
  try {
    cameras = await availableCameras();
  } catch (e) {
    print("Error initializing cameras: $e");
  }
  runApp(MyApp(cameras: cameras));
}

class MyApp extends StatelessWidget {
  final List<CameraDescription> cameras;
  const MyApp({super.key, required this.cameras});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AI Smart Detector',
      theme: ThemeData.light().copyWith(
        scaffoldBackgroundColor: const Color(0xFFEAEDED), // Amazon Background Light Grey
        colorScheme: const ColorScheme.light(
          primary: Color(0xFFFF9900), // Amazon Orange
          secondary: Color(0xFF232F3E), // Amazon Navy
          surface: Colors.white,
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF232F3E), // Amazon Header Navy
          foregroundColor: Colors.white,
        ),
      ),
      home: DetectorScreen(cameras: cameras),
      debugShowCheckedModeBanner: false,
    );
  }
}

class DetectorScreen extends StatefulWidget {
  final List<CameraDescription> cameras;
  const DetectorScreen({super.key, required this.cameras});

  @override
  State<DetectorScreen> createState() => _DetectorScreenState();
}

class _DetectorScreenState extends State<DetectorScreen> {
  CameraController? _cameraController;
  WebSocketChannel? _channel;
  bool _isConnected = false;
  bool _isConnecting = false;
  bool _isStreaming = false;
  bool _isSendingFrame = false;

  final TextEditingController _serverController =
      TextEditingController(text: "ws://localhost:8000/ws");

  List<DetectedObject> _detectedObjects = [];
  List<DetectedHand> _detectedHands = [];

  double _fps = 0.0;
  DateTime? _lastFrameTime;

  List<CameraDescription> _cameras = [];
  CameraDescription? _selectedCamera;

  @override
  void initState() {
    super.initState();
    _cameras = List.from(widget.cameras);
    if (_cameras.isNotEmpty) {
      _selectedCamera = _cameras.first;
    }
    _initializeCamera();
  }

  Future<void> _initializeCamera() async {
    if (_cameras.isEmpty) return;

    if (_cameraController != null) {
      await _cameraController!.dispose();
      _cameraController = null;
    }

    if (_selectedCamera == null || !_cameras.contains(_selectedCamera)) {
      _selectedCamera = _cameras.first;
    }

    // Select the chosen camera
    _cameraController = CameraController(
      _selectedCamera!,
      ResolutionPreset.medium, // 640x480 resolution matches YOLO input
      enableAudio: false,
    );

    try {
      await _cameraController!.initialize();
      if (mounted) setState(() {});
    } catch (e) {
      print("Camera init error: $e. Retrying with ResolutionPreset.low...");
      _cameraController = CameraController(
        _selectedCamera!,
        ResolutionPreset.low,
        enableAudio: false,
      );
      try {
        await _cameraController!.initialize();
        if (mounted) setState(() {});
      } catch (e2) {
        print("Camera retry error: $e2");
      }
    }
  }

  Future<void> _requestCameraAccess() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isNotEmpty) {
        setState(() {
          _cameras = cameras;
          // Keep selection if it's still available, else default to first
          if (_selectedCamera == null || !cameras.contains(_selectedCamera)) {
            _selectedCamera = cameras.first;
          }
        });
        await _initializeCamera();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("No cameras found on this device."),
            backgroundColor: Colors.orange,
          ),
        );
      }
    } catch (e) {
      print("Camera request error: $e");
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Could not open camera. Please make sure no other application is using it and browser permissions are granted."),
          backgroundColor: const Color(0xFFD93838),
          duration: const Duration(seconds: 5),
        ),
      );
    }
  }

  Widget _buildCameraDropdown({bool isLight = false}) {
    if (_cameras.length <= 1) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 4.0),
      decoration: BoxDecoration(
        color: isLight ? Colors.white : const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(8.0),
        border: Border.all(color: const Color(0xFFCCCCCC)),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<CameraDescription>(
          value: _selectedCamera ?? _cameras.first,
          dropdownColor: isLight ? Colors.white : const Color(0xFF1E293B),
          icon: const Icon(Icons.arrow_drop_down, color: Color(0xFF007185)),
          style: TextStyle(
            color: isLight ? const Color(0xFF111111) : Colors.white,
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
          items: _cameras.map((camera) {
            return DropdownMenuItem<CameraDescription>(
              value: camera,
              child: Text(
                camera.name.isNotEmpty
                    ? camera.name
                    : 'Camera ${_cameras.indexOf(camera) + 1}',
              ),
            );
          }).toList(),
          onChanged: (camera) {
            if (camera != null) {
              setState(() {
                _selectedCamera = camera;
              });
              _initializeCamera();
            }
          },
        ),
      ),
    );
  }

  void _toggleConnection() async {
    if (_isConnected) {
      _disconnect();
    } else {
      _connect();
    }
  }

  void _connect() {
    if (_isConnecting) return;

    setState(() {
      _isConnecting = true;
    });

    final String url = _serverController.text.trim();
    print("Connecting to WebSocket at $url");

    try {
      _channel = WebSocketChannel.connect(Uri.parse(url));
      
      // Start listening to the stream
      _channel!.stream.listen(
        _onMessageReceived,
        onDone: () {
          print("WebSocket Connection Closed");
          _handleDisconnection();
        },
        onError: (error) {
          print("WebSocket Error: $error");
          _handleDisconnection();
        },
      );

      setState(() {
        _isConnected = true;
        _isConnecting = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Connected to server successfully!"),
          backgroundColor: Color(0xFF10B981),
        ),
      );
    } catch (e) {
      print("Connection error: $e");
      _handleDisconnection();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Failed to connect: $e"),
          backgroundColor: Colors.redAccent,
        ),
      );
    }
  }

  void _disconnect() {
    _isStreaming = false;
    _channel?.sink.close();
    _handleDisconnection();
  }

  void _handleDisconnection() {
    if (mounted) {
      setState(() {
        _isConnected = false;
        _isConnecting = false;
        _isStreaming = false;
        _isSendingFrame = false;
        _detectedObjects = [];
        _detectedHands = [];
        _fps = 0.0;
      });
    }
  }

  void _onMessageReceived(dynamic message) {
    if (!mounted) return;

    // Calculate FPS
    final now = DateTime.now();
    if (_lastFrameTime != null) {
      final diff = now.difference(_lastFrameTime!).inMilliseconds;
      if (diff > 0) {
        setState(() {
          _fps = 1000.0 / diff;
        });
      }
    }
    _lastFrameTime = now;

    // Parse JSON
    try {
      final Map<String, dynamic> data = json.decode(message as String);
      
      final List<dynamic> objectsJson = data['objects'] ?? [];
      final List<dynamic> handsJson = data['hands'] ?? [];

      setState(() {
        _detectedObjects = objectsJson
            .map((item) => DetectedObject.fromJson(item as Map<String, dynamic>))
            .toList();
        _detectedHands = handsJson
            .map((item) => DetectedHand.fromJson(item as Map<String, dynamic>))
            .toList();
        _isSendingFrame = false;
      });
    } catch (e) {
      print("Parsing error: $e");
      setState(() {
        _isSendingFrame = false;
      });
    }

    // Trigger next frame in self-pacing loop with a 300ms throttle delay
    // to prevent camera hardware driver overload.
    if (_isStreaming && _isConnected) {
      Future.delayed(const Duration(milliseconds: 300), () {
        if (_isStreaming && _isConnected) {
          _sendFrame();
        }
      });
    }
  }

  void _toggleStreaming() {
    if (!_isConnected) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Please connect to the server first."),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() {
      _isStreaming = !_isStreaming;
    });

    if (_isStreaming) {
      _sendFrame();
    }
  }

  Future<void> _sendFrame() async {
    if (!_isStreaming || !_isConnected || _isSendingFrame) return;
    if (_cameraController == null || !_cameraController!.value.isInitialized) return;

    setState(() {
      _isSendingFrame = true;
    });

    try {
      // Capture frame locally (native JPEG compression)
      final XFile image = await _cameraController!.takePicture();
      final bytes = await image.readAsBytes();

      if (_isStreaming && _isConnected) {
        _channel?.sink.add(bytes);
      } else {
        setState(() {
          _isSendingFrame = false;
        });
      }
    } catch (e) {
      print("Error sending frame: $e");
      if (mounted) {
        setState(() {
          _isSendingFrame = false;
        });
      }
      // Retry in 200ms if failed
      Future.delayed(const Duration(milliseconds: 200), () {
        if (_isStreaming && _isConnected) {
          _sendFrame();
        }
      });
    }
  }

  @override
  void dispose() {
    _cameraController?.dispose();
    _channel?.sink.close();
    _serverController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final isInitialized =
        _cameraController != null && _cameraController!.value.isInitialized;

    return Scaffold(
      appBar: AppBar(
        title: const Text('AI Object & Hand Detector'),
        centerTitle: true,
        backgroundColor: const Color(0xFF232F3E),
        elevation: 0,
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: Row(
              children: [
                Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: _isConnected
                        ? const Color(0xFF2ECC71)
                        : _isConnecting
                            ? Colors.amber
                            : Colors.redAccent,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  _isConnected
                      ? "Connected"
                      : _isConnecting
                          ? "Connecting"
                          : "Disconnected",
                  style: TextStyle(
                    fontSize: 14,
                    color: _isConnected
                        ? const Color(0xFF2ECC71)
                        : _isConnecting
                            ? Colors.amber[300]
                            : Colors.red[300],
                  ),
                ),
              ],
            ),
          )
        ],
      ),
      body: Column(
        children: [
          // Connection & Control Bar
          Container(
            padding: const EdgeInsets.all(16.0),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _serverController,
                        style: const TextStyle(color: Color(0xFF111111)),
                        decoration: InputDecoration(
                          labelText: 'Server WebSocket URL',
                          labelStyle: const TextStyle(color: Color(0xFF555555)),
                          hintText: 'ws://localhost:8000/ws',
                          prefixIcon: const Icon(Icons.link, color: Color(0xFF007185)),
                          filled: true,
                          fillColor: const Color(0xFFF3F4F6),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10.0),
                            borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10.0),
                            borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10.0),
                            borderSide: const BorderSide(color: Color(0xFFFF9900), width: 2),
                          ),
                          contentPadding:
                              const EdgeInsets.symmetric(vertical: 12.0),
                        ),
                        enabled: !_isConnected && !_isConnecting,
                      ),
                    ),
                    const SizedBox(width: 12),
                    ElevatedButton(
                      onPressed: _isConnecting ? null : _toggleConnection,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _isConnected ? const Color(0xFFD93838) : const Color(0xFFFFA41C),
                        foregroundColor: _isConnected ? Colors.white : const Color(0xFF111111),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 20, vertical: 16),
                        elevation: 1,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10.0),
                        ),
                      ),
                      child: _isConnecting
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : Text(_isConnected ? 'Disconnect' : 'Connect'),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Text(
                          'FPS: ${_fps.toStringAsFixed(1)}',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF007185),
                          ),
                        ),
                        const SizedBox(width: 16),
                        _buildCameraDropdown(isLight: true),
                      ],
                    ),
                    ElevatedButton.icon(
                      onPressed: _isConnected ? _toggleStreaming : null,
                      icon: Icon(_isStreaming ? Icons.stop : Icons.play_arrow),
                      label: Text(_isStreaming ? 'Stop Stream' : 'Start Stream'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _isStreaming ? const Color(0xFFD93838) : const Color(0xFFFF9900),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 24, vertical: 12),
                        elevation: 1,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8.0),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Main Viewport (Camera + Painter Overlay)
          Expanded(
            child: Center(
              child: isInitialized
                  ? Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.1),
                              blurRadius: 12,
                              offset: const Offset(0, 6),
                            ),
                          ],
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: AspectRatio(
                          aspectRatio: _cameraController!.value.aspectRatio,
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              CameraPreview(_cameraController!),
                              CustomPaint(
                                painter: DetectionOverlayPainter(
                                  objects: _detectedObjects,
                                  hands: _detectedHands,
                                  frameWidth: 640,  // Native camera width preset
                                  frameHeight: 480, // Native camera height preset
                                ),
                              ),
                              if (_isSendingFrame)
                                Positioned(
                                  top: 16,
                                  right: 16,
                                  child: Container(
                                    padding: const EdgeInsets.all(6),
                                    decoration: const BoxDecoration(
                                      color: Colors.black54,
                                      shape: BoxShape.circle,
                                    ),
                                    child: const SizedBox(
                                      width: 14,
                                      height: 14,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.blue,
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    )
                  : Center(
                      child: Container(
                        constraints: const BoxConstraints(maxWidth: 400),
                        padding: const EdgeInsets.all(24.0),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16.0),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.05),
                              blurRadius: 10,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.videocam_off_rounded, size: 64, color: Color(0xFFD93838)),
                            const SizedBox(height: 16),
                            const Text(
                              'Webcam Access Required',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF232F3E),
                              ),
                            ),
                            const SizedBox(height: 8),
                            const Text(
                              'Please grant browser permissions and make sure your camera is not in use by another application.',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: Color(0xFF555555), height: 1.4),
                            ),
                            const SizedBox(height: 20),
                            _buildCameraDropdown(isLight: true),
                            const SizedBox(height: 16),
                            ElevatedButton.icon(
                              onPressed: _requestCameraAccess,
                              icon: const Icon(Icons.videocam),
                              label: const Text('Request Camera Access'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFFFFA41C),
                                foregroundColor: const Color(0xFF111111),
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 24, vertical: 14),
                                elevation: 1,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8.0),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
            ),
          ),

          // Detection Stats Panel
          Container(
            height: 140,
            width: double.infinity,
            padding: const EdgeInsets.all(16.0),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(24),
                topRight: Radius.circular(24),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 10,
                  offset: const Offset(0, -4),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Live Detections',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF232F3E),
                  ),
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: _detectedObjects.isEmpty && _detectedHands.isEmpty
                      ? const Center(
                          child: Text(
                            'No detections active. Start stream and place items in view.',
                            style: TextStyle(color: Color(0xFF666666), fontSize: 13),
                          ),
                        )
                      : ListView(
                          scrollDirection: Axis.horizontal,
                          children: [
                            // Objects chips
                            ..._detectedObjects.map((obj) {
                              return Padding(
                                padding: const EdgeInsets.only(right: 8.0),
                                child: Chip(
                                  avatar: const Icon(Icons.category, size: 16, color: Color(0xFF007185)),
                                  label: Text(
                                    "${obj.className} #${obj.id}",
                                    style: const TextStyle(color: Color(0xFF111111)),
                                  ),
                                  backgroundColor: const Color(0xFF007185).withOpacity(0.1),
                                  side: const BorderSide(color: Color(0xFF007185)),
                                ),
                              );
                            }),
                            // Hands chips
                            ..._detectedHands.map((hand) {
                              return Padding(
                                padding: const EdgeInsets.only(right: 8.0),
                                child: Chip(
                                  avatar: const Icon(Icons.back_hand, size: 16, color: Color(0xFFFF9900)),
                                  label: const Text(
                                    "Hand Detected",
                                    style: TextStyle(color: Color(0xFF111111)),
                                  ),
                                  backgroundColor: const Color(0xFFFF9900).withOpacity(0.1),
                                  side: const BorderSide(color: Color(0xFFFF9900)),
                                ),
                              );
                            }),
                          ],
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
