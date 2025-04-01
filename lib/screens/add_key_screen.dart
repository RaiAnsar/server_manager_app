// lib/screens/add_key_screen.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:server_manager_app/providers/key_provider.dart';

class AddKeyScreen extends StatefulWidget {
  const AddKeyScreen({super.key});

  @override
  State<AddKeyScreen> createState() => _AddKeyScreenState();
}

class _AddKeyScreenState extends State<AddKeyScreen> {
  final _formKey = GlobalKey<FormState>();
  final _labelController = TextEditingController();
  final _privateKeyController = TextEditingController();
  final _passphraseController = TextEditingController();

  bool _isSaving = false;
  bool _obscurePassphrase = true;

  @override
  void dispose() {
    _labelController.dispose();
    _privateKeyController.dispose();
    _passphraseController.dispose();
    super.dispose();
  }

  Future<void> _saveKey() async {
    final isValid = _formKey.currentState?.validate() ?? false;
    if (!isValid) {
      return;
    }

    setState(() => _isSaving = true);

    final keyProvider = context.read<KeyProvider>();
    final String label = _labelController.text.trim();
    final String privateKey = _privateKeyController.text; // Keep original newlines etc.
    final String? passphrase = _passphraseController.text.isNotEmpty
        ? _passphraseController.text
        : null;

    bool success = false;
    try {
       success = await keyProvider.addKey(
        label: label,
        privateKeyData: privateKey,
        passphrase: passphrase,
      );

      if (mounted && success) {
         ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Key "$label" added successfully.'), backgroundColor: Colors.green)
         );
         Navigator.of(context).pop(); // Go back
      } else if (mounted && !success) {
          // Error handled by provider state/snackbar
          debugPrint("Add key failed, provider should show error.");
      }

    } catch (e) {
        // Should be caught by provider, but just in case
         if (mounted) {
           ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red)
           );
         }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Add New SSH Key'),
        actions: [
           IconButton(
            icon: _isSaving
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.save),
            onPressed: _isSaving ? null : _saveKey,
            tooltip: 'Save Key',
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: ListView(
            children: [
              TextFormField(
                controller: _labelController,
                decoration: const InputDecoration(
                  labelText: 'Label',
                  hintText: 'e.g., Work Laptop Key, Personal Key',
                ),
                textInputAction: TextInputAction.next,
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Please enter a label for the key.';
                  }
                  // Could add check against existing labels here if desired
                  return null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _privateKeyController,
                decoration: const InputDecoration(
                  labelText: 'Private Key Data',
                  hintText: 'Paste the full content of your private key file (e.g., -----BEGIN OPENSSH PRIVATE KEY----- ...)',
                  alignLabelWithHint: true, // Good for multiline
                   border: OutlineInputBorder(),
                ),
                maxLines: 8, // Allow multiple lines
                minLines: 5,
                keyboardType: TextInputType.multiline,
                textInputAction: TextInputAction.newline, // Allow entering newlines
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Please paste your private key data.';
                  }
                  // Basic check - could be improved
                  if (!value.contains("-----BEGIN") || !value.contains("-----END")) {
                     return 'Key does not look like a valid PEM format.';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _passphraseController,
                decoration: InputDecoration(
                  labelText: 'Passphrase (Optional)',
                  hintText: 'Enter if your private key is encrypted',
                   suffixIcon: IconButton(
                      icon: Icon(_obscurePassphrase ? Icons.visibility_off : Icons.visibility),
                      onPressed: () => setState(() => _obscurePassphrase = !_obscurePassphrase),
                    )
                ),
                 obscureText: _obscurePassphrase,
                textInputAction: TextInputAction.done,
                // No validator needed, empty is fine
              ),
              const SizedBox(height: 30),
              ElevatedButton(
                onPressed: _isSaving ? null : _saveKey,
                 style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 15)),
                child: _isSaving ? const Text('Saving Key...') : const Text('Save Key'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}