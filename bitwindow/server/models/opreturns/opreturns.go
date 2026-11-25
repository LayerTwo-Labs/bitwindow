package opreturns

import (
	"context"
	"database/sql"
	"encoding/hex"
	"errors"
	"fmt"
	"slices"
	"strings"
	"sync"
	"time"
	"unicode"
	"unicode/utf8"

	sq "github.com/Masterminds/squirrel"
	"github.com/btcsuite/btcd/btcutil"
	"github.com/rs/zerolog"
	"github.com/samber/lo"

	"github.com/LayerTwo-Labs/sidesail/bitwindow/server/database"
	cnstore "github.com/LayerTwo-Labs/sidesail/bitwindow/server/models/coinnews"
	codec "github.com/LayerTwo-Labs/sidesail/coinnews/codec"
)

// Persist clears the caches. The TTL covers a query that races a write.
const listCacheTTL = 2 * time.Second

// The *sql.DB key keeps the caches of parallel tests apart.

type listCacheEntry struct {
	rows []OPReturn
	at   time.Time
}

type coinNewsCacheEntry struct {
	rows []CoinNews
	at   time.Time
}

var (
	listCacheMu      sync.RWMutex
	listCacheEntries = map[*sql.DB]map[int]listCacheEntry{}

	coinNewsCacheMu      sync.RWMutex
	coinNewsCacheEntries = map[*sql.DB]coinNewsCacheEntry{}
)

// invalidateCaches drops cached List / ListCoinNews entries for db.
// Called from Persist.
func invalidateCaches(db *sql.DB) {
	listCacheMu.Lock()
	delete(listCacheEntries, db)
	listCacheMu.Unlock()

	InvalidateCoinNewsCache(db)
}

func InvalidateCoinNewsCache(db *sql.DB) {
	coinNewsCacheMu.Lock()
	delete(coinNewsCacheEntries, db)
	coinNewsCacheMu.Unlock()
}

func Persist(
	ctx context.Context, db *sql.DB, values []OPReturn,
) error {
	if len(values) == 0 {
		return nil
	}

	start := time.Now()
	builder := sq.
		Insert("op_returns").
		Columns("txid", "vout", "op_return_data", "fee_sats", "height", "created_at", "explorer_message")

	for _, value := range values {
		createdAt := time.Now()
		if value.CreatedAt != nil {
			createdAt = *value.CreatedAt
		}
		builder = builder.Values(
			value.TxID, value.Vout,
			hex.EncodeToString(value.Data),
			value.Fee, value.Height, createdAt, value.ExplorerMessage,
		)
	}

	builder = builder.Suffix(
		`ON CONFLICT (txid, vout) DO UPDATE SET 
			op_return_data = excluded.op_return_data,
			explorer_message = excluded.explorer_message,
			height = COALESCE(excluded.height, op_returns.height), 
			-- Zero reads as unknown: a scan on a node with no txindex cannot
			-- fetch the fee, and must not erase one the mempool already gave us.
			fee_sats = COALESCE(NULLIF(excluded.fee_sats, 0), op_returns.fee_sats),
			created_at = CASE
				WHEN excluded.height IS NOT NULL THEN excluded.created_at
				ELSE op_returns.created_at
			END`,
	)

	sql, args := builder.MustSql()
	if _, err := db.ExecContext(ctx, sql, args...); err != nil {
		return fmt.Errorf("persist %d OP_RETURN(s): %w", len(values), err)
	}

	invalidateCaches(db)

	zerolog.Ctx(ctx).Debug().
		Msgf("opreturns: persisted %d OP_RETURN(s) in %s", len(values), time.Since(start))

	return nil
}

type OPReturn struct {
	ID              int64          `db:"id"`
	TxID            string         `db:"txid"`
	Vout            int32          `db:"vout"`
	Data            []byte         `db:"op_return_data"`
	ExplorerMessage *string        `db:"explorer_message"`
	Fee             btcutil.Amount `db:"fee_sats"` // 0 can either mean zero fee or unknown fee
	Height          *uint32        `db:"height"`
	CreatedAt       *time.Time     `db:"created_at"`
}

// Message returns the text or hex that the explorer shows.
func (o OPReturn) Message() string {
	if o.ExplorerMessage != nil {
		return *o.ExplorerMessage
	}
	return OPReturnToReadable(o.Data)
}

// GetByTxID returns the OP_RETURN of the transaction with the lowest vout, or nil
// when the transaction has none.
func GetByTxID(ctx context.Context, db *sql.DB, txid string) (*OPReturn, error) {
	opReturn, err := database.Get[OPReturn](ctx, db, `
		SELECT id, txid, vout, unhex(op_return_data) AS op_return_data, fee_sats, height, created_at
		FROM op_returns
		WHERE txid = ?
		ORDER BY vout
		LIMIT 1
	`, txid)
	switch {
	case errors.Is(err, sql.ErrNoRows):
		return nil, nil
	case err != nil:
		return nil, fmt.Errorf("get op_return %s: %w", txid, err)
	}
	return &opReturn, nil
}

// List returns the newest OP_RETURNs first, at most limit rows. A limit of 0 or less returns all rows.
// Do not change the returned values: the cache shares them.
func List(ctx context.Context, db *sql.DB, limit int) ([]OPReturn, error) {
	listCacheMu.RLock()
	cached, hit := listCacheEntries[db][limit]
	listCacheMu.RUnlock()
	if hit && time.Since(cached.at) < listCacheTTL {
		out := make([]OPReturn, len(cached.rows))
		copy(out, cached.rows)
		return out, nil
	}

	query := `
		SELECT id, txid, vout, unhex(op_return_data) AS op_return_data, fee_sats, height, created_at
		FROM op_returns
		ORDER BY created_at DESC
	`
	args := []any{}
	if limit > 0 {
		query += "\nLIMIT ?"
		args = append(args, limit)
	}

	opReturns, err := database.Select[OPReturn](ctx, db, query, args...)
	if err != nil {
		return nil, fmt.Errorf("list op_returns: %w", err)
	}

	snapshot := make([]OPReturn, len(opReturns))
	copy(snapshot, opReturns)
	listCacheMu.Lock()
	byLimit, ok := listCacheEntries[db]
	if !ok {
		byLimit = map[int]listCacheEntry{}
		listCacheEntries[db] = byLimit
	}
	byLimit[limit] = listCacheEntry{rows: snapshot, at: time.Now()}
	listCacheMu.Unlock()

	return opReturns, nil
}

// SortColumn selects the order of Query.
type SortColumn int

const (
	SortByTime SortColumn = iota
	SortByHeight
	SortByFee
	SortByTxID
	SortByMessage
)

var sortColumns = map[SortColumn]string{
	SortByTime:    "julianday(created_at)",
	SortByHeight:  "height",
	SortByFee:     "fee_sats",
	SortByTxID:    "txid",
	SortByMessage: "id",
}

// Filter selects the rows of Query. A zero Filter returns the newest rows first.
type Filter struct {
	// Search is text that the readable message or the txid holds, with no case match.
	Search string
	// From and To bound the create time: From <= created_at < To. A zero time sets no bound.
	From, To  time.Time
	Sort      SortColumn
	Ascending bool
}

// Query returns at most limit OP_RETURNs that match the filter, in the filter order.
// A limit of 0 or less returns all matches.
func Query(ctx context.Context, db *sql.DB, filter Filter, limit int) ([]OPReturn, error) {
	column, ok := sortColumns[filter.Sort]
	if !ok {
		return nil, fmt.Errorf("unknown sort column %d", filter.Sort)
	}
	direction := "DESC"
	if filter.Ascending {
		direction = "ASC"
	}

	var where []string
	var args []any
	// datetime() reads each stored zone offset, so rows from other offsets compare right.
	if !filter.From.IsZero() {
		where = append(where, "datetime(created_at) >= datetime(?)")
		args = append(args, filter.From.UTC().Format(time.DateTime))
	}
	if !filter.To.IsZero() {
		where = append(where, "datetime(created_at) < datetime(?)")
		args = append(args, filter.To.UTC().Format(time.DateTime))
	}
	query := "SELECT id, txid, vout, unhex(op_return_data) AS op_return_data, explorer_message, fee_sats, height, created_at FROM op_returns"
	if len(where) > 0 {
		query += " WHERE " + strings.Join(where, " AND ")
	}
	query += fmt.Sprintf(" ORDER BY %s %s, id %s", column, direction, direction)

	var keep func(OPReturn) bool
	if search := strings.ToLower(filter.Search); search != "" {
		keep = func(o OPReturn) bool {
			return strings.Contains(strings.ToLower(o.TxID), search) ||
				strings.Contains(strings.ToLower(o.Message()), search)
		}
	}

	if filter.Sort != SortByMessage {
		opReturns, err := database.SelectMatching(ctx, db, max(limit, 0), keep, query, args...)
		if err != nil {
			return nil, fmt.Errorf("query op_returns: %w", err)
		}
		return opReturns, nil
	}

	// The shown message is decoded in Go, so SQL cannot sort by it.
	opReturns, err := database.SelectMatching(ctx, db, 0, keep, query, args...)
	if err != nil {
		return nil, fmt.Errorf("query op_returns: %w", err)
	}
	slices.SortStableFunc(opReturns, func(a, b OPReturn) int {
		order := strings.Compare(a.Message(), b.Message())
		if !filter.Ascending {
			order = -order
		}
		return order
	})
	if limit > 0 && len(opReturns) > limit {
		opReturns = opReturns[:limit]
	}
	return opReturns, nil
}

// ForgetPending removes the unconfirmed outputs for a transaction.
func ForgetPending(ctx context.Context, db *sql.DB, txid string) error {
	result, err := db.ExecContext(ctx, `DELETE FROM op_returns WHERE txid = ? AND height IS NULL`, txid)
	if err != nil {
		return fmt.Errorf("delete pending OP_RETURNs for %s: %w", txid, err)
	}
	count, err := result.RowsAffected()
	if err != nil {
		return fmt.Errorf("count deleted OP_RETURNs for %s: %w", txid, err)
	}
	if count > 0 {
		invalidateCaches(db)
	}
	return nil
}

// PruneMempool drops pending OP_RETURNs absent from Core's mempool.
func PruneMempool(ctx context.Context, db *sql.DB, mempoolTxIDs func() ([]string, error)) error {
	candidates, err := database.Select[string](ctx, db, `
		SELECT DISTINCT txid FROM op_returns WHERE height IS NULL
	`)
	if err != nil {
		return fmt.Errorf("select pending OP_RETURNs: %w", err)
	}
	if len(candidates) == 0 {
		return nil
	}

	txids, err := mempoolTxIDs()
	if err != nil {
		return fmt.Errorf("read mempool: %w", err)
	}
	live := lo.Keyify(txids)
	for _, txid := range candidates {
		if _, found := live[txid]; found {
			continue
		}
		if err := ForgetPending(ctx, db, txid); err != nil {
			return err
		}
	}
	return nil
}

// OPReturnToReadable returns printable UTF-8 as text and other bytes as hex.
func OPReturnToReadable(data []byte) string {
	if isPrintableText(data) {
		return string(data)
	}
	return hex.EncodeToString(data)
}

func isPrintableText(b []byte) bool {
	if !utf8.Valid(b) {
		return false
	}
	for _, r := range string(b) {
		if !unicode.IsPrint(r) && !unicode.IsSpace(r) {
			return false
		}
	}
	return true
}

func ValidNewsTopicID(topic string) (TopicID, error) {
	if topic == "" {
		return TopicID{}, errors.New("topic ID is empty")
	}

	decode, err := hex.DecodeString(topic)
	if err != nil {
		return TopicID{}, fmt.Errorf("topic ID %q is not hex: %w", topic, err)
	}

	if len(decode) != TopicIdLength {
		return TopicID{}, fmt.Errorf("topic ID %q is not 4 bytes: %d", topic, len(decode))
	}

	return TopicID(decode), nil
}

const TopicIdLength = 4

type Topic struct {
	ID            int64
	Topic         TopicID
	Name          string
	Confirmed     bool
	Txid          string
	RetentionDays int32

	// CreatedAt is zero for a topic with no known creation time.
	CreatedAt time.Time
}

type CoinNews struct {
	ID        int64
	Topic     TopicID
	TopicName string
	Headline  string
	Content   string
	Fee       btcutil.Amount
	ItemID    string // hex-encoded 12-byte ItemID; comment parent
	URL       string // optional link (TLV §10)
	Subtype   int32  // 0=link,1=text,2=ask,3=show,4=poll,5=job
	NSFW      bool
	TxID      string
	Vout      uint32

	CreatedAt *time.Time
}

// ListTopics returns the confirmed topics, then each topic whose creation
// waits in the mempool. The earliest creation of a topic wins.
func ListTopics(ctx context.Context, db *sql.DB) ([]Topic, error) {
	topics, err := listConfirmedTopics(ctx, db)
	if err != nil {
		return nil, err
	}
	pending, err := listPendingTopics(ctx, db)
	if err != nil {
		return nil, err
	}
	known := lo.SliceToMap(topics, func(t Topic) (TopicID, bool) { return t.Topic, true })
	for _, topic := range pending {
		if known[topic.Topic] {
			continue
		}
		known[topic.Topic] = true
		topics = append(topics, topic)
	}
	return topics, nil
}

func listConfirmedTopics(ctx context.Context, db *sql.DB) ([]Topic, error) {
	rows, err := db.QueryContext(ctx, `
	SELECT rowid, topic, name, COALESCE(txid, ''), retention_days,
		(SELECT i.block_time FROM cn_items i WHERE i.txid = cn_topics.txid ORDER BY i.block_time ASC LIMIT 1) AS created_at
	FROM cn_topics
	ORDER BY created_at ASC, rowid ASC
`)
	if err != nil {
		return nil, fmt.Errorf("list topics: query: %w", err)
	}
	defer database.SafeDefer(ctx, rows.Close)

	var topics []Topic
	for rows.Next() {
		topic := Topic{Confirmed: true}
		var createdAt sql.NullTime
		err := rows.Scan(&topic.ID, &topic.Topic, &topic.Name, &topic.Txid, &topic.RetentionDays, &createdAt)
		if err != nil {
			return nil, fmt.Errorf("list topics: scan: %w", err)
		}
		if createdAt.Valid {
			topic.CreatedAt = createdAt.Time
		}

		topics = append(topics, topic)
	}

	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("list topics: iterate: %w", err)
	}

	return topics, nil
}

// listPendingTopics returns the topic creations in the mempool, the first seen first.
func listPendingTopics(ctx context.Context, db *sql.DB) ([]Topic, error) {
	rows, err := listPendingOPReturns(ctx, db)
	if err != nil {
		return nil, fmt.Errorf("list pending topics: %w", err)
	}

	var out []Topic
	for _, row := range rows {
		_, msg, err := codec.DecodeMessage(row.Data)
		if err != nil {
			continue
		}
		creation, ok := msg.(*codec.TopicCreation)
		if !ok {
			continue
		}
		out = append(out, Topic{
			ID:            row.ID,
			Topic:         TopicID(creation.Topic),
			Name:          creation.Name,
			Txid:          row.TxID,
			RetentionDays: int32(creation.RetentionDays),
			CreatedAt:     lo.FromPtr(row.CreatedAt),
		})
	}
	return out, nil
}

// listPendingOPReturns returns the OP_RETURNs in the mempool, the first seen first.
func listPendingOPReturns(ctx context.Context, db *sql.DB) ([]OPReturn, error) {
	return database.Select[OPReturn](ctx, db, `
		SELECT id, txid, vout, unhex(op_return_data) AS op_return_data, fee_sats, height, created_at
		FROM op_returns
		WHERE height IS NULL
		ORDER BY created_at ASC, id ASC
	`)
}

// TopicExists reports whether a block or the mempool holds a creation of the topic.
func TopicExists(ctx context.Context, db *sql.DB, topic TopicID) (bool, error) {
	topics, err := ListTopics(ctx, db)
	if err != nil {
		return false, fmt.Errorf("topic exists: %w", err)
	}
	return lo.ContainsBy(topics, func(t Topic) bool { return t.Topic == topic }), nil
}

// EncodeNewsMessageNewFormat produces the current CoinNews Story wire
// format used by BroadcastNews and decoded by the cn_* block parser.
func EncodeNewsMessageNewFormat(topic TopicID, headline string, content string) ([]byte, error) {
	return EncodeNewsMessageWithOptions(topic, headline, content, StoryOptions{})
}

// StoryOptions holds the optional Story TLVs (spec §6, §10): a link
// URL, language, content subtype, and the NSFW flag.
type StoryOptions struct {
	URL     string
	Lang    string
	Subtype int32
	NSFW    bool
}

// EncodeNewsMessageWithOptions builds a Story payload with the body and
// any provided optional TLVs, in the canonical order body, url, lang,
// subtype, nsfw.
func EncodeNewsMessageWithOptions(topic TopicID, headline, content string, opts StoryOptions) ([]byte, error) {
	var t codec.Topic
	copy(t[:], topic[:])
	story := codec.Story{Topic: t, Headline: headline}
	if content != "" {
		story.TLVs = append(story.TLVs, codec.TLV{Tag: codec.TLVBody, Value: []byte(content)})
	}
	if opts.URL != "" {
		story.TLVs = append(story.TLVs, codec.TLV{Tag: codec.TLVURL, Value: []byte(opts.URL)})
	}
	if opts.Lang != "" {
		story.TLVs = append(story.TLVs, codec.TLV{Tag: codec.TLVLang, Value: []byte(opts.Lang)})
	}
	if opts.Subtype != 0 {
		story.TLVs = append(story.TLVs, codec.TLV{Tag: codec.TLVSubtype, Value: []byte{byte(opts.Subtype)}})
	}
	if opts.NSFW {
		story.TLVs = append(story.TLVs, codec.TLV{Tag: codec.TLVNSFW, Value: []byte{0x01}})
	}
	return codec.EncodeStory(story)
}

// EncodeTopicCreationMessageNewFormat produces the current CoinNews
// TopicCreation wire format. Retention days are clamped to the
// single-byte field.
func EncodeTopicCreationMessageNewFormat(topic TopicID, name string, retentionDays int32) ([]byte, error) {
	if retentionDays < 0 {
		retentionDays = 0
	}
	if retentionDays > 255 {
		retentionDays = 255
	}
	var t codec.Topic
	copy(t[:], topic[:])
	return codec.EncodeTopicCreation(codec.TopicCreation{
		Topic:         t,
		RetentionDays: byte(retentionDays),
		Name:          name,
	})
}

type TopicID [TopicIdLength]byte

func (t TopicID) String() string {
	return hex.EncodeToString(t[:])
}

func (t *TopicID) Scan(src any) error {
	b, ok := src.([]byte)
	if !ok {
		return fmt.Errorf("topic ID is %T, want []byte", src)
	}
	if len(b) != TopicIdLength {
		return fmt.Errorf("topic ID %x is %d bytes, want %d", b, len(b), TopicIdLength)
	}
	copy(t[:], b)
	return nil
}

// ListCoinNews returns articles from the canonical CoinNews tables.
func ListCoinNews(ctx context.Context, db *sql.DB) ([]CoinNews, error) {
	coinNewsCacheMu.RLock()
	cached, hit := coinNewsCacheEntries[db]
	coinNewsCacheMu.RUnlock()
	if hit && time.Since(cached.at) < listCacheTTL {
		out := make([]CoinNews, len(cached.rows))
		copy(out, cached.rows)
		return out, nil
	}

	coinNews, err := listCoinNewsNewFormat(ctx, db)
	if err != nil {
		return nil, err
	}
	rankCoinNews(coinNews)

	snapshot := make([]CoinNews, len(coinNews))
	copy(snapshot, coinNews)
	coinNewsCacheMu.Lock()
	coinNewsCacheEntries[db] = coinNewsCacheEntry{rows: snapshot, at: time.Now()}
	coinNewsCacheMu.Unlock()

	return coinNews, nil
}

func listCoinNewsNewFormat(ctx context.Context, db *sql.DB) ([]CoinNews, error) {
	type storyRow struct {
		ID        int64          `db:"id"`
		Topic     TopicID        `db:"topic"`
		TopicName string         `db:"topic_name"`
		Headline  string         `db:"headline"`
		Content   string         `db:"content"`
		Fee       btcutil.Amount `db:"fee"`
		BlockTime time.Time      `db:"block_time"`
		ItemID    string         `db:"item_id"`
		RawTLV    []byte         `db:"raw_tlv"`
		URL       string         `db:"url"`
		Subtype   int32          `db:"subtype"`
		NSFW      bool           `db:"nsfw"`
		TxID      string         `db:"txid"`
		Vout      uint32         `db:"vout"`
	}
	rows, err := database.Select[storyRow](ctx, db, `
		SELECT
			i.rowid AS id,
			s.topic AS topic,
			COALESCE(ct.name, '') AS topic_name,
			s.headline AS headline,
			COALESCE(s.body, '') AS content,
			COALESCE(o.fee_sats, 0) AS fee,
			i.block_time AS block_time,
			lower(hex(s.item_id)) AS item_id,
			COALESCE(s.raw_tlv, x'') AS raw_tlv,
			COALESCE(s.url, '') AS url,
			s.subtype AS subtype,
			s.nsfw AS nsfw,
			i.txid AS txid,
			i.vout AS vout
		FROM cn_stories s
		JOIN cn_items i ON i.item_id = s.item_id
		LEFT JOIN cn_topics ct ON ct.topic = s.topic
		LEFT JOIN op_returns o ON o.txid = i.txid AND o.vout = i.vout
		WHERE
			trim(s.headline) != ''
			AND
			CASE
				WHEN ct.topic IS NOT NULL THEN
					ct.retention_days = 0
					OR datetime(i.block_time) >= datetime('now', '-' || ct.retention_days || ' days')
				ELSE 1
			END
	`)
	if err != nil {
		return nil, fmt.Errorf("list coin news: query new-format stories: %w", err)
	}

	type continuationTarget struct {
		idx    int
		itemID string
		rawTLV []byte
	}
	var out []CoinNews
	var toReassemble []continuationTarget
	for _, row := range rows {
		if strings.TrimSpace(row.Headline) == "" {
			continue
		}
		blockTime := row.BlockTime
		out = append(out, CoinNews{
			ID:        row.ID,
			Topic:     row.Topic,
			TopicName: row.TopicName,
			Headline:  row.Headline,
			Content:   row.Content,
			Fee:       row.Fee,
			ItemID:    row.ItemID,
			URL:       row.URL,
			Subtype:   row.Subtype,
			NSFW:      row.NSFW,
			TxID:      row.TxID,
			Vout:      row.Vout,
			CreatedAt: &blockTime,
		})
		toReassemble = append(toReassemble, continuationTarget{idx: len(out) - 1, itemID: row.ItemID, rawTLV: row.RawTLV})
	}

	heads, err := database.Select[string](ctx, db, `SELECT DISTINCT lower(hex(head_id)) FROM cn_continuations`)
	if err != nil {
		return nil, fmt.Errorf("list coin news: select continuation heads: %w", err)
	}
	headSet := lo.Keyify(heads)
	invalid := make(map[int]bool)
	for _, t := range toReassemble {
		if _, ok := headSet[t.itemID]; !ok {
			continue
		}
		tlvs, err := reassembledTLVs(ctx, db, t.itemID, t.rawTLV)
		if errors.Is(err, cnstore.ErrInvalidContinuation) {
			invalid[t.idx] = true
			continue
		}
		if err != nil {
			return nil, fmt.Errorf("list coin news: %w", err)
		}
		if body := codec.FindFirst(tlvs, codec.TLVBody); body != nil {
			out[t.idx].Content = string(body.Value)
		}
		if url := codec.FindFirst(tlvs, codec.TLVURL); url != nil {
			out[t.idx].URL = string(url.Value)
		}
		if subtype := codec.FindFirst(tlvs, codec.TLVSubtype); subtype != nil && len(subtype.Value) > 0 {
			out[t.idx].Subtype = int32(subtype.Value[0])
		}
		if nsfw := codec.FindFirst(tlvs, codec.TLVNSFW); nsfw != nil {
			out[t.idx].NSFW = len(nsfw.Value) > 0 && nsfw.Value[0] != 0
		}
	}
	return lo.Filter(out, func(_ CoinNews, i int) bool { return !invalid[i] }), nil
}

// ListPendingCoinNews returns the stories in the mempool, with the fee the
// mempool gave. They have no ItemID: a comment needs a confirmed parent.
func ListPendingCoinNews(ctx context.Context, db *sql.DB) ([]CoinNews, error) {
	rows, err := listPendingOPReturns(ctx, db)
	if err != nil {
		return nil, fmt.Errorf("list pending coin news: %w", err)
	}

	var out []CoinNews
	for _, row := range rows {
		_, msg, err := codec.DecodeMessage(row.Data)
		if err != nil {
			continue
		}
		story, ok := msg.(*codec.Story)
		if !ok || strings.TrimSpace(story.Headline) == "" {
			continue
		}
		url, body, _, nsfw, _, subtype := cnstore.ExtractStoryTLV(story.TLVs)
		out = append(out, CoinNews{
			ID:        row.ID,
			Topic:     TopicID(story.Topic),
			Headline:  story.Headline,
			Content:   body,
			Fee:       row.Fee,
			URL:       url,
			Subtype:   int32(subtype),
			NSFW:      nsfw,
			TxID:      row.TxID,
			Vout:      uint32(row.Vout),
			CreatedAt: row.CreatedAt,
		})
	}
	return out, nil
}

func reassembledTLVs(ctx context.Context, db *sql.DB, itemIDHex string, rawTLV []byte) ([]codec.TLV, error) {
	raw, err := hex.DecodeString(itemIDHex)
	if err != nil {
		return nil, fmt.Errorf("decode item id %q: %w", itemIDHex, err)
	}
	if len(raw) != codec.ItemIDLen {
		return nil, fmt.Errorf("item id %q is %d bytes, want %d", itemIDHex, len(raw), codec.ItemIDLen)
	}
	var headID codec.ItemID
	copy(headID[:], raw)

	tlvs, err := cnstore.ReassembleTLVs(ctx, db, headID, rawTLV)
	if err != nil {
		return nil, fmt.Errorf("reassemble story %s: %w", itemIDHex, err)
	}
	return tlvs, nil
}

// rankCoinNews orders the feed by descending §13 score, breaking ties
// with the newer item first.
func rankCoinNews(news []CoinNews) {
	slices.SortFunc(news, func(a, b CoinNews) int {
		if a.Fee != b.Fee {
			if a.Fee > b.Fee {
				return -1
			}
			return 1
		}
		at, bt := time.Time{}, time.Time{}
		if a.CreatedAt != nil {
			at = *a.CreatedAt
		}
		if b.CreatedAt != nil {
			bt = *b.CreatedAt
		}
		switch {
		case at.After(bt):
			return -1
		case bt.After(at):
			return 1
		default:
			return 0
		}
	})
}
