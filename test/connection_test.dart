import 'package:flutter_test/flutter_test.dart';
import 'package:polaris/core/connection.dart' as connection;
import 'package:shared_preferences/shared_preferences.dart';

import 'mock/http_client.dart' as mock;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('Server address without a scheme defaults to https', () async {
    final manager = connection.Manager(httpClient: mock.HttpClient());
    await pumpEventQueue(); // Let the constructor finish reading saved preferences.
    await manager.connect(mock.goodHost);
    expect(manager.url, 'https://${mock.goodHost}');
  });

  test('Server address keeps an explicit http scheme', () async {
    final manager = connection.Manager(httpClient: mock.HttpClient());
    await pumpEventQueue(); // Let the constructor finish reading saved preferences.
    await manager.connect(mock.goodHostURI);
    expect(manager.url, mock.goodHostURI);
  });
}
