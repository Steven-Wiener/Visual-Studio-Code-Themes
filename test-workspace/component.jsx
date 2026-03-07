/**
 * theme_preview.jsx — React/JSX syntax showcase
 * Covers: hooks, context, custom hooks, forwardRef, memo,
 *         compound components, render props, error boundaries
 */

import { createContext, forwardRef, memo, useCallback, useContext,
         useEffect, useId, useReducer, useRef, useState } from 'react';

// ── Context ───────────────────────────────────────────────────────────────────
const ThemeContext = createContext(null);

function ThemeProvider({ children, initialTheme = 'dark' }) {
  const [theme, setTheme] = useState(initialTheme);
  const toggle = useCallback(() =>
    setTheme(t => t === 'dark' ? 'light' : 'dark'), []);

  return (
    <ThemeContext.Provider value={{ theme, toggle }}>
      <div data-theme={theme} style={{ colorScheme: theme }}>
        {children}
      </div>
    </ThemeContext.Provider>
  );
}

function useTheme() {
  const ctx = useContext(ThemeContext);
  if (!ctx) throw new Error('useTheme must be used inside <ThemeProvider>');
  return ctx;
}

// ── Reducer ───────────────────────────────────────────────────────────────────
const initialState = { palette: [], themeName: '', loading: false, error: null };

function themeReducer(state, action) {
  switch (action.type) {
    case 'SET_COLOR':     return { ...state, palette: state.palette.map((c, i) => i === action.index ? action.color : c) };
    case 'ADD_COLOR':     return state.palette.length < 10 ? { ...state, palette: [...state.palette, action.color] } : state;
    case 'REMOVE_COLOR':  return { ...state, palette: state.palette.filter((_, i) => i !== action.index) };
    case 'SET_NAME':      return { ...state, themeName: action.name };
    case 'LOAD_START':    return { ...state, loading: true, error: null };
    case 'LOAD_SUCCESS':  return { ...state, loading: false };
    case 'LOAD_ERROR':    return { ...state, loading: false, error: action.error };
    case 'RESET':         return initialState;
    default:              return state;
  }
}

// ── Custom hooks ──────────────────────────────────────────────────────────────
function useLocalStorage(key, initial) {
  const [value, setValue] = useState(() => {
    try { return JSON.parse(localStorage.getItem(key) ?? 'null') ?? initial; }
    catch { return initial; }
  });

  useEffect(() => {
    try { localStorage.setItem(key, JSON.stringify(value)); }
    catch { /* quota exceeded */ }
  }, [key, value]);

  return [value, setValue];
}

function useDebounce(value, delay = 300) {
  const [debounced, setDebounced] = useState(value);
  useEffect(() => {
    const timer = setTimeout(() => setDebounced(value), delay);
    return () => clearTimeout(timer);
  }, [value, delay]);
  return debounced;
}

function useClickOutside(ref, handler) {
  useEffect(() => {
    const listener = e => { if (!ref.current?.contains(e.target)) handler(e); };
    document.addEventListener('pointerdown', listener);
    return () => document.removeEventListener('pointerdown', listener);
  }, [ref, handler]);
}

// ── Compound components ───────────────────────────────────────────────────────
const CardContext = createContext(null);

function Card({ children, className = '', ...props }) {
  return (
    <CardContext.Provider value={true}>
      <div className={`card ${className}`} {...props}>
        {children}
      </div>
    </CardContext.Provider>
  );
}

Card.Header = function CardHeader({ children, actions }) {
  return (
    <div className="card__header">
      <div className="card__header-content">{children}</div>
      {actions && <div className="card__header-actions">{actions}</div>}
    </div>
  );
};

Card.Body   = ({ children }) => <div className="card__body">{children}</div>;
Card.Footer = ({ children }) => <div className="card__footer">{children}</div>;

// ── forwardRef ────────────────────────────────────────────────────────────────
const ColorInput = forwardRef(function ColorInput({ label, value, onChange, error }, ref) {
  const id = useId();
  return (
    <div className="field">
      <label htmlFor={id} className="field__label">{label}</label>
      <div className="field__row">
        <input
          ref={ref}
          id={id}
          type="color"
          value={value}
          onChange={e => onChange(e.target.value)}
          aria-describedby={error ? `${id}-error` : undefined}
          aria-invalid={!!error}
        />
        <span className="field__value">{value}</span>
      </div>
      {error && <p id={`${id}-error`} className="field__error" role="alert">{error}</p>}
    </div>
  );
});

// ── memo ──────────────────────────────────────────────────────────────────────
const SwatchGrid = memo(function SwatchGrid({ colors, onRemove }) {
  return (
    <div className="swatch-grid" role="list" aria-label="Palette colours">
      {colors.map((color, i) => (
        <div key={i} className="swatch" role="listitem"
          style={{ '--swatch-color': color }}>
          <span className="swatch__preview" aria-hidden />
          <span className="swatch__hex">{color}</span>
          <button
            className="swatch__remove"
            aria-label={`Remove colour ${color}`}
            onClick={() => onRemove(i)}
          >✕</button>
        </div>
      ))}
    </div>
  );
});

// ── Error boundary (class component) ─────────────────────────────────────────
import { Component } from 'react';

class ErrorBoundary extends Component {
  constructor(props) {
    super(props);
    this.state = { error: null };
  }

  static getDerivedStateFromError(error) { return { error }; }

  componentDidCatch(error, info) {
    console.error('ErrorBoundary caught:', error, info.componentStack);
  }

  render() {
    if (this.state.error) {
      return this.props.fallback?.(this.state.error) ?? (
        <div role="alert" className="error-boundary">
          <h2>Something went wrong</h2>
          <p>{this.state.error.message}</p>
          <button onClick={() => this.setState({ error: null })}>Try again</button>
        </div>
      );
    }
    return this.props.children;
  }
}

// ── Main component ────────────────────────────────────────────────────────────
export default function ThemeGenerator() {
  const [state, dispatch] = useReducer(themeReducer, {
    ...initialState,
    palette: ['#070425', '#9900FF', '#09FBD3', '#5CB800', '#FF068B'],
    themeName: 'My Theme',
  });

  const [savedThemes, setSavedThemes] = useLocalStorage('themepreview:saved', []);
  const nameRef  = useRef(null);
  const menuRef  = useRef(null);
  const [menuOpen, setMenuOpen] = useState(false);
  const debouncedName = useDebounce(state.themeName);

  useClickOutside(menuRef, () => setMenuOpen(false));

  // Announce debounced name changes
  useEffect(() => {
    document.title = debouncedName ? `${debouncedName} — ThemePreview` : 'ThemePreview';
  }, [debouncedName]);

  const handleGenerate = async () => {
    dispatch({ type: 'LOAD_START' });
    try {
      await new Promise(r => setTimeout(r, 600)); // simulate async work
      setSavedThemes(prev => [...prev, { name: state.themeName, palette: state.palette }]);
      dispatch({ type: 'LOAD_SUCCESS' });
    } catch (err) {
      dispatch({ type: 'LOAD_ERROR', error: err.message });
    }
  };

  return (
    <ThemeProvider>
      <ErrorBoundary fallback={err => <div>Error: {err.message}</div>}>
        <main className="generator">
          <Card>
            <Card.Header actions={<ThemeToggleButton />}>
              <h1>⚡ ThemePreview</h1>
            </Card.Header>

            <Card.Body>
              <div className="field">
                <label htmlFor="theme-name">Theme name</label>
                <input
                  ref={nameRef}
                  id="theme-name"
                  type="text"
                  value={state.themeName}
                  onChange={e => dispatch({ type: 'SET_NAME', name: e.target.value })}
                  placeholder="My Awesome Theme"
                />
              </div>

              <SwatchGrid
                colors={state.palette}
                onRemove={i => dispatch({ type: 'REMOVE_COLOR', index: i })}
              />

              {state.palette.map((color, i) => (
                <ColorInput
                  key={i}
                  label={`Colour ${i + 1}`}
                  value={color}
                  onChange={v => dispatch({ type: 'SET_COLOR', index: i, color: v })}
                />
              ))}
            </Card.Body>

            <Card.Footer>
              <button
                className="btn btn--primary"
                onClick={handleGenerate}
                disabled={state.loading || !state.themeName.trim()}
                aria-busy={state.loading}
              >
                {state.loading ? 'Generating…' : '⚡ Generate'}
              </button>
              {state.error && <p className="error" role="alert">{state.error}</p>}
            </Card.Footer>
          </Card>

          {savedThemes.length > 0 && (
            <section aria-labelledby="saved-heading">
              <h2 id="saved-heading">Saved themes</h2>
              <ul>
                {savedThemes.map((t, i) => (
                  <li key={i}>
                    <strong>{t.name}</strong>
                    {t.palette.map((c, j) => (
                      <span key={j} style={{ background: c, width: 16, height: 16, display: 'inline-block' }} />
                    ))}
                  </li>
                ))}
              </ul>
            </section>
          )}
        </main>
      </ErrorBoundary>
    </ThemeProvider>
  );
}

function ThemeToggleButton() {
  const { theme, toggle } = useTheme();
  return (
    <button onClick={toggle} aria-label={`Switch to ${theme === 'dark' ? 'light' : 'dark'} mode`}>
      {theme === 'dark' ? '☀️' : '🌙'}
    </button>
  );
}
