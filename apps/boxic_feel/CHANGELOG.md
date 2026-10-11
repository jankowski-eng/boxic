# Changelog

All notable changes to `boxic_feel` will be documented in this file.

The project follows Semantic Versioning. While the package is below version
1.0.0, breaking changes increment the minor version.

## Unreleased

DMN 1.6 additions:

- Add the `...` descendant operator, e.g. `{a: {b: {b: 1}}}...b` evaluates to
  `[{b: 1}, 1]`. It collects matching entries of a context, its nested contexts,
  and contexts nested in lists.
- Add the `value` property for dates, times, date and time values, and both
  duration kinds. A date and time without a zone has no position on the timeline,
  so its `value` is `null`.
- Add single-parameter forms of `round up`, `round down`, `round half up`, and
  `round half down`; the scale defaults to 0.
- Add `date and time(date, time, timezone)`, where `timezone` is an offset or an
  IANA identifier.
- Apply the implicit decimal-to-integer conversion: a fractional rounding scale,
  list position or length, or date and time component is truncated instead of
  producing an error. Time zone offsets remain strict.

Not yet supported: the strict error-handling mode and the B-FEEL dialect.

Validation:

- Validate against DMN TCK revision `0456e1a2fa5b9c2382cc7380cc6b95f0031e4793`.
  The FEEL profile is unchanged at 2,042 passing cases, with the same 18
  intentionally unsupported Java cases.

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
