//
//  Generated code. Do not modify.
//  source: sidepot/v1/sidepot.proto
//

import "package:connectrpc/connect.dart" as connect;
import "sidepot.pb.dart" as sidepotv1sidepot;

abstract final class SidepotService {
  /// Fully-qualified name of the SidepotService service.
  static const name = 'sidepot.v1.SidepotService';

  /// Get wallet balance (total and available).
  static const getBalance = connect.Spec(
    '/$name/GetBalance',
    connect.StreamType.unary,
    sidepotv1sidepot.GetBalanceRequest.new,
    sidepotv1sidepot.GetBalanceResponse.new,
  );

  /// Get current block count.
  static const getBlockCount = connect.Spec(
    '/$name/GetBlockCount',
    connect.StreamType.unary,
    sidepotv1sidepot.GetBlockCountRequest.new,
    sidepotv1sidepot.GetBlockCountResponse.new,
  );

  /// Stop the sidepot node.
  static const stop = connect.Spec(
    '/$name/Stop',
    connect.StreamType.unary,
    sidepotv1sidepot.StopRequest.new,
    sidepotv1sidepot.StopResponse.new,
  );

  /// Get a new address from the wallet.
  static const getNewAddress = connect.Spec(
    '/$name/GetNewAddress',
    connect.StreamType.unary,
    sidepotv1sidepot.GetNewAddressRequest.new,
    sidepotv1sidepot.GetNewAddressResponse.new,
  );

  /// Withdraw to mainchain.
  static const withdraw = connect.Spec(
    '/$name/Withdraw',
    connect.StreamType.unary,
    sidepotv1sidepot.WithdrawRequest.new,
    sidepotv1sidepot.WithdrawResponse.new,
  );

  /// Transfer within sidechain.
  static const transfer = connect.Spec(
    '/$name/Transfer',
    connect.StreamType.unary,
    sidepotv1sidepot.TransferRequest.new,
    sidepotv1sidepot.TransferResponse.new,
  );

  /// Get total sidechain wealth in sats.
  static const getSidechainWealth = connect.Spec(
    '/$name/GetSidechainWealth',
    connect.StreamType.unary,
    sidepotv1sidepot.GetSidechainWealthRequest.new,
    sidepotv1sidepot.GetSidechainWealthResponse.new,
  );

  /// Create a deposit transaction.
  static const createDeposit = connect.Spec(
    '/$name/CreateDeposit',
    connect.StreamType.unary,
    sidepotv1sidepot.CreateDepositRequest.new,
    sidepotv1sidepot.CreateDepositResponse.new,
  );

  /// Get pending withdrawal bundle.
  static const getPendingWithdrawalBundle = connect.Spec(
    '/$name/GetPendingWithdrawalBundle',
    connect.StreamType.unary,
    sidepotv1sidepot.GetPendingWithdrawalBundleRequest.new,
    sidepotv1sidepot.GetPendingWithdrawalBundleResponse.new,
  );

  /// Connect to a peer.
  static const connectPeer = connect.Spec(
    '/$name/ConnectPeer',
    connect.StreamType.unary,
    sidepotv1sidepot.ConnectPeerRequest.new,
    sidepotv1sidepot.ConnectPeerResponse.new,
  );

  /// List connected peers.
  static const listPeers = connect.Spec(
    '/$name/ListPeers',
    connect.StreamType.unary,
    sidepotv1sidepot.ListPeersRequest.new,
    sidepotv1sidepot.ListPeersResponse.new,
  );

  /// Mine a block.
  static const mine = connect.Spec(
    '/$name/Mine',
    connect.StreamType.unary,
    sidepotv1sidepot.MineRequest.new,
    sidepotv1sidepot.MineResponse.new,
  );

  /// Get block by hash.
  static const getBlock = connect.Spec(
    '/$name/GetBlock',
    connect.StreamType.unary,
    sidepotv1sidepot.GetBlockRequest.new,
    sidepotv1sidepot.GetBlockResponse.new,
  );

  /// Get best mainchain block hash.
  static const getBestMainchainBlockHash = connect.Spec(
    '/$name/GetBestMainchainBlockHash',
    connect.StreamType.unary,
    sidepotv1sidepot.GetBestMainchainBlockHashRequest.new,
    sidepotv1sidepot.GetBestMainchainBlockHashResponse.new,
  );

  /// Get best sidechain block hash.
  static const getBestSidechainBlockHash = connect.Spec(
    '/$name/GetBestSidechainBlockHash',
    connect.StreamType.unary,
    sidepotv1sidepot.GetBestSidechainBlockHashRequest.new,
    sidepotv1sidepot.GetBestSidechainBlockHashResponse.new,
  );

  /// Get BMM inclusions for a block.
  static const getBmmInclusions = connect.Spec(
    '/$name/GetBmmInclusions',
    connect.StreamType.unary,
    sidepotv1sidepot.GetBmmInclusionsRequest.new,
    sidepotv1sidepot.GetBmmInclusionsResponse.new,
  );

  /// Get wallet UTXOs.
  static const getWalletUtxos = connect.Spec(
    '/$name/GetWalletUtxos',
    connect.StreamType.unary,
    sidepotv1sidepot.GetWalletUtxosRequest.new,
    sidepotv1sidepot.GetWalletUtxosResponse.new,
  );

  /// List all UTXOs.
  static const listUtxos = connect.Spec(
    '/$name/ListUtxos',
    connect.StreamType.unary,
    sidepotv1sidepot.ListUtxosRequest.new,
    sidepotv1sidepot.ListUtxosResponse.new,
  );

  /// Remove transaction from mempool.
  static const removeFromMempool = connect.Spec(
    '/$name/RemoveFromMempool',
    connect.StreamType.unary,
    sidepotv1sidepot.RemoveFromMempoolRequest.new,
    sidepotv1sidepot.RemoveFromMempoolResponse.new,
  );

  /// Get latest failed withdrawal bundle height.
  static const getLatestFailedWithdrawalBundleHeight = connect.Spec(
    '/$name/GetLatestFailedWithdrawalBundleHeight',
    connect.StreamType.unary,
    sidepotv1sidepot.GetLatestFailedWithdrawalBundleHeightRequest.new,
    sidepotv1sidepot.GetLatestFailedWithdrawalBundleHeightResponse.new,
  );

  /// Generate a new mnemonic.
  static const generateMnemonic = connect.Spec(
    '/$name/GenerateMnemonic',
    connect.StreamType.unary,
    sidepotv1sidepot.GenerateMnemonicRequest.new,
    sidepotv1sidepot.GenerateMnemonicResponse.new,
  );

  /// Set seed from mnemonic.
  static const setSeedFromMnemonic = connect.Spec(
    '/$name/SetSeedFromMnemonic',
    connect.StreamType.unary,
    sidepotv1sidepot.SetSeedFromMnemonicRequest.new,
    sidepotv1sidepot.SetSeedFromMnemonicResponse.new,
  );

  /// Raw JSON-RPC passthrough. The game methods go through it.
  static const callRaw = connect.Spec(
    '/$name/CallRaw',
    connect.StreamType.unary,
    sidepotv1sidepot.CallRawRequest.new,
    sidepotv1sidepot.CallRawResponse.new,
  );
}
