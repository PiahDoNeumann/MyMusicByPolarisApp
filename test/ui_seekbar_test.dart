import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:polaris/ui/playback/seekbar.dart';

void main() {
  testWidgets('Seek bar accepts a slightly negative position', (WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: SeekBar(duration: Duration(minutes: 3), position: Duration(milliseconds: -9)),
      ),
    ));
    expect(tester.takeException(), isNull);
  });
}
