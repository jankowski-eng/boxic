defmodule Boxic.FEELBFEELTest do
  use ExUnit.Case, async: true

  # The examples of DMN 1.6 clause 11.

  defp feel(expression), do: Boxic.FEEL.evaluate(expression)
  defp b_feel(expression), do: Boxic.FEEL.evaluate(expression, %{}, dialect: :b_feel)

  # Renders a result so it can be compared with `==`: numbers as normalized strings, temporal values and
  # durations through FEEL's own `string` function, and compound values recursively.
  defp render({:ok, value}), do: render(value)
  defp render({:error, _error}), do: :error

  defp render(%Decimal{} = number),
    do: number |> Decimal.normalize() |> Decimal.to_string(:normal)

  defp render(%Boxic.FEEL.Range{} = range), do: {:range, render(range.start), render(range.end)}
  defp render(list) when is_list(list), do: Enum.map(list, &render/1)

  defp render(value) when is_struct(value) do
    {:ok, string} = Boxic.FEEL.evaluate("string(value)", %{"value" => value})
    string
  end

  defp render(value), do: value

  # Each row is `{expression, B-FEEL result}`. The specification contrasts these with FEEL, where
  # they are null; Boxic's FEEL reports some of them as errors or other values instead, so only
  # the B-FEEL result is asserted exactly.
  defp assert_b_feel(rows) do
    for {expression, expected} <- rows do
      assert render(b_feel(expression)) == expected, "#{expression} in B-FEEL"
    end
  end

  describe "operators and built-ins returning a boolean (11.2)" do
    test "operators are two-valued" do
      assert_b_feel([
        {~S|"a" = 1|, false},
        {~S|"a" < 1|, false},
        {~S|"a" <= null|, false},
        {~S|"a" > 1|, false},
        {~S|null >= 1|, false},
        {~S|not("a")|, false},
        {~S|true and "x"|, false},
        {~S|false or "x"|, false},
        {~S|"a" in [1..100]|, false},
        {~S|null between 1 and 100|, false},
        {~S|"a" != 1|, true}
      ])
    end

    test "valid operands behave as in FEEL" do
      for expression <- [
            "1 = 1",
            "1 < 2",
            "2 <= 2",
            "3 > 2",
            "not(false)",
            "true and true",
            "false or true",
            "true or null",
            "false and null",
            "5 in [1..10]",
            "5 between 1 and 10",
            "1 != 2",
            "null = null"
          ] do
        assert render(b_feel(expression)) == render(feel(expression)), expression
      end
    end

    test "built-in functions return false instead of null" do
      assert_b_feel([
        {~S|matches("bad pattern", "[0-9")|, false},
        {~S|before(date("2021-01-01"), null)|, false},
        {~S|all(true, "x", true)|, false},
        {~S|any(null)|, false}
      ])
    end
  end

  describe "built-ins returning a number (11.3)" do
    test "return 0 instead of null" do
      assert_b_feel([
        {~S|decimal("a", 0)|, "0"},
        {~S|round up("5.5", 0)|, "0"},
        {~S|string length(22)|, "0"},
        {~S|day of year("a")|, "0"}
      ])
    end

    test "list aggregates ignore non-numeric elements" do
      assert_b_feel([
        {~S|count([1, null, 3])|, "3"},
        {~S|sum([1, null, 3])|, "4"},
        {~S|sum([1, "1", 3])|, "4"},
        {~S|sum([])|, "0"},
        {~S|mean(["a"])|, "0"},
        {~S|mean([1, "a", 3])|, "2"}
      ])
    end

    test "variadic aggregates ignore non-numeric arguments too" do
      assert render(b_feel(~S|mean(1, "x", 3)|)) == "2"
      assert render(b_feel(~S|product(2, null, 4)|)) == "8"
    end
  end

  describe "built-ins returning a string (11.4)" do
    test "return the empty string instead of null" do
      assert_b_feel([
        {~S|lower case(12)|, ""},
        {~S|string(null)|, ""},
        {~S|day of week("a")|, ""},
        {~S|substring("a", "z")|, ""}
      ])
    end
  end

  describe "built-ins returning a date, time, or date and time (11.5)" do
    test "return the epoch instead of null" do
      assert_b_feel([
        {~S|time("a")|, "00:00:00Z"},
        {~S|date(null)|, "1970-01-01"},
        {~S|date and time("a")|, "1970-01-01T00:00:00Z"}
      ])
    end
  end

  describe "built-ins returning a duration (11.6)" do
    test "return a zero duration instead of null" do
      assert_b_feel([
        {~S|duration("a")|, "P0M"},
        {~S|years and months duration(null, null)|, "P0M"}
      ])
    end
  end

  describe "built-ins returning a collection or a range (11.7, 11.8)" do
    test "return an empty list instead of null" do
      assert_b_feel([
        {~S|split("abc", 22)|, []},
        {~S|mode([null, null, null, 1, 1, 2])|, ["1"]}
      ])
    end

    test "range returns an empty range instead of null" do
      assert render(feel(~S|range("x")|)) in [nil, :error]
      assert render(b_feel(~S|range("x")|)) == {:range, "0", "0"}

      assert {:ok, %Boxic.FEEL.Range{start_inclusive: false, end_inclusive: false}} =
               b_feel(~S|range("x")|)
    end
  end

  describe "addition and subtraction (11.9)" do
    test "convert operands when the types do not match" do
      assert_b_feel([
        {~S|"Today is " + date("2020-01-01")|, "Today is 2020-01-01"},
        {~S|"The result is: " + 1|, "The result is: 1"},
        {~S|5 + " minutes"|, "5 minutes"},
        {~S|"This is " + null|, "This is "},
        {~S|1 + null|, "1"},
        {~S|null - 6|, "-6"},
        {~S|date("2021-01-01") + 7|, "7"},
        {~S|"abc" - 2|, ""}
      ])
    end

    test "valid operands behave as in FEEL" do
      for expression <- [
            "1 + 2",
            "5 - 3",
            ~S|"a" + "b"|,
            ~S|date("2020-01-01") + duration("P1D")|,
            ~S|duration("PT1H") + duration("PT1H")|
          ] do
        assert render(b_feel(expression)) == render(feel(expression)), expression
      end
    end

    test "leave a temporal operand unchanged when the other one is missing" do
      assert render(b_feel(~S|duration("PT1H") + null|)) == "PT1H"
      assert render(b_feel(~S|duration("P1Y") - null|)) == "P1Y"
      assert render(b_feel(~S|date("2021-01-01") + null|)) == "2021-01-01"
    end

    test "leave combinations without a rule to FEEL" do
      assert {:ok, nil} = b_feel("[1] + [2]")
      assert {:ok, nil} = b_feel("null + null")
    end
  end

  describe "multiplication and division (11.10)" do
    test "convert operands when the types do not match" do
      assert_b_feel([
        {~S|22 * "a"|, "0"},
        {~S|null / 22|, "0"},
        {~S|duration("P1Y") * null|, "P0M"}
      ])
    end

    test "division by zero is 0" do
      assert render(feel("1 / 0")) in [nil, :error]
      assert render(b_feel("1 / 0")) == "0"
    end

    test "valid operands behave as in FEEL" do
      for expression <- ["6 * 7", "10 / 4", ~S|duration("PT1H") * 2|, ~S|duration("P1Y") / 2|] do
        assert render(b_feel(expression)) == render(feel(expression)), expression
      end
    end
  end

  describe "exponentiation (11.11)" do
    test "converts both operands to numbers" do
      assert render(b_feel(~S|"a" ** 2|)) == "0"
      assert render(b_feel(~S|2 ** "a"|)) == "1"
      assert render(b_feel(~S|"3" ** 2|)) == "9"
      assert render(b_feel("2 ** 10")) == render(feel("2 ** 10"))
    end
  end

  describe "dialect selection" do
    test "FEEL is the default" do
      assert {:ok, nil} = Boxic.FEEL.evaluate(~S|"a" = 1|)
      assert {:ok, nil} = Boxic.FEEL.evaluate(~S|"a" = 1|, %{}, dialect: :feel)
    end

    test "an explicit FEEL dialect overrides a context that selected B-FEEL" do
      context = Boxic.FEEL.BFEEL.enable(%{})
      assert {:ok, false} = Boxic.FEEL.evaluate(~S|"a" = 1|, context)
      assert {:ok, nil} = Boxic.FEEL.evaluate(~S|"a" = 1|, context, dialect: :feel)
    end

    test "applies to parsed expressions and unary tests" do
      assert {:ok, ast} = Boxic.FEEL.parse(~S|"a" < 1|)
      assert {:ok, false} = Boxic.FEEL.evaluate_ast(ast, %{}, dialect: :b_feel)
      assert {:ok, false} = Boxic.FEEL.evaluate_unary_test("> 1", "a", %{}, dialect: :b_feel)
    end

    test "is inherited by functions defined in the expression" do
      expression = ~S|{f: function(x) x + 1, result: f(null)}.result|
      assert render(b_feel(expression)) == "1"
      assert render(feel(expression)) in [nil, :error]
    end

    test "rejects an unknown dialect" do
      assert_raise ArgumentError, ~r/unknown FEEL dialect/, fn ->
        Boxic.FEEL.evaluate("1", %{}, dialect: :other)
      end
    end

    test "names bound in the context are unaffected" do
      assert {:ok, false} =
               Boxic.FEEL.evaluate("age > limit", %{"age" => "old", "limit" => Decimal.new(18)},
                 dialect: :b_feel
               )
    end
  end
end
