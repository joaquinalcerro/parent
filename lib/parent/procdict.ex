defmodule Parent.Procdict do
  @moduledoc false
  alias Parent.Functional
  use Parent.PublicTypes

  @spec initialize() :: :ok
  def initialize() do
    if Process.get(__MODULE__) != nil, do: raise("#{__MODULE__} is already initialized")
    Process.put(__MODULE__, Functional.initialize())
    :ok
  end

  @spec start_child(in_child_spec) :: on_start_child
  def start_child(child_spec) do
    with result <- Functional.start_child(state(), child_spec),
         {:ok, pid, state} <- result do
      store(state)
      {:ok, pid}
    end
  end

  @spec shutdown_child(name) :: :ok
  def shutdown_child(child_name) do
    state = Functional.shutdown_child(state(), child_name)
    store(state)
    :ok
  end

  @spec shutdown_all(term) :: :ok
  def shutdown_all(reason) do
    state = Functional.shutdown_all(state(), reason)
    store(state)
    :ok
  end

  @spec handle_message(term) :: Functional.on_handle_message()
  def handle_message(message) do
    with {result, state} <- Functional.handle_message(state(), message) do
      store(state)
      result
    end
  end

  @spec entries :: entries
  def entries(), do: Functional.entries(state())

  @spec size() :: non_neg_integer
  def size(), do: Functional.size(state())

  @spec name(pid) :: {:ok, name} | pid
  def name(pid), do: Functional.name(state(), pid)

  @spec pid(name) :: {:ok, pid} | name
  def pid(name), do: Functional.pid(state(), name)

  @spec state() :: Functional.t()
  defp state() do
    state = Process.get(__MODULE__)
    if is_nil(state), do: raise("#{__MODULE__} is not initialized")
    state
  end

  defp store(state), do: Process.put(__MODULE__, state)
end
