{:ok, _apps} = Application.ensure_all_started(:x3m_system)
:ok = Banking.Api.Test.Router.register_services()

ExUnit.start()
