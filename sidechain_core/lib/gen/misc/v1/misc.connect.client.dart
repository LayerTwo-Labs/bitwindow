//
//  Generated code. Do not modify.
//  source: misc/v1/misc.proto
//

import "package:connectrpc/connect.dart" as connect;

import "misc.pb.dart" as miscv1misc;
import "misc.connect.spec.dart" as specs;

import "package:protobuf/well_known_types/google/protobuf/empty.pb.dart" as googleprotobufempty;

extension type MiscServiceClient(connect.Transport _transport) {
  /// Lists the newest 1000 OP_RETURNs that match the request, in the requested order.
  Future<miscv1misc.ListOPReturnResponse> listOPReturn(
    miscv1misc.ListOPReturnRequest input, {
    connect.Headers? headers,
    connect.AbortSignal? signal,
    Function(connect.Headers)? onHeader,
    Function(connect.Headers)? onTrailer,
  }) {
    return connect.Client(_transport).unary(
      specs.MiscService.listOPReturn,
      input,
      signal: signal,
      headers: headers,
      onHeader: onHeader,
      onTrailer: onTrailer,
    );
  }

  Future<miscv1misc.BroadcastNewsResponse> broadcastNews(
    miscv1misc.BroadcastNewsRequest input, {
    connect.Headers? headers,
    connect.AbortSignal? signal,
    Function(connect.Headers)? onHeader,
    Function(connect.Headers)? onTrailer,
  }) {
    return connect.Client(_transport).unary(
      specs.MiscService.broadcastNews,
      input,
      signal: signal,
      headers: headers,
      onHeader: onHeader,
      onTrailer: onTrailer,
    );
  }

  /// Broadcasts a topic creation and subscribes to the topic.
  Future<miscv1misc.CreateTopicResponse> createTopic(
    miscv1misc.CreateTopicRequest input, {
    connect.Headers? headers,
    connect.AbortSignal? signal,
    Function(connect.Headers)? onHeader,
    Function(connect.Headers)? onTrailer,
  }) {
    return connect.Client(_transport).unary(
      specs.MiscService.createTopic,
      input,
      signal: signal,
      headers: headers,
      onHeader: onHeader,
      onTrailer: onTrailer,
    );
  }

  /// Lists the topics that the user subscribes to.
  Future<miscv1misc.ListTopicsResponse> listTopics(
    googleprotobufempty.Empty input, {
    connect.Headers? headers,
    connect.AbortSignal? signal,
    Function(connect.Headers)? onHeader,
    Function(connect.Headers)? onTrailer,
  }) {
    return connect.Client(_transport).unary(
      specs.MiscService.listTopics,
      input,
      signal: signal,
      headers: headers,
      onHeader: onHeader,
      onTrailer: onTrailer,
    );
  }

  /// Lists each topic in a block or in the mempool, subscribed or not.
  Future<miscv1misc.ListTopicsResponse> listChainTopics(
    googleprotobufempty.Empty input, {
    connect.Headers? headers,
    connect.AbortSignal? signal,
    Function(connect.Headers)? onHeader,
    Function(connect.Headers)? onTrailer,
  }) {
    return connect.Client(_transport).unary(
      specs.MiscService.listChainTopics,
      input,
      signal: signal,
      headers: headers,
      onHeader: onHeader,
      onTrailer: onTrailer,
    );
  }

  /// Subscribes to a topic in a block or in the mempool, or leaves a topic.
  Future<googleprotobufempty.Empty> setTopicSubscribed(
    miscv1misc.SetTopicSubscribedRequest input, {
    connect.Headers? headers,
    connect.AbortSignal? signal,
    Function(connect.Headers)? onHeader,
    Function(connect.Headers)? onTrailer,
  }) {
    return connect.Client(_transport).unary(
      specs.MiscService.setTopicSubscribed,
      input,
      signal: signal,
      headers: headers,
      onHeader: onHeader,
      onTrailer: onTrailer,
    );
  }

  Future<miscv1misc.ListCoinNewsResponse> listCoinNews(
    miscv1misc.ListCoinNewsRequest input, {
    connect.Headers? headers,
    connect.AbortSignal? signal,
    Function(connect.Headers)? onHeader,
    Function(connect.Headers)? onTrailer,
  }) {
    return connect.Client(_transport).unary(
      specs.MiscService.listCoinNews,
      input,
      signal: signal,
      headers: headers,
      onHeader: onHeader,
      onTrailer: onTrailer,
    );
  }

  /// Broadcasts a signed Comment (CoinNews Comment, 0x03) on an Item.
  Future<miscv1misc.CommentNewsResponse> commentNews(
    miscv1misc.CommentNewsRequest input, {
    connect.Headers? headers,
    connect.AbortSignal? signal,
    Function(connect.Headers)? onHeader,
    Function(connect.Headers)? onTrailer,
  }) {
    return connect.Client(_transport).unary(
      specs.MiscService.commentNews,
      input,
      signal: signal,
      headers: headers,
      onHeader: onHeader,
      onTrailer: onTrailer,
    );
  }

  /// Returns the full reply thread rooted at an Item, highest fee first.
  Future<miscv1misc.ListCommentsResponse> listComments(
    miscv1misc.ListCommentsRequest input, {
    connect.Headers? headers,
    connect.AbortSignal? signal,
    Function(connect.Headers)? onHeader,
    Function(connect.Headers)? onTrailer,
  }) {
    return connect.Client(_transport).unary(
      specs.MiscService.listComments,
      input,
      signal: signal,
      headers: headers,
      onHeader: onHeader,
      onTrailer: onTrailer,
    );
  }

  /// The fee that the active wallet pays for a story, a comment or a topic with no fee
  /// choice. Broadcasts nothing.
  Future<miscv1misc.EstimateNewsFeeResponse> estimateNewsFee(
    miscv1misc.EstimateNewsFeeRequest input, {
    connect.Headers? headers,
    connect.AbortSignal? signal,
    Function(connect.Headers)? onHeader,
    Function(connect.Headers)? onTrailer,
  }) {
    return connect.Client(_transport).unary(
      specs.MiscService.estimateNewsFee,
      input,
      signal: signal,
      headers: headers,
      onHeader: onHeader,
      onTrailer: onTrailer,
    );
  }

  /// File timestamping
  Future<miscv1misc.TimestampFileResponse> timestampFile(
    miscv1misc.TimestampFileRequest input, {
    connect.Headers? headers,
    connect.AbortSignal? signal,
    Function(connect.Headers)? onHeader,
    Function(connect.Headers)? onTrailer,
  }) {
    return connect.Client(_transport).unary(
      specs.MiscService.timestampFile,
      input,
      signal: signal,
      headers: headers,
      onHeader: onHeader,
      onTrailer: onTrailer,
    );
  }

  Future<miscv1misc.ListTimestampsResponse> listTimestamps(
    googleprotobufempty.Empty input, {
    connect.Headers? headers,
    connect.AbortSignal? signal,
    Function(connect.Headers)? onHeader,
    Function(connect.Headers)? onTrailer,
  }) {
    return connect.Client(_transport).unary(
      specs.MiscService.listTimestamps,
      input,
      signal: signal,
      headers: headers,
      onHeader: onHeader,
      onTrailer: onTrailer,
    );
  }

  Future<miscv1misc.VerifyTimestampResponse> verifyTimestamp(
    miscv1misc.VerifyTimestampRequest input, {
    connect.Headers? headers,
    connect.AbortSignal? signal,
    Function(connect.Headers)? onHeader,
    Function(connect.Headers)? onTrailer,
  }) {
    return connect.Client(_transport).unary(
      specs.MiscService.verifyTimestamp,
      input,
      signal: signal,
      headers: headers,
      onHeader: onHeader,
      onTrailer: onTrailer,
    );
  }
}
