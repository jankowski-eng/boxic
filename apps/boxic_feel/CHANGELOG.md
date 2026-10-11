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

Fixes, so that results match the specification's tables:

- `sum([])`, `mean([])`, and the standard deviation of fewer than two numbers are
  `null`. They returned `0` or an error.
- A range function (`before`, `after`, `includes`, `during`, ...) with a `null`
  argument is `null`. It returned `false`.
- A value that cannot be compared with the bounds of a range is neither in it nor
  out of it: `"a" in [1..100]` and `1 in ["a".."z"]` are `null`, not `false`.
  Range bounds are only compared when both are numbers, strings, booleans, or the
  same kind of temporal value.
- `evaluate_unary_test/3` is documented as returning `nil` when a test cannot be
  decided, and `not(...)` of such a test is `nil` instead of raising.

Not yet supported: the strict error-handling mode and the B-FEEL dialect.

Validation:

- Validate against DMN TCK revision `0456e1a2fa5b9c2382cc7380cc6b95f0031e4793`.
  The FEEL profile is unchanged at 2,042 passing cases, with the same 18
  intentionally unsupported Java cases.

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
