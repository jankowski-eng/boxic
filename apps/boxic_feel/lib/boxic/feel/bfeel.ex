defmodule Boxic.FEEL.BFEEL do
  @moduledoc false
  # B-FEEL (DMN 1.6, clause 11) is a dialect of FEEL with the same grammar in which `null`
  # only represents missing data. Operations and built-in functions that return `null` when
  # an error occurs return a non-null value instead, chosen by the type of the result.
  #
  # The dialect is carried in the evaluation context under a reserved key, so it follows
  # lexical closures and nested evaluation without changing any evaluator signature.

  alias Boxic.FEEL.{Builtins, Duration, Error, Range}
  alias Boxic.FEEL.DateTime, as: FeelDateTime
  alias Boxic.FEEL.Time, as: FeelTime

  @context_key "__feel_dialect__"
  @language "https://www.omg.org/spec/DMN/20240513/B-FEEL/"

  @boolean_operators [:eq, :neq, :lt, :lte, :gt, :gte, :and, :or]
  @arithmetic_operators [:plus, :minus, :mul, :div, :pow]

  # Built-in functions by the type of their result (clauses 11.2 to 11.8). Functions returning
  # `Any`, such as `min`, `max`, `get value`, and the context functions, are not listed: null
  # remains possible for them.
  @return_types %{
    boolean:
      ~w(contains ends_with starts_with matches is before after meets met_by overlaps_before
         overlaps_after finishes finished_by includes during starts started_by coincides overlaps
         list_contains all any even odd),
    number:
      ~w(string_length day_of_year week_of_year count sum mean product median stddev abs sqrt exp
         log modulo round floor ceiling decimal round_up round_down round_half_up round_half_down
         number),
    string:
      ~w(upper_case lower_case substring substring_before substring_after replace string_join
         string day_of_week month_of_year),
    date: ~w(date today),
    time: ~w(time),
    date_time: ~w(date_time now),
    duration: ~w(duration years_and_months_duration),
    list:
      ~w(split append concatenate insert_before remove reverse sort index_of union distinct_values
         flatten sublist list_replace mode get_entries),
    range: ~w(range)
  }

  @builtin_types for {type, names} <- @return_types, name <- names, into: %{}, do: {name, type}

  # List functions that ignore non-numeric elements of their input (clause 11.3 and 11.7).
  @numeric_aggregates ~w(sum mean median product stddev mode)

  @doc "The expression language URI that selects B-FEEL."
  def language, do: @language

  def enable(context), do: Map.put(context, @context_key, :b_feel)
  def disable(context), do: Map.delete(context, @context_key)
  def enabled?(context), do: Map.get(context, @context_key) == :b_feel

  ## Boolean operators (clause 11.2)

  @doc """
  Evaluates a binary operator under B-FEEL.

  `feel` is the FEEL implementation of the operator. Boolean operators never return null: a
  result that FEEL reports as null or as an error is false, except for `!=`, where
  incompatible operands are considered different. Arithmetic follows clauses 11.9 to 11.11.
  """
  def binary(op, left, right, feel) when op in @boolean_operators do
    default = op == :neq

    case feel.(op, left, right) do
      {:ok, value} when is_boolean(value) -> {:ok, value}
      {:ok, nil} -> {:ok, default}
      {:error, %Error{} = error} -> recover(error, default)
      other -> other
    end
  end

  def binary(op, left, right, feel) when op in @arithmetic_operators do
    case feel.(op, left, right) do
      {:ok, value} when not is_nil(value) ->
        {:ok, value}

      {:ok, nil} ->
        {:ok, convert(op, left, right, feel)}

      {:error, %Error{} = error} ->
        if semantic?(error), do: {:ok, convert(op, left, right, feel)}, else: {:error, error}
    end
  end

  def binary(op, left, right, feel), do: feel.(op, left, right)

  @doc "`not` under B-FEEL: anything but a boolean negates to false."
  def negate(value) when is_boolean(value), do: not value
  def negate(_value), do: false

  @doc "Maps a null or erroneous boolean result (`in`, `between`) to false."
  def boolean_result({:ok, value}) when is_boolean(value), do: {:ok, value}
  def boolean_result({:ok, nil}), do: {:ok, false}

  def boolean_result({:error, %Error{} = error}), do: recover(error, false)
  def boolean_result(other), do: other

  ## Built-in functions (clauses 11.2 to 11.8)

  @doc """
  Calls a built-in function under B-FEEL.

  `call` receives the (possibly adjusted) arguments and runs the FEEL implementation. A null
  or erroneous result is replaced by the default for the type the function returns.
  """
  def builtin(name, args, call) do
    case Map.fetch(@builtin_types, name) do
      {:ok, type} -> normalize(call.(numeric_only(name, args)), type)
      :error -> call.(args)
    end
  end

  defp normalize({:ok, nil}, type), do: {:ok, default(type)}
  defp normalize({:ok, _value} = result, _type), do: result

  defp normalize({:error, %Error{} = error}, type) do
    if semantic?(error), do: {:ok, default(type)}, else: {:error, error}
  end

  defp numeric_only(name, args) when name in @numeric_aggregates do
    cond do
      Enum.any?(args, &match?({:named_arg, _, _}, &1)) -> args
      match?([list] when is_list(list), args) -> [Enum.filter(hd(args), &number?/1)]
      true -> Enum.filter(args, &number?/1)
    end
  end

  defp numeric_only(_name, args), do: args

  @doc "The value returned for a result of the given type when FEEL would return null."
  def default(:boolean), do: false
  def default(:number), do: Decimal.new(0)
  def default(:string), do: ""
  def default(:date), do: ~D[1970-01-01]
  def default(:time), do: epoch_time()
  def default(:date_time), do: FeelDateTime.new(~D[1970-01-01], epoch_time())
  def default(:duration), do: zero_duration(:year_month)
  def default(:list), do: []

  def default(:range),
    do: %Range{
      start: Decimal.new(0),
      end: Decimal.new(0),
      start_inclusive: false,
      end_inclusive: false
    }

  defp epoch_time do
    {:ok, time} = FeelTime.new(0, 0, 0, {:offset, 0})
    time
  end

  defp zero_duration(:year_month) do
    {:ok, duration} = Duration.parse_iso8601("P0M")
    duration
  end

  defp zero_duration(:day_time) do
    {:ok, duration} = Duration.parse_iso8601("PT0S")
    duration
  end

  ## Arithmetic (clauses 11.9 to 11.11)

  # Applies when the operand types do not match the FEEL tables, i.e. when FEEL gives null.
  # The rules are tried in the order of the specification; `nil` means no rule applies, in
  # which case FEEL's null stands.
  defp convert(op, left, right, feel) when op in [:plus, :minus] do
    cond do
      is_binary(left) or is_binary(right) -> string_arithmetic(op, left, right)
      number?(left) or number?(right) -> number_arithmetic(op, left, right, feel)
      true -> temporal_arithmetic(op, left, right, feel)
    end
  end

  defp convert(op, left, right, feel) when op in [:mul, :div] do
    cond do
      number?(left) or number?(right) ->
        number_arithmetic(op, left, right, feel)

      duration_kind(left) != nil or duration_kind(right) != nil ->
        duration_arithmetic(op, left, right, feel)

      true ->
        nil
    end
  end

  defp convert(:pow, left, right, feel), do: number_arithmetic(:pow, left, right, feel)

  defp string_arithmetic(:plus, left, right), do: to_string_value(left) <> to_string_value(right)
  defp string_arithmetic(:minus, _left, _right), do: ""

  defp number_arithmetic(op, left, right, feel) do
    case feel.(op, to_number(left), to_number(right)) do
      {:ok, value} when not is_nil(value) -> value
      _ -> default(:number)
    end
  end

  # Temporal values and durations: the operand that is not of the temporal type is replaced
  # by a zero duration, so the temporal operand is returned unchanged.
  defp temporal_arithmetic(op, left, right, feel) do
    case {temporal_kind(left), temporal_kind(right)} do
      {nil, nil} -> nil
      {kind, nil} when kind != nil -> retry(op, left, zero_for(kind), feel)
      {nil, kind} -> retry(op, zero_for(kind), right, feel)
      _both_temporal -> nil
    end
  end

  defp duration_arithmetic(op, left, right, feel) do
    case {duration_kind(left), duration_kind(right)} do
      {kind, nil} when kind != nil -> retry(op, left, to_number(right), feel)
      {nil, kind} when kind != nil -> retry(op, to_number(left), right, feel)
      _both_durations -> nil
    end
  end

  defp retry(op, left, right, feel) do
    case feel.(op, left, right) do
      {:ok, value} -> value
      {:error, _error} -> nil
    end
  end

  defp zero_for(:duration_year_month), do: zero_duration(:year_month)
  defp zero_for(:duration_day_time), do: zero_duration(:day_time)
  defp zero_for(_temporal), do: zero_duration(:day_time)

  defp temporal_kind(%FeelDateTime{}), do: :date_time
  defp temporal_kind(%DateTime{}), do: :date_time
  defp temporal_kind(%NaiveDateTime{}), do: :date_time
  defp temporal_kind(%Date{}), do: :date
  defp temporal_kind(%FeelTime{}), do: :time
  defp temporal_kind(%Time{}), do: :time
  defp temporal_kind(%Duration{kind: :year_month}), do: :duration_year_month
  defp temporal_kind(%Duration{kind: :day_time}), do: :duration_day_time
  defp temporal_kind(_value), do: nil

  defp duration_kind(%Duration{kind: kind}), do: kind
  defp duration_kind(_value), do: nil

  ## B-FEEL conversion functions

  # `number` under B-FEEL: a number is itself, a numeric string is converted, anything else is 0.
  defp to_number(%Decimal{} = value), do: value

  defp to_number(value) when is_binary(value) do
    case Builtins.invoke("number", [value]) do
      {:ok, %Decimal{} = number} -> number
      _ -> default(:number)
    end
  end

  defp to_number(_value), do: default(:number)

  # `string` under B-FEEL: null and failures give the empty string.
  defp to_string_value(value) when is_binary(value), do: value

  defp to_string_value(value) do
    case Builtins.invoke("string", [value]) do
      {:ok, string} when is_binary(string) -> string
      _ -> ""
    end
  end

  defp number?(%Decimal{}), do: true
  defp number?(_value), do: false

  ## Errors

  # FEEL reports semantic problems as null or as errors; B-FEEL turns the latter into values.
  # Errors that are not semantic, such as an invalid AST, are still reported.
  defp semantic?(%Error{code: code}), do: code in [:type_error, :evaluation_error, :arity_error]

  defp recover(%Error{} = error, default) do
    if semantic?(error), do: {:ok, default}, else: {:error, error}
  end
end
