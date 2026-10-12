defmodule Boxic.FEEL.CrashFixesTest do
  # Inputs that used to raise out of the public API. Failures must be returned as values.
  use ExUnit.Case

  alias Boxic.FEEL.{Duration, Error}

  defp evaluate(expression, context \\ %{}), do: Boxic.FEEL.evaluate(expression, context)

  # A FEEL string literal containing the backslash escape `escape`. The backslash is built
  # separately so that the escapes in the tests stay literal.
  defp quoted(escape), do: ~s|"| <> <<92>> <> escape <> ~s|"|

  describe "invalid temporal at-literals" do
    for value <- [
          "2020-02-30",
          "2020-13-45",
          "2020-00-10",
          "2020-02-30T10:00:00Z",
          "2021-02-29T10:00:00",
          "2020-01-01T25:00:00",
          "P",
          "PT",
          "PT1",
          "-P",
          "P1.5D",
          ""
        ] do
      test "@\"#{value}\" is a syntax error" do
        literal = ~s|@"#{unquote(value)}"|

        assert {:error, %Error{code: :invalid_syntax, message: "invalid at-literal"}} =
                 evaluate(literal)

        assert {:error, %Error{code: :invalid_syntax}} = Boxic.FEEL.parse(literal)
      end
    end

    test "valid at-literals still evaluate" do
      assert {:ok, ~D[2020-02-29]} = evaluate(~S|@"2020-02-29"|)
      assert {:ok, %Boxic.FEEL.DateTime{}} = evaluate(~S|@"2020-02-29T10:00:00Z"|)
      assert {:ok, %Boxic.FEEL.Time{}} = evaluate(~S|@"10:00:00"|)
      assert {:ok, %Duration{kind: :day_time}} = evaluate(~S|@"P1D"|)
      assert {:ok, %Duration{kind: :year_month}} = evaluate(~S|@"-P1Y2M"|)
    end

    test "the parsers return :error for impossible dates" do
      assert :error = Boxic.FEEL.DateTime.parse("2020-02-30T10:00:00")
      assert :error = Boxic.FEEL.DateTime.parse("2020-13-45T10:00:00Z")
      assert {:error, :invalid_duration} = Duration.parse_iso8601("PT")
    end

    test "the constructor functions give no value for the same inputs" do
      for expression <- [
            ~S|date("2020-02-30")|,
            ~S|date and time("2020-02-30T10:00:00")|,
            ~S|date and time("2020-13-45T10:00:00Z")|
          ] do
        # Whether such a call is null or an error is decided elsewhere; it must not raise.
        assert match?({:ok, nil}, evaluate(expression)) or
                 match?({:error, %Error{}}, evaluate(expression)),
               expression
      end
    end
  end

  describe "string literal escapes" do
    for {name, escape} <- [
          {"a lone surrogate in a big-U escape", "U00D800"},
          {"the last surrogate in a big-U escape", "U00DFFF"},
          {"a big-U escape beyond the Unicode range", "U110000"},
          {"a sign in a small-u escape", "u-123"},
          {"a plus sign in a small-u escape", "u+123"},
          {"a sign in a big-U escape", "U-00123"},
          {"a non-hex digit in a small-u escape", "u12G4"},
          {"a lone high surrogate", "uD800"},
          {"a lone low surrogate", "uDC00"},
          {"a high surrogate followed by a non-surrogate", "uD800" <> <<92>> <> "u0041"}
        ] do
      test "#{name} is a syntax error" do
        literal = quoted(unquote(escape))
        assert {:error, %Error{code: :invalid_syntax}} = evaluate(literal)
        assert {:error, %Error{code: :invalid_syntax}} = Boxic.FEEL.parse(literal)
      end
    end

    test "valid escapes still decode" do
      assert {:ok, "A"} = evaluate(quoted("u0041"))
      assert {:ok, "A"} = evaluate(quoted("U000041"))
      assert {:ok, <<0xFF::utf8>>} = evaluate(quoted("u00ff"))
      assert {:ok, <<0x1F600::utf8>>} = evaluate(quoted("U01F600"))
      assert {:ok, <<0x1F600::utf8>>} = evaluate(quoted("uD83D" <> <<92>> <> "uDE00"))
      assert {:ok, <<0x10FFFF::utf8>>} = evaluate(quoted("U10FFFF"))
    end
  end

  describe "invalid UTF-8 in the source text" do
    for {name, source} <- [
          {"inside a string literal", "\"a" <> <<255>> <> "\""},
          {"after an identifier", "abc" <> <<255>>},
          {"inside an at-literal", "@\"" <> <<255>> <> "\""},
          {"as the whole expression", <<255>>},
          {"after a number", "1 + " <> <<0xC3>>}
        ] do
      test "#{name} is a syntax error" do
        assert {:error, %Error{code: :invalid_syntax}} = evaluate(unquote(source))
        assert {:error, %Error{code: :invalid_syntax}} = Boxic.FEEL.parse(unquote(source))

        assert {:error, %Error{code: :invalid_syntax}} =
                 Boxic.FEEL.evaluate_unary_test(unquote(source), Decimal.new(1))
      end
    end

    test "valid multi-byte text is unaffected" do
      assert {:ok, "ünïcödé 😀"} = evaluate(~S|"ünïcödé 😀"|)
      assert {:ok, three} = evaluate(~S|string length("ünï")|)
      assert Decimal.equal?(three, Decimal.new(3))
    end
  end

  describe "malformed syntax trees" do
    test "context entries that are not key/value pairs are invalid" do
      assert {:error, %Error{code: :invalid_ast}} = Boxic.FEEL.evaluate_ast({:context, [1]}, %{})
      assert {:error, %Error{code: :invalid_ast}} = Boxic.FEEL.evaluate_ast({:context, [:a]}, %{})

      assert {:error, %Error{code: :invalid_ast}} =
               Boxic.FEEL.evaluate_ast({:context, [{"a", {:literal, 1}}, :b]}, %{})
    end

    test "function parameters and for bindings that are not pairs are invalid" do
      assert {:error, %Error{code: :invalid_ast}} =
               Boxic.FEEL.evaluate_ast({:function, [1], {:literal, 1}}, %{})

      assert {:error, %Error{code: :invalid_ast}} =
               Boxic.FEEL.evaluate_ast({:for, [1], {:literal, 1}}, %{})
    end

    test "improper lists are invalid" do
      assert {:error, %Error{code: :invalid_ast}} =
               Boxic.FEEL.evaluate_ast({:list, [{:literal, 1} | {:literal, 2}]}, %{})

      assert {:error, %Error{code: :invalid_ast}} =
               Boxic.FEEL.evaluate_ast({:call, {:identifier, "f"}, [{:literal, 1} | 2]}, %{})
    end

    test "a named argument outside a call is invalid" do
      assert {:error, %Error{code: :invalid_ast}} =
               Boxic.FEEL.evaluate_ast({:named_arg, "x", {:literal, 1}}, %{})

      assert {:error, %Error{code: :invalid_ast}} =
               Boxic.FEEL.evaluate_ast({:list, [{:named_arg, "x", {:literal, 1}}]}, %{})

      assert {:error, %Error{code: :invalid_ast}} =
               Boxic.FEEL.evaluate_ast(
                 {:call, {:identifier, "f"}, [{:named_arg, "", {:literal, 1}}]},
                 %{}
               )
    end

    test "well-formed trees are accepted" do
      assert {:ok, %{"a" => _}} = Boxic.FEEL.evaluate_ast({:context, [{"a", {:literal, 1}}]}, %{})
      assert {:ok, []} = Boxic.FEEL.evaluate_ast({:list, []}, %{})
    end
  end

  describe "instance of" do
    test "takes a single type expression, so the rest of the expression still parses" do
      assert {:ok, true} = evaluate("1 instance of number and true")
      assert {:ok, false} = evaluate("1 instance of number and false")
      assert {:ok, true} = evaluate("1 instance of string or true")
      assert {:ok, true} = evaluate("1 instance of number = true")
      assert {:ok, true} = evaluate("(1 instance of number)")
      assert {:ok, true} = evaluate("not(1 instance of number) = false")

      assert {:ok, [true, two]} = evaluate("[1 instance of number, 2]")
      assert Decimal.equal?(two, Decimal.new(2))

      assert {:ok, one} = evaluate("if 1 instance of number then 1 else 2")
      assert Decimal.equal?(one, Decimal.new(1))

      assert {:ok, %{"a" => true, "b" => false}} =
               evaluate(~S|{a: 1 instance of number, b: 1 instance of string}|)
    end

    test "does not swallow a following operand into the type" do
      assert {:ok, true} = evaluate("1 instance of number and x", %{"x" => true})
      assert {:ok, false} = evaluate("1 instance of number and x", %{"x" => false})
      assert {:ok, true} = evaluate("1 instance of string or x", %{"x" => true})
      assert {:ok, nil} = evaluate("1 instance of number and x")
    end

    test "parses to an instance_of node over just the type" do
      assert {:ok, {:binary, :and, {:instance_of, {:literal, _}, "number"}, {:literal, true}}} =
               Boxic.FEEL.parse("1 instance of number and true")
    end

    test "still accepts every form of type" do
      for {expression, expected} <- [
            {"1 instance of number", true},
            {"1 instance of Any", true},
            {~S|"a" instance of string|, true},
            {"[1, 2] instance of list<number>", true},
            {"[1, 2] instance of list<string>", false},
            {"{a: 1} instance of context<a: number>", true},
            {"{a: 1, b: \"x\"} instance of context<a: number, b: string>", true},
            {"{a: 1} instance of context<a: string>", false},
            {"{a: {b: 1}} instance of context<a: context<b: number>>", true},
            {"[1..2] instance of range<number>", true},
            {"(function(x) x) instance of function<number> -> number", true},
            {"(function(x) x) instance of function<number>->number", true},
            {"duration(\"P1D\") instance of days and time duration", true},
            {"duration(\"P1Y\") instance of years and months duration", true},
            {"duration(\"P1Y\") instance of days and time duration", false},
            {"date(\"2020-01-01\") instance of date", true},
            {"date and time(\"2020-01-01T10:00:00\") instance of date and time", true},
            {"time(\"10:00:00\") instance of time", true},
            {"duration(\"P1D\") instance of days and time duration and true", true},
            {"1 instance of Unknown Type Name", false}
          ] do
        assert {:ok, expected} == evaluate(expression), expression
      end
    end

    test "types in context-nested lists and functions keep composing with other operators" do
      assert {:ok, [true, false]} =
               evaluate("[[1] instance of list<number>, [1] instance of list<string>]")

      assert {:ok, true} =
               evaluate("{a: 1} instance of context<a: number> and [1] instance of list<number>")
    end

    test "a missing or malformed type is a syntax error" do
      for expression <- [
            "1 instance of",
            "1 instance of 5",
            ~S|1 instance of "number"|,
            "1 instance of true",
            "1 instance of null",
            "1 instance of list<",
            "1 instance of list<number",
            "1 instance of context<a: >=>",
            "1 instance of ()",
            "1 instance of +",
            "1 instance of number number )"
          ] do
        assert {:error, %Error{code: :invalid_syntax}} = evaluate(expression), expression
      end
    end
  end

  describe "exponentiation that is not a real number" do
    test "is null rather than raising" do
      for expression <- [
            "(-8) ** (1/3)",
            "(-1) ** 0.5",
            "0 ** -0.5",
            "10 ** 308.5",
            "1.5 ** 2000.5",
            "1e300 ** 1.5",
            "1e400 ** 0.5",
            "1 ** 1e-400",
            "(1e-400) ** 0.5",
            "1e6144 ** 1.5",
            "2 ** 1e-6000"
          ] do
        assert {:ok, nil} == evaluate(expression), expression
      end
    end

    test "other powers still evaluate" do
      assert {:ok, nine} = evaluate("3 ** 2")
      assert Decimal.equal?(nine, Decimal.new(9))
      assert {:ok, quarter} = evaluate("2 ** -2")
      assert Decimal.equal?(quarter, Decimal.new("0.25"))
      assert {:ok, root} = evaluate("2 ** 0.5")
      assert Decimal.equal?(Decimal.round(root, 10), Decimal.new("1.4142135624"))
      assert {:ok, one} = evaluate("(-8) ** 0")
      assert Decimal.equal?(one, Decimal.new(1))
      assert {:ok, minus_eight} = evaluate("(-2) ** 3")
      assert Decimal.equal?(minus_eight, Decimal.new(-8))
      assert {:ok, nil} == evaluate("0 ** -1")
      assert {:ok, big} = evaluate("10 ** 6144")
      assert Decimal.equal?(big, Decimal.new("1e6144"))
    end
  end

  describe "arithmetic that overflows" do
    test "is null instead of an infinity" do
      for expression <- [
            "1e6144 * 10",
            "10 * 1e6144",
            "10 ** 6145",
            "2 ** 100000",
            "2 ** 1000000",
            "1e6000 * 1e6000",
            "-(1e6144 * 10)",
            "1e6144 + 1e6144 * 10",
            "1e6144 * 10 + 1",
            "1e6144 * 10 - 1",
            "1 - 1e6144 * 10",
            "-1e6144 * 10 - 1e6144 * 10",
            "1e6144 / 1e-6000",
            "10 ** -6145",
            "(-10) ** 6145",
            "(1e6144 * 10) - (1e6144 * 10)",
            "10 ** 6145 / 10 ** 6145",
            "0 * (1e6144 * 10)",
            "(1e6144 * 10) * 0",
            "sum([9e6144, 9e6144])",
            "product([1e6144, 10])"
          ] do
        assert {:ok, nil} == evaluate(expression), expression
      end
    end

    test "a value near the limit is not an overflow" do
      assert {:ok, %Decimal{coef: coef}} = evaluate("9e6144 + 1e6144 * 0")
      assert is_integer(coef)
      assert {:ok, %Decimal{coef: coef}} = evaluate("1e6144 * 9")
      assert is_integer(coef)
    end
  end

  describe "a NaN supplied by the host" do
    test "is not ordered, so comparing it is null" do
      context = %{"x" => Decimal.new("NaN")}

      for expression <- [
            "x < 1",
            "x > 1",
            "1 <= x",
            "x in [1..5]",
            "x between 1 and 5",
            "x in (>1)"
          ] do
        assert {:ok, nil} == evaluate(expression, context), expression
      end

      assert {:ok, nil} = Boxic.FEEL.evaluate_unary_test("> 1", Decimal.new("NaN"))
      assert {:ok, nil} = Boxic.FEEL.evaluate_unary_test("[1..5]", Decimal.new("NaN"))
    end

    test "does not yield a number from arithmetic" do
      context = %{"x" => Decimal.new("NaN")}

      for expression <- ["x + 1", "1 - x", "x * 2", "x / 2", "x ** 2", "2 ** x", "-x"] do
        assert {:ok, nil} == evaluate(expression, context), expression
      end
    end
  end

  describe "non-finite number strings" do
    test "number() returns null for NaN and infinities" do
      for text <- ["NaN", "nan", "Infinity", "-Infinity", "+Infinity", "inf", "-inf"] do
        assert {:ok, nil} == evaluate(~s|number("#{text}")|), text
        assert {:ok, nil} == evaluate(~s|number("#{text}", " ", ".")|), text
      end
    end

    test "comparisons and range tests on them are null" do
      assert {:ok, nil} == evaluate(~S|number("NaN") < 1|)
      assert {:ok, nil} == evaluate(~S|number("NaN") in [1..2]|)
      assert {:ok, nil} == evaluate(~S|number("Infinity") > 1|)
      assert {:ok, nil} == evaluate(~S|1 < number("Infinity")|)
    end

    test "number() still parses finite strings" do
      assert {:ok, n} = evaluate(~S|number("12.5")|)
      assert Decimal.equal?(n, Decimal.new("12.5"))
      assert {:ok, n} = evaluate(~S|number("1,234.5", ",", ".")|)
      assert Decimal.equal?(n, Decimal.new("1234.5"))
    end
  end

  describe "duration arithmetic beyond the representable range" do
    test "scaling past the limit is null" do
      for expression <- [
            ~S|duration("P1M") * 1e34|,
            ~S|1e34 * duration("P1M")|,
            ~S|duration("P1M") * number("NaN")|,
            ~S|duration("P1Y") * 1e40|,
            ~S|duration("P1Y") * 1e6144|,
            ~S|duration("P1D") * 1e300|,
            ~S|duration("P1D") * 1e6144|,
            ~S|duration("P1D") / 1e-6000|,
            ~S|duration("P1Y") / 1e-6000|,
            ~S|date("2020-01-01") + duration("P1D") * 1e300|,
            ~S|date("2020-01-01") - duration("P1D") * 1e300|,
            ~S|(duration("P1D") * 1e300).days|,
            ~S|(duration("P1D") * 1e300).seconds|,
            ~S|(duration("P1Y") * 1e40).years|
          ] do
        assert {:ok, nil} == evaluate(expression), expression
      end
    end

    test "scaling within the limit still works" do
      assert {:ok, %Duration{kind: :year_month, months: 24}} = evaluate(~S|duration("P1Y") * 2|)
      assert {:ok, %Duration{kind: :year_month, months: 18}} = evaluate(~S|duration("P1Y") * 1.5|)
      assert {:ok, %Duration{kind: :year_month, months: 6}} = evaluate(~S|duration("P1Y") / 2|)

      assert {:ok, %Duration{kind: :day_time} = scaled} = evaluate(~S|duration("P1D") * 0.5|)
      assert Decimal.equal?(Decimal.new(scaled.seconds), Decimal.new(43_200))
      assert {:ok, %Duration{kind: :year_month, months: 0}} = evaluate(~S|duration("P1Y") * 0|)
    end

    test "Duration.scale/2 reports an unrepresentable result as :error" do
      {:ok, month} = Duration.parse_iso8601("P1M")
      assert :error = Duration.scale(month, Decimal.new("1e34"))
      assert :error = Duration.scale(month, Decimal.new("NaN"))
      assert :error = Duration.scale(month, Decimal.new("Infinity"))
      assert {:ok, %Duration{months: 2}} = Duration.scale(month, Decimal.new(2))
    end

    test "huge duration literals do not break their accessors" do
      huge = "P" <> String.duplicate("9", 60) <> "D"

      for expression <- [
            ~s|duration("#{huge}").days|,
            ~s|duration("#{huge}").hours|,
            ~s|duration("#{huge}").seconds|,
            ~s|string(duration("#{huge}"))|,
            ~s|date("2020-01-01") + duration("#{huge}")|,
            ~s|date and time("2020-01-01T10:00:00Z") + duration("#{huge}")|,
            ~s|date and time("2020-01-01T10:00:00@Europe/Berlin") + duration("#{huge}")|,
            ~s|time("10:00:00") + duration("#{huge}")|,
            ~s|duration("#{huge}") + duration("#{huge}")|,
            ~s|duration("#{huge}") * 2|,
            ~s|duration("#{huge}") / duration("PT1S")|
          ] do
        assert match?({:ok, _}, evaluate(expression)), expression
      end
    end
  end

  describe "an Elixir DateTime in a non-UTC zone" do
    setup do
      berlin = DateTime.new!(~D[2020-06-01], ~T[10:30:00], "Europe/Berlin", Tz.TimeZoneDatabase)
      {:ok, berlin: berlin, context: %{"dt" => berlin}}
    end

    test "can be shifted by a day-time duration", %{context: context} do
      assert {:ok, %DateTime{} = result} = evaluate(~S|dt + duration("P1D")|, context)
      assert result.time_zone == "Europe/Berlin"
      assert DateTime.to_date(result) == ~D[2020-06-02]
      assert DateTime.to_time(result) == ~T[10:30:00]

      assert {:ok, %DateTime{} = result} = evaluate(~S|duration("PT2H") + dt|, context)
      assert DateTime.to_time(result) == ~T[12:30:00]

      assert {:ok, %DateTime{} = result} = evaluate(~S|dt - duration("P1D")|, context)
      assert DateTime.to_date(result) == ~D[2020-05-31]
    end

    test "can be shifted by a year-month duration", %{context: context} do
      assert {:ok, %DateTime{} = result} = evaluate(~S|dt + duration("P1M")|, context)
      assert DateTime.to_date(result) == ~D[2020-07-01]
      assert result.time_zone == "Europe/Berlin"
    end

    test "keeps the wall-clock time across a daylight-saving change" do
      before_change =
        DateTime.new!(~D[2020-03-28], ~T[12:00:00], "Europe/Berlin", Tz.TimeZoneDatabase)

      assert {:ok, %DateTime{} = result} =
               evaluate(~S|dt + duration("P1M")|, %{"dt" => before_change})

      assert DateTime.to_date(result) == ~D[2020-04-28]
      assert DateTime.to_time(result) == ~T[12:00:00]
      assert result.utc_offset + result.std_offset == 7_200
    end

    test "is null when the shifted wall-clock time does not exist" do
      before_change =
        DateTime.new!(~D[2020-02-29], ~T[02:30:00], "Europe/Berlin", Tz.TimeZoneDatabase)

      # 2020-03-29 02:30 does not exist in Europe/Berlin (clocks jump from 02:00 to 03:00).
      assert {:ok, nil} = evaluate(~S|dt + duration("P1M")|, %{"dt" => before_change})
    end

    test "in an unknown zone is null" do
      unknown = %DateTime{
        year: 2020,
        month: 6,
        day: 1,
        hour: 10,
        minute: 0,
        second: 0,
        microsecond: {0, 0},
        zone_abbr: "XX",
        utc_offset: 3_600,
        std_offset: 0,
        time_zone: "Nowhere/Land"
      }

      assert {:ok, nil} = evaluate(~S|dt + duration("P1D")|, %{"dt" => unknown})
    end

    test "UTC values still work" do
      utc = DateTime.new!(~D[2020-06-01], ~T[10:30:00], "Etc/UTC")
      assert {:ok, %DateTime{} = result} = evaluate(~S|dt + duration("P1D")|, %{"dt" => utc})
      assert DateTime.to_date(result) == ~D[2020-06-02]
    end

    test "Duration.add_to_datetime/2 returns the shifted value or :error", %{berlin: berlin} do
      {:ok, day} = Duration.parse_iso8601("P1D")
      assert {:ok, %DateTime{} = shifted} = Duration.add_to_datetime(berlin, day)
      assert DateTime.to_date(shifted) == ~D[2020-06-02]
      assert :error = Duration.add_to_datetime(%{berlin | time_zone: "Nowhere/Land"}, day)
    end
  end
end
