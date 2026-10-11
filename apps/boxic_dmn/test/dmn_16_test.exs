defmodule Boxic.DMN16Test do
  use ExUnit.Case, async: true

  @model_16 "https://www.omg.org/spec/DMN/20240513/MODEL/"
  @feel_16 "https://www.omg.org/spec/DMN/20240513/FEEL/"
  @feel_14 "https://www.omg.org/spec/DMN/20211108/FEEL/"
  @b_feel_16 "https://www.omg.org/spec/DMN/20240513/B-FEEL/"

  defp load!(body) do
    xml = """
    <definitions xmlns="#{@model_16}" id="defs" name="model" namespace="urn:model">
      #{body}
    </definitions>
    """

    assert {:ok, model} = Boxic.DMN.load_xml(xml)
    model
  end

  defp literal_decision(text, language \\ nil) do
    attribute = if language, do: ~s( expressionLanguage="#{language}"), else: ""

    """
    <decision id="dec" name="Result">
      <variable name="Result"/>
      <literalExpression#{attribute}><text>#{text}</text></literalExpression>
    </decision>
    """
  end

  defp boxed_decision(boxed) do
    """
    <decision id="dec" name="Result">
      <variable name="Result"/>
      #{boxed}
    </decision>
    """
  end

  defp literal(tag, text),
    do: "<#{tag}><literalExpression><text>#{text}</text></literalExpression></#{tag}>"

  defp number(value), do: Decimal.new(to_string(value))

  describe "DMN 1.6 documents" do
    test "load, validate and evaluate under the 1.6 model namespace" do
      model = load!(literal_decision("1 + 1"))

      assert model.definitions.namespace == "urn:model"
      assert :ok = Boxic.DMN.validate(model)
      assert {:ok, result} = Boxic.DMN.evaluate(model, "Result")
      assert Decimal.equal?(result, number(2))
    end

    test "accept the FEEL language URIs of DMN 1.4 and 1.6" do
      for language <- [@feel_16, @feel_14] do
        model = load!(literal_decision("1", language))
        assert :ok = Boxic.DMN.validate(model), language
      end
    end

    test "reject the B-FEEL dialect, which is not supported" do
      model = load!(literal_decision("1", @b_feel_16))

      assert {:error, errors} = Boxic.DMN.validate(model)
      assert Enum.any?(errors, &match?({:unsupported_expression_language, _, @b_feel_16}, &1))
    end

    test "evaluate the 1.6 FEEL additions inside decisions" do
      model = load!(literal_decision(~S|date("1970-01-02").value|))
      assert {:ok, seconds} = Boxic.DMN.evaluate(model, "Result")
      assert Decimal.equal?(seconds, number(86_400))

      model = load!(literal_decision("{a: {b: 1, c: {b: 2}}}...b"))
      assert {:ok, [one, two]} = Boxic.DMN.evaluate(model, "Result")
      assert Decimal.equal?(one, number(1)) and Decimal.equal?(two, number(2))
    end
  end

  describe "item definitions" do
    test "retain typeConstraint next to allowedValues" do
      model =
        load!("""
        <itemDefinition id="age" name="Age">
          <typeRef>number</typeRef>
          <allowedValues><text>[0..150]</text></allowedValues>
          <typeConstraint><text>value = floor(value)</text></typeConstraint>
        </itemDefinition>
        <itemDefinition id="person" name="Person">
          <itemComponent id="years" name="years">
            <typeRef>number</typeRef>
            <typeConstraint><text>&gt; 0</text></typeConstraint>
          </itemComponent>
        </itemDefinition>
        #{literal_decision("1")}
        """)

      age = model.item_definitions["Age"]
      assert age.allowed_values == "[0..150]"
      assert age.type_constraint == "value = floor(value)"

      assert [%{name: "years", type_constraint: "> 0", allowed_values: nil}] =
               model.item_definitions["Person"].components

      assert :ok = Boxic.DMN.validate(model)
    end
  end

  describe "boxed filter and iterators" do
    test "convert a single value into a singleton list" do
      model =
        load!(
          boxed_decision("""
          <for iteratorVariable="x">
            #{literal("in", "5")}
            #{literal("return", "x * 2")}
          </for>
          """)
        )

      assert {:ok, [ten]} = Boxic.DMN.evaluate(model, "Result")
      assert Decimal.equal?(ten, number(10))
    end

    test "filter a single value as a one-element list" do
      keep =
        load!(
          boxed_decision("<filter>#{literal("in", "5")}#{literal("match", "item > 3")}</filter>")
        )

      drop =
        load!(
          boxed_decision("<filter>#{literal("in", "5")}#{literal("match", "item > 9")}</filter>")
        )

      assert {:ok, [five]} = Boxic.DMN.evaluate(keep, "Result")
      assert Decimal.equal?(five, number(5))
      assert {:ok, []} = Boxic.DMN.evaluate(drop, "Result")
    end

    test "evaluate quantifiers over a single value" do
      some =
        load!(
          boxed_decision(
            ~s|<some iteratorVariable="x">#{literal("in", "5")}#{literal("satisfies", "x > 3")}</some>|
          )
        )

      every =
        load!(
          boxed_decision(
            ~s|<every iteratorVariable="x">#{literal("in", "5")}#{literal("satisfies", "x > 9")}</every>|
          )
        )

      assert {:ok, true} = Boxic.DMN.evaluate(some, "Result")
      assert {:ok, false} = Boxic.DMN.evaluate(every, "Result")
    end

    test "still iterate lists element by element" do
      model =
        load!(
          boxed_decision(
            ~s|<for iteratorVariable="x">#{literal("in", "[1, 2, 3]")}#{literal("return", "x * 2")}</for>|
          )
        )

      assert {:ok, [two, four, six]} = Boxic.DMN.evaluate(model, "Result")

      assert Enum.zip([two, four, six], [2, 4, 6])
             |> Enum.all?(fn {a, b} -> Decimal.equal?(a, number(b)) end)
    end

    test "do not turn null into a collection" do
      model =
        load!(
          boxed_decision(
            ~s|<for iteratorVariable="x">#{literal("in", "null")}#{literal("return", "x")}</for>|
          )
        )

      assert {:error, {:type_error, :list}} = Boxic.DMN.evaluate(model, "Result")
    end
  end

  describe "decision table input entries" do
    defp range_table(input) do
      model =
        load!("""
        <inputData id="value" name="Value"><variable name="Value" typeRef="string"/></inputData>
        <decision id="dec" name="Result">
          <variable name="Result"/>
          <informationRequirement><requiredInput href="#value"/></informationRequirement>
          <decisionTable hitPolicy="FIRST">
            <input id="in"><inputExpression typeRef="string"><text>Value</text></inputExpression></input>
            <output id="out"/>
            <rule><inputEntry><text>#{input}</text></inputEntry><outputEntry><text>"low"</text></outputEntry></rule>
            <rule><inputEntry><text>-</text></inputEntry><outputEntry><text>"other"</text></outputEntry></rule>
          </decisionTable>
        </decision>
        """)

      model
    end

    test "do not match a value that cannot be compared with a range" do
      model = range_table("[1..10]")

      assert {:ok, "other"} = Boxic.DMN.evaluate(model, "Result", %{"Value" => "abc"})
    end

    test "do not match a range for a null input" do
      model = range_table("[1..10]")

      assert {:ok, "other"} = Boxic.DMN.evaluate(model, "Result", %{"Value" => nil})
    end

    test "do not match a negated range for a value that cannot be compared" do
      model = range_table("not([1..10])")

      assert {:ok, "other"} = Boxic.DMN.evaluate(model, "Result", %{"Value" => "abc"})
    end
  end

  describe "implicit type conversions" do
    @list_types """
    <itemDefinition id="strings" name="stringList" isCollection="true"><typeRef>string</typeRef></itemDefinition>
    <itemDefinition id="numbers" name="numberList" isCollection="true"><typeRef>number</typeRef></itemDefinition>
    <itemDefinition id="alias" name="Alias"><typeRef>numberList</typeRef></itemDefinition>
    <itemDefinition id="person" name="Person">
      <itemComponent id="p1" name="name"><typeRef>string</typeRef></itemComponent>
    </itemDefinition>
    """

    defp typed_decision(type_ref, text) do
      load!("""
      #{@list_types}
      <decision id="dec" name="Result">
        <variable name="Result" typeRef="#{type_ref}"/>
        <literalExpression><text>#{text}</text></literalExpression>
      </decision>
      """)
    end

    test "convert a single value to a singleton list" do
      assert {:ok, ["abc"]} =
               Boxic.DMN.evaluate(typed_decision("stringList", ~S|"abc"|), "Result")
    end

    test "convert a singleton list to its element" do
      assert {:ok, "abc"} = Boxic.DMN.evaluate(typed_decision("string", ~S|["abc"]|), "Result")

      assert {:ok, ~D[2000-01-02]} =
               Boxic.DMN.evaluate(typed_decision("date", ~S|[date("2000-01-02")]|), "Result")

      assert {:ok, %{"name" => "Ada"}} =
               Boxic.DMN.evaluate(typed_decision("Person", ~S|[{name: "Ada"}]|), "Result")
    end

    test "keep a list that is not a singleton for a collection type" do
      assert {:ok, [one]} = Boxic.DMN.evaluate(typed_decision("Alias", "[1]"), "Result")
      assert Decimal.equal?(one, number(1))
    end

    test "convert a date to a date and time at UTC midnight" do
      model = typed_decision("date and time", ~S|date("2000-01-02")|)

      assert {:ok, %Boxic.FEEL.DateTime{} = value} = Boxic.DMN.evaluate(model, "Result")
      assert "2000-01-02T00:00:00Z" == Boxic.FEEL.DateTime.to_string(value)
    end

    test "produce null when a result cannot be converted to its type" do
      assert {:ok, nil} =
               Boxic.DMN.evaluate(typed_decision("string", ~S|["abc", "bcd"]|), "Result")

      assert {:ok, nil} = Boxic.DMN.evaluate(typed_decision("number", ~S|"abc"|), "Result")
    end

    test "still reject input data that does not match its declared type" do
      model =
        load!("""
        <inputData id="age" name="Age"><variable name="Age" typeRef="number"/></inputData>
        <decision id="dec" name="Result">
          <variable name="Result" typeRef="number"/>
          <informationRequirement><requiredInput href="#age"/></informationRequirement>
          <literalExpression><text>Age</text></literalExpression>
        </decision>
        """)

      assert {:error, {:type_error, "number"}} =
               Boxic.DMN.evaluate(model, "Result", %{"Age" => "old"})
    end

    test "convert context entries to the type of their variable" do
      model =
        load!("""
        #{@list_types}
        <decision id="dec" name="Result">
          <variable name="Result"/>
          <context>
            <contextEntry>
              <variable name="listed" typeRef="numberList"/>
              <literalExpression><text>1</text></literalExpression>
            </contextEntry>
            <contextEntry>
              <variable name="single" typeRef="number"/>
              <literalExpression><text>[2]</text></literalExpression>
            </contextEntry>
            <contextEntry>
              <variable name="moment" typeRef="date and time"/>
              <literalExpression><text>date("2000-12-01")</text></literalExpression>
            </contextEntry>
            <contextEntry><literalExpression><text>[listed, single, moment]</text></literalExpression></contextEntry>
          </context>
        </decision>
        """)

      assert {:ok, [[one], two, %Boxic.FEEL.DateTime{} = moment]} =
               Boxic.DMN.evaluate(model, "Result")

      assert Decimal.equal?(one, number(1)) and Decimal.equal?(two, number(2))
      assert "2000-12-01T00:00:00Z" == Boxic.FEEL.DateTime.to_string(moment)
    end

    test "convert invocation arguments to the parameter types of a business knowledge model" do
      model =
        load!("""
        #{@list_types}
        <businessKnowledgeModel id="bkm" name="Count">
          <variable name="Count"/>
          <encapsulatedLogic>
            <formalParameter name="xs" typeRef="numberList"/>
            <literalExpression><text>count(xs)</text></literalExpression>
          </encapsulatedLogic>
        </businessKnowledgeModel>
        """)

      assert {:ok, count} = Boxic.DMN.evaluate_bkm(model, "Count", %{"xs" => number(5)})
      assert Decimal.equal?(count, number(1))
    end
  end

  describe "evaluate_bkm/3" do
    setup do
      model =
        load!("""
        <businessKnowledgeModel id="bkm" name="Scale">
          <variable name="Scale" typeRef="number"/>
          <encapsulatedLogic>
            <formalParameter name="value" typeRef="number"/>
            <formalParameter name="factor" typeRef="number"/>
            <literalExpression><text>value * factor</text></literalExpression>
          </encapsulatedLogic>
        </businessKnowledgeModel>
        """)

      %{model: model}
    end

    test "accepts arguments by name or by position", %{model: model} do
      named = %{"value" => number(6), "factor" => number(7)}
      assert {:ok, product} = Boxic.DMN.evaluate_bkm(model, "Scale", named)
      assert Decimal.equal?(product, number(42))

      assert {:ok, product} = Boxic.DMN.evaluate_bkm(model, "Scale", [number(2), number(3)])
      assert Decimal.equal?(product, number(6))
    end

    test "reports unknown business knowledge models and wrong arguments", %{model: model} do
      assert {:error, {:bkm_not_found, "Missing"}} = Boxic.DMN.evaluate_bkm(model, "Missing", %{})
      assert {:error, _reason} = Boxic.DMN.evaluate_bkm(model, "Scale", %{"value" => number(1)})
    end
  end

  describe "externally defined function kinds" do
    test "ONNX business knowledge models are reported as unsupported" do
      model =
        load!("""
        <businessKnowledgeModel id="bkm" name="Predict">
          <variable name="Predict"/>
          <encapsulatedLogic kind="ONNX">
            <formalParameter name="input" typeRef="number"/>
            <context>
              <contextEntry>
                <variable name="file"/>
                <literalExpression><text>"model.onnx"</text></literalExpression>
              </contextEntry>
            </context>
          </encapsulatedLogic>
        </businessKnowledgeModel>
        """)

      assert {:unsupported, "functionDefinition:ONNX"} = model.bkms["bkm"].expression
      assert {:error, errors} = Boxic.DMN.validate(model)

      assert Enum.any?(
               errors,
               &match?({:unsupported_expression, _, "functionDefinition:ONNX"}, &1)
             )
    end

    test "Java and PMML function definitions are no longer evaluated as FEEL" do
      for kind <- ["Java", "PMML", "ONNX"] do
        model =
          load!(
            boxed_decision("""
            <context>
              <contextEntry>
                <variable name="f"/>
                <functionDefinition kind="#{kind}">
                  <formalParameter name="n" typeRef="number"/>
                  <literalExpression><text>"mapping"</text></literalExpression>
                </functionDefinition>
              </contextEntry>
              <contextEntry><literalExpression><text>f(1)</text></literalExpression></contextEntry>
            </context>
            """)
          )

        assert {:error, [{:unsupported_expression, _, "functionDefinition:" <> ^kind}]} =
                 Boxic.DMN.evaluate(model, "Result")
      end
    end

    test "FEEL function definitions evaluate with or without an explicit kind" do
      for attributes <- ["", ~s( kind="FEEL")] do
        model =
          load!(
            boxed_decision("""
            <context>
              <contextEntry>
                <variable name="f"/>
                <functionDefinition#{attributes}>
                  <formalParameter name="n" typeRef="number"/>
                  <literalExpression><text>n + 1</text></literalExpression>
                </functionDefinition>
              </contextEntry>
              <contextEntry><literalExpression><text>f(1)</text></literalExpression></contextEntry>
            </context>
            """)
          )

        assert {:ok, two} = Boxic.DMN.evaluate(model, "Result")
        assert Decimal.equal?(two, number(2))
      end
    end
  end
end
