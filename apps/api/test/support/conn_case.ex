defmodule TreeDxWeb.ConnCase do
  use ExUnit.CaseTemplate

  using do
    quote do
      import Plug.Conn
      import Phoenix.ConnTest
      import TreeDxTestFixtures
      import TreeDxPublicHygieneAssertions

      @endpoint TreeDxWeb.Endpoint
    end
  end

  setup _tags do
    dir = Path.join(System.tmp_dir!(), "treedx-conn-test-#{System.unique_integer([:positive])}")
    File.rm_rf!(dir)
    Application.put_env(:treedx, :data_dir, dir)
    TreeDx.Store.init!(node_id: "node_local")
    {:ok, _} = TreeDx.Store.seed_dev_records("node_local", "http://localhost:4000")
    {:ok, conn: Phoenix.ConnTest.build_conn()}
  end
end
