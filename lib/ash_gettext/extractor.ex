defmodule AshGettext.Extractor do
  @moduledoc """
  Find the translatable `message:` strings that plain gettext extraction misses.

  `mix gettext.extract` works by compiling the app and recording every call to a
  gettext macro. Ash's error messages are not gettext calls — they are `message:`
  options written inside resource DSL blocks and validation modules:

      identity :one_per_type, [:user_id, :streak_type] do
        message "A streak of this type already exists for this user"
      end

      {:error, field: :weight, message: "must be at least %{min} kg"}

  Nothing in that is a macro gettext knows about, so those strings never reach a
  `.pot` file and never get translated. The usual workaround is to wrap each one
  in `Gettext.Macros.dgettext_noop/2` by hand — which is churn across every call
  site, and something a reviewer has to remember forever.

  This module reads the source instead. It parses each file and collects every
  `message:` whose value is a plain string, so no call site has to change and
  forgetting is not possible.

  Interpolated messages are skipped on purpose: `message: "Bad frequency:
  \#{inspect(value)}"` cannot be a msgid, because the msgid has to be a constant
  the catalog can key on. Those are reported separately by `find_messages/1` so they can
  be found and rewritten with gettext bindings rather than silently ignored.

  Pure: give it source text, get back results. No compilation, no app state.
  """

  @type reference_entry :: %{path: String.t(), line: pos_integer()}
  @type message :: %{
          required(:msgid) => String.t(),
          required(:references) => [reference_entry()],
          optional(:comments) => [String.t()]
        }
  @type interpolated :: %{path: String.t(), line: pos_integer()}
  @type find_result :: %{messages: [message()], interpolated: [interpolated()]}

  @doc """
  Scan `sources` — a list of `{path, contents}` — for translatable messages.

  Returns the extractable msgids with every place they appear, and separately
  the interpolated messages that cannot become msgids as written.
  """
  @spec find_messages([{String.t(), String.t()}]) :: find_result()
  def find_messages(sources) do
    found = Enum.flat_map(sources, fn {path, contents} -> read_source(path, contents) end)

    %{
      messages: found |> Enum.filter(&(&1.kind == :literal)) |> group_by_msgid(),
      interpolated:
        found
        |> Enum.filter(&(&1.kind == :interpolated))
        |> Enum.map(&%{path: &1.path, line: &1.line})
        |> Enum.sort_by(&{&1.path, &1.line})
    }
  end

  @doc """
  The messages a list of resources contribute: every public attribute's name
  (`AshGettext.attribute_msgid/1`) and, for enum attributes (also
  `{:array, enum}`), every value's label and description.

  Each message carries a `comments` entry like `MyApp.Parcel.weight` in place of
  file references. Pure: reads compiled resource modules only.
  """
  @spec resource_messages([module()]) :: [message()]
  def resource_messages(resources) do
    resources
    |> Enum.flat_map(fn resource ->
      resource
      |> Ash.Resource.Info.public_attributes()
      |> Enum.flat_map(&attribute_messages(resource, &1))
    end)
    |> merge()
  end

  @doc """
  Combine message lists, deduplicating by msgid and merging references and
  comments. Sorted by msgid, so the output is deterministic.
  """
  @spec merge([[message()]]) :: [message()]
  def merge(message_lists) do
    message_lists
    |> List.flatten()
    |> Enum.group_by(& &1.msgid)
    |> Enum.map(fn {msgid, group} ->
      %{
        msgid: msgid,
        references:
          group
          |> Enum.flat_map(& &1.references)
          |> Enum.uniq()
          |> Enum.sort_by(&{&1.path, &1.line}),
        comments:
          group |> Enum.flat_map(&Map.get(&1, :comments, [])) |> Enum.uniq() |> Enum.sort()
      }
    end)
    |> Enum.sort_by(& &1.msgid)
  end

  defp attribute_messages(resource, %{name: name, type: type}) do
    source = "#{inspect(resource)}.#{name}"
    labels = type |> enum_of() |> enum_texts()

    for msgid <- [AshGettext.attribute_msgid(name) | labels] do
      %{msgid: msgid, references: [], comments: [source]}
    end
  end

  defp enum_of({:array, type}), do: enum_of(type)

  defp enum_of(type) when is_atom(type) do
    if Code.ensure_loaded?(type) and function_exported?(type, :values, 0) and
         function_exported?(type, :label, 1) and function_exported?(type, :description, 1),
       do: type
  end

  defp enum_of(_type), do: nil

  defp enum_texts(nil), do: []

  defp enum_texts(enum) do
    for value <- enum.values(),
        text <- [enum.label(value), enum.description(value)],
        is_binary(text),
        do: text
  end

  @doc """
  Render extracted messages as the contents of a `.pot` file.
  """
  @spec to_template([message()]) :: String.t()
  def to_template(messages) do
    Enum.join([template_header() | Enum.map(messages, &entry/1)], "\n")
  end

  defp read_source(path, contents) do
    case parse(contents) do
      {:ok, ast} -> find_message_nodes(ast, path)
      :error -> []
    end
  end

  # `literal_encoder` wraps every literal in a block that carries line metadata.
  # Without it a string in a keyword list is a bare binary with nowhere to hang a
  # source reference, and a `.pot` entry without a reference is much harder to act on.
  defp parse(contents) do
    contents
    |> Code.string_to_quoted(
      literal_encoder: &{:ok, {:__block__, &2, [&1]}},
      token_metadata: true,
      unescape: false,
      emit_warnings: false
    )
    |> case do
      {:ok, ast} -> {:ok, ast}
      {:error, _reason} -> :error
    end
  end

  defp find_message_nodes(ast, path) do
    {_ast, found} = Macro.prewalk(ast, [], &find_message_nodes(&1, &2, path))
    Enum.reverse(found)
  end

  # `message: "..."` as a keyword pair, wherever it appears.
  defp find_message_nodes({{:__block__, _key_meta, [:message]}, value} = node, found, path) do
    {node, prepend(message_kind(value, path), found)}
  end

  # `message "..."` as a DSL call, the form Ash's identity and validation blocks use.
  defp find_message_nodes({:message, _meta, [value]} = node, found, path) do
    {node, prepend(message_kind(value, path), found)}
  end

  defp find_message_nodes(node, found, _path), do: {node, found}

  defp prepend(nil, found), do: found
  defp prepend(entry, found), do: [entry | found]

  defp message_kind({:__block__, meta, [value]}, path) when is_binary(value) do
    %{kind: :literal, msgid: value, path: path, line: meta[:line] || 0}
  end

  # An interpolated string parses as a `<<>>` construction, never a binary.
  defp message_kind({:<<>>, meta, _parts}, path) do
    %{kind: :interpolated, path: path, line: meta[:line] || 0}
  end

  defp message_kind(_other, _path), do: nil

  defp group_by_msgid(entries) do
    entries
    |> Enum.group_by(& &1.msgid)
    |> Enum.map(fn {msgid, occurrences} ->
      %{
        msgid: msgid,
        references:
          occurrences
          |> Enum.map(&%{path: &1.path, line: &1.line})
          |> Enum.uniq()
          |> Enum.sort_by(&{&1.path, &1.line})
      }
    end)
    |> Enum.sort_by(& &1.msgid)
  end

  defp template_header do
    """
    ## This file is a PO Template file.
    ##
    ## Generated by `mix ash_gettext.extract` from Ash `message:` options, which
    ## plain `mix gettext.extract` cannot see. Do not edit by hand — re-run the
    ## task instead. Translations belong in the matching `.po` files.
    msgid ""
    msgstr ""
    """
  end

  # A reference deliberately carries no line number: the template is compared
  # byte for byte against a fresh extraction, so any edit above a `message:`
  # would move a line and be reported as a message change.
  defp entry(%{msgid: msgid, references: references} = message) do
    comment_lines = message |> Map.get(:comments, []) |> Enum.map(&"#. #{&1}")

    file_lines =
      references |> Enum.map(& &1.path) |> Enum.uniq() |> Enum.map(&"#: #{&1}")

    Enum.join(comment_lines ++ file_lines, "\n") <>
      """

      msgid "#{escape(msgid)}"
      msgstr ""
      """
  end

  defp escape(string) do
    string
    |> String.replace("\\", "\\\\")
    |> String.replace("\"", "\\\"")
    |> String.replace("\n", "\\n")
  end
end
