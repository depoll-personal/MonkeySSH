# MonkeySSH

> ⚠️ **EXPERIMENTAL PROJECT** ⚠️
> 
> This is a learning/experimental project. **Not intended for production use.**
> May contain security vulnerabilities. Use at your own risk.

A cross-platform SSH client built with Flutter, inspired by [Termius](https://termius.com/).

[![CI](https://github.com/depoll/monkeyssh/actions/workflows/ci.yml/badge.svg)](https://github.com/depoll/monkeyssh/actions/workflows/ci.yml)
[![codecov](https://codecov.io/gh/depoll/monkeyssh/branch/main/graph/badge.svg)](https://codecov.io/gh/depoll/monkeyssh)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

## Features

- 🔐 **SSH2 Protocol** - Password & key-based authentication, jump hosts
- 💻 **Terminal Emulator** - xterm-256color with customizable themes
- ⌨️ **Rich Keyboard** - Modifier keys, function keys, macros, gestures
- 📁 **SFTP** - Browse, upload, download, edit remote files
- 🔑 **Key Management** - Generate, import, export Ed25519/RSA keys
- 🔄 **Offline Device Transfer** - Encrypted `.monkeysshx` packages for host/key/device migration
- 📂 **Organization** - Groups, folders, tags, favorites, search
- 🚇 **Port Forwarding** - Local & remote tunnels
- 📝 **Snippets** - Save and execute common commands
- ✨ **On-Device AI Assist** - Prefer built-in Apple/Android on-device models when available, with local model-file fallback
- 🔒 **Security** - Biometric/PIN lock, encrypted local storage
- 🎨 **Themes** - Dark/light mode, customizable colors

## Platforms

| Platform | Status |
|----------|--------|
| Android  | 🚧 In Development |
| iOS      | 🚧 In Development |
| macOS    | 🚧 In Development |
| Windows  | 🚧 In Development |
| Linux    | 🚧 In Development |

## Getting Started

### Prerequisites

- [Flutter](https://flutter.dev/docs/get-started/install) 3.x or later
- For iOS/macOS: Xcode 15+
- For Android: Android Studio with SDK 21+
- For Windows: Visual Studio 2022 with C++ workload
- For Linux: CMake, GTK3, pkg-config

### Installation

```bash
# Clone the repository
git clone https://github.com/depoll/monkeyssh.git
cd monkeyssh

# Install dependencies
flutter pub get

# Run the app
flutter run
```

### Experimental on-device AI setup

MonkeySSH can optionally use an on-device model inside the terminal screen to suggest commands and complete the current line.

- Open `Settings` → `On-device AI`
- Enable the assistant
- Leave `Prefer built-in system model` enabled to use:
  - Apple `FoundationModels` on supported Apple Intelligence devices
- Optionally configure a fallback local model file
  - Use `.task` on iOS/Android
  - Use `.litertlm` on macOS/Windows/Linux
- Pick the matching fallback model family (for example `Gemma IT`, `FunctionGemma`, `Qwen`, or `DeepSeek`)

The assistant runs locally and only inserts commands after an explicit review step. If the built-in system model is unavailable on a device, MonkeySSH falls back to the configured local model file.

Android still uses the fallback local model path today. Google's current built-in prompt SDK requires a higher Android `minSdk` than MonkeySSH currently targets, so the app reports that limitation instead of silently raising platform support.

### Building

```bash
# Android
flutter build apk
flutter build appbundle

# iOS
flutter build ios

# macOS
flutter build macos

# Windows
flutter build windows

# Linux
flutter build linux
```

## Development

### Running Tests

```bash
# Unit and widget tests
flutter test

# With coverage
flutter test --coverage

# Integration tests
flutter test integration_test
```

### Code Quality

```bash
# Analyze code
flutter analyze

# Format code
dart format .

# Check formatting
dart format --set-exit-if-changed .
```

## Architecture

```
lib/
├── app/                    # App configuration, themes, routing
├── core/                   # Core utilities, extensions, constants
├── data/                   # Data layer (database, repositories)
│   ├── database/          # Drift database schemas
│   ├── models/            # Data models
│   └── repositories/      # Repository implementations
├── domain/                 # Business logic
│   ├── entities/          # Domain entities
│   └── services/          # Domain services
├── presentation/           # UI layer
│   ├── screens/           # Screen widgets
│   ├── widgets/           # Reusable widgets
│   └── providers/         # Riverpod providers
└── main.dart              # Entry point
```

## Tech Stack

| Layer | Technology |
|-------|------------|
| Framework | Flutter 3.x |
| State Management | Riverpod |
| Navigation | GoRouter |
| Database | Drift (SQLite) |
| SSH | dartssh2 |
| Terminal | xterm |
| Secure Storage | flutter_secure_storage |

## Deployment

See [docs/deployment.md](docs/deployment.md) for setting up automated deployment to TestFlight and Google Play.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines.

## Security

This is an **experimental project** and has not undergone a security audit. 
Do not use for production workloads or to connect to sensitive systems.

Recent hardening changes:
- PIN verification uses PBKDF2-HMAC-SHA256 (120k iterations, per-device salt) in secure storage. Legacy PIN hashes are not migrated; users on unsupported pre-release data must re-create their PIN.
- The SQLite database is stored in the platform Application Support directory, with automatic migration from legacy Documents storage.
- Platform backup/file exposure is restricted:
  - Android disables app backup and excludes app data from backup/device-transfer rules.
  - iOS disables `UIFileSharingEnabled` and `LSSupportsOpeningDocumentsInPlace`.
- CI/CD workflows pin third-party GitHub Actions by commit SHA, scope `GITHUB_TOKEN` permissions to the minimum needed, and avoid inherited reusable-workflow secrets.
- CI now runs OSS Gitleaks secret scanning, a pull-request dependency diff review backed by OSV when GitHub dependency review is unavailable, and baseline OSV dependency scanning, while release uploads publish `SHA256SUMS.txt` alongside release artifacts.

Transfer packages are encrypted with a user-provided passphrase and are intended for direct device-to-device transfer through encrypted file import. No cloud sync is required.

If you discover a security vulnerability, please open an issue.

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Acknowledgments

- [Termius](https://termius.com/) - Inspiration for features and UX
- [dartssh2](https://pub.dev/packages/dartssh2) - SSH2 client implementation
- [xterm](https://pub.dev/packages/xterm) - Terminal emulator widget
