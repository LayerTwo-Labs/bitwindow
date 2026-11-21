package main

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"strings"
	"sync"
)

// mailbox holds short values that one phone test leaves for the next one.
type mailbox struct {
	mu     sync.Mutex
	values map[string]string
}

// registerControl adds the test routes. They mine blocks and pay from the Core
// wallet, so they serve a test stack only.
// With an enforcerURL, the enforcer mines the blocks. Its coinbase then holds
// the BIP300 votes, and its blocks pay out a withdrawal bundle.
func registerControl(mux *http.ServeMux, core *coreRPC, x *index, wallet, enforcerURL string) {
	mux.HandleFunc("POST /regtest/mine", func(w http.ResponseWriter, r *http.Request) {
		var req struct {
			Blocks  int    `json:"blocks"`
			Address string `json:"address"`
		}
		if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
			http.Error(w, fmt.Sprintf("decode: %v", err), http.StatusBadRequest)
			return
		}
		if req.Blocks < 1 || req.Blocks > 1000 {
			http.Error(w, "blocks must be 1 to 1000", http.StatusBadRequest)
			return
		}
		if req.Address == "" {
			if err := core.call(r.Context(), wallet, "getnewaddress", nil, &req.Address); err != nil {
				http.Error(w, err.Error(), http.StatusBadGateway)
				return
			}
		}
		var hashes []string
		var err error
		if enforcerURL != "" {
			hashes, err = enforcerMine(r.Context(), enforcerURL, req.Blocks, req.Address)
		} else {
			err = core.call(r.Context(), "", "generatetoaddress", []any{req.Blocks, req.Address}, &hashes)
		}
		if err != nil {
			http.Error(w, err.Error(), http.StatusBadGateway)
			return
		}
		x.invalidate()
		writeJSON(w, map[string]any{"hashes": hashes})
	})

	mux.HandleFunc("POST /regtest/send", func(w http.ResponseWriter, r *http.Request) {
		var req struct {
			Address string      `json:"address"`
			Amount  json.Number `json:"amount_btc"`
		}
		if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
			http.Error(w, fmt.Sprintf("decode: %v", err), http.StatusBadRequest)
			return
		}
		if req.Address == "" || req.Amount == "" {
			http.Error(w, "give an address and amount_btc", http.StatusBadRequest)
			return
		}
		var txid string
		if err := core.call(r.Context(), wallet, "sendtoaddress", []any{req.Address, req.Amount}, &txid); err != nil {
			http.Error(w, err.Error(), http.StatusBadGateway)
			return
		}
		x.invalidate()
		writeJSON(w, map[string]any{"txid": txid})
	})

	mux.HandleFunc("GET /regtest/newaddress", func(w http.ResponseWriter, r *http.Request) {
		var addr string
		if err := core.call(r.Context(), wallet, "getnewaddress", nil, &addr); err != nil {
			http.Error(w, err.Error(), http.StatusBadGateway)
			return
		}
		writeJSON(w, map[string]any{"address": addr})
	})

	box := &mailbox{values: map[string]string{}}
	mux.HandleFunc("PUT /regtest/mailbox/{key}", func(w http.ResponseWriter, r *http.Request) {
		raw, err := io.ReadAll(io.LimitReader(r.Body, 4096))
		if err != nil {
			http.Error(w, err.Error(), http.StatusBadRequest)
			return
		}
		box.mu.Lock()
		box.values[r.PathValue("key")] = string(raw)
		box.mu.Unlock()
		writeJSON(w, map[string]any{})
	})
	mux.HandleFunc("GET /regtest/mailbox/{key}", func(w http.ResponseWriter, r *http.Request) {
		box.mu.Lock()
		value, ok := box.values[r.PathValue("key")]
		box.mu.Unlock()
		if !ok {
			http.Error(w, "no value", http.StatusNotFound)
			return
		}
		writeJSON(w, map[string]any{"value": value})
	})

	mux.HandleFunc("GET /regtest/tx/{txid}", func(w http.ResponseWriter, r *http.Request) {
		var out map[string]any
		if err := core.call(r.Context(), "", "getrawtransaction", []any{r.PathValue("txid"), 1}, &out); err != nil {
			http.Error(w, err.Error(), http.StatusNotFound)
			return
		}
		writeJSON(w, out)
	})
}

// enforcerMine calls MiningService/GenerateToAddress of the enforcer with the
// Connect protocol, and returns the hashes of the new blocks.
func enforcerMine(ctx context.Context, enforcerURL string, blocks int, address string) ([]string, error) {
	body, err := json.Marshal(map[string]any{"blocks": blocks, "address": address})
	if err != nil {
		return nil, err
	}
	req, err := http.NewRequestWithContext(ctx, http.MethodPost,
		strings.TrimSuffix(enforcerURL, "/")+"/cusf.mainchain.v1.MiningService/GenerateToAddress", bytes.NewReader(body))
	if err != nil {
		return nil, err
	}
	req.Header.Set("Content-Type", "application/json")
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		return nil, fmt.Errorf("enforcer generate: %w", err)
	}
	defer resp.Body.Close() //nolint:errcheck
	text, err := io.ReadAll(resp.Body)
	if err != nil {
		return nil, fmt.Errorf("enforcer generate: %w", err)
	}
	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("enforcer generate: %d %s", resp.StatusCode, text)
	}
	var out struct {
		BlockHashes []struct {
			Hex string `json:"hex"`
		} `json:"blockHashes"`
	}
	if err := json.Unmarshal(text, &out); err != nil {
		return nil, fmt.Errorf("enforcer generate: decode %s: %w", text, err)
	}
	if len(out.BlockHashes) != blocks {
		return nil, fmt.Errorf("enforcer generate: asked for %d blocks, got %d", blocks, len(out.BlockHashes))
	}
	hashes := make([]string, 0, len(out.BlockHashes))
	for _, hash := range out.BlockHashes {
		hashes = append(hashes, hash.Hex)
	}
	return hashes, nil
}
