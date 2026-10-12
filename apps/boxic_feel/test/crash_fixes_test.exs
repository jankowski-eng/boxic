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
end
