package database

import (
	"context"
	"database/sql"
	"fmt"
)

// addDenialDelaySeed runs one time: it skips a table that has the delay_seed column.
func addDenialDelaySeed(ctx context.Context, db *sql.DB) error {
	var done bool
	if err := db.QueryRowContext(ctx, `
		SELECT EXISTS (SELECT 1 FROM pragma_table_info('denials') WHERE name = 'delay_seed')
	`).Scan(&done); err != nil {
		return fmt.Errorf("read denial columns: %w", err)
	}
	if done {
		return nil
	}
	tx, err := db.BeginTx(ctx, nil)
	if err != nil {
		return fmt.Errorf("begin denial delay seed: %w", err)
	}
	defer SafeDefer(ctx, tx.Rollback)
	if _, err := tx.ExecContext(ctx, `
		ALTER TABLE denials ADD COLUMN delay_seed INTEGER NOT NULL DEFAULT 0;
		UPDATE denials SET delay_seed = random();
	`); err != nil {
		return fmt.Errorf("add denial delay seed: %w", err)
	}
	if err := tx.Commit(); err != nil {
		return fmt.Errorf("commit denial delay seed: %w", err)
	}
	return nil
}
