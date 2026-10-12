# Changelog

All notable changes to `boxic_feel` will be documented in this file.

The project follows Semantic Versioning. While the package is below version
1.0.0, breaking changes increment the minor version.

## Unreleased

Fixes:

- Return an `:invalid_syntax` error for numeric literals that exceed Decimal128
  limits (more than 34 significant digits, or an exponent beyond +-6144, such as
  `1e-6176`) instead of raising `Decimal.Error`.
- Return `nil` from a unary test whose value is null, instead of raising
  `ArgumentError` when the test is negated (`not([1..10])`). `evaluate_unary_test/3`
  is specified as returning a boolean or `nil`.
- Decide a range test for a value that cannot be compared with the bounds as `null`,
  not by Erlang's term order: `"a" in [1..100]` and `1 in ["a".."z"]` returned
  `false`. Bounds are only compared when both are numbers, strings, booleans, or the
  same kind of temporal value, and the two bound tests combine with three-valued `and`.
- Return an `:invalid_syntax` error for a temporal at-literal with an impossible date or a
  malformed duration (`@"2020-02-30"`, `@"2020-13-45"`, `@"P"`, `@"PT1"`, `@"P1.5D"`),
  instead of raising `CaseClauseError`. `Boxic.FEEL.DateTime.parse/1` returns `:error` for an
  impossible date, as its spec says, rather than `{:error, :invalid_date}`.
- Return an `:invalid_syntax` error for a surrogate in a `\U` escape (`"\U00D800"`), a signed
  `\u` or `\U` escape (`"\u-123"`; `"\u+123"` was accepted), and expression text that is not
  valid UTF-8, instead of raising `ArgumentError` or `FunctionClauseError`.
- Return an `:invalid_ast` error from `evaluate_ast/2` for a context entry, function
  parameter, or `for` binding that is not a pair, for an improper list, and for a named
  argument outside a call, instead of raising `FunctionClauseError`.
- Parse the type after `instance of` as a single type expression. `1 instance of number and
  true`, `[1 instance of number, 2]`, `if 1 instance of number then 1 else 2`, and
  `1 instance of number = true` no longer raise `ArgumentError`, `(1 instance of number)` no
  longer fails to parse, and `1 instance of number and x` no longer reads `number and x` as the
  type.
- Return `null` for an exponentiation without a real result, instead of raising
  `ArithmeticError` or `Decimal.Error`: a negative base with a fractional exponent
  (`(-8) ** (1/3)`), zero to a negative fractional power, and a base, exponent, or result
  that a float cannot hold (`10 ** 308.5`, `1e400 ** 0.5`, `1 ** 1e-400`).
- Return `null` instead of an infinity when arithmetic overflows (`1e6144 * 10`, `10 ** 6145`,
  `2 ** 1000000`, `sum([9e6144, 9e6144])`), and instead of raising `Decimal.Error` when an
  infinity would be subtracted, divided, or multiplied by zero. `number("NaN")` and
  `number("Infinity")` are `null` rather than a `Decimal` that is not a number, and comparing a
  `NaN` that the host supplied is `null` rather than raising.
- Return `null` when a duration is scaled to more than 34 digits (`duration("P1M") * 1e34`,
  `duration("P1D") * 1e300`), or by a factor that is not a number, instead of raising
  `Decimal.Error`. `Boxic.FEEL.Duration.scale/2` now returns `{:ok, duration}` or `:error`.
  The `days`, `hours`, `minutes`, and `seconds` of a very long duration, its text, and its sum
  with a date or time no longer raise either.
- Add a duration to an Elixir `DateTime` in a zone other than UTC with the `Tz` time zone
  database instead of raising `MatchError`. The result is `null` when the shifted wall-clock
  time does not exist or the zone is unknown. `Boxic.FEEL.Duration.add_to_datetime/2` now
  returns `{:ok, datetime}` or `:error`.
- Return a `:type_error` from an external function whose `:float` parameter receives a number
  beyond the range of a float, or that returns a `:char` that is not a Unicode scalar value or a
  `:number` that is not finite, instead of raising `Decimal.Error` or `ArgumentError`. An
  `:integer` parameter takes an integer of any size. A call with named arguments is an
  `:arity_error`, so the host function never receives the evaluator's `{:named_arg, name,
  value}` tuple; this holds for a plain Elixir function in the context as well.

Fixes, so that results match the specification:

- Support the variadic forms `sum(n1, ..., nN)` and `min(c1, ..., cN)`, and accept a
  single non-list argument for `max(c1, ..., cN)`, as the specification defines.
- Return `null` for `sum([])`, `mean([])`, and the standard deviation of fewer than two
  numbers (these returned `0` or an error), and for a range function (`before`, `after`,
  `includes`, ...) with a `null` argument (it returned `false`).

Security:

- Require `decimal` 3.1.2 or later, which fixes unbounded allocation in
  `Decimal.round/3` (CVE-2026-97853). Releases 3.1.2 and 3.2.x are tested.

## 0.1.0 - 2026-07-18

- Initial public release.
- Parse and evaluate FEEL expressions with decimal number semantics.
- Support FEEL collections, contexts, ranges, functions, temporal values, and
  Level 3 built-ins.
- Provide an allowlisted Elixir external-function boundary.
- Target DMN 1.4 and use the IANA timezone database through `tz`.
- Validate against DMN TCK revision
  `0dbcaf9b98bc3af4e36d44a7aed95e9e85703a13`.
- Pass 2,042 cases in the pinned FEEL TCK profile, with the 18 Java-specific
  external-function cases reported as intentionally unsupported.
