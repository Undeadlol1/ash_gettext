defmodule AshGettext.AshMessages do
  @messages [
    {Ash.Error.Changes.Required, "is required"},
    {Ash.Error.Changes.InvalidAttribute, "is invalid"},
    {Ash.Error.Changes.InvalidArgument, "is invalid"},
    {Ash.Error.Query.Required, "is required"},
    {Ash.Error.Query.InvalidArgument, "is invalid"},
    {Ash.Error.Query.NotFound, "could not be found"},
    {Ash.Error.Forbidden.Policy, "You are not allowed to do this"}
  ]

  @replies [
    {"required", "is required"},
    {"not_found", "could not be found"},
    {"forbidden", "You are not allowed to do this"},
    {"invalid_primary_key", "invalid primary key provided"},
    {"invalid_keyset", "invalid keyset"},
    {"no_such_input", "no such input"},
    {"forbidden_field", "forbidden field"}
  ]

  @sentences [
    "has already been taken",
    "must match %{match}",
    "Something went wrong. Error id: %{id}",
    "invalid filter value",
    "Invalid filter value %{value}",
    "Invalid value provided as a keyset for %{key}: %{value}"
  ]

  @moduledoc """
  The sentences shown for Ash's own errors when they carry no message.

  Ash builds the text of these errors from code names, so each one gets a
  written English sentence here. It is the msgid, and `mix gettext.extract`
  finds it for every domain with a `gettext` block. The translated sentence
  goes into the error's own text field (`message`, or `custom_message` for a
  policy), so the error stays Ash's own struct.

  `Ash.Error.Changes.Required` has no text field. Its sentence goes into its
  `vars`, under `:translation`, next to whatever values the app put there.
  Every transport passes `vars` on (JSON:API as `meta`), so the reader's
  sentence travels with the error.

  | Error | Sentence |
  | --- | --- |
  #{for {module, msgid} <- @messages, into: "", do: "| `#{inspect(module)}` | #{msgid} |\n"}

  An error that already has a message keeps it; that message is its msgid.
  A policy with its own message keeps that message too. Its msgid is kept in
  `vars[:policy_message]`, so a JSON:API or GraphQL reply can show it.

  ## Sentences a transport writes

  AshJsonApi and AshGraphql write the text of some errors themselves, after
  every Ash error handler has run. `AshGettext.JsonApi` and
  `AshGettext.Graphql` translate those in the reply. Each error code has a
  written sentence here too, so it is in your template:

  | Code | Sentence |
  | --- | --- |
  #{for {code, msgid} <- @replies, into: "", do: "| `#{code}` | #{msgid} |\n"}

  These have no code of their own:

  #{for msgid <- @sentences, into: "", do: "- #{msgid}\n"}
  """

  @doc "Every `{error_module, msgid}` pair."
  @spec messages() :: [{module(), String.t()}]
  def messages, do: @messages

  @doc "Every msgid, each once."
  @spec msgids() :: [String.t()]
  def msgids,
    do:
      (@messages ++ @replies) |> Enum.map(&elem(&1, 1)) |> Enum.concat(@sentences) |> Enum.uniq()

  @doc """
  Every sentence Ash marks as translatable: "must be present", "must match the
  pattern %{regex}" and the rest.

  They are read from Ash itself, so a later Ash release that adds a sentence
  adds it here too: from the template Ash ships (`priv/gettext/ash.pot`) and
  from each `error_message("...")` in Ash's source, which the template can
  lag behind.
  """
  @spec ash_sentences() :: [String.t()]
  def ash_sentences, do: Enum.uniq(shipped_template() ++ marked_in_source())

  defp shipped_template do
    case Expo.PO.parse_file(Application.app_dir(:ash, "priv/gettext/ash.pot")) do
      {:ok, template} ->
        for %{msgid: msgid} <- template.messages, do: IO.iodata_to_binary(msgid)

      {:error, _no_template} ->
        []
    end
  end

  @marked ~r/error_message\(\s*"((?:[^"\\]|\\.)*)"/

  defp marked_in_source do
    for file <- Path.wildcard(Path.join(ash_source(), "**/*.ex")),
        [sentence] <- Regex.scan(@marked, File.read!(file), capture: :all_but_first),
        sentence =~ ~r/\p{L}/u,
        do: Macro.unescape_string(sentence)
  end

  defp ash_source, do: Ash.module_info(:compile)[:source] |> List.to_string() |> Path.dirname()

  @doc """
  The msgid for a reply with this error `code`, or `nil` when none is listed.
  """
  @spec reply_msgid(term()) :: String.t() | nil
  def reply_msgid(code) do
    Enum.find_value(@replies, fn {listed, msgid} -> listed == code && msgid end)
  end

  @doc """
  The msgid for `error`, or `nil` when it already has a message or is not listed.
  """
  @spec msgid(term()) :: String.t() | nil
  def msgid(%{message: message}) when is_binary(message), do: nil

  def msgid(%Ash.Error.Forbidden.Policy{custom_message: custom, vars: vars})
      when is_binary(custom),
      do: Keyword.get(List.wrap(vars), :policy_message, custom)

  def msgid(%module{}) do
    Enum.find_value(@messages, fn {listed, msgid} -> listed == module && msgid end)
  end

  def msgid(_other), do: nil
end
