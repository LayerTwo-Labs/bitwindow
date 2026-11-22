package database

import (
	"testing"

	"github.com/stretchr/testify/require"
)

func TestAddDenialDelaySeedGivesOldDenialsASeed(t *testing.T) {
	ctx := t.Context()
	db := Test(t)

	_, err := db.ExecContext(ctx, `ALTER TABLE denials DROP COLUMN delay_seed`)
	require.NoError(t, err)
	_, err = db.ExecContext(ctx, `INSERT INTO denials (wallet_id, initial_txid, initial_vout, delay_duration, num_hops, created_at)
		VALUES ('w', 'a', 0, 3600, 3, '2026-08-18 10:00:00'), ('w', 'b', 0, 3600, 3, '2026-08-18 10:00:00')`)
	require.NoError(t, err)

	require.NoError(t, addDenialDelaySeed(ctx, db))
	require.NoError(t, addDenialDelaySeed(ctx, db))

	var zero, distinct int
	require.NoError(t, db.QueryRowContext(ctx, `
		SELECT COUNT(*) FILTER (WHERE delay_seed = 0), COUNT(DISTINCT delay_seed) FROM denials
	`).Scan(&zero, &distinct))
	require.Zero(t, zero)
	require.Equal(t, 2, distinct)
}
