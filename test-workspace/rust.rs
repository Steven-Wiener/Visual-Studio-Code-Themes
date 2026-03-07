//! theme_preview.rs — Rust syntax showcase
//! Covers: traits, generics, lifetimes, enums, pattern matching,
//!         iterators, closures, error handling, async, macros

use std::{
    collections::HashMap,
    fmt,
    marker::PhantomData,
    str::FromStr,
    sync::{Arc, RwLock},
};

// ── Custom error type ─────────────────────────────────────────────────────────
#[derive(Debug, Clone, PartialEq)]
pub enum ThemeError {
    InvalidHex(String),
    InvalidPalette { expected_min: usize, got: usize },
    NotFound(String),
    Unauthorized,
}

impl fmt::Display for ThemeError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::InvalidHex(h)                         => write!(f, "Invalid hex colour: {h:?}"),
            Self::InvalidPalette { expected_min, got }  => write!(f, "Need ≥{expected_min} colours, got {got}"),
            Self::NotFound(id)                          => write!(f, "Theme {id:?} not found"),
            Self::Unauthorized                          => write!(f, "Unauthorized"),
        }
    }
}

impl std::error::Error for ThemeError {}

type Result<T, E = ThemeError> = std::result::Result<T, E>;

// ── Colour newtype ────────────────────────────────────────────────────────────
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub struct HexColor(u32);

impl HexColor {
    pub const BLACK: Self = Self(0x000000);
    pub const WHITE: Self = Self(0xFFFFFF);

    pub fn r(self) -> u8 { ((self.0 >> 16) & 0xFF) as u8 }
    pub fn g(self) -> u8 { ((self.0 >>  8) & 0xFF) as u8 }
    pub fn b(self) -> u8 {  (self.0        & 0xFF) as u8 }

    pub fn luminance(self) -> f32 {
        let linearise = |c: u8| -> f32 {
            let v = c as f32 / 255.0;
            if v <= 0.04045 { v / 12.92 } else { ((v + 0.055) / 1.055).powf(2.4) }
        };
        0.2126 * linearise(self.r()) + 0.7152 * linearise(self.g()) + 0.0722 * linearise(self.b())
    }

    pub fn with_alpha(self, alpha: u8) -> String {
        format!("#{:06X}{:02X}", self.0, alpha)
    }
}

impl FromStr for HexColor {
    type Err = ThemeError;

    fn from_str(s: &str) -> Result<Self> {
        let s = s.trim_start_matches('#');
        let n = u32::from_str_radix(s, 16)
            .map_err(|_| ThemeError::InvalidHex(s.to_owned()))?;
        if s.len() == 6 { Ok(Self(n)) } else { Err(ThemeError::InvalidHex(s.to_owned())) }
    }
}

impl fmt::Display for HexColor {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result { write!(f, "#{:06X}", self.0) }
}

// ── Traits ────────────────────────────────────────────────────────────────────
pub trait Colorable {
    fn primary_color(&self) -> HexColor;
    fn is_dark(&self) -> bool { self.primary_color().luminance() < 0.5 }
}

pub trait Persistable: Sized {
    type Id: Clone + fmt::Debug;
    fn id(&self) -> &Self::Id;
    fn save(&self, store: &dyn Store<Self>) -> Result<()>;
}

pub trait Store<T: Persistable>: Send + Sync {
    fn get(&self, id: &T::Id) -> Option<T>;
    fn set(&self, item: T) -> Result<()>;
    fn remove(&self, id: &T::Id) -> bool;
    fn all(&self) -> Vec<T>;
}

// ── Structs with lifetimes ────────────────────────────────────────────────────
#[derive(Debug, Clone)]
pub struct Theme {
    pub id:      String,
    pub name:    String,
    pub palette: Vec<HexColor>,
    pub colors:  HashMap<String, HexColor>,
}

impl Theme {
    pub fn new(id: impl Into<String>, name: impl Into<String>) -> Self {
        Self { id: id.into(), name: name.into(), palette: vec![], colors: HashMap::new() }
    }

    pub fn with_palette(mut self, palette: Vec<HexColor>) -> Result<Self> {
        if palette.len() < 2 {
            return Err(ThemeError::InvalidPalette { expected_min: 2, got: palette.len() });
        }
        self.palette = palette;
        Ok(self)
    }

    pub fn background(&self) -> Option<HexColor> { self.colors.get("editor.background").copied() }
}

impl Colorable for Theme {
    fn primary_color(&self) -> HexColor {
        self.palette.first().copied().unwrap_or(HexColor::BLACK)
    }
}

impl Persistable for Theme {
    type Id = String;
    fn id(&self) -> &Self::Id { &self.id }
    fn save(&self, store: &dyn Store<Self>) -> Result<()> { store.set(self.clone()) }
}

// ── Generic in-memory store ────────────────────────────────────────────────────
pub struct MemoryStore<T: Persistable + Clone + Send + Sync> {
    data:    Arc<RwLock<HashMap<String, T>>>,
    _marker: PhantomData<T>,
}

impl<T: Persistable<Id = String> + Clone + Send + Sync> MemoryStore<T> {
    pub fn new() -> Self {
        Self { data: Arc::new(RwLock::new(HashMap::new())), _marker: PhantomData }
    }
}

impl<T: Persistable<Id = String> + Clone + Send + Sync> Store<T> for MemoryStore<T> {
    fn get(&self, id: &String) -> Option<T> {
        self.data.read().ok()?.get(id).cloned()
    }
    fn set(&self, item: T) -> Result<()> {
        self.data.write().unwrap().insert(item.id().clone(), item);
        Ok(())
    }
    fn remove(&self, id: &String) -> bool {
        self.data.write().unwrap().remove(id).is_some()
    }
    fn all(&self) -> Vec<T> {
        self.data.read().unwrap().values().cloned().collect()
    }
}

// ── Iterator adapter ──────────────────────────────────────────────────────────
struct Fibonacci { a: u64, b: u64 }
impl Fibonacci { fn new() -> Self { Self { a: 0, b: 1 } } }
impl Iterator for Fibonacci {
    type Item = u64;
    fn next(&mut self) -> Option<u64> {
        let next = self.a;
        (self.a, self.b) = (self.b, self.a + self.b);
        Some(next)
    }
}

// ── Macros ────────────────────────────────────────────────────────────────────
macro_rules! hex {
    ($s:literal) => { $s.parse::<HexColor>().expect(concat!("Invalid hex: ", $s)) };
}

macro_rules! colors {
    ($($key:expr => $val:literal),* $(,)?) => {{
        let mut map = HashMap::new();
        $(map.insert($key.to_owned(), hex!($val));)*
        map
    }};
}

// ── Entry point ───────────────────────────────────────────────────────────────
fn main() -> Result<(), Box<dyn std::error::Error>> {
    let palette = vec![
        hex!("#070425"), hex!("#9900FF"), hex!("#09FBD3"),
        hex!("#5CB800"), hex!("#FF068B"), hex!("#4499FF"),
    ];

    let theme = Theme::new("neon-vomit-night", "Neon Vomit Night")
        .with_palette(palette)?;

    println!("Theme:       {}", theme.name);
    println!("Primary:     {}", theme.primary_color());
    println!("Is dark:     {}", theme.is_dark());
    println!("Luminance:   {:.4}", theme.primary_color().luminance());

    // Closures + iterators
    let dark_colors: Vec<_> = theme.palette.iter()
        .filter(|c| c.luminance() < 0.1)
        .map(|c| c.to_string())
        .collect();
    println!("Very dark colours: {dark_colors:?}");

    // Store
    let store: MemoryStore<Theme> = MemoryStore::new();
    theme.save(&store)?;
    println!("Saved theme: {:?}", store.get(&"neon-vomit-night".to_owned()).map(|t| t.name));

    // Fibonacci via iterator adapter
    let fibs: Vec<u64> = Fibonacci::new().take(12).collect();
    println!("Fibonacci:   {fibs:?}");

    // Pattern matching
    let values: Vec<Result<HexColor>> = vec![
        "#09FBD3".parse(),
        "not-a-color".parse(),
        "#FFFFFF".parse(),
    ];
    for result in values {
        match result {
            Ok(c)                           => println!("  ✓ {c}  luminance={:.3}", c.luminance()),
            Err(ThemeError::InvalidHex(h))  => println!("  ✗ bad hex: {h:?}"),
            Err(e)                          => println!("  ✗ error: {e}"),
        }
    }

    Ok(())
}
