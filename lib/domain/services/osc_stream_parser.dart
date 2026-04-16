import 'dart:convert';
import 'dart:typed_data';

/// Callback signature for a parsed OSC sequence.
///
/// [code] is the numeric OSC code as a string (e.g. `'7'`, `'52'`, `'133'`).
/// [args] is the remaining semicolon-separated argument list, where the first
/// element (before the code) has been removed.
typedef OscCallback = void Function(String code, List<String> args);

/// Streaming parser that extracts OSC (Operating System Command) sequences
/// from a raw terminal byte stream before forwarding the remaining bytes to
/// the VT engine.
///
/// Ghostty's terminal controller only surfaces a subset of OSC information
/// (notably the window title). Features such as OSC 7 (working directory),
/// OSC 8 (hyperlinks), OSC 52 (clipboard), and OSC 133 (shell integration)
/// need to be intercepted from the byte stream directly. This parser scans
/// for `ESC ] ... BEL` and `ESC ] ... ESC \` (ST) terminator sequences and
/// invokes [onOsc] with the decoded code + args.
///
/// OSC bytes are still forwarded to the VT engine via [onBytes] so that
/// Ghostty can process title updates and any sequences it recognizes.
class OscStreamParser {
  /// Creates a new [OscStreamParser].
  OscStreamParser({required this.onBytes, required this.onOsc});

  /// Invoked for every byte consumed from the stream, including OSC bytes.
  final void Function(List<int> bytes) onBytes;

  /// Invoked when a complete OSC sequence has been decoded.
  final OscCallback onOsc;

  static const int _esc = 0x1B;
  static const int _bel = 0x07;
  static const int _oscIntroducer = 0x5D; // ']'
  static const int _st2 = 0x5C; // '\'
  static const int _maxOscLength = 64 * 1024;

  _OscState _state = _OscState.text;
  final BytesBuilder _oscBuffer = BytesBuilder(copy: false);

  /// Feeds a chunk of raw bytes into the parser.
  void feed(List<int> bytes) {
    if (bytes.isEmpty) {
      return;
    }
    onBytes(bytes);

    for (var i = 0; i < bytes.length; i++) {
      final b = bytes[i];
      switch (_state) {
        case _OscState.text:
          if (b == _esc) {
            _state = _OscState.escape;
          }
        case _OscState.escape:
          if (b == _oscIntroducer) {
            _oscBuffer.clear();
            _state = _OscState.oscBody;
          } else if (b == _esc) {
            // Stay in escape.
          } else {
            _state = _OscState.text;
          }
        case _OscState.oscBody:
          if (b == _bel) {
            _dispatchOsc();
            _state = _OscState.text;
          } else if (b == _esc) {
            _state = _OscState.oscStPending;
          } else {
            if (_oscBuffer.length < _maxOscLength) {
              _oscBuffer.addByte(b);
            }
          }
        case _OscState.oscStPending:
          if (b == _st2) {
            _dispatchOsc();
            _state = _OscState.text;
          } else if (b == _bel) {
            _dispatchOsc();
            _state = _OscState.text;
          } else if (b == _esc) {
            // Stay pending.
          } else {
            // False alarm — append ESC and the new byte, return to body.
            if (_oscBuffer.length < _maxOscLength) {
              _oscBuffer.addByte(_esc);
            }
            if (_oscBuffer.length < _maxOscLength) {
              _oscBuffer.addByte(b);
            }
            _state = _OscState.oscBody;
          }
      }
    }
  }

  void _dispatchOsc() {
    final buffer = _oscBuffer.takeBytes();
    if (buffer.isEmpty) {
      return;
    }
    final text = _safeDecodeOsc(buffer);
    final parts = text.split(';');
    if (parts.isEmpty) {
      return;
    }
    final code = parts.first;
    final args = parts.sublist(1);
    onOsc(code, args);
  }

  String _safeDecodeOsc(Uint8List bytes) {
    try {
      return utf8.decode(bytes, allowMalformed: true);
    } on FormatException {
      return String.fromCharCodes(bytes);
    }
  }
}

enum _OscState { text, escape, oscBody, oscStPending }
