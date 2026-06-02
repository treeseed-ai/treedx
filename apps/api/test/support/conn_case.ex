defmodule TreeDbWeb.ConnCase do
  use ExUnit.CaseTemplate

  using do
    quote do
      import Plug.Conn
      import Phoenix.ConnTest

      @endpoint TreeDbWeb.Endpoint
    end
  end

  setup _tags do
    dir = Path.join(System.tmp_dir!(), "treedb-conn-test-#{System.unique_integer([:positive])}")
    File.rm_rf!(dir)
    Application.put_env(:treedb, :data_dir, dir)
    TreeDb.Store.init!(node_id: "node_local")
    {:ok, _} = TreeDb.Store.seed_dev_records("node_local", "http://localhost:4000")
    {:ok, conn: Phoenix.ConnTest.build_conn()}
  end
end
