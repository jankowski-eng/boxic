defmodule Boxic.FEEL.AST do
  @moduledoc false

  alias Boxic.FEEL.Error

  @unary_operators [:negate, :not]
  @binary_operators [:plus, :minus, :mul, :div, :pow, :eq, :neq, :lt, :lte, :gt, :gte, :and, :or]

  @spec validate(term()) :: :ok | {:error, Error.t()}
  def validate(ast) do
    case validate_node(ast) do
      :ok -> :ok
      {:error, reason} -> {:error, Error.new(:invalid_ast, reason)}
    end
  end

  defp validate_node({:literal, _value}), do: :ok
  defp validate_node({:identifier, name}) when is_binary(name) and name != "", do: :ok

  defp validate_node({:unary, operator, operand}) when operator in @unary_operators,
    do: validate_node(operand)

  defp validate_node({:binary, operator, left, right}) when operator in @binary_operators,
    do: validate_children([left, right])

  defp validate_node({:list, items}) do
    if proper_list?(items), do: validate_children(items), else: invalid_list(items)
  end

  defp validate_node({:context, entries}) do
    cond do
      not proper_list?(entries) ->
        invalid_list(entries)

      not Enum.all?(entries, &match?({name, _value} when is_binary(name), &1)) ->
        entry = Enum.find(entries, &(not match?({name, _value} when is_binary(name), &1)))
        {:error, "invalid context entry: #{inspect(entry)}"}

      true ->
        names = Enum.map(entries, &elem(&1, 0))

        if length(names) == length(Enum.uniq(names)),
          do: validate_children(Enum.map(entries, &elem(&1, 1))),
          else: {:error, "context keys must be unique"}
    end
  end

  defp validate_node({:path, source, name}) when is_binary(name) and name != "",
    do: validate_node(source)

  defp validate_node({:filter, source, predicate}),
    do: validate_children([source, predicate])

  defp validate_node({:range, start_inclusive, end_inclusive, first, last})
       when is_boolean(start_inclusive) and is_boolean(end_inclusive),
       do: validate_children([first, last])

  defp validate_node({:if, condition, then_branch, else_branch}),
    do: validate_children([condition, then_branch, else_branch])

  defp validate_node({:in, value, tests}), do: validate_children([value, tests])

  defp validate_node({:between, value, lower, upper}),
    do: validate_children([value, lower, upper])

  defp validate_node({:instance_of, value, type}) when is_binary(type), do: validate_node(value)

  defp validate_node({:unary_test, operator, operand})
       when operator in [:eq, :neq, :lt, :lte, :gt, :gte],
       do: validate_node(operand)

  defp validate_node({:unary_tests, [_ | _] = tests}) do
    if proper_list?(tests), do: validate_children(tests), else: invalid_list(tests)
  end

  defp validate_node({:sequence, first, last}), do: validate_children([first, last])

  defp validate_node({:for, variable, source, body}) when is_binary(variable) and variable != "",
    do: validate_children([source, body])

  defp validate_node({:for, [_ | _] = bindings, body}) do
    cond do
      not proper_list?(bindings) ->
        invalid_list(bindings)

      not Enum.all?(bindings, &match?({_variable, _source}, &1)) ->
        {:error, "for bindings must be {name, source} pairs"}

      true ->
        variables = Enum.map(bindings, &elem(&1, 0))

        if Enum.all?(variables, &(is_binary(&1) and &1 != "")) and
             length(variables) == length(Enum.uniq(variables)) do
          validate_children(Enum.map(bindings, &elem(&1, 1)) ++ [body])
        else
          {:error, "for bindings must use unique, non-empty names"}
        end
    end
  end

  defp validate_node({:quantifier, kind, variable, source, predicate})
       when kind in [:some, :every] and is_binary(variable) and variable != "",
       do: validate_children([source, predicate])

  defp validate_node({:function, parameters, body}) do
    cond do
      not proper_list?(parameters) ->
        invalid_list(parameters)

      not Enum.all?(parameters, &match?({_name, _type}, &1)) ->
        {:error, "function parameters must be {name, type} pairs"}

      true ->
        names = Enum.map(parameters, &elem(&1, 0))

        if Enum.all?(names, &(is_binary(&1) and &1 != "")) and
             length(names) == length(Enum.uniq(names)) do
          validate_node(body)
        else
          {:error, "function parameters must be unique, non-empty names"}
        end
    end
  end

  defp validate_node({:call, function, arguments}) do
    if proper_list?(arguments) do
      with :ok <- validate_node(function), do: validate_arguments(arguments)
    else
      invalid_list(arguments)
    end
  end

  defp validate_node(ast), do: {:error, "invalid AST node: #{inspect(ast)}"}

  # Only a call takes named arguments.
  defp validate_arguments(arguments) do
    Enum.reduce_while(arguments, :ok, fn
      {:named_arg, name, value}, :ok when is_binary(name) and name != "" ->
        continue_or_halt(validate_node(value))

      argument, :ok ->
        continue_or_halt(validate_node(argument))
    end)
  end

  defp validate_children(nodes) do
    Enum.reduce_while(nodes, :ok, fn node, :ok -> continue_or_halt(validate_node(node)) end)
  end

  defp proper_list?([]), do: true
  defp proper_list?([_ | tail]), do: proper_list?(tail)
  defp proper_list?(_other), do: false

  defp invalid_list(value), do: {:error, "invalid list: #{inspect(value)}"}

  defp continue_or_halt(:ok), do: {:cont, :ok}
  defp continue_or_halt({:error, _reason} = error), do: {:halt, error}
end
