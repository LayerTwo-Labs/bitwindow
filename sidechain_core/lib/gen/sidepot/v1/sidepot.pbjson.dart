// This is a generated file - do not edit.
//
// Generated from sidepot/v1/sidepot.proto.

// @dart = 3.3

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names
// ignore_for_file: curly_braces_in_flow_control_structures
// ignore_for_file: deprecated_member_use_from_same_package, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_relative_imports
// ignore_for_file: unused_import

import 'dart:convert' as $convert;
import 'dart:core' as $core;
import 'dart:typed_data' as $typed_data;

@$core.Deprecated('Use getBalanceRequestDescriptor instead')
const GetBalanceRequest$json = {
  '1': 'GetBalanceRequest',
};

/// Descriptor for `GetBalanceRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List getBalanceRequestDescriptor = $convert.base64Decode('ChFHZXRCYWxhbmNlUmVxdWVzdA==');

@$core.Deprecated('Use getBalanceResponseDescriptor instead')
const GetBalanceResponse$json = {
  '1': 'GetBalanceResponse',
  '2': [
    {'1': 'total_sats', '3': 1, '4': 1, '5': 3, '10': 'totalSats'},
    {'1': 'available_sats', '3': 2, '4': 1, '5': 3, '10': 'availableSats'},
  ],
};

/// Descriptor for `GetBalanceResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List getBalanceResponseDescriptor =
    $convert.base64Decode('ChJHZXRCYWxhbmNlUmVzcG9uc2USHQoKdG90YWxfc2F0cxgBIAEoA1IJdG90YWxTYXRzEiUKDm'
        'F2YWlsYWJsZV9zYXRzGAIgASgDUg1hdmFpbGFibGVTYXRz');

@$core.Deprecated('Use getBlockCountRequestDescriptor instead')
const GetBlockCountRequest$json = {
  '1': 'GetBlockCountRequest',
};

/// Descriptor for `GetBlockCountRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List getBlockCountRequestDescriptor = $convert.base64Decode('ChRHZXRCbG9ja0NvdW50UmVxdWVzdA==');

@$core.Deprecated('Use getBlockCountResponseDescriptor instead')
const GetBlockCountResponse$json = {
  '1': 'GetBlockCountResponse',
  '2': [
    {'1': 'count', '3': 1, '4': 1, '5': 3, '10': 'count'},
  ],
};

/// Descriptor for `GetBlockCountResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List getBlockCountResponseDescriptor =
    $convert.base64Decode('ChVHZXRCbG9ja0NvdW50UmVzcG9uc2USFAoFY291bnQYASABKANSBWNvdW50');

@$core.Deprecated('Use stopRequestDescriptor instead')
const StopRequest$json = {
  '1': 'StopRequest',
};

/// Descriptor for `StopRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List stopRequestDescriptor = $convert.base64Decode('CgtTdG9wUmVxdWVzdA==');

@$core.Deprecated('Use stopResponseDescriptor instead')
const StopResponse$json = {
  '1': 'StopResponse',
};

/// Descriptor for `StopResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List stopResponseDescriptor = $convert.base64Decode('CgxTdG9wUmVzcG9uc2U=');

@$core.Deprecated('Use getNewAddressRequestDescriptor instead')
const GetNewAddressRequest$json = {
  '1': 'GetNewAddressRequest',
};

/// Descriptor for `GetNewAddressRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List getNewAddressRequestDescriptor = $convert.base64Decode('ChRHZXROZXdBZGRyZXNzUmVxdWVzdA==');

@$core.Deprecated('Use getNewAddressResponseDescriptor instead')
const GetNewAddressResponse$json = {
  '1': 'GetNewAddressResponse',
  '2': [
    {'1': 'address', '3': 1, '4': 1, '5': 9, '10': 'address'},
  ],
};

/// Descriptor for `GetNewAddressResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List getNewAddressResponseDescriptor =
    $convert.base64Decode('ChVHZXROZXdBZGRyZXNzUmVzcG9uc2USGAoHYWRkcmVzcxgBIAEoCVIHYWRkcmVzcw==');

@$core.Deprecated('Use withdrawRequestDescriptor instead')
const WithdrawRequest$json = {
  '1': 'WithdrawRequest',
  '2': [
    {'1': 'address', '3': 1, '4': 1, '5': 9, '10': 'address'},
    {'1': 'amount_sats', '3': 2, '4': 1, '5': 3, '10': 'amountSats'},
    {'1': 'side_fee_sats', '3': 3, '4': 1, '5': 3, '10': 'sideFeeSats'},
    {'1': 'main_fee_sats', '3': 4, '4': 1, '5': 3, '10': 'mainFeeSats'},
  ],
};

/// Descriptor for `WithdrawRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List withdrawRequestDescriptor =
    $convert.base64Decode('Cg9XaXRoZHJhd1JlcXVlc3QSGAoHYWRkcmVzcxgBIAEoCVIHYWRkcmVzcxIfCgthbW91bnRfc2'
        'F0cxgCIAEoA1IKYW1vdW50U2F0cxIiCg1zaWRlX2ZlZV9zYXRzGAMgASgDUgtzaWRlRmVlU2F0'
        'cxIiCg1tYWluX2ZlZV9zYXRzGAQgASgDUgttYWluRmVlU2F0cw==');

@$core.Deprecated('Use withdrawResponseDescriptor instead')
const WithdrawResponse$json = {
  '1': 'WithdrawResponse',
  '2': [
    {'1': 'txid', '3': 1, '4': 1, '5': 9, '10': 'txid'},
  ],
};

/// Descriptor for `WithdrawResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List withdrawResponseDescriptor =
    $convert.base64Decode('ChBXaXRoZHJhd1Jlc3BvbnNlEhIKBHR4aWQYASABKAlSBHR4aWQ=');

@$core.Deprecated('Use transferRequestDescriptor instead')
const TransferRequest$json = {
  '1': 'TransferRequest',
  '2': [
    {'1': 'address', '3': 1, '4': 1, '5': 9, '10': 'address'},
    {'1': 'amount_sats', '3': 2, '4': 1, '5': 3, '10': 'amountSats'},
    {'1': 'fee_sats', '3': 3, '4': 1, '5': 3, '10': 'feeSats'},
  ],
};

/// Descriptor for `TransferRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List transferRequestDescriptor =
    $convert.base64Decode('Cg9UcmFuc2ZlclJlcXVlc3QSGAoHYWRkcmVzcxgBIAEoCVIHYWRkcmVzcxIfCgthbW91bnRfc2'
        'F0cxgCIAEoA1IKYW1vdW50U2F0cxIZCghmZWVfc2F0cxgDIAEoA1IHZmVlU2F0cw==');

@$core.Deprecated('Use transferResponseDescriptor instead')
const TransferResponse$json = {
  '1': 'TransferResponse',
  '2': [
    {'1': 'txid', '3': 1, '4': 1, '5': 9, '10': 'txid'},
  ],
};

/// Descriptor for `TransferResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List transferResponseDescriptor =
    $convert.base64Decode('ChBUcmFuc2ZlclJlc3BvbnNlEhIKBHR4aWQYASABKAlSBHR4aWQ=');

@$core.Deprecated('Use getSidechainWealthRequestDescriptor instead')
const GetSidechainWealthRequest$json = {
  '1': 'GetSidechainWealthRequest',
};

/// Descriptor for `GetSidechainWealthRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List getSidechainWealthRequestDescriptor =
    $convert.base64Decode('ChlHZXRTaWRlY2hhaW5XZWFsdGhSZXF1ZXN0');

@$core.Deprecated('Use getSidechainWealthResponseDescriptor instead')
const GetSidechainWealthResponse$json = {
  '1': 'GetSidechainWealthResponse',
  '2': [
    {'1': 'sats', '3': 1, '4': 1, '5': 3, '10': 'sats'},
  ],
};

/// Descriptor for `GetSidechainWealthResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List getSidechainWealthResponseDescriptor =
    $convert.base64Decode('ChpHZXRTaWRlY2hhaW5XZWFsdGhSZXNwb25zZRISCgRzYXRzGAEgASgDUgRzYXRz');

@$core.Deprecated('Use createDepositRequestDescriptor instead')
const CreateDepositRequest$json = {
  '1': 'CreateDepositRequest',
  '2': [
    {'1': 'address', '3': 1, '4': 1, '5': 9, '10': 'address'},
    {'1': 'value_sats', '3': 2, '4': 1, '5': 3, '10': 'valueSats'},
    {'1': 'fee_sats', '3': 3, '4': 1, '5': 3, '10': 'feeSats'},
  ],
};

/// Descriptor for `CreateDepositRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List createDepositRequestDescriptor =
    $convert.base64Decode('ChRDcmVhdGVEZXBvc2l0UmVxdWVzdBIYCgdhZGRyZXNzGAEgASgJUgdhZGRyZXNzEh0KCnZhbH'
        'VlX3NhdHMYAiABKANSCXZhbHVlU2F0cxIZCghmZWVfc2F0cxgDIAEoA1IHZmVlU2F0cw==');

@$core.Deprecated('Use createDepositResponseDescriptor instead')
const CreateDepositResponse$json = {
  '1': 'CreateDepositResponse',
  '2': [
    {'1': 'txid', '3': 1, '4': 1, '5': 9, '10': 'txid'},
  ],
};

/// Descriptor for `CreateDepositResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List createDepositResponseDescriptor =
    $convert.base64Decode('ChVDcmVhdGVEZXBvc2l0UmVzcG9uc2USEgoEdHhpZBgBIAEoCVIEdHhpZA==');

@$core.Deprecated('Use getPendingWithdrawalBundleRequestDescriptor instead')
const GetPendingWithdrawalBundleRequest$json = {
  '1': 'GetPendingWithdrawalBundleRequest',
};

/// Descriptor for `GetPendingWithdrawalBundleRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List getPendingWithdrawalBundleRequestDescriptor =
    $convert.base64Decode('CiFHZXRQZW5kaW5nV2l0aGRyYXdhbEJ1bmRsZVJlcXVlc3Q=');

@$core.Deprecated('Use getPendingWithdrawalBundleResponseDescriptor instead')
const GetPendingWithdrawalBundleResponse$json = {
  '1': 'GetPendingWithdrawalBundleResponse',
  '2': [
    {'1': 'bundle_json', '3': 1, '4': 1, '5': 9, '10': 'bundleJson'},
  ],
};

/// Descriptor for `GetPendingWithdrawalBundleResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List getPendingWithdrawalBundleResponseDescriptor =
    $convert.base64Decode('CiJHZXRQZW5kaW5nV2l0aGRyYXdhbEJ1bmRsZVJlc3BvbnNlEh8KC2J1bmRsZV9qc29uGAEgAS'
        'gJUgpidW5kbGVKc29u');

@$core.Deprecated('Use connectPeerRequestDescriptor instead')
const ConnectPeerRequest$json = {
  '1': 'ConnectPeerRequest',
  '2': [
    {'1': 'address', '3': 1, '4': 1, '5': 9, '10': 'address'},
  ],
};

/// Descriptor for `ConnectPeerRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List connectPeerRequestDescriptor =
    $convert.base64Decode('ChJDb25uZWN0UGVlclJlcXVlc3QSGAoHYWRkcmVzcxgBIAEoCVIHYWRkcmVzcw==');

@$core.Deprecated('Use connectPeerResponseDescriptor instead')
const ConnectPeerResponse$json = {
  '1': 'ConnectPeerResponse',
};

/// Descriptor for `ConnectPeerResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List connectPeerResponseDescriptor = $convert.base64Decode('ChNDb25uZWN0UGVlclJlc3BvbnNl');

@$core.Deprecated('Use listPeersRequestDescriptor instead')
const ListPeersRequest$json = {
  '1': 'ListPeersRequest',
};

/// Descriptor for `ListPeersRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List listPeersRequestDescriptor = $convert.base64Decode('ChBMaXN0UGVlcnNSZXF1ZXN0');

@$core.Deprecated('Use listPeersResponseDescriptor instead')
const ListPeersResponse$json = {
  '1': 'ListPeersResponse',
  '2': [
    {'1': 'peers_json', '3': 1, '4': 1, '5': 9, '10': 'peersJson'},
  ],
};

/// Descriptor for `ListPeersResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List listPeersResponseDescriptor =
    $convert.base64Decode('ChFMaXN0UGVlcnNSZXNwb25zZRIdCgpwZWVyc19qc29uGAEgASgJUglwZWVyc0pzb24=');

@$core.Deprecated('Use mineRequestDescriptor instead')
const MineRequest$json = {
  '1': 'MineRequest',
  '2': [
    {'1': 'fee_sats', '3': 1, '4': 1, '5': 3, '10': 'feeSats'},
  ],
};

/// Descriptor for `MineRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List mineRequestDescriptor =
    $convert.base64Decode('CgtNaW5lUmVxdWVzdBIZCghmZWVfc2F0cxgBIAEoA1IHZmVlU2F0cw==');

@$core.Deprecated('Use mineResponseDescriptor instead')
const MineResponse$json = {
  '1': 'MineResponse',
  '2': [
    {'1': 'bmm_result_json', '3': 1, '4': 1, '5': 9, '10': 'bmmResultJson'},
  ],
};

/// Descriptor for `MineResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List mineResponseDescriptor =
    $convert.base64Decode('CgxNaW5lUmVzcG9uc2USJgoPYm1tX3Jlc3VsdF9qc29uGAEgASgJUg1ibW1SZXN1bHRKc29u');

@$core.Deprecated('Use getBlockRequestDescriptor instead')
const GetBlockRequest$json = {
  '1': 'GetBlockRequest',
  '2': [
    {'1': 'hash', '3': 1, '4': 1, '5': 9, '10': 'hash'},
  ],
};

/// Descriptor for `GetBlockRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List getBlockRequestDescriptor =
    $convert.base64Decode('Cg9HZXRCbG9ja1JlcXVlc3QSEgoEaGFzaBgBIAEoCVIEaGFzaA==');

@$core.Deprecated('Use getBlockResponseDescriptor instead')
const GetBlockResponse$json = {
  '1': 'GetBlockResponse',
  '2': [
    {'1': 'block_json', '3': 1, '4': 1, '5': 9, '10': 'blockJson'},
  ],
};

/// Descriptor for `GetBlockResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List getBlockResponseDescriptor =
    $convert.base64Decode('ChBHZXRCbG9ja1Jlc3BvbnNlEh0KCmJsb2NrX2pzb24YASABKAlSCWJsb2NrSnNvbg==');

@$core.Deprecated('Use getBestMainchainBlockHashRequestDescriptor instead')
const GetBestMainchainBlockHashRequest$json = {
  '1': 'GetBestMainchainBlockHashRequest',
};

/// Descriptor for `GetBestMainchainBlockHashRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List getBestMainchainBlockHashRequestDescriptor =
    $convert.base64Decode('CiBHZXRCZXN0TWFpbmNoYWluQmxvY2tIYXNoUmVxdWVzdA==');

@$core.Deprecated('Use getBestMainchainBlockHashResponseDescriptor instead')
const GetBestMainchainBlockHashResponse$json = {
  '1': 'GetBestMainchainBlockHashResponse',
  '2': [
    {'1': 'hash', '3': 1, '4': 1, '5': 9, '10': 'hash'},
  ],
};

/// Descriptor for `GetBestMainchainBlockHashResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List getBestMainchainBlockHashResponseDescriptor =
    $convert.base64Decode('CiFHZXRCZXN0TWFpbmNoYWluQmxvY2tIYXNoUmVzcG9uc2USEgoEaGFzaBgBIAEoCVIEaGFzaA'
        '==');

@$core.Deprecated('Use getBestSidechainBlockHashRequestDescriptor instead')
const GetBestSidechainBlockHashRequest$json = {
  '1': 'GetBestSidechainBlockHashRequest',
};

/// Descriptor for `GetBestSidechainBlockHashRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List getBestSidechainBlockHashRequestDescriptor =
    $convert.base64Decode('CiBHZXRCZXN0U2lkZWNoYWluQmxvY2tIYXNoUmVxdWVzdA==');

@$core.Deprecated('Use getBestSidechainBlockHashResponseDescriptor instead')
const GetBestSidechainBlockHashResponse$json = {
  '1': 'GetBestSidechainBlockHashResponse',
  '2': [
    {'1': 'hash', '3': 1, '4': 1, '5': 9, '10': 'hash'},
  ],
};

/// Descriptor for `GetBestSidechainBlockHashResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List getBestSidechainBlockHashResponseDescriptor =
    $convert.base64Decode('CiFHZXRCZXN0U2lkZWNoYWluQmxvY2tIYXNoUmVzcG9uc2USEgoEaGFzaBgBIAEoCVIEaGFzaA'
        '==');

@$core.Deprecated('Use getBmmInclusionsRequestDescriptor instead')
const GetBmmInclusionsRequest$json = {
  '1': 'GetBmmInclusionsRequest',
  '2': [
    {'1': 'block_hash', '3': 1, '4': 1, '5': 9, '10': 'blockHash'},
  ],
};

/// Descriptor for `GetBmmInclusionsRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List getBmmInclusionsRequestDescriptor =
    $convert.base64Decode('ChdHZXRCbW1JbmNsdXNpb25zUmVxdWVzdBIdCgpibG9ja19oYXNoGAEgASgJUglibG9ja0hhc2'
        'g=');

@$core.Deprecated('Use getBmmInclusionsResponseDescriptor instead')
const GetBmmInclusionsResponse$json = {
  '1': 'GetBmmInclusionsResponse',
  '2': [
    {'1': 'inclusions', '3': 1, '4': 1, '5': 9, '10': 'inclusions'},
  ],
};

/// Descriptor for `GetBmmInclusionsResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List getBmmInclusionsResponseDescriptor =
    $convert.base64Decode('ChhHZXRCbW1JbmNsdXNpb25zUmVzcG9uc2USHgoKaW5jbHVzaW9ucxgBIAEoCVIKaW5jbHVzaW'
        '9ucw==');

@$core.Deprecated('Use getWalletUtxosRequestDescriptor instead')
const GetWalletUtxosRequest$json = {
  '1': 'GetWalletUtxosRequest',
};

/// Descriptor for `GetWalletUtxosRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List getWalletUtxosRequestDescriptor = $convert.base64Decode('ChVHZXRXYWxsZXRVdHhvc1JlcXVlc3Q=');

@$core.Deprecated('Use getWalletUtxosResponseDescriptor instead')
const GetWalletUtxosResponse$json = {
  '1': 'GetWalletUtxosResponse',
  '2': [
    {'1': 'utxos_json', '3': 1, '4': 1, '5': 9, '10': 'utxosJson'},
  ],
};

/// Descriptor for `GetWalletUtxosResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List getWalletUtxosResponseDescriptor =
    $convert.base64Decode('ChZHZXRXYWxsZXRVdHhvc1Jlc3BvbnNlEh0KCnV0eG9zX2pzb24YASABKAlSCXV0eG9zSnNvbg'
        '==');

@$core.Deprecated('Use listUtxosRequestDescriptor instead')
const ListUtxosRequest$json = {
  '1': 'ListUtxosRequest',
};

/// Descriptor for `ListUtxosRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List listUtxosRequestDescriptor = $convert.base64Decode('ChBMaXN0VXR4b3NSZXF1ZXN0');

@$core.Deprecated('Use listUtxosResponseDescriptor instead')
const ListUtxosResponse$json = {
  '1': 'ListUtxosResponse',
  '2': [
    {'1': 'utxos_json', '3': 1, '4': 1, '5': 9, '10': 'utxosJson'},
  ],
};

/// Descriptor for `ListUtxosResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List listUtxosResponseDescriptor =
    $convert.base64Decode('ChFMaXN0VXR4b3NSZXNwb25zZRIdCgp1dHhvc19qc29uGAEgASgJUgl1dHhvc0pzb24=');

@$core.Deprecated('Use removeFromMempoolRequestDescriptor instead')
const RemoveFromMempoolRequest$json = {
  '1': 'RemoveFromMempoolRequest',
  '2': [
    {'1': 'txid', '3': 1, '4': 1, '5': 9, '10': 'txid'},
  ],
};

/// Descriptor for `RemoveFromMempoolRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List removeFromMempoolRequestDescriptor =
    $convert.base64Decode('ChhSZW1vdmVGcm9tTWVtcG9vbFJlcXVlc3QSEgoEdHhpZBgBIAEoCVIEdHhpZA==');

@$core.Deprecated('Use removeFromMempoolResponseDescriptor instead')
const RemoveFromMempoolResponse$json = {
  '1': 'RemoveFromMempoolResponse',
};

/// Descriptor for `RemoveFromMempoolResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List removeFromMempoolResponseDescriptor =
    $convert.base64Decode('ChlSZW1vdmVGcm9tTWVtcG9vbFJlc3BvbnNl');

@$core.Deprecated('Use getLatestFailedWithdrawalBundleHeightRequestDescriptor instead')
const GetLatestFailedWithdrawalBundleHeightRequest$json = {
  '1': 'GetLatestFailedWithdrawalBundleHeightRequest',
};

/// Descriptor for `GetLatestFailedWithdrawalBundleHeightRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List getLatestFailedWithdrawalBundleHeightRequestDescriptor =
    $convert.base64Decode('CixHZXRMYXRlc3RGYWlsZWRXaXRoZHJhd2FsQnVuZGxlSGVpZ2h0UmVxdWVzdA==');

@$core.Deprecated('Use getLatestFailedWithdrawalBundleHeightResponseDescriptor instead')
const GetLatestFailedWithdrawalBundleHeightResponse$json = {
  '1': 'GetLatestFailedWithdrawalBundleHeightResponse',
  '2': [
    {'1': 'height', '3': 1, '4': 1, '5': 3, '10': 'height'},
  ],
};

/// Descriptor for `GetLatestFailedWithdrawalBundleHeightResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List getLatestFailedWithdrawalBundleHeightResponseDescriptor =
    $convert.base64Decode('Ci1HZXRMYXRlc3RGYWlsZWRXaXRoZHJhd2FsQnVuZGxlSGVpZ2h0UmVzcG9uc2USFgoGaGVpZ2'
        'h0GAEgASgDUgZoZWlnaHQ=');

@$core.Deprecated('Use generateMnemonicRequestDescriptor instead')
const GenerateMnemonicRequest$json = {
  '1': 'GenerateMnemonicRequest',
};

/// Descriptor for `GenerateMnemonicRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List generateMnemonicRequestDescriptor =
    $convert.base64Decode('ChdHZW5lcmF0ZU1uZW1vbmljUmVxdWVzdA==');

@$core.Deprecated('Use generateMnemonicResponseDescriptor instead')
const GenerateMnemonicResponse$json = {
  '1': 'GenerateMnemonicResponse',
  '2': [
    {'1': 'mnemonic', '3': 1, '4': 1, '5': 9, '10': 'mnemonic'},
  ],
};

/// Descriptor for `GenerateMnemonicResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List generateMnemonicResponseDescriptor =
    $convert.base64Decode('ChhHZW5lcmF0ZU1uZW1vbmljUmVzcG9uc2USGgoIbW5lbW9uaWMYASABKAlSCG1uZW1vbmlj');

@$core.Deprecated('Use setSeedFromMnemonicRequestDescriptor instead')
const SetSeedFromMnemonicRequest$json = {
  '1': 'SetSeedFromMnemonicRequest',
  '2': [
    {'1': 'mnemonic', '3': 1, '4': 1, '5': 9, '10': 'mnemonic'},
  ],
};

/// Descriptor for `SetSeedFromMnemonicRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List setSeedFromMnemonicRequestDescriptor =
    $convert.base64Decode('ChpTZXRTZWVkRnJvbU1uZW1vbmljUmVxdWVzdBIaCghtbmVtb25pYxgBIAEoCVIIbW5lbW9uaW'
        'M=');

@$core.Deprecated('Use setSeedFromMnemonicResponseDescriptor instead')
const SetSeedFromMnemonicResponse$json = {
  '1': 'SetSeedFromMnemonicResponse',
};

/// Descriptor for `SetSeedFromMnemonicResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List setSeedFromMnemonicResponseDescriptor =
    $convert.base64Decode('ChtTZXRTZWVkRnJvbU1uZW1vbmljUmVzcG9uc2U=');

@$core.Deprecated('Use callRawRequestDescriptor instead')
const CallRawRequest$json = {
  '1': 'CallRawRequest',
  '2': [
    {'1': 'method', '3': 1, '4': 1, '5': 9, '10': 'method'},
    {'1': 'params_json', '3': 2, '4': 1, '5': 9, '10': 'paramsJson'},
  ],
};

/// Descriptor for `CallRawRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List callRawRequestDescriptor =
    $convert.base64Decode('Cg5DYWxsUmF3UmVxdWVzdBIWCgZtZXRob2QYASABKAlSBm1ldGhvZBIfCgtwYXJhbXNfanNvbh'
        'gCIAEoCVIKcGFyYW1zSnNvbg==');

@$core.Deprecated('Use callRawResponseDescriptor instead')
const CallRawResponse$json = {
  '1': 'CallRawResponse',
  '2': [
    {'1': 'result_json', '3': 1, '4': 1, '5': 9, '10': 'resultJson'},
  ],
};

/// Descriptor for `CallRawResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List callRawResponseDescriptor =
    $convert.base64Decode('Cg9DYWxsUmF3UmVzcG9uc2USHwoLcmVzdWx0X2pzb24YASABKAlSCnJlc3VsdEpzb24=');

const $core.Map<$core.String, $core.dynamic> SidepotServiceBase$json = {
  '1': 'SidepotService',
  '2': [
    {'1': 'GetBalance', '2': '.sidepot.v1.GetBalanceRequest', '3': '.sidepot.v1.GetBalanceResponse'},
    {'1': 'GetBlockCount', '2': '.sidepot.v1.GetBlockCountRequest', '3': '.sidepot.v1.GetBlockCountResponse'},
    {'1': 'Stop', '2': '.sidepot.v1.StopRequest', '3': '.sidepot.v1.StopResponse'},
    {'1': 'GetNewAddress', '2': '.sidepot.v1.GetNewAddressRequest', '3': '.sidepot.v1.GetNewAddressResponse'},
    {'1': 'Withdraw', '2': '.sidepot.v1.WithdrawRequest', '3': '.sidepot.v1.WithdrawResponse'},
    {'1': 'Transfer', '2': '.sidepot.v1.TransferRequest', '3': '.sidepot.v1.TransferResponse'},
    {
      '1': 'GetSidechainWealth',
      '2': '.sidepot.v1.GetSidechainWealthRequest',
      '3': '.sidepot.v1.GetSidechainWealthResponse'
    },
    {'1': 'CreateDeposit', '2': '.sidepot.v1.CreateDepositRequest', '3': '.sidepot.v1.CreateDepositResponse'},
    {
      '1': 'GetPendingWithdrawalBundle',
      '2': '.sidepot.v1.GetPendingWithdrawalBundleRequest',
      '3': '.sidepot.v1.GetPendingWithdrawalBundleResponse'
    },
    {'1': 'ConnectPeer', '2': '.sidepot.v1.ConnectPeerRequest', '3': '.sidepot.v1.ConnectPeerResponse'},
    {'1': 'ListPeers', '2': '.sidepot.v1.ListPeersRequest', '3': '.sidepot.v1.ListPeersResponse'},
    {'1': 'Mine', '2': '.sidepot.v1.MineRequest', '3': '.sidepot.v1.MineResponse'},
    {'1': 'GetBlock', '2': '.sidepot.v1.GetBlockRequest', '3': '.sidepot.v1.GetBlockResponse'},
    {
      '1': 'GetBestMainchainBlockHash',
      '2': '.sidepot.v1.GetBestMainchainBlockHashRequest',
      '3': '.sidepot.v1.GetBestMainchainBlockHashResponse'
    },
    {
      '1': 'GetBestSidechainBlockHash',
      '2': '.sidepot.v1.GetBestSidechainBlockHashRequest',
      '3': '.sidepot.v1.GetBestSidechainBlockHashResponse'
    },
    {'1': 'GetBmmInclusions', '2': '.sidepot.v1.GetBmmInclusionsRequest', '3': '.sidepot.v1.GetBmmInclusionsResponse'},
    {'1': 'GetWalletUtxos', '2': '.sidepot.v1.GetWalletUtxosRequest', '3': '.sidepot.v1.GetWalletUtxosResponse'},
    {'1': 'ListUtxos', '2': '.sidepot.v1.ListUtxosRequest', '3': '.sidepot.v1.ListUtxosResponse'},
    {
      '1': 'RemoveFromMempool',
      '2': '.sidepot.v1.RemoveFromMempoolRequest',
      '3': '.sidepot.v1.RemoveFromMempoolResponse'
    },
    {
      '1': 'GetLatestFailedWithdrawalBundleHeight',
      '2': '.sidepot.v1.GetLatestFailedWithdrawalBundleHeightRequest',
      '3': '.sidepot.v1.GetLatestFailedWithdrawalBundleHeightResponse'
    },
    {'1': 'GenerateMnemonic', '2': '.sidepot.v1.GenerateMnemonicRequest', '3': '.sidepot.v1.GenerateMnemonicResponse'},
    {
      '1': 'SetSeedFromMnemonic',
      '2': '.sidepot.v1.SetSeedFromMnemonicRequest',
      '3': '.sidepot.v1.SetSeedFromMnemonicResponse'
    },
    {'1': 'CallRaw', '2': '.sidepot.v1.CallRawRequest', '3': '.sidepot.v1.CallRawResponse'},
  ],
};

@$core.Deprecated('Use sidepotServiceDescriptor instead')
const $core.Map<$core.String, $core.Map<$core.String, $core.dynamic>> SidepotServiceBase$messageJson = {
  '.sidepot.v1.GetBalanceRequest': GetBalanceRequest$json,
  '.sidepot.v1.GetBalanceResponse': GetBalanceResponse$json,
  '.sidepot.v1.GetBlockCountRequest': GetBlockCountRequest$json,
  '.sidepot.v1.GetBlockCountResponse': GetBlockCountResponse$json,
  '.sidepot.v1.StopRequest': StopRequest$json,
  '.sidepot.v1.StopResponse': StopResponse$json,
  '.sidepot.v1.GetNewAddressRequest': GetNewAddressRequest$json,
  '.sidepot.v1.GetNewAddressResponse': GetNewAddressResponse$json,
  '.sidepot.v1.WithdrawRequest': WithdrawRequest$json,
  '.sidepot.v1.WithdrawResponse': WithdrawResponse$json,
  '.sidepot.v1.TransferRequest': TransferRequest$json,
  '.sidepot.v1.TransferResponse': TransferResponse$json,
  '.sidepot.v1.GetSidechainWealthRequest': GetSidechainWealthRequest$json,
  '.sidepot.v1.GetSidechainWealthResponse': GetSidechainWealthResponse$json,
  '.sidepot.v1.CreateDepositRequest': CreateDepositRequest$json,
  '.sidepot.v1.CreateDepositResponse': CreateDepositResponse$json,
  '.sidepot.v1.GetPendingWithdrawalBundleRequest': GetPendingWithdrawalBundleRequest$json,
  '.sidepot.v1.GetPendingWithdrawalBundleResponse': GetPendingWithdrawalBundleResponse$json,
  '.sidepot.v1.ConnectPeerRequest': ConnectPeerRequest$json,
  '.sidepot.v1.ConnectPeerResponse': ConnectPeerResponse$json,
  '.sidepot.v1.ListPeersRequest': ListPeersRequest$json,
  '.sidepot.v1.ListPeersResponse': ListPeersResponse$json,
  '.sidepot.v1.MineRequest': MineRequest$json,
  '.sidepot.v1.MineResponse': MineResponse$json,
  '.sidepot.v1.GetBlockRequest': GetBlockRequest$json,
  '.sidepot.v1.GetBlockResponse': GetBlockResponse$json,
  '.sidepot.v1.GetBestMainchainBlockHashRequest': GetBestMainchainBlockHashRequest$json,
  '.sidepot.v1.GetBestMainchainBlockHashResponse': GetBestMainchainBlockHashResponse$json,
  '.sidepot.v1.GetBestSidechainBlockHashRequest': GetBestSidechainBlockHashRequest$json,
  '.sidepot.v1.GetBestSidechainBlockHashResponse': GetBestSidechainBlockHashResponse$json,
  '.sidepot.v1.GetBmmInclusionsRequest': GetBmmInclusionsRequest$json,
  '.sidepot.v1.GetBmmInclusionsResponse': GetBmmInclusionsResponse$json,
  '.sidepot.v1.GetWalletUtxosRequest': GetWalletUtxosRequest$json,
  '.sidepot.v1.GetWalletUtxosResponse': GetWalletUtxosResponse$json,
  '.sidepot.v1.ListUtxosRequest': ListUtxosRequest$json,
  '.sidepot.v1.ListUtxosResponse': ListUtxosResponse$json,
  '.sidepot.v1.RemoveFromMempoolRequest': RemoveFromMempoolRequest$json,
  '.sidepot.v1.RemoveFromMempoolResponse': RemoveFromMempoolResponse$json,
  '.sidepot.v1.GetLatestFailedWithdrawalBundleHeightRequest': GetLatestFailedWithdrawalBundleHeightRequest$json,
  '.sidepot.v1.GetLatestFailedWithdrawalBundleHeightResponse': GetLatestFailedWithdrawalBundleHeightResponse$json,
  '.sidepot.v1.GenerateMnemonicRequest': GenerateMnemonicRequest$json,
  '.sidepot.v1.GenerateMnemonicResponse': GenerateMnemonicResponse$json,
  '.sidepot.v1.SetSeedFromMnemonicRequest': SetSeedFromMnemonicRequest$json,
  '.sidepot.v1.SetSeedFromMnemonicResponse': SetSeedFromMnemonicResponse$json,
  '.sidepot.v1.CallRawRequest': CallRawRequest$json,
  '.sidepot.v1.CallRawResponse': CallRawResponse$json,
};

/// Descriptor for `SidepotService`. Decode as a `google.protobuf.ServiceDescriptorProto`.
final $typed_data.Uint8List sidepotServiceDescriptor =
    $convert.base64Decode('Cg5TaWRlcG90U2VydmljZRJLCgpHZXRCYWxhbmNlEh0uc2lkZXBvdC52MS5HZXRCYWxhbmNlUm'
        'VxdWVzdBoeLnNpZGVwb3QudjEuR2V0QmFsYW5jZVJlc3BvbnNlElQKDUdldEJsb2NrQ291bnQS'
        'IC5zaWRlcG90LnYxLkdldEJsb2NrQ291bnRSZXF1ZXN0GiEuc2lkZXBvdC52MS5HZXRCbG9ja0'
        'NvdW50UmVzcG9uc2USOQoEU3RvcBIXLnNpZGVwb3QudjEuU3RvcFJlcXVlc3QaGC5zaWRlcG90'
        'LnYxLlN0b3BSZXNwb25zZRJUCg1HZXROZXdBZGRyZXNzEiAuc2lkZXBvdC52MS5HZXROZXdBZG'
        'RyZXNzUmVxdWVzdBohLnNpZGVwb3QudjEuR2V0TmV3QWRkcmVzc1Jlc3BvbnNlEkUKCFdpdGhk'
        'cmF3Ehsuc2lkZXBvdC52MS5XaXRoZHJhd1JlcXVlc3QaHC5zaWRlcG90LnYxLldpdGhkcmF3Um'
        'VzcG9uc2USRQoIVHJhbnNmZXISGy5zaWRlcG90LnYxLlRyYW5zZmVyUmVxdWVzdBocLnNpZGVw'
        'b3QudjEuVHJhbnNmZXJSZXNwb25zZRJjChJHZXRTaWRlY2hhaW5XZWFsdGgSJS5zaWRlcG90Ln'
        'YxLkdldFNpZGVjaGFpbldlYWx0aFJlcXVlc3QaJi5zaWRlcG90LnYxLkdldFNpZGVjaGFpbldl'
        'YWx0aFJlc3BvbnNlElQKDUNyZWF0ZURlcG9zaXQSIC5zaWRlcG90LnYxLkNyZWF0ZURlcG9zaX'
        'RSZXF1ZXN0GiEuc2lkZXBvdC52MS5DcmVhdGVEZXBvc2l0UmVzcG9uc2USewoaR2V0UGVuZGlu'
        'Z1dpdGhkcmF3YWxCdW5kbGUSLS5zaWRlcG90LnYxLkdldFBlbmRpbmdXaXRoZHJhd2FsQnVuZG'
        'xlUmVxdWVzdBouLnNpZGVwb3QudjEuR2V0UGVuZGluZ1dpdGhkcmF3YWxCdW5kbGVSZXNwb25z'
        'ZRJOCgtDb25uZWN0UGVlchIeLnNpZGVwb3QudjEuQ29ubmVjdFBlZXJSZXF1ZXN0Gh8uc2lkZX'
        'BvdC52MS5Db25uZWN0UGVlclJlc3BvbnNlEkgKCUxpc3RQZWVycxIcLnNpZGVwb3QudjEuTGlz'
        'dFBlZXJzUmVxdWVzdBodLnNpZGVwb3QudjEuTGlzdFBlZXJzUmVzcG9uc2USOQoETWluZRIXLn'
        'NpZGVwb3QudjEuTWluZVJlcXVlc3QaGC5zaWRlcG90LnYxLk1pbmVSZXNwb25zZRJFCghHZXRC'
        'bG9jaxIbLnNpZGVwb3QudjEuR2V0QmxvY2tSZXF1ZXN0Ghwuc2lkZXBvdC52MS5HZXRCbG9ja1'
        'Jlc3BvbnNlEngKGUdldEJlc3RNYWluY2hhaW5CbG9ja0hhc2gSLC5zaWRlcG90LnYxLkdldEJl'
        'c3RNYWluY2hhaW5CbG9ja0hhc2hSZXF1ZXN0Gi0uc2lkZXBvdC52MS5HZXRCZXN0TWFpbmNoYW'
        'luQmxvY2tIYXNoUmVzcG9uc2USeAoZR2V0QmVzdFNpZGVjaGFpbkJsb2NrSGFzaBIsLnNpZGVw'
        'b3QudjEuR2V0QmVzdFNpZGVjaGFpbkJsb2NrSGFzaFJlcXVlc3QaLS5zaWRlcG90LnYxLkdldE'
        'Jlc3RTaWRlY2hhaW5CbG9ja0hhc2hSZXNwb25zZRJdChBHZXRCbW1JbmNsdXNpb25zEiMuc2lk'
        'ZXBvdC52MS5HZXRCbW1JbmNsdXNpb25zUmVxdWVzdBokLnNpZGVwb3QudjEuR2V0Qm1tSW5jbH'
        'VzaW9uc1Jlc3BvbnNlElcKDkdldFdhbGxldFV0eG9zEiEuc2lkZXBvdC52MS5HZXRXYWxsZXRV'
        'dHhvc1JlcXVlc3QaIi5zaWRlcG90LnYxLkdldFdhbGxldFV0eG9zUmVzcG9uc2USSAoJTGlzdF'
        'V0eG9zEhwuc2lkZXBvdC52MS5MaXN0VXR4b3NSZXF1ZXN0Gh0uc2lkZXBvdC52MS5MaXN0VXR4'
        'b3NSZXNwb25zZRJgChFSZW1vdmVGcm9tTWVtcG9vbBIkLnNpZGVwb3QudjEuUmVtb3ZlRnJvbU'
        '1lbXBvb2xSZXF1ZXN0GiUuc2lkZXBvdC52MS5SZW1vdmVGcm9tTWVtcG9vbFJlc3BvbnNlEpwB'
        'CiVHZXRMYXRlc3RGYWlsZWRXaXRoZHJhd2FsQnVuZGxlSGVpZ2h0Ejguc2lkZXBvdC52MS5HZX'
        'RMYXRlc3RGYWlsZWRXaXRoZHJhd2FsQnVuZGxlSGVpZ2h0UmVxdWVzdBo5LnNpZGVwb3QudjEu'
        'R2V0TGF0ZXN0RmFpbGVkV2l0aGRyYXdhbEJ1bmRsZUhlaWdodFJlc3BvbnNlEl0KEEdlbmVyYX'
        'RlTW5lbW9uaWMSIy5zaWRlcG90LnYxLkdlbmVyYXRlTW5lbW9uaWNSZXF1ZXN0GiQuc2lkZXBv'
        'dC52MS5HZW5lcmF0ZU1uZW1vbmljUmVzcG9uc2USZgoTU2V0U2VlZEZyb21NbmVtb25pYxImLn'
        'NpZGVwb3QudjEuU2V0U2VlZEZyb21NbmVtb25pY1JlcXVlc3QaJy5zaWRlcG90LnYxLlNldFNl'
        'ZWRGcm9tTW5lbW9uaWNSZXNwb25zZRJCCgdDYWxsUmF3Ehouc2lkZXBvdC52MS5DYWxsUmF3Um'
        'VxdWVzdBobLnNpZGVwb3QudjEuQ2FsbFJhd1Jlc3BvbnNl');
