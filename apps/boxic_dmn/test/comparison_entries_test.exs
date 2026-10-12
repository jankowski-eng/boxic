defmodule Boxic.DMN.ComparisonEntriesTest do
  # A decision table input entry is satisfied only when the FEEL unary test is true (DMN 1.5
  # clause 10.3.2.10, grammar rules 15.a and 15.b). A test that cannot be decided, because the
  # input is null or has no order with the bound, does not satisfy the entry, and it does not
  # abort the decision either.
  use ExUnit.Case, async: true

  defp table(type, entries) do
    rules =
      Enum.map_join(entries, "\n", fn {entry, output} ->
        ~s|<rule><inputEntry><text>#{entry}</text></inputEntry><outputEntry><text>"#{output}"</text></outputEntry></rule>|
      end)

    """
    <definitions id="defs" name="comparisons" namespace="urn:comparisons">
      <inputData id="value" name="Value"><variable name="Value" typeRef="#{type}"/></inputData>
      <decision id="dec" name="Result">
        <variable name="Result"/>
        <informationRequirement><requiredInput href="#value"/></informationRequirement>
        <decisionTable hitPolicy="FIRST">
          <input id="in"><inputExpression typeRef="#{type}"><text>Value</text></inputExpression></input>
          <output id="out"/>
          #{rules}
        </decisionTable>
      </decision>
    </definitions>
    """
  end

  defp result(xml, value) do
    {:ok, model} = Boxic.DMN.load_xml(xml)
    Boxic.DMN.evaluate(model, "Result", %{"Value" => value})
  end

  test "a negated comparison does not match a null input" do
    xml = table("number", [{"&lt; 5", "low"}, {"not(&lt; 5)", "high"}, {"-", "other"}])

    assert {:ok, "other"} = result(xml, nil)
    assert {:ok, "low"} = result(xml, Decimal.new(3))
    assert {:ok, "high"} = result(xml, Decimal.new(7))
  end

  test "a comparison does not match an input that cannot be compared with its bound" do
    xml = table("string", [{"&lt; 5", "low"}, {"not(&lt;= 5)", "high"}, {"-", "other"}])

    assert {:ok, "other"} = result(xml, "abc")
  end

  test "a comparison with a date does not match a number" do
    xml = table("number", [{~s|&gt; date(&quot;2020-01-01&quot;)|, "later"}, {"-", "other"}])

    assert {:ok, "other"} = result(xml, Decimal.new(5))
  end

  test "an entry that compares with null treats a null input as a value" do
    xml = table("number", [{"= null", "none"}, {"!= null", "some"}])

    assert {:ok, "none"} = result(xml, nil)
    assert {:ok, "some"} = result(xml, Decimal.new(5))
  end

  test "!= matches a null input" do
    xml = table("number", [{"!= 3", "not three"}, {"-", "other"}])

    assert {:ok, "not three"} = result(xml, nil)
    assert {:ok, "not three"} = result(xml, Decimal.new(4))
    assert {:ok, "other"} = result(xml, Decimal.new(3))
  end

  test "a list of entries matches when one of them is true" do
    xml = table("number", [{"&lt; 5, = null", "low or none"}, {"-", "other"}])

    assert {:ok, "low or none"} = result(xml, nil)
    assert {:ok, "low or none"} = result(xml, Decimal.new(3))
    assert {:ok, "other"} = result(xml, Decimal.new(7))
  end
end
