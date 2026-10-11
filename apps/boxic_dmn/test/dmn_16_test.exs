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
