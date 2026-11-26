// This is a generated file - do not edit.
//
// Generated from misc/v1/misc.proto.

// @dart = 3.3

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names
// ignore_for_file: curly_braces_in_flow_control_structures
// ignore_for_file: deprecated_member_use_from_same_package, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_relative_imports

import 'dart:core' as $core;

import 'package:protobuf/protobuf.dart' as $pb;

class OPReturnSort extends $pb.ProtobufEnum {
  static const OPReturnSort OP_RETURN_SORT_UNSPECIFIED =
      OPReturnSort._(0, _omitEnumNames ? '' : 'OP_RETURN_SORT_UNSPECIFIED');
  static const OPReturnSort OP_RETURN_SORT_TIME = OPReturnSort._(1, _omitEnumNames ? '' : 'OP_RETURN_SORT_TIME');
  static const OPReturnSort OP_RETURN_SORT_HEIGHT = OPReturnSort._(2, _omitEnumNames ? '' : 'OP_RETURN_SORT_HEIGHT');
  static const OPReturnSort OP_RETURN_SORT_FEE = OPReturnSort._(3, _omitEnumNames ? '' : 'OP_RETURN_SORT_FEE');
  static const OPReturnSort OP_RETURN_SORT_TXID = OPReturnSort._(4, _omitEnumNames ? '' : 'OP_RETURN_SORT_TXID');
  static const OPReturnSort OP_RETURN_SORT_MESSAGE = OPReturnSort._(5, _omitEnumNames ? '' : 'OP_RETURN_SORT_MESSAGE');

  static const $core.List<OPReturnSort> values = <OPReturnSort>[
    OP_RETURN_SORT_UNSPECIFIED,
    OP_RETURN_SORT_TIME,
    OP_RETURN_SORT_HEIGHT,
    OP_RETURN_SORT_FEE,
    OP_RETURN_SORT_TXID,
    OP_RETURN_SORT_MESSAGE,
  ];

  static final $core.List<OPReturnSort?> _byValue = $pb.ProtobufEnum.$_initByValueList(values, 5);
  static OPReturnSort? valueOf($core.int value) => value < 0 || value >= _byValue.length ? null : _byValue[value];

  const OPReturnSort._(super.value, super.name);
}

/// What the user is about to put on chain.
class NewsAction extends $pb.ProtobufEnum {
  static const NewsAction NEWS_ACTION_UNSPECIFIED = NewsAction._(0, _omitEnumNames ? '' : 'NEWS_ACTION_UNSPECIFIED');
  static const NewsAction NEWS_ACTION_COMMENT = NewsAction._(2, _omitEnumNames ? '' : 'NEWS_ACTION_COMMENT');
  static const NewsAction NEWS_ACTION_STORY = NewsAction._(3, _omitEnumNames ? '' : 'NEWS_ACTION_STORY');
  static const NewsAction NEWS_ACTION_TOPIC = NewsAction._(4, _omitEnumNames ? '' : 'NEWS_ACTION_TOPIC');

  static const $core.List<NewsAction> values = <NewsAction>[
    NEWS_ACTION_UNSPECIFIED,
    NEWS_ACTION_COMMENT,
    NEWS_ACTION_STORY,
    NEWS_ACTION_TOPIC,
  ];

  static final $core.List<NewsAction?> _byValue = $pb.ProtobufEnum.$_initByValueList(values, 4);
  static NewsAction? valueOf($core.int value) => value < 0 || value >= _byValue.length ? null : _byValue[value];

  const NewsAction._(super.value, super.name);
}

const $core.bool _omitEnumNames = $core.bool.fromEnvironment('protobuf.omit_enum_names');
