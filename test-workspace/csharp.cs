/**
 * theme_preview.cs — C# syntax showcase
 * Covers: records, pattern matching, nullable refs, LINQ, async streams,
 *         interfaces, generics, attributes, extension methods, switch expressions
 */

#nullable enable

using System;
using System.Collections.Generic;
using System.Linq;
using System.Runtime.CompilerServices;
using System.Text.Json.Serialization;
using System.Threading;
using System.Threading.Tasks;

namespace ThemePreview.Preview;

// ── Enums ──────────────────────────────────────────────────────────────────────
public enum Severity { Info, Warning, Error, Critical }

[Flags]
public enum Permission { None = 0, Read = 1, Write = 2, Delete = 4, Admin = 8 }

// ── Records ───────────────────────────────────────────────────────────────────
public sealed record User(
    [property: JsonPropertyName("id")]           string    Id,
    [property: JsonPropertyName("email")]        string    Email,
    [property: JsonPropertyName("display_name")] string    DisplayName,
    [property: JsonPropertyName("created_at")]   DateTime  CreatedAt
)
{
    public static User Create(string email) =>
        new(Guid.NewGuid().ToString(), email,
            email.Split('@')[0], DateTime.UtcNow);
}

public record struct Point(double X, double Y)
{
    public double Magnitude => Math.Sqrt(X * X + Y * Y);
    public Point  Normalize  => Magnitude is 0 ? this : this with { X = X / Magnitude, Y = Y / Magnitude };
    public static Point operator +(Point a, Point b) => new(a.X + b.X, a.Y + b.Y);
}

// ── Generic interface with constraints ────────────────────────────────────────
public interface IRepository<T, TId> where T : notnull
{
    ValueTask<T?>          FindByIdAsync(TId id,            CancellationToken ct = default);
    IAsyncEnumerable<T>    GetAllAsync(                      CancellationToken ct = default);
    ValueTask<T>           SaveAsync(T entity,              CancellationToken ct = default);
    ValueTask              DeleteAsync(TId id,              CancellationToken ct = default);
}

// ── Discriminated union via abstract record ────────────────────────────────────
public abstract record Result<T>
{
    public sealed record Ok(T Value)          : Result<T>;
    public sealed record Err(string Message)  : Result<T>;

    public static Result<T> From(Func<T> fn)
    {
        try   { return new Ok(fn()); }
        catch (Exception ex) { return new Err(ex.Message); }
    }

    public TOut Match<TOut>(Func<T, TOut> onOk, Func<string, TOut> onErr) =>
        this switch
        {
            Ok  { Value:   var v } => onOk(v),
            Err { Message: var m } => onErr(m),
            _                      => throw new InvalidOperationException()
        };
}

// ── Extension methods ─────────────────────────────────────────────────────────
public static class Extensions
{
    public static IEnumerable<T> WhereNotNull<T>(this IEnumerable<T?> source)
        where T : class => source.Where(x => x is not null)!;

    public static async IAsyncEnumerable<T> TakeWhileAsync<T>(
        this IAsyncEnumerable<T> source,
        Func<T, bool> predicate,
        [EnumeratorCancellation] CancellationToken ct = default)
    {
        await foreach (var item in source.WithCancellation(ct))
        {
            if (!predicate(item)) yield break;
            yield return item;
        }
    }

    public static string ToSentenceCase(this string s) =>
        string.IsNullOrWhiteSpace(s) ? s :
        char.ToUpper(s[0]) + s[1..].ToLower();
}

// ── Async stream + LINQ ────────────────────────────────────────────────────────
public class DataPipeline
{
    private static readonly int[] _primes = { 2,3,5,7,11,13,17,19,23,29,31,37 };

    public static async IAsyncEnumerable<int> GetPrimesAsync(
        int count,
        [EnumeratorCancellation] CancellationToken ct = default)
    {
        foreach (var prime in _primes.Take(count))
        {
            await Task.Delay(10, ct);
            yield return prime;
        }
    }

    public static async Task<Dictionary<bool, List<int>>> PartitionAsync(int take)
    {
        var result = new Dictionary<bool, List<int>>
        {
            [true]  = new(),
            [false] = new(),
        };

        await foreach (var p in GetPrimesAsync(take))
            result[p % 2 == 0].Add(p);

        return result;
    }
}

// ── Pattern matching ──────────────────────────────────────────────────────────
static class PatternDemo
{
    record Shape;
    record Circle(double Radius)        : Shape;
    record Rectangle(double W, double H): Shape;
    record Triangle(double A, double B, double C) : Shape;

    static double Area(Shape shape) => shape switch
    {
        Circle    { Radius: var r }           => Math.PI * r * r,
        Rectangle { W: var w, H: var h }      => w * h,
        Triangle  { A: var a, B: var b, C: var c } =>
            // Heron's formula
            Math.Sqrt((a + b + c) / 2 * ((a + b + c) / 2 - a) *
                      ((a + b + c) / 2 - b) * ((a + b + c) / 2 - c)),
        _ => throw new NotSupportedException($"Unknown shape: {shape}")
    };

    static string Classify(object obj) => obj switch
    {
        int n when n < 0         => $"negative int: {n}",
        int n when n == 0        => "zero",
        int n                    => $"positive int: {n}",
        string { Length: 0 }     => "empty string",
        string s                 => $"string: \"{s}\"",
        (int x, int y)           => $"tuple ({x}, {y})",
        null                     => "null",
        _                        => $"other: {obj.GetType().Name}"
    };
}

// ── Entry point ───────────────────────────────────────────────────────────────
static class Program
{
    static async Task Main()
    {
        // Records
        var alice = User.Create("alice@example.com");
        var bob   = alice with { Email = "bob@example.com", DisplayName = "Bob" };
        Console.WriteLine($"User: {alice}");

        // Result monad
        var r = Result<int>.From(() => int.Parse("42"));
        Console.WriteLine(r.Match(v => $"Ok: {v}", e => $"Err: {e}"));

        // Async streams
        var partitioned = await DataPipeline.PartitionAsync(12);
        foreach (var (isEven, primes) in partitioned)
            Console.WriteLine($"{(isEven ? "Even" : "Odd")} primes: [{string.Join(", ", primes)}]");

        // LINQ
        var evens = Enumerable.Range(1, 50)
            .Where(n  => n % 2 == 0)
            .Select(n => n * n)
            .TakeWhile(n => n < 500)
            .ToList();
        Console.WriteLine($"Even squares < 500: {string.Join(", ", evens)}");

        // Pattern matching
        foreach (var obj in new object[] { -3, 0, 7, "", "hello", (4, 5), null! })
            Console.WriteLine(PatternDemo.Classify(obj));
    }
}
