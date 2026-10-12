defmodule Boxic.FEEL.ExternalFunctionsTest do
  use ExUnit.Case

  alias Boxic.FEEL.ExternalFunctions

  defmodule HostFunctions do
    def max(left, right), do: Kernel.max(left, right)
    def cosine(value), do: :math.cos(value)
    def identity(value), do: value
    def join(first, rest), do: Enum.join([first | rest], " ")
    def explode(_value), do: raise("host failure")
    def nan, do: Decimal.new("NaN")
    def infinity, do: Decimal.new("Infinity")

    def reject_named(value) do
      if match?({:named_arg, _, _}, value), do: raise("named argument leaked"), else: value
    end

    def reject_named_all(args) do
      if Enum.any?(args, &match?({:named_arg, _, _}, &1)), do: raise("named argument leaked")
      length(args)
    end
  end

  defmodule Registry do
    use ExternalFunctions

    external("max", {HostFunctions, :max}, parameters: [:float, :float], returns: :number)
    external("cos", {HostFunctions, :cosine}, parameters: [:float], returns: :number)
    external("integer", {HostFunctions, :identity}, parameters: [:integer], returns: :integer)
    external("char", {HostFunctions, :identity}, parameters: [:char], returns: :char)

    external("join", {HostFunctions, :join},
      parameters: [:string, {:varargs, :string}],
      returns: :string
    )

    external("explode", {HostFunctions, :explode}, parameters: [:feel], returns: :feel)
    external("id_float", {HostFunctions, :identity}, parameters: [:float], returns: :number)
    external("id_integer", {HostFunctions, :identity}, parameters: [:integer], returns: :integer)
    external("id_number", {HostFunctions, :identity}, parameters: [:number], returns: :number)
    external("chr", {HostFunctions, :identity}, parameters: [:integer], returns: :char)
    external("nan", {HostFunctions, :nan}, returns: :number)
    external("infinity", {HostFunctions, :infinity}, returns: :number)
    external("typed_echo", {HostFunctions, :reject_named}, parameters: [:feel], returns: :feel)
    external("untyped_echo", {HostFunctions, :reject_named}, returns: :feel)

    external("count_args", {HostFunctions, :reject_named_all},
      parameters: [{:varargs, :feel}],
      returns: :number
    )
  end

  test "an allowlisted Elixir function is callable from FEEL and may shadow a built-in" do
    context = Registry.external_functions() |> ExternalFunctions.to_context()

    assert {:ok, result} = Boxic.FEEL.evaluate("max(123.45, 456.78)", context)
    assert Decimal.equal?(result, Decimal.new("456.78"))

    assert {:ok, cosine} = Boxic.FEEL.evaluate("cos(123)", context)
    assert Decimal.equal?(Decimal.round(cosine, 8), Decimal.new("-0.88796891"))
  end

  test "the boundary converts integer, character, and vararg values" do
    context = ExternalFunctions.to_context(Registry)

    assert {:ok, integer} = Boxic.FEEL.evaluate("integer(456)", context)
    assert Decimal.equal?(integer, Decimal.new(456))
    assert {:ok, "a"} = Boxic.FEEL.evaluate(~S|char("a")|, context)
    assert {:ok, "foo bar baz"} = Boxic.FEEL.evaluate(~S|join("foo", "bar", "baz")|, context)
  end

  test "invalid arity, conversion, and host exceptions remain structured FEEL errors" do
    context = ExternalFunctions.to_context(Registry)

    assert {:error, %{code: :arity_error}} = Boxic.FEEL.evaluate("max(1)", context)
    assert {:error, %{code: :type_error}} = Boxic.FEEL.evaluate(~S|char("abc")|, context)

    assert {:error, %{code: :external_function_error, message: "host failure"}} =
             Boxic.FEEL.evaluate("explode(1)", context)
  end

  describe "values that cannot cross the boundary" do
    setup do
      {:ok, context: ExternalFunctions.to_context(Registry)}
    end

    test "a number outside the range of a float is a type error", %{context: context} do
      for expression <- ["id_float(1e400)", "id_float(1e-400)", "id_float(-1e400)"] do
        assert {:error, %{code: :type_error}} = Boxic.FEEL.evaluate(expression, context),
               expression
      end

      assert {:ok, one} = Boxic.FEEL.evaluate("id_float(1.5)", context)
      assert Decimal.equal?(one, Decimal.new("1.5"))
    end

    test "an integer of any size converts exactly", %{context: context} do
      assert {:ok, huge} = Boxic.FEEL.evaluate("id_integer(1e400)", context)
      assert Decimal.equal?(huge, Decimal.new("1e400"))

      assert {:ok, small} = Boxic.FEEL.evaluate("id_integer(-42)", context)
      assert Decimal.equal?(small, Decimal.new(-42))

      assert {:error, %{code: :type_error}} = Boxic.FEEL.evaluate("id_integer(1.5)", context)
      assert {:error, %{code: :type_error}} = Boxic.FEEL.evaluate("id_integer(1e-400)", context)
    end

    test "a non-finite number is a type error in either direction", %{context: context} do
      assert {:error, %{code: :type_error}} = Boxic.FEEL.evaluate("nan()", context)
      assert {:error, %{code: :type_error}} = Boxic.FEEL.evaluate("infinity()", context)

      registry = Registry.external_functions()

      for name <- ["id_float", "id_integer", "id_number"],
          value <- [Decimal.new("NaN"), Decimal.new("Infinity"), Decimal.new("-Infinity")] do
        assert {:error, %{code: :type_error}} = ExternalFunctions.invoke(registry, name, [value]),
               "#{name} #{inspect(value)}"
      end
    end

    test "a character return that is not a Unicode scalar value is a type error", %{
      context: context
    } do
      for expression <- ["chr(-1)", "chr(1114112)", "chr(55296)", "chr(57343)", "chr(1e30)"] do
        assert {:error, %{code: :type_error}} = Boxic.FEEL.evaluate(expression, context),
               expression
      end

      assert {:ok, "A"} = Boxic.FEEL.evaluate("chr(65)", context)
      assert {:ok, <<0x10FFFF::utf8>>} = Boxic.FEEL.evaluate("chr(1114111)", context)
      assert {:ok, <<0::utf8>>} = Boxic.FEEL.evaluate("chr(0)", context)
    end

    test "conversion failures are structured errors from invoke/3 as well" do
      registry = Registry.external_functions()

      assert {:error, %{code: :type_error}} =
               ExternalFunctions.invoke(registry, "id_float", [Decimal.new("1e400")])

      assert {:error, %{code: :type_error}} =
               ExternalFunctions.invoke(registry, "chr", [Decimal.new(-1)])
    end
  end

  describe "named arguments" do
    setup do
      {:ok, context: ExternalFunctions.to_context(Registry)}
    end

    test "are an arity error and never reach the host function", %{context: context} do
      for expression <- [
            "typed_echo(x: 1)",
            "untyped_echo(x: 1)",
            "count_args(x: 1)",
            "count_args(1, x: 1)",
            "count_args(x: 1, y: 2)",
            "max(a: 1, b: 2)",
            "integer(n: 1)"
          ] do
        assert {:error, %{code: :arity_error}} = Boxic.FEEL.evaluate(expression, context),
               expression
      end
    end

    test "are rejected by invoke/3 directly" do
      registry = Registry.external_functions()

      assert {:error, %{code: :arity_error}} =
               ExternalFunctions.invoke(registry, "typed_echo", [
                 {:named_arg, "x", Decimal.new(1)}
               ])

      assert {:error, %{code: :arity_error}} =
               ExternalFunctions.invoke(registry, "untyped_echo", [
                 {:named_arg, "x", Decimal.new(1)}
               ])
    end

    test "positional calls are unaffected", %{context: context} do
      assert {:ok, one} = Boxic.FEEL.evaluate("typed_echo(1)", context)
      assert Decimal.equal?(one, Decimal.new(1))
      assert {:ok, one} = Boxic.FEEL.evaluate("untyped_echo(1)", context)
      assert Decimal.equal?(one, Decimal.new(1))
      assert {:ok, three} = Boxic.FEEL.evaluate("count_args(1, 2, 3)", context)
      assert Decimal.equal?(three, Decimal.new(3))
    end

    test "are not passed to a plain Elixir function in the context either" do
      context = %{"f" => fn value -> value end}

      assert {:error, %{code: :arity_error}} = Boxic.FEEL.evaluate("f(x: 1)", context)
      assert {:ok, one} = Boxic.FEEL.evaluate("f(1)", context)
      assert Decimal.equal?(one, Decimal.new(1))
    end
  end
end
