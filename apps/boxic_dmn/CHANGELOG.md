# Changelog

All notable changes to `boxic_dmn` will be documented in this file.

The project follows Semantic Versioning. While the package is below version
1.0.0, breaking changes increment the minor version.

## Unreleased

Fixes:

- A decision table input entry that cannot be decided for the input, such as a range
  entry with a null input, no longer raises `CaseClauseError`. The rule does not match.
- Report a decision table input expression, input entry, or output entry with an empty or
  missing `<text>` as `{:missing_entry_text, rule_id, :input_entries | :output_entries, index}`
  from `validate/1`, and return an error from `evaluate/3` instead of raising
  `FunctionClauseError`. A table in a business knowledge model is checked when it is invoked.
- Return `{:error, {:unresolved_reference, kind, nil}}` for an information requirement without
  an `href`, instead of raising `FunctionClauseError`.
- Return `{:error, {:type_error, "date and time"}}` for a `date and time` input that is not a
  real date (`"2020-02-30T10:00:00"`), instead of raising `CaseClauseError`.
- Reject `NaN` and the infinities (`"NaN"`, `"Infinity"`, `"inf"`) for a `number` input with
  `{:error, {:type_error, "number"}}`. `Decimal.parse/1` accepts them, and `In > 1` then raised
  `Decimal.Error`.
- Return `{:error, {:invalid_model, model}}`, `{:invalid_decision_name, name}`,
  `{:invalid_context, context}`, `{:invalid_options, options}`, or
  `{:invalid_external_functions, registry}` from `evaluate/3,4`, and `{:invalid_model, model}`,
  `{:invalid_service_name, name}`, or `{:invalid_arguments, arguments}` from
  `evaluate_service/3`, for arguments of the wrong type such as a `nil` model or a context
  that is not a map, instead of raising `FunctionClauseError`.
- Return `null` from a decision that raises a negative number to a fractional power
  (`In ** 0.5` with `In` of `-4`) or overflows, with the corresponding `boxic_feel` fixes,
  instead of raising `ArithmeticError`.

## 0.1.0 - 2026-07-18

- Initial public release.
- Load and normalize DMN 1.4 XML models.
- Validate model structure, types, and references.
- Evaluate decisions, decision tables, boxed expressions, business knowledge
  models, imports, and decision services.
- Validate against DMN TCK revision
  `0dbcaf9b98bc3af4e36d44a7aed95e9e85703a13`.
- Pass all 1,485 cases in the pinned DMN TCK profile.
