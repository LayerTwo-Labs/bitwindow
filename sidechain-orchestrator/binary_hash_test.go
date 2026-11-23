package orchestrator

import (
	"os"
	"path/filepath"
	"testing"
	"time"

	"github.com/stretchr/testify/require"
)

func TestStatusCarriesTheBinaryHash(t *testing.T) {
	dataDir := t.TempDir()
	config := makeSidechainConfig("http://127.0.0.1/")
	o := New(dataDir, "signet", t.TempDir(), []BinaryConfig{config}, testLogger(t))
	o.process.SidechainVariant = nil

	require.Empty(t, o.Status(config.Name).SHA256)

	path := BinaryPath(dataDir, config.BinaryName)
	require.NoError(t, os.MkdirAll(filepath.Dir(path), 0o755))
	require.NoError(t, os.WriteFile(path, []byte("binary"), 0o755))

	status := o.Status(config.Name)
	require.Empty(t, status.Error)
	require.Equal(t, sha256Hex([]byte("binary")), status.SHA256)
}

func TestFileHashCacheReadsTheFileAgainAfterAChange(t *testing.T) {
	path := filepath.Join(t.TempDir(), "bin")
	require.NoError(t, os.WriteFile(path, []byte("v1"), 0o755))
	var cache fileHashCache

	sum, err := cache.Hash(path)
	require.NoError(t, err)
	require.Equal(t, sha256Hex([]byte("v1")), sum)

	require.NoError(t, os.WriteFile(path, []byte("v2"), 0o755))
	later := time.Now().Add(time.Minute)
	require.NoError(t, os.Chtimes(path, later, later))

	sum, err = cache.Hash(path)
	require.NoError(t, err)
	require.Equal(t, sha256Hex([]byte("v2")), sum)
}

func TestFileHashCacheSkipsADirectory(t *testing.T) {
	var cache fileHashCache
	sum, err := cache.Hash(t.TempDir())
	require.NoError(t, err)
	require.Empty(t, sum)
}

func TestFileHashCacheReturnsAMissingFileError(t *testing.T) {
	var cache fileHashCache
	_, err := cache.Hash(filepath.Join(t.TempDir(), "missing"))
	require.Error(t, err)
}
