defmodule Mix.Tasks.AshGettext.Install do
  @shortdoc "Opt every Ash domain into translated errors"

  @moduledoc """
  Wire this application into `ash_gettext`.

      mix ash_gettext.install                    # preview every edit
      mix ash_gettext.install --apply            # write them
      mix ash_gettext.install --backend MyApp.Gettext --resolver MyApp.Localization

  For each Ash domain it adds the `AshGettext.Domain` extension and a
  `gettext do` block naming this app's Gettext backend. A domain that already
  has the extension is skipped, so re-running is safe.

  ## Options

    * `--backend` — the Gettext backend to translate against. Detected from the
      project when there is exactly one `use Gettext.Backend`.
    * `--resolver` — a module implementing `AshGettext.Locale.Resolver`, placed
      after the generic context resolver so an explicit locale still wins.
    * `--text-domain` — defaults to `ash_errors`, which is what
      `mix ash_gettext.extract` writes.
    * `--apply` — write the changes. Without it, nothing is written.

  ## What this cannot do for you

  Translating to *the signed-in user's saved language* needs a resolver that
  knows where this app stores that, and a generic library must not assume it.
  Without `--resolver` the domains are wired to `AshGettext.Locale.Context`,
  which reads `context[:locale]` — enough to translate whatever locale a
  request carries. For the rest, implement `AshGettext.Locale.Resolver`
  yourself; `AshGettext.Installer.resolver_stub/1` returns a starting point.
  """

  use Mix.Task

  alias AshGettext.Installer

  @switches [backend: :string, resolver: :string, text_domain: :string, apply: :boolean]

  @impl Mix.Task
  def run(argv) do
    {opts, roots} = OptionParser.parse!(argv, strict: @switches)

    backend = backend(opts)
    searched = search_roots(roots)

    domains =
      wire(domain_paths(searched), &Installer.install_domain(&1, install_opts(opts, backend)))

    resources = wire(resource_paths(searched), &Installer.install_resource/1)

    report(domains, resources, backend, apply?(opts))
    write_changes(domains ++ resources, apply?(opts))
  end

  defp wire(paths, install), do: Enum.map(paths, &{&1, install.(File.read!(&1))})

  defp backend(opts), do: opts[:backend] || detect_backend()
  defp apply?(opts), do: Keyword.get(opts, :apply, false)

  defp search_roots([]), do: ["lib"]
  defp search_roots(roots), do: roots

  defp write_changes(_results, false), do: :ok

  defp write_changes(results, true) do
    for {path, %{changed?: true, content: content}} <- results, do: File.write!(path, content)
  end

  defp install_opts(opts, backend) do
    [backend: backend]
    |> put_present(:text_domain, opts[:text_domain])
    |> put_present(:resolver, opts[:resolver])
  end

  defp put_present(opts, _key, nil), do: opts
  defp put_present(opts, key, value), do: Keyword.put(opts, key, value)

  @domain_declaration ~r/^\s*use Ash\.Domain/m

  # Bounded so it does not also match Ash.Resource.Validation/.Change/.Preparation.
  @resource_declaration ~r/^\s*use Ash\.Resource\s*(,|$)/m

  defp domain_paths(roots), do: paths_matching(roots, @domain_declaration)
  defp resource_paths(roots), do: paths_matching(roots, @resource_declaration)

  defp paths_matching(roots, declaration) do
    roots
    |> Enum.flat_map(&Path.wildcard(Path.join(&1, "**/*.ex")))
    |> Enum.uniq()
    |> Enum.filter(&Regex.match?(declaration, File.read!(&1)))
    |> Enum.sort()
  end

  # One `use Gettext.Backend` is the overwhelmingly common case. Two is not
  # something to guess at, and zero means the host has no catalogs yet.
  defp detect_backend do
    case gettext_backends() do
      [backend] ->
        backend

      [] ->
        Mix.raise("""
        No Gettext backend found.

        ash_gettext translates against your app's existing catalogs, so it needs
        a backend. Create one, or name it with --backend.
        """)

      many ->
        Mix.raise("""
        Found #{length(many)} Gettext backends: #{Enum.join(many, ", ")}.

        Name the one to translate errors against with --backend.
        """)
    end
  end

  # Anchored to a real declaration, not a mention. Matching the bare string
  # finds every moduledoc that talks about backends -- including this task's,
  # which is how the first version reported itself as one.
  @backend_declaration ~r/^\s*use Gettext\.Backend/m
  @module_declaration ~r/^defmodule\s+([\w.]+)\s+do/m

  defp gettext_backends do
    for path <- Path.wildcard("lib/**/*.ex"),
        source = File.read!(path),
        Regex.match?(@backend_declaration, source),
        [_full, module] <- Regex.scan(@module_declaration, source),
        do: module
  end

  defp report(domains, resources, backend, apply?) do
    Mix.shell().info("Backend: #{backend}")
    report_group("Domains", domains)
    report_group("Resources", resources)
    report_unrecognised(unrecognised(domains) ++ unrecognised(resources))

    if !apply? do
      Mix.shell().info("\nNothing written. Re-run with --apply to make these changes.")
    end
  end

  defp report_group(label, results) do
    by_status = Enum.group_by(results, fn {_path, result} -> result.status end)
    installed = Map.get(by_status, :installed, [])
    already = Map.get(by_status, :already_installed, [])

    Mix.shell().info("#{label}: #{length(installed)} to wire, #{length(already)} already done")
  end

  defp unrecognised(results) do
    Enum.filter(results, fn {_path, result} -> result.status == :unrecognised end)
  end

  # Never let this pass as "nothing to do": the domain looks like a domain and
  # was left alone anyway, which is the one outcome a caller cannot infer.
  defp report_unrecognised([]), do: :ok

  defp report_unrecognised(unrecognised) do
    Mix.shell().error("""

    #{length(unrecognised)} files could not be wired automatically:

      #{Enum.map_join(unrecognised, "\n  ", fn {path, _result} -> path end)}

    Add the extension and a gettext block by hand, or open an issue with the
    shape of the `use Ash.Domain` call.
    """)
  end
end
