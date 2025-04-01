# Server Manager App

A cross-platform mobile and desktop application for managing remote servers through SSH connections, built with Flutter.

![Flutter Version](https://img.shields.io/badge/Flutter-3.0+-blue.svg)
![License](https://img.shields.io/badge/License-MIT-green.svg)

## Features

- **Server Management**
  - Store and organize multiple server connections
  - Support for various server types (CloudPanel, cPanel, and generic servers)
  - View server details and status at a glance

- **Secure Authentication**
  - Password-based authentication
  - SSH key-based authentication with secure key storage
  - Key management system for reusing keys across multiple servers

- **Terminal Interaction**
  - Interactive terminal emulation for direct command execution
  - Execute common commands with quick access buttons
  - View command output in real-time

- **Server Actions**
  - Start, stop, and restart common services (nginx, MySQL, PHP-FPM, Redis)
  - View service status with detailed feedback
  - Perform server-specific operations

- **CloudPanel Integration**
  - Manage CloudPanel databases directly
  - Add and remove databases with ease
  - View detailed database information

## Screenshots

*Screenshots will be added here*

## Installation

### Prerequisites
- Flutter SDK 3.0 or higher
- Dart SDK 3.0 or higher

### Steps

1. Clone the repository:
   ```
   git clone https://github.com/RaiAnsar/server_manager_app.git
   ```

2. Navigate to the project directory:
   ```
   cd server_manager_app
   ```

3. Install dependencies:
   ```
   flutter pub get
   ```

4. Run the app:
   ```
   flutter run
   ```

## Usage

1. **Adding a Server**
   - Tap the "+" button on the server list screen
   - Enter server details (name, host, port, username)
   - Choose authentication method (password or SSH key)
   - Save to add the server to your list

2. **Connecting to a Server**
   - Tap on a server from the list
   - Press the "Connect" button on the server details screen
   - Once connected, the terminal and action tabs will become available

3. **Managing SSH Keys**
   - Navigate to the "Manage SSH Keys" section from the drawer menu
   - Add, edit, or delete SSH keys
   - Keys are securely stored on your device

4. **Using the Terminal**
   - Enter commands directly in the command input field
   - Use quick-access buttons for common commands
   - View real-time output in the terminal display

5. **Controlling Services**
   - Navigate to the "Actions" tab
   - Use the service control buttons to start, stop, restart, or check status
   - Feedback is displayed for each action

## Security

- Passwords and private keys are stored using secure storage mechanisms
- No sensitive data is transmitted to external services
- All connections use standard SSH security protocols

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## License

This project is licensed under the MIT License - see the LICENSE file for details.

## Acknowledgements

- [dartssh2](https://pub.dev/packages/dartssh2) for SSH functionality
- [xterm.dart](https://pub.dev/packages/xterm) for terminal emulation
- [flutter_secure_storage](https://pub.dev/packages/flutter_secure_storage) for secure credential storage