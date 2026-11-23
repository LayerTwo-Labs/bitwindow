import 'package:bitwindow/providers/news_provider.dart';
import 'package:bitwindow/widgets/coinnews.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:protobuf/well_known_types/google/protobuf/timestamp.pb.dart';
import 'package:sail_ui/sail_ui.dart';

import 'test_utils.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

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
