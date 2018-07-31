defmodule Events.Impl.EtsTree do
  @moduledoc false

  @behaviour Events.Impl

  @table __MODULE__
  @end_of_table :"$end_of_table"

  @impl true
  def child_spec(_) do
    %{
      id: __MODULE__,
      start: {Agent, :start_link, [&create_table/0, [name: __MODULE__]]}
    }
  end

  @impl true
  def attach(handler_id, prefix, module, function, config) do
    if handler_exists?(handler_id) do
      {:error, :already_exists}
    else
      true = :ets.insert(@table, {key_path(prefix), handler_id, prefix, module, function, config})
      :ok
    end
  end

  @impl true
  def detach(handler_id) do
    if handler_exists?(handler_id) do
      :ets.match_delete(@table, {:_, handler_id, :_, :_, :_, :_})
      {:ok, @table}
    else
      {:error, :not_found}
    end
  end

  @impl true
  def list_handlers_for_event(event_name) do
    path = key_path(event_name)
    handlers_for_event(path, :ets.prev(@table, path_before(event_name)), :ets.lookup(@table, path))
    |> strip_keys()
  end


  defp handlers_for_event(_, @end_of_table, acc), do: acc
  defp handlers_for_event(path, key, acc) do
    if String.starts_with?(path, key) do
      handlers_for_event(path, :ets.prev(@table, key), :ets.lookup(@table, key) ++ acc)
    else
      acc
    end
  end

  @impl true
  def list_handlers_by_prefix(event_prefix) do
    path = key_path(event_prefix)
    handlers_with_prefix(path, :ets.next(@table, path_before(event_prefix)), [])
    |> strip_keys()
  end

  defp handlers_with_prefix(_, @end_of_table, acc), do: acc
  defp handlers_with_prefix(path, key, acc) do
    if String.starts_with?(key, path) do
      handlers_with_prefix(path, :ets.next(@table, key), :ets.lookup(@table, key) ++ acc)
    else
      acc
    end
  end

  defp create_table() do
    :ets.new(@table, [:ordered_set, :public, :named_table, read_concurrency: true])
  end

  @spec handler_exists?(Events.handler_id()) :: boolean()
  defp handler_exists?(handler_id) do
    case :ets.match(@table, {:_, handler_id, :_, :_, :_, :_}) do
      [_] ->
        true

      [] ->
        false
    end
  end

  defp key_path([]), do: "*"
  defp key_path(prefix), do: path(prefix) <> "*"

  defp path_after([]), do: "^"
  defp path_after(prefix), do: path(prefix) <> "^"

  defp path_before([]), do: "$"
  defp path_before(prefix), do: path(prefix) <> "$"

  defp path(prefix) do
    "*" <> (Enum.map(prefix, &Atom.to_string/1) |> Enum.join("*"))
  end

  defp strip_keys(entries) do
    Enum.map(entries, fn {_, handler_id, event, m, f, a} ->
      {handler_id, event, m, f, a}
    end)
  end
end
