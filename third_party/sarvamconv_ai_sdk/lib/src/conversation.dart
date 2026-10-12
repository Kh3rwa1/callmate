// Conversational AI agent implementation with WebSocket management.
//
// This module provides the main [SamvaadAgent] class for managing real-time
// conversations with voice using WebSocket connections.

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:web_socket_channel/web_socket_channel.dart';

import 'audio_interface.dart';
import 'messages/actions.dart';
import 'messages/audio.dart';
import 'messages/base.dart';
import 'messages/config.dart';
import 'messages/events.dart';
import 'messages/parser.dart';
import 'messages/system.dart';
import 'messages/text.dart';
import 'messages/types.dart';

/// Callback type for audio messages from the server.
typedef AudioCallback = Future<void> Function(ServerAudioChunkMsg msg);

/// Callback type for text messages from the server.
typedef TextCallback = Future<void> Function(ServerMsgBase msg);

/// Callback type for event messages from the server.
typedef EventCallback = Future<void> Function(ServerEventBase event);

/// Main conversational agent class for real-time voice and text interactions.
///
/// This class manages WebSocket connections, handles message routing, and provides
/// callbacks for various conversation events.
///
/// Example with direct API key:
/// ```dart
/// final config = InteractionConfig(
///   orgId: 'your_org_id',
///   workspaceId: 'your_workspace_id',
///   appId: 'support_agent_v1',
///   interactionType: InteractionType.call,
///   userIdentifier: 'user@example.com',
///   userIdentifierType: UserIdentifierType.email,
///   sampleRate: 16000,
///   agentVariables: {'user_name': 'Rahul'},
///   initialLanguageName: SarvamToolLanguageName.hindi,
/// );
///
/// final agent = SamvaadAgent(
///   apiKey: 'sk_...',
///   config: config,
/// );
///
/// await agent.start();
/// // Conversation runs...
/// await agent.stop();
/// ```
///
/// Example with proxy server (API key hidden from client):
/// ```dart
/// final agent = SamvaadAgent(
///   config: config,
///   baseUrl: 'https://your-proxy-server.com/api/',
///   headers: {'Authorization': 'Bearer user_token'}, // Your auth
/// );
/// // Your proxy server adds X-API-Key header before forwarding to Sarvam
/// ```
class SamvaadAgent {
  /// API key for authentication.
  /// Optional when using a proxy server that adds the API key.
  final String? apiKey;

  /// Interaction configuration.
  final InteractionConfig config;

  /// Base URL for HTTP API endpoints.
  /// Change this to your proxy server URL when hiding API keys from client.
  final String baseUrl;

  /// Custom headers to send with HTTP requests.
  /// Use this for authentication with your proxy server.
  final Map<String, String>? headers;

  /// Optional audio interface for automatic audio handling.
  final AudioInterface? audioInterface;

  /// Callback for audio messages.
  final AudioCallback? audioCallback;

  /// Callback for text messages.
  final TextCallback? textCallback;

  /// Callback for event messages.
  final EventCallback? eventCallback;

  // Internal state
  WebSocketChannel? _ws;
  String? _referenceId;
  String? _interactionId;
  bool _shouldStop = false;
  StreamSubscription? _wsSubscription;

  // Message queue for sending
  final _sendQueue = StreamController<ClientMsgBase>.broadcast();

  // Audio receive queue
  final _audioReceiveQueue = StreamController<ServerAudioChunkMsg>.broadcast();
  StreamSubscription? _audioReceiveSubscription;

  // Connection signaling
  final _disconnectedCompleter = Completer<void>();
  final _connectedCompleter = Completer<void>();

  /// Creates a new [SamvaadAgent] instance.
  ///
  /// [apiKey] - API key for authentication. Optional when using a proxy server.
  /// [config] - Interaction start configuration
  /// [audioInterface] - Optional audio interface for automatic audio handling
  /// [audioCallback] - Optional callback for audio messages
  /// [textCallback] - Optional callback for text messages
  /// [eventCallback] - Optional callback for event messages
  /// [baseUrl] - Base URL for HTTP API endpoints. Set to your proxy server URL to hide API keys.
  /// [headers] - Custom headers to send with HTTP requests (e.g., for proxy authentication)
  SamvaadAgent({
    this.apiKey,
    required this.config,
    this.audioInterface,
    this.audioCallback,
    this.textCallback,
    this.eventCallback,
    this.baseUrl = 'https://apps.sarvam.ai/api/app-runtime/',
    this.headers,
  });

  /// Get the reference ID for this session.
  String? get referenceId => _referenceId;

  /// Get the current interaction ID.
  String? get interactionId => _interactionId;

  /// Check if the WebSocket is currently connected.
  bool get isConnected => _ws != null && _ws!.closeCode == null;

  /// Start the conversation session.
  ///
  /// This method:
  /// 1. Gets a signed WebSocket URL via HTTP GET
  /// 2. Connects to the WebSocket
  /// 3. Sends the interaction_start message
  /// 4. Starts the message receive loop
  Future<void> start() async {
    // Get signed URL for secure WebSocket connection
    final (signedUrl, referenceId, interactionId) = await _getSignedUrl();
    _referenceId = referenceId;
    // Set interaction ID from API response if available (common for chat interactions)
    if (interactionId != null && interactionId.isNotEmpty) {
      _interactionId = interactionId;
    }

    _shouldStop = false;

    // Augment URL with params
    final wsUrl = _augmentWsUrlWithParams(signedUrl);

    // Connect to WebSocket
    _ws = WebSocketChannel.connect(Uri.parse(wsUrl));

    // Wait for connection
    await _ws!.ready;

    // Signal connected
    if (!_connectedCompleter.isCompleted) {
      _connectedCompleter.complete();
    }

    // Send interaction start
    await _sendInteractionStart();

    // Start audio interface if provided
    if (audioInterface != null) {
      await audioInterface!.start((audioData, frameCount) async {
        if (!_shouldStop && isConnected) {
          await sendAudio(audioData);
        }
      });
    }

    // Start send queue processing
    _sendQueue.stream.listen((msg) {
      if (isConnected) {
        _ws!.sink.add(jsonEncode(msg.toJson()));
      }
    });

    // Start audio receive queue processing
    _audioReceiveSubscription =
        _audioReceiveQueue.stream.listen((audioMsg) async {
      await _handleAudio(audioMsg);
    });

    // Start receive loop
    _wsSubscription = _ws!.stream.listen(
      (data) async {
        final message = jsonDecode(data as String) as Map<String, dynamic>;
        await _routeMessage(message);
      },
      onError: (error) {
        print('WebSocket error: $error');
        _shouldStop = true;
      },
      onDone: () {
        _shouldStop = true;
        if (!_disconnectedCompleter.isCompleted) {
          _disconnectedCompleter.complete();
        }
      },
    );
  }

  /// Stop the conversation session.
  ///
  /// This method:
  /// - Closes the WebSocket connection
  /// - Cancels background tasks
  /// - Cleans up resources
  Future<void> stop() async {
    _shouldStop = true;

    // Stop audio interface if provided
    if (audioInterface != null) {
      await audioInterface!.stop();
    }

    // Cancel subscriptions
    await _wsSubscription?.cancel();
    await _audioReceiveSubscription?.cancel();

    // Close WebSocket
    await _ws?.sink.close();
    _ws = null;

    // Signal disconnected
    if (!_disconnectedCompleter.isCompleted) {
      _disconnectedCompleter.complete();
    }
  }

  /// Wait until the WebSocket disconnects or the agent is stopped.
  Future<void> waitForDisconnect() async {
    await _disconnectedCompleter.future;
  }

  /// Wait until the WebSocket connection is established.
  ///
  /// [timeout] - Maximum time to wait. If null, wait indefinitely.
  /// Returns true if connected within timeout, false otherwise.
  Future<bool> waitForConnect({Duration? timeout}) async {
    if (isConnected) return true;

    try {
      if (timeout != null) {
        await _connectedCompleter.future.timeout(timeout);
      } else {
        await _connectedCompleter.future;
      }
      return isConnected;
    } on TimeoutException {
      return isConnected;
    }
  }

  /// Send an audio chunk to the agent.
  ///
  /// [audioData] - Raw 16-bit PCM mono audio bytes at config.sampleRate
  Future<void> sendAudio(Uint8List audioData) async {
    if (!isConnected) {
      print('[Conversation] sendAudio: WebSocket not connected');
      throw StateError('WebSocket is not connected');
    }

    final message = ClientAudioChunkMsg.fromBytes(
      audioData: audioData,
      format: AudioEncoding.linear16,
      sampleRate: config.sampleRate,
      timestamp: DateTime.now().millisecondsSinceEpoch / 1000.0,
    );
    _sendQueue.add(message);
  }

  /// Send a voice note to the agent for transcription.
  ///
  /// [audioData] - Raw 16-bit PCM mono audio bytes
  /// [transcribe] - Whether to transcribe the audio (default: true)
  Future<void> sendVoiceNote(Uint8List audioData,
      {bool transcribe = true}) async {
    if (!isConnected) {
      throw StateError('WebSocket is not connected');
    }

    final message = ClientAudioMsg.fromBytes(
      audioData: audioData,
      format: AudioEncoding.linear16,
      sampleRate: config.sampleRate,
      transcribe: transcribe,
      timestamp: DateTime.now().millisecondsSinceEpoch / 1000.0,
    );
    _sendQueue.add(message);
  }

  /// Send a text message to the agent.
  ///
  /// [text] - The text message to send.
  Future<void> sendText(String text) async {
    if (!isConnected) {
      throw StateError('WebSocket is not connected');
    }

    final message = ClientTextMsg(
      text: text,
      timestamp: DateTime.now().millisecondsSinceEpoch / 1000.0,
    );
    _sendQueue.add(message);
  }

  // Private methods

  String _constructUrl() {
    return '${baseUrl}orgs/${config.orgId}/workspaces/${config.workspaceId}/apps/${config.appId}/url';
  }

  String _augmentWsUrlWithParams(String wsUrl) {
    final uri = Uri.parse(wsUrl);
    final params = Map<String, String>.from(uri.queryParameters);

    params['user_identifier'] = config.userIdentifier;
    params['user_identifier_type'] = config.userIdentifierType.value;
    params['sample_rate'] = config.sampleRate.toString();

    return uri.replace(queryParameters: params).toString();
  }

  Future<(String, String, String?)> _getSignedUrl() async {
    final url = _constructUrl();

    final queryParams = {
      'interaction_type': config.interactionType.value,
    };
    if (config.version != null) {
      queryParams['version'] = config.version.toString();
    }

    final uri = Uri.parse(url).replace(queryParameters: queryParams);

    // Build headers: start with custom headers, then add API key if provided
    final requestHeaders = <String, String>{};
    if (headers != null) {
      requestHeaders.addAll(headers!);
    }
    if (apiKey != null && apiKey!.isNotEmpty) {
      requestHeaders['X-API-Key'] = apiKey!;
    }

    final response = await http.get(
      uri,
      headers: requestHeaders,
    );

    if (response.statusCode != 200) {
      throw Exception('Failed to get signed URL: ${response.statusCode}');
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final signedUrl = data['url'] as String;
    final referenceId = data['reference_id'] as String;
    // Also capture interaction_id from the API response if present (for chat interactions)
    final interactionId = data['interaction_id'] as String?;

    // Add additional query parameters
    final parsedUrl = Uri.parse(signedUrl);
    final newParams = Map<String, String>.from(parsedUrl.queryParameters);
    newParams['user_identifier'] = config.userIdentifier;
    newParams['user_identifier_type'] = config.userIdentifierType.value;
    newParams['sample_rate'] = config.sampleRate.toString();
    newParams['interaction_type'] = config.interactionType.value;

    final modifiedUrl =
        parsedUrl.replace(queryParameters: newParams).toString();

    return (modifiedUrl, referenceId, interactionId);
  }

  Future<void> _sendInteractionStart() async {
    if (_ws == null) {
      throw StateError('WebSocket not connected');
    }

    final message = ClientInteractionStartMsg.fromConfig(config);
    _ws!.sink.add(jsonEncode(message.toJson()));
  }

  Future<void> _routeMessage(Map<String, dynamic> message) async {
    try {
      final parsed = parseServerMessage(message);

      if (parsed is ServerTextChunkMsg) {
        await _handleText(parsed);
      } else if (parsed is ServerTextMsg) {
        await _handleText(parsed);
      } else if (parsed is ServerAudioChunkMsg) {
        _audioReceiveQueue.add(parsed);
      } else if (parsed is ServerPingMsg) {
        await _handlePing(parsed);
      } else if (parsed is ServerEventBase) {
        // Route all events (including InteractionEnd, InteractionConnected, etc.)
        // through _handleEvent so eventCallback is always called
        await _handleEvent(parsed);
      }
    } catch (e) {
      print('Failed to parse server message: $e');
    }
  }

  Future<void> _handleText(ServerMsgBase textMsg) async {
    if (textCallback != null) {
      await textCallback!(textMsg);
    }
  }

  Future<void> _handleAudio(ServerAudioChunkMsg audioMsg) async {
    // Play through audioInterface if provided
    if (audioInterface != null && audioMsg.audioBase64.isNotEmpty) {
      final audioBytes = audioMsg.audioBytes;
      if (audioBytes.isNotEmpty) {
        // Use server sample rate or fall back to config sample rate
        final sampleRate = audioMsg.sampleRate ?? config.sampleRate;
        await audioInterface!.output(
          audioBytes,
          sampleRate: sampleRate,
        );
      }
    } else if (audioCallback != null) {
      await audioCallback!(audioMsg);
    }
  }

  Future<void> _handleEvent(ServerEventBase event) async {
    // Handle SDK internal logic for specific events
    if (event is ServerUserInterruptEvent && audioInterface != null) {
      audioInterface!.interrupt();
    }
    if (event is ServerInteractionEndEvent) {
      await _handleInteractionEnd(event);
    }
    if (event is ServerInteractionConnectedEvent) {
      await _handleInteractionConnected(event);
    }

    // Always call client's eventCallback for every event
    if (eventCallback != null) {
      await eventCallback!(event);
    }
  }

  Future<void> _handleInteractionConnected(
      ServerInteractionConnectedEvent event) async {
    _interactionId = event.interactionId;
  }

  Future<void> _handleInteractionEnd(ServerInteractionEndEvent endMsg) async {
    // Interaction has ended - can trigger cleanup or callbacks
  }

  Future<void> _handlePing(ServerPingMsg pingMsg) async {
    if (isConnected) {
      final pong = ClientPongMsg(
        eventId: pingMsg.eventId,
        timestamp: DateTime.now().millisecondsSinceEpoch / 1000.0,
      );
      _ws!.sink.add(jsonEncode(pong.toJson()));
    }
  }
}

/// Create and start a conversation session.
///
/// This is a convenience function that creates a [SamvaadAgent] instance
/// and starts it immediately.
///
/// [config] - Interaction start configuration
/// [apiKey] - API key for authentication. Optional when using a proxy server.
/// [audioInterface] - Optional audio interface for automatic audio handling
/// [audioCallback] - Optional callback for audio messages
/// [textCallback] - Optional callback for text messages
/// [baseUrl] - Base URL for HTTP API endpoints. Set to your proxy server URL to hide API keys.
/// [headers] - Custom headers to send with HTTP requests (e.g., for proxy authentication)
///
/// Returns the started [SamvaadAgent] instance.
Future<SamvaadAgent> createConversation({
  required InteractionConfig config,
  String? apiKey,
  AudioInterface? audioInterface,
  AudioCallback? audioCallback,
  TextCallback? textCallback,
  EventCallback? eventCallback,
  String baseUrl = 'https://apps.sarvam.ai/api/app-runtime/',
  Map<String, String>? headers,
}) async {
  final agent = SamvaadAgent(
    apiKey: apiKey,
    config: config,
    audioInterface: audioInterface,
    audioCallback: audioCallback,
    textCallback: textCallback,
    eventCallback: eventCallback,
    baseUrl: baseUrl,
    headers: headers,
  );

  await agent.start();
  return agent;
}
