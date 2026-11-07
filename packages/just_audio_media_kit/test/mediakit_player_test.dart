// Runs against a real libmpv. Point LIBMPV at libmpv-2.dll, for example the one
// copied next to the app by `flutter build windows`.
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio_media_kit/mediakit_player.dart';
import 'package:just_audio_platform_interface/just_audio_platform_interface.dart';
import 'package:media_kit/media_kit.dart';

/// Writes a mono 8 kHz WAV of silence lasting [seconds].
File _silence(Directory dir, String name, int seconds) {
  const rate = 8000;
  final dataSize = rate * 2 * seconds;
  final header = ByteData(44)
    ..setUint32(0, 0x46464952, Endian.little) // RIFF
    ..setUint32(4, 36 + dataSize, Endian.little)
    ..setUint32(8, 0x45564157, Endian.little) // WAVE
    ..setUint32(12, 0x20746d66, Endian.little) // fmt
    ..setUint32(16, 16, Endian.little)
    ..setUint16(20, 1, Endian.little)
    ..setUint16(22, 1, Endian.little)
    ..setUint32(24, rate, Endian.little)
    ..setUint32(28, rate * 2, Endian.little)
    ..setUint16(32, 2, Endian.little)
    ..setUint16(34, 16, Endian.little)
    ..setUint32(36, 0x61746164, Endian.little) // data
    ..setUint32(40, dataSize, Endian.little);
  return File('${dir.path}/$name.wav')
    ..writeAsBytesSync([...header.buffer.asUint8List(), ...Uint8List(dataSize)]);
}

ProgressiveAudioSourceMessage _source(File file) =>
    ProgressiveAudioSourceMessage(id: file.path, uri: file.uri.toString());

void main() {
  final libmpv = Platform.environment['LIBMPV'];
  late Directory dir;
  late MediaKitPlayer player;

  setUpAll(() {
    MediaKit.ensureInitialized(libmpv: libmpv);
    dir = Directory.systemTemp.createTempSync('mediakit_player_test');
  });

  tearDownAll(() => dir.deleteSync(recursive: true));

  setUp(() async {
    player = MediaKitPlayer('test');
    await player.ready();
  });

  tearDown(() => player.release());

  test('keeps reporting the duration while playing', () async {
    await player.load(LoadRequest(audioSourceMessage: _source(_silence(dir, 'a', 3))));
    final events = <PlaybackEventMessage>[];
    final subscription = player.playbackEventMessageStream.listen(events.add);
    await player.play(PlayRequest());
    await Future.delayed(const Duration(milliseconds: 1500));
    await subscription.cancel();

    final positionUpdates = events.where((e) => e.updatePosition > Duration.zero).toList();
    expect(positionUpdates, isNotEmpty);
    for (final event in positionUpdates) {
      expect(event.duration?.inSeconds, 3, reason: 'event at ${event.updatePosition}');
    }
  }, skip: libmpv == null ? 'LIBMPV not set' : false);

  test('inserts several sources at an index in order', () async {
    await player.load(LoadRequest(
      audioSourceMessage: ConcatenatingAudioSourceMessage(
        id: 'queue',
        children: [_source(_silence(dir, 'three', 3))],
        useLazyPreparation: true,
        shuffleOrder: [0],
      ),
    ));
    await player.concatenatingInsertAll(ConcatenatingInsertAllRequest(
      id: 'queue',
      index: 0,
      children: [_source(_silence(dir, 'one', 1)), _source(_silence(dir, 'two', 2))],
      shuffleOrder: [0, 1, 2],
    ));

    expect(player.playlistUris.map((uri) => uri.split('/').last), ['one.wav', 'two.wav', 'three.wav']);
  }, skip: libmpv == null ? 'LIBMPV not set' : false);

  test('stays completed after the last source ends', () async {
    await player.load(LoadRequest(audioSourceMessage: _source(_silence(dir, 'short', 1))));
    final events = <PlaybackEventMessage>[];
    final subscription = player.playbackEventMessageStream.listen(events.add);
    await player.play(PlayRequest());
    await player.playbackEventMessageStream
        .firstWhere((e) => e.processingState == ProcessingStateMessage.completed)
        .timeout(const Duration(seconds: 10));
    await Future.delayed(const Duration(seconds: 1));
    await subscription.cancel();

    expect(events.last.processingState, ProcessingStateMessage.completed);
  }, skip: libmpv == null ? 'LIBMPV not set' : false);

  test('plays a source added and seeked to after the queue completed', () async {
    await player.load(LoadRequest(
      audioSourceMessage: ConcatenatingAudioSourceMessage(
        id: 'queue',
        children: [_source(_silence(dir, 'first', 1))],
        useLazyPreparation: true,
        shuffleOrder: [0],
      ),
    ));
    await player.play(PlayRequest());
    await player.playbackEventMessageStream
        .firstWhere((e) => e.processingState == ProcessingStateMessage.completed)
        .timeout(const Duration(seconds: 10));

    await player.concatenatingInsertAll(ConcatenatingInsertAllRequest(
      id: 'queue',
      index: 1,
      children: [_source(_silence(dir, 'second', 3))],
      shuffleOrder: [0, 1],
    ));
    await player.seek(SeekRequest(index: 1, position: Duration.zero));
    await player.play(PlayRequest());

    final playing = await player.playbackEventMessageStream
        .firstWhere((e) => e.currentIndex == 1 && e.updatePosition > const Duration(milliseconds: 500))
        .timeout(const Duration(seconds: 5));
    expect(playing.duration?.inSeconds, 3);
  }, skip: libmpv == null ? 'LIBMPV not set' : false);
}
