defmodule Boxic.FEEL.Semantics do
  @moduledoc false
  # The equality (DMN 1.5 Table 52 and Table 53) and the order (Table 54) of FEEL values, which
  # `=`, `!=`, `<`, `in`, the unary tests, and the built-in functions that compare values all
  # share. There is no other place that decides whether two values are equal or which is less.

  alias Boxic.FEEL.{Duration, Function, Range}
  alias Boxic.FEEL.DateTime, as: FeelDateTime
  alias Boxic.FEEL.Time, as: FeelTime

  @doc """
  FEEL equality of two values: `true`, `false`, or `nil` when the values are of kinds that
  cannot be compared, such as a number and a string.

  Numbers are equal by value, so `1.0 = 1`. Lists are equal when they have the same length and
  equal items, and contexts when they have the same keys and equal entries, so that a list or
  a context of dates, durations, or ranges is compared deeply. Two functions are equal when
  they are the same function.

  Times and date-times keep the equality that the TCK expects: a time is equal to another time
  of the same zone that has the same hour, minute, and whole second (case 0068 ignores
  fractional seconds), and date-times in different zones are equal when they are the same
  instant.
  """
  @spec equal(term(), term()) :: boolean() | nil
  def equal(nil, nil), do: true
  def equal(nil, _right), do: false
  def equal(_left, nil), do: false
  def equal(%Decimal{} = left, %Decimal{} = right), do: Decimal.equal?(left, right)
  def equal(left, right) when is_integer(left) and is_integer(right), do: left == right

  def equal(%Decimal{} = left, right) when is_integer(right),
    do: Decimal.equal?(left, Decimal.new(right))

  def equal(left, %Decimal{} = right) when is_integer(left),
    do: Decimal.equal?(Decimal.new(left), right)

  def equal(left, right) when is_boolean(left) and is_boolean(right), do: left == right
  def equal(left, right) when is_binary(left) and is_binary(right), do: left == right
  def equal(%Date{} = left, %Date{} = right), do: Date.compare(left, right) == :eq
  def equal(%Time{} = left, %Time{} = right), do: Time.compare(left, right) == :eq

  def equal(%DateTime{} = left, %DateTime{} = right),
    do: DateTime.compare(left, right) == :eq

  def equal(%FeelTime{} = left, %FeelTime{} = right),
    do:
      left.zone == right.zone and left.hour == right.hour and left.minute == right.minute and
        Decimal.equal?(
          Decimal.round(left.second, 0, :down),
          Decimal.round(right.second, 0, :down)
        )

  def equal(%FeelDateTime{} = left, %FeelDateTime{} = right),
    do:
      if(left.time.zone == right.time.zone,
        do:
          Date.compare(left.date, right.date) == :eq and
            equal(left.time, right.time) == true,
        else: FeelDateTime.compare(left, right) == :eq
      )

  def equal(%Duration{} = left, %Duration{} = right),
    do:
      if(left.kind == right.kind,
        do: left.months == right.months and equal(left.seconds, right.seconds) == true,
        else: nil
      )

  def equal(%Range{} = left, %Range{} = right) do
    left.start_inclusive == right.start_inclusive and
      left.end_inclusive == right.end_inclusive and
      equal(left.start, right.start) == true and
      equal(left.end, right.end) == true
  end

  def equal(
        {:unary_test_value, left_operator, left_operand},
        {:unary_test_value, right_operator, right_operand}
      ) do
    left_operator == right_operator and equal(left_operand, right_operand) == true
  end

  def equal({:unary_test_value, _operator, _operand}, %Range{}), do: false
  def equal(%Range{}, {:unary_test_value, _operator, _operand}), do: false

  def equal(%Function{} = left, %Function{} = right), do: left == right
  def equal({:builtin, left}, {:builtin, right}), do: left == right
  def equal({:external_function, left}, {:external_function, right}), do: left == right

  def equal(left, right) when is_list(left) and is_list(right) do
    if length(left) == length(right) do
      left |> Enum.zip(right) |> Enum.map(fn {l, r} -> equal(l, r) end) |> equality_all()
    else
      false
    end
  end

  def equal(left, right)
      when is_map(left) and is_map(right) and not is_struct(left) and not is_struct(right) do
    if Map.keys(left) |> Enum.sort() == Map.keys(right) |> Enum.sort() do
      left
      |> Enum.map(fn {key, value} -> equal(value, Map.fetch!(right, key)) end)
      |> equality_all()
    else
      false
    end
  end

  def equal(_left, _right), do: nil

  @doc "True when the values are equal; false when they are not, or cannot be compared."
  @spec equal?(term(), term()) :: boolean()
  def equal?(left, right), do: equal(left, right) == true

  @typedoc "How two values are ordered; `:not_comparable` when they have no order."
  @type ordering :: :lt | :eq | :gt | :not_comparable

  @doc """
  Orders two values as `<` does (Table 54): `:lt`, `:eq`, `:gt`, or `:not_comparable`.

  Numbers are ordered by value, strings by code point, dates by year, month, and day, times
  and date-times by instant, and durations by length. Booleans are not ordered by the
  specification; they keep the order `false < true` that `<` and `in` have always given them.
  Two durations are ordered only when they are of the same kind, and times and date-times only
  when they have a common timeline: both have an offset, or one has none, in which case it
  takes the offset of the other (Table 54), or both are in the same named zone. Values of
  different kinds, such as a number and a string, a date and a date-time, a list, a context,
  a range, and null have no order.
  """
  @spec compare(term(), term()) :: ordering()
  def compare(left, right)
      when (is_integer(left) or is_struct(left, Decimal)) and
             (is_integer(right) or is_struct(right, Decimal)) do
    left = to_decimal(left)
    right = to_decimal(right)

    # NaN is not a FEEL number, but a host can put one in the context. It is not ordered.
    if Decimal.nan?(left) or Decimal.nan?(right),
      do: :not_comparable,
      else: Decimal.compare(left, right)
  end

  def compare(left, right) when is_binary(left) and is_binary(right) do
    cond do
      left == right -> :eq
      left < right -> :lt
      true -> :gt
    end
  end

  def compare(false, true), do: :lt
  def compare(true, false), do: :gt
  def compare(left, right) when is_boolean(left) and is_boolean(right), do: :eq

  def compare(%Date{} = left, %Date{} = right), do: Date.compare(left, right)
  def compare(%Time{} = left, %Time{} = right), do: Time.compare(left, right)
  def compare(%DateTime{} = left, %DateTime{} = right), do: DateTime.compare(left, right)

  def compare(%FeelTime{} = left, %FeelTime{} = right) do
    {left, right} = adopt_offset(left, right)
    ordering(FeelTime.compare(left, right))
  end

  def compare(%FeelDateTime{} = left, %FeelDateTime{} = right) do
    {left_time, right_time} = adopt_offset(left.time, right.time)
    ordering(FeelDateTime.compare(%{left | time: left_time}, %{right | time: right_time}))
  end

  def compare(%Duration{} = left, %Duration{} = right),
    do: ordering(Duration.compare(left, right))

  def compare(_left, _right), do: :not_comparable

  @doc """
  The kind of an ordered value: `:number`, `:string`, `:boolean`, `:date`, `:time`,
  `:date_time`, or `:duration`; `nil` for a value that has no order, such as a list.

  Two values of one kind that `compare/2` calls `:not_comparable` cannot be ordered, as two
  durations of different kinds cannot. Two values of different kinds are not meant to be
  compared at all.
  """
  @spec kind(term()) ::
          :number | :string | :boolean | :date | :time | :date_time | :duration | nil
  def kind(value) when is_integer(value) or is_struct(value, Decimal), do: :number
  def kind(value) when is_binary(value), do: :string
  def kind(value) when is_boolean(value), do: :boolean
  def kind(%Date{}), do: :date
  def kind(%Time{}), do: :time
  def kind(%FeelTime{}), do: :time
  def kind(%DateTime{}), do: :date_time
  def kind(%FeelDateTime{}), do: :date_time
  def kind(%Duration{}), do: :duration
  def kind(_value), do: nil

  # Table 54: if one input has a null time offset, it uses the offset of the other input. A
  # time that is in a named zone has no offset of its own, but the zone of the other value
  # tells which one applies.
  defp adopt_offset(%{zone: :floating} = left, %{zone: zone} = right) when zone != :floating,
    do: {%{left | zone: zone}, right}

  defp adopt_offset(%{zone: zone} = left, %{zone: :floating} = right) when zone != :floating,
    do: {left, %{right | zone: zone}}

  defp adopt_offset(left, right), do: {left, right}

  defp ordering(:unordered), do: :not_comparable
  defp ordering(ordering), do: ordering

  defp to_decimal(%Decimal{} = value), do: value
  defp to_decimal(value), do: Decimal.new(value)

  # The items of a list or the entries of a context are equal when all of them are.
  defp equality_all(results) do
    cond do
      Enum.any?(results, &(&1 == false)) -> false
      Enum.any?(results, &is_nil/1) -> nil
      true -> true
    end
  end
end
