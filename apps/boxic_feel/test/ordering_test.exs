defmodule Boxic.FEEL.OrderingTest do
  # One ordering of FEEL values (DMN 1.5 Table 54) backs `<`, `>`, `<=`, `>=`, `between`, and `in`
  # with a range or a comparison. Two values that have no order, such as durations of different
  # kinds, or two times in different named zones, are not comparable, and the result is null,
  # not false. The range functions (see RangeRelationsTest), `min` and `max` (see MinMaxTest),
  # and the unary tests (see UnaryTestsTest) use the same order.
  use ExUnit.Case, async: true

  import Boxic.FEEL.TestValues

  describe "ordering by instant" do
    for {expression, expected} <- [
          {~S|date and time("2020-02-01T00:00:00Z") > date and time("2020-01-31T00:00:00Z")|,
           "true"},
          {~S|date and time("2020-01-31T00:00:00Z") < date and time("2021-01-01T00:00:00Z")|,
           "true"},
          {~S|date and time("2020-01-01T10:00:00+05:00") < date and time("2020-01-01T06:00:00Z")|,
           "true"},
          {~S|date and time("2020-01-01T10:00:00+05:00") <= date and time("2020-01-01T05:00:00Z")|,
           "true"},
          {~S|date and time("2020-01-01T10:00:00+05:00") < date and time("2020-01-01T05:00:00Z")|,
           "false"},
          {~S|time("10:00:00+02:00") < time("09:30:00Z")|, "true"},
          {~S|time("10:00:00Z") < time("11:00:00+02:00")|, "false"},
          {~S|time("10:00:00.5") > time("10:00:00.25")|, "true"},
          {~S|@"PT1.5S" < @"PT10S"|, "true"},
          {~S|@"P13M" > @"P1Y"|, "true"},
          {~S|1.0 <= 1|, "true"},
          {~S|"Z" < "a"|, "true"},
          {~S|date("2020-01-01") < date("2020-01-02")|, "true"}
        ] do
      test expression do
        assert eval(unquote(expression)) == unquote(expected)
      end
    end
  end

  # Table 54: if one input has a null time offset, it uses the offset of the other input.
  describe "a time or date-time without an offset" do
    test "takes the offset of the other time" do
      assert eval(~S|time("10:00:00") < time("11:00:00Z")|) == "true"
      assert eval(~S|time("10:00:00") > time("11:00:00Z")|) == "false"
      assert eval(~S|time("12:00:00") > time("11:00:00+02:00")|) == "true"
      assert eval(~S|time("12:00:00") <= time("12:00:00+02:00")|) == "true"
      assert eval(~S|@"10:00:00" in [@"09:00:00Z"..@"11:00:00Z"]|) == "true"
      assert eval(~S|@"12:00:00" in [@"09:00:00Z"..@"11:00:00Z"]|) == "false"
      assert eval(~S|time("10:00:00") between time("09:00:00Z") and time("11:00:00Z")|) == "true"
    end

    test "takes the offset of the other date-time" do
      assert eval(
               ~S|date and time("2020-01-01T10:00:00") < date and time("2020-01-01T11:00:00Z")|
             ) ==
               "true"

      assert eval(
               ~S|date and time("2020-01-01T12:00:00") < date and time("2020-01-01T11:00:00Z")|
             ) ==
               "false"

      assert eval(
               ~S|date and time("2020-01-01T10:00:00") in (> date and time("2020-01-01T09:00:00-05:00"))|
             ) ==
               "true"
    end

    # Equality is not changed by this: `=` still compares the zone (TCK case 0068).
    test "is still not equal to a time with an offset" do
      assert eval(~S|time("10:00:00") = time("10:00:00Z")|) == "false"
      assert eval(~S|time("10:00:00") <= time("10:00:00Z")|) == "true"
    end
  end

  describe "values that have no order" do
    test "times in different named zones, or in a named zone and an offset" do
      assert eval(~S|time("10:00:00@Europe/Paris") < time("11:00:00Z")|) == "null"
      assert eval(~S|time("10:00:00@Europe/Paris") < time("11:00:00@Asia/Tokyo")|) == "null"

      assert eval(~S|time("10:00:00@Europe/Paris") in [time("09:00:00Z")..time("11:00:00Z")]|) ==
               "null"
    end

    test "durations of different kinds" do
      assert eval(~S|@"PT1H" < @"P1Y"|) == "null"
      assert eval(~S|@"P1Y" >= @"PT1H"|) == "null"
      assert eval(~S|@"PT1H" between @"PT0H" and @"P1Y"|) == "null"
    end

    test "a value of another kind is an error in a comparison, and null for a null" do
      assert eval(~S|1 < "a"|) == "error:type_error"
      assert eval(~S|1 < null|) == "null"
      assert eval(~S|null >= "a"|) == "null"
    end
  end

  describe "in, between, and the comparison operators" do
    test "a bound that cannot be ordered with the value gives null, not false" do
      assert eval(~S|@"PT1H" in [@"PT0H"..@"P1Y"]|) == "null"
      assert eval(~S|"a" in [1..100]|) == "null"
      assert eval(~S|1 in ["a".."z"]|) == "null"
      assert eval(~S|date("2020-01-01") in [time("09:00:00Z")..time("11:00:00Z")]|) == "null"
      assert eval(~S|@"PT1H" < @"P1Y"|) == "null"
      assert eval(~S|@"PT1H" between @"PT0H" and @"P1Y"|) == "null"
    end

    test "ordered values still give true and false" do
      assert eval(~S|@"PT1H" in [@"PT0H"..@"PT2H"]|) == "true"
      assert eval(~S|@"PT3H" in [@"PT0H"..@"PT2H"]|) == "false"

      assert eval(
               ~S|date and time("2020-01-01T10:00:00+05:00") in [date and time("2020-01-01T04:00:00Z")..date and time("2020-01-01T06:00:00Z")]|
             ) ==
               "true"

      assert eval(~S|time("10:00:00+02:00") in [time("08:00:00Z")..time("08:30:00Z")]|) ==
               "true"

      assert eval(~S|time("10:00:00+02:00") > time("09:30:00Z")|) == "false"
    end

    test "the operators compare operands of different kinds as before" do
      assert eval(~S|1 < "a"|) == "error:type_error"
      assert eval(~S|1 < null|) == "null"
    end
  end
end
