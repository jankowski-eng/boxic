defmodule Boxic.DMN.CrashFixesTest do
  # Models and inputs that used to raise out of the public API. Failures must be returned as
  # values.
  use ExUnit.Case

  defp load!(xml) do
    assert {:ok, model} = Boxic.DMN.load_xml(xml)
    model
  end

  defp table_model(entries) do
    load!("""
    <definitions id="defs" name="entries" namespace="urn:entries">
      <inputData id="value" name="Value"><variable name="Value" typeRef="number"/></inputData>
      <decision id="dec" name="Result">
        <variable name="Result"/>
        <informationRequirement><requiredInput href="#value"/></informationRequirement>
        <decisionTable hitPolicy="FIRST">
          <input id="in"><inputExpression typeRef="number"><text>Value</text></inputExpression></input>
          <output id="out"/>
          #{entries}
          <rule id="fallback">
            <inputEntry><text>-</text></inputEntry>
            <outputEntry><text>"other"</text></outputEntry>
          </rule>
        </decisionTable>
      </decision>
    </definitions>
    """)
  end

  defp decision_model(variable_type, text) do
    load!("""
    <definitions id="defs" name="typed" namespace="urn:typed">
      <inputData id="in" name="In"><variable name="In" typeRef="#{variable_type}"/></inputData>
      <decision id="dec" name="Out">
        <variable name="Out"/>
        <informationRequirement><requiredInput href="#in"/></informationRequirement>
        <literalExpression><text>#{text}</text></literalExpression>
      </decision>
    </definitions>
    """)
  end

  describe "decision table entries without text" do
    for {name, entry} <- [
          {"an empty text element", "<inputEntry><text></text></inputEntry>"},
          {"a self-closing text element", "<inputEntry><text/></inputEntry>"},
          {"no text element", "<inputEntry/>"},
          {"a whitespace-only text element", "<inputEntry><text>  \n </text></inputEntry>"}
        ] do
      test "an input entry with #{name} is invalid and cannot be evaluated" do
        model =
          table_model("""
          <rule id="bad">
            #{unquote(entry)}
            <outputEntry><text>"bad"</text></outputEntry>
          </rule>
          """)

        assert {:error, errors} = Boxic.DMN.validate(model)
        assert {:missing_entry_text, "bad", :input_entries, 0} in errors

        assert {:error, errors} =
                 Boxic.DMN.evaluate(model, "Result", %{"Value" => Decimal.new(1)})

        assert {:missing_entry_text, "bad", :input_entries, 0} in List.wrap(errors)
      end
    end

    for {name, entry} <- [
          {"an empty text element", "<outputEntry><text></text></outputEntry>"},
          {"no text element", "<outputEntry/>"}
        ] do
      test "an output entry with #{name} is invalid and cannot be evaluated" do
        model =
          table_model("""
          <rule id="bad">
            <inputEntry><text>&gt; 0</text></inputEntry>
            #{unquote(entry)}
          </rule>
          """)

        assert {:error, errors} = Boxic.DMN.validate(model)
        assert {:missing_entry_text, "bad", :output_entries, 0} in errors

        assert {:error, errors} =
                 Boxic.DMN.evaluate(model, "Result", %{"Value" => Decimal.new(1)})

        assert {:missing_entry_text, "bad", :output_entries, 0} in List.wrap(errors)
      end
    end

    test "the position of the entry is reported" do
      model =
        load!("""
        <definitions id="defs" name="positions" namespace="urn:positions">
          <decision id="dec" name="Result">
            <decisionTable>
              <input><inputExpression><text>1</text></inputExpression></input>
              <input><inputExpression><text>2</text></inputExpression></input>
              <output name="a"/>
              <output name="b"/>
              <rule id="r">
                <inputEntry><text>1</text></inputEntry>
                <inputEntry/>
                <outputEntry/>
                <outputEntry><text>1</text></outputEntry>
              </rule>
            </decisionTable>
          </decision>
        </definitions>
        """)

      assert {:error, errors} = Boxic.DMN.validate(model)
      assert {:missing_entry_text, "r", :input_entries, 1} in errors
      assert {:missing_entry_text, "r", :output_entries, 0} in errors
      refute {:missing_entry_text, "r", :input_entries, 0} in errors
      refute {:missing_entry_text, "r", :output_entries, 1} in errors
    end

    test "an input expression without text is an error rather than a crash" do
      model =
        load!("""
        <definitions id="defs" name="expression" namespace="urn:expression">
          <decision id="dec" name="Result">
            <decisionTable>
              <input id="in"><inputExpression><text/></inputExpression></input>
              <output name="a"/>
              <rule id="r"><inputEntry><text>-</text></inputEntry><outputEntry><text>1</text></outputEntry></rule>
            </decisionTable>
          </decision>
        </definitions>
        """)

      assert {:error, errors} = Boxic.DMN.validate(model)
      assert {:missing_input_expression, "dec", "in"} in errors
      assert {:error, _} = Boxic.DMN.evaluate(model, "Result")
    end

    test "a decision table inside a business knowledge model is checked when it is invoked" do
      model =
        load!("""
        <definitions id="defs" name="bkm table" namespace="urn:bkm-table">
          <businessKnowledgeModel id="pick" name="pick">
            <variable name="pick"/>
            <encapsulatedLogic>
              <formalParameter name="n" typeRef="number"/>
              <decisionTable hitPolicy="FIRST">
                <input><inputExpression><text>n</text></inputExpression></input>
                <output name="r"/>
                <rule id="bad"><inputEntry/><outputEntry><text>1</text></outputEntry></rule>
              </decisionTable>
            </encapsulatedLogic>
          </businessKnowledgeModel>
          <decision id="dec" name="Result">
            <knowledgeRequirement><requiredKnowledge href="#pick"/></knowledgeRequirement>
            <literalExpression><text>pick(1)</text></literalExpression>
          </decision>
        </definitions>
        """)

      assert {:error, _reason} = Boxic.DMN.evaluate(model, "Result")
    end

    test "tables whose entries all have text still evaluate" do
      model =
        table_model("""
        <rule id="low"><inputEntry><text>&lt; 10</text></inputEntry><outputEntry><text>"low"</text></outputEntry></rule>
        """)

      assert :ok = Boxic.DMN.validate(model)
      assert {:ok, "low"} = Boxic.DMN.evaluate(model, "Result", %{"Value" => Decimal.new(5)})
      assert {:ok, "other"} = Boxic.DMN.evaluate(model, "Result", %{"Value" => Decimal.new(50)})
    end
  end

  describe "an information requirement without an href" do
    test "is reported by validate and is an error when evaluated" do
      for kind <- ["requiredInput", "requiredDecision", "requiredKnowledge"] do
        model =
          load!("""
          <definitions id="defs" name="no href" namespace="urn:no-href">
            <inputData id="in" name="In"><variable name="In"/></inputData>
            <decision id="dec" name="Out">
              <informationRequirement><#{kind}/></informationRequirement>
              <literalExpression><text>In</text></literalExpression>
            </decision>
          </definitions>
          """)

        assert {:error, errors} = Boxic.DMN.validate(model)
        assert Enum.any?(errors, &match?({:unresolved_reference, "dec", _kind, nil}, &1)), kind

        assert {:error, _reason} = Boxic.DMN.evaluate(model, "Out", %{"In" => Decimal.new(1)})
      end
    end

    test "an empty href is an error as well" do
      model =
        load!("""
        <definitions id="defs" name="empty href" namespace="urn:empty-href">
          <decision id="dec" name="Out">
            <informationRequirement><requiredInput href=""/></informationRequirement>
            <literalExpression><text>1</text></literalExpression>
          </decision>
        </definitions>
        """)

      assert {:error, _errors} = Boxic.DMN.validate(model)
      assert {:error, _reason} = Boxic.DMN.evaluate(model, "Out")
    end
  end

  describe "inputs of type date and time" do
    for type <- ["date and time", "dateTime"] do
      test "an impossible date is a type error for #{type}" do
        model = decision_model(unquote(type), "In")

        for value <- ["2020-02-30T10:00:00", "2020-13-45T10:00:00Z", "2021-02-29T00:00:00"] do
          assert {:error, {:type_error, unquote(type)}} =
                   Boxic.DMN.evaluate(model, "Out", %{"In" => value}),
                 value
        end
      end

      test "a valid date and time is still accepted for #{type}" do
        model = decision_model(unquote(type), "In")

        assert {:ok, %Boxic.FEEL.DateTime{}} =
                 Boxic.DMN.evaluate(model, "Out", %{"In" => "2020-02-29T10:00:00"})
      end
    end

    test "an impossible time or duration is a type error too" do
      assert {:error, {:type_error, "time"}} =
               Boxic.DMN.evaluate(decision_model("time", "In"), "Out", %{"In" => "25:00:00"})

      assert {:error, {:type_error, "duration"}} =
               Boxic.DMN.evaluate(decision_model("duration", "In"), "Out", %{"In" => "PT"})
    end
  end

  describe "exponentiation in a decision" do
    test "a power that is not a real number is null" do
      model = decision_model("number", "In ** 0.5")

      assert {:ok, nil} = Boxic.DMN.evaluate(model, "Out", %{"In" => Decimal.new(-4)})
      assert {:ok, root} = Boxic.DMN.evaluate(model, "Out", %{"In" => Decimal.new(4)})
      assert Decimal.equal?(root, Decimal.new(2))
    end

    test "an overflowing product is null" do
      model = decision_model("number", "In * 10")
      assert {:ok, nil} = Boxic.DMN.evaluate(model, "Out", %{"In" => Decimal.new("1e6144")})
    end
  end

  describe "non-finite numbers for a number input" do
    for text <- ["NaN", "nan", "sNaN", "Infinity", "-Infinity", "inf", "-inf", "+inf"] do
      test "the string #{inspect(text)} is a type error" do
        model = decision_model("number", "In > 1")

        assert {:error, {:type_error, "number"}} =
                 Boxic.DMN.evaluate(model, "Out", %{"In" => unquote(text)})
      end
    end

    test "a non-finite Decimal is a type error" do
      model = decision_model("number", "In > 1")

      for value <- [Decimal.new("NaN"), Decimal.new("Infinity"), Decimal.new("-Infinity")] do
        assert {:error, {:type_error, "number"}} =
                 Boxic.DMN.evaluate(model, "Out", %{"In" => value}),
               inspect(value)
      end
    end

    test "non-finite values are rejected inside typed components too" do
      model =
        load!("""
        <definitions id="defs" name="component" namespace="urn:component">
          <itemDefinition name="Order">
            <itemComponent name="total"><typeRef>number</typeRef></itemComponent>
          </itemDefinition>
          <inputData id="in" name="In"><variable name="In" typeRef="Order"/></inputData>
          <decision id="dec" name="Out">
            <informationRequirement><requiredInput href="#in"/></informationRequirement>
            <literalExpression><text>In.total &gt; 1</text></literalExpression>
          </decision>
        </definitions>
        """)

      assert {:error, {:type_error, "number"}} =
               Boxic.DMN.evaluate(model, "Out", %{"In" => %{"total" => "NaN"}})

      assert {:ok, true} = Boxic.DMN.evaluate(model, "Out", %{"In" => %{"total" => "5"}})
    end

    test "finite strings are still coerced" do
      model = decision_model("number", "In")

      for {text, expected} <- [{"21", "21"}, {"1e3", "1000"}, {"-4.5", "-4.5"}, {" 7", nil}] do
        case expected do
          nil ->
            assert {:error, {:type_error, "number"}} =
                     Boxic.DMN.evaluate(model, "Out", %{"In" => text})

          expected ->
            assert {:ok, value} = Boxic.DMN.evaluate(model, "Out", %{"In" => text})
            assert Decimal.equal?(value, Decimal.new(expected))
        end
      end
    end
  end

  describe "arguments that are not a model, a name, or a context" do
    setup do
      {:ok, model: decision_model("number", "In")}
    end

    test "evaluate/3 returns an error tuple", %{model: model} do
      assert {:error, {:invalid_model, nil}} = Boxic.DMN.evaluate(nil, "Out", %{})
      assert {:error, {:invalid_model, nil}} = Boxic.DMN.evaluate(nil, "Out")
      assert {:error, {:invalid_model, %{}}} = Boxic.DMN.evaluate(%{}, "Out", %{})
      assert {:error, {:invalid_context, nil}} = Boxic.DMN.evaluate(model, "Out", nil)
      assert {:error, {:invalid_context, []}} = Boxic.DMN.evaluate(model, "Out", [])
      assert {:error, {:invalid_context, "In"}} = Boxic.DMN.evaluate(model, "Out", "In")
      assert {:error, {:invalid_decision_name, nil}} = Boxic.DMN.evaluate(model, nil)
      assert {:error, {:invalid_decision_name, :out}} = Boxic.DMN.evaluate(model, :out, %{})
    end

    test "evaluate/4 returns an error tuple", %{model: model} do
      assert {:error, {:invalid_model, nil}} = Boxic.DMN.evaluate(nil, "Out", %{}, [])
      assert {:error, {:invalid_context, nil}} = Boxic.DMN.evaluate(model, "Out", nil, [])
      assert {:error, {:invalid_decision_name, 1}} = Boxic.DMN.evaluate(model, 1, %{}, [])
      assert {:error, {:invalid_options, :opts}} = Boxic.DMN.evaluate(model, "Out", %{}, :opts)
      assert {:error, {:invalid_options, nil}} = Boxic.DMN.evaluate(model, "Out", %{}, nil)
    end

    test "evaluate_service/3 returns an error tuple", %{model: model} do
      assert {:error, {:invalid_model, nil}} = Boxic.DMN.evaluate_service(nil, "S", %{})
      assert {:error, {:invalid_service_name, nil}} = Boxic.DMN.evaluate_service(model, nil, %{})
      assert {:error, {:invalid_arguments, nil}} = Boxic.DMN.evaluate_service(model, "S", nil)
      assert {:error, {:invalid_arguments, "x"}} = Boxic.DMN.evaluate_service(model, "S", "x")

      assert {:error, {:invalid_arguments, [1 | 2]}} =
               Boxic.DMN.evaluate_service(model, "S", [1 | 2])
    end

    test "well-formed calls are unaffected", %{model: model} do
      assert {:ok, value} = Boxic.DMN.evaluate(model, "Out", %{"In" => Decimal.new(3)})
      assert Decimal.equal?(value, Decimal.new(3))
      assert {:ok, _} = Boxic.DMN.evaluate(model, "Out", %{"In" => Decimal.new(3)}, [])

      assert {:error, {:decision_not_found, "Missing"}} =
               Boxic.DMN.evaluate(model, "Missing", %{})

      assert {:error, {:decision_service_not_found, "Missing"}} =
               Boxic.DMN.evaluate_service(model, "Missing", %{})
    end
  end
end
