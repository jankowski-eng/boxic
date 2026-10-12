# Helpers shared by the equality, ordering, range-relation, and unary-test tests. They print a
# FEEL value as text, so that a test states its expectation as text and does not depend on the
# code under test to decide whether two values are equal.
defmodule Boxic.FEEL.TestValues do
  @moduledoc false

  alias Boxic.FEEL.{Duration, Error, Function, Range}
  alias Boxic.FEEL.DateTime, as: FeelDateTime
  alias Boxic.FEEL.Time, as: FeelTime

  @doc "Evaluates `expression` and prints the outcome: the value, or `error:<code>`."
  def eval(expression, context \\ %{}), do: show_result(Boxic.FEEL.evaluate(expression, context))

  @doc "Evaluates a unary test and prints the outcome."
  def unary(test, value, context \\ %{}),
    do: show_result(Boxic.FEEL.evaluate_unary_test(test, value, context))

  def show_result({:ok, value}), do: show(value)
  def show_result({:error, %Error{code: code}}), do: "error:#{code}"

  def show(nil), do: "null"
  def show(value) when is_boolean(value), do: Atom.to_string(value)
  def show(value) when is_binary(value), do: inspect(value)
  def show(%Decimal{} = value), do: Decimal.to_string(value, :normal)
  def show(%Date{} = value), do: Date.to_iso8601(value)
  def show(%FeelTime{} = value), do: FeelTime.to_string(value)
  def show(%FeelDateTime{} = value), do: FeelDateTime.to_string(value)
  def show(%Duration{} = value), do: Duration.to_string(value)
  def show(%Function{}), do: "function"

  def show(%Range{} = range) do
    open = if range.start_inclusive, do: "[", else: "("
    close = if range.end_inclusive, do: "]", else: ")"
    open <> show(range.start) <> ".." <> show(range.end) <> close
  end

  def show(value) when is_list(value), do: "[" <> Enum.map_join(value, ", ", &show/1) <> "]"

  def show(value) when is_map(value) and not is_struct(value) do
    entries =
      value
      |> Enum.sort_by(&elem(&1, 0))
      |> Enum.map_join(", ", fn {key, item} -> "#{key}: #{show(item)}" end)

    "{" <> entries <> "}"
  end

  def show(value), do: inspect(value)
end
