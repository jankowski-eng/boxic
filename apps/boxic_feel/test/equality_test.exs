defmodule Boxic.FEEL.EqualityTest do
  # One notion of FEEL equality (DMN 1.5 Table 52 and Table 53) backs `=`, `in`, the unary tests
  # `=` and `!=`, and the built-ins that compare values: `list contains`, `index of`, `union`,
  # `distinct values`, and `coincides`. Values of every kind, and lists and contexts of them,
  # must be comparable without failing.
  use ExUnit.Case, async: true

  import Boxic.FEEL.TestValues

  describe "list contains" do
    for {expression, expected} <- [
          {~S|list contains([date("2020-01-01")], date("2020-01-02"))|, "false"},
          {~S|list contains([date("2020-01-01")], date("2020-01-01"))|, "true"},
          {~S|list contains([duration("P1D")], duration("PT24H"))|, "true"},
          {~S|list contains([duration("P1D")], duration("PT1H"))|, "false"},
          {~S|list contains([duration("P1Y")], duration("P12M"))|, "true"},
          {~S|list contains([duration("P1M")], duration("P30D"))|, "false"},
          {~S|list contains([[1..5]], [1..5])|, "true"},
          {~S|list contains([[1..5]], (1..5])|, "false"},
          {~S|list contains([[1..5]], [1..6])|, "false"},
          {~S|list contains([[date("2020-01-01")..date("2020-02-01")]], [date("2020-01-01")..date("2020-02-01")])|,
           "true"},
          {~S|list contains([date and time("2020-01-01T10:00:00Z")], date and time("2020-01-01T10:00:00Z"))|,
           "true"},
          {~S|list contains([date and time("2020-01-01T10:00:00Z")], date and time("2020-01-01T12:00:00+02:00"))|,
           "true"},
          {~S|list contains([time("10:00:00Z")], time("10:00:00Z"))|, "true"},
          {~S|list contains([time("10:00:00Z")], time("11:00:00Z"))|, "false"},
          {~S|list contains([[date("2020-01-01"), duration("P1D")]], [date("2020-01-01"), duration("PT24H")])|,
           "true"},
          {~S|list contains([{a: duration("P1D")}], {a: duration("PT24H")})|, "true"},
          {~S|list contains([{a: [date("2020-01-01")]}], {a: [date("2020-01-02")]})|, "false"},
          {~S|list contains([1.0], 1)|, "true"},
          {~S|list contains([{a: 1.0}], {a: 1})|, "true"},
          {~S|list contains([null], null)|, "true"},
          {~S|list contains([1], "a")|, "false"},
          {~S|list contains([1], date("2020-01-01"))|, "false"},
          {~S|list contains([[1, "a"]], [1, 2])|, "false"},
          {~S|list contains([function(x) x], function(x) x)|, "true"},
          {~S|list contains([function(x) x], function(y) y)|, "false"},
          {~S|list contains([function(x) x], 1)|, "false"}
        ] do
      test expression do
        assert eval(unquote(expression)) == unquote(expected)
      end
    end

    test "a function is equal to itself" do
      assert eval(~S|{f: function(x) x, r: list contains([f], f)}.r|) == "true"
    end

    # The built-ins use the same equality as `=`, which compares times by their zone and
    # ignores fractional seconds (TCK case 0068).
    test "times are equal the way `=` says they are" do
      assert eval(~S|time("10:00:00Z") = time("12:00:00+02:00")|) == "false"
      assert eval(~S|list contains([time("10:00:00Z")], time("12:00:00+02:00"))|) == "false"
      assert eval(~S|time("10:30:00.0001") = time("10:30:00.0002")|) == "true"
      assert eval(~S|list contains([time("10:30:00.0001")], time("10:30:00.0002"))|) == "true"
    end
  end

  describe "index of" do
    for {expression, expected} <- [
          {~S|index of([duration("P1D")], duration("P1D"))|, "[1]"},
          {~S|index of([duration("P1D"), duration("PT1H"), duration("PT24H")], duration("P1D"))|,
           "[1, 3]"},
          {~S|index of([date("2020-01-01"), date("2020-01-02"), date("2020-01-01")], date("2020-01-01"))|,
           "[1, 3]"},
          {~S|index of([[1..5], (1..5], [1..5]], [1..5])|, "[1, 3]"},
          {~S|index of([1, 2, 1.0], 1)|, "[1, 3]"},
          {~S|index of([{a: 1}, {a: 1.0}], {a: 1})|, "[1, 2]"},
          {~S|index of([1, "a", null], null)|, "[3]"},
          {~S|index of([date("2020-01-01")], "2020-01-01")|, "[]"}
        ] do
      test expression do
        assert eval(unquote(expression)) == unquote(expected)
      end
    end
  end

  describe "distinct values and union" do
    for {expression, expected} <- [
          {~S|distinct values([date("2020-01-02"), date("2020-01-02")])|, "[2020-01-02]"},
          {~S|distinct values([date("2020-01-02"), date("2020-01-03")])|,
           "[2020-01-02, 2020-01-03]"},
          {~S|distinct values([duration("P1D"), duration("PT24H")])|, "[P1D]"},
          {~S|distinct values([duration("P1D"), duration("PT1H")])|, "[P1D, PT1H]"},
          {~S|distinct values([[1..5], [1..5], (1..5]])|, "[[1..5], (1..5]]"},
          {~S|distinct values([1.0, 1, 2])|, "[1.0, 2]"},
          {~S|distinct values([{a: 1}, {a: 1.0}, {a: 2}])|, "[{a: 1}, {a: 2}]"},
          {~S|distinct values([[date("2020-01-01")], [date("2020-01-01")]])|, "[[2020-01-01]]"},
          {~S|distinct values([null, null, 1])|, "[null, 1]"},
          {~S|union([date("2020-01-02")], [date("2020-01-02"), date("2020-01-03")])|,
           "[2020-01-02, 2020-01-03]"},
          {~S|union([duration("P1D")], [duration("PT24H")])|, "[P1D]"},
          {~S|union([[1..5]], [[1..5]])|, "[[1..5]]"},
          {~S|union([[1..5]], [(1..5]])|, "[[1..5], (1..5]]"},
          {~S|union([1, 2], [2.0, 3])|, "[1, 2, 3]"}
        ] do
      test expression do
        assert eval(unquote(expression)) == unquote(expected)
      end
    end
  end

  describe "coincides" do
    for {expression, expected} <- [
          {~S|coincides(date("2020-01-31"), date("2020-01-31"))|, "true"},
          {~S|coincides(date("2020-01-31"), date("2020-02-01"))|, "false"},
          {~S|coincides(duration("P1D"), duration("P1D"))|, "true"},
          {~S|coincides(duration("P1D"), duration("PT24H"))|, "true"},
          {~S|coincides(duration("P1D"), duration("PT1H"))|, "false"},
          {~S|coincides(time("10:00:00Z"), time("10:00:00Z"))|, "true"},
          {~S|coincides(date and time("2020-01-01T10:00:00Z"), date and time("2020-01-01T10:00:00Z"))|,
           "true"},
          {~S|coincides(1.0, 1)|, "true"},
          {~S|coincides("a", "a")|, "true"},
          {~S|coincides(true, false)|, "false"},
          {~S|coincides([1, 2], [1.0, 2])|, "true"},
          {~S|coincides({a: 1}, {a: 1.0})|, "true"},
          {~S|coincides([1..5], [1..5])|, "true"},
          {~S|coincides([1..5], (1..5])|, "false"},
          {~S|coincides([date("2020-01-01")..date("2020-01-31")], [date("2020-01-01")..date("2020-01-31")])|,
           "true"},
          # Values of different kinds are neither equal nor unequal.
          {~S|coincides(1, "a")|, "null"},
          {~S|coincides(date("2020-01-01"), duration("P1D"))|, "null"}
        ] do
      test expression do
        assert eval(unquote(expression)) == unquote(expected)
      end
    end
  end

  describe "= and !=" do
    for {expression, expected} <- [
          {~S|{a: 1.0} = {a: 1}|, "true"},
          {~S|[1.0, 2] = [1, 2]|, "true"},
          {~S|[1..5] = [1..5]|, "true"},
          {~S|[1..5] = (1..5]|, "false"},
          {~S|duration("P1D") = duration("PT24H")|, "true"},
          {~S|date("2020-01-01") = date("2020-01-01")|, "true"},
          {~S|{a: date("2020-01-01"), b: [duration("P1D")]} = {a: date("2020-01-01"), b: [duration("PT24H")]}|,
           "true"},
          {~S|date and time("2020-01-01T10:00:00Z") = date and time("2020-01-01T12:00:00+02:00")|,
           "true"},
          {~S|1 = "a"|, "null"},
          {~S|1 != "a"|, "null"},
          {~S|null = null|, "true"},
          {~S|null != 1|, "true"},
          {~S|1 = null|, "false"},
          {~S|1 != null|, "true"}
        ] do
      test expression do
        assert eval(unquote(expression)) == unquote(expected)
      end
    end
  end

  describe "unary-test equality" do
    test "numbers are equal by value, in a context and in a list" do
      assert {:ok, true} = Boxic.FEEL.evaluate_unary_test("= {a: 1.0}", %{"a" => 1})
      assert {:ok, true} = Boxic.FEEL.evaluate_unary_test("= {a: 1.0}", %{"a" => Decimal.new(1)})
      assert {:ok, false} = Boxic.FEEL.evaluate_unary_test("= {a: 1.0}", %{"a" => Decimal.new(2)})
      assert {:ok, true} = Boxic.FEEL.evaluate_unary_test("= [1.0, 2]", [1, 2])

      assert {:ok, true} =
               Boxic.FEEL.evaluate_unary_test("= [1.0, 2]", [Decimal.new(1), Decimal.new(2)])

      assert {:ok, false} = Boxic.FEEL.evaluate_unary_test("= [1.0, 2]", [1, 3])
    end

    test "temporal values, durations, and ranges are compared by value" do
      assert {:ok, true} =
               Boxic.FEEL.evaluate_unary_test(~S|= date("2020-01-01")|, ~D[2020-01-01])

      assert {:ok, false} =
               Boxic.FEEL.evaluate_unary_test(~S|= date("2020-01-01")|, ~D[2020-01-02])

      {:ok, day} = Boxic.FEEL.evaluate(~S|duration("P1D")|)
      assert {:ok, true} = Boxic.FEEL.evaluate_unary_test(~S|= duration("PT24H")|, day)
      assert {:ok, false} = Boxic.FEEL.evaluate_unary_test(~S|!= duration("PT24H")|, day)

      {:ok, range} = Boxic.FEEL.evaluate("[1..5]")
      assert {:ok, true} = Boxic.FEEL.evaluate_unary_test("= [1..5]", range)
      assert {:ok, false} = Boxic.FEEL.evaluate_unary_test("= (1..5]", range)
    end

    test "a plain value is compared the same way" do
      assert {:ok, true} = Boxic.FEEL.evaluate_unary_test("1.0", Decimal.new(1))
      assert {:ok, true} = Boxic.FEEL.evaluate_unary_test("1.0", 1)
      assert {:ok, false} = Boxic.FEEL.evaluate_unary_test("1.0", Decimal.new(2))
      assert {:ok, true} = Boxic.FEEL.evaluate_unary_test(~S|"a"|, "a")
    end

    test "a value of another kind is neither equal nor unequal" do
      assert {:ok, nil} = Boxic.FEEL.evaluate_unary_test("= 5", "abc")
      assert {:ok, nil} = Boxic.FEEL.evaluate_unary_test("!= 5", "abc")
    end
  end

  describe "string() of values that are not numbers, strings, or booleans" do
    for {expression, expected} <- [
          {~S|string([date("2020-01-31")])|, ~S|[@"2020-01-31"]|},
          {~S|string({a: duration("P1D")})|, ~S|{a: @"P1D"}|},
          {~S|string([time("10:00:00Z")])|, ~S|[@"10:00:00Z"]|},
          {~S|string([date and time("2020-01-31T10:00:00Z")])|, ~S|[@"2020-01-31T10:00:00Z"]|},
          {~S|string([[1..5], (1..5]])|, "[[1..5], (1..5]]"},
          {~S|string([1, "a", date("2020-01-31"), null])|, ~S|[1, "a", @"2020-01-31", null]|},
          {~S|string({a: {b: [duration("PT1H")]}})|, ~S|{a: {b: [@"PT1H"]}}|}
        ] do
      test expression do
        assert {:ok, unquote(expected)} = Boxic.FEEL.evaluate(unquote(expression))
      end
    end
  end
end
