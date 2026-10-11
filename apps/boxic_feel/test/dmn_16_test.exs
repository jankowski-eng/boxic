defmodule Boxic.FEELDMN16Test do
  use ExUnit.Case, async: true

  alias Boxic.FEEL.Error

  defp eval!(expression, context \\ %{}) do
    assert {:ok, value} = Boxic.FEEL.evaluate(expression, context)
    value
  end

  defp assert_number(expression, expected) do
    assert %Decimal{} = value = eval!(expression)
    assert Decimal.equal?(value, Decimal.new(to_string(expected))), "#{expression} = #{value}"
  end

  describe "single-parameter rounding functions" do
    test "default to a scale of zero" do
      assert_number("round up(5.5)", 6)
      assert_number("round up(-5.5)", -6)
      assert_number("round down(5.5)", 5)
      assert_number("round down(-5.5)", -5)
      assert_number("round half up(5.5)", 6)
      assert_number("round half up(-5.5)", -6)
      assert_number("round half down(5.5)", 5)
      assert_number("round half down(-5.5)", -5)
    end

    test "still accept an explicit scale, positionally or by name" do
      assert_number("round up(1.121, 2)", "1.13")
      assert_number("round down(n: -1.126, scale: 2)", "-1.12")
      assert_number("round half up(n: 5.5)", 6)
    end
  end

  describe "number(from)" do
    test "converts strings and returns numbers unchanged" do
      assert_number(~S|number("1.1")|, "1.1")
      assert_number("number(5)", 5)
    end
  end

  describe "implicit decimal to integer conversion" do
    test "discards the fraction of a rounding scale" do
      assert_number("decimal(1/3, 2.7)", "0.33")
      assert_number("floor(-1.56, 1.5)", "-1.6")
      assert_number("ceiling(-1.56, 1.9)", "-1.5")
      assert_number("round up(1.121, 2.9)", "1.13")
    end

    test "discards the fraction of list positions and lengths" do
      assert [two] = eval!("sublist([1, 2, 3, 4], 2.5, 1.9)")
      assert Decimal.equal?(two, Decimal.new(2))
      assert [one, three] = eval!("remove([1, 2, 3], 2.9)")
      assert Decimal.equal?(one, Decimal.new(1)) and Decimal.equal?(three, Decimal.new(3))
      assert [two, _one, _three] = eval!("insert before([1, 3], 1.5, 2)")
      assert Decimal.equal?(two, Decimal.new(2))
    end

    test "discards the fraction of date and time components" do
      assert ~D[2024-01-03] == eval!("date(2024, 1.9, 3.5)")
      assert "10:30:00" == eval!(~S|string(time(10.9, 30.2, 0, null))|)
    end

    test "still rejects fractional time zone offsets" do
      assert {:error, %Error{}} =
               Boxic.FEEL.evaluate(~S|time(10, 30, 0, duration("PT1.5S"))|)
    end
  end

  describe "value property" do
    test "of dates counts seconds from the epoch to UTC midnight" do
      assert_number(~S|date("1970-01-01").value|, 0)
      assert_number(~S|date("1970-01-02").value|, 86_400)
      assert_number(~S|date("1969-12-31").value|, -86_400)
    end

    test "of date and time values counts seconds from the epoch" do
      assert_number(~S|date and time("1970-01-01T00:00:10Z").value|, 10)
      assert_number(~S|date and time("1970-01-01T01:00:00+01:00").value|, 0)
      assert_number(~S|date and time("1970-01-02T00:00:00@Europe/Paris").value|, 82_800)
    end

    test "of a date and time without a zone is null" do
      assert nil == eval!(~S|date and time("2020-01-01T00:00:00").value|)
    end

    test "of times counts seconds since midnight" do
      assert_number(~S|time("01:01:01").value|, 3_661)
      assert_number(~S|time("00:00:00.5").value|, "0.5")
    end

    test "of durations counts seconds or months" do
      assert_number(~S|duration("P1DT1H").value|, 90_000)
      assert_number(~S|duration("-PT1M").value|, -60)
      assert_number(~S|duration("P1Y1M").value|, 13)
      assert_number(~S|duration("-P1Y1M").value|, -13)
    end

    test "does not shadow context entries called value" do
      assert_number("{value: 7}.value", 7)
    end
  end

  describe "date and time(date, time, timezone)" do
    test "attaches an offset" do
      assert "2024-12-24T23:59:00Z" ==
               eval!(~S|string(date and time(date("2024-12-24"), time("23:59:00"), "Z"))|)

      assert "2024-12-24T23:59:00+02:00" ==
               eval!(~S|string(date and time(date("2024-12-24"), time("23:59:00"), "+02:00"))|)
    end

    test "attaches an IANA zone identifier" do
      assert "2024-12-24T23:59:00@America/Costa_Rica" ==
               eval!(
                 ~S|string(date and time(date("2024-12-24"), time("23:59:00"), "America/Costa_Rica"))|
               )
    end

    test "uses the date part of a date and time" do
      assert "2024-12-24T23:59:00Z" ==
               eval!(
                 ~S|string(date and time(date and time("2024-12-24T01:00:00Z"), time("23:59:00"), "Z"))|
               )
    end

    test "supports named arguments" do
      assert "2024-12-24T23:59:00Z" ==
               eval!(
                 ~S|string(date and time(date: date("2024-12-24"), time: time("23:59:00"), timezone: "Z"))|
               )
    end

    test "rejects a time that already has a zone or an unknown zone" do
      assert {:error, %Error{}} =
               Boxic.FEEL.evaluate(~S|date and time(date("2024-12-24"), time("23:59:00Z"), "Z")|)

      assert {:error, %Error{}} =
               Boxic.FEEL.evaluate(
                 ~S|date and time(date("2024-12-24"), time("23:59:00"), "Not/AZone")|
               )
    end
  end

  describe "descendant expression" do
    test "collects values at every nesting depth in document order" do
      assert [%{"b" => one}, one_again] = eval!("{a: {b: {b: 1}}}...b")
      assert Decimal.equal?(one, Decimal.new(1))
      assert Decimal.equal?(one_again, Decimal.new(1))
    end

    test "yields an empty list when nothing matches" do
      assert [] == eval!("{a: 1}...b")
    end

    test "finds entries of contexts nested in lists" do
      assert [one, two] = eval!("{x: [{b: 1}, {c: {b: 2}}]}...b")
      assert Decimal.equal?(one, Decimal.new(1))
      assert Decimal.equal?(two, Decimal.new(2))
    end

    test "composes with other postfix operators" do
      assert [value] = eval!("{a: {b: 5}}...b[item > 1]")
      assert Decimal.equal?(value, Decimal.new(5))
      assert true == eval!("count({a: {b: 1, c: {b: 2}}}...b) = 2")
    end

    test "is null for anything but a context" do
      assert nil == eval!("[1, 2]...b")
      assert nil == eval!("null...b")
      assert nil == eval!("5...b")
    end

    test "reads names from the evaluation context" do
      context = %{"order" => %{"lines" => [%{"sku" => "a"}, %{"sku" => "b"}]}}
      assert ["a", "b"] == eval!("order...sku", context)
    end

    test "does not interfere with ranges or decimal literals" do
      assert %Boxic.FEEL.Range{} = eval!("[1..3]")
      assert_number("1.5 + .5", 2)
      assert true == eval!("2 in [1..3]")
    end
  end
end
