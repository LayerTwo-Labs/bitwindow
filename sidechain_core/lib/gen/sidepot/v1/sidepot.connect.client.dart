//
//  Generated code. Do not modify.
//  source: sidepot/v1/sidepot.proto
//

import "package:connectrpc/connect.dart" as connect;
import "sidepot.pb.dart" as sidepotv1sidepot;
import "sidepot.connect.spec.dart" as specs;

extension type SidepotServiceClient (connect.Transport _transport) {
  /// Get wallet balance (total and available).
  Future<sidepotv1sidepot.GetBalanceResponse> getBalance(
    sidepotv1sidepot.GetBalanceRequest input, {
    connect.Headers? headers,
    connect.AbortSignal? signal,
    Function(connect.Headers)? onHeader,
    Function(connect.Headers)? onTrailer,
  }) {
    return connect.Client(_transport).unary(
      specs.SidepotService.getBalance,
      input,
      signal: signal,
      headers: headers,
      onHeader: onHeader,
      onTrailer: onTrailer,
    );
  }

  /// Get current block count.
  Future<sidepotv1sidepot.GetBlockCountResponse> getBlockCount(
    sidepotv1sidepot.GetBlockCountRequest input, {
    connect.Headers? headers,
    connect.AbortSignal? signal,
    Function(connect.Headers)? onHeader,
    Function(connect.Headers)? onTrailer,
  }) {
    return connect.Client(_transport).unary(
      specs.SidepotService.getBlockCount,
      input,
      signal: signal,
      headers: headers,
      onHeader: onHeader,
      onTrailer: onTrailer,
    );
  }

  /// Stop the sidepot node.
  Future<sidepotv1sidepot.StopResponse> stop(
    sidepotv1sidepot.StopRequest input, {
    connect.Headers? headers,
    connect.AbortSignal? signal,
    Function(connect.Headers)? onHeader,
    Function(connect.Headers)? onTrailer,
  }) {
    return connect.Client(_transport).unary(
      specs.SidepotService.stop,
      input,
      signal: signal,
      headers: headers,
      onHeader: onHeader,
      onTrailer: onTrailer,
    );
  }

  /// Get a new address from the wallet.
  Future<sidepotv1sidepot.GetNewAddressResponse> getNewAddress(
    sidepotv1sidepot.GetNewAddressRequest input, {
    connect.Headers? headers,
    connect.AbortSignal? signal,
    Function(connect.Headers)? onHeader,
    Function(connect.Headers)? onTrailer,
  }) {
    return connect.Client(_transport).unary(
      specs.SidepotService.getNewAddress,
      input,
      signal: signal,
      headers: headers,
      onHeader: onHeader,
      onTrailer: onTrailer,
    );
  }

  /// Withdraw to mainchain.
  Future<sidepotv1sidepot.WithdrawResponse> withdraw(
    sidepotv1sidepot.WithdrawRequest input, {
    connect.Headers? headers,
    connect.AbortSignal? signal,
    Function(connect.Headers)? onHeader,
    Function(connect.Headers)? onTrailer,
  }) {
    return connect.Client(_transport).unary(
      specs.SidepotService.withdraw,
      input,
      signal: signal,
      headers: headers,
      onHeader: onHeader,
      onTrailer: onTrailer,
    );
  }

  /// Transfer within sidechain.
  Future<sidepotv1sidepot.TransferResponse> transfer(
    sidepotv1sidepot.TransferRequest input, {
    connect.Headers? headers,
    connect.AbortSignal? signal,
    Function(connect.Headers)? onHeader,
    Function(connect.Headers)? onTrailer,
  }) {
    return connect.Client(_transport).unary(
      specs.SidepotService.transfer,
      input,
      signal: signal,
      headers: headers,
      onHeader: onHeader,
      onTrailer: onTrailer,
    );
  }

  /// Get total sidechain wealth in sats.
  Future<sidepotv1sidepot.GetSidechainWealthResponse> getSidechainWealth(
    sidepotv1sidepot.GetSidechainWealthRequest input, {
    connect.Headers? headers,
    connect.AbortSignal? signal,
    Function(connect.Headers)? onHeader,
    Function(connect.Headers)? onTrailer,
  }) {
    return connect.Client(_transport).unary(
      specs.SidepotService.getSidechainWealth,
      input,
      signal: signal,
      headers: headers,
      onHeader: onHeader,
      onTrailer: onTrailer,
    );
  }

  /// Create a deposit transaction.
  Future<sidepotv1sidepot.CreateDepositResponse> createDeposit(
    sidepotv1sidepot.CreateDepositRequest input, {
    connect.Headers? headers,
    connect.AbortSignal? signal,
    Function(connect.Headers)? onHeader,
    Function(connect.Headers)? onTrailer,
  }) {
    return connect.Client(_transport).unary(
      specs.SidepotService.createDeposit,
      input,
      signal: signal,
      headers: headers,
      onHeader: onHeader,
      onTrailer: onTrailer,
    );
  }

  /// Get pending withdrawal bundle.
  Future<sidepotv1sidepot.GetPendingWithdrawalBundleResponse> getPendingWithdrawalBundle(
    sidepotv1sidepot.GetPendingWithdrawalBundleRequest input, {
    connect.Headers? headers,
    connect.AbortSignal? signal,
    Function(connect.Headers)? onHeader,
    Function(connect.Headers)? onTrailer,
  }) {
    return connect.Client(_transport).unary(
      specs.SidepotService.getPendingWithdrawalBundle,
      input,
      signal: signal,
      headers: headers,
      onHeader: onHeader,
      onTrailer: onTrailer,
    );
  }

  /// Connect to a peer.
  Future<sidepotv1sidepot.ConnectPeerResponse> connectPeer(
    sidepotv1sidepot.ConnectPeerRequest input, {
    connect.Headers? headers,
    connect.AbortSignal? signal,
    Function(connect.Headers)? onHeader,
    Function(connect.Headers)? onTrailer,
  }) {
    return connect.Client(_transport).unary(
      specs.SidepotService.connectPeer,
      input,
      signal: signal,
      headers: headers,
      onHeader: onHeader,
      onTrailer: onTrailer,
    );
  }

  /// List connected peers.
  Future<sidepotv1sidepot.ListPeersResponse> listPeers(
    sidepotv1sidepot.ListPeersRequest input, {
    connect.Headers? headers,
    connect.AbortSignal? signal,
    Function(connect.Headers)? onHeader,
    Function(connect.Headers)? onTrailer,
  }) {
    return connect.Client(_transport).unary(
      specs.SidepotService.listPeers,
      input,
      signal: signal,
      headers: headers,
      onHeader: onHeader,
      onTrailer: onTrailer,
    );
  }

  /// Mine a block.
  Future<sidepotv1sidepot.MineResponse> mine(
    sidepotv1sidepot.MineRequest input, {
    connect.Headers? headers,
    connect.AbortSignal? signal,
    Function(connect.Headers)? onHeader,
    Function(connect.Headers)? onTrailer,
  }) {
    return connect.Client(_transport).unary(
      specs.SidepotService.mine,
      input,
      signal: signal,
      headers: headers,
      onHeader: onHeader,
      onTrailer: onTrailer,
    );
  }

  /// Get block by hash.
  Future<sidepotv1sidepot.GetBlockResponse> getBlock(
    sidepotv1sidepot.GetBlockRequest input, {
    connect.Headers? headers,
    connect.AbortSignal? signal,
    Function(connect.Headers)? onHeader,
    Function(connect.Headers)? onTrailer,
  }) {
    return connect.Client(_transport).unary(
      specs.SidepotService.getBlock,
      input,
      signal: signal,
      headers: headers,
      onHeader: onHeader,
      onTrailer: onTrailer,
    );
  }

  /// Get best mainchain block hash.
  Future<sidepotv1sidepot.GetBestMainchainBlockHashResponse> getBestMainchainBlockHash(
    sidepotv1sidepot.GetBestMainchainBlockHashRequest input, {
    connect.Headers? headers,
    connect.AbortSignal? signal,
    Function(connect.Headers)? onHeader,
    Function(connect.Headers)? onTrailer,
  }) {
    return connect.Client(_transport).unary(
      specs.SidepotService.getBestMainchainBlockHash,
      input,
      signal: signal,
      headers: headers,
      onHeader: onHeader,
      onTrailer: onTrailer,
    );
  }

  /// Get best sidechain block hash.
  Future<sidepotv1sidepot.GetBestSidechainBlockHashResponse> getBestSidechainBlockHash(
    sidepotv1sidepot.GetBestSidechainBlockHashRequest input, {
    connect.Headers? headers,
    connect.AbortSignal? signal,
    Function(connect.Headers)? onHeader,
    Function(connect.Headers)? onTrailer,
  }) {
    return connect.Client(_transport).unary(
      specs.SidepotService.getBestSidechainBlockHash,
      input,
      signal: signal,
      headers: headers,
      onHeader: onHeader,
      onTrailer: onTrailer,
    );
  }

  /// Get BMM inclusions for a block.
  Future<sidepotv1sidepot.GetBmmInclusionsResponse> getBmmInclusions(
    sidepotv1sidepot.GetBmmInclusionsRequest input, {
    connect.Headers? headers,
    connect.AbortSignal? signal,
    Function(connect.Headers)? onHeader,
    Function(connect.Headers)? onTrailer,
  }) {
    return connect.Client(_transport).unary(
      specs.SidepotService.getBmmInclusions,
      input,
      signal: signal,
      headers: headers,
      onHeader: onHeader,
      onTrailer: onTrailer,
    );
  }

  /// Get wallet UTXOs.
  Future<sidepotv1sidepot.GetWalletUtxosResponse> getWalletUtxos(
    sidepotv1sidepot.GetWalletUtxosRequest input, {
    connect.Headers? headers,
    connect.AbortSignal? signal,
    Function(connect.Headers)? onHeader,
    Function(connect.Headers)? onTrailer,
  }) {
    return connect.Client(_transport).unary(
      specs.SidepotService.getWalletUtxos,
      input,
      signal: signal,
      headers: headers,
      onHeader: onHeader,
      onTrailer: onTrailer,
    );
  }

  /// List all UTXOs.
  Future<sidepotv1sidepot.ListUtxosResponse> listUtxos(
    sidepotv1sidepot.ListUtxosRequest input, {
    connect.Headers? headers,
    connect.AbortSignal? signal,
    Function(connect.Headers)? onHeader,
    Function(connect.Headers)? onTrailer,
  }) {
    return connect.Client(_transport).unary(
      specs.SidepotService.listUtxos,
      input,
      signal: signal,
      headers: headers,
      onHeader: onHeader,
      onTrailer: onTrailer,
    );
  }

  /// Remove transaction from mempool.
  Future<sidepotv1sidepot.RemoveFromMempoolResponse> removeFromMempool(
    sidepotv1sidepot.RemoveFromMempoolRequest input, {
    connect.Headers? headers,
    connect.AbortSignal? signal,
    Function(connect.Headers)? onHeader,
    Function(connect.Headers)? onTrailer,
  }) {
    return connect.Client(_transport).unary(
      specs.SidepotService.removeFromMempool,
      input,
      signal: signal,
      headers: headers,
      onHeader: onHeader,
      onTrailer: onTrailer,
    );
  }

  /// Get latest failed withdrawal bundle height.
  Future<sidepotv1sidepot.GetLatestFailedWithdrawalBundleHeightResponse> getLatestFailedWithdrawalBundleHeight(
    sidepotv1sidepot.GetLatestFailedWithdrawalBundleHeightRequest input, {
    connect.Headers? headers,
    connect.AbortSignal? signal,
    Function(connect.Headers)? onHeader,
    Function(connect.Headers)? onTrailer,
  }) {
    return connect.Client(_transport).unary(
      specs.SidepotService.getLatestFailedWithdrawalBundleHeight,
      input,
      signal: signal,
      headers: headers,
      onHeader: onHeader,
      onTrailer: onTrailer,
    );
  }

  /// Generate a new mnemonic.
  Future<sidepotv1sidepot.GenerateMnemonicResponse> generateMnemonic(
    sidepotv1sidepot.GenerateMnemonicRequest input, {
    connect.Headers? headers,
    connect.AbortSignal? signal,
    Function(connect.Headers)? onHeader,
    Function(connect.Headers)? onTrailer,
  }) {
    return connect.Client(_transport).unary(
      specs.SidepotService.generateMnemonic,
      input,
      signal: signal,
      headers: headers,
      onHeader: onHeader,
      onTrailer: onTrailer,
    );
  }

  /// Set seed from mnemonic.
  Future<sidepotv1sidepot.SetSeedFromMnemonicResponse> setSeedFromMnemonic(
    sidepotv1sidepot.SetSeedFromMnemonicRequest input, {
    connect.Headers? headers,
    connect.AbortSignal? signal,
    Function(connect.Headers)? onHeader,
    Function(connect.Headers)? onTrailer,
  }) {
    return connect.Client(_transport).unary(
      specs.SidepotService.setSeedFromMnemonic,
      input,
      signal: signal,
      headers: headers,
      onHeader: onHeader,
      onTrailer: onTrailer,
    );
  }

  /// Raw JSON-RPC passthrough. The game methods go through it.
  Future<sidepotv1sidepot.CallRawResponse> callRaw(
    sidepotv1sidepot.CallRawRequest input, {
    connect.Headers? headers,
    connect.AbortSignal? signal,
    Function(connect.Headers)? onHeader,
    Function(connect.Headers)? onTrailer,
  }) {
    return connect.Client(_transport).unary(
      specs.SidepotService.callRaw,
      input,
      signal: signal,
      headers: headers,
      onHeader: onHeader,
      onTrailer: onTrailer,
    );
  }
}
