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
  @type located :: %{msgid: String.t(), path: String.t(), line: non_neg_integer()}

  @doc """
  Marks each text for `mix gettext.extract`, as if `env`'s module had called
  `Gettext.Macros.dgettext_noop_with_backend(backend, text_domain, text)`.
  A text given as a `t:located/0` is referenced at its own path and line,
  a plain string at `env`. Does nothing unless Gettext is extracting.
  """
  @spec mark(Macro.Env.t(), module(), String.t(), [String.t() | located()]) :: :ok
  def mark(env, backend, text_domain, texts) do
    if Gettext.Extractor.extracting?() do
      texts
      |> Enum.map(&located(&1, env))
      |> Enum.uniq()
      |> Enum.group_by(& &1.path)
      |> Enum.each(fn {path, entries} ->
        calls =
          for %{msgid: msgid, line: line} <- entries do
            {{:., [line: line], [Gettext.Macros, :dgettext_noop_with_backend]}, [line: line],
             [backend, text_domain, msgid]}
          end

        Code.eval_quoted(
          {:__block__, [], [quote(do: require(Gettext.Macros)) | calls]},
          [],
          %{env | file: path}
        )
      end)
    end

    :ok
  end

  defp located(text, env) when is_binary(text), do: %{msgid: text, path: env.file, line: env.line}
  defp located(entry, _env), do: entry

  @doc """
  The texts a resource shows: its written attribute labels and, with
  `messages?`, every literal `message` in its DSL and in the app's own
  validation, change, preparation, generic-action run, manual-action and calculation modules it uses.
  """
  @spec resource_texts(module(), boolean()) :: [String.t()]
  def resource_texts(resource, messages?),
    do: resource |> resource_messages(messages?) |> Enum.map(& &1.msgid)

  @doc """
  `resource_texts/2`, each text with the file and line it is written at.
  """
  @spec resource_messages(module(), boolean(), MapSet.t(String.t())) :: [located()]
  def resource_messages(resource, messages?, scanned_paths \\ MapSet.new()) do
    labels =
      for label <- Spark.Dsl.Extension.get_entities(resource, [:gettext]),
          do: {label.text, entity_location(label, :text, nil)}

    {messages, modules} =
      if messages?, do: walk(dsl_entities(resource), nil, {[], []}), else: {[], []}

    place(labels ++ messages, resource) ++
      Enum.flat_map(Enum.uniq(modules), &module_messages(&1, scanned_paths))
  end

  @doc """
  Every literal `message` in the app's own source: the `.ex` files under the
  project's `elixirc_paths`. Read once per backend and text domain: the first
  call returns `{:new, scan}`, every later one `{:seen, scan}`.
  """
  @spec app_messages(module(), String.t()) ::
          {:new | :seen, %{paths: MapSet.t(String.t()), messages: [located()]}}
  def app_messages(backend, text_domain) do
    key = {__MODULE__, :app_messages, backend, text_domain}

    # ponytail: remembered for the VM's life, which is one `mix gettext.extract`
    # run; a second run in the same VM would need the key cleared.
    :global.trans({key, self()}, fn ->
      case :persistent_term.get(key, nil) do
        nil ->
          scan = scan_app()
          :persistent_term.put(key, scan)
          {:new, scan}

        scan ->
          {:seen, scan}
      end
    end)
  end

  defp scan_app do
    paths =
      for dir <- Mix.Project.config()[:elixirc_paths] || [],
          path <- Path.wildcard(Path.join(dir, "**/*.ex")),
          do: Path.expand(path)

    result =
      find_messages(for path <- paths, {:ok, contents} <- [File.read(path)], do: {path, contents})

    Enum.each(result.interpolated, &warn_interpolated/1)
    %{paths: MapSet.new(paths), messages: located(result)}
  end

  defp dsl_entities(resource) do
    for {path, %{entities: entities}} when is_list(path) <- resource.spark_dsl_config(),
        path != [:gettext],
        do: entities
  end

  # Any `message` (a policy's is `error_message`) holding a string, and any `{module, opts}` implementing a
  # validation, change, preparation, run, manual action or calculation, wherever the DSL nests it.
  defp walk({key, text}, at, {messages, modules})
       when key in [:message, :error_message] and is_binary(text),
       do: {[{text, at} | messages], modules}

  defp walk({key, {module, opts}}, at, {messages, modules})
       when key in [:validation, :change, :preparation, :run, :manual, :calculation] and
              is_atom(module),
       do: walk(opts, at, {messages, [module | modules]})

  defp walk(%_{__spark_metadata__: _} = entity, at, acc) do
    entity
    |> Map.from_struct()
    |> Enum.reduce(acc, fn {key, _value} = field, acc ->
      walk(field, entity_location(entity, key, at), acc)
    end)
  end

  defp walk(%_{} = struct, at, acc), do: walk(Map.from_struct(struct), at, acc)
  defp walk(map, at, acc) when is_map(map), do: walk(Map.to_list(map), at, acc)
  defp walk(list, at, acc) when is_list(list), do: Enum.reduce(list, acc, &walk(&1, at, &2))
  defp walk(tuple, at, acc) when is_tuple(tuple), do: walk(Tuple.to_list(tuple), at, acc)
  defp walk(_other, _at, acc), do: acc

  defp entity_location(entity, key, outer) do
    anno_location(Spark.Dsl.Entity.property_anno(entity, key)) ||
      anno_location(Spark.Dsl.Entity.anno(entity)) || outer
  end

  @doc false
  def anno_location(nil), do: nil

  def anno_location(anno) do
    case :erl_anno.file(anno) do
      :undefined -> nil
      file -> {to_string(file), :erl_anno.line(anno)}
    end
  end

  # Spark records no annotation when `debug_info` is off, nor on an entity a
  # transformer built: the text is then looked up in the resource's own source.
  defp place(found, resource) do
    path = List.to_string(resource.module_info(:compile)[:source])

    ast =
      with {:ok, contents} <- File.read(path),
           {:ok, ast} <- parse(contents),
           do: ast,
           else: (_unreadable -> nil)

    Enum.map(found, fn
      {text, {file, line}} ->
        %{msgid: text, path: file, line: line}

      {text, nil} ->
        line = literal_line(ast, text) || defmodule_line(ast, resource) || 1
        %{msgid: text, path: path, line: line}
    end)
  end

  defp literal_line(ast, text) do
    find_line(ast, fn
      {:__block__, meta, [^text]} -> meta[:line]
      _other -> nil
    end)
  end

  defp defmodule_line(ast, resource) do
    find_line(ast, fn
      {:defmodule, meta, [{:__aliases__, _, parts} | _]} ->
        if Module.concat(parts) == resource, do: meta[:line]

      _other ->
        nil
    end)
  end

  defp find_line(nil, _line_of), do: nil

  defp find_line(ast, line_of) do
    {_ast, line} =
      Macro.prewalk(ast, nil, fn
        node, nil -> {node, line_of.(node)}
        node, line -> {node, line}
      end)

    line
  end

  # Anything but third-party deps, so sibling umbrella and path-dep apps count.
  defp module_messages(module, scanned_paths) do
    with {:module, ^module} <- Code.ensure_compiled(module),
         source when is_list(source) <- module.module_info(:compile)[:source],
         path = List.to_string(source),
         true <- app_source?(path),
         false <- MapSet.member?(scanned_paths, path),
         {:ok, contents} <- File.read(path) do
      result = find_messages([{path, contents}])
      Enum.each(result.interpolated, &warn_interpolated/1)
      located(result)
    else
      _not_the_apps -> []
    end
  end

  defp located(%{messages: messages}) do
    for %{msgid: msgid, references: references} <- messages,
        %{path: path, line: line} <- references,
        do: %{msgid: msgid, path: path, line: line}
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
