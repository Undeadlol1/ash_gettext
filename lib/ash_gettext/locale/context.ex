defmodule AshGettext.Locale.Context do
  @moduledoc """
  Read a locale that was already decided and placed on the action context.

  This is the resolver that makes the whole library testable: run an action with
  `context: %{locale: "ru"}` and the locale is settled — no actor, no database,
  no logging in.

      Ash.read(Post, context: %{locale: "ru"})

  It is generic by construction, so it ships in the library. Both the atom and
  string key are accepted, because a locale that arrives over the wire has often
  been through a JSON round-trip by the time it lands here.
  """

  @behaviour AshGettext.Locale.Resolver

  @impl true
  def resolve(%{locale: locale}) when is_binary(locale), do: locale
  def resolve(%{"locale" => locale}) when is_binary(locale), do: locale
  def resolve(_context), do: nil
end
