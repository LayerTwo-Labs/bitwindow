// Package sidepot is the client for the Sidepot sidechain, a Thunder fork that
// also reads every mainchain block for its game.
package sidepot

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"net"
	"strconv"

	"github.com/LayerTwo-Labs/sidesail/sidechain-orchestrator/sidechain"
)

// unusedL1RPC fills --l1-rpc-url when the node reads blocks from Esplora.
const unusedL1RPC = "http://unused.invalid"

var (
	_ sidechain.Node           = (*Node)(nil)
	_ sidechain.BMMNode        = (*Node)(nil)
	_ sidechain.WithdrawalNode = (*Node)(nil)
	_ sidechain.ModeArgsNode   = (*Node)(nil)
)

// Node is a Sidepot node. It serves a block template and takes the won block
// back, so the BMM engine drives it as it drives Thunder. The template names
// the node's own game account as the block's producer, which is where the
// block bonus goes.
type Node struct {
	*sidechain.JSONRPCProxy
	seedPeer string
	network  string
}

// The block bonus rules (spec section 6, sidepot-core's default parameters).
// The L1 block that accepts a Sidepot block pays its producer a bonus out of
// the bonus pool: bonusBidMultiple times the bid, at most bonusPoolBps of the
// pool, and nothing for a bid under bonusMinBidSats.
const (
	bonusPoolBps     = 500
	bonusBidMultiple = 2
	bonusMinBidSats  = 10_000
)

// bonusCapSats is the most a block can earn from a bonus pool.
func bonusCapSats(poolSats int64) int64 {
	if poolSats <= 0 {
		return 0
	}
	return poolSats * bonusPoolBps / 10_000
}

// bonusSats is what a bid of bidSats earns from a bonus cap of capSats.
func bonusSats(bidSats, capSats int64) int64 {
	if bidSats < bonusMinBidSats {
		return 0
	}
	return min(bidSats*bonusBidMultiple, capSats)
}

// openingBidSats is the smallest bid that earns the whole bonus cap: half the
// cap, and never under the minimum a bid needs to earn anything.
func openingBidSats(capSats int64) int64 {
	return max(bonusMinBidSats, (capSats+bonusBidMultiple-1)/bonusBidMultiple)
}

// GetBlockTemplate adds the block bonus to what the block is worth, and names
// the bid that earns it. The pool is read as of the latest mainchain block; the
// bonus is paid when a later Sidepot block settles the block that took the bid.
func (n *Node) GetBlockTemplate(ctx context.Context) (*sidechain.BlockTemplate, error) {
	template, err := n.JSONRPCProxy.GetBlockTemplate(ctx)
	if err != nil {
		return nil, err
	}
	raw, err := n.CallRaw(ctx, "game_state", nil)
	if err != nil {
		return nil, fmt.Errorf("read the game: %w", err)
	}
	// The game is null until it starts.
	var game *struct {
		BonusPoolSats int64 `json:"bonus_pool_sats"`
		Preview       *struct {
			BonusPoolSats int64 `json:"bonus_pool_sats"`
		} `json:"preview"`
	}
	if err := json.Unmarshal(raw, &game); err != nil {
		return nil, fmt.Errorf("decode the game: %w", err)
	}
	pool := int64(0)
	if game != nil {
		pool = game.BonusPoolSats
		if game.Preview != nil {
			pool = game.Preview.BonusPoolSats
		}
	}
	bonus := bonusCapSats(pool)
	fees := template.FeesSats
	template.FeesSats += bonus
	template.OpeningBidSats = openingBidSats(bonus)
	template.WorthAt = func(bidSats int64) int64 { return fees + bonusSats(bidSats, bonus) }
	return template, nil
}

// NewNode wraps the node's JSON-RPC proxy. network is the node's own name for
// the network the mainchain runs, empty when it has none.
func NewNode(proxy *sidechain.JSONRPCProxy, network string) *Node {
	return &Node{JSONRPCProxy: proxy, seedPeer: proxy.SeedPeer, network: network}
}

// Args starts the bare node and names where it reads mainchain blocks: the
// network's Esplora server in light mode, the local mainchain node otherwise.
func (n *Node) Args(ctx context.Context, host sidechain.Host) ([]string, error) {
	if n.network != "mainnet" {
		return nil, errors.New("sidepot runs on eCash mainnet only")
	}
	args := []string{"--headless"}
	if n.seedPeer != "" {
		args = append(args, "--add-peer="+n.seedPeer)
	}
	if esplora := host.MainchainEsplora(); esplora != "" {
		return append(args, "--l1-rpc-url="+unusedL1RPC, "--l1-esplora-url="+esplora), nil
	}
	rpcHost, rpcPort, err := host.MainchainRPC()
	if err != nil {
		return nil, err
	}
	cookie, err := host.MainchainReader(ctx)
	if err != nil {
		return nil, err
	}
	rpcURL := "http://" + net.JoinHostPort(rpcHost, strconv.Itoa(rpcPort))
	return append(args, "--l1-rpc-url="+rpcURL, "--l1-rpc-cookie="+cookie), nil
}

// ModeArgs names the block source flags, which differ between the node modes.
func (n *Node) ModeArgs() []string {
	return []string{"--l1-rpc-url", "--l1-rpc-cookie", "--l1-esplora-url"}
}
