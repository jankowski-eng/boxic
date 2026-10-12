defmodule Boxic.FEEL.Semantics do
  @moduledoc false
  # The equality of FEEL values (DMN 1.5 Table 52 and Table 53), which `=`, `!=`, `in`, the
  # unary tests, and the built-in functions that compare values all share.

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

  # The items of a list or the entries of a context are equal when all of them are.
  defp equality_all(results) do
    cond do
      Enum.any?(results, &(&1 == false)) -> false
      Enum.any?(results, &is_nil/1) -> nil
      true -> true
    end
  end
end
