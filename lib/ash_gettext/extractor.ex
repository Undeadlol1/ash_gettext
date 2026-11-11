defmodule AshGettext.Extractor do
  @moduledoc """
  Shows every text AshGettext translates to `mix gettext.extract`.

  `mix gettext.extract` compiles the app and records each Gettext macro it
  meets. The texts AshGettext translates are plain strings, not macro calls:
  enum labels, attribute labels, `message:` options and the sentences for
  Ash's own errors. So while the app compiles, `AshGettext.Enum` and
  `AshGettext.Domain` hand each one to `Gettext.Macros.dgettext_noop_with_backend/3`
  in the app's own modules, with the backend and text domain the lookups use.

  A validation or change module a resource uses is read from its source file:
  every `message:` whose value is a plain string is found there. An
  interpolated message (`message: "too heavy: \#{weight}"`) cannot be a msgid,
  so it is reported as a compile warning instead.
  """

  @type reference_entry :: %{path: String.t(), line: pos_integer()}
  @type message :: %{msgid: String.t(), references: [reference_entry()]}
  @type interpolated :: %{path: String.t(), line: pos_integer()}
  @type find_result :: %{messages: [message()], interpolated: [interpolated()]}

  @doc """
  Marks each text for `mix gettext.extract`, as if `env`'s module had called
  `Gettext.Macros.dgettext_noop_with_backend(backend, text_domain, text)`.
  Does nothing unless Gettext is extracting.
  """
  @spec mark(Macro.Env.t(), module(), String.t(), [String.t()]) :: :ok
  def mark(env, backend, text_domain, texts) do
    if Gettext.Extractor.extracting?() do
      calls =
        for text <- Enum.uniq(texts) do
          quote do
            Gettext.Macros.dgettext_noop_with_backend(
              unquote(backend),
              unquote(text_domain),
              unquote(text)
            )
          end
        end

      Code.eval_quoted({:__block__, [], [quote(do: require(Gettext.Macros)) | calls]}, [], env)
    end

    :ok
  end

  @doc """
  The texts a resource shows: its written attribute labels and, with
  `messages?`, every literal `message` in its DSL and in the app's own
  validation, change, preparation, generic-action run, manual-action and calculation modules it uses.
  """
  @spec resource_texts(module(), boolean()) :: [String.t()]
  def resource_texts(resource, messages?) do
    labels = for {_attribute, text} <- AshGettext.Info.attribute_labels(resource), do: text

    if messages? do
      {messages, modules} = walk(dsl_entities(resource), {[], []})
      labels ++ messages ++ Enum.flat_map(Enum.uniq(modules), &module_messages/1)
    else
      labels
    end
  end

  defp dsl_entities(resource) do
    for {path, %{entities: entities}} when is_list(path) <- resource.spark_dsl_config(),
        path != [:gettext],
        do: entities
  end

  # Any `message` (a policy's is `error_message`) holding a string, and any `{module, opts}` implementing a
  # validation, change, preparation, run, manual action or calculation, wherever the DSL nests it.
  defp walk({key, text}, {messages, modules})
       when key in [:message, :error_message] and is_binary(text),
       do: {[text | messages], modules}

  defp walk({key, {module, opts}}, {messages, modules})
       when key in [:validation, :change, :preparation, :run, :manual, :calculation] and
              is_atom(module),
       do: walk(opts, {messages, [module | modules]})

  defp walk(%_{} = struct, acc), do: walk(Map.from_struct(struct), acc)
  defp walk(map, acc) when is_map(map), do: walk(Map.to_list(map), acc)
  defp walk(list, acc) when is_list(list), do: Enum.reduce(list, acc, &walk/2)
  defp walk(tuple, acc) when is_tuple(tuple), do: walk(Tuple.to_list(tuple), acc)
  defp walk(_other, acc), do: acc

  # Anything but third-party deps, so sibling umbrella and path-dep apps count.
  defp module_messages(module) do
    with {:module, ^module} <- Code.ensure_compiled(module),
         source when is_list(source) <- module.module_info(:compile)[:source],
         path = List.to_string(source),
         true <- app_source?(path),
         {:ok, contents} <- File.read(path) do
      result = find_messages([{path, contents}])
      Enum.each(result.interpolated, &warn_interpolated/1)
      Enum.map(result.messages, & &1.msgid)
    else
      _not_the_apps -> []
    end
  end

  defp app_source?(path),
    do: not String.starts_with?(path, Mix.Project.deps_path() <> "/")

  defp warn_interpolated(%{path: path, line: line}) do
    IO.warn(
      "this interpolated message cannot be a msgid, so it is not translated. " <>
        ~s|Write a constant message and pass the varying part as vars, e.g. message: "must be at most %{max}", vars: [max: max].|,
      file: path,
      line: line
    )
  end

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
end
