defmodule Boxic.FEELTest do
  use ExUnit.Case

  alias Boxic.FEEL.Duration
  alias Boxic.FEEL.Time, as: FeelTime

  test "parse builds AST without evaluation" do
    assert {:ok, {:binary, :plus, {:identifier, "a"}, {:literal, %Decimal{} = _one}}} =
             Boxic.FEEL.parse("a + 1")
  end

  test "AST validation accepts parser output and rejects malformed trees" do
    assert {:ok, ast} = Boxic.FEEL.parse("for x in [1, 2] return x + 1")
    assert :ok = Boxic.FEEL.AST.validate(ast)

    assert {:error, %Boxic.FEEL.Error{code: :invalid_ast, message: message}} =
             Boxic.FEEL.AST.validate({:binary, :unknown, {:literal, 1}, {:literal, 2}})

    assert message =~ "invalid AST node"

    assert {:error, %Boxic.FEEL.Error{code: :invalid_ast}} =
             Boxic.FEEL.evaluate_ast({:call, :not_an_ast, []}, %{})
  end

  test "if expression evaluates only the selected branch" do
    assert {:ok, Decimal.new("2")} == Boxic.FEEL.evaluate("if true then 1 + 1 else missing + 1")
    assert {:ok, Decimal.new("3")} == Boxic.FEEL.evaluate("if false then missing + 1 else 3")
    assert {:ok, "else"} == Boxic.FEEL.evaluate("if null then \"then\" else \"else\"")

    assert {:error, %Boxic.FEEL.Error{code: :type_error}} =
             Boxic.FEEL.evaluate("if 1 then true else false")
  end

  test "arithmetic uses decimal semantics" do
    assert {:ok, %Decimal{} = result} = Boxic.FEEL.evaluate("1 + 2 * 3", %{})
    assert Decimal.equal?(result, Decimal.new("7"))
  end

  test "comparison evaluates against decimal values" do
    assert {:ok, true} == Boxic.FEEL.evaluate("7 > 2", %{})
    assert {:ok, false} == Boxic.FEEL.evaluate("1 >= 2", %{})
  end

  test "three-valued boolean logic" do
    assert {:ok, false} == Boxic.FEEL.evaluate("false and null", %{})
    assert {:ok, true} == Boxic.FEEL.evaluate("true or null", %{})
    assert {:ok, nil} == Boxic.FEEL.evaluate("not null", %{})
  end

  test "null propagates in arithmetic and ordering comparisons" do
    assert {:ok, nil} == Boxic.FEEL.evaluate("null + 1", %{})
    assert {:ok, nil} == Boxic.FEEL.evaluate("2 < null", %{})
  end

  test "context values resolve by name" do
    assert {:ok, %Decimal{} = value} =
             Boxic.FEEL.evaluate("input + 1", %{"input" => Decimal.new("2")})

    assert Decimal.equal?(value, Decimal.new("3"))
  end

  test "range literals evaluate to FEEL ranges" do
    assert {:ok, %Boxic.FEEL.Range{start_inclusive: true, end_inclusive: false} = range} =
             Boxic.FEEL.evaluate("[1..3)", %{})

    assert Decimal.equal?(range.start, Decimal.new("1"))
    assert Decimal.equal?(range.end, Decimal.new("3"))
  end

  test "path expressions resolve context entries" do
    assert {:ok, %Decimal{} = value} = Boxic.FEEL.evaluate("{a: 2}.a", %{})
    assert Decimal.equal?(value, Decimal.new("2"))
  end

  test "bracket filters retain matching list items" do
    assert {:ok, [%Decimal{} = two, %Decimal{} = three]} =
             Boxic.FEEL.evaluate("[1,2,3][item > 1]", %{})

    assert Decimal.equal?(two, Decimal.new("2"))
    assert Decimal.equal?(three, Decimal.new("3"))
  end

  test "for-expressions project over lists" do
    assert {:ok, [%Decimal{} = two, %Decimal{} = three, %Decimal{} = four]} =
             Boxic.FEEL.evaluate("for x in [1,2,3] return x + 1", %{})

    assert Decimal.equal?(two, Decimal.new("2"))
    assert Decimal.equal?(three, Decimal.new("3"))
    assert Decimal.equal?(four, Decimal.new("4"))
  end

  test "some and every quantifiers evaluate predicates" do
    assert {:ok, true} == Boxic.FEEL.evaluate("some x in [1,2,3] satisfies x > 2", %{})
    assert {:ok, false} == Boxic.FEEL.evaluate("every x in [1,2,3] satisfies x > 2", %{})
  end

  test "function closures capture surrounding context" do
    assert {:ok, %Decimal{} = value} =
             Boxic.FEEL.evaluate("(function(x) x + inc)(2)", %{"inc" => Decimal.new("5")})

    assert Decimal.equal?(value, Decimal.new("7"))
  end

  test "unary test evaluation supports comparators and ranges" do
    assert {:ok, true} == Boxic.FEEL.evaluate_unary_test("> 5", Decimal.new("7"), %{})
    assert {:ok, false} == Boxic.FEEL.evaluate_unary_test("<= 5", Decimal.new("7"), %{})
    assert {:ok, true} == Boxic.FEEL.evaluate_unary_test("[1..10]", Decimal.new("7"), %{})
    assert {:ok, false} == Boxic.FEEL.evaluate_unary_test("[1..10)", Decimal.new("10"), %{})
    assert {:ok, false} == Boxic.FEEL.evaluate_unary_test("not(2)", Decimal.new("2"), %{})

    assert {:ok, true} ==
             Boxic.FEEL.evaluate_unary_test("choices", "silver", %{
               "choices" => ["gold", "silver"]
             })
  end

  test "context entries scope and shadow outer context" do
    assert {:ok, %Decimal{} = value} =
             Boxic.FEEL.evaluate("{x: 2, y: x + 1}.y", %{"x" => Decimal.new("99")})

    assert Decimal.equal?(value, Decimal.new("3"))
  end

  test "function parameter shadows captured name" do
    assert {:ok, %Decimal{} = value} =
             Boxic.FEEL.evaluate("(function(x) x + 1)(2)", %{"x" => Decimal.new("100")})

    assert Decimal.equal?(value, Decimal.new("3"))
  end

  test "user-defined functions accept named arguments in declaration order" do
    assert {:ok, %Decimal{} = value} =
             Boxic.FEEL.evaluate("(function(a, b) a - b)(b: 3, a: 10)")

    assert Decimal.equal?(value, Decimal.new("7"))
  end

  test "range and list replace functions support their standard forms" do
    assert {:ok, %Boxic.FEEL.Range{} = range} = Boxic.FEEL.evaluate(~s|range("[1..3]")|)
    assert Decimal.equal?(range.start, Decimal.new("1"))
    assert Decimal.equal?(range.end, Decimal.new("3"))

    assert {:ok, values} = Boxic.FEEL.evaluate("list replace([1, 2, 3], 2, 4)")
    assert Enum.map(values, &Decimal.to_integer/1) == [1, 4, 3]

    assert {:ok, values} =
             Boxic.FEEL.evaluate(
               "list replace([1, 2, 3], function(item, newItem) item < newItem, 3)"
             )

    assert Enum.map(values, &Decimal.to_integer/1) == [3, 3, 3]
  end

  test "string and numeric built-ins" do
    assert {:ok, %Decimal{} = len} = Boxic.FEEL.evaluate("string_length(\"hello\")", %{})
    assert Decimal.equal?(len, Decimal.new("5"))

    assert {:ok, "HE"} == Boxic.FEEL.evaluate("substring(upper_case(\"hello\"), 1, 2)", %{})
    assert {:ok, %Decimal{} = sum} = Boxic.FEEL.evaluate("sum([1,2,3])", %{})
    assert Decimal.equal?(sum, Decimal.new("6"))
  end

  test "list built-ins" do
    assert {:ok, %Decimal{} = count} = Boxic.FEEL.evaluate("count([1,2,3])", %{})
    assert Decimal.equal?(count, Decimal.new("3"))

    assert {:ok, [%Decimal{} = one, %Decimal{} = two, %Decimal{} = three]} =
             Boxic.FEEL.evaluate("append([1,2], 3)", %{})

    assert Decimal.equal?(one, Decimal.new("1"))
    assert Decimal.equal?(two, Decimal.new("2"))
    assert Decimal.equal?(three, Decimal.new("3"))

    assert {:ok, true} == Boxic.FEEL.evaluate("list contains([1, 2], 2)")
    assert {:ok, [one, two, three]} == Boxic.FEEL.evaluate("concatenate([1], [2, 3])")
    assert {:ok, [one, two, three]} == Boxic.FEEL.evaluate("insert before([1, 3], 2, 2)")
    assert {:ok, [one, three]} == Boxic.FEEL.evaluate("remove([1, 2, 3], 2)")
    assert {:ok, [three, two, one]} == Boxic.FEEL.evaluate("reverse([1, 2, 3])")
    assert {:ok, [one, three]} == Boxic.FEEL.evaluate("index of([2, 1, 2], 2)")
    assert {:ok, [one, two, three]} == Boxic.FEEL.evaluate("union([1, 2], [2, 3])")
    assert {:ok, [one, two]} == Boxic.FEEL.evaluate("distinct values([1, 1, 2])")
    assert {:ok, [one, two, three]} == Boxic.FEEL.evaluate("flatten([1, [2, [3]]])")
    assert {:ok, [two, three]} == Boxic.FEEL.evaluate("sublist([1, 2, 3], 2)")
  end

  test "boolean aggregate and statistical built-ins" do
    assert {:ok, false} == Boxic.FEEL.evaluate("all([true, false, true])")
    assert {:ok, nil} == Boxic.FEEL.evaluate("any(false, null)")
    assert {:ok, Decimal.new("2.5")} == Boxic.FEEL.evaluate("median([1, 2, 3, 4])")

    assert {:ok, modes} = Boxic.FEEL.evaluate("mode([3, 1, 3, 1, 2])")
    assert Enum.map(modes, &Decimal.to_string/1) == ["1", "3"]

    assert {:ok, stddev} = Boxic.FEEL.evaluate("stddev([2, 4, 7, 5])")
    assert Decimal.equal?(stddev, Decimal.new("2.0816659994661"))
  end

  test "Unicode escapes, regex functions, and canonical string conversion" do
    assert {:ok, "🐎"} = Boxic.FEEL.evaluate("\"\\U01F40E\"")
    assert {:ok, true} = Boxic.FEEL.evaluate(~S|matches("aA", "(a)\1", "i")|)
    assert {:ok, ["John", "Doe"]} = Boxic.FEEL.evaluate(~S|split("John Doe", "\s")|)

    assert {:ok, "{a: \"foo\", b: [1, \"bar\"]}"} =
             Boxic.FEEL.evaluate(~S|string({a: "foo", b: [1, "bar"]})|)
  end

  test "type predicates, between, comments, and context functions" do
    assert {:ok, true} = Boxic.FEEL.evaluate("5 between 1 and 10")
    assert {:ok, true} = Boxic.FEEL.evaluate("[1, 2] instance of list<number>")
    assert {:ok, two} = Boxic.FEEL.evaluate("1 + /* ignored */ 1")
    assert Decimal.equal?(two, Decimal.new("2"))

    assert {:ok, %{"a" => updated}} = Boxic.FEEL.evaluate(~S|context put({a: 1}, "a", 2)|)
    assert Decimal.equal?(updated, Decimal.new("2"))
  end

  test "calendar extraction and interval relations" do
    assert {:ok, day} = Boxic.FEEL.evaluate(~S|day of year(@"2020-12-31")|)
    assert Decimal.equal?(day, Decimal.new("366"))
    assert {:ok, "Tuesday"} = Boxic.FEEL.evaluate(~S|day of week(@"2019-09-17")|)
    assert {:ok, true} = Boxic.FEEL.evaluate("overlaps([1..5], [5..8])")
    assert {:ok, true} = Boxic.FEEL.evaluate("includes([1..10], (1..5])")
  end

  test "temporal constructors and arithmetic" do
    assert {:ok, %Date{year: 2026, month: 7, day: 16}} =
             Boxic.FEEL.evaluate("date(\"2026-07-15\") + duration(\"P1D\")", %{})

    assert {:ok, %FeelTime{} = time} =
             Boxic.FEEL.evaluate("time(\"10:00:00\") + duration(\"PT90M\")", %{})

    assert time.hour == 11
    assert time.minute == 30
  end

  test "timezone-aware datetime comparison" do
    assert {:ok, true} =
             Boxic.FEEL.evaluate(
               "date_time(\"2026-07-15T10:00:00+00:00\") = date_time(\"2026-07-15T12:00:00+02:00\")",
               %{}
             )
  end

  test "named-zone date-time arithmetic follows IANA transitions" do
    assert {:ok, %Boxic.FEEL.DateTime{} = result} =
             Boxic.FEEL.evaluate(
               "date and time(\"2026-03-28T12:00:00@Europe/Paris\") + duration(\"PT24H\")"
             )

    assert Boxic.FEEL.DateTime.to_string(result) ==
             "2026-03-29T13:00:00@Europe/Paris"
  end

  test "general string conversion preserves temporal forms" do
    assert {:ok, "P1Y2M"} = Boxic.FEEL.evaluate("string(duration(\"P1Y2M\"))")
    assert {:ok, "12.50"} = Boxic.FEEL.evaluate("string(12.50)")
    assert {:ok, "true"} = Boxic.FEEL.evaluate("string(true)")
  end

  describe "unary tests on a null value" do
    test "are null rather than raising, also when negated" do
      assert {:ok, nil} = Boxic.FEEL.evaluate_unary_test("[1..100]", nil)
      assert {:ok, nil} = Boxic.FEEL.evaluate_unary_test("not([1..100])", nil)
    end

    test "still decide values that can be tested" do
      assert {:ok, true} = Boxic.FEEL.evaluate_unary_test("[1..100]", Decimal.new(5))
      assert {:ok, false} = Boxic.FEEL.evaluate_unary_test("not([1..100])", Decimal.new(5))
      assert {:ok, true} = Boxic.FEEL.evaluate_unary_test("not([1..100])", Decimal.new(500))
    end
  end

  describe "range tests on values that cannot be compared with the bounds" do
    test "are null, not decided by Erlang's term order" do
      for expression <- [
            ~S|"a" in [1..100]|,
            ~S|1 in ["a".."z"]|,
            ~S|date("2021-01-01") in [1..5]|,
            ~S|true in [1..5]|,
            "[1] in [1..5]"
          ] do
        assert {:ok, nil} == Boxic.FEEL.evaluate(expression), expression
      end
    end

    test "are null as unary tests too, also when negated" do
      assert {:ok, nil} = Boxic.FEEL.evaluate_unary_test("[1..100]", "a")
      assert {:ok, nil} = Boxic.FEEL.evaluate_unary_test("not([1..100])", "a")
    end

    test "do not affect values that can be compared" do
      assert {:ok, true} = Boxic.FEEL.evaluate("5 in [1..10]")
      assert {:ok, false} = Boxic.FEEL.evaluate("50 in [1..10]")
      assert {:ok, false} = Boxic.FEEL.evaluate("10 in [1..10)")
      assert {:ok, true} = Boxic.FEEL.evaluate(~S|"m" in ["a".."z"]|)
      assert {:ok, false} = Boxic.FEEL.evaluate(~S|"zz" in ["a".."z"]|)

      assert {:ok, true} =
               Boxic.FEEL.evaluate(
                 ~S|date("2021-06-01") in [date("2021-01-01")..date("2021-12-31")]|
               )

      assert {:ok, nil} == Boxic.FEEL.evaluate("null in [1..10]")
    end
  end

  describe "numeric literals beyond the supported range" do
    # Decimal rejects literals with more than 34 significant digits or a decimal exponent
    # beyond +-6144. Those must surface as syntax errors, never as raised exceptions.
    for {name, literal} <- [
          {"a negative exponent below the limit", "1e-6176"},
          {"a positive exponent above the limit", "1e6145"},
          {"an integer with too many digits", String.duplicate("9", 35)},
          {"a decimal with too many digits", "0." <> String.duplicate("1", 40)},
          {"a leading-dot decimal with too many digits", "." <> String.duplicate("1", 40)}
        ] do
      test "#{name} is a syntax error" do
        assert {:error, %Boxic.FEEL.Error{code: :invalid_syntax, message: message}} =
                 Boxic.FEEL.evaluate(unquote(literal))

        assert message =~ "numeric literal"

        assert {:error, %Boxic.FEEL.Error{code: :invalid_syntax}} =
                 Boxic.FEEL.parse(unquote(literal))
      end
    end

    test "error messages do not echo an arbitrarily long literal" do
      assert {:error, %Boxic.FEEL.Error{message: message}} =
               Boxic.FEEL.evaluate(String.duplicate("9", 5_000))

      assert String.length(message) < 120
    end

    test "literals at the limits still evaluate" do
      assert {:ok, %Decimal{}} = Boxic.FEEL.evaluate("1e6144")
      assert {:ok, %Decimal{}} = Boxic.FEEL.evaluate("1e-6144")
      assert {:ok, %Decimal{}} = Boxic.FEEL.evaluate(String.duplicate("9", 34))
      assert {:ok, %Decimal{}} = Boxic.FEEL.evaluate(".5")
    end
  end

  test "max accepts a single value as well as a list or several values" do
    for expression <- ["max(5)", "max([5])", "max(5, 3)", "max(3, 5, 4)"] do
      assert {:ok, five} = Boxic.FEEL.evaluate(expression)
      assert Decimal.equal?(five, Decimal.new(5)), expression
    end
  end

  test "sum and min accept their variadic forms" do
    assert {:ok, six} = Boxic.FEEL.evaluate("sum(1, 2, 3)")
    assert Decimal.equal?(six, Decimal.new(6))
    assert {:ok, one} = Boxic.FEEL.evaluate("sum(1)")
    assert Decimal.equal?(one, Decimal.new(1))
    assert {:ok, two} = Boxic.FEEL.evaluate("min(3, 2, 5)")
    assert Decimal.equal?(two, Decimal.new(2))
    assert {:ok, four} = Boxic.FEEL.evaluate("min([4, 9])")
    assert Decimal.equal?(four, Decimal.new(4))
  end

  test "duration arithmetic preserves kinds and temporal boundary semantics" do
    assert {:ok, %Duration{kind: :day_time} = scaled} =
             Boxic.FEEL.evaluate(~S|duration("PT1H") * 2.5|)

    assert Decimal.equal?(Decimal.new(scaled.seconds), Decimal.new(9_000))

    assert {:ok, %Duration{kind: :year_month, months: 6}} =
             Boxic.FEEL.evaluate(~S|duration("P1Y") / 2|)

    assert {:error, %{code: :type_error}} =
             Boxic.FEEL.evaluate(~S|duration("P1Y") + duration("P1D")|)

    assert {:ok, ~D[2021-01-01]} =
             Boxic.FEEL.evaluate(~S|@"2021-01-02" - @"PT1S"|)
  end
end
