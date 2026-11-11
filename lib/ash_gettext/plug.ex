if Code.ensure_loaded?(Plug.Conn) do
  defmodule AshGettext.Plug do
    @moduledoc """
    Set Gettext's language to the actor's for one request.

    A transport such as AshJsonApi writes some error text without knowing who
    asked. `AshGettext.JsonApi` translates that text into Gettext's current
    language, so the request has to carry the actor's language. Put this after
    the plug that sets the actor:

        plug :set_actor
        plug AshGettext.Plug, domain: MyApp.Shop

    It asks the domain's `locale_resolver` with the actor, the same way actions
    do. With no actor, or a resolver that returns `nil`, the language is left
    alone. The language that was set before is put back when the reply is
    sent, so a connection that serves several requests does not carry one
    reader's language into the next.
    """

    @behaviour Plug

    @impl true
    def init(opts), do: Keyword.fetch!(opts, :domain)

    @impl true
    def call(conn, domain) do
      case AshGettext.Info.language(domain, Ash.PlugHelpers.get_actor(conn)) do
        {backend, locale} ->
          previous = Gettext.get_locale(backend)
          Gettext.put_locale(backend, locale)

          Plug.Conn.register_before_send(conn, fn conn ->
            Gettext.put_locale(backend, previous)
            conn
          end)

        nil ->
          conn
      end
    end
  end
end
