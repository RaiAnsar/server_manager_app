// lib/screens/server_detail_screen.dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:xterm/xterm.dart';
import 'package:server_manager_app/models/server.dart';
import 'package:server_manager_app/providers/key_provider.dart';
import 'package:server_manager_app/providers/server_provider.dart';
import 'package:server_manager_app/services/ssh_service.dart';

class ServerDetailScreen extends StatefulWidget {
  final Server server;
  const ServerDetailScreen({required this.server, super.key});
  @override
  State<ServerDetailScreen> createState() => _ServerDetailScreenState();
}

class _ServerDetailScreenState extends State<ServerDetailScreen> with SingleTickerProviderStateMixin {
  late final SshService _sshService;
  SshConnectionStatus _connectionStatus = SshConnectionStatus.disconnected;
  String? _connectionError;
  bool _isExecutingCommand = false;

  final _commandController = TextEditingController();
  // Keep Terminal, remove TerminalController if not used by View
  final _terminal = Terminal(maxLines: 10000);

  StreamSubscription<String>? _outputSubscription;
  
  // --- <<< NEW: CloudPanel State >>> ---
  List<String>? _cloudPanelDatabases;
  bool _isLoadingDatabases = false;
  String? _databaseListError;
  // --- <<< END NEW >>> ---
  
  // Key for TabBarView to prevent hero tag conflicts
  final _tabBarViewKey = GlobalKey();
  
  // Database Dialog Methods
  Future<void> _showAddDatabaseDialog() async {
    final formKey = GlobalKey<FormState>();
    final dbNameController = TextEditingController();
    final userNameController = TextEditingController();
    final passwordController = TextEditingController();
    bool isSaving = false;

    return showDialog<void>(
      context: context,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Add CloudPanel Database'),
              content: SingleChildScrollView(
                child: Form(
                  key: formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      TextFormField(
                        controller: dbNameController,
                        decoration: const InputDecoration(labelText: 'Database Name'),
                        validator: (value) => (value == null || value.trim().isEmpty) ? 'Required' : null,
                      ),
                      TextFormField(
                        controller: userNameController,
                        decoration: const InputDecoration(labelText: 'Database User Name'),
                        validator: (value) => (value == null || value.trim().isEmpty) ? 'Required' : null,
                      ),
                      TextFormField(
                        controller: passwordController,
                        decoration: const InputDecoration(labelText: 'Database Password'),
                        obscureText: true,
                        validator: (value) => (value == null || value.isEmpty) ? 'Required' : null,
                      ),
                    ],
                  ),
                ),
              ),
              actions: <Widget>[
                TextButton(
                  onPressed: isSaving ? null : () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: isSaving ? null : () async {
                    if (formKey.currentState!.validate()) {
                      setDialogState(() => isSaving = true);
                      final dbName = dbNameController.text.trim();
                      final userName = userNameController.text.trim();
                      final password = passwordController.text;

                      final command = "clpctl db:add --domainName='${widget.server.name}' --databaseName='$dbName' --databaseUserName='$userName' --databaseUserPassword='$password'";
                      
                      String? addError;
                      try {
                        debugPrint("Running Add DB Command: $command");
                        final output = await _sshService.runCommandForOutput(command);
                        debugPrint("Add DB Output: $output");
                        
                        if (output.toLowerCase().contains('error')) {
                          throw Exception(output);
                        }
                        
                        if (!context.mounted) return;
                        Navigator.of(context).pop();
                        _fetchCloudPanelDatabases();
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Database "$dbName" added.'), backgroundColor: Colors.green)
                        );
                      } catch (e) {
                        addError = "Failed to add database: $e";
                        debugPrint(addError);
                      } finally {
                        if (mounted) {
                          setDialogState(() => isSaving = false);
                          if (addError != null) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text(addError), backgroundColor: Colors.red)
                            );
                          }
                        }
                      }
                    }
                  },
                  child: isSaving 
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) 
                    : const Text('Add Database'),
                ),
              ],
            );
          }
        );
      },
    );
  }

  Future<void> _confirmDeleteDatabase(String dbName) async {
    return showDialog<void>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Confirm Deletion'),
          content: Text('Are you sure you want to delete the database "$dbName"? This cannot be undone.'),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            TextButton(
              style: TextButton.styleFrom(foregroundColor: Theme.of(context).colorScheme.error),
              onPressed: () async {
                Navigator.of(context).pop();
                String? deleteError;
                try {
                  final command = "clpctl db:delete --databaseName='$dbName' --force";
                  debugPrint("Running Delete DB command: $command");
                  final output = await _sshService.runCommandForOutput(command);
                  debugPrint("Delete DB output: $output");
                  
                  if (output.toLowerCase().contains('error')) {
                    throw Exception(output);
                  }
                  
                  if (!context.mounted) return;
                  _fetchCloudPanelDatabases();
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Database "$dbName" deleted.'), backgroundColor: Colors.green)
                  );
                } catch (e) {
                  deleteError = "Failed to delete database: $e";
                  debugPrint(deleteError);
                } finally {
                  if (mounted && deleteError != null) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(deleteError), backgroundColor: Colors.red)
                    );
                  }
                }
              },
              child: const Text('Delete'),
            ),
          ],
        );
      }
    );
  }
  
  // --- TabController and Tab Data ---
  late TabController _tabController;
  final List<Tab> _tabs = []; // Will populate based on server type etc.
  final List<Widget> _tabViews = []; // Content for each tab
  
  @override
  void initState() {
    super.initState();
    _sshService = SshService();
    
    // Setup Tabs
    _setupTabs();
    
    // Initialize TabController
    _tabController = TabController(length: _tabs.length, vsync: this);

    _sshService.statusStream.listen((status) {
      if (mounted) {
        setState(() {
          _connectionStatus = status;
          _connectionError = _sshService.lastError;
          if (status == SshConnectionStatus.disconnected || status == SshConnectionStatus.error) {
            // Use ANSI codes to clear
            _terminal.write('\x1b[2J\x1b[H'); // Clear screen & move cursor home
            _commandController.clear();
          }
        });
      }
    });

    _outputSubscription = _sshService.outputStream.listen(
       (data) { if (mounted) { _terminal.write(data); } }, // Write directly
       onError: (error) { 
         if (mounted) { _terminal.write('\n[Output Stream Error: $error]\n'); }
         debugPrint("SSH Output Stream Error: $error");
       }
    );

    // Set onOutput callback on Terminal directly
    _terminal.onOutput = (data) {
      _sshService.sendRawInput(data); // Send input from terminal to SSH service
    };
  }

  void _setupTabs() {
    _tabs.clear();
    _tabViews.clear();

    // Always add Terminal Tab
    _tabs.add(const Tab(icon: Icon(Icons.terminal_rounded), text: 'Terminal'));
    _tabViews.add(_LazyTabContent(index: 0, builder: _buildTerminalTab));
    
    // Add Actions Tab
    _tabs.add(const Tab(icon: Icon(Icons.play_for_work_rounded), text: 'Actions'));
    _tabViews.add(_LazyTabContent(index: 1, builder: _buildActionsTab));

    // Add Server-Specific Tabs
    if (widget.server.serverType == ServerType.cloudpanel) {
      _tabs.add(const Tab(icon: Icon(Icons.cloud_circle_outlined), text: 'CloudPanel'));
      _tabViews.add(_LazyTabContent(index: 2, builder: _buildCloudPanelTab));
    }
    
    // TODO: Add more tabs based on server type if needed
  }

  @override
  void dispose() {
    _tabController.dispose();
    _outputSubscription?.cancel();
    _sshService.disconnect();
    _sshService.dispose();
    _commandController.dispose();
    super.dispose();
  }

  Future<void> _connectToServer() async {
    if (_connectionStatus == SshConnectionStatus.connecting || _connectionStatus == SshConnectionStatus.connected) return;
    final serverProvider = context.read<ServerProvider>();
    final keyProvider = context.read<KeyProvider>();
    String? password; String? privateKey; String? passphrase;
    try {
      if (widget.server.authMethod == AuthenticationMethod.password) {
        password = await serverProvider.getPassword(widget.server.id);
      } else if (widget.server.authMethod == AuthenticationMethod.managedKey && widget.server.managedKeyId != null) {
        final credentials = await keyProvider.getKeyCredentials(widget.server.managedKeyId!);
        privateKey = credentials['privateKey']; passphrase = credentials['passphrase'];
      } else { throw Exception("Invalid authentication configuration."); }
      await _sshService.connect( host: widget.server.host, port: widget.server.port, username: widget.server.user, password: password, privateKeyData: privateKey, passphrase: passphrase,);
    } catch (e) {
      if (mounted) {
        setState(() { _connectionStatus = SshConnectionStatus.error; _connectionError = "Failed to get credentials or connect: $e"; });
        ScaffoldMessenger.of(context).showSnackBar( SnackBar(content: Text("Connection Error: $e"), backgroundColor: Colors.red) );
      }
    }
  }

  Future<void> _disconnectFromServer() async {
    await _sshService.disconnect();
  }

  // Command Execution Logic (Simplified)
  Future<void> _executeEnteredCommand() async {
    if (_commandController.text.trim().isEmpty || _isExecutingCommand) return;

    final commandToRun = _commandController.text.trim();
    // Don't manually add command echo, terminal/shell usually handles it

    setState(() {
       _isExecutingCommand = true; // Set loading (disables input/button)
       // Optional: Clear input field immediately after sending
       _commandController.clear();
    });

    try {
      // Send the command - no direct result awaited here
      await _sshService.sendCommand(commandToRun);
      // Output will arrive via listener -> terminal.write()
    } catch(e) {
       // Handle error *sending* the command (not execution errors from the shell)
       if (mounted) {
          // Write error to terminal
          _terminal.write('\nError sending command: $e\n');
          ScaffoldMessenger.of(context).showSnackBar(
             SnackBar(content: Text("Send Error: $e"), backgroundColor: Colors.red)
          );
       }
    } finally {
       // Command is sent, UI can re-enable input field etc.
       // The actual command execution on the server is asynchronous.
       if (mounted) {
          setState(() {
            _isExecutingCommand = false;
          });
       }
    }
  }
  
  // --- <<< NEW: CloudPanel Method >>> ---
  Future<void> _fetchCloudPanelDatabases() async {
    if (_isLoadingDatabases) return;
    setState(() {
      _isLoadingDatabases = true;
      _databaseListError = null;
      _cloudPanelDatabases = null;
    });

    String? connectCommand; // Store the extracted command

    try {
      // 1. Get Master Credentials Output
      const credsCommand = 'clpctl db:show:master-credentials';
      final credsOutput = await _sshService.runCommandForOutput(credsCommand);
      debugPrint("Raw Master Credentials Output:\n$credsOutput");

      // --- <<< REVISED Parsing: Extract Connect Command >>> ---
      // Regex to find the line starting with "Connect Command:" and capture the mysql command
      final connectMatch = RegExp(r"^\s*Connect Command:\s*(mysql\s+.*)$", multiLine: true)
                             .firstMatch(credsOutput);

      if (connectMatch == null || connectMatch.group(1) == null) {
        throw Exception("Could not find 'Connect Command:' in clpctl output.");
      }
      connectCommand = connectMatch.group(1)!.trim(); // Get the captured mysql command
      debugPrint("Extracted Connect Command: $connectCommand");
      // --- <<< END REVISED Parsing >>> ---


      // 2. Modify and Run SHOW DATABASES Command
      // Modify the extracted command: remove common ending flags like -A or specific db name
      // and append the execute flag for SHOW DATABASES.
      // This regex removes optional trailing database name or flags like -A
      final baseConnectCommand = connectCommand.replaceAll(RegExp(r'\s+(-A|\S+)$'), '');
      final listDbCommand = '$baseConnectCommand -e "SHOW DATABASES;"';

      debugPrint("Executing List DB Command: $listDbCommand");
      final listDbOutput = await _sshService.runCommandForOutput(listDbCommand);
      debugPrint("Raw SHOW DATABASES Output:\n$listDbOutput");


      // 3. Parse SHOW DATABASES Output (Remains the Same)
      final lines = listDbOutput.split('\n');
      final databases = <String>[];
      // Added 'Database' and the mysql warning line start to filter list
      final systemDBs = {'information_schema', 'mysql', 'performance_schema', 'sys', 'Database'};
      final warningPrefix = 'mysql: [Warning]';

      for (final line in lines) {
         final dbName = line.trim();
         // Check if not empty, not a system DB, and not the warning line
         if (dbName.isNotEmpty && !systemDBs.contains(dbName) && !dbName.startsWith(warningPrefix)) {
            databases.add(dbName);
         }
      }
      // --- End Parsing ---

      setState(() { _cloudPanelDatabases = databases; });

    } catch (e) {
      final errorMsg = "Failed to list databases: ${e.toString()}";
      setState(() { _databaseListError = errorMsg; });
      debugPrint(errorMsg);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(errorMsg), backgroundColor: Colors.red)
        );
      }
    } finally {
      if (mounted) { setState(() { _isLoadingDatabases = false; }); }
    }
  }
  // --- <<< END NEW >>> ---

  // Service Control Methods
  Future<void> _runServiceCommand(String service, String action) async {
    final command = 'systemctl $action $service';
    debugPrint("Running Service Command: $command");
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Running: $command...'), duration: const Duration(seconds: 2))
    );
    try {
      final output = await _sshService.runCommandForOutput(command);
      debugPrint("Service Command Output ($service $action):\n$output");
      // Check mounted BEFORE showing snackbar
      if (!mounted) return;
      // Check output for common errors
      if (output.toLowerCase().contains('fail') || output.toLowerCase().contains('error')) {
        throw Exception(output.split('\n').first); // Show first line of error
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$service ${action}ed successfully.'), backgroundColor: Colors.green)
      );
    } catch (e) {
      final errorMsg = "Failed to $action $service: ${e.toString().split('\n').first}";
      debugPrint(errorMsg);
      // Check mounted BEFORE showing snackbar
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(errorMsg), backgroundColor: Colors.red)
      );
    }
  }


  @override
  Widget build(BuildContext context) {
    final keyProvider = context.read<KeyProvider>();
    final theme = Theme.of(context); // Get theme

    String authDetail = '';
     if (widget.server.authMethod == AuthenticationMethod.password) { authDetail = 'Password Auth'; }
     else if (widget.server.authMethod == AuthenticationMethod.managedKey && widget.server.managedKeyId != null) {
       String keyLabel = "Unknown Key";
       final keyIndex = keyProvider.keys.indexWhere((k) => k.id == widget.server.managedKeyId);
       if (keyIndex != -1) { keyLabel = keyProvider.keys[keyIndex].label; }
       authDetail = 'Key: $keyLabel';
     } else { authDetail = 'Invalid Auth Config'; }

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.server.name),
        actions: [
          // MOVE Disconnect Button Here
          if (_connectionStatus == SshConnectionStatus.connected)
             IconButton(
               icon: const Icon(Icons.link_off),
               tooltip: 'Disconnect',
               onPressed: _disconnectFromServer,
             ),
          // END MOVE

          // Keep status chip
          Padding(
            padding: const EdgeInsets.only(right: 12.0),
            child: Center(child: _buildConnectionStatusChip(_connectionStatus)),
          )
        ],
        // Add TabBar to the AppBar's bottom property
        bottom: (_tabs.isNotEmpty && _connectionStatus == SshConnectionStatus.connected)
            ? TabBar(
                controller: _tabController,
                isScrollable: true,
                tabs: _tabs,
              )
            : null,
      ),
      // Use Column to separate Connection Card from Tabs
      body: Column(
        children: [
          // Connection Details Card (always visible)
          Padding(
            padding: const EdgeInsets.fromLTRB(12.0, 12.0, 12.0, 0),
            child: Card(
              elevation: 2,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              child: Padding(
                padding: const EdgeInsets.all(16.0), // Keep padding
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text("Connection Details", style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    // REVISED Compact Info Area
                    Wrap( // Use Wrap widget - fixed indentation here
                      spacing: 12.0, // Horizontal space between items
                      runSpacing: 4.0,  // Vertical space if it wraps (less needed)
                      crossAxisAlignment: WrapCrossAlignment.center, // Align items vertically in the center
                      children: [
                        // Call the helper for each detail item
                        _buildDetailRow(theme, Icons.dns_outlined, '${widget.server.host}:${widget.server.port}'),
                        _buildDetailRow(theme, Icons.person_outline, widget.server.user),
                        _buildDetailRow(
                           theme,
                           widget.server.authMethod == AuthenticationMethod.managedKey
                              ? Icons.vpn_key_outlined
                              : Icons.password_outlined,
                           authDetail // authDetail is calculated earlier
                        ),
                      ],
                    ),

                    if (_connectionStatus == SshConnectionStatus.error && _connectionError != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 12.0), // Add padding before error
                        child: Text('Error: $_connectionError', style: TextStyle(color: theme.colorScheme.error)),
                      ),

                    const SizedBox(height: 20), // Spacing before button

                    // Center the Connect button (Disconnect moves to AppBar)
                    if (_connectionStatus != SshConnectionStatus.connected) // Show connect button only if not connected
                       Center(
                         child: ElevatedButton.icon(
                           icon: const Icon(Icons.power_settings_new),
                           label: Text(
                              _connectionStatus == SshConnectionStatus.connecting ? 'Connecting...' : 'Connect'
                           ),
                           onPressed: (_connectionStatus == SshConnectionStatus.connecting) ? null : _connectToServer,
                           style: ElevatedButton.styleFrom(
                              minimumSize: const Size(150, 40),
                              backgroundColor: theme.colorScheme.primary,
                              foregroundColor: Colors.white,
                           ),
                         ),
                       ),
                  ],
                ),
              ),
            ),
          ), // End of Connection Card
          
          // TabBarView - Expanded to fill the remaining space
          Expanded(
            child: _tabs.isEmpty
              ? const Center(child: Text('Connect to server to see available actions.'))
              : TabBarView(
                  key: _tabBarViewKey, // Add key to fix Hero tag conflicts
                  controller: _tabController,
                  children: _tabViews,
                ),
          ),
        ],
      ),
    );
  }

  // Helper to build detail row
  Widget _buildDetailRow(ThemeData theme, IconData icon, String text) {
    return Row(
      mainAxisSize: MainAxisSize.min, // Row takes minimum space needed
      children: [
        Icon(icon, size: 16, color: theme.colorScheme.onSurfaceVariant), // Use a subtle color
        const SizedBox(width: 8),
        // Use Flexible to allow text to wrap if needed, though unlikely here
        Flexible(child: Text(text, style: theme.textTheme.bodyMedium)),
      ],
    );
  }

  // Helper methods for building tab content
  Widget _buildTerminalTab() {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Command Input Row
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _commandController,
                  decoration: const InputDecoration(
                    hintText: 'Enter command (e.g., ls -la)',
                    border: OutlineInputBorder(),
                    contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  ),
                  style: const TextStyle(fontFamily: 'monospace'),
                  onSubmitted: (_) => _executeEnteredCommand(),
                  enabled: !_isExecutingCommand,
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                icon: _isExecutingCommand
                     ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                     : const Icon(Icons.play_arrow_rounded),
                tooltip: 'Execute Command',
                onPressed: _isExecutingCommand ? null : _executeEnteredCommand,
                style: IconButton.styleFrom(
                    backgroundColor: theme.colorScheme.primary,
                    foregroundColor: theme.colorScheme.onPrimary,
                    padding: const EdgeInsets.all(12),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          
          // Predefined Command Buttons
          Wrap(
            spacing: 8.0,
            runSpacing: 4.0,
            children: [
              OutlinedButton.icon(
                icon: const Icon(Icons.timer_outlined, size: 18),
                label: const Text('Uptime'),
                onPressed: _isExecutingCommand ? null : () { _commandController.text = 'uptime'; _executeEnteredCommand(); },
                style: OutlinedButton.styleFrom(
                   padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                   textStyle: const TextStyle(fontSize: 12),
                ),
              ),
              OutlinedButton.icon(
                icon: const Icon(Icons.storage_outlined, size: 18),
                label: const Text('Disk Usage'),
                onPressed: _isExecutingCommand ? null : () { _commandController.text = 'df -h'; _executeEnteredCommand(); },
                style: OutlinedButton.styleFrom(
                   padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                   textStyle: const TextStyle(fontSize: 12),
                ),
              ),
              OutlinedButton.icon(
                icon: const Icon(Icons.memory_outlined, size: 18),
                label: const Text('Memory'),
                onPressed: _isExecutingCommand ? null : () { _commandController.text = 'free -h'; _executeEnteredCommand(); },
                style: OutlinedButton.styleFrom(
                   padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                   textStyle: const TextStyle(fontSize: 12),
                ),
              ),
              OutlinedButton.icon(
                icon: const Icon(Icons.list_alt_outlined, size: 18),
                label: const Text('Processes'),
                onPressed: _isExecutingCommand ? null : () { _commandController.text = 'ps aux | head -n 20'; _executeEnteredCommand(); },
                style: OutlinedButton.styleFrom(
                   padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                   textStyle: const TextStyle(fontSize: 12),
                ),
              ),
            ],
          ),
          
          const SizedBox(height: 16),
          
          // Output Section Header
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text("Output / Terminal", style: theme.textTheme.titleSmall),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(Icons.cancel_presentation_outlined),
                    iconSize: 20,
                    color: Colors.orange[700],
                    tooltip: 'Send Ctrl+C (SIGINT)',
                    onPressed: () {
                       _sshService.sendRawInput('\x03');
                    },
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete_sweep_outlined),
                    iconSize: 20,
                    color: Colors.grey[600],
                    tooltip: 'Clear Terminal (send clear command)',
                    onPressed: () {
                      try {
                        _sshService.sendCommand('clear');
                      } catch (e) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text("Failed to send clear command: $e"), backgroundColor: Colors.red)
                        );
                      }
                    },
                  ),
                ],
              )
            ],
          ),
          const SizedBox(height: 8),
          
          // Terminal View (Expanded to fill remaining space)
          Expanded(
            child: TerminalView(
              _terminal,
              autofocus: true,
              theme: TerminalThemes.defaultTheme,
              textStyle: const TerminalStyle(fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionsTab() {
    final theme = Theme.of(context);
    if (_connectionStatus != SshConnectionStatus.connected) {
      return const Center(child: Text('Connect to server to perform actions.'));
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Card(
            elevation: 1,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text("Service Controls (systemd)", style: theme.textTheme.titleMedium),
                  const SizedBox(height: 16),
                  // Nginx Row
                  _buildServiceControlRow("Nginx", "nginx"),
                  const Divider(height: 24),
                  // MySQL/MariaDB Row
                  _buildServiceControlRow("MySQL / MariaDB", "mysql"),
                  const Divider(height: 24),
                  // PHP-FPM Row
                  _buildServiceControlRow("PHP-FPM (Default)", "php-fpm"),
                  const Divider(height: 24),
                  // Redis Row
                  _buildServiceControlRow("Redis", "redis-server"),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Helper widget for service control rows
  Widget _buildServiceControlRow(String displayName, String serviceName) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(displayName, style: Theme.of(context).textTheme.titleSmall),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.play_arrow_outlined),
              color: Colors.green,
              tooltip: 'Start $displayName',
              onPressed: () => _runServiceCommand(serviceName, 'start'),
            ),
            IconButton(
              icon: const Icon(Icons.refresh_outlined),
              color: Colors.blue,
              tooltip: 'Restart $displayName',
              onPressed: () => _runServiceCommand(serviceName, 'restart'),
            ),
            IconButton(
              icon: const Icon(Icons.stop_outlined),
              color: Colors.red,
              tooltip: 'Stop $displayName',
              onPressed: () => _runServiceCommand(serviceName, 'stop'),
            ),
            IconButton(
              icon: const Icon(Icons.info_outline),
              color: Colors.grey,
              tooltip: 'Status $displayName',
              onPressed: () {
                // Send status command to terminal view instead of runCommandForOutput
                final command = 'systemctl status $serviceName';
                _commandController.text = command;
                _sshService.sendCommand(command);
                // Switch to Terminal tab
                // --- <<< TEMPORARILY COMMENT OUT >>> ---
                // _tabController.animateTo(0); // Terminal tab is at index 0
                // --- <<< END COMMENT OUT >>> ---
              },
            ),
          ],
        ),
      ],
    );
  }
  
  Widget _buildCloudPanelTab() {
    final theme = Theme.of(context);
    
    // Show connect message if not connected
    if (_connectionStatus != SshConnectionStatus.connected) {
      return const Center(child: Text('Connect to server to manage CloudPanel.'));
    }

    // Build CloudPanel specific UI
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Databases Section
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text("Databases", style: theme.textTheme.titleMedium),
              IconButton(
                icon: const Icon(Icons.add_circle_outline),
                tooltip: 'Add Database',
                color: theme.colorScheme.primary,
                onPressed: _showAddDatabaseDialog,
              ),
            ],
          ),
          const SizedBox(height: 8),
          ElevatedButton.icon(
            icon: const Icon(Icons.refresh, size: 18),
            label: const Text("Refresh List"),
            onPressed: _isLoadingDatabases ? null : _fetchCloudPanelDatabases,
            style: ElevatedButton.styleFrom(visualDensity: VisualDensity.compact),
          ),
          const SizedBox(height: 12),
          
          // Display Loading / Error / List
          if (_isLoadingDatabases) 
            const Center(child: Padding(padding: EdgeInsets.all(8.0), child: CircularProgressIndicator(strokeWidth: 2)))
          else if (_databaseListError != null) 
            Text("Error: $_databaseListError", style: TextStyle(color: theme.colorScheme.error))
          else if (_cloudPanelDatabases != null && _cloudPanelDatabases!.isEmpty && !_isLoadingDatabases) 
            const Text("No databases found.")
          else if (_cloudPanelDatabases != null && _cloudPanelDatabases!.isNotEmpty)
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _cloudPanelDatabases!.length,
              itemBuilder: (context, index) {
                final dbName = _cloudPanelDatabases![index];
                return ListTile(
                  dense: true,
                  leading: const Icon(Icons.storage_rounded, size: 18),
                  title: Text(dbName),
                  trailing: IconButton(
                    icon: Icon(Icons.delete_outline, size: 20, color: Colors.redAccent[100]),
                    tooltip: 'Delete Database "$dbName"',
                    onPressed: () => _confirmDeleteDatabase(dbName),
                  ),
                  contentPadding: EdgeInsets.zero,
                );
              },
            ),
            
          // TODO: Add other sections (Sites, Users, etc.)
          const SizedBox(height: 24),
          const Divider(),
          const SizedBox(height: 16),
          Text("Sites (Placeholder)", style: theme.textTheme.titleMedium),
        ],
      ),
    );
  }

  // Helper to build status chip
  Widget _buildConnectionStatusChip(SshConnectionStatus status) {
    IconData icon;
    Color color;
    String label;

    switch (status) {
      case SshConnectionStatus.connected:
        icon = Icons.check_circle;
        color = Colors.green;
        label = 'Connected';
        break;
      case SshConnectionStatus.connecting:
         icon = Icons.sync; // Or CircularProgressIndicator
         color = Colors.blue;
         label = 'Connecting';
         break;
      case SshConnectionStatus.disconnecting:
         icon = Icons.sync_disabled;
         color = Colors.orange;
         label = 'Disconnecting';
         break;
      case SshConnectionStatus.error:
         icon = Icons.error;
         color = Colors.red;
         label = 'Error';
         break;
      case SshConnectionStatus.disconnected:
        icon = Icons.link_off;
        color = Colors.grey;
        label = 'Offline';
        break;
    }

    return Chip(
       avatar: Icon(icon, color: color, size: 18),
       label: Text(label),
       padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
       labelPadding: const EdgeInsets.only(left: 4), // Adjust padding if needed
    );
  }
}

// Helper class to lazily build tab content only when tab is visible
class _LazyTabContent extends StatelessWidget {
  final int index;
  final Widget Function() builder;
  
  const _LazyTabContent({required this.index, required this.builder, Key? key}) : super(key: key);
  
  @override
  Widget build(BuildContext context) {
    // The builder is called only when this widget is actually built,
    // which happens only when the tab is selected
    return builder();
  }
}