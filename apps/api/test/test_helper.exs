File.rm_rf!(Application.get_env(:treedx, :data_dir))
ExUnit.start()
