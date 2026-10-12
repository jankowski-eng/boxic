defmodule Boxic.DMN.NoRaiseTest do
  # The public API returns failures as values. These are hostile models, inputs, and arguments
  # that once raised an exception. None of them may raise, throw, or exit.
  use ExUnit.Case

  defp outcome(fun) do
    fun.()
  rescue
    exception -> {:raised, exception}
  catch
    kind, reason -> {:raised, {kind, reason}}
  end

  defp value?({:ok, _value}), do: true
  defp value?({:error, _reason}), do: true
  defp value?(:ok), do: true
  defp value?(_other), do: false

  defp assert_no_failures(inputs, fun) do
    failures =
      for input <- inputs,
          result = outcome(fn -> fun.(input) end),
          not value?(result),
          do: {input, result}

    assert failures == [], "inputs that did not return a value:\n" <> inspect(failures, limit: 20)
  end

  defp decision_table(rules) do
    """
    <definitions id="defs" name="table" namespace="urn:table">
      <inputData id="value" name="Value"><variable name="Value" typeRef="number"/></inputData>
      <decision id="dec" name="Result">
        <variable name="Result"/>
        <informationRequirement><requiredInput href="#value"/></informationRequirement>
        <decisionTable hitPolicy="FIRST">
          <input id="in"><inputExpression typeRef="number"><text>Value</text></inputExpression></input>
          <output id="out"><defaultOutputEntry><text>"default"</text></defaultOutputEntry></output>
          #{rules}
        </decisionTable>
      </decision>
    </definitions>
    """
  end

  defp typed(type, expression) do
    """
    <definitions id="defs" name="typed" namespace="urn:typed">
      <inputData id="in" name="In"><variable name="In" typeRef="#{type}"/></inputData>
      <decision id="dec" name="Out">
        <variable name="Out"/>
        <informationRequirement><requiredInput href="#in"/></informationRequirement>
        <literalExpression><text>#{expression}</text></literalExpression>
      </decision>
    </definitions>
    """
  end

  @rules [
    ~s|<rule id="r"><inputEntry><text></text></inputEntry><outputEntry><text>1</text></outputEntry></rule>|,
    ~s|<rule id="r"><inputEntry/><outputEntry><text>1</text></outputEntry></rule>|,
    ~s|<rule id="r"><inputEntry><text>-</text></inputEntry><outputEntry/></rule>|,
    ~s|<rule id="r"><inputEntry><text>-</text></inputEntry><outputEntry><text></text></outputEntry></rule>|,
    ~s|<rule id="r"><inputEntry><text>  </text></inputEntry><outputEntry><text>1</text></outputEntry></rule>|,
    ~s|<rule id="r"><inputEntry/><inputEntry/><outputEntry/><outputEntry/></rule>|,
    ~s|<rule id="r"></rule>|,
    ~s|<rule><inputEntry><text>[</text></inputEntry><outputEntry><text>1</text></outputEntry></rule>|,
    ~s|<rule><inputEntry><text>"a</text></inputEntry><outputEntry><text>1 +</text></outputEntry></rule>|,
    ~s|<rule><inputEntry><text>> 1, , ,</text></inputEntry><outputEntry><text>1</text></outputEntry></rule>|
  ]

  @requirements [
    "<requiredInput/>",
    ~s|<requiredInput href=""/>|,
    ~s|<requiredInput href="#"/>|,
    ~s|<requiredInput href="#missing"/>|,
    ~s|<requiredInput href="urn:other#missing"/>|,
    "<requiredDecision/>",
    ~s|<requiredDecision href="#dec"/>|,
    ~s|<requiredDecision href="#missing"/>|
  ]

  defp hostile_inputs do
    [
      nil,
      "",
      " ",
      "NaN",
      "nan",
      "sNaN",
      "Infinity",
      "-Infinity",
      "inf",
      "-inf",
      "1e999999",
      "1e6144",
      "1e-6144",
      "2020-02-30",
      "2020-02-30T10:00:00",
      "2020-13-45T10:00:00Z",
      "25:00:00",
      "PT",
      "P1.5D",
      "P99999999999999999999999999999999999999999999D",
      "true",
      "é",
      <<255>>,
      Decimal.new("NaN"),
      Decimal.new("Infinity"),
      Decimal.new("-1e6144"),
      Decimal.new("1e6144"),
      true,
      false,
      [],
      [nil],
      [Decimal.new(1)],
      ["NaN"],
      %{},
      %{"a" => "NaN"},
      ~D[2020-01-01],
      :atom,
      {:tuple, 1},
      self(),
      fn value -> value end
    ]
  end

  describe "decision tables with entries that have no text" do
    test "are reported by validate and evaluate" do
      assert_no_failures(@rules, fn rules ->
        with {:ok, model} <- Boxic.DMN.load_xml(decision_table(rules)) do
          Boxic.DMN.validate(model)
          Boxic.DMN.evaluate(model, "Result", %{"Value" => Decimal.new(5)})
        end
      end)
    end

    test "are reported for every hostile input" do
      pairs = for rules <- @rules, input <- hostile_inputs(), do: {rules, input}

      assert_no_failures(pairs, fn {rules, input} ->
        with {:ok, model} <- Boxic.DMN.load_xml(decision_table(rules)) do
          Boxic.DMN.evaluate(model, "Result", %{"Value" => input})
        end
      end)
    end
  end

  describe "information requirements that do not resolve" do
    test "are reported by validate and evaluate" do
      assert_no_failures(@requirements, fn requirement ->
        xml = """
        <definitions id="defs" name="requirements" namespace="urn:requirements">
          <inputData id="in" name="In"><variable name="In"/></inputData>
          <decision id="dec" name="Out">
            <informationRequirement>#{requirement}</informationRequirement>
            <literalExpression><text>In</text></literalExpression>
          </decision>
        </definitions>
        """

        with {:ok, model} <- Boxic.DMN.load_xml(xml) do
          Boxic.DMN.validate(model)
          Boxic.DMN.evaluate(model, "Out", %{"In" => Decimal.new(1)})
        end
      end)
    end
  end

  describe "typed inputs" do
    @types ~w(string number boolean date time dateTime duration dayTimeDuration yearMonthDuration Any Unknown)
    @types_with_spaces ["date and time", "days and time duration", "years and months duration"]
    @expressions [
      "In",
      "In > 1",
      "In * 10",
      "In ** 0.5",
      "In + 1",
      "In = In",
      "string(In)",
      "In.a"
    ]

    test "accept hostile values without raising" do
      combinations =
        for type <- @types ++ @types_with_spaces,
            expression <- @expressions,
            input <- hostile_inputs(),
            do: {type, expression, input}

      assert_no_failures(combinations, fn {type, expression, input} ->
        with {:ok, model} <- Boxic.DMN.load_xml(typed(type, expression)) do
          Boxic.DMN.evaluate(model, "Out", %{"In" => input})
        end
      end)
    end
  end

  describe "arguments that are not a model, a name, or a context" do
    test "return an error tuple" do
      {:ok, model} = Boxic.DMN.load_xml(typed("number", "In"))
      values = [nil, 1, "text", :atom, [], [1 | 2], %{}, {:tuple}, self()]

      calls =
        for a <- [model | values], b <- ["Out" | values], c <- [%{} | values] do
          [a, b, c]
        end

      assert_no_failures(calls, fn [model, name, context] ->
        Boxic.DMN.evaluate(model, name, context)
      end)

      assert_no_failures(calls, fn [model, name, argument] ->
        Boxic.DMN.evaluate_service(model, name, argument)
      end)

      assert_no_failures(calls, fn [model, name, context] ->
        Boxic.DMN.evaluate(model, name, context, [])
      end)

      assert_no_failures(Enum.map([[] | values], &[&1]), fn [options] ->
        Boxic.DMN.evaluate(model, "Out", %{"In" => Decimal.new(1)}, options)
      end)

      assert_no_failures(Enum.map(values, &[&1]), fn [registry] ->
        Boxic.DMN.evaluate(model, "Out", %{"In" => Decimal.new(1)}, external_functions: registry)
      end)
    end
  end
end
