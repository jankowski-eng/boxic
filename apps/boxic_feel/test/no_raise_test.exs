defmodule Boxic.FEEL.NoRaiseTest do
  # The public API returns failures as values: `{:error, %Boxic.FEEL.Error{}}`, or null where
  # the specification says so. These are hostile inputs that once raised an exception, plus a
  # matrix of awkward operands. None of them may raise, throw, or exit.
  use ExUnit.Case

  alias Boxic.FEEL.{Error, ExternalFunctions}

  defmodule Host do
    def identity(value), do: value
    def nan, do: Decimal.new("NaN")
  end

  defmodule Registry do
    use ExternalFunctions

    external("id_float", {Host, :identity}, parameters: [:float], returns: :number)
    external("id_integer", {Host, :identity}, parameters: [:integer], returns: :integer)
    external("id_number", {Host, :identity}, parameters: [:number], returns: :number)
    external("chr", {Host, :identity}, parameters: [:integer], returns: :char)
    external("nan", {Host, :nan}, returns: :number)
    external("echo", {Host, :identity}, parameters: [:feel], returns: :feel)
    external("echo_untyped", {Host, :identity}, returns: :feel)
  end

  @backslash <<92>>

  # Expressions that raised before the crash fixes, grouped by the part of the code that failed.
  @temporal_literals [
    ~S|@"2020-02-30"|,
    ~S|@"2020-13-45"|,
    ~S|@"2020-02-30T10:00:00Z"|,
    ~S|@"P"|,
    ~S|@"PT"|,
    ~S|@"PT1"|,
    ~S|@"-P"|,
    ~S|@"P1.5D"|,
    ~S|@""|,
    ~S|@"T"|,
    ~S|@"2020-01-01T"|,
    ~S|@"999999999-12-31T24:00:00"|
  ]

  @strings [
    ~S|"\U00D800"|,
    ~S|"\U110000"|,
    ~S|"\u-123"|,
    ~S|"\u+123"|,
    ~S|"\U-00123"|,
    ~S|"\uD800"|,
    "\"" <> @backslash <> "u12",
    "\"" <> @backslash,
    "\"a" <> <<255>> <> "\"",
    "abc" <> <<255>>,
    "@\"" <> <<255>> <> "\"",
    <<255>>,
    <<0xC3>>,
    "1 + " <> <<0xC3, 0x28>>,
    "\"" <> @backslash <> "u" <> <<0xE2, 0x82>> <> "\""
  ]

  @types [
    "1 instance of number and true",
    "[1 instance of number, 2]",
    "if 1 instance of number then 1 else 2",
    "1 instance of number = true",
    "(1 instance of number)",
    "1 instance of number and x",
    "1 instance of",
    "1 instance of 5",
    "1 instance of true",
    "1 instance of null",
    ~S|1 instance of "string"|,
    "1 instance of list<",
    "1 instance of list<number",
    "1 instance of list<number>>",
    "1 instance of context<a: >",
    "1 instance of context<: number>",
    "1 instance of function<number> ->",
    "1 instance of function<number> -> -> number",
    "1 instance of ()",
    "1 instance of [1]",
    "1 instance of days and time",
    "1 instance of date and"
  ]

  @numbers [
    "(-8) ** (1/3)",
    "(-1) ** 0.5",
    "0 ** -0.5",
    "10 ** 308.5",
    "1.5 ** 2000.5",
    "1e300 ** 1.5",
    "1e400 ** 0.5",
    "1 ** 1e-400",
    "(1e-400) ** 0.5",
    "2 ** 1e30",
    "1.0000001 ** 1e30",
    "0.5 ** 1e6000",
    "(-1) ** 1e6000",
    "1e6144 * 10",
    "10 ** 6145",
    "2 ** 100000",
    "2 ** 1000000",
    "1e6000 * 1e6000",
    "(1e6144 * 10) - (1e6144 * 10)",
    "10 ** 6145 / 10 ** 6145",
    "0 * (1e6144 * 10)",
    "1e6144 / 1e-6000",
    ~S|number("NaN")|,
    ~S|number("Infinity")|,
    ~S|number("-inf")|,
    ~S|number("sNaN")|,
    ~S|number("NaN") < 1|,
    ~S|number("NaN") in [1..2]|,
    ~S|number("NaN") = number("NaN")|,
    ~S|sum([number("NaN"), 1])|,
    "sum([9e6144, 9e6144])",
    "product([1e6144, 10, 10])",
    "sqrt(1e6144)",
    "exp(1e6144)",
    "log(1e-6143)",
    "modulo(1e6144, 1e-6000)",
    "round(1e6144)",
    "decimal(1e6144, 6000)"
  ]

  @durations [
    ~S|duration("P1M") * 1e34|,
    ~S|duration("P1M") * number("NaN")|,
    ~S|duration("P1Y") * 1e40|,
    ~S|duration("P1Y") * 1e6144|,
    ~S|duration("P1D") / 1e-6000|,
    ~S|date("2020-01-01") + duration("P1D") * 1e300|,
    ~S|(duration("P1D") * 1e300).days|,
    ~S|(duration("P1D") * 1e300).seconds|,
    ~S|duration("P1Y") * 0.00000000000000000000000000000001|,
    ~S|duration("P99999999999999999999999999999999999999999999D").days|,
    ~S|duration("P99999999999999999999999999999999999999999999D").hours|,
    ~S|duration("P99999999999999999999999999999999999999999999D").seconds|,
    ~S|string(duration("P99999999999999999999999999999999999999999999D"))|,
    ~S|date("2020-01-01") + duration("P99999999999999999999999999999999999999999999D")|,
    ~S|date("2020-01-01") + duration("P99999999999999999999999999999999999999999999Y")|,
    ~S|date and time("2020-01-01T10:00:00Z") + duration("P99999999999999999999999999999999D")|,
    ~S|date and time("2020-01-01T10:00:00@Europe/Berlin") - duration("P99999999999999999999D")|,
    ~S|time("10:00:00") + duration("P99999999999999999999999999999999999999999999D")|,
    ~S|time("10:00:00") - duration("P99999999999999999999999999999999999999999999D")|,
    ~S|duration("P99999999999999999999999999999999999999999999D") * duration("P1D")|,
    ~S|duration("P99999999999999999999999999999999999999999999D") / duration("PT0.001S")|
  ]

  @expressions @temporal_literals ++ @strings ++ @types ++ @numbers ++ @durations

  defp outcome(fun) do
    fun.()
  rescue
    exception -> {:raised, exception}
  catch
    kind, reason -> {:raised, {kind, reason}}
  end

  defp value?({:ok, _value}), do: true
  defp value?({:error, %Error{}}), do: true
  defp value?(_other), do: false

  defp assert_no_failures(inputs, fun) do
    failures =
      for input <- inputs,
          result = outcome(fn -> fun.(input) end),
          not value?(result),
          do: {input, result}

    assert failures == [], "inputs that did not return a value:\n" <> inspect(failures, limit: 20)
  end

  test "parse/1 returns a value for every hostile expression" do
    assert_no_failures(@expressions, &Boxic.FEEL.parse/1)
  end

  test "evaluate/2 returns a value for every hostile expression" do
    assert_no_failures(@expressions, &Boxic.FEEL.evaluate/1)

    assert_no_failures(@expressions, fn expression ->
      Boxic.FEEL.evaluate(expression, %{"x" => Decimal.new(1)})
    end)
  end

  test "evaluate_unary_test/3 returns a value for hostile tests and hostile values" do
    values = [
      nil,
      Decimal.new(1),
      Decimal.new("1e6144"),
      "text",
      true,
      [],
      %{"a" => Decimal.new(1)},
      ~D[2020-01-01],
      Boxic.FEEL.Duration.from_days(1)
    ]

    for value <- values do
      assert_no_failures(@expressions, fn test ->
        Boxic.FEEL.evaluate_unary_test(test, value)
      end)
    end
  end

  test "evaluate_ast/2 returns a value for malformed trees" do
    trees = [
      {:context, [1]},
      {:context, [:a, :b]},
      {:context, [{"a", {:literal, 1}} | :tail]},
      {:context, [{:a, {:literal, 1}}]},
      {:function, [1], {:literal, 1}},
      {:function, [{"x", nil} | :tail], {:literal, 1}},
      {:function, :params, {:literal, 1}},
      {:for, [1], {:literal, 1}},
      {:for, [{"i", {:list, []}} | :tail], {:literal, 1}},
      {:for, :bindings, {:literal, 1}},
      {:list, [{:literal, 1} | {:literal, 2}]},
      {:list, :items},
      {:call, {:identifier, "f"}, [{:literal, 1} | 2]},
      {:call, {:identifier, "f"}, :arguments},
      {:unary_tests, [{:literal, 1} | 2]},
      {:unary_tests, :tests},
      {:instance_of, {:literal, 1}, :number},
      {:range, 1, 2, {:literal, 1}, {:literal, 2}},
      {:binary, :plus, {:literal, 1}},
      {:named_arg, "x", {:literal, 1}},
      {:literal, :atom},
      nil,
      :atom,
      1,
      "text",
      []
    ]

    assert_no_failures(trees, fn tree -> Boxic.FEEL.evaluate_ast(tree, %{}) end)
  end

  defp host_values do
    [
      nil,
      Decimal.new("NaN"),
      Decimal.new("Infinity"),
      Decimal.new("-1e6144"),
      "text",
      true,
      [],
      [Decimal.new(1)],
      %{"a" => Decimal.new(1)},
      ~D[2020-01-01],
      ~T[10:00:00],
      ~N[2020-01-01 10:00:00],
      DateTime.new!(~D[2020-06-01], ~T[10:30:00], "Europe/Berlin", Tz.TimeZoneDatabase),
      DateTime.new!(~D[2020-06-01], ~T[10:30:00], "Etc/UTC"),
      Boxic.FEEL.Duration.from_days(1),
      :atom,
      {:tuple, 1},
      self(),
      fn value -> value end
    ]
  end

  describe "operands that are numbers, text, collections, temporal values, or durations" do
    @operands [
      "1",
      "-1",
      "0",
      "0.5",
      "1e6144",
      "-1e6144",
      "1e-6143",
      "9e6144",
      "123456789012345678901234567890123",
      ~S|"a"|,
      ~S|""|,
      "true",
      "null",
      "[]",
      "[1, 2]",
      "{a: 1}",
      "[1..5]",
      "(1..5)",
      "(null..5]",
      ~S|date("2020-01-01")|,
      ~S|time("10:00:00")|,
      ~S|time("10:00:00@Europe/Berlin")|,
      ~S|date and time("2020-01-01T10:00:00Z")|,
      ~S|date and time("2020-01-01T10:00:00@Europe/Berlin")|,
      ~S|date and time("2020-01-01T10:00:00")|,
      ~S|duration("P1D")|,
      ~S|duration("P1Y")|,
      ~S|duration("-P1M")|,
      ~S|duration("P999999999999999999999999999999999999999D")|,
      ~S|duration("P999999999999999999999999999999999999999Y")|,
      ~S|number("NaN")|,
      "function(x) x",
      "x"
    ]

    @operators ["+", "-", "*", "/", "**", "=", "!=", "<", "<=", ">", ">=", "and", "or"]

    test "combined with every binary operator" do
      expressions =
        for left <- @operands, right <- @operands, operator <- @operators do
          "(#{left}) #{operator} (#{right})"
        end

      assert_no_failures(expressions, &Boxic.FEEL.evaluate/1)
    end

    test "read through every property" do
      properties =
        ~w(year month day weekday hour minute second years months days hours minutes seconds start end a)

      expressions =
        for operand <- @operands, property <- ["time offset", "timezone" | properties] do
          "(#{operand}).#{property}"
        end

      assert_no_failures(expressions, &Boxic.FEEL.evaluate/1)
    end

    test "inside unary and structural forms" do
      forms = [
        "-(%)",
        "not(%)",
        "% in [1..5]",
        "% in (>1, <0)",
        "% between 1 and 5",
        "for i in % return i",
        "some i in % satisfies i",
        "[%][1]",
        "[%][item > 1]",
        "{x: %}.x",
        "if % then 1 else 2",
        "% instance of number",
        "% instance of list<number>",
        "(function(y) y)(%)",
        "sort([%, %], function(a, b) a < b)",
        "string(%)",
        "% in %"
      ]

      expressions =
        for operand <- @operands, form <- forms, do: String.replace(form, "%", operand)

      assert_no_failures(expressions, &Boxic.FEEL.evaluate/1)
    end

    test "passed to built-in functions" do
      functions =
        ~w(abs sqrt exp log even odd floor ceiling round string number date time duration sum product mean median mode stddev count min max sort reverse flatten)

      expressions =
        for operand <- @operands,
            function <- functions,
            arguments <- ["#{operand}", "#{operand}, 2", "2, #{operand}"] do
          "#{function}(#{arguments})"
        end

      assert_no_failures(expressions, &Boxic.FEEL.evaluate/1)
    end
  end

  describe "context values supplied by the host" do
    test "used with arithmetic, comparison, and navigation" do
      expressions = [
        "x",
        "x + 1",
        "1 + x",
        "x - 1",
        "1 - x",
        "x * 2",
        "x / 2",
        "x ** 2",
        "2 ** x",
        "x = 1",
        "x < 1",
        "x > 1",
        "x in [1..5]",
        "x.a",
        "x[1]",
        "x.days",
        "-x",
        ~S|x + duration("P1D")|,
        ~S|x - duration("P1M")|,
        ~S|duration("PT1H") + x|
      ]

      pairs = for expression <- expressions, value <- host_values(), do: {expression, value}

      assert_no_failures(pairs, fn {expression, value} ->
        Boxic.FEEL.evaluate(expression, %{"x" => value})
      end)
    end
  end

  describe "external functions" do
    setup do
      {:ok, context: ExternalFunctions.to_context(Registry)}
    end

    test "return a value for hostile arguments", %{context: context} do
      expressions = [
        "id_float(1e400)",
        "id_float(-1e400)",
        "id_float(1e-400)",
        "id_float(1e6144)",
        "id_integer(1e400)",
        "id_integer(1e-400)",
        "id_integer(1.5)",
        "id_integer(1e6144)",
        "id_number(1e6144)",
        "chr(-1)",
        "chr(1114112)",
        "chr(55296)",
        "chr(1e30)",
        "chr(-1e30)",
        "nan()",
        "echo(x: 1)",
        "echo_untyped(x: 1)",
        "echo(1, x: 1)",
        "id_float(x: 1)",
        "id_float()",
        "id_float(1, 2)",
        "id_float(null)",
        ~S|id_float("1")|,
        ~S|id_float(number("NaN"))|
      ]

      assert_no_failures(expressions, fn expression ->
        Boxic.FEEL.evaluate(expression, context)
      end)
    end

    test "return a value for hostile arguments given to invoke/3 directly" do
      registry = Registry.external_functions()

      calls =
        for name <- ["id_float", "id_integer", "id_number", "chr", "echo", "echo_untyped", "nan"],
            arguments <- [
              [],
              [Decimal.new("NaN")],
              [Decimal.new("Infinity")],
              [Decimal.new("-Infinity")],
              [Decimal.new("1e400")],
              [Decimal.new("-1e400")],
              [Decimal.new("1e-400")],
              [{:named_arg, "x", Decimal.new(1)}],
              [Decimal.new(1), {:named_arg, "x", Decimal.new(1)}],
              [nil],
              ["text"],
              [:atom],
              [Decimal.new(1), Decimal.new(2)]
            ] do
          {name, arguments}
        end

      assert_no_failures(calls, fn {name, arguments} ->
        ExternalFunctions.invoke(registry, name, arguments)
      end)
    end
  end
end
