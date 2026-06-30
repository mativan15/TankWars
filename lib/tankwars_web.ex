defmodule TankWarsWeb do
  @moduledoc false

  def controller do
    quote do
      use Phoenix.Controller, formats: [:html, :json], layouts: []

      import Plug.Conn
    end
  end

  def router do
    quote do
      use Phoenix.Router, helpers: false

      import Plug.Conn
      import Phoenix.Controller
    end
  end

  def channel do
    quote do
      use Phoenix.Channel
    end
  end

  def static_paths, do: ~w(assets sounds)

  defmacro __using__(which) when is_atom(which) do
    apply(__MODULE__, which, [])
  end
end
