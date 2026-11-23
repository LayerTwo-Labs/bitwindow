package sidechain

import "context"

// Host is what a sidechain reads from the orchestrator before its node starts.
// Args takes one, so a chain states its own command line and the orchestrator
// holds no rule about any single chain.
type Host interface {
	// BackendOnly reports whether the orchestrator starts the bare node. When
	// it is false the orchestrator starts the chain's frontend build, which
	// draws a window of its own.
	BackendOnly() bool

	// MainchainRPC returns the RPC address of the local mainchain node, or an
	// error when none runs.
	MainchainRPC() (host string, port int, err error)

	// MainchainReader returns the credential file of a mainchain user that may
	// call only read-only RPCs.
	MainchainReader(ctx context.Context) (string, error)

	// MainchainCookie is the admin cookie of the local mainchain node.
	MainchainCookie() string

	// MainchainEsplora is the Esplora server a node reads mainchain blocks
	// from in light mode. It is empty when a local mainchain node runs.
	MainchainEsplora() string
}

// ModeArgsNode is a chain whose Args differ between the node modes. A mode
// change drops the flags ModeArgs names, and the next start builds them again.
type ModeArgsNode interface {
	Node

	ModeArgs() []string
}
