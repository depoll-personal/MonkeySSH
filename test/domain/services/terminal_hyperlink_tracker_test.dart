import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:ghostty_vte_flutter/ghostty_vte_flutter.dart';
import 'package:monkeyssh/domain/models/cell_offset.dart';
import 'package:monkeyssh/domain/services/terminal_hyperlink_tracker.dart';

void main() {
  group('TerminalHyperlinkTracker', () {
    late GhosttyTerminalController controller;
    late TerminalHyperlinkTracker tracker;

    setUp(() {
      controller = GhosttyTerminalController(maxLines: 200);
      tracker = TerminalHyperlinkTracker()..attach(controller);
    });

    tearDown(() {
      controller.dispose();
    });

    void feed(String data) {
      final bytes = utf8.encode(data);
      controller.appendOutputBytes(bytes);
      tracker.observeBytes(bytes);
    }

    test('resolves OSC 8 links whose visible label is not a URL', () {
      feed(
        [
          '\u001b]8;;https://github.com/orgs/community/discussions/1\u0007',
          'Community CLI docs',
          '\u001b]8;;\u0007',
        ].join(),
      );

      expect(
        tracker.resolveLinkAt(const CellOffset(2, 0)),
        'https://github.com/orgs/community/discussions/1',
      );
      expect(tracker.resolveLinkAt(const CellOffset(40, 0)), isNull);
    });

    test('reassembles OSC 8 destinations containing semicolons', () {
      feed(
        [
          '\u001b]8;;https://example.com/docs;topic=tmux\u0007',
          'tmux docs',
          '\u001b]8;;\u0007',
        ].join(),
      );

      expect(
        tracker.resolveLinkAt(const CellOffset(1, 0)),
        'https://example.com/docs;topic=tmux',
      );
    });

    test('keeps hyperlink anchors valid after terminal reflow', () {
      feed(
        [
          '\u001b]8;;https://example.com/reflow\u0007',
          'abcdefghijkl',
          '\u001b]8;;\u0007',
        ].join(),
      );
      controller.resize(cols: 6, rows: controller.rows);

      String? resolved;
      for (
        var y = 0;
        y < controller.snapshot.lines.length && resolved == null;
        y++
      ) {
        for (var x = 0; x < 6 && resolved == null; x++) {
          resolved = tracker.resolveLinkAt(CellOffset(x, y));
        }
      }
      expect(resolved, 'https://example.com/reflow');
    });

    test('tracks distinct spans across many lines of output', () {
      feed(
        [
          '\u001b]8;;https://example.com/one\u0007',
          'one',
          '\u001b]8;;\u0007\r\n',
          for (var i = 0; i < 20; i++) 'filler-$i\r\n',
          '\u001b]8;;https://example.com/two\u0007',
          'two',
          '\u001b]8;;\u0007',
        ].join(),
      );

      expect(tracker.trackedHyperlinkCount, 2);
    });

    test(r'accepts ESC \ (ST) terminators interchangeably with BEL', () {
      feed(
        '\u001b]8;;https://example.com/st\u001b\\'
        'label'
        '\u001b]8;;\u001b\\',
      );
      expect(
        tracker.resolveLinkAt(const CellOffset(2, 0)),
        'https://example.com/st',
      );
    });

    test('returns null when no controller is attached', () {
      final detached = TerminalHyperlinkTracker();
      expect(detached.resolveLinkAt(const CellOffset(0, 0)), isNull);
    });

    test('handlePrivateOsc is a no-op that does not throw', () {
      tracker.handlePrivateOsc('8', <String>['', 'https://example.com']);
      expect(tracker.trackedHyperlinkCount, 0);
    });

    test('reset clears spans and optionally detaches the controller', () {
      feed('\u001b]8;;https://example.com/a\u0007a\u001b]8;;\u0007');
      expect(tracker.trackedHyperlinkCount, 1);
      tracker.reset();
      expect(tracker.trackedHyperlinkCount, 0);

      feed('\u001b]8;;https://example.com/b\u0007b\u001b]8;;\u0007');
      expect(tracker.trackedHyperlinkCount, 1);
      tracker.reset(keepControllerReference: false);
      expect(tracker.resolveLinkAt(const CellOffset(0, 0)), isNull);
    });
  });
}
