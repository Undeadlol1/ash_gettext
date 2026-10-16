defmodule AshGettext.InstallerTest do
  use ExUnit.Case, async: true

  alias AshGettext.Installer

  @opts [backend: "MyApp.Gettext"]

  describe "install_domain/2 on a domain with an extensions list" do
    setup do
      %{
        source: """
        defmodule MyApp.Shop do
          use Ash.Domain, extensions: [AshJsonApi.Domain]

          resources do
            resource MyApp.Shop.Order
          end
        end
        """
      }
    end

    test "adds the extension alongside the ones already there", %{source: source} do
      %{content: content} = Installer.install_domain(source, @opts)

      assert content =~ "extensions: [AshJsonApi.Domain, AshGettext.Domain]"
    end

    test "adds a gettext block naming the host's backend", %{source: source} do
      %{content: content} = Installer.install_domain(source, @opts)

      assert content =~ "gettext do"
      assert content =~ "backend MyApp.Gettext"
    end

    test "leaves the rest of the domain alone", %{source: source} do
      %{content: content} = Installer.install_domain(source, @opts)

      assert content =~ "resource MyApp.Shop.Order"
    end

    test "reports that it changed the source", %{source: source} do
      assert %{changed?: true, status: :installed} = Installer.install_domain(source, @opts)
    end
  end

  describe "install_resource/1" do
    test "adds the extension alongside the ones a resource already has" do
      source = """
      defmodule MyApp.Shop.Order do
        use Ash.Resource,
          domain: MyApp.Shop,
          extensions: [AshJsonApi.Resource]
      end
      """

      %{content: content, status: status} = Installer.install_resource(source)

      assert content =~ "extensions: [AshJsonApi.Resource, AshGettext.Resource]"
      assert status == :installed
    end

    test "gives a resource without an extensions list one" do
      source = """
      defmodule MyApp.Shop.Order do
        use Ash.Resource,
          domain: MyApp.Shop
      end
      """

      assert %{content: content} = Installer.install_resource(source)
      assert content =~ "extensions: [AshGettext.Resource]"
    end

    test "is safe to run twice" do
      source = """
      defmodule MyApp.Shop.Order do
        use Ash.Resource, extensions: [AshGettext.Resource]
      end
      """

      assert %{changed?: false, status: :already_installed} = Installer.install_resource(source)
    end

    test "leaves a validation alone, despite the name starting the same way" do
      source = """
      defmodule MyApp.Shop.MinimumWeight do
        use Ash.Resource.Validation
      end
      """

      assert %{changed?: false, status: :unrecognised} = Installer.install_resource(source)
    end

    test "leaves a change and a preparation alone too" do
      for module <- ["Ash.Resource.Change", "Ash.Resource.Preparation"] do
        source = "defmodule MyApp.Thing do\n  use #{module}\nend\n"

        assert %{changed?: false, status: :unrecognised} = Installer.install_resource(source)
      end
    end

    test "changes nothing else about the resource" do
      source = """
      defmodule MyApp.Shop.Order do
        use Ash.Resource, domain: MyApp.Shop, extensions: [AshJsonApi.Resource]

        attributes do
          attribute :total, :integer
        end
      end
      """

      %{content: content} = Installer.install_resource(source)

      assert content =~ "attribute :total, :integer"
    end
  end

  describe "already_installed?/1" do
    test "is true once the extension is declared" do
      assert Installer.already_installed?("use Ash.Domain, extensions: [AshGettext.Domain]")
    end

    test "is false for a domain that does not mention it" do
      refute Installer.already_installed?("use Ash.Domain, extensions: [AshJsonApi.Domain]")
    end
  end

  describe "install_domain/2 status" do
    test "says already_installed rather than just unchanged" do
      source = """
      defmodule MyApp.Shop do
        use Ash.Domain, extensions: [AshGettext.Domain]
      end
      """

      assert %{status: :already_installed} = Installer.install_domain(source, @opts)
    end

    test "says unrecognised when it cannot find the use call, instead of a silent no-op" do
      source = """
      defmodule MyApp.NotADomain do
        def hello, do: :world
      end
      """

      assert %{status: :unrecognised, changed?: false} = Installer.install_domain(source, @opts)
    end

    test "leaves the source byte-for-byte alone when unrecognised" do
      source = "defmodule MyApp.NotADomain do\n  def hello, do: :world\nend\n"

      assert %{content: ^source} = Installer.install_domain(source, @opts)
    end
  end

  describe "install_domain/2 on a bare domain" do
    test "gives it an extensions list" do
      source = """
      defmodule MyApp.Shop do
        use Ash.Domain
      end
      """

      %{content: content} = Installer.install_domain(source, @opts)

      assert content =~ "use Ash.Domain, extensions: [AshGettext.Domain]"
      assert content =~ "gettext do"
    end
  end

  describe "install_domain/2 run twice" do
    test "makes no further change, so the installer is safe to re-run" do
      source = """
      defmodule MyApp.Shop do
        use Ash.Domain, extensions: [AshJsonApi.Domain]
      end
      """

      %{content: once} = Installer.install_domain(source, @opts)

      assert %{content: ^once, changed?: false} = Installer.install_domain(once, @opts)
    end
  end

  describe "gettext_block/1" do
    test "writes only the backend when everything else is a default" do
      block = Installer.gettext_block(@opts)

      assert block =~ "backend MyApp.Gettext"
      refute block =~ "text_domain"
      refute block =~ "locale_resolvers"
    end

    test "leaves out a text domain that is the default" do
      refute Installer.gettext_block(backend: "MyApp.Gettext", text_domain: "ash_errors") =~
               "text_domain"
    end

    test "honours a text domain that differs from the default" do
      assert Installer.gettext_block(backend: "MyApp.Gettext", text_domain: "errors") =~
               ~s|text_domain "errors"|
    end

    test "puts a host resolver after the context resolver, so an explicit locale still wins" do
      block = Installer.gettext_block(backend: "MyApp.Gettext", resolver: "MyApp.Localization")

      assert block =~ "locale_resolvers [AshGettext.Locale.Context, MyApp.Localization]"
    end
  end

  describe "resolver_stub/1" do
    test "implements the resolver behaviour" do
      assert Installer.resolver_stub("MyApp.Localization") =~
               "@behaviour AshGettext.Locale.Resolver"
    end

    test "compiles as written, so a host can install and run before filling it in" do
      stub = Installer.resolver_stub("AshGettextInstallerStubTest.Localization")

      assert {:ok, _ast} = Code.string_to_quoted(stub)
    end

    test "declines by default rather than guessing where a locale is stored" do
      stub = Installer.resolver_stub("MyApp.Localization")

      assert stub =~ "TODO"
      assert stub =~ "nil"
    end
  end
end
