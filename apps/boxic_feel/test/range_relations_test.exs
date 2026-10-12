defmodule Boxic.FEEL.RangeRelationsTest do
  # The range functions of DMN 1.5 clause 10.3.4.7, Table 78: before, after, meets, met by,
  # overlaps, overlaps before, overlaps after, finishes, finished by, includes, during, starts,
  # started by, and coincides.
  #
  # The specification's own examples were never enough to pin them down: a relation that checks
  # only one endpoint passes every example in the table. So the test below transcribes the
  # formulas of Table 78 literally, in `Reference`, and checks every function against that
  # transcription for all proper ranges over a small domain, for every combination of endpoint
  # inclusion, and for the points around them.
  use ExUnit.Case, async: true

  import Boxic.FEEL.TestValues

  alias Boxic.FEEL.{Duration, Range}
  alias Boxic.FEEL.DateTime, as: FeelDateTime
  alias Boxic.FEEL.Time, as: FeelTime

  defmodule Reference do
    @moduledoc false
    # Table 78, "Semantics of range functions". A point is any value that Elixir orders, and a
    # range is a map with the keys of the table: `s` is `range.start`, `e` is `range.end`, `si`
    # is `range.start included`, and `ei` is `range.end included`. Each clause is the formula of
    # the table row named in its comment, with `and`, `or`, `not`, `<`, `>`, and `=` as written
    # there, and `==` between two flags where the table compares them with `=`.

    # (a) before(point1, point2)
    def before(:pp, p1, p2), do: p1 < p2

    # (b) before(point, range)
    def before(:pr, p, r), do: p < r.s or (p == r.s and not r.si)

    # (c) before(range, point)
    def before(:rp, r, p), do: r.e < p or (r.e == p and not r.ei)

    # (d) before(range1, range2)
    def before(:rr, r1, r2), do: r1.e < r2.s or ((not r1.ei or not r2.si) and r1.e == r2.s)

    # (a) after(point1, point2)
    def after_(:pp, p1, p2), do: p1 > p2

    # (b) after(point, range)
    def after_(:pr, p, r), do: p > r.e or (p == r.e and not r.ei)

    # (c) after(range, point)
    def after_(:rp, r, p), do: r.s > p or (r.s == p and not r.si)

    # (d) after(range1, range2)
    def after_(:rr, r1, r2), do: r1.s > r2.e or ((not r1.si or not r2.ei) and r1.s == r2.e)

    # (a) meets(range1, range2)
    def meets(:rr, r1, r2), do: r1.ei and r2.si and r1.e == r2.s

    # (a) met by(range1, range2)
    def met_by(:rr, r1, r2), do: r1.si and r2.ei and r1.s == r2.e

    # (a) overlaps(range1, range2)
    def overlaps(:rr, r1, r2) do
      (r1.e > r2.s or (r1.e == r2.s and r1.ei and r2.si)) and
        (r1.s < r2.e or (r1.s == r2.e and r1.si and r2.ei))
    end

    # (a) overlaps before(range1, range2)
    def overlaps_before(:rr, r1, r2) do
      (r1.s < r2.s or (r1.s == r2.s and r1.si and not r2.si)) and
        (r1.e > r2.s or (r1.e == r2.s and r1.ei and r2.si)) and
        (r1.e < r2.e or (r1.e == r2.e and (not r1.ei or r2.ei)))
    end

    # (a) overlaps after(range1, range2)
    def overlaps_after(:rr, r1, r2) do
      (r2.s < r1.s or (r2.s == r1.s and r2.si and not r1.si)) and
        (r2.e > r1.s or (r2.e == r1.s and r2.ei and r1.si)) and
        (r2.e < r1.e or (r2.e == r1.e and (not r2.ei or r1.ei)))
    end

    # (a) finishes(point, range)
    def finishes(:pr, p, r), do: r.ei and r.e == p

    # (b) finishes(range1, range2)
    def finishes(:rr, r1, r2) do
      r1.ei == r2.ei and r1.e == r2.e and
        (r1.s > r2.s or (r1.s == r2.s and (not r1.si or r2.si)))
    end

    # (a) finished by(range, point)
    def finished_by(:rp, r, p), do: r.ei and r.e == p

    # (b) finished by(range1, range2)
    def finished_by(:rr, r1, r2) do
      r1.ei == r2.ei and r1.e == r2.e and
        (r1.s < r2.s or (r1.s == r2.s and (r1.si or not r2.si)))
    end

    # (a) includes(range, point)
    def includes(:rp, r, p) do
      (r.s < p and r.e > p) or (r.s == p and r.si) or (r.e == p and r.ei)
    end

    # (b) includes(range1, range2)
    def includes(:rr, r1, r2) do
      (r1.s < r2.s or (r1.s == r2.s and (r1.si or not r2.si))) and
        (r1.e > r2.e or (r1.e == r2.e and (r1.ei or not r2.ei)))
    end

    # (a) during(point, range)
    def during(:pr, p, r) do
      (r.s < p and r.e > p) or (r.s == p and r.si) or (r.e == p and r.ei)
    end

    # (b) during(range1, range2)
    def during(:rr, r1, r2) do
      (r2.s < r1.s or (r2.s == r1.s and (r2.si or not r1.si))) and
        (r2.e > r1.e or (r2.e == r1.e and (r2.ei or not r1.ei)))
    end

    # (a) starts(point, range)
    def starts(:pr, p, r), do: r.s == p and r.si

    # (b) starts(range1, range2)
    def starts(:rr, r1, r2) do
      r1.s == r2.s and r1.si == r2.si and
        (r1.e < r2.e or (r1.e == r2.e and (not r1.ei or r2.ei)))
    end

    # (a) started by(range, point)
    def started_by(:rp, r, p), do: r.s == p and r.si

    # (b) started by(range1, range2)
    def started_by(:rr, r1, r2) do
      r1.s == r2.s and r1.si == r2.si and
        (r2.e < r1.e or (r2.e == r1.e and (not r2.ei or r1.ei)))
    end

    # (a) coincides(point1, point2)
    def coincides(:pp, p1, p2), do: p1 == p2

    # (b) coincides(range1, range2)
    def coincides(:rr, r1, r2) do
      r1.s == r2.s and r1.si == r2.si and r1.e == r2.e and r1.ei == r2.ei
    end
  end

  # The functions and the argument forms that Table 78 gives each of them. `p` is a point and
  # `r` is a range; `:pr` is a function of a point and a range.
  @relations [
    {"before", :before, [:pp, :pr, :rp, :rr]},
    {"after", :after_, [:pp, :pr, :rp, :rr]},
    {"meets", :meets, [:rr]},
    {"met by", :met_by, [:rr]},
    {"overlaps", :overlaps, [:rr]},
    {"overlaps before", :overlaps_before, [:rr]},
    {"overlaps after", :overlaps_after, [:rr]},
    {"finishes", :finishes, [:pr, :rr]},
    {"finished by", :finished_by, [:rp, :rr]},
    {"includes", :includes, [:rp, :rr]},
    {"during", :during, [:pr, :rr]},
    {"starts", :starts, [:pr, :rr]},
    {"started by", :started_by, [:rp, :rr]},
    {"coincides", :coincides, [:pp, :rr]}
  ]

  # The datatypes that the functions are checked on. Each has a function that maps a position
  # in the order `0, 1, 2, ...` to a FEEL value, so that the reference can work on integers
  # and the function under test works on the values. The second argument of the function is 0
  # for the first argument of a relation and 1 for the second, so that a value is also written
  # in a second way when that does not change it.
  @offsets [0, 18_000, -28_800]

  defp world(:numbers, i, slot) do
    if rem(i + slot, 2) == 0, do: Decimal.new(i), else: Decimal.new("#{i}.00")
  end

  defp world(:strings, i, _slot), do: <<?a + i>> <> <<?x>>
  defp world(:dates, i, _slot), do: Date.add(~D[2019-12-20], i * 20)

  # Noon UTC and the hours around it, written in the offset of its position, so that the
  # wall-clock time never leaves the day. A value always has the same offset, as times in
  # different zones are equal by `=` only when they have the same zone.
  defp world(:times, i, _slot) do
    offset = Enum.at(@offsets, Integer.mod(i, 3))
    {:ok, time} = wall_time(12 * 3600 + i * 3600 + offset, offset)
    time
  end

  # Twelve hours apart, from the end of January, written in the offset of its position, so
  # that the date, the hour, and the offset all differ from one value to the next.
  defp world(:date_times, i, _slot) do
    offset = Enum.at(@offsets, Integer.mod(i, 3))
    instant = ~N[2020-01-30 22:00:00] |> NaiveDateTime.add(i * 43_200 + offset)
    {:ok, time} = FeelTime.new(instant.hour, instant.minute, instant.second, {:offset, offset})
    FeelDateTime.new(NaiveDateTime.to_date(instant), time)
  end

  defp world(:day_time_durations, i, slot) do
    if rem(i + slot, 2) == 0,
      do: Duration.from_seconds(i * 4500 + 1),
      else: Duration.from_seconds(Decimal.new("#{i * 4500 + 1}.0"))
  end

  defp world(:year_month_durations, i, _slot),
    do: %Duration{kind: :year_month, months: i * 7, seconds: 0}

  defp wall_time(seconds, offset) do
    FeelTime.new(div(seconds, 3600), rem(div(seconds, 60), 60), 0, {:offset, offset})
  end

  # The whole sample is run for the numbers 0..4 and the points -1..5; every other datatype
  # is run for 0..2 and the points -1..3, which keeps the run short.
  @samples [
    numbers: {0..4, -1..5},
    strings: {0..2, 0..2},
    dates: {0..2, -1..3},
    times: {0..2, -1..3},
    date_times: {0..2, -1..3},
    day_time_durations: {0..2, -1..3},
    year_month_durations: {0..2, -1..3}
  ]

  # Every proper range over the domain, for each of the four combinations of included and
  # excluded endpoints: a range has at least one point, so its start is before its end, or the
  # range is `[a..a]`. The formulas of Table 78 say nothing sensible about an empty range such
  # as `[a..a)`, which is not proper.
  defp ranges(domain) do
    for s <- domain,
        e <- domain,
        s <= e,
        si <- [true, false],
        ei <- [true, false],
        s < e or (si and ei) do
      %{s: s, e: e, si: si, ei: ei}
    end
  end

  defp range_value(kind, r, slot) do
    %Range{
      start: world(kind, r.s, slot),
      end: world(kind, r.e, slot),
      start_inclusive: r.si,
      end_inclusive: r.ei
    }
  end

  defp operands(domain, kind, form, points) do
    ranges = ranges(domain)

    case form do
      :pp -> for p1 <- points, p2 <- points, do: {p1, p2}
      :pr -> for p <- points, r <- ranges, do: {p, r}
      :rp -> for r <- ranges, p <- points, do: {r, p}
      :rr -> for r1 <- ranges, r2 <- ranges, do: {r1, r2}
    end
    |> Enum.map(fn {a, b} -> {a, b, argument(kind, a, 0), argument(kind, b, 1)} end)
  end

  defp argument(kind, %{} = range, slot), do: range_value(kind, range, slot)
  defp argument(kind, point, slot), do: world(kind, point, slot)

  # The calls of `name` for which the function under test and the reference disagree.
  defp mismatches(kind, name, reference, forms) do
    {domain, points} = Keyword.fetch!(@samples, kind)
    {:ok, ast} = Boxic.FEEL.parse(name <> "(a, b)")

    Enum.flat_map(forms, fn form ->
      domain
      |> operands(kind, form, points)
      |> Enum.flat_map(fn {a, b, a_value, b_value} ->
        expected = {:ok, apply(Reference, reference, [form, a, b])}
        actual = Boxic.FEEL.evaluate_ast(ast, %{"a" => a_value, "b" => b_value})
        if actual == expected, do: [], else: [{name, form, a, b, expected, actual}]
      end)
    end)
  end

  for {kind, _sizes} <- @samples, {name, reference, forms} <- @relations do
    test "#{name} agrees with Table 78 on #{kind}" do
      mismatches = mismatches(unquote(kind), unquote(name), unquote(reference), unquote(forms))

      assert mismatches == [],
             "#{length(mismatches)} mismatches, the first ones: " <>
               inspect(Enum.take(mismatches, 5))
    end
  end

  # The cases in which the functions disagreed with Table 78, once for each relation whose
  # formula looks at the second endpoint, as well as the first.
  describe "relations that look at both endpoints" do
    for {expression, expected} <- [
          {~S|starts([1..10], [1..5])|, "false"},
          {~S|starts([1..5], [1..10])|, "true"},
          {~S|started by([1..5], [1..10])|, "false"},
          {~S|started by([1..10], [1..5])|, "true"},
          {~S|finishes([1..10], [5..10])|, "false"},
          {~S|finishes([5..10], [1..10])|, "true"},
          {~S|finished by([5..10], [1..10])|, "false"},
          {~S|finished by([1..10], [5..10])|, "true"},
          {~S|overlaps before([0..5], (0..5))|, "false"},
          {~S|overlaps after((0..5), [0..5])|, "false"}
        ] do
      test expression do
        assert eval(unquote(expression)) == unquote(expected)
      end
    end

    # Table 78 has no exception for ranges that coincide: both ends of each range reach into
    # the other range.
    test "overlaps is true for ranges that are equal" do
      assert eval(~S|overlaps([1..5], [1..5])|) == "true"
      assert eval(~S|overlaps([1..5), [1..5))|) == "true"
      assert eval(~S|overlaps([5..5], [5..5])|) == "true"
      assert eval(~S|overlaps((1..5), (1..5))|) == "true"
    end
  end

  # The examples in the "Example" column of Table 78.
  describe "the examples of Table 78" do
    for {expression, expected} <- [
          {"before( 1, 10 )", true},
          {"before( 10, 1 )", false},
          {"before( 1, [1..10] )", false},
          {"before( 1, (1..10] )", true},
          {"before( 1, [5..10] )", true},
          {"before( [1..10], 10 )", false},
          {"before( [1..10), 10 )", true},
          {"before( [1..10], 15 )", true},
          {"before( [1..10], [15..20] )", true},
          {"before( [1..10], [10..20] )", false},
          {"before( [1..10), [10..20] )", true},
          {"before( [1..10], (10..20] )", true},
          {"after( 10, 5 )", true},
          {"after( 5, 10 )", false},
          {"after( 12, [1..10] )", true},
          {"after( 10, [1..10) )", true},
          {"after( 10, [1..10] )", false},
          {"after( [11..20], 12 )", false},
          {"after( [11..20], 10 )", true},
          {"after( (11..20], 11 )", true},
          {"after( [11..20], 11 )", false},
          {"after( [11..20], [1..10] )", true},
          {"after( [1..10], [11..20] )", false},
          {"after( [11..20], [1..11) )", true},
          {"after( (11..20], [1..11] )", true},
          {"meets( [1..5], [5..10] )", true},
          {"meets( [1..5), [5..10] )", false},
          {"meets( [1..5], (5..10] )", false},
          {"meets( [1..5], [6..10] )", false},
          {"met by( [5..10], [1..5] )", true},
          {"met by( [5..10], [1..5) )", false},
          {"met by( (5..10], [1..5] )", false},
          {"met by( [6..10], [1..5] )", false},
          {"overlaps( [1..5], [3..8] )", true},
          {"overlaps( [3..8], [1..5] )", true},
          {"overlaps( [1..8], [3..5] )", true},
          {"overlaps( [3..5], [1..8] )", true},
          {"overlaps( [1..5], [6..8] )", false},
          {"overlaps( [6..8], [1..5] )", false},
          {"overlaps( [1..5], [5..8] )", true},
          {"overlaps( [1..5], (5..8] )", false},
          {"overlaps( [1..5), [5..8] )", false},
          {"overlaps( [1..5), (5..8] )", false},
          {"overlaps( [5..8], [1..5] )", true},
          {"overlaps( (5..8], [1..5] )", false},
          {"overlaps( [5..8], [1..5) )", false},
          {"overlaps( (5..8], [1..5) )", false},
          {"overlaps before( [1..5], [3..8] )", true},
          {"overlaps before( [1..5], [6..8] )", false},
          {"overlaps before( [1..5], [5..8] )", true},
          {"overlaps before( [1..5], (5..8] )", false},
          {"overlaps before( [1..5), [5..8] )", false},
          {"overlaps before( [1..5), (1..5] )", true},
          {"overlaps before( [1..5], (1..5] )", true},
          {"overlaps before( [1..5), [1..5] )", false},
          {"overlaps before( [1..5], [1..5] )", false},
          {"overlaps after( [3..8], [1..5] )", true},
          {"overlaps after( [6..8], [1..5] )", false},
          {"overlaps after( [5..8], [1..5] )", true},
          {"overlaps after( (5..8], [1..5] )", false},
          {"overlaps after( [5..8], [1..5) )", false},
          {"overlaps after( (1..5], [1..5) )", true},
          {"overlaps after( (1..5], [1..5] )", true},
          {"overlaps after( [1..5], [1..5) )", false},
          {"overlaps after( [1..5], [1..5] )", false},
          {"finishes( 10, [1..10] )", true},
          {"finishes( 10, [1..10) )", false},
          {"finishes( [5..10], [1..10] )", true},
          {"finishes( [5..10), [1..10] )", false},
          {"finishes( [5..10), [1..10) )", true},
          {"finishes( [1..10], [1..10] )", true},
          {"finishes( (1..10], [1..10] )", true},
          {"finished by( [1..10], 10 )", true},
          {"finished by( [1..10), 10 )", false},
          {"finished by( [1..10], [5..10] )", true},
          {"finished by( [1..10], [5..10) )", false},
          {"finished by( [1..10), [5..10) )", true},
          {"finished by( [1..10], [1..10] )", true},
          {"finished by( [1..10], (1..10] )", true},
          {"includes( [1..10], 5 )", true},
          {"includes( [1..10], 12 )", false},
          {"includes( [1..10], 1 )", true},
          {"includes( [1..10], 10 )", true},
          {"includes( (1..10], 1 )", false},
          {"includes( [1..10), 10 )", false},
          {"includes( [1..10], [4..6] )", true},
          {"includes( [1..10], [1..5] )", true},
          {"includes( (1..10], (1..5] )", true},
          {"includes( [1..10], (1..10) )", true},
          {"includes( [1..10), [5..10) )", true},
          {"includes( [1..10], [1..10) )", true},
          {"includes( [1..10], (1..10] )", true},
          {"includes( [1..10], [1..10] )", true},
          {"during( 5, [1..10] )", true},
          {"during( 12, [1..10] )", false},
          {"during( 1, [1..10] )", true},
          {"during( 10, [1..10] )", true},
          {"during( 1, (1..10] )", false},
          {"during( 10, [1..10) )", false},
          {"during( [4..6], [1..10] )", true},
          {"during( [1..5], [1..10] )", true},
          {"during( (1..5], (1..10] )", true},
          {"during( (1..10), [1..10] )", true},
          {"during( [5..10), [1..10) )", true},
          {"during( [1..10), [1..10] )", true},
          {"during( (1..10], [1..10] )", true},
          {"during( [1..10], [1..10] )", true},
          {"starts( 1, [1..10] )", true},
          {"starts( 1, (1..10] )", false},
          {"starts( 2, [1..10] )", false},
          {"starts( [1..5], [1..10] )", true},
          {"starts( (1..5], (1..10] )", true},
          {"starts( (1..5], [1..10] )", false},
          {"starts( [1..5], (1..10] )", false},
          {"starts( [1..10], [1..10] )", true},
          {"starts( [1..10), [1..10] )", true},
          {"starts( (1..10), (1..10) )", true},
          {"started by( [1..10], 1 )", true},
          {"started by( (1..10], 1 )", false},
          {"started by( [1..10], 2 )", false},
          {"started by( [1..10], [1..5] )", true},
          {"started by( (1..10], (1..5] )", true},
          {"started by( [1..10], (1..5] )", false},
          {"started by( (1..10], [1..5] )", false},
          {"started by( [1..10], [1..10] )", true},
          {"started by( [1..10], [1..10) )", true},
          {"started by( (1..10), (1..10) )", true},
          {"coincides( 5, 5 )", true},
          {"coincides( 3, 4 )", false},
          {"coincides( [1..5], [1..5] )", true},
          {"coincides( (1..5), [1..5] )", false},
          {"coincides( [1..5], [2..6] )", false}
        ] do
      test expression do
        assert eval(unquote(expression)) == to_string(unquote(expected))
      end
    end
  end

  # The functions order their operands as `<` does (Table 54): numbers and strings by value,
  # dates, times and date-times by instant, and durations of one kind by length. Operands that
  # have no order give null.

  describe "range functions order date-times by instant" do
    for {expression, expected} <- [
          {~S|before(date and time("2020-02-01T00:00:00Z"), date and time("2020-01-31T00:00:00Z"))|,
           "false"},
          {~S|before(date and time("2020-01-31T00:00:00Z"), date and time("2020-02-01T00:00:00Z"))|,
           "true"},
          {~S|before(date and time("2020-01-31T00:00:00Z"), date and time("2021-01-01T00:00:00Z"))|,
           "true"},
          {~S|before(date and time("2020-01-01T10:00:00+05:00"), date and time("2020-01-01T06:00:00Z"))|,
           "true"},
          {~S|after(date and time("2020-01-01T10:00:00+05:00"), date and time("2020-01-01T06:00:00Z"))|,
           "false"},
          {~S|before(date and time("2020-01-01T10:00:00+05:00"), date and time("2020-01-01T05:00:00Z"))|,
           "false"},
          {~S|during(date and time("2020-02-15T00:00:00Z"), [date and time("2020-02-01T00:00:00Z")..date and time("2020-03-01T00:00:00Z")])|,
           "true"},
          {~S|during(date and time("2021-02-15T00:00:00Z"), [date and time("2020-02-01T00:00:00Z")..date and time("2020-03-01T00:00:00Z")])|,
           "false"},
          {~S|overlaps([date and time("2020-01-01T00:00:00Z")..date and time("2020-03-01T00:00:00Z")], [date and time("2020-02-01T00:00:00Z")..date and time("2020-04-01T00:00:00Z")])|,
           "true"},
          {~S|overlaps([date and time("2020-01-01T10:00:00+05:00")..date and time("2020-01-01T20:00:00+05:00")], [date and time("2020-01-01T08:00:00Z")..date and time("2020-01-01T09:00:00Z")])|,
           "true"},
          {~S|overlaps([date and time("2020-01-01T10:00:00+05:00")..date and time("2020-01-01T20:00:00+05:00")], [date and time("2020-01-01T16:00:00Z")..date and time("2020-01-01T17:00:00Z")])|,
           "false"},
          {~S|meets([date and time("2020-01-01T00:00:00Z")..date and time("2020-01-01T10:00:00+05:00")], [date and time("2020-01-01T05:00:00Z")..date and time("2020-01-02T00:00:00Z")])|,
           "true"}
        ] do
      test expression do
        assert eval(unquote(expression)) == unquote(expected)
      end
    end
  end

  describe "range functions order times by offset" do
    for {expression, expected} <- [
          {~S|before(time("10:00:00+02:00"), time("09:30:00Z"))|, "true"},
          {~S|after(time("10:00:00+02:00"), time("09:30:00Z"))|, "false"},
          {~S|before(time("10:00:00Z"), time("11:00:00+02:00"))|, "false"},
          {~S|before(time("10:00:00.5"), time("10:00:00.25"))|, "false"},
          {~S|after(time("10:00:00.5"), time("10:00:00.25"))|, "true"},
          {~S|includes([time("08:00:00Z")..time("12:00:00Z")], time("11:00:00+02:00"))|, "true"},
          {~S|includes([time("08:00:00Z")..time("12:00:00Z")], time("15:00:00+02:00"))|, "false"}
        ] do
      test expression do
        assert eval(unquote(expression)) == unquote(expected)
      end
    end

    # Table 54: if one input has a null time offset, it uses the offset of the other input.
    test "a time without an offset takes the offset of the other time" do
      assert eval(~S|time("10:00:00") < time("11:00:00Z")|) == "true"
      assert eval(~S|time("10:00:00") > time("11:00:00Z")|) == "false"
      assert eval(~S|time("12:00:00") > time("11:00:00+02:00")|) == "true"
      assert eval(~S|before(time("10:00:00"), time("11:00:00Z"))|) == "true"
      assert eval(~S|@"10:00:00" in [@"09:00:00Z"..@"11:00:00Z"]|) == "true"
      assert eval(~S|@"12:00:00" in [@"09:00:00Z"..@"11:00:00Z"]|) == "false"
    end

    test "a date-time without an offset takes the offset of the other date-time" do
      assert eval(
               ~S|date and time("2020-01-01T10:00:00") < date and time("2020-01-01T11:00:00Z")|
             ) ==
               "true"

      assert eval(
               ~S|before(date and time("2020-01-01T12:00:00"), date and time("2020-01-01T11:00:00Z"))|
             ) ==
               "false"
    end

    test "times in different named zones cannot be ordered" do
      assert eval(~S|time("10:00:00@Europe/Paris") < time("11:00:00Z")|) == "null"
      assert eval(~S|before(time("10:00:00@Europe/Paris"), time("11:00:00Z"))|) == "null"

      assert eval(~S|time("10:00:00@Europe/Paris") in [time("09:00:00Z")..time("11:00:00Z")]|) ==
               "null"
    end
  end

  describe "range functions order durations of one kind" do
    for {expression, expected} <- [
          {~S|before(@"PT1.5S", @"PT10S")|, "true"},
          {~S|after(@"PT1.5S", @"PT10S")|, "false"},
          {~S|before(@"PT10S", @"PT1.5S")|, "false"},
          {~S|before(@"P1Y", @"P2Y")|, "true"},
          {~S|after(@"P13M", @"P1Y")|, "true"},
          {~S|includes([@"PT0.5S"..@"PT10S"], @"PT5S")|, "true"},
          {~S|includes([@"PT0.5S"..@"PT10S"], @"PT11S")|, "false"},
          {~S|during(@"PT5S", [@"PT0.5S"..@"PT10S"])|, "true"},
          {~S|includes([@"P1Y"..@"P3Y"], @"P2Y")|, "true"},
          # Durations of different kinds have no order.
          {~S|before(@"P1Y", @"PT2H")|, "null"},
          {~S|after(@"P1Y", @"PT2H")|, "null"},
          {~S|includes([@"PT1H"..@"PT3H"], @"P1Y")|, "null"},
          {~S|@"PT1H" in [@"PT0H"..@"P1Y"]|, "null"},
          {~S|@"PT1H" in [@"P0Y"..@"P1Y"]|, "null"}
        ] do
      test expression do
        assert eval(unquote(expression)) == unquote(expected)
      end
    end
  end

  describe "range functions order numbers, strings, dates, and booleans" do
    for {expression, expected} <- [
          {~S|before(1, 10)|, "true"},
          {~S|before(1.0, 1)|, "false"},
          {~S|after(1.00, 1)|, "false"},
          {~S|before("a", "b")|, "true"},
          {~S|before("b", "a")|, "false"},
          {~S|before("Z", "a")|, "true"},
          {~S|before("a", "aa")|, "true"},
          {~S|before(date("2020-01-01"), date("2020-01-02"))|, "true"},
          {~S|after(date("2020-01-01"), date("2020-01-02"))|, "false"},
          {~S|includes([date("2020-01-01")..date("2020-12-31")], date("2020-06-15"))|, "true"},
          {~S|includes(["a".."m"], "c")|, "true"},
          {~S|includes(["a".."m"], "z")|, "false"},
          # The specification gives booleans no order. They keep the order `false < true` that
          # `<` and `in` have always given them.
          {~S|before(false, true)|, "true"},
          {~S|before(true, false)|, "false"},
          {~S|false < true|, "true"}
        ] do
      test expression do
        assert eval(unquote(expression)) == unquote(expected)
      end
    end
  end

  describe "range functions give null for operands that cannot be compared" do
    for expression <- [
          ~S|before(1, "a")|,
          ~S|before("a", 1)|,
          ~S|after(1, "a")|,
          ~S|before(1, true)|,
          ~S|before([1..2], "a")|,
          ~S|before("a", [1..2])|,
          ~S|after([1..2], "a")|,
          ~S|before({a: 1}, {a: 2})|,
          ~S|before([1, 2], [3, 4])|,
          ~S|before(date("2020-01-01"), time("10:00:00Z"))|,
          ~S|before(date("2020-01-01"), date and time("2020-01-02T00:00:00"))|,
          ~S|before(date and time("2020-01-01T00:00:00Z"), date("2020-01-02"))|,
          ~S|before(time("10:00:00Z"), date and time("2020-01-02T10:00:00Z"))|,
          ~S|before(@"P1Y", @"PT2H")|,
          ~S|before(1, @"PT2H")|,
          ~S|includes([1..5], "a")|,
          ~S|includes(["a".."c"], 2)|,
          ~S|during("a", [1..5])|,
          ~S|before([1..5], ["a".."c"])|,
          ~S|includes([1..5], ["a".."c"])|,
          ~S|overlaps([1..5], ["a".."c"])|,
          ~S|meets([1..5], ["a".."c"])|,
          ~S|coincides([1..5], ["a".."c"])|
        ] do
      test expression do
        assert eval(unquote(expression)) == "null"
      end
    end
  end

  describe "a range with a null endpoint" do
    # `in` gives null for a range whose endpoint is null, and so do the range functions. Section
    # 10.3.2.7 requires the endpoints of a range to be ordered values, and says that only a
    # comparison such as `<10` leaves the other endpoint undefined.
    for expression <- [
          ~S|100 in [1..null)|,
          ~S|before([1..null), 100)|,
          ~S|after(100, [1..null))|,
          ~S|before(100, [null..200])|,
          ~S|after([null..200], 100)|,
          ~S|includes([1..null), 100)|,
          ~S|includes([null..200], 100)|,
          ~S|during(100, [1..null))|,
          ~S|during(100, [null..200])|,
          ~S|before([1..null), [5..10])|,
          ~S|includes([1..null), [5..10])|,
          ~S|meets([1..null], [5..10])|,
          ~S|overlaps([1..null), [5..10])|,
          ~S|coincides([1..null), [1..null))|
        ] do
      test expression do
        assert eval(unquote(expression)) == "null"
      end
    end

    test "a null point is null" do
      assert eval(~S|before(null, [1..5])|) == "null"
      assert eval(~S|includes([1..5], null)|) == "null"
    end
  end
end
