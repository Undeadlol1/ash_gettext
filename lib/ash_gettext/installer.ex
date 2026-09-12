defmodule AshGettext.Installer do
  @moduledoc """
  The source rewrites `mix ash_gettext.install` performs, as pure functions.

  Opting a domain into translation is mechanical: add the extension, add a
  `gettext do` block naming the host's backend. Doing that by hand across a real
  app is a dozen near-identical edits, each a chance to miss one — and a domain
  that gets missed keeps emitting untranslated errors with nothing to notice.

  The work lives here rather than in the Mix task so it can be tested as
  `string in, string out`: no igniter, no project, no filesystem. The task is a
  thin shell that reads files, calls these, and writes them back.

  ## What cannot be generated

  `locale_resolver` is deliberately left pointing at the library's generic
  `AshGettext.Locale.Context`, which reads a locale someone already put on the
  action context. Resolving "the signed-in user's saved language" needs to know
  where the host stores that, which is exactly what a generic library must not
  assume. `resolver_stub/1` generates a module with the
  behaviour and a `TODO` instead of guessing.
  """

  @typedoc """
  What happened to one domain.

  `:unrecognised` matters as much as the other two: a domain whose `use` call
  this cannot find comes back byte-for-byte unchanged, and without a status that
  is indistinguishable from "already done". A caller must be able to say so out
  loud rather than report a silent success.
  """
  @type status :: :installed | :already_installed | :unrecognised

  @type result :: %{content: String.t(), changed?: boolean(), status: status()}

  @doc """
  Add the `AshGettext.Domain` extension and a `gettext do` block to a domain.

  Returns the source unchanged when the domain already has the extension, so
  running the installer twice is safe.

  ## Options

    * `:backend` — required; the host's Gettext backend module, as a string.
    * `:text_domain` — the gettext text domain. Defaults to `"ash_errors"`.
    * `:resolver` — a locale resolver module name to place ahead of the generic
      context resolver. Omitted when absent.
  """
  @spec install_domain(String.t(), keyword()) :: result()
  def install_domain(content, opts) when is_binary(content) do
    if already_installed?(content) do
      %{content: content, changed?: false, status: :already_installed}
    else
      rewritten = content |> add_extension() |> insert_gettext_block(opts)

      if String.contains?(rewritten, "gettext do") do
        %{content: rewritten, changed?: true, status: :installed}
      else
        %{content: content, changed?: false, status: :unrecognised}
      end
    end
  end

  @doc """
  Add the `AshGettext.Resource` extension to a resource.

  A domain's `gettext do` block does nothing on its own: the error handler is
  installed by the *resource* extension, so a migration that wires only domains
  changes no behaviour at all. This is the other half.

  Resources are never otherwise touched — no attribute, action or policy.
  """
  # `use Ash.Resource` and nothing more. Without the boundary this also matches
  # `use Ash.Resource.Validation`, `.Change` and `.Preparation` -- 174 files in
  # this app alone, none of them resources.
  @resource_declaration ~r/^\s*use Ash\.Resource\s*(,|$)/m

  @spec install_resource(String.t()) :: result()
  def install_resource(content) when is_binary(content) do
    cond do
      String.contains?(content, "AshGettext.Resource") ->
        %{content: content, changed?: false, status: :already_installed}

      Regex.match?(@resource_declaration, content) ->
        rewritten = add_resource_extension(content)

        if rewritten == content do
          %{content: content, changed?: false, status: :unrecognised}
        else
          %{content: rewritten, changed?: true, status: :installed}
        end

      true ->
        %{content: content, changed?: false, status: :unrecognised}
    end
  end

  @doc """
  Whether this source already opts into `AshGettext.Domain`.
  """
  @spec already_installed?(String.t()) :: boolean()
  def already_installed?(content), do: String.contains?(content, "AshGettext.Domain")

  @doc """
  The `gettext do` block for a domain, as source text.
  """
  @spec gettext_block(keyword()) :: String.t()
  def gettext_block(opts) do
    backend = Keyword.fetch!(opts, :backend)
    text_domain = Keyword.get(opts, :text_domain, "ash_errors")

    """
      gettext do
        backend #{backend}
        text_domain "#{text_domain}"
        locale_resolvers [#{resolvers(opts)}]
      end
    """
  end

  @doc """
  A locale resolver the host must finish writing.

  Generated rather than inferred: the library cannot know where an application
  keeps a user's language, and guessing wrong is worse than an obvious `TODO`.
  """
  @spec resolver_stub(String.t()) :: String.t()
  def resolver_stub(module) do
    """
    defmodule #{module} do
      @moduledoc \"\"\"
      Tells AshGettext how this application finds a user's language.

      AshGettext ships no actor-aware resolver: it has no idea what a user is in
      this app, and must not learn. This is the seam where that knowledge lives.
      \"\"\"

      @behaviour AshGettext.Locale.Resolver

      @impl true
      def resolve(%{actor: actor}) when is_map(actor) do
        # TODO: return the locale this actor has chosen, or nil to fall back.
        #
        #   actor.locale
        #   MyApp.Accounts.locale_for(actor)
        #
        # Returning nil is always safe — the next resolver, then the domain's
        # default_locale, will answer.
        _ = actor
        nil
      end

      def resolve(_context), do: nil
    end
    """
  end

  defp resolvers(opts) do
    case Keyword.get(opts, :resolver) do
      nil -> "AshGettext.Locale.Context"
      resolver -> "AshGettext.Locale.Context, #{resolver}"
    end
  end

  # `use Ash.Domain` appears with an extensions list, or bare. Both are common.
  defp add_extension(content) do
    cond do
      Regex.match?(~r/extensions:\s*\[/, content) ->
        add_to_extensions(content)

      Regex.match?(~r/use Ash\.Domain\b(?!,)/, content) ->
        Regex.replace(
          ~r/use Ash\.Domain\b/,
          content,
          "use Ash.Domain, extensions: [AshGettext.Domain]",
          global: false
        )

      true ->
        Regex.replace(~r/(use Ash\.Domain,)/, content, "\\1 extensions: [AshGettext.Domain],",
          global: false
        )
    end
  end

  defp add_resource_extension(content) do
    if Regex.match?(~r/extensions:\s*\[/, content) do
      add_to_extensions(content, "AshGettext.Resource")
    else
      Regex.replace(
        ~r/(use Ash\.Resource,)/,
        content,
        "\\1 extensions: [AshGettext.Resource],",
        global: false
      )
    end
  end

  # The new extension goes immediately after the last one already listed, never
  # on the line of the closing bracket. A multi-line list closes like this:
  #
  #       Ash.Domain.CodeInterface
  #     ]
  #
  # and appending before the bracket yields a line starting with a comma, which
  # is a syntax error rather than a formatting nit.
  defp add_to_extensions(content, extension \\ "AshGettext.Domain") do
    Regex.replace(
      ~r/(extensions:\s*\[)([^\]]*?)(\s*)\]/,
      content,
      fn _match, opening, existing, trailing ->
        separator = if String.trim(existing) == "", do: "", else: ", "
        "#{opening}#{existing}#{separator}#{extension}#{trailing}]"
      end,
      global: false
    )
  end

  # Placed straight after the `use Ash.Domain` call, which is where a reader
  # looks for how a domain is configured.
  #
  # Where that call *ends* is read from the AST rather than matched with a
  # regex. A real domain spreads its options over many lines:
  #
  #     use Ash.Domain,
  #       otp_app: :my_app,
  #       extensions: [
  #         AshAdmin.Domain,
  #         Ash.Domain.CodeInterface
  #       ]
  #
  # and a pattern that stops at the first line without a continuation inserts
  # the block into the middle of the list. Four of this app's thirteen domains
  # look like that, and every one produced source that would not parse.
  defp insert_gettext_block(content, opts) do
    case use_call_last_line(content) do
      nil -> content
      line -> insert_after_line(content, line, String.trim_trailing(gettext_block(opts)))
    end
  end

  # `literal_encoder` is what makes the closing bracket visible. A plain list is
  # a bare Elixir list in quoted form, not a `{form, meta, args}` tuple, so it
  # carries no metadata at all — and the `]` of a multi-line extensions list is
  # exactly the position we need. Wrapping literals in blocks gives them meta.
  defp use_call_last_line(content) do
    parsed =
      Code.string_to_quoted(content,
        token_metadata: true,
        literal_encoder: &{:ok, {:__block__, &2, [&1]}}
      )

    case parsed do
      {:ok, ast} ->
        find_use_last_line(ast)

      # A syntax error is the only way this fails, and the caller's answer to it
      # is the same as "no use call here": leave the source alone and report it
      # as unrecognised rather than write something half-transformed.
      {:error, {_location, _message, _token}} ->
        nil
    end
  end

  defp find_use_last_line(ast) do
    {_ast, line} =
      Macro.prewalk(ast, nil, fn
        {:use, meta, [{:__aliases__, _, [:Ash, :Domain]} | _] = args} = node, _found ->
          {node, deepest_line(args, meta[:line] || 1)}

        node, found ->
          {node, found}
      end)

    line
  end

  # A node's own line is not enough: a multi-line list ends at its closing
  # bracket, which lives in `closing` metadata rather than on any child.
  defp deepest_line(ast, start) do
    {_ast, line} =
      Macro.prewalk(ast, start, fn
        {_form, meta, _args} = node, deepest when is_list(meta) ->
          {node, Enum.max([deepest, meta[:line] || 0, meta[:closing][:line] || 0])}

        node, deepest ->
          {node, deepest}
      end)

    line
  end

  defp insert_after_line(content, line, block) do
    {before, rest} = content |> String.split("\n") |> Enum.split(line)

    Enum.join(before ++ ["", block] ++ rest, "\n")
  end
end
