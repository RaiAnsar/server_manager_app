import 'dart:async';
import 'dart:convert'; // For utf8 encoding/decoding

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter/foundation.dart';

enum SshConnectionStatus { disconnected, connecting, connected, disconnecting, error }

class SshService {
  SSHClient? _client;
  SSHSession? _shellSession; // Store the interactive shell session
  SshConnectionStatus _currentStatus = SshConnectionStatus.disconnected;
  String? lastError;

  final _statusController = StreamController<SshConnectionStatus>.broadcast();
  // StreamController for shell output
  final _outputController = StreamController<String>.broadcast();

  Stream<SshConnectionStatus> get statusStream => _statusController.stream;
  // Public stream for shell output
  Stream<String> get outputStream => _outputController.stream;

  void _updateStatus(SshConnectionStatus newStatus, {String? errorMsg}) {
    if (_currentStatus == newStatus && errorMsg == lastError) return;
    _currentStatus = newStatus;
    lastError = errorMsg;
    _statusController.add(newStatus);
    debugPrint("SSH Status: $newStatus ${errorMsg != null ? '- Error: $errorMsg': ''}");
  }


  Future<void> _startShell() async {
    if (_client == null || _shellSession != null) return;

    try {
      _shellSession = await _client!.shell(
        // Use the CORRECT named parameters
        pty: const SSHPtyConfig(
          type: 'xterm-256color', // Use 'type'
          width: 80,              // Use 'width'
          height: 25,             // Use 'height'
          // pixelWidth and pixelHeight have defaults, so omit if not needed
        ),
      );

      // Use utf8.decoder.bind() for stream transformation
      utf8.decoder.bind(_shellSession!.stdout).listen(
        (data) { _outputController.add(data); },
        onError: (error) {
          debugPrint("Shell stdout error: $error");
          _outputController.add("\n[Shell stdout error: $error]\n");
        },
        onDone: () {
          debugPrint("Shell stdout stream closed.");
        }
      );

      utf8.decoder.bind(_shellSession!.stderr).listen(
        (data) { _outputController.add("[STDERR] $data"); }, // Prefix stderr
        onError: (error) {
          debugPrint("Shell stderr error: $error");
          _outputController.add("\n[Shell stderr error: $error]\n");
        },
        onDone: () {
          debugPrint("Shell stderr stream closed.");
        }
      );

      // Handle shell session closing unexpectedly
      _shellSession!.done.then((_) {
        debugPrint("Shell session closed.");
        // If the client is still technically connected, this indicates an issue.
        if (_currentStatus == SshConnectionStatus.connected) {
          // Maybe trigger a disconnect or show an error
          disconnect(); // Trigger full disconnect process
          _updateStatus(SshConnectionStatus.error, errorMsg: "Shell session closed unexpectedly");
        }
        _shellSession = null; // Clear the session variable
      });

      debugPrint("Interactive shell started.");

    } catch (e) {
      debugPrint("Failed to start shell: $e");
      _updateStatus(SshConnectionStatus.error, errorMsg: "Failed to start shell: $e");
      // Attempt to disconnect cleanly if shell fails
      await disconnect();
    }
  }


  Future<void> connect({
    required String host,
    required int port,
    required String username,
    String? password,
    String? privateKeyData,
    String? passphrase,
  }) async {
    if (_currentStatus != SshConnectionStatus.disconnected) {
      await disconnect();
    }
    
    _updateStatus(SshConnectionStatus.connecting);

    try {
      // Create socket connection
      final socket = await SSHSocket.connect(host, port);
      
      // Parse private key if provided
      List<SSHKeyPair>? keyPairs;
      if (privateKeyData != null) {
        try {
          // Use correct positional argument for fromPem
          keyPairs = SSHKeyPair.fromPem(privateKeyData, passphrase); // Passphrase is optional positional
          if (keyPairs.isEmpty) {
            throw Exception('No valid keys found in the provided private key data');
          }
        } catch (e) {
          debugPrint('SSH Key parsing error: $e');
          throw Exception('Failed to parse private key: $e');
        }
      }

      _client = SSHClient(
        socket,
        username: username,
        identities: keyPairs,
        onPasswordRequest: () => password,
        onAuthenticated: () {
          debugPrint('SSH Authenticated successfully!');
          _updateStatus(SshConnectionStatus.connected);
          // Start shell after successful authentication
          _startShell();
        },
        printTrace: kDebugMode ? print : null,
      );

      await _client?.authenticated;

      _client?.done.then((_) {
        if (_currentStatus != SshConnectionStatus.disconnecting && 
            _currentStatus != SshConnectionStatus.disconnected) {
          debugPrint("SSH client disconnected unexpectedly.");
          _updateStatus(SshConnectionStatus.disconnected, 
            errorMsg: "Connection lost unexpectedly");
          _shellSession = null;
        }
      });

    } catch (e) {
      debugPrint('SSH Connection Error: $e');
      await disconnect();
      _updateStatus(SshConnectionStatus.error, errorMsg: e.toString());
    }
  }


  Future<void> disconnect() async {
    if (_client == null && _currentStatus == SshConnectionStatus.disconnected) return;

    _updateStatus(SshConnectionStatus.disconnecting);
    try {
       // Close shell session first
       _shellSession?.close(); // Signal shell to close
       await _shellSession?.done; // Wait for shell to close
       _shellSession = null;
       
       _client?.close();
       await _client?.done;
    } catch (e) {
       debugPrint("Error during SSH disconnect: $e");
    } finally {
       _client = null;
       _updateStatus(SshConnectionStatus.disconnected);
    }
  }


  // --- RENAMED & MODIFIED: Send a complete command line ---
  Future<void> sendCommand(String command) async {
    if (_shellSession == null || _currentStatus != SshConnectionStatus.connected) {
      throw Exception("Not connected or shell not ready.");
    }
    // Send command followed by newline
    await sendRawInput('$command\n');
    debugPrint("Sent command line: $command");
  }

  // --- NEW: Send raw input (e.g., from terminal keyboard) ---
  Future<void> sendRawInput(String data) async {
    if (_shellSession == null || _currentStatus != SshConnectionStatus.connected) {
      // Maybe handle this more gracefully than throwing? Log and ignore?
      // For now, throw if trying to send input when not ready.
      throw Exception("Not connected or shell not ready for input.");
    }
    if (data.isEmpty) return; // Don't send empty data

    try {
       // Write the raw data directly to the shell's stdin
       _shellSession!.stdin.add(utf8.encode(data));
       // No flush needed/available
       // debugPrint("Sent raw input: ${data.replaceAll('\n', '\\n')}"); // Optional logging
    } catch (e) {
       debugPrint("Failed to write raw input to shell stdin: $e");
       throw Exception("Failed to send input: $e");
    }
  }


  // --- <<< NEW: Run command specifically for output (non-interactive) >>> ---
  Future<String> runCommandForOutput(String command) async {
    if (_client == null || _currentStatus != SshConnectionStatus.connected) {
      throw Exception("Not connected to SSH server.");
    }
    if (command.trim().isEmpty) {
      throw Exception("Command cannot be empty.");
    }

    debugPrint("Running for output: $command");
    try {
      // Use client.run() for a non-interactive session, capturing output
      final result = await _client!.run(command, stderr: true); // Capture stderr too
      final decodedOutput = utf8.decode(result, allowMalformed: true); // Allow potential malformed output
      debugPrint("Output received: ${decodedOutput.substring(0, (decodedOutput.length > 100 ? 100 : decodedOutput.length))}..."); // Log snippet
      return decodedOutput;
    } on SSHChannelOpenError catch (e) {
       debugPrint("SSH Command Error (Channel - run): $e");
       throw Exception("Failed to open channel for command: ${e.toString()}");
    } catch (e) {
       debugPrint("SSH Command Error (run): $e");
       throw Exception("Failed to execute command '$command': $e");
    }
  }
  // --- <<< END NEW >>> ---

  void dispose() {
    _statusController.close();
    _outputController.close(); // Close output stream controller
    disconnect();
  }
}