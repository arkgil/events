defmodule Telemetry do
  @moduledoc """
  `Telemetry` allows to attach functions to be called when events are emitted

  Note that all subscribed functions are called in the process which emits the event.
  """

  require Logger

  @callback_mod Telemetry.Impl.Ets

  @type handler_id :: term()
  @type event_name :: [atom()]
  @type event_value :: number()
  @type event_metadata :: map()
  @type event_prefix :: [atom()]

  @doc """
  Attaches a handler to the event prefix.

  `handler_id` must be unique, if another handler with the same ID already exists the
  `{:error, :already_exists}` tuple is returned.

  When events with `event_prefix` are emitted, function `function` in module `module` will be
  called with three arguments:
  * the exact event name (see `execute/3`)
  * the event value (see `execute/3`)
  * the event metadata (see `execute/3`)
  * the handler configuration, `config`, or `nil` if one wasn't provided

  If the function fails (raises, exits or throws) then the handler is removed.
  """
  @spec attach(handler_id, event_prefix, module, function :: atom) ::
          :ok | {:error, :already_exists}
  @spec attach(handler_id, event_prefix, module, function :: atom, config :: term) ::
          :ok | {:error, :already_exists}
  def attach(handler_id, event_prefix, module, function, config \\ nil) do
    assert_event_prefix(event_prefix)
    @callback_mod.attach(handler_id, event_prefix, module, function, config)
  end

  @doc """
  Removes existing handler.

  If the handler with given ID doesn't exist, `{:error, :not_found}` is returned.
  """
  @spec detach(handler_id) :: :ok | {:error, :not_found}
  defdelegate detach(handler_id), to: @callback_mod

  @doc """
  Emits an event, executing handlers attached to all of its prefixes.

  Note that you should not rely on the order in which handlers are invoked.
  """
  @spec execute(event_name, event_value) :: :ok
  @spec execute(event_name, event_value, event_metadata) :: :ok
  def execute(event_name, value, metadata \\ %{}, callback_mod \\ @callback_mod)
      when is_number(value) and is_map(metadata) do
    handlers = callback_mod.list_handlers_for_event(event_name)

    for {handler_id, _, module, function, config} <- handlers do
      try do
        apply(module, function, [event_name, value, metadata, config])
      catch
        class, reason ->
          detach(handler_id)

          stacktrace = System.stacktrace()

          Logger.error(
            "Handler #{inspect(module)}.#{function} with ID #{inspect(handler_id)} " <>
              "has failed and has been detached\n" <> Exception.format(class, reason, stacktrace)
          )
      end
    end
  end

  @doc """
  Returns all handlers attached to events with given prefix.

  Note that you can list all handlers by feeding this function an empty list.
  """
  @spec list_handlers(event_prefix) ::
          {handler_id, event_prefix, module, function :: atom, config :: map}
  def list_handlers(event_prefix) do
    assert_event_prefix(event_prefix)

    @callback_mod.list_handlers_by_prefix(event_prefix)
  end

  @doc false
  defdelegate child_spec(term), to: @callback_mod

  @spec assert_event_prefix(term()) :: :ok | no_return
  defp assert_event_prefix(list) when is_list(list) do
    if Enum.all?(list, &is_atom/1) do
      :ok
    else
      raise ArgumentError, "Expected event prefix to be a list of atoms"
    end
  end

  defp assert_event_prefix(_) do
    raise ArgumentError, "Expected event prefix to be a list of atoms"
  end
end
