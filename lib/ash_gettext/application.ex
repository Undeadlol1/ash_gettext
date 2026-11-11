defmodule AshGettext.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    if Code.ensure_loaded?(AshGettext.JsonApi), do: AshGettext.JsonApi.remember_request_actors()
    if Code.ensure_loaded?(AshGettext.Graphql), do: AshGettext.Graphql.remember_operations()

    Supervisor.start_link([], strategy: :one_for_one, name: AshGettext.Supervisor)
  end
end
