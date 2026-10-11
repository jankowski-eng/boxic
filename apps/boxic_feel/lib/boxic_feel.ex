defmodule Boxic.FEEL do
  @moduledoc """
  Parses and evaluates FEEL expressions.

  The public facade accepts FEEL source through `parse/1` and `evaluate/2`, or
  an already parsed syntax tree through `evaluate_ast/2`.
  """

  alias Boxic.FEEL.{AST, BFEEL, Error, Evaluator, Parser, Tokenizer}

  @type ast ::
          {:literal, term()}
          | {:identifier, String.t()}
          | {:unary, atom(), ast()}
          | {:binary, atom(), ast(), ast()}
          | {:list, [ast()]}
          | {:context, [{String.t(), ast()}]}
          | {:path, ast(), String.t()}
          | {:descendant, ast(), String.t()}
          | {:filter, ast(), ast()}
          | {:range, boolean(), boolean(), ast(), ast()}
          | {:in, ast(), ast()}
          | {:unary_test, atom(), ast()}
          | {:unary_tests, [ast()]}
          | {:sequence, ast(), ast()}
          | {:if, ast(), ast(), ast()}
          | {:for, String.t(), ast(), ast()}
          | {:for, [{String.t(), ast()}], ast()}
          | {:quantifier, :some | :every, String.t(), ast(), ast()}
          | {:between, ast(), ast(), ast()}
          | {:instance_of, ast(), String.t()}
          | {:function, [String.t()], ast()}
          | {:call, ast(), [ast()]}
  @type context :: %{optional(String.t()) => term()}

  @typedoc """
  The FEEL dialect used for evaluation.

  `:b_feel` is the DMN 1.6 Business Friendly Enough Expression Language: it shares FEEL's
  grammar, but `null` only represents missing data. Operators and built-in functions that
  would return `null` because of an error return a value of their result type instead, such
  as `false`, `0`, or `""`.
  """
  @type dialect :: :feel | :b_feel

  @type option :: {:dialect, dialect()}

  @doc """
  Parses a FEEL expression into Boxic's public AST representation.

      iex> Boxic.FEEL.parse("1 + 2")
      {:ok, {:binary, :plus, {:literal, Decimal.new("1")}, {:literal, Decimal.new("2")}}}
  """
  @spec parse(String.t()) :: {:ok, ast()} | {:error, Error.t()}
  def parse(expression) when is_binary(expression) do
    trimmed = String.trim(expression)

    if trimmed == "" do
      {:error, %Error{code: :empty_expression, message: "expression cannot be empty"}}
    else
      with {:ok, tokens} <- Tokenizer.tokenize(trimmed),
           {:ok, ast, []} <- Parser.parse_expression(tokens),
           :ok <- AST.validate(ast) do
        {:ok, ast}
      else
        {:ok, _ast, rest} ->
          {:error, %Error{code: :invalid_syntax, message: "unexpected tokens: #{inspect(rest)}"}}

        {:error, %Error{} = error} ->
          {:error, error}
      end
    end
  end

  @doc """
  Parses and evaluates a FEEL expression.

      iex> Boxic.FEEL.evaluate("price * quantity", %{
      ...>   "price" => Decimal.new("12.50"),
      ...>   "quantity" => Decimal.new("2")
      ...> })
      {:ok, Decimal.new("25.00")}

  ## Options

    * `:dialect` - `:feel` (the default) or `:b_feel`. See `t:dialect/0`.

          iex> Boxic.FEEL.evaluate(~S|"a" = 1|, %{}, dialect: :b_feel)
          {:ok, false}
  """
  @spec evaluate(String.t(), context(), [option()]) :: {:ok, term()} | {:error, Error.t()}
  def evaluate(expression, context \\ %{}, opts \\ [])
      when is_binary(expression) and is_map(context) and is_list(opts) do
    with {:ok, ast} <- parse(expression), do: evaluate_ast(ast, context, opts)
  end

  @doc """
  Evaluates an AST previously returned by `parse/1`.

  Accepts the same options as `evaluate/3`.
  """
  @spec evaluate_ast(ast(), context(), [option()]) :: {:ok, term()} | {:error, Error.t()}
  def evaluate_ast(ast, context, opts \\ []) when is_map(context) and is_list(opts) do
    with :ok <- AST.validate(ast), do: Evaluator.eval(ast, with_dialect(context, opts))
  end

  @doc """
  Evaluates a FEEL unary test against `value`.

      iex> Boxic.FEEL.evaluate_unary_test(">= 18", Decimal.new("21"))
      {:ok, true}

  The result is `nil` when the test cannot be decided, for example when `value` is null or
  cannot be compared with the bounds of a range.
  A caller deciding whether a rule matches should treat that as not satisfied.
  """
  @spec evaluate_unary_test(String.t(), term(), context(), [option()]) ::
          {:ok, boolean() | nil} | {:error, Error.t()}
  def evaluate_unary_test(test_expression, value, context \\ %{}, opts \\ [])
      when is_binary(test_expression) and is_map(context) and is_list(opts) do
    Evaluator.evaluate_unary_test(test_expression, value, with_dialect(context, opts))
  end

  @doc """
  Selects the dialect for evaluations that use `context`.

  The choice also applies to functions defined in expressions evaluated with the returned
  context, because they capture it. This lets a host, such as a DMN evaluator, select the
  dialect once for a whole model.
  """
  @spec put_dialect(context(), dialect()) :: context()
  def put_dialect(context, :feel) when is_map(context), do: BFEEL.disable(context)
  def put_dialect(context, :b_feel) when is_map(context), do: BFEEL.enable(context)

  @doc """
  Returns the dialect selected by `context`, which is `:feel` unless `put_dialect/2` or the
  `:dialect` option chose another.
  """
  @spec dialect(context()) :: dialect()
  def dialect(context) when is_map(context),
    do: if(BFEEL.enabled?(context), do: :b_feel, else: :feel)

  @doc """
  Returns the dialect selected by a DMN expression language URI.

  Only the B-FEEL URI of DMN 1.6 selects `:b_feel`; every other language is treated as FEEL
  here, and deciding whether it is supported is left to the caller.

      iex> Boxic.FEEL.dialect_for_language("https://www.omg.org/spec/DMN/20240513/B-FEEL/")
      :b_feel
  """
  @spec dialect_for_language(String.t() | nil) :: dialect()
  def dialect_for_language(language) do
    if language == BFEEL.language(), do: :b_feel, else: :feel
  end

  defp with_dialect(context, opts) do
    case Keyword.fetch(opts, :dialect) do
      :error -> context
      {:ok, dialect} when dialect in [:feel, :b_feel] -> put_dialect(context, dialect)
      {:ok, other} -> raise ArgumentError, "unknown FEEL dialect: #{inspect(other)}"
    end
  end
end
