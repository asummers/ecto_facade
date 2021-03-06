defmodule EctoFacade.TestAdapter do
  @behaviour Ecto.Adapter

  alias Ecto.Migration.SchemaMigration

  defmacro __before_compile__(_opts), do: :ok

  def ensure_all_started(_, _) do
    {:ok, []}
  end

  def child_spec(_repo, opts) do
    :ecto_facade = opts[:otp_app]
    "user" = opts[:username]
    "pass" = opts[:password]
    "hello" = opts[:database]
    "local" = opts[:hostname]

    Supervisor.Spec.worker(Task, [fn -> :timer.sleep(:infinity) end])
  end

  ## Types

  def loaders(:binary_id, type), do: [Ecto.UUID, type]
  def loaders(_primitive, type), do: [type]

  def dumpers(:binary_id, type), do: [type, Ecto.UUID]
  def dumpers(_primitive, type), do: [type]

  def autogenerate(:id), do: nil
  def autogenerate(:embed_id), do: Ecto.UUID.autogenerate()
  def autogenerate(:binary_id), do: Ecto.UUID.autogenerate()

  ## Queryable

  def prepare(operation, query), do: {:nocache, {operation, query}}

  def execute(_repo, _, {:nocache, {:all, %{select: %{fields: [_ | _] = fields}}}}, _, _) do
    # Pad nil values after first
    values = List.duplicate(nil, length(fields) - 1)
    Process.get(:test_repo_all_results, {1, [[1 | values]]})
  end

  def execute(_repo, _, {:nocache, {:all, %{select: %{fields: []}}}}, _, _) do
    Process.get(:test_repo_all_results, {1, [[]]})
  end

  def execute(
        _repo,
        _meta,
        {:nocache, {:delete_all, %{from: {_, SchemaMigration}}}},
        [version],
        _
      ) do
    Process.put(:migrated_versions, List.delete(migrated_versions(), version))
    {1, nil}
  end

  def execute(_repo, meta, {:nocache, {op, %{from: {source, _}}}}, _params, _opts) do
    send(test_process(), {op, {meta.prefix, source}})
    {1, nil}
  end

  def stream(repo, meta, prepared, params, opts) do
    Stream.map([:execute], fn :execute ->
      send(test_process(), :stream_execute)
      execute(repo, meta, prepared, params, opts)
    end)
  end

  ## Schema

  def insert_all(_repo, %{source: source}, _header, rows, _on_conflict, _returning, _opts) do
    send(test_process(), {:insert_all, source, rows})
    {1, nil}
  end

  def insert(_repo, %{source: {nil, "schema_migrations"}}, val, _, _, _) do
    version = Keyword.fetch!(val, :version)
    Process.put(:migrated_versions, [version | migrated_versions()])
    {:ok, []}
  end

  def insert(_repo, %{context: nil, source: source}, _fields, _on_conflict, return, _opts),
    do: send(test_process(), {:insert, source}) && {:ok, Enum.zip(return, 1..length(return))}

  def insert(_repo, %{context: {:invalid, _} = res}, _fields, _on_conflict, _return, _opts),
    do: res

  # Notice the list of changes is never empty.
  def update(_repo, %{context: nil, source: source}, [_ | _], _filters, return, _opts),
    do: send(test_process(), {:update, source}) && {:ok, Enum.zip(return, 1..length(return))}

  def update(_repo, %{context: {:invalid, _} = res}, [_ | _], _filters, _return, _opts), do: res

  def delete(_repo, meta, _filter, _opts),
    do: send(test_process(), {:delete, meta.source}) && {:ok, []}

  ## Transactions

  def transaction(_repo, _opts, fun) do
    # Makes transactions "trackable" in tests
    send(test_process(), {:transaction, fun})

    try do
      {:ok, fun.()}
    catch
      :throw, {:ecto_rollback, value} ->
        {:error, value}
    end
  end

  def rollback(_repo, value) do
    send(test_process(), {:rollback, value})
    throw({:ecto_rollback, value})
  end

  ## Migrations

  def lock_for_migrations(_repo, _query, _opts, fun) do
    send(test_process(), {:lock_for_migrations, fun})
    fun.(migrated_versions())
  end

  def execute_ddl(_repo, command, _) do
    Process.put(:last_command, command)
    :ok
  end

  defp migrated_versions do
    Process.get(:migrated_versions, [])
  end

  def supports_ddl_transaction? do
    get_config(:supports_ddl_transaction?, false)
  end

  defp test_process do
    get_config(:test_process, self())
  end

  defp get_config(name, default) do
    :ecto_facade
    |> Application.get_env(__MODULE__, [])
    |> Keyword.get(name, default)
  end
end

Application.put_env(:ecto_facade, EctoFacade.TestRepo, user: "invalid")

defmodule EctoFacade.TestRepo do
  use Ecto.Repo, otp_app: :ecto_facade, adapter: EctoFacade.TestAdapter

  def init(type, opts) do
    opts = [url: "ecto://user:pass@local/hello"] ++ opts
    opts[:parent] && send(opts[:parent], {__MODULE__, type, opts})
    {:ok, opts}
  end
end

EctoFacade.TestRepo.start_link()
