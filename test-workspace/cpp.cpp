/**
 * theme_preview.cpp — C++ syntax showcase
 * Covers: templates, concepts, RAII, smart pointers, lambdas,
 *         ranges, coroutines, structured bindings, constexpr, variant
 */

#include <algorithm>
#include <concepts>
#include <coroutine>
#include <iostream>
#include <memory>
#include <optional>
#include <ranges>
#include <span>
#include <string>
#include <string_view>
#include <unordered_map>
#include <variant>
#include <vector>

// ── Concepts ──────────────────────────────────────────────────────────────────
template <typename T>
concept Numeric = std::integral<T> || std::floating_point<T>;

template <typename T>
concept Printable = requires(T t, std::ostream& os) {
    { os << t } -> std::same_as<std::ostream&>;
};

template <typename Container>
concept Iterable = requires(Container c) {
    std::begin(c);
    std::end(c);
};

// ── constexpr utilities ───────────────────────────────────────────────────────
constexpr std::size_t CACHE_SIZE = 256;

template <Numeric T>
constexpr T clamp(T value, T lo, T hi) noexcept {
    return (value < lo) ? lo : (value > hi) ? hi : value;
}

consteval double circle_area(double r) { return 3.14159265358979 * r * r; }

// ── RAII + smart pointer wrapper ──────────────────────────────────────────────
template <typename T>
class UniqueBuffer {
    std::unique_ptr<T[]> _data;
    std::size_t          _size;

public:
    explicit UniqueBuffer(std::size_t n)
        : _data(std::make_unique<T[]>(n)), _size(n) {}

    std::span<T>       span()       noexcept { return { _data.get(), _size }; }
    std::span<const T> span() const noexcept { return { _data.get(), _size }; }

    T& operator[](std::size_t i) { return _data[i]; }
    std::size_t size() const noexcept { return _size; }

    // Iterators
    T* begin() noexcept { return _data.get(); }
    T* end()   noexcept { return _data.get() + _size; }
};

// ── std::variant — tagged union ────────────────────────────────────────────────
using JsonValue = std::variant<
    std::nullptr_t,
    bool,
    int64_t,
    double,
    std::string,
    std::vector<struct JsonNode>,
    std::unordered_map<std::string, struct JsonNode>
>;

struct JsonNode { JsonValue value; };

std::string json_type(const JsonValue& v) {
    return std::visit([]<typename T>(const T&) -> std::string {
        if constexpr (std::is_same_v<T, std::nullptr_t>) return "null";
        if constexpr (std::is_same_v<T, bool>)           return "boolean";
        if constexpr (std::is_same_v<T, int64_t>)        return "integer";
        if constexpr (std::is_same_v<T, double>)         return "float";
        if constexpr (std::is_same_v<T, std::string>)    return "string";
        return "composite";
    }, v);
}

// ── Templates & template specialisation ───────────────────────────────────────
template <Numeric T>
struct Statistics {
    T min{}, max{}, sum{};
    std::size_t count{};

    void update(T value) noexcept {
        if (count == 0) { min = max = value; }
        else {
            min = std::min(min, value);
            max = std::max(max, value);
        }
        sum += value;
        ++count;
    }

    double mean() const { return count ? static_cast<double>(sum) / count : 0.0; }
};

template <Iterable Container>
auto compute_stats(const Container& c) {
    using T = std::ranges::range_value_t<Container>;
    Statistics<T> s;
    for (const auto& v : c) s.update(v);
    return s;
}

// ── Coroutine — generator ─────────────────────────────────────────────────────
struct Generator {
    struct promise_type {
        int current;
        auto get_return_object()  { return Generator{std::coroutine_handle<promise_type>::from_promise(*this)}; }
        auto initial_suspend()    { return std::suspend_always{}; }
        auto final_suspend() noexcept { return std::suspend_always{}; }
        auto yield_value(int v)   { current = v; return std::suspend_always{}; }
        void return_void() {}
        void unhandled_exception() { std::terminate(); }
    };

    std::coroutine_handle<promise_type> handle;
    ~Generator() { if (handle) handle.destroy(); }

    bool next()  { handle.resume(); return !handle.done(); }
    int  value() { return handle.promise().current; }
};

Generator fibonacci_gen() {
    int a = 0, b = 1;
    while (true) {
        co_yield a;
        auto tmp = a; a = b; b = tmp + b;
    }
}

// ── Ranges pipeline ───────────────────────────────────────────────────────────
void demo_ranges() {
    using namespace std::views;

    auto pipeline = iota(1, 101)
        | filter([](int n) { return n % 2 == 0; })
        | transform([](int n) { return n * n; })
        | take(5);

    std::cout << "Even squares: ";
    for (int v : pipeline) std::cout << v << ' ';
    std::cout << '\n';

    // Structured binding from ranges
    std::vector<std::pair<std::string, int>> scores = {
        {"Alice", 92}, {"Bob", 87}, {"Carol", 95}
    };

    auto top = scores
        | filter([](const auto& [_, s]) { return s > 90; })
        | transform([](const auto& [n, s]) { return n + ": " + std::to_string(s); });

    for (const auto& entry : top) std::cout << entry << '\n';
}

// ── Lambda overload set ───────────────────────────────────────────────────────
template<typename... Ts> struct overloaded : Ts... { using Ts::operator()...; };
template<typename... Ts> overloaded(Ts...) -> overloaded<Ts...>;

// ── Main ───────────────────────────────────────────────────────────────────────
int main() {
    // Concepts & constexpr
    constexpr double area = circle_area(5.0);
    std::cout << "Circle area(r=5): " << area << '\n';
    std::cout << "Clamp(-3, 0, 10): " << clamp(-3, 0, 10) << '\n';

    // Buffer + stats
    UniqueBuffer<double> buf(10);
    std::iota(buf.begin(), buf.end(), 1.0);
    auto stats = compute_stats(buf.span());
    std::cout << "Stats: min=" << stats.min << " max=" << stats.max
              << " mean=" << stats.mean() << '\n';

    // Coroutine
    auto gen = fibonacci_gen();
    std::cout << "Fibonacci: ";
    for (int i = 0; i < 10 && gen.next(); ++i)
        std::cout << gen.value() << ' ';
    std::cout << '\n';

    // Variant
    JsonValue vals[] = { nullptr, true, 42LL, 3.14, std::string("hello") };
    for (const auto& v : vals)
        std::cout << "json_type: " << json_type(v) << '\n';

    // Overloaded visitor
    std::variant<int, float, std::string> mixed = "world";
    std::visit(overloaded{
        [](int i)               { std::cout << "int: "    << i << '\n'; },
        [](float f)             { std::cout << "float: "  << f << '\n'; },
        [](const std::string& s){ std::cout << "string: " << s << '\n'; }
    }, mixed);

    demo_ranges();
    return 0;
}
