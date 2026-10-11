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
