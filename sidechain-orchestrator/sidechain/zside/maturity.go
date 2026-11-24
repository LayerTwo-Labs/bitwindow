package zside

import (
	"context"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"slices"

	commonpb "github.com/LayerTwo-Labs/sidesail/sidechain-orchestrator/gen/cusf/common/v1"
	enforcerpb "github.com/LayerTwo-Labs/sidesail/sidechain-orchestrator/gen/cusf/mainchain/v1"
	"google.golang.org/protobuf/types/known/wrapperspb"
	"lukechampine.com/blake3"
)

const maturityBlocks = 50

type maturityCache struct {
	tip   string
	coins map[string]bool
}

func (h *Handler) setSpendable(ctx context.Context, rows []map[string]json.RawMessage) error {
	var deposits, coinbases bool
	for _, row := range rows {
		var point outPoint
		if err := json.Unmarshal(row["outpoint"], &point); err != nil {
			return err
		}
		deposits = deposits || point.Deposit != nil
		coinbases = coinbases || point.Coinbase != nil
	}
	h.maturityMu.Lock()
	defer h.maturityMu.Unlock()
	if deposits {
		if err := h.readImmatureDeposits(ctx); err != nil {
			return err
		}
	}
	if coinbases {
		if err := h.readImmatureCoinbases(ctx); err != nil {
			return err
		}
	}
	for _, row := range rows {
		var point outPoint
		var value output
		if err := json.Unmarshal(row["outpoint"], &point); err != nil {
			return err
		}
		if err := json.Unmarshal(row["output"], &value); err != nil {
			return err
		}
		spendable := string(row["confirmed"]) != "false" && value.Content.Withdrawal == nil
		if point.Deposit != nil {
			spendable = spendable && !h.deposits.coins[*point.Deposit]
		}
		if point.Coinbase != nil {
			spendable = spendable && !h.coinbases.coins[point.Coinbase.Txid]
		}
		row["spendable"] = json.RawMessage(fmt.Sprintf("%t", spendable))
	}
	return nil
}

func (h *Handler) readImmatureDeposits(ctx context.Context) error {
	if h.validator == nil {
		return fmt.Errorf("read zSide deposit maturity: no validator")
	}
	validator, err := h.validator()
	if err != nil {
		return err
	}
	chainTip, err := validator.GetChainTip(ctx, &enforcerpb.GetChainTipRequest{})
	if err != nil {
		return err
	}
	tip := chainTip.GetBlockHeaderInfo().GetBlockHash().GetHex().GetValue()
	tipHeight := chainTip.GetBlockHeaderInfo().GetHeight()
	if tip == "" {
		return fmt.Errorf("read zSide deposit maturity: no mainchain tip")
	}
	if h.deposits.coins != nil && h.deposits.tip == tip {
		return nil
	}
	coins := make(map[string]bool)
	from := tip
	remaining := uint32(maturityBlocks)
	for remaining > 0 {
		ancestors := remaining - 1
		resp, err := validator.GetBlockInfo(ctx, &enforcerpb.GetBlockInfoRequest{
			BlockHash:   &commonpb.ReverseHex{Hex: wrapperspb.String(from)},
			SidechainId: wrapperspb.UInt32(98), MaxAncestors: &ancestors,
		})
		if err != nil {
			return err
		}
		if len(resp.GetInfos()) == 0 {
			return fmt.Errorf("read zSide deposit maturity: no block %s", from)
		}
		oldest := resp.GetInfos()[0].GetHeaderInfo()
		for _, info := range resp.GetInfos() {
			header := info.GetHeaderInfo()
			if header.GetHeight() < oldest.GetHeight() {
				oldest = header
			}
			if tipHeight-header.GetHeight() >= maturityBlocks {
				continue
			}
			for _, event := range info.GetBlockInfo().GetEvents() {
				if deposit := event.GetDeposit(); deposit != nil {
					point := deposit.GetOutpoint()
					coins[fmt.Sprintf("%s:%d", point.GetTxid().GetHex().GetValue(), point.GetVout().GetValue())] = true
				}
			}
		}
		if oldest.GetHeight() == 0 || tipHeight-oldest.GetHeight() >= maturityBlocks-1 {
			break
		}
		remaining = maturityBlocks - (tipHeight - oldest.GetHeight() + 1)
		from = oldest.GetPrevBlockHash().GetHex().GetValue()

	}
	h.deposits = maturityCache{tip: tip, coins: coins}
	return nil
}

type maturityHeader struct {
	MerkleRoot   string  `json:"merkle_root"`
	PrevMainHash string  `json:"prev_main_hash"`
	PrevSideHash *string `json:"prev_side_hash"`
}

func coinbaseTxid(header maturityHeader) (string, error) {
	data := make([]byte, 0, 97)
	for index, hash := range []string{header.MerkleRoot, header.PrevMainHash} {
		bytes, err := hex.DecodeString(hash)
		if err != nil {
			return "", err
		}
		if len(bytes) != 32 {
			return "", fmt.Errorf("read zSide header: expected a 32-byte hash")
		}
		if index == 1 {
			slices.Reverse(bytes)
		}
		data = append(data, bytes...)
	}
	if header.PrevSideHash == nil {
		data = append(data, 0)
	} else {
		bytes, err := hex.DecodeString(*header.PrevSideHash)
		if err != nil {
			return "", err
		}
		if len(bytes) != 32 {
			return "", fmt.Errorf("read zSide header: expected a 32-byte hash")
		}
		data = append(data, 1)
		data = append(data, bytes...)
	}
	hash := blake3.Sum256(data)
	return hex.EncodeToString(hash[:]), nil
}

func (h *Handler) readImmatureCoinbases(ctx context.Context) error {
	var tip *string
	if err := h.proxy.Client.Call(ctx, "get_best_sidechain_block_hash", nil, &tip); err != nil {
		return err
	}
	if tip == nil {
		return fmt.Errorf("read zSide coinbase maturity: no sidechain tip")
	}
	if h.coinbases.coins != nil && h.coinbases.tip == *tip {
		return nil
	}
	coins := make(map[string]bool)
	from := tip
	// The next sidechain block spends coins, so the last 49 coinbases are immature.
	for count := 0; count < maturityBlocks-1 && from != nil; count++ {
		var block *struct {
			Header maturityHeader `json:"header"`
		}
		if err := h.proxy.Client.Call(ctx, "get_block", []any{*from, false}, &block); err != nil {
			return err
		}
		if block == nil {
			return fmt.Errorf("read zSide coinbase maturity: no block %s", *from)
		}
		txid, err := coinbaseTxid(block.Header)
		if err != nil {
			return err
		}
		coins[txid] = true
		from = block.Header.PrevSideHash
	}
	h.coinbases = maturityCache{tip: *tip, coins: coins}
	return nil
}
