/**
 * theme_preview.java — Java syntax showcase
 * Covers: generics, interfaces, records, sealed classes, streams,
 *         lambdas, optional, annotations, varargs, switch expressions
 */

package dev.themepreview.preview;

import java.time.Instant;
import java.util.*;
import java.util.concurrent.*;
import java.util.function.*;
import java.util.stream.*;

// ── Annotations ───────────────────────────────────────────────────────────────
@FunctionalInterface
interface Transformer<A, B> {
    B transform(A input);
    static <T> Transformer<T, T> identity() { return t -> t; }
}

// ── Sealed interface ──────────────────────────────────────────────────────────
sealed interface Result<T> permits Result.Ok, Result.Err {

    record Ok<T>(T value) implements Result<T> {}
    record Err<T>(String message, Throwable cause) implements Result<T> {
        Err(String message) { this(message, null); }
    }

    static <T> Result<T> of(Supplier<T> supplier) {
        try {
            return new Ok<>(supplier.get());
        } catch (Exception e) {
            return new Err<>(e.getMessage(), e);
        }
    }

    default boolean isOk() { return this instanceof Ok; }

    default T orElse(T fallback) {
        return switch (this) {
            case Ok<T> ok     -> ok.value();
            case Err<T> err   -> fallback;
        };
    }
}

// ── Record ────────────────────────────────────────────────────────────────────
record User(
    String id,
    String email,
    String displayName,
    Instant createdAt
) {
    // compact constructor for validation
    User {
        Objects.requireNonNull(id,    "id must not be null");
        Objects.requireNonNull(email, "email must not be null");
        if (!email.contains("@")) throw new IllegalArgumentException("Invalid email: " + email);
        createdAt = Objects.requireNonNullElseGet(createdAt, Instant::now);
    }

    public User withDisplayName(String name) {
        return new User(id, email, name, createdAt);
    }
}

// ── Generic repository ────────────────────────────────────────────────────────
interface Repository<T, ID> {
    Optional<T> findById(ID id);
    List<T> findAll();
    T save(T entity);
    void deleteById(ID id);

    default List<T> findAllWhere(Predicate<T> predicate) {
        return findAll().stream().filter(predicate).collect(Collectors.toList());
    }
}

class InMemoryUserRepository implements Repository<User, String> {
    private final Map<String, User> store = new ConcurrentHashMap<>();

    @Override public Optional<User> findById(String id)  { return Optional.ofNullable(store.get(id)); }
    @Override public List<User>     findAll()             { return List.copyOf(store.values()); }
    @Override public User           save(User user)       { store.put(user.id(), user); return user; }
    @Override public void           deleteById(String id) { store.remove(id); }

    public Map<String, List<User>> groupByDomain() {
        return findAll().stream()
            .collect(Collectors.groupingBy(u -> u.email().split("@")[1]));
    }
}

// ── Streams & lambdas ─────────────────────────────────────────────────────────
class StreamExamples {
    static final List<Integer> NUMBERS = IntStream.rangeClosed(1, 20)
        .boxed().collect(Collectors.toUnmodifiableList());

    static Map<Boolean, List<Integer>> partitionEvenOdd() {
        return NUMBERS.stream().collect(Collectors.partitioningBy(n -> n % 2 == 0));
    }

    static OptionalInt firstPrimeSqrt() {
        return NUMBERS.stream()
            .filter(StreamExamples::isPrime)
            .mapToInt(Integer::intValue)
            .map(n -> (int) Math.sqrt(n))
            .findFirst();
    }

    @SafeVarargs
    static <T> List<T> concat(List<T>... lists) {
        return Arrays.stream(lists)
            .flatMap(Collection::stream)
            .distinct()
            .collect(Collectors.toList());
    }

    private static boolean isPrime(int n) {
        if (n < 2) return false;
        return IntStream.rangeClosed(2, (int) Math.sqrt(n)).noneMatch(i -> n % i == 0);
    }
}

// ── Switch expression & pattern matching ──────────────────────────────────────
class PaymentProcessor {
    sealed interface Payment permits Payment.Card, Payment.Cash, Payment.Crypto {}
    record Card(String number, double amount) implements Payment {}
    record Cash(double amount)                implements Payment {}
    record Crypto(String coin, double units)  implements Payment {}

    static String process(Payment payment) {
        return switch (payment) {
            case Card c  when c.amount() > 10_000 -> "Large card payment: flagged for review";
            case Card c                            -> "Card ending in " + c.number().substring(c.number().length() - 4);
            case Cash ca when ca.amount() > 5_000  -> "Large cash: report required";
            case Cash ca                           -> String.format("Cash: $%.2f", ca.amount());
            case Crypto cr                         -> String.format("%s %.6f", cr.coin(), cr.units());
        };
    }
}

// ── Main ───────────────────────────────────────────────────────────────────────
public class ThemePreview {
    public static void main(String[] args) {
        var repo = new InMemoryUserRepository();

        var users = List.of(
            new User("u1", "alice@example.com",   "Alice",   null),
            new User("u2", "bob@example.com",     "Bob",     null),
            new User("u3", "carol@corp.internal", "Carol",   null)
        );
        users.forEach(repo::save);

        repo.findById("u1").ifPresent(u -> System.out.println("Found: " + u));

        repo.groupByDomain().forEach((domain, members) ->
            System.out.printf("  @%s → %s%n", domain,
                members.stream().map(User::displayName).collect(Collectors.joining(", "))));

        Result<Integer> r = Result.of(() -> Integer.parseInt("42"));
        System.out.println("Result: " + r.orElse(-1));

        Result<Integer> bad = Result.of(() -> Integer.parseInt("not-a-number"));
        System.out.println("Bad result: " + bad.orElse(-1));

        StreamExamples.partitionEvenOdd().forEach((even, nums) ->
            System.out.println((even ? "Even" : "Odd") + ": " + nums));

        var payments = List.<PaymentProcessor.Payment>of(
            new PaymentProcessor.Card("4111111111111234", 250.00),
            new PaymentProcessor.Cash(15_000.00),
            new PaymentProcessor.Crypto("ETH", 0.5)
        );
        payments.stream()
            .map(PaymentProcessor::process)
            .forEach(System.out::println);
    }
}
