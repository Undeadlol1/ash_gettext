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

  @written (@messages ++ @replies)
           |> Enum.map(&elem(&1, 1))
           |> Enum.concat(@sentences)
           |> Enum.uniq()

  # The path is written out: a dependency sits there in every app that has
  # one, whatever machine compiled it.
  @located (
             lines = __ENV__.file |> File.read!() |> String.split("\n")

             for msgid <- @written do
               %{
                 msgid: msgid,
                 path: "deps/ash_gettext/lib/ash_gettext/ash_messages.ex",
                 line: Enum.find_index(lines, &String.contains?(&1, inspect(msgid))) + 1
               }
             end
           )

  @typedoc "A sentence and the file and line it is written at."
  @type located :: %{msgid: String.t(), path: String.t(), line: pos_integer()}

  @doc "Every built-in sentence with the place it is written at: here or in Ash."
  @spec located() :: [located()]
  def located do
    in_code = marked_in_source()
    found = MapSet.new(in_code, & &1.msgid)

    @located ++ in_code ++ Enum.reject(shipped_template(), &(&1.msgid in found))
  end

  @doc "Every `{error_module, msgid}` pair."
  @spec messages() :: [{module(), String.t()}]
  def messages, do: @messages

  @doc "Every msgid, each once."
  @spec msgids() :: [String.t()]
  def msgids, do: @written

  @doc """
  Every sentence Ash marks as translatable: "must be present", "must match the
  pattern %{regex}" and the rest.

  They are read from Ash itself, so a later Ash release that adds a sentence
  adds it here too: from the template Ash ships (`priv/gettext/ash.pot`) and
  from each `error_message("...")` in Ash's source, which the template can
  lag behind.
  """
  @spec ash_sentences() :: [String.t()]
  def ash_sentences,
    do: (shipped_template() ++ marked_in_source()) |> Enum.map(& &1.msgid) |> Enum.uniq()

  defp shipped_template do
    path = Path.expand("../priv/gettext/ash.pot", ash_source())

    case Expo.PO.parse_file(path) do
      {:ok, template} ->
        for message <- template.messages do
          %{
            msgid: IO.iodata_to_binary(message.msgid),
            path: path,
            line: Expo.Message.source_line_number(message, :msgid)
          }
        end

      {:error, _no_template} ->
        []
    end
  end

  @marked ~r/error_message\(\s*"((?:[^"\\]|\\.)*)"/

  defp marked_in_source do
    for path <- Path.wildcard(Path.join(ash_source(), "**/*.ex")),
        source = File.read!(path),
        [{start, length}] <- Regex.scan(@marked, source, capture: :all_but_first, return: :index),
        sentence = binary_part(source, start, length),
        sentence =~ ~r/\p{L}/u do
      %{
        msgid: Macro.unescape_string(sentence),
        path: path,
        line: length(:binary.matches(binary_part(source, 0, start), "\n")) + 1
      }
    end
  end

  defp ash_source, do: Path.join(Mix.Project.deps_paths()[:ash], "lib")

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
