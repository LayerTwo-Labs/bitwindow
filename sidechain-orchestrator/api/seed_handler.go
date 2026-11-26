package api

import (
	"context"
	"errors"
	"fmt"

	"connectrpc.com/connect/v2"

	pb "github.com/LayerTwo-Labs/sidesail/sidechain-orchestrator/gen/walletmanager/v1"
	"github.com/LayerTwo-Labs/sidesail/sidechain-orchestrator/wallet"
)

func (h *WalletHandler) ExploreSeed(
	ctx context.Context,
	req *pb.ExploreSeedRequest,
) (*pb.ExploreSeedResponse, error) {
	if err := h.requireEngine(); err != nil {
		return nil, connect.NewError(connect.CodeFailedPrecondition, err.Error()).WithCause(err)
	}
	if req.WalletId != "" {
		return h.exploreWallet(ctx, req)
	}
	out, err := wallet.ExploreSeed(req.Mnemonic, req.Passphrase, req.BasePath, req.StartIndex, req.Count, h.engine.Network())
	if err != nil {
		return nil, connect.NewError(connect.CodeInvalidArgument, err.Error()).WithCause(err)
	}
	return exploredResponse(out), nil
}

func (h *WalletHandler) exploreWallet(ctx context.Context, req *pb.ExploreSeedRequest) (*pb.ExploreSeedResponse, error) {
	if req.Mnemonic != "" || req.Passphrase != "" {
		return nil, connect.Errorf(connect.CodeInvalidArgument, "give a wallet_id or a mnemonic, not both")
	}
	for _, w := range h.svc.GetAllWallets() {
		if w.ID != req.WalletId {
			continue
		}
		out, err := wallet.ExploreWallet(&w, req.BasePath, req.StartIndex, req.Count, h.engine.Network())
		if errors.Is(err, wallet.ErrNoSingleSeed) {
			return nil, connect.NewError(connect.CodeFailedPrecondition, err.Error()).WithCause(err)
		}
		if err != nil {
			return nil, connect.NewError(connect.CodeInvalidArgument, err.Error()).WithCause(err)
		}
		resp := exploredResponse(out)
		resp.Mnemonic = w.Master.Mnemonic
		if out.WalletReceiveChain && len(resp.Keys) > 0 {
			if err := h.fillKeyUse(ctx, w.ID, resp); err != nil {
				return nil, err
			}
		}
		return resp, nil
	}
	return nil, connect.Errorf(connect.CodeNotFound, "wallet %s not found", req.WalletId)
}

// fillKeyUse sets the use and the balance of each key from the wallet.
func (h *WalletHandler) fillKeyUse(ctx context.Context, walletID string, resp *pb.ExploreSeedResponse) error {
	received, err := h.engine.Backend().ListReceivedByAddress(ctx, walletID)
	if err != nil {
		err = fmt.Errorf("read the address use of wallet %s: %w", walletID, err)
		return connect.NewError(connect.CodeUnavailable, err.Error()).WithCause(err)
	}
	byAddress := make(map[string]wallet.ReceivedByAddress, len(received))
	for _, r := range received {
		byAddress[r.Address] = r
	}
	for _, k := range resp.Keys {
		r := byAddress[k.Address]
		k.Used = len(r.TxIDs) > 0
		k.BalanceSats = r.BalanceSats
	}
	resp.WalletTracksKeys = true
	return nil
}

func exploredResponse(out wallet.SeedExplorer) *pb.ExploreSeedResponse {
	keys := make([]*pb.ExploredKey, 0, len(out.Keys))
	for _, k := range out.Keys {
		keys = append(keys, &pb.ExploredKey{Path: k.Path, Address: k.Address, PublicKey: k.PublicKey, Wif: k.WIF})
	}
	return &pb.ExploreSeedResponse{
		SeedHex:          out.SeedHex,
		Xprv:             out.Xprv,
		Xpub:             out.Xpub,
		Bip47PaymentCode: out.PaymentCode,
		BasePath:         out.BasePath,
		WatchDescriptor:  out.WatchDescriptor,
		Keys:             keys,
	}
}

func (h *WalletHandler) GenerateMnemonic(
	ctx context.Context,
	_ *pb.GenerateMnemonicRequest,
) (*pb.GenerateMnemonicResponse, error) {
	mnemonic, err := wallet.GenerateMnemonic()
	if err != nil {
		return nil, rpcError(err)
	}
	return &pb.GenerateMnemonicResponse{Mnemonic: mnemonic}, nil
}

func (h *WalletHandler) ValidateMnemonic(
	ctx context.Context,
	req *pb.ValidateMnemonicRequest,
) (*pb.ValidateMnemonicResponse, error) {
	kind := pb.MnemonicKind_MNEMONIC_KIND_INVALID
	switch {
	case wallet.IsBIP39Mnemonic(req.Mnemonic):
		kind = pb.MnemonicKind_MNEMONIC_KIND_BIP39
	case wallet.IsElectrumSeed(req.Mnemonic):
		kind = pb.MnemonicKind_MNEMONIC_KIND_ELECTRUM
	}
	return &pb.ValidateMnemonicResponse{Kind: kind}, nil
}
