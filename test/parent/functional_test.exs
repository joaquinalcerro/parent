defmodule Parent.FunctionalTest do
  use ExUnit.Case, async: true
  use ExUnitProperties
  alias Parent.{Functional, Registry}

  property "started processes are registered" do
    check all child_specs <- child_specs(successful_child_spec()) do
      initial_data = %{registry: Functional.initialize(), children: []}

      reducer = fn child_spec, data ->
        assert {:ok, pid, registry} = Functional.start_child(data.registry, child_spec)
        %{data | registry: registry, children: [%{id: id(child_spec), pid: pid} | data.children]}
      end

      data = Enum.reduce(child_specs, initial_data, reducer)

      Enum.each(
        data.children,
        &assert(Registry.name(data.registry, &1.pid) == {:ok, &1.id})
      )
    end
  end

  property "processes which fail to start are not registered" do
    check all child_specs <- child_specs(failed_child_spec()) do
      registry = Functional.initialize()

      Enum.each(
        child_specs,
        &assert(Functional.start_child(registry, &1) == {:error, :not_started})
      )
    end
  end

  property "handling of exit messages" do
    check all exit_data <- exit_data() do
      registry =
        Enum.reduce(exit_data.starts, Functional.initialize(), fn child_spec, registry ->
          {:ok, _pid, registry} = Functional.start_child(registry, child_spec)
          registry
        end)

      Enum.reduce(exit_data.stops, registry, fn child_spec, registry ->
        {:ok, pid} = Registry.pid(registry, id(child_spec))
        Agent.stop(pid, :shutdown)
        assert_receive {:EXIT, ^pid, reason} = message

        assert {{:EXIT, ^pid, name, ^reason}, new_registry} =
                 Functional.handle_message(registry, message)

        assert name == id(child_spec)

        assert Registry.size(new_registry) == Registry.size(registry) - 1
        assert Registry.pid(new_registry, id(child_spec)) == :error
        assert Registry.name(new_registry, pid) == :error

        new_registry
      end)
    end
  end

  property "handling of other messages" do
    check all message <- one_of([term(), constant({:EXIT, self(), :normal})]) do
      registry = Functional.initialize()
      assert Functional.handle_message(registry, message) == :error
    end
  end

  property "shutting down children" do
    check all exit_data <- exit_data(), max_runs: 5 do
      registry =
        Enum.reduce(exit_data.starts, Functional.initialize(), fn child_spec, registry ->
          {:ok, _pid, registry} = Functional.start_child(registry, child_spec)
          registry
        end)

      Enum.reduce(exit_data.stops, registry, fn child_spec, registry ->
        {:ok, pid} = Registry.pid(registry, id(child_spec))
        new_registry = Functional.shutdown_child(registry, id(child_spec))
        refute_receive {:EXIT, ^pid, _reason}

        assert Registry.size(new_registry) == Registry.size(registry) - 1
        assert Registry.pid(new_registry, id(child_spec)) == :error
        assert Registry.name(new_registry, pid) == :error

        new_registry
      end)
    end
  end

  defp child_specs(child_spec) do
    child_spec
    |> list_of()
    |> nonempty()
    |> bind(fn specs -> specs |> Enum.uniq_by(&id/1) |> constant() end)
  end

  defp id(%{id: id}), do: id
  defp id({_mod, arg}), do: arg
  defp id(mod) when is_atom(mod), do: nil

  defp successful_child_spec() do
    bind(
      id(),
      &one_of([
        fixed_map(%{id: constant(&1), start: successful_start()}),
        constant({__MODULE__, &1}),
        constant(__MODULE__)
      ])
    )
  end

  defp failed_child_spec() do
    bind(id(), &fixed_map(%{id: constant(&1), start: constant({__MODULE__, :test_start, []})}))
  end

  defp id(), do: StreamData.scale(term(), fn _size -> 2 end)

  @doc false
  def child_spec(arg), do: %{id: arg, start: fn -> Agent.start_link(fn -> :ok end) end}

  defp successful_start() do
    one_of([
      constant({Agent, :start_link, [fn -> :ok end]}),
      constant(fn -> Agent.start_link(fn -> :ok end) end)
    ])
  end

  @doc false
  def test_start(), do: {:error, :not_started}

  defp exit_data() do
    bind(
      child_specs(successful_child_spec()),
      &fixed_map(%{
        starts: constant(&1),
        stops: bind(nonempty(list_of(member_of(&1))), fn stops -> constant(Enum.uniq(stops)) end)
      })
    )
  end
end