package main

import (
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"sync"
)

// mailbox holds short values that one phone test leaves for the next one.
type mailbox struct {
	mu     sync.Mutex
	values map[string]string
}

// registerControl adds the test routes. They mine blocks and pay from the Core
// wallet, so they serve a test stack only.
func registerControl(mux *http.ServeMux, core *coreRPC, x *index, wallet string) {
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
		if err := core.call(r.Context(), "", "generatetoaddress", []any{req.Blocks, req.Address}, &hashes); err != nil {
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
