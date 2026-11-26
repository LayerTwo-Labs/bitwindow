import 'dart:convert';

import 'package:bitwindow/widgets/news_cost.dart';
import 'package:flutter/widgets.dart';
import 'package:get_it/get_it.dart';
import 'package:sail_ui/sail_ui.dart';

/// A news topic in the export form {days}{identifier}Name.
class TopicLine {
  final int retentionDays;
  final String topic;
  final String name;

  const TopicLine({required this.retentionDays, required this.topic, required this.name});

  static final _format = RegExp(r'^(\d+)\{([a-fA-F0-9]{8})\}(.+)$');

  /// Reads [line]. Throws a [FormatException] with the reason for the user.
  static TopicLine parse(String line) {
    final match = _format.firstMatch(line.trim());
    final days = int.tryParse(match?.group(1) ?? '');
    if (match == null || days == null) {
      throw const FormatException('Invalid URL format. Expected: {days}{identifier}Name');
    }
    final topic = TopicLine(retentionDays: days, topic: match.group(2)!.toLowerCase(), name: match.group(3)!.trim());
    if (topicError(topic: topic.topic, name: topic.name, retentionDays: days) case final error?) {
      throw FormatException(error);
    }
    return topic;
  }

  /// The line, or null when [line] is not a valid topic.
  static TopicLine? tryParse(String line) {
    try {
      return parse(line);
    } on FormatException {
      return null;
    }
  }

  String get days => retentionDays == 0 ? 'kept forever' : '$retentionDays days';
}

/// Why a new topic is not valid, or null when it is.
String? topicError({required String topic, required String name, required int? retentionDays}) {
  if (topic.length != 8) {
    return 'Identifier must be exactly 8 hex characters';
  }
  if (!RegExp(r'^[0-9A-Fa-f]+$').hasMatch(topic)) {
    return 'Identifier must contain only valid hex characters (0-9, A-F)';
  }
  if (name.trim().isEmpty) {
    return 'Enter a name';
  }
  if (name.characters.length > 20 || utf8.encode(name).length > 64) {
    return 'Name must be 20 characters or less';
  }
  if (retentionDays == null || retentionDays < 0 || retentionDays > 255) {
    return 'Retention days must be between 0 and 255 (0 = infinite)';
  }
  return null;
}

/// A topic that is not on the chain, with the fee to create it.
typedef NewTopic = ({TopicLine line, NewsFeeEstimate? estimate, String? error});

/// Prices each topic in [lines].
Future<List<NewTopic>> priceNewTopics(List<TopicLine> lines) => Future.wait([
  for (final line in lines)
    estimateTopicFee(line).then(
      (estimate) => (line: line, estimate: estimate, error: null),
      onError: (Object e) => (line: line, estimate: null, error: feeErrorText(e)),
    ),
]);

/// The fee that the wallet pays to create [line] on the chain.
Future<NewsFeeEstimate> estimateTopicFee(TopicLine line) => GetIt.I.get<BitwindowRPC>().misc.estimateNewsFee(
  NewsAction.NEWS_ACTION_TOPIC,
  topicName: line.name,
  retentionDays: line.retentionDays,
);

/// Lists [topics] with the fee of each, and asks before the app creates them.
/// [listed] is the number of other topics that are already in Your Topics.
Future<bool> confirmNewTopics(BuildContext context, List<NewTopic> topics, {required int listed}) async {
  final count = topics.length == 1 ? '1 topic' : '${topics.length} topics';
  final fees = [for (final topic in topics) topic.estimate?.feeSats];
  final total = fees.contains(null)
      ? 'Network fee: unknown.'
      : 'Network fee: ≈ ${fees.fold(0, (sum, fee) => sum + fee!)} sats.';
  var confirmed = false;

  await showThemedDialog(
    context: context,
    builder: (context) => SailDialog(
      title: 'Create $count?',
      subtitle: 'These topics are not on the chain. Each one costs a fee.',
      maxWidth: 520,
      actions: [
        SailButton(label: 'Cancel', variant: ButtonVariant.ghost, onPressed: () async => Navigator.of(context).pop()),
        SailButton(
          label: 'Create $count',
          onPressed: () async {
            confirmed = true;
            Navigator.of(context).pop();
          },
        ),
      ],
      child: SailColumn(
        spacing: SailStyleValues.padding12,
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final topic in topics)
            if (topic.estimate case final estimate?)
              SailText.primary13(
                '${topic.line.name} (${topic.line.topic}), ${topic.line.days}  ·  ≈ ${estimate.feeSats} sats',
              )
            else
              SailText.primary13(
                '${topic.line.name} (${topic.line.topic}): ${topic.error}',
                color: context.sailTheme.colors.error,
              ),
          SailText.secondary12(
            [
              total,
              if (listed == 1) '1 topic is already in Your Topics.',
              if (listed > 1) '$listed topics are already in Your Topics.',
            ].join(' '),
          ),
        ],
      ),
    ),
  );

  return confirmed;
}
