import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:server_manager_app/models/managed_key.dart'; // Import ManagedKey
import 'package:server_manager_app/models/server.dart';
import 'package:server_manager_app/providers/key_provider.dart'; // Import KeyProvider
import 'package:server_manager_app/providers/server_provider.dart';
// Import the key management screen for navigation hint
import 'package:server_manager_app/screens/key_management_screen.dart';

class AddServerScreen extends StatefulWidget {
  const AddServerScreen({super.key});

  @override
  State<AddServerScreen> createState() => _AddServerScreenState();
}

class _AddServerScreenState extends State<AddServerScreen> {
  final _formKey = GlobalKey<FormState>();
  AuthenticationMethod _selectedAuthMethod = AuthenticationMethod.password;
  String? _selectedKeyId; // To store the ID of the chosen managed key
  ServerType _selectedServerType = ServerType.generic; // <<< NEW state variable

  // Controllers
  final _nameController = TextEditingController();
  final _hostController = TextEditingController();
  final _portController = TextEditingController(text: '22');
  final _userController = TextEditingController();
  final _passwordController = TextEditingController();
  // Removed: final _privateKeyController = TextEditingController();

  bool _isSaving = false;
  bool _obscurePassword = true;

  @override
  void dispose() {
    _nameController.dispose();
    _hostController.dispose();
    _portController.dispose();
    _userController.dispose();
    _passwordController.dispose();
    // Removed: _privateKeyController.dispose();
    super.dispose();
  }

  // Helper function to get display name for ServerType
  String _getServerTypeDisplayName(ServerType type) {
     switch (type) {
       case ServerType.generic: return 'Generic Linux';
       case ServerType.cloudpanel: return 'CloudPanel';
       case ServerType.whmCpanel: return 'WHM / cPanel';
     }
  }

  Future<void> _saveForm() async {
    final isValid = _formKey.currentState?.validate() ?? false;
    if (!isValid) {
      return;
    }

    // Specific validation for auth method
    if (_selectedAuthMethod == AuthenticationMethod.password && _passwordController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Password cannot be empty.'), backgroundColor: Colors.red));
      return;
    }
    if (_selectedAuthMethod == AuthenticationMethod.managedKey && _selectedKeyId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please select a Managed SSH Key.'), backgroundColor: Colors.red));
      return;
    }

    _formKey.currentState?.save();

    setState(() => _isSaving = true);

    // Read providers using context.read within the callback
    final serverProvider = context.read<ServerProvider>();

    bool success = false;
    try {
      success = await serverProvider.addServer(
        name: _nameController.text.trim(),
        host: _hostController.text.trim(),
        port: int.tryParse(_portController.text.trim()) ?? 22,
        user: _userController.text.trim(),
        authMethod: _selectedAuthMethod,
        serverType: _selectedServerType, // <<< PASS selected type
        password: _selectedAuthMethod == AuthenticationMethod.password
            ? _passwordController.text
            : null,
        managedKeyId: _selectedAuthMethod == AuthenticationMethod.managedKey
            ? _selectedKeyId // Pass the selected key ID
            : null,
      );

      if (mounted && success) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Server "${_nameController.text.trim()}" added.'), backgroundColor: Colors.green));
        Navigator.of(context).pop();
      } else if (mounted && !success) {
           // Error message is handled by the provider now, just prevent popping
           debugPrint("Add server failed, provider should show error.");
           // Optionally show a generic failure snackbar if provider error display isn't enough
           // ScaffoldMessenger.of(context).showSnackBar(
           //   SnackBar(content: Text('Failed to add server. Check logs.'), backgroundColor: Colors.red));
      }
    } catch (error) {
      // Catch potential exceptions from addServer if it re-throws
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error: $error'), backgroundColor: Colors.red));
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Watch KeyProvider to rebuild dropdown when keys change
    final availableKeys = context.watch<KeyProvider>().keys;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Add New Server'),
        actions: [
          IconButton(
            icon: _isSaving
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.save),
            onPressed: _isSaving ? null : _saveForm,
            tooltip: 'Save Server',
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: ListView(
            children: [
              // ... (Name, Host, User, Port TextFormFields remain the same) ...
               TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(labelText: 'Server Name / Alias'),
                textInputAction: TextInputAction.next,
                validator: (value) => (value == null || value.trim().isEmpty) ? 'Please enter a name.' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _hostController,
                decoration: const InputDecoration(labelText: 'Hostname or IP Address'),
                textInputAction: TextInputAction.next,
                keyboardType: TextInputType.url,
                 validator: (value) => (value == null || value.trim().isEmpty) ? 'Please enter host/IP.' : null,
              ),
               const SizedBox(height: 12),
               Row(
                 crossAxisAlignment: CrossAxisAlignment.start,
                 children: [
                    Expanded(
                      flex: 3,
                      child: TextFormField(
                        controller: _userController,
                        decoration: const InputDecoration(labelText: 'Username'),
                        textInputAction: TextInputAction.next,
                        validator: (value) => (value == null || value.trim().isEmpty) ? 'Enter username.' : null,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 1,
                      child: TextFormField(
                        controller: _portController,
                        decoration: const InputDecoration(labelText: 'Port'),
                        textInputAction: TextInputAction.next,
                        keyboardType: TextInputType.number,
                        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) return 'Enter Port.';
                          final port = int.tryParse(value);
                          if (port == null || port < 1 || port > 65535) return 'Invalid Port.';
                          return null;
                        },
                      ),
                    ),
                 ],
               ),
              const SizedBox(height: 20),
              Text('Authentication Method', style: Theme.of(context).textTheme.titleMedium),
              RadioListTile<AuthenticationMethod>(
                title: const Text('Password'),
                value: AuthenticationMethod.password,
                groupValue: _selectedAuthMethod,
                onChanged: (AuthenticationMethod? value) {
                  if (value != null) setState(() => _selectedAuthMethod = value);
                },
              ),
              RadioListTile<AuthenticationMethod>(
                // Updated title
                title: const Text('Managed SSH Key'),
                value: AuthenticationMethod.managedKey,
                groupValue: _selectedAuthMethod,
                onChanged: (AuthenticationMethod? value) {
                  if (value != null) setState(() => _selectedAuthMethod = value);
                },
              ),
              const SizedBox(height: 20),

              // --- <<< NEW: Server Type Dropdown >>> ---
              Text('Server Type', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              DropdownButtonFormField<ServerType>(
                 value: _selectedServerType,
                 items: ServerType.values.map((ServerType type) {
                    return DropdownMenuItem<ServerType>(
                       value: type,
                       child: Text(_getServerTypeDisplayName(type)), // Use helper for display name
                    );
                 }).toList(),
                 onChanged: (ServerType? newValue) {
                    if (newValue != null) {
                       setState(() {
                         _selectedServerType = newValue;
                       });
                    }
                 },
                 decoration: const InputDecoration(
                   // labelText: 'Server Type', // Optional
                   border: OutlineInputBorder()
                 ),
              ),
              // --- <<< END NEW >>> ---

              const SizedBox(height: 12),

              // --- Conditional Fields ---
              if (_selectedAuthMethod == AuthenticationMethod.password)
                TextFormField(
                  controller: _passwordController,
                  decoration: InputDecoration(
                      labelText: 'Password',
                      suffixIcon: IconButton(
                        icon: Icon(_obscurePassword ? Icons.visibility_off : Icons.visibility),
                        onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                      )),
                  obscureText: _obscurePassword,
                  textInputAction: TextInputAction.done,
                  // Validator handled in _saveForm
                ),

              // Updated: Show Dropdown for Managed Keys
              if (_selectedAuthMethod == AuthenticationMethod.managedKey)
                if (availableKeys.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8.0),
                    child: Row(
                      children: [
                        const Icon(Icons.warning_amber_rounded, color: Colors.amber),
                        const SizedBox(width: 8),
                        const Expanded(child: Text('No managed keys available.')),
                        TextButton(
                           // Navigate to key management screen
                           onPressed: () {
                              Navigator.of(context).push(MaterialPageRoute(
                                builder: (ctx) => const KeyManagementScreen(),
                              ));
                           },
                          child: const Text('Add Key'),
                        ),
                      ],
                    ),
                  )
                else
                  DropdownButtonFormField<String>(
                    value: _selectedKeyId, // Currently selected key ID
                    hint: const Text('Select SSH Key'),
                    // Use items generated from the KeyProvider
                    items: availableKeys.map<DropdownMenuItem<String>>((ManagedKey key) {
                      return DropdownMenuItem<String>(
                        value: key.id, // The value is the key's unique ID
                        child: Text(key.label), // Display the user-friendly label
                      );
                    }).toList(),
                    onChanged: (String? newValue) {
                      setState(() {
                        _selectedKeyId = newValue; // Store the selected key's ID
                      });
                    },
                    validator: (value) => value == null ? 'Please select a key' : null,
                    decoration: const InputDecoration(
                      // labelText: 'Managed SSH Key', // Optional label
                       border: OutlineInputBorder() // Add border for clarity
                    ),
                  ),

              const SizedBox(height: 30),
              ElevatedButton(
                onPressed: _isSaving ? null : _saveForm,
                style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 15)),
                child: _isSaving ? const Text('Saving...') : const Text('Add Server'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}