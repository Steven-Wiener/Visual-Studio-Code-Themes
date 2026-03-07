// theme_preview.go — Go syntax showcase
// Covers: interfaces, generics, goroutines, channels, error wrapping,
//         struct embedding, closures, defer, init, build tags

//go:build !windows

package main

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"log/slog"
	"math"
	"net/http"
	"os"
	"sync"
	"time"
)

// ── Constants & sentinel errors ───────────────────────────────────────────────
const (
	maxPaletteSize = 10
	minPaletteSize = 2
	defaultTimeout = 5 * time.Second
)

var (
	ErrNotFound    = errors.New("not found")
	ErrUnauthorized = errors.New("unauthorized")
	ErrInvalidInput = errors.New("invalid input")
)

// ── Types ─────────────────────────────────────────────────────────────────────
type HexColor string

func (h HexColor) String() string { return string(h) }

func (h HexColor) Validate() error {
	s := string(h)
	if len(s) != 7 || s[0] != '#' {
		return fmt.Errorf("%w: %q is not a valid hex colour", ErrInvalidInput, s)
	}
	return nil
}

type Status string

const (
	StatusDraft     Status = "draft"
	StatusPublished Status = "published"
	StatusArchived  Status = "archived"
)

type Theme struct {
	ID          string            `json:"id"`
	Name        string            `json:"name"`
	Palette     []HexColor        `json:"palette"`
	Colors      map[string]string `json:"colors"`
	Status      Status            `json:"status"`
	InstallCount int64            `json:"install_count"`
	CreatedAt   time.Time         `json:"created_at"`
	UpdatedAt   time.Time         `json:"updated_at"`
}

// ── Generic repository ────────────────────────────────────────────────────────
type Repository[T any, ID comparable] interface {
	Get(ctx context.Context, id ID) (T, error)
	List(ctx context.Context) ([]T, error)
	Save(ctx context.Context, item T) error
	Delete(ctx context.Context, id ID) error
}

type MemoryStore[T any, ID comparable] struct {
	mu   sync.RWMutex
	data map[ID]T
	keyFn func(T) ID
}

func NewMemoryStore[T any, ID comparable](keyFn func(T) ID) *MemoryStore[T, ID] {
	return &MemoryStore[T, ID]{data: make(map[ID]T), keyFn: keyFn}
}

func (s *MemoryStore[T, ID]) Get(_ context.Context, id ID) (T, error) {
	s.mu.RLock()
	defer s.mu.RUnlock()
	v, ok := s.data[id]
	if !ok {
		var zero T
		return zero, fmt.Errorf("%w: %v", ErrNotFound, id)
	}
	return v, nil
}

func (s *MemoryStore[T, ID]) List(_ context.Context) ([]T, error) {
	s.mu.RLock()
	defer s.mu.RUnlock()
	items := make([]T, 0, len(s.data))
	for _, v := range s.data {
		items = append(items, v)
	}
	return items, nil
}

func (s *MemoryStore[T, ID]) Save(_ context.Context, item T) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.data[s.keyFn(item)] = item
	return nil
}

func (s *MemoryStore[T, ID]) Delete(_ context.Context, id ID) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	delete(s.data, id)
	return nil
}

// ── Struct embedding ──────────────────────────────────────────────────────────
type Timestamped struct {
	CreatedAt time.Time `json:"created_at"`
	UpdatedAt time.Time `json:"updated_at"`
}

func (t *Timestamped) Touch() { t.UpdatedAt = time.Now() }

type User struct {
	Timestamped
	ID          string `json:"id"`
	Email       string `json:"email"`
	DisplayName string `json:"display_name"`
}

// ── Goroutines & channels ─────────────────────────────────────────────────────
func processBatch(ctx context.Context, items []string, workers int) <-chan struct {
	Item string
	Err  error
} {
	results := make(chan struct{ Item string; Err error }, len(items))
	sem     := make(chan struct{}, workers)

	var wg sync.WaitGroup
	for _, item := range items {
		item := item // capture
		wg.Add(1)
		go func() {
			defer wg.Done()
			sem <- struct{}{}
			defer func() { <-sem }()

			select {
			case <-ctx.Done():
				results <- struct{ Item string; Err error }{item, ctx.Err()}
			default:
				// simulate work
				time.Sleep(10 * time.Millisecond)
				results <- struct{ Item string; Err error }{item, nil}
			}
		}()
	}

	go func() { wg.Wait(); close(results) }()
	return results
}

// ── Functional helpers ─────────────────────────────────────────────────────────
func Map[A, B any](slice []A, fn func(A) B) []B {
	result := make([]B, len(slice))
	for i, v := range slice { result[i] = fn(v) }
	return result
}

func Filter[A any](slice []A, pred func(A) bool) []A {
	var result []A
	for _, v := range slice { if pred(v) { result = append(result, v) } }
	return result
}

func Reduce[A, B any](slice []A, init B, fn func(B, A) B) B {
	acc := init
	for _, v := range slice { acc = fn(acc, v) }
	return acc
}

// ── Fibonacci closure ─────────────────────────────────────────────────────────
func fibGenerator() func() int {
	a, b := 0, 1
	return func() int {
		v := a
		a, b = b, a+b
		return v
	}
}

// ── HTTP handler ──────────────────────────────────────────────────────────────
type ThemeHandler struct {
	store  Repository[Theme, string]
	logger *slog.Logger
}

func (h *ThemeHandler) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	ctx, cancel := context.WithTimeout(r.Context(), defaultTimeout)
	defer cancel()

	id := r.PathValue("id")
	theme, err := h.store.Get(ctx, id)
	if err != nil {
		switch {
		case errors.Is(err, ErrNotFound):
			http.Error(w, err.Error(), http.StatusNotFound)
		default:
			h.logger.ErrorContext(ctx, "failed to get theme", "id", id, "err", err)
			http.Error(w, "internal error", http.StatusInternalServerError)
		}
		return
	}

	w.Header().Set("Content-Type", "application/json")
	if err := json.NewEncoder(w).Encode(theme); err != nil {
		h.logger.ErrorContext(ctx, "encode error", "err", err)
	}
}

// ── init ──────────────────────────────────────────────────────────────────────
func init() {
	slog.SetDefault(slog.New(slog.NewJSONHandler(os.Stdout, &slog.HandlerOptions{
		Level: slog.LevelDebug,
	})))
}

// ── Main ───────────────────────────────────────────────────────────────────────
func main() {
	ctx := context.Background()
	store := NewMemoryStore(func(t Theme) string { return t.ID })

	// Save some themes
	themes := []Theme{
		{ID: "neon-vomit-night", Name: "Neon Vomit Night", Status: StatusPublished,
			Palette:   []HexColor{"#070425", "#9900FF", "#09FBD3", "#5CB800"},
			CreatedAt: time.Now(), UpdatedAt: time.Now()},
		{ID: "teal-steel", Name: "Teal Steel", Status: StatusPublished,
			Palette:   []HexColor{"#004d4d", "#ff79c6", "#50fa7b", "#f1fa8c"},
			CreatedAt: time.Now(), UpdatedAt: time.Now()},
	}

	for _, t := range themes {
		if err := store.Save(ctx, t); err != nil {
			slog.Error("save failed", "err", err)
		}
	}

	// List & transform
	all, _ := store.List(ctx)
	names  := Map(all, func(t Theme) string { return t.Name })
	published := Filter(all, func(t Theme) bool { return t.Status == StatusPublished })
	totalInstalls := Reduce(all, int64(0), func(acc int64, t Theme) int64 { return acc + t.InstallCount })

	fmt.Println("Names:", names)
	fmt.Printf("Published: %d/%d, Total installs: %d\n", len(published), len(all), totalInstalls)

	// Fibonacci
	next := fibGenerator()
	fibs := make([]int, 12)
	for i := range fibs { fibs[i] = next() }
	fmt.Println("Fibonacci:", fibs)

	// Concurrent batch processing
	batchCtx, cancel := context.WithTimeout(ctx, 2*time.Second)
	defer cancel()

	ids := []string{"id-1", "id-2", "id-3", "id-4", "id-5"}
	for res := range processBatch(batchCtx, ids, 3) {
		if res.Err != nil {
			slog.Error("batch item failed", "item", res.Item, "err", res.Err)
		} else {
			slog.Debug("processed", "item", res.Item)
		}
	}

	// Math
	for _, r := range []float64{1, 2, 3, 5} {
		fmt.Printf("  circle(r=%.0f) area=%.4f\n", r, math.Pi*r*r)
	}
}
