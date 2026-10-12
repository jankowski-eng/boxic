defmodule Boxic.FEEL.UnaryTestsTest do
  # A unary test `op x` on an input `v` means `v op x` (DMN 1.5 Table 55), so it follows the
  # comparison and equality rules of Table 49 (clause 49.a), Table 52, Table 53, and Table 54:
  # a null is equal only to null, an order involving a null is null, and values that have no
  # order give null. A decision table treats a null as "the entry is not satisfied".
  use ExUnit.Case, async: true

  import Boxic.FEEL.TestValues

  defp d(value), do: Decimal.new(value)

  describe "`in` with an empty list" do
    for {expression, expected} <- [
          {~S|1 in []|, "false"},
          {~S|null in []|, "false"},
          {~S|"a" in []|, "false"},
          {~S|list contains([], 1)|, "false"},
          # A list of tests that cannot decide stays null, and one that matches is true.
          {~S|"a" in [1, 2]|, "null"},
          {~S|1 in [2, 3]|, "false"},
          {~S|1 in [2, 1]|, "true"}
        ] do
      test expression do
        assert eval(unquote(expression)) == unquote(expected)
      end
    end
  end

  describe "a comparison with a null input" do
    for test <- ["< 5", "<= 5", "> 5", ">= 5", "< null", "not(< 5)", "not(>= 5)"] do
      test "#{test} is null" do
        assert unary(unquote(test), nil) == "null"
      end
    end

    test "= and != treat null as a value" do
      assert unary("= null", nil) == "true"
      assert unary("= null", d(5)) == "false"
      assert unary("!= null", d(5)) == "true"
      assert unary("!= null", nil) == "false"
      assert unary("= 3", nil) == "false"
      assert unary("!= 3", nil) == "true"
      assert unary("not(= 3)", nil) == "true"
      assert unary("not(!= 3)", nil) == "false"
    end

    test "a null on the right is null for an order, and a value for = and !=" do
      assert unary("< null", d(5)) == "null"
      assert unary("= null", d(5)) == "false"
      assert unary("!= null", d(5)) == "true"
    end

    test "the same holds for `in`" do
      assert eval(~S|null in (< 5)|) == "null"
      assert eval(~S|null in (= null)|) == "true"
      assert eval(~S|5 in (!= null)|) == "true"
      assert eval(~S|null in (!= 3)|) == "true"
    end
  end

  describe "a comparison with an input that cannot be compared" do
    test "gives null, not an error" do
      assert unary("< 5", "abc") == "null"
      assert unary("<= 5", ~D[2020-01-01]) == "null"
      assert unary("> 5", true) == "null"
      assert unary("< date(\"2020-01-01\")", d(5)) == "null"
      assert unary("< \"b\"", d(5)) == "null"
      assert unary("< duration(\"P1D\")", d(5)) == "null"
      assert unary("<= time(\"10:00:00Z\")", ~D[2020-01-01]) == "null"
      assert unary("not(< 5)", "abc") == "null"
    end

    test "durations of different kinds, and times in different named zones, have no order" do
      {:ok, year} = Boxic.FEEL.evaluate(~S|duration("P1Y")|)
      {:ok, hour} = Boxic.FEEL.evaluate(~S|duration("PT1H")|)
      {:ok, paris} = Boxic.FEEL.evaluate(~S|time("10:00:00@Europe/Paris")|)

      assert unary(~S|< duration("PT2H")|, year) == "null"
      assert unary(~S|< duration("P2Y")|, hour) == "null"
      assert unary(~S|< time("11:00:00Z")|, paris) == "null"
      assert unary(~S|< duration("PT2H")|, hour) == "true"
    end

    test "booleans are ordered, as they are by `<`" do
      assert unary("< true", false) == "true"
      assert unary("< true", true) == "false"
      assert eval(~S|true < true|) == "false"
      assert unary("< true", d(5)) == "null"
    end

    test "= and != give null for another kind of value" do
      assert unary("= 5", "abc") == "null"
      assert unary("!= 5", "abc") == "null"
      assert unary(~S|= "5"|, d(5)) == "null"
    end
  end

  describe "tests whose result is decided" do
    for {test, value, expected} <- [
          {"< 5", 3, "true"},
          {"< 5", 5, "false"},
          {"<= 5", 5, "true"},
          {"> 5", 6, "true"},
          {">= 5", 5, "true"},
          {"= 5", 5, "true"},
          {"= 5", 6, "false"},
          {"!= 5", 5, "false"},
          {"!= 5", 6, "true"},
          {">= 18", 21, "true"},
          {"[1..10]", 5, "true"},
          {"[1..10]", 11, "false"},
          {"(1..10)", 10, "false"},
          {"not([1..10])", 11, "true"},
          {"not([1..10])", 5, "false"},
          {"-", 5, "true"}
        ] do
      test "#{test} on #{value}" do
        assert unary(unquote(test), d(unquote(value))) == unquote(expected)
      end
    end

    test "the input may be a string, a date, or a duration" do
      assert unary(~S|< "b"|, "a") == "true"
      assert unary(~S|>= "b"|, "a") == "false"
      assert unary(~S|< date("2020-01-02")|, ~D[2020-01-01]) == "true"
      assert unary(~S|> date("2020-01-02")|, ~D[2020-01-01]) == "false"
      assert unary("-", nil) == "true"
      assert unary("[1..10]", nil) == "null"
      assert unary("not([1..10])", nil) == "null"
    end

    test "a time or a date-time without an offset takes the offset of the bound" do
      {:ok, floating} = Boxic.FEEL.evaluate(~S|time("10:00:00")|)
      {:ok, later} = Boxic.FEEL.evaluate(~S|date and time("2020-01-01T12:00:00")|)

      assert unary(~S|< time("11:00:00Z")|, floating) == "true"
      assert unary(~S|> date and time("2020-01-01T11:00:00Z")|, later) == "true"
    end
  end
end
