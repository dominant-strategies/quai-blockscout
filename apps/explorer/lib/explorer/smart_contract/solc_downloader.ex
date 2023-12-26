defmodule Explorer.SmartContract.SolcDownloader do
  @moduledoc """
  Checks to see if the requested solc compiler version exists, and if not it
  downloads and stores the file.
  """
  use GenServer

  alias Explorer.SmartContract.CompilerVersion

  @latest_compiler_refetch_time :timer.minutes(30)

  def ensure_exists(version) do
    path = file_path(version)

    if File.exists?(path) && version !== "latest" do
      path
    else
      compiler_versions =
        case CompilerVersion.fetch_versions(:solc) do
          {:ok, compiler_versions} ->
            compiler_versions

          {:error, _} ->
            []
        end

      if version in compiler_versions do
        GenServer.call(__MODULE__, {:ensure_exists, version}, 60_000)
      else
        false
      end
    end
  end

  def start_link(_) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  # sobelow_skip ["Traversal"]
  @impl true
  def init([]) do
    File.mkdir(compiler_dir())

    {:ok, []}
  end

  # sobelow_skip ["Traversal"]
  @impl true
  def handle_call({:ensure_exists, version}, _from, state) do
    path = file_path(version)

    if fetch?(version, path) do
      temp_path = file_path("#{version}-tmp")

      contents = download(version)
      IO.inspect(version, label: "Version:")
      IO.inspect(contents, label: "Contents:")
      IO.inspect(temp_path, label: "Temp Path:")
      file = File.open!(temp_path, [:write, :exclusive])

      IO.binwrite(file, contents)

      File.rename(temp_path, path)
      wasm_contents = download("solidityX-wasm")
      wasm_temp_path = file_path("soljson-tmp.wasm")
      IO.inspect(wasm_contents, label: "Wasm Contents:")
      IO.inspect(wasm_temp_path, label: "Wasm Temp Path:")

      file = File.open!(wasm_temp_path, [:write, :exclusive])
      IO.binwrite(file, wasm_contents)

      File.rename(wasm_temp_path, file_path_wasm())
    end

    {:reply, path, state}
  end

  defp file_path_wasm() do
    Path.join(compiler_dir(), "soljson.wasm")
  end

  defp fetch?("latest", path) do
    case File.stat(path) do
      {:error, :enoent} ->
        true

      {:ok, %{mtime: mtime}} ->
        last_modified = NaiveDateTime.from_erl!(mtime)
        diff = Timex.diff(NaiveDateTime.utc_now(), last_modified, :milliseconds)

        diff > @latest_compiler_refetch_time
    end
  end

  defp fetch?(_, path) do
    not File.exists?(path)
  end

  defp file_path(version) do
    Path.join(compiler_dir(), "#{version}.js")
  end

  defp compiler_dir do
    Application.app_dir(:explorer, "priv/solc_compilers/")
  end

  defp download(version) do
    IO.puts("Downloading #{version}")
    download_path =
      case version do
        "solidityX-wasm" ->
          "https://storage.googleapis.com/quai-utility/blockscout/soljson.wasm"
        "0.8.19-solidityx" ->
          "https://storage.googleapis.com/quai-utility/blockscout/0.8.19-solidityx.js"
        _ ->
          "https://solc-bin.ethereum.org/bin/soljson-#{version}.js"
      end
    IO.inspect(download_path, label: "Download Path:")

    try do
      download_path
      |> HTTPoison.get!([], timeout: 60_000, recv_timeout: 60_000)
      |> Map.get(:body)
      |> IO.inspect(label: "Downloaded Body:")
    rescue
      e in HTTPoison.Error -> IO.puts("HTTPoison error: #{e.message}")
      e in Exception -> IO.puts("General error: #{e.message}")
    end
  end
end
