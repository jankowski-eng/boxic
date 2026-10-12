defmodule Boxic.FEEL.MinMaxTest do
  # `min` and `max` take comparable items (DMN 1.5 Table 75): numbers, strings, dates, times,
  # date-times, and durations of one kind, ordered as in Table 54. Items that are not comparable
  # give null.
  use ExUnit.Case, async: true

  import Boxic.FEEL.TestValues

  describe "min and max order comparable items" do
    for {expression, expected} <- [
          {~S|min(["b", "a"])|, ~S|"a"|},
          {~S|max(["b", "a"])|, ~S|"b"|},
          {~S|min("b", "a", "c")|, ~S|"a"|},
          {~S|max("b", "a", "c")|, ~S|"c"|},
          {~S|max([date("2020-01-01"), date("2019-01-01")])|, "2020-01-01"},
          {~S|min([date("2020-01-01"), date("2019-01-01")])|, "2019-01-01"},
          {~S|max(date("2020-01-01"), date("2019-01-01"))|, "2020-01-01"},
          {~S|max([time("10:00:00"), time("09:00:00")])|, "10:00:00"},
          {~S|min([time("10:00:00"), time("09:00:00")])|, "09:00:00"},
          {~S|max([time("10:00:00Z"), time("09:00:00+02:00")])|, "10:00:00Z"},
          {~S|min([time("10:00:00Z"), time("09:00:00+02:00")])|, "09:00:00+02:00"},
          {~S|max([duration("P1D"), duration("PT1H")])|, "P1D"},
          {~S|min([duration("P1D"), duration("PT1H")])|, "PT1H"},
          {~S|max([duration("P1Y"), duration("P13M")])|, "P1Y1M"},
          {~S|max([date and time("2020-01-01T10:00:00Z"), date and time("2020-01-01T09:00:00Z")])|,
           "2020-01-01T10:00:00Z"},
          {~S|min([date and time("2020-01-01T10:00:00Z"), date and time("2020-01-01T09:00:00Z")])|,
           "2020-01-01T09:00:00Z"},
          {~S|max([date and time("2020-01-01T10:00:00+05:00"), date and time("2020-01-01T06:00:00Z")])|,
           "2020-01-01T06:00:00Z"},
          # Numbers, and the forms that were already supported.
          {~S|max([1, 3, 2])|, "3"},
          {~S|min([1, 3, 2])|, "1"},
          {~S|max(1, 3, 2)|, "3"},
          {~S|min(5)|, "5"},
          {~S|max(5)|, "5"},
          {~S|min([5])|, "5"},
          {~S|max([])|, "null"},
          {~S|min([])|, "null"}
        ] do
      test expression do
        assert eval(unquote(expression)) == unquote(expected)
      end
    end

    # Items of different kinds, or items that have no order, give null.
    for expression <- [
          ~S|min([1, "a"])|,
          ~S|max(["a", 1])|,
          ~S|max([1, 2, "a"])|,
          ~S|min([1, null])|,
          ~S|max([null, 1])|,
          ~S|max([date("2020-01-01"), time("10:00:00")])|,
          ~S|max([date("2020-01-01"), date and time("2020-01-01T00:00:00")])|,
          ~S|max([duration("P1Y"), duration("PT1H")])|,
          ~S|min(duration("P1Y"), duration("PT1H"))|,
          ~S|max([[1], [2]])|,
          ~S|max([{a: 1}, {a: 2}])|,
          ~S|max([[1..2], [3..4]])|,
          ~S|min(1, "a")|,
          ~S|max([time("10:00:00@Europe/Paris"), time("09:00:00Z")])|
        ] do
      test expression do
        assert eval(unquote(expression)) == "null"
      end
    end
  end
end
