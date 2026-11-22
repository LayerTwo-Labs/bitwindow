// Package sidepot is the client for the Sidepot sidechain, a Thunder fork that
// also reads every mainchain block for its game.
package sidepot

import (
	"context"
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

// NewNode wraps the node's JSON-RPC proxy. network is the node's own name for
// the network the mainchain runs, empty when it has none.
func NewNode(proxy *sidechain.JSONRPCProxy, network string) *Node {
	return &Node{JSONRPCProxy: proxy, seedPeer: proxy.SeedPeer, network: network}
}

// Args starts the bare node and names where it reads mainchain blocks: the
// network's Esplora server in light mode, the local mainchain node otherwise.
func (n *Node) Args(ctx context.Context, host sidechain.Host) ([]string, error) {
	if n.network != "mainnet" {
		return nil, fmt.Errorf("Sidepot runs on eCash mainnet only")
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
