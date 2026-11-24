package blocks

import (
	"context"
	"database/sql"
	"encoding/json"
	"errors"
	"fmt"
	"time"

	sq "github.com/Masterminds/squirrel"
	"github.com/btcsuite/btcd/chaincfg/chainhash"
	"github.com/rs/zerolog"

	"github.com/LayerTwo-Labs/sidesail/bitwindow/server/database"
)

func GetProcessedTip(ctx context.Context, db *sql.DB) (*ProcessedBlock, error) {
	query, args := selectProcessedBlock.OrderBy("height DESC").Limit(1).MustSql()
	pb, err := scanProcessedBlock(db.QueryRowContext(ctx, query, args...))
	switch {
	case errors.Is(err, sql.ErrNoRows):
		return nil, nil
	case err != nil:
		return nil, fmt.Errorf("query processed tip: %w", err)
	}
	return &pb, nil
}

// GetProcessedTipHash returns the hash of the highest processed block, or nil
// when no block is processed.
func GetProcessedTipHash(ctx context.Context, db *sql.DB) (*chainhash.Hash, error) {
	var raw string
	err := db.QueryRowContext(ctx, `SELECT block_hash FROM processed_blocks ORDER BY height DESC LIMIT 1`).Scan(&raw)
	switch {
	case errors.Is(err, sql.ErrNoRows):
		return nil, nil
	case err != nil:
		return nil, fmt.Errorf("query processed tip hash: %w", err)
	}
	hash, err := chainhash.NewHashFromStr(raw)
	if err != nil {
		return nil, fmt.Errorf("parse block hash: %w", err)
	}
	return hash, nil
}

var selectProcessedBlock = sq.
	Select("height", "block_hash", "txids", "block_time", "processed_at").
	From("processed_blocks").
	PlaceholderFormat(sq.Question)

func scanProcessedBlock(scanner interface{ Scan(dest ...any) error }) (ProcessedBlock, error) {
	var (
		pb           ProcessedBlock
		rawBlockHash string
		txidsJSON    string
	)
	if err := scanner.Scan(&pb.Height, &rawBlockHash, &txidsJSON, &pb.BlockTime, &pb.ProcessedAt); err != nil {
		return ProcessedBlock{}, err
	}

	hash, err := chainhash.NewHashFromStr(rawBlockHash)
	if err != nil {
		return ProcessedBlock{}, fmt.Errorf("parse block hash: %w", err)
	}
	pb.Hash = *hash

	if err := json.Unmarshal([]byte(txidsJSON), &pb.Txids); err != nil {
		return ProcessedBlock{}, fmt.Errorf("unmarshal txids: %w", err)
	}

	return pb, nil
}

func MarkBlocksProcessed(ctx context.Context, db *sql.DB, blocks []ProcessedBlock) error {
	if len(blocks) == 0 {
		return nil
	}

	start := time.Now()

	tx, err := db.BeginTx(ctx, nil)
	if err != nil {
		return fmt.Errorf("begin tx: %w", err)
	}
	defer database.SafeDefer(ctx, tx.Rollback)

	stmt, err := tx.PrepareContext(ctx, `
		INSERT INTO processed_blocks (height, block_hash, txids, block_time, processed_at)
		VALUES (?, ?, ?, ?, ?)
		ON CONFLICT(height) DO UPDATE SET block_hash=excluded.block_hash, txids=excluded.txids, block_time=excluded.block_time, processed_at=excluded.processed_at
	`)
	if err != nil {
		return fmt.Errorf("prepare stmt: %w", err)
	}
	defer database.SafeDefer(ctx, stmt.Close)

	var bestBlockHeight uint32
	for _, block := range blocks {
		bestBlockHeight = max(bestBlockHeight, block.Height)

		txidsJSON, err := json.Marshal(block.Txids)
		if err != nil {
			return fmt.Errorf("marshal txids: %w", err)
		}
		_, err = stmt.ExecContext(
			ctx, block.Height, block.Hash.String(),
			string(txidsJSON), block.BlockTime, time.Now(),
		)
		if err != nil {
			return fmt.Errorf("exec stmt: %w", err)
		}
	}

	if err := tx.Commit(); err != nil {
		return fmt.Errorf("commit tx: %w", err)
	}

	zerolog.Ctx(ctx).Debug().
		Msgf("blocks: marked %d as processed in %s, best block height: %d", len(blocks), time.Since(start), bestBlockHeight)

	return nil
}

// DeleteProcessedBlocksAtOrAboveTx drops every processed block from height up,
// so a chain that forked below it is re-scanned from the last common block.
func DeleteProcessedBlocksAtOrAboveTx(ctx context.Context, tx *sql.Tx, height uint32) error {
	if _, err := tx.ExecContext(ctx, `DELETE FROM processed_blocks WHERE height >= ?`, height); err != nil {
		return fmt.Errorf("delete processed blocks at or above %d: %w", height, err)
	}
	return nil
}

type ProcessedBlock struct {
	Height      uint32
	Hash        chainhash.Hash
	BlockTime   time.Time
	ProcessedAt time.Time
	Txids       []chainhash.Hash
}

func GetProcessedBlock(ctx context.Context, db *sql.DB, height uint32) (ProcessedBlock, error) {
	query, args := selectProcessedBlock.Where(sq.Eq{"height": height}).MustSql()
	pb, err := scanProcessedBlock(db.QueryRowContext(ctx, query, args...))
	if err != nil {
		return ProcessedBlock{}, fmt.Errorf("get processed block: %w", err)
	}
	return pb, nil
}

// GetProcessedBlockAtOrBelow returns the highest processed block at or below
// height. It returns sql.ErrNoRows when no such block exists.
func GetProcessedBlockAtOrBelow(ctx context.Context, db *sql.DB, height uint32) (ProcessedBlock, error) {
	query, args := selectProcessedBlock.Where(sq.LtOrEq{"height": height}).OrderBy("height DESC").Limit(1).MustSql()
	pb, err := scanProcessedBlock(db.QueryRowContext(ctx, query, args...))
	if err != nil {
		return ProcessedBlock{}, fmt.Errorf("get processed block at or below %d: %w", height, err)
	}
	return pb, nil
}

// Window is the processed blocks with a block time at or after a time.
type Window struct {
	Blocks int64 `db:"blocks"`
	// Transactions counts the non-coinbase transactions.
	Transactions int64 `db:"transactions"`
	// OldestUnix is the block time of the oldest block, in Unix seconds.
	OldestUnix int64 `db:"oldest"`
}

// Oldest returns the block time of the oldest block, or the zero time for no block.
func (w Window) Oldest() time.Time {
	if w.Blocks == 0 {
		return time.Time{}
	}
	return time.Unix(w.OldestUnix, 0)
}

// WindowSince returns the processed blocks with a block time at or after since.
// It compares whole seconds.
func WindowSince(ctx context.Context, db *sql.DB, since time.Time) (Window, error) {
	window, err := database.Get[Window](ctx, db, `
		SELECT COUNT(*) AS blocks,
		       COALESCE(SUM(json_array_length(txids)) - COUNT(*), 0) AS transactions,
		       COALESCE(CAST(strftime('%s', MIN(datetime(block_time))) AS INTEGER), 0) AS oldest
		FROM processed_blocks
		WHERE datetime(block_time) >= datetime(?)
	`, since)
	if err != nil {
		return Window{}, fmt.Errorf("read blocks since %s: %w", since, err)
	}
	return window, nil
}
