defmodule AshGettext.ErrorKindsTest do
  @moduledoc """
  Every kind of error Ash can raise, read by a Russian and an English reader
  through plain Ash, an AshPhoenix form, a real JSON:API request and a GraphQL
  document. Where a transport really does not translate, that is pinned in
  "known gaps" so a later fix has to change the test too.
  """

  use ExUnit.Case, async: true

  import ExUnit.CaptureLog, only: [with_log: 1]
  import Plug.Conn
  import Plug.Test

  require Ash.Query

  alias AshGettextFixture.ApiRouter
  alias AshGettextFixture.GraphSchema
  alias AshGettextFixture.Rules.Entry
  alias AshGettextFixture.Rules.Locker
  alias AshGettextFixture.UnknownError

  @russian %{language: "ru"}
  @english %{language: "en"}
  @readers [{"Russian", @russian, :ru}, {"English", @english, :en}]
  @transports [:plain_ash, :phoenix_form, :json_api, :graphql]
  @parsers Plug.Parsers.init(
             parsers: [:json, AshJsonApi.Plug.Parser],
             json_decoder: Jason,
             pass: ["*/*"]
           )

  @weight_sentence %{ru: "Вес должен быть не менее 30 кг", en: "Weight must be at least 30 kg"}
  @minimum_sentence %{ru: "должно быть не меньше 1", en: "must be greater than or equal to 1"}
  @locked_sentence %{ru: "должно быть равно false", en: "must equal false"}
  @pattern_sentence %{
    ru: "должно соответствовать шаблону ~r/^[a-z]+$/",
    en: "must match the pattern ~r/^[a-z]+$/"
  }
  @pattern_check_sentence %{
    ru: "должно соответствовать ~r/^[a-z]+$/",
    en: "must match ~r/^[a-z]+$/"
  }
  @taken_sentence %{ru: "уже занято", en: "has already been taken"}
  @went_wrong_json %{
    ru: ~r/^Что-то пошло не так\. Номер ошибки: [0-9a-f-]+$/,
    en: ~r/^Something went wrong\. Error id: [0-9a-f-]+$/
  }
  @required_sentence %{ru: "обязательное поле", en: "is required"}
  @not_found_sentence %{ru: "не найдено", en: "could not be found"}
  @not_found_json %{ru: "не найдено", en: "No entry record found with"}
  @forbidden_on_the_wire %{ru: "Вам нельзя это делать", en: "forbidden"}
  @forbidden_sentence %{ru: "Вам нельзя это делать", en: "You are not allowed to do this"}
  @sealed_sentence %{ru: "Этот заказ уже размещён", en: "This order has already been placed"}

  @creation_kinds [
    {"a missing required value", %{code: nil},
     %{ru: "должно быть заполнено", en: "must be present"}},
    {"a number that must be greater", %{quantity: 0},
     %{ru: "должно быть больше 0", en: "must be greater than 0"}},
    {"a text that is too long", %{nickname: "toolong"},
     %{ru: "длина должна быть не больше 5", en: "length must be less than or equal to 5"}},
    {"a number below its minimum", %{stock: 0}, @minimum_sentence},
    {"a text that breaks the type's pattern", %{handle: "A1"}, @pattern_sentence},
    {"an action argument below its minimum", %{size: 0}, @minimum_sentence},
    {"a rule with a code of its own", %{weight: 5}, @weight_sentence}
  ]

  defp unique_code, do: "code-#{System.unique_integer([:positive])}"

  defp valid(attrs),
    do: Map.merge(%{code: unique_code(), quantity: 1, slug: "ab", weight: 40}, attrs)

  defp stored_entry(attrs \\ %{}), do: Ash.create!(Entry, valid(attrs))

  defp locked_entry, do: stored_entry(%{locked: true})

  defp missing_id, do: Ash.UUID.generate()

  defp text(sentences, reader), do: Map.fetch!(sentences, reader)

  defp leaf_messages({:error, error}) do
    error |> Ash.Error.to_error_class() |> Map.fetch!(:errors) |> Enum.map(& &1.message)
  end

  defp carried_sentences({:error, error}) do
    error
    |> Ash.Error.to_error_class()
    |> Map.fetch!(:errors)
    |> Enum.map(& &1.vars[:translation])
  end

  defp class_text({:error, error}), do: Exception.message(Ash.Error.to_error_class(error))

  defp form_params(attrs) do
    for {key, value} <- attrs, into: %{}, do: {to_string(key), to_string(value)}
  end

  defp field_sentences(form), do: form |> AshPhoenix.Form.errors() |> Keyword.values()

  defp submitted(form, params) do
    {:error, form} = AshPhoenix.Form.submit(form, params: params)
    form
  end

  defp json_reply(method, path, body, actor) do
    conn =
      conn(method, path, body && Jason.encode!(body))
      |> put_req_header("content-type", "application/vnd.api+json")
      |> put_req_header("accept", "application/vnd.api+json")
      |> Ash.PlugHelpers.set_actor(actor)
      |> Plug.Parsers.call(@parsers)
      |> ApiRouter.call(ApiRouter.init([]))

    {conn.status, Jason.decode!(conn.resp_body)["errors"]}
  end

  defp json_details(reply), do: reply |> elem(1) |> Enum.map(& &1["detail"])

  defp entry_body(attrs), do: %{data: %{type: "entry", attributes: attrs}}

  defp locker_body, do: %{data: %{type: "locker", attributes: %{}}}

  defp graphql(document, actor),
    do: Absinthe.run(document, GraphSchema, context: %{actor: actor})

  defp graphql_errors(document, root, actor) do
    {:ok, %{data: data}} = graphql(document, actor)
    data[root]["errors"]
  end

  defp graphql_messages(errors), do: Enum.map(errors, & &1["message"])

  @selection "errors { message shortMessage code fields }"

  defp graphql_input(attrs) do
    attrs
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
    |> Enum.map_join(", ", fn {key, value} -> "#{key}: #{inspect(value)}" end)
  end

  defp graphql_create(attrs, actor) do
    graphql_errors(
      "mutation { createEntry(input: {#{graphql_input(attrs)}}) { #{@selection} } }",
      "createEntry",
      actor
    )
  end

  defp graphql_update(entry, attrs, actor) do
    graphql_errors(
      ~s|mutation { updateEntry(id: "#{entry.id}", input: {#{graphql_input(attrs)}}) { #{@selection} } }|,
      "updateEntry",
      actor
    )
  end

  defp graphql_destroy(entry, actor) do
    graphql_errors(
      ~s|mutation { destroyEntry(id: "#{entry.id}") { #{@selection} } }|,
      "destroyEntry",
      actor
    )
  end

  defp graphql_locker(name, root, actor),
    do: graphql_errors("mutation { #{name} { #{@selection} } }", root, actor)

  defp create_sentences(:plain_ash, attrs, actor),
    do: Entry |> Ash.create(valid(attrs), actor: actor) |> leaf_messages()

  defp create_sentences(:phoenix_form, attrs, actor) do
    Entry
    |> AshPhoenix.Form.for_create(:create, actor: actor)
    |> submitted(form_params(valid(attrs)))
    |> field_sentences()
  end

  defp create_sentences(:json_api, attrs, actor),
    do: :post |> json_reply("/entries", entry_body(valid(attrs)), actor) |> json_details()

  defp create_sentences(:graphql, attrs, actor),
    do: attrs |> valid() |> graphql_create(actor) |> graphql_messages()

  defp update_sentences(:plain_ash, entry, actor),
    do: entry |> Ash.update(%{weight: 5}, actor: actor) |> leaf_messages()

  defp update_sentences(:phoenix_form, entry, actor) do
    entry
    |> AshPhoenix.Form.for_update(:update, actor: actor)
    |> submitted(%{"weight" => "5"})
    |> field_sentences()
  end

  defp update_sentences(:json_api, entry, actor) do
    body = %{data: %{type: "entry", id: entry.id, attributes: %{weight: 5}}}
    :patch |> json_reply("/entries/#{entry.id}", body, actor) |> json_details()
  end

  defp update_sentences(:graphql, entry, actor),
    do: entry |> graphql_update(%{weight: 5}, actor) |> graphql_messages()

  defp destroy_sentences(:plain_ash, entry, actor),
    do: entry |> Ash.destroy(actor: actor) |> leaf_messages()

  defp destroy_sentences(:phoenix_form, entry, actor) do
    entry
    |> AshPhoenix.Form.for_destroy(:destroy, actor: actor)
    |> submitted(nil)
    |> field_sentences()
  end

  defp destroy_sentences(:json_api, entry, actor),
    do: :delete |> json_reply("/entries/#{entry.id}", nil, actor) |> json_details()

  defp destroy_sentences(:graphql, entry, actor),
    do: entry |> graphql_destroy(actor) |> graphql_messages()

  defp weigh_sentences(:plain_ash, actor) do
    Entry
    |> Ash.ActionInput.for_action(:weigh, %{weight: 5}, actor: actor)
    |> Ash.run_action()
    |> leaf_messages()
  end

  defp weigh_sentences(:phoenix_form, actor) do
    Entry
    |> AshPhoenix.Form.for_action(:weigh, actor: actor)
    |> submitted(%{"weight" => "5"})
    |> field_sentences()
  end

  defp weigh_sentences(:json_api, actor),
    do: :post |> json_reply("/entries/weigh", %{data: %{weight: 5}}, actor) |> json_details()

  defp weigh_sentences(:graphql, actor) do
    {:ok, %{errors: errors}} = graphql("mutation { weighEntry(input: {weight: 5}) }", actor)
    Enum.map(errors, & &1.message)
  end

  describe "creating with a rule broken" do
    for {kind, attrs, sentences} <- @creation_kinds,
        {reader_name, actor, reader} <- @readers,
        transport <- @transports do
      test "#{kind} reads in #{reader_name} through #{transport}" do
        sentences = unquote(Macro.escape(sentences))

        assert [text(sentences, unquote(reader))] ==
                 create_sentences(
                   unquote(transport),
                   unquote(Macro.escape(attrs)),
                   unquote(Macro.escape(actor))
                 )
      end
    end
  end

  describe "updating a stored record with a rule broken" do
    for {reader_name, actor, reader} <- @readers, transport <- @transports do
      test "reads in #{reader_name} through #{transport}" do
        assert [text(@weight_sentence, unquote(reader))] ==
                 update_sentences(
                   unquote(transport),
                   stored_entry(),
                   unquote(Macro.escape(actor))
                 )
      end
    end
  end

  describe "a value another record already has" do
    for {reader_name, actor, reader} <- @readers, transport <- @transports do
      test "reads in #{reader_name} through #{transport}" do
        taken = stored_entry().code

        assert [text(@taken_sentence, unquote(reader))] ==
                 create_sentences(
                   unquote(transport),
                   %{code: taken},
                   unquote(Macro.escape(actor))
                 )
      end
    end
  end

  describe "destroying a record whose rule says no" do
    for {reader_name, actor, reader} <- @readers,
        transport <- [:plain_ash, :phoenix_form, :json_api] do
      test "reads in #{reader_name} through #{transport}" do
        assert [text(@locked_sentence, unquote(reader))] ==
                 destroy_sentences(
                   unquote(transport),
                   locked_entry(),
                   unquote(Macro.escape(actor))
                 )
      end
    end

    for {reader_name, actor, reader} <- @readers do
      test "reads in #{reader_name} through graphql, where the destroy runs as a bulk action" do
        assert [text(@locked_sentence, unquote(reader))] ==
                 destroy_sentences(:graphql, locked_entry(), unquote(Macro.escape(actor)))
      end
    end
  end

  describe "a generic action given a bad argument" do
    for {reader_name, actor, reader} <- @readers, transport <- @transports do
      test "reads in #{reader_name} through #{transport}" do
        assert [text(@weight_sentence, unquote(reader))] ==
                 weigh_sentences(unquote(transport), unquote(Macro.escape(actor)))
      end
    end
  end

  describe "a record that is not there" do
    for {reader_name, actor, reader} <- @readers do
      test "reads in #{reader_name} through json_api" do
        reply =
          json_reply(:get, "/entries/#{missing_id()}", nil, unquote(Macro.escape(actor)))

        assert {404, [%{"code" => "not_found"}]} = reply
        assert hd(json_details(reply)) =~ text(@not_found_json, unquote(reader))
      end

      test "reads in #{reader_name} through graphql" do
        {:ok, %{errors: [error]}} =
          graphql(
            ~s|query { entry(id: "#{missing_id()}") { id } }|,
            unquote(Macro.escape(actor))
          )

        assert error.message == text(@not_found_sentence, unquote(reader))
      end
    end
  end

  describe "a sentence the catalog has no entry for" do
    for {reader_name, actor, _reader} <- @readers, transport <- @transports do
      test "reaches a #{reader_name} reader in English with its value filled in through #{transport}" do
        assert ["needs 2 more words"] ==
                 create_sentences(
                   unquote(transport),
                   %{note: "unlisted"},
                   unquote(Macro.escape(actor))
                 )
      end
    end
  end

  describe "a policy that forbids" do
    for {reader_name, actor, reader} <- @readers do
      test "reads in #{reader_name} through plain_ash when it has no message of its own" do
        result =
          Ash.create(AshGettextFixture.Rules.Locker, %{},
            action: :open_plain,
            actor: unquote(Macro.escape(actor))
          )

        assert class_text(result) =~ text(@forbidden_sentence, unquote(reader))
      end

      test "reads in #{reader_name} through plain_ash with the message the policy gave" do
        result =
          Ash.create(AshGettextFixture.Rules.Locker, %{},
            action: :open_sealed,
            actor: unquote(Macro.escape(actor))
          )

        assert class_text(result) =~ text(@sealed_sentence, unquote(reader))
      end

      test "reads in #{reader_name} through json_api when it has no message of its own" do
        reply = json_reply(:post, "/lockers/plain", locker_body(), unquote(Macro.escape(actor)))

        assert {403, [%{"code" => "forbidden"}]} = reply
        assert [text(@forbidden_on_the_wire, unquote(reader))] == json_details(reply)
      end

      test "reads in #{reader_name} through graphql when it has no message of its own" do
        errors =
          graphql_locker("openPlainLocker", "openPlainLocker", unquote(Macro.escape(actor)))

        assert [text(@forbidden_on_the_wire, unquote(reader))] == graphql_messages(errors)
      end
    end
  end

  describe "an error no catalog and no transport has heard of" do
    for {reader_name, actor, reader} <- @readers do
      test "comes back from plain_ash to a #{reader_name} reader untouched" do
        result = Ash.create(Entry, valid(%{note: "unknown"}), actor: unquote(Macro.escape(actor)))

        assert [%UnknownError{reason: "odd"}] =
                 result |> elem(1) |> Ash.Error.to_error_class() |> Map.fetch!(:errors)
      end

      test "shows a #{reader_name} reader no field error on a phoenix_form and logs a warning" do
        {sentences, log} =
          with_log(fn ->
            create_sentences(:phoenix_form, %{note: "unknown"}, unquote(Macro.escape(actor)))
          end)

        assert sentences == []
        assert log =~ "does not implement the `AshPhoenix.FormData.Error` protocol"
      end

      test "answers a #{reader_name} reader with something_went_wrong through json_api" do
        {reply, log} =
          with_log(fn ->
            json_reply(
              :post,
              "/entries",
              entry_body(valid(%{note: "unknown"})),
              unquote(Macro.escape(actor))
            )
          end)

        assert {400, [%{"code" => "something_went_wrong", "detail" => detail}]} = reply
        assert detail =~ Map.fetch!(@went_wrong_json, unquote(reader))
        assert log =~ "AshJsonApi.Error not implemented"
      end

      test "answers a #{reader_name} reader in English through graphql, which hands the text to no handler" do
        {[message], log} =
          with_log(fn ->
            %{note: "unknown"}
            |> valid()
            |> graphql_create(unquote(Macro.escape(actor)))
            |> graphql_messages()
          end)

        assert message =~ ~r/^something went wrong\. Unique error id: `[0-9a-f-]+`$/
        assert log =~ "AshGraphql.Error not implemented"
      end
    end
  end

  describe "bulk and plain reads" do
    for {reader_name, actor, reader} <- @readers do
      test "bulk_create reports a rule broken in the #{reader_name} reader's language" do
        result =
          Ash.bulk_create([valid(%{weight: 5})], Entry, :create,
            actor: unquote(Macro.escape(actor)),
            return_errors?: true
          )

        assert :error == result.status
        assert Exception.message(hd(result.errors)) =~ text(@weight_sentence, unquote(reader))
      end

      test "a missing record is reported to a #{reader_name} reader by plain Ash in English" do
        {:error, error} =
          Ash.get(Entry, missing_id(), actor: unquote(Macro.escape(actor)))

        assert Exception.message(error) =~ "not found"
      end
    end
  end

  describe "a match validation with no message, whose pattern Ash writes into the text" do
    for {reader_name, actor, reader} <- @readers, transport <- @transports do
      test "reads to a #{reader_name} reader in their language through #{transport}" do
        assert [@pattern_check_sentence[unquote(reader)]] ==
                 create_sentences(
                   unquote(transport),
                   %{slug: "A1"},
                   unquote(Macro.escape(actor))
                 )
      end
    end
  end

  describe "a read called from code" do
    for {reader_name, actor, reader} <- @readers do
      test "shows a #{reader_name} reader an argument below its minimum" do
        result =
          Entry
          |> Ash.Query.for_read(:heavier, %{than: 0}, actor: unquote(Macro.escape(actor)))
          |> Ash.read()

        assert [text(@minimum_sentence, unquote(reader))] == leaf_messages(result)
      end

      test "shows a #{reader_name} reader an argument below its minimum when Ash prepares the query" do
        result =
          Entry
          |> Ash.Query.set_argument(:than, 0)
          |> Ash.read(action: :heavier, actor: unquote(Macro.escape(actor)))

        assert [text(@minimum_sentence, unquote(reader))] == leaf_messages(result)
      end

      test "shows a #{reader_name} reader a missing argument" do
        result =
          Entry
          |> Ash.Query.for_read(:heavier, %{}, actor: unquote(Macro.escape(actor)))
          |> Ash.read()

        assert [text(@required_sentence, unquote(reader))] == carried_sentences(result)
      end

      test "shows a #{reader_name} reader a policy without a message" do
        result = Ash.read(Locker, action: :peek_plain, actor: unquote(Macro.escape(actor)))

        assert class_text(result) =~ text(@forbidden_sentence, unquote(reader))
      end

      test "shows a #{reader_name} reader a policy's own message" do
        result = Ash.read(Locker, action: :peek_sealed, actor: unquote(Macro.escape(actor)))

        assert class_text(result) =~ text(@sealed_sentence, unquote(reader))
      end

      test "shows a #{reader_name} reader a policy's own message when the query came prepared" do
        result =
          Locker
          |> Ash.Query.for_read(:peek_sealed, %{}, actor: unquote(Macro.escape(actor)))
          |> Ash.read()

        assert class_text(result) =~ text(@sealed_sentence, unquote(reader))
      end

      test "shows a #{reader_name} reader the rule a record broke when many are deleted one by one" do
        entry = locked_entry()

        result =
          Entry
          |> Ash.Query.filter(id == ^entry.id)
          |> Ash.bulk_destroy(:destroy, %{},
            actor: unquote(Macro.escape(actor)),
            return_errors?: true,
            strategy: [:stream],
            allow_stream_with: :full_read
          )

        assert [text(@locked_sentence, unquote(reader))] ==
                 result.errors |> Enum.flat_map(& &1.errors) |> Enum.map(& &1.message)
      end
    end
  end

  describe "a policy with a message of its own" do
    for {reader_name, actor, reader} <- @readers do
      test "shows a #{reader_name} reader that message through json_api" do
        reply = json_reply(:post, "/lockers/sealed", locker_body(), unquote(Macro.escape(actor)))

        assert [text(@sealed_sentence, unquote(reader))] == json_details(reply)
      end

      test "shows a #{reader_name} reader that message through graphql" do
        errors =
          graphql_locker("openSealedLocker", "openSealedLocker", unquote(Macro.escape(actor)))

        assert [text(@sealed_sentence, unquote(reader))] == graphql_messages(errors)
      end

      test "a #{reader_name} reader refused without a message is not shown the last reader's" do
        json_reply(:post, "/lockers/sealed", locker_body(), unquote(Macro.escape(actor)))
        reply = json_reply(:post, "/lockers/plain", locker_body(), unquote(Macro.escape(actor)))

        assert [text(@forbidden_on_the_wire, unquote(reader))] == json_details(reply)
      end
    end
  end

  describe "known gaps" do
    for {reader_name, actor, _reader} <- @readers do
      test "a policy failure shows a #{reader_name} reader no field error on a phoenix_form and logs a warning" do
        {sentences, log} =
          with_log(fn ->
            AshGettextFixture.Rules.Locker
            |> AshPhoenix.Form.for_create(:open_sealed, actor: unquote(Macro.escape(actor)))
            |> submitted(nil)
            |> field_sentences()
          end)

        assert [] == sentences
        assert log =~ "does not implement the `AshPhoenix.FormData.Error` protocol"
      end

      test "many records deleted in one statement leave a #{reader_name} reader the sentence untranslated" do
        entry = locked_entry()

        result =
          Entry
          |> Ash.Query.filter(id == ^entry.id)
          |> Ash.bulk_destroy(:destroy, %{},
            actor: unquote(Macro.escape(actor)),
            return_errors?: true,
            strategy: [:atomic],
            allow_stream_with: :full_read
          )

        assert [%{message: "must equal %{value}"}] = Enum.flat_map(result.errors, & &1.errors)
      end

      test "Ash.get leaves a #{reader_name} reader a missing record without a sentence" do
        result = Ash.get(Entry, missing_id(), actor: unquote(Macro.escape(actor)))

        assert [nil] == carried_sentences(result)
      end

      test "Ash.read_one leaves a #{reader_name} reader a missing record without a sentence" do
        result =
          Entry
          |> Ash.Query.for_read(:by_code, %{code: "nobody"}, actor: unquote(Macro.escape(actor)))
          |> Ash.read_one(not_found_error?: true)

        assert [nil] == carried_sentences(result)
      end

      test "a count leaves a #{reader_name} reader the policy's message as it was written" do
        result =
          Locker
          |> Ash.Query.for_read(:peek_sealed, %{}, actor: unquote(Macro.escape(actor)))
          |> Ash.count()

        assert class_text(result) =~ "order_already_placed"
      end

      test "an argument error stays as written for a #{reader_name} reader named only when the read runs" do
        result =
          Entry
          |> Ash.Query.for_read(:heavier, %{than: 0})
          |> Ash.read(actor: unquote(Macro.escape(actor)))

        assert [text(@minimum_sentence, :en)] == leaf_messages(result)
      end
    end
  end
end
