package orchestrator

import (
	"context"
	"path/filepath"
	"strconv"
	"testing"

	"github.com/stretchr/testify/require"

	"github.com/LayerTwo-Labs/sidesail/sidechain-orchestrator/config"
	"github.com/LayerTwo-Labs/sidesail/sidechain-orchestrator/config/netcatalog"
)

// sidepotOrchestrator runs eCash mainnet in mode, with a remote enforcer at a
// local test server.
func sidepotOrchestrator(t *testing.T, mode NodeMode) *Orchestrator {
	t.Helper()
	server := remoteValidatorServer(t, 42, nil)
	o := remoteTestOrchestrator(t, server.URL)
	previous := config.ECashEndpoints()
	previousID := config.ECashNetworkID()
	entry, ok := netcatalog.Embedded().ByID("ecash")
	require.True(t, ok)
	entry.Services.Enforcer = netcatalog.Endpoints{{URL: server.URL}}
	config.SetECashEndpoints(entry)
	config.SetECashNetworkID(entry.ID)
	t.Cleanup(func() {
		config.SetECashEndpoints(previous)
		config.SetECashNetworkID(previousID)
	})
	o.setNetwork("ecash")
	o.BitcoinConf.Network = config.NetworkECash
	require.NoError(t, WriteNodeMode(o.BitwindowDir, mode))
	return o
}

// sidepotArgs builds the command line a backend start gives the node, on top
// of the arguments the caller already holds.
func sidepotArgs(t *testing.T, o *Orchestrator, have []string) []string {
	t.Helper()
	cfg, err := o.getConfig("sidepot")
	require.NoError(t, err)
	opts := StartOpts{ForceBackend: true, TargetArgs: have}
	require.NoError(t, o.prepareSidechainArgs(cfg, &opts))
	require.NoError(t, o.appendSidechainArgs(context.Background(), cfg, &opts))
	return opts.TargetArgs
}

func sidepotPorts() (rpcPort, netAddr string) {
	spec := config.KnownSidechainSpecs["sidepot"]
	return strconv.Itoa(spec.BasePort), "0.0.0.0:" + strconv.Itoa(spec.BasePort-2000)
}

func TestSidepotLightModeArgs(t *testing.T) {
	o := sidepotOrchestrator(t, NodeModeLight)
	bridge, err := o.EnforcerURL()
	require.NoError(t, err)
	esplora := config.EsploraURLForNetwork(config.NetworkECash)
	require.NotEmpty(t, esplora)
	_, netAddr := sidepotPorts()

	require.ElementsMatch(t, []string{
		"--mainchain-grpc-url=" + bridge,
		"--net-addr=" + netAddr,
		"--network=mainnet",
		"--headless",
		"--l1-rpc-url=http://unused.invalid",
		"--l1-esplora-url=" + esplora,
	}, sidepotArgs(t, o, nil))
}

func TestSidepotFullModeArgs(t *testing.T) {
	o := sidepotOrchestrator(t, NodeModeFull)
	readerCore(t, o, 200)
	_, netAddr := sidepotPorts()
	core := "http://" + o.BitcoinConf.GetRPCHost() + ":" + strconv.Itoa(o.BitcoinConf.GetRPCPort())

	require.ElementsMatch(t, []string{
		"--net-addr=" + netAddr,
		"--mainchain-grpc-url=" + config.EnforcerGRPCURL(),
		"--network=mainnet",
		"--headless",
		"--l1-rpc-url=" + core,
		"--l1-rpc-cookie=" + filepath.Join(o.DataDir, "mainchain-reader.cookie"),
	}, sidepotArgs(t, o, nil))
}

// A mode change restarts the daemon from its own command line, so the block
// source of the mode it leaves must not survive.
func TestSidepotModeChangeRebuildsTheBlockSource(t *testing.T) {
	o := sidepotOrchestrator(t, NodeModeFull)
	readerCore(t, o, 200)
	cfg, err := o.getConfig("sidepot")
	require.NoError(t, err)
	full := sidepotArgs(t, o, nil)

	require.NoError(t, WriteNodeMode(o.BitwindowDir, NodeModeLight))
	kept, err := o.dropModeArgs(cfg, full)
	require.NoError(t, err)
	light := sidepotArgs(t, o, kept)
	require.Contains(t, light, "--l1-esplora-url="+config.EsploraURLForNetwork(config.NetworkECash))
	require.Contains(t, light, "--l1-rpc-url=http://unused.invalid")
	require.False(t, hasCLIFlag(light, "--l1-rpc-cookie"))

	require.NoError(t, WriteNodeMode(o.BitwindowDir, NodeModeFull))
	kept, err = o.dropModeArgs(cfg, light)
	require.NoError(t, err)
	require.ElementsMatch(t, full, sidepotArgs(t, o, kept))
}

func TestSidepotIsRefusedOffMainnet(t *testing.T) {
	server := remoteValidatorServer(t, 42, nil)
	o := remoteTestOrchestrator(t, server.URL)
	cfg, err := o.getConfig("sidepot")
	require.NoError(t, err)
	opts := StartOpts{ForceBackend: true}
	require.NoError(t, o.prepareSidechainArgs(cfg, &opts))
	require.ErrorContains(t, o.appendSidechainArgs(context.Background(), cfg, &opts), "eCash mainnet only")
}

func TestSidepotHasNoSeedPeer(t *testing.T) {
	for _, network := range []config.Network{config.NetworkECash, config.NetworkSignet, config.NetworkRegtest} {
		require.Empty(t, config.SidechainSeedPeerForNetwork("sidepot", network))
	}
}

// The release archive and the node inside it are pinned on every platform, so
// a changed download is refused.
func TestSidepotReleaseIsPinned(t *testing.T) {
	cfg, ok := BinaryConfigByName("sidepot")
	require.True(t, ok)
	require.Equal(t, 88, cfg.Slot)
	require.Equal(t, "sidepot-node", cfg.BinaryName)
	require.Equal(t, DownloadSourceDirect, cfg.DownloadSource)
	for _, platform := range []string{"linux-x86_64", "macos-x86_64", "macos-arm64", "windows-x86_64"} {
		require.NoError(t, checkArtifactPins(cfg, platform), platform)
	}
}
