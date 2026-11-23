package orchestrator

import (
	"fmt"
	"os"
	"sync"
	"time"
)

// fileHashCache holds the SHA256 of each binary on disk. Status runs on each
// poll, so a file gets a new hash only after its size or mtime changes.
type fileHashCache struct {
	mu      sync.Mutex
	entries map[string]fileHashEntry
}

type fileHashEntry struct {
	size    int64
	modTime time.Time
	sum     string
}

// Hash returns the SHA256 of the file at path. A directory, such as a macOS
// app bundle, has no single hash and returns "".
func (c *fileHashCache) Hash(path string) (string, error) {
	info, err := os.Stat(path)
	if err != nil {
		return "", fmt.Errorf("hash %s: %w", path, err)
	}
	if !info.Mode().IsRegular() {
		return "", nil
	}

	c.mu.Lock()
	entry, ok := c.entries[path]
	c.mu.Unlock()
	if ok && entry.size == info.Size() && entry.modTime.Equal(info.ModTime()) {
		return entry.sum, nil
	}

	sum, _, err := hashFile(path)
	if err != nil {
		return "", fmt.Errorf("hash %s: %w", path, err)
	}

	c.mu.Lock()
	if c.entries == nil {
		c.entries = make(map[string]fileHashEntry)
	}
	c.entries[path] = fileHashEntry{size: info.Size(), modTime: info.ModTime(), sum: sum}
	c.mu.Unlock()
	return sum, nil
}
