# Changelog

All notable changes to `boxic_dmn` will be documented in this file.

The project follows Semantic Versioning. While the package is below version
1.0.0, breaking changes increment the minor version.

## Unreleased

DMN 1.6 additions:

- Accept the FEEL language URIs of DMN 1.4 (`20211108`) and DMN 1.6 (`20240513`).
  The B-FEEL URI (`.../20240513/B-FEEL/`) is accepted as well: set it as the
  `expressionLanguage` of the definitions to evaluate the whole model under
  B-FEEL, or on a single literal expression to override the model's language. Under
  B-FEEL the `C+` collect policy sums only numeric outputs and the sum of nothing
  is 0.
- `LiteralExpression.expression_language` is `nil` when the model does not declare
  one, so that the expression inherits the language of the definitions. It used to
  be `"feel"`.
- Implicitly convert a single value used as the `in` expression of a boxed
  filter, `for`, `some`, or `every` into a singleton list. `null` is still a type
  error.
- Evaluate the new FEEL features of `boxic_feel`.
- Apply the DMN 1.6 implicit type conversions to results and context entries:
  a single value converts to a singleton list, a singleton list converts to its
  element (for built-in scalar types and named non-collection types), and a date
  converts to a date and time at UTC midnight. Context entries are converted to
  the type declared on their variable.
- Add `Boxic.DMN.evaluate_bkm/3` to invoke a business knowledge model directly,
  mirroring `evaluate_service/3`.
- Validate against DMN TCK revision `0456e1a2fa5b9c2382cc7380cc6b95f0031e4793`,
  adding the `1157-implicit-conversions` and `1160-multiple-imports` groups. The
  DMN profile passes all 1,501 cases.

Behavior changes:

- A decision, business knowledge model, decision service, or context entry whose
  result cannot be converted to its declared type now evaluates to `nil` instead
  of returning `{:error, {:type_error, type}}`, as DMN 1.6 section 10.3.2.9.4
  specifies. Input data and invocation arguments that do not match their declared
  type are still rejected.
- Function definitions and business knowledge model logic whose `kind` is not
  `FEEL` (Java, PMML, and since DMN 1.6 ONNX) are now reported as
  `:unsupported_expression` instead of having their mapping context evaluated as
  FEEL.

Fixes:

- A decision table input entry that cannot be decided for the input, such as a range
  entry with a null input, no longer raises `CaseClauseError`. The rule does not match.

## 0.1.0 - 2026-07-18

- Initial public release.
- Load and normalize DMN 1.4 XML models.
- Validate model structure, types, and references.
- Evaluate decisions, decision tables, boxed expressions, business knowledge
  models, imports, and decision services.
- Validate against DMN TCK revision
  `0dbcaf9b98bc3af4e36d44a7aed95e9e85703a13`.
- Pass all 1,485 cases in the pinned DMN TCK profile.
