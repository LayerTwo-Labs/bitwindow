import 'dart:async';
import 'dart:io';

import 'package:bitwindow/env.dart';
import 'package:bitwindow/providers/news_provider.dart';
import 'package:bitwindow/widgets/coinnews.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:logger/logger.dart';
import 'package:protobuf/well_known_types/google/protobuf/timestamp.pb.dart';
import 'package:sail_ui/sail_ui.dart';

import 'test_utils.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() async {
    Environment.isInTest = true;
    await GetIt.I.reset();
  });

  Future<ClientSettings> useFileStore(Directory dir) async {
    await GetIt.I.get<NewsProvider>().fetch();
    await GetIt.I.unregister<ClientSettings>();
    final settings = ClientSettings(store: FileStorage.fromDirectory(dir), log: Logger());
    GetIt.I.registerSingleton<ClientSettings>(settings);
    return settings;
  }

  Future<void> nextRead(ChangeNotifier model, {int count = 1}) {
    final read = Completer<void>();
    void onChange() {
      count--;
      if (count == 0) {
        model.removeListener(onChange);
        read.complete();
      }
    }

    model.addListener(onChange);
    return read.future.timeout(const Duration(seconds: 2));
  }

  test('the news columns save both topics to the file store', () async {
    await registerTestDependencies();
    final dir = await Directory.systemTemp.createTemp('coinnews-topics-');
    addTearDown(() => dir.delete(recursive: true));
    final settings = await useFileStore(dir);
    final model = CoinNewsLargeViewModel();
    addTearDown(model.dispose);
    await Future<void>.sync(() => model.setLeftTopic('c0ffee01'));
    await Future<void>.sync(() => model.setRightTopic('c0ffee02'));

    final config = (await settings.getValue(SelectedTopicsSetting())).value;
    expect(config.leftTopic, 'c0ffee01');
    expect(config.rightTopic, 'c0ffee02');
  });

  test('the news columns restore both topics from a new file store', () async {
    await registerTestDependencies();
    final dir = await Directory.systemTemp.createTemp('coinnews-topics-');
    addTearDown(() => dir.delete(recursive: true));
    final settings = await useFileStore(dir);
    await settings.setValue(
      SelectedTopicsSetting(
        newValue: TopicsConfigData(
          selectedTopics: ['a1a1a1a1'],
          leftTopic: 'c0ffee01',
          rightTopic: 'c0ffee02',
        ),
      ),
    );
    await useFileStore(dir);
    final model = CoinNewsLargeViewModel();
    addTearDown(model.dispose);
    await nextRead(model);

    expect(model.leftTopic, 'c0ffee01');
    expect(model.rightTopic, 'c0ffee02');
  });

  test('an empty topic selection stays empty after the model restarts', () async {
    await registerTestDependencies();
    final dir = await Directory.systemTemp.createTemp('coinnews-topics-');
    addTearDown(() => dir.delete(recursive: true));
    final settings = await useFileStore(dir);
    final provider = GetIt.I.get<NewsProvider>();
    await provider.fetch();
    provider.topics = [Topic(topic: 'a1a1a1a1', name: 'US Weekly')];
    await settings.setValue(SelectedTopicsSetting(newValue: TopicsConfigData(selectedTopics: [])));
    Environment.isInTest = false;
    final model = CoinNewsViewModel();
    addTearDown(model.dispose);
    await nextRead(model, count: 2);

    provider.topics = [...provider.topics, Topic(topic: 'c0ffee01', name: 'New topic')];
    expect(model.selectedTopicIds, isEmpty);
  });

  test("the columns and the table keep each other's saved topics", () async {
    await registerTestDependencies();
    final dir = await Directory.systemTemp.createTemp('coinnews-topics-');
    addTearDown(() => dir.delete(recursive: true));
    final settings = await useFileStore(dir);
    final columns = CoinNewsLargeViewModel();
    addTearDown(columns.dispose);
    await nextRead(columns);
    final table = CoinNewsViewModel();
    addTearDown(table.dispose);

    await Future.wait([
      columns.setLeftTopic('c0ffee01'),
      columns.setRightTopic('c0ffee02'),
      table.setSelectedTopics(['a1a1a1a1']),
    ]);

    final config = (await settings.getValue(SelectedTopicsSetting())).value;
    expect(config.leftTopic, 'c0ffee01');
    expect(config.rightTopic, 'c0ffee02');
    expect(config.selectedTopics, ['a1a1a1a1']);
  });

  test('a first read selects all topics when no selection exists', () async {
    await registerTestDependencies();
    final dir = await Directory.systemTemp.createTemp('coinnews-topics-');
    addTearDown(() => dir.delete(recursive: true));
    await useFileStore(dir);
    GetIt.I.get<NewsProvider>().topics = [Topic(topic: 'a1a1a1a1', name: 'US Weekly')];
    Environment.isInTest = false;
    final model = CoinNewsViewModel();
    addTearDown(model.dispose);
    await nextRead(model, count: 2);

    expect(model.selectedTopicIds, ['a1a1a1a1']);
  });

  test('the default selection includes topics that arrive after settings load', () async {
    await registerTestDependencies();
    final dir = await Directory.systemTemp.createTemp('coinnews-topics-');
    addTearDown(() => dir.delete(recursive: true));
    await useFileStore(dir);
    final provider = GetIt.I.get<NewsProvider>();
    provider.topics = [Topic(topic: 'a1a1a1a1', name: 'US Weekly')];
    provider.initialized = true;
    Environment.isInTest = false;
    final model = CoinNewsViewModel();
    addTearDown(model.dispose);
    await nextRead(model, count: 2);

    final topic = Topic(topic: 'c0ffee01', name: 'New topic');
    final story = CoinNews(topic: topic.topic, headline: 'First story');
    provider.topics = [...provider.topics, topic];
    provider.news = [story];

    expect(model.selectedTopicIds, ['a1a1a1a1', topic.topic]);
    expect(model.entries, [story]);
  });

  test('a search on a later page shows the matches on page one', () async {
    await registerTestDependencies();
    final provider = GetIt.I.get<NewsProvider>();
    await provider.fetch();
    provider.news = [
      for (var i = 0; i < 9; i++)
        CoinNews(
          topic: 'a1a1a1a1',
          headline: 'Story $i',
          createTime: Timestamp.fromDateTime(DateTime.utc(2026, 11, 1 + i)),
        ),
    ];
    provider.initialized = true;

    final model = CoinNewsViewModel();
    addTearDown(model.dispose);
    await model.setSelectedTopics(['a1a1a1a1']);
    model.pageSize = 3;
    model.setPage(3);
    expect(model.paginatedEntries, hasLength(3));

    model.searchController.text = 'Story 4';

    expect(model.currentPage, 1);
    expect(model.paginatedEntries.map((n) => n.headline), ['Story 4']);
  });
}
