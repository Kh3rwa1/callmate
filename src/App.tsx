import { Toaster } from "sonner"

import { AppRouterProvider } from "@/app/router"
import { RouteView } from "@/app/RouteView"
import { AppStoreProvider, useApp } from "@/core/state/AppStoreProvider"
import { AppToast } from "@/core/widgets/AppToast"

function AppShell() {
  const { state } = useApp()
  return (
    <>
      <RouteView />
      <AppToast message={state.toast} />
      <Toaster position="top-center" />
    </>
  )
}

export function App() {
  return (
    <AppStoreProvider>
      <AppRouterProvider>
        <AppShell />
      </AppRouterProvider>
    </AppStoreProvider>
  )
}

export default App
