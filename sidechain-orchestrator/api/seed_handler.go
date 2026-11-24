package api

import (
	"context"
	"errors"

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
		return h.exploreWallet(req)
	}
	out, err := wallet.ExploreSeed(req.Mnemonic, req.Passphrase, req.BasePath, req.StartIndex, req.Count, h.engine.Network())
	if err != nil {
		return nil, connect.NewError(connect.CodeInvalidArgument, err.Error()).WithCause(err)
	}
	return exploredResponse(out), nil
}

func (h *WalletHandler) exploreWallet(req *pb.ExploreSeedRequest) (*pb.ExploreSeedResponse, error) {
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
		return resp, nil
	}
	return nil, connect.Errorf(connect.CodeNotFound, "wallet %s not found", req.WalletId)
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
