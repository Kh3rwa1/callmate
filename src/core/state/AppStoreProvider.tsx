import * as React from "react"

import { BRAND } from "@/core/constants/brand"
import {
  createInitialState,
  reducer,
  selectDerived,
  type Action,
  type AppData,
  type AppState,
  type Selectors,
} from "@/core/state/appReducer"
import { DEMO_BUSINESS } from "@/data/services/contactFactory"
import { createStorage, STORAGE_KEYS, type AppStorage } from "@/data/storage/localStorage"
import { createMockAuthRepository, type AuthRepository } from "@/data/repositories/authRepository"
import { createBackendRepositories, toAppData } from "@/data/repositories/backendRepositories"
import { backend, BackendError } from "@/data/backend/client"
import { createWhatsAppService, type WhatsAppService } from "@/data/services/whatsappService"
import type { RepositoryBundle } from "@/data/repositories/types"

type AppContextValue = {
  state: AppState
  dispatch: React.Dispatch<Action>
  derived: Selectors
  storage: AppStorage
  repositories: RepositoryBundle
  auth: AuthRepository
  whatsapp: WhatsAppService
  /** Re-reads all business data from the backend after a change. */
  refresh: () => Promise<void>
  loadingData: boolean
  loadError: string | null
}

const AppContext = React.createContext<AppContextValue | null>(null)

const EMPTY_DATA: AppData = { contacts: [], calls: [], followUps: [], campaigns: [] }

export function AppStoreProvider({ children }: { children: React.ReactNode }) {
  const storage = React.useMemo(() => createStorage(), [])
  const [state, dispatch] = React.useReducer(
    reducer,
    undefined,
    () => createInitialState(EMPTY_DATA, DEMO_BUSINESS)
  )

  const auth = React.useMemo(() => createMockAuthRepository(storage), [storage])
  const [loadingData, setLoadingData] = React.useState(false)
  const [loadError, setLoadError] = React.useState<string | null>(null)

  /**
   * The single way data enters the app. Everything the screens show comes from
   * the backend, so after any change we re-read rather than patching a local
   * copy — the two can never disagree about a customer's status.
   */
  const refresh = React.useCallback(async () => {
    const payload = await backend.bootstrap()
    dispatch({
      type: "refresh",
      data: toAppData(payload),
      usage: payload.usage
        ? {
            minutesUsed: Number(payload.usage.minutes_used),
            callsMade: payload.usage.calls_made,
            cycleStart: payload.usage.cycle_started_at ?? undefined,
          }
        : undefined,
    })
  }, [])

  const repositories = React.useMemo<RepositoryBundle>(
    () => createBackendRepositories(refresh).bundle,
    [refresh]
  )

  const whatsapp = React.useMemo(() => createWhatsAppService(), [])

  React.useEffect(() => {
    const onboardingComplete = storage.read<boolean>(STORAGE_KEYS.onboarding) ?? false
    const business = storage.read<AppState["business"]>(STORAGE_KEYS.business) ?? DEMO_BUSINESS
    const session = auth.restore()
    const selectedStage = storage.read<AppState["selectedStage"]>(STORAGE_KEYS.selectedStage)
    const aiEmployee = storage.read<AppState["aiEmployee"]>(STORAGE_KEYS.ai)
    const notifications = storage.read<AppState["notifications"]>(STORAGE_KEYS.notifications)

    const payload: Partial<AppState> = {
      onboardingComplete,
      business,
      session,
      selectedStage: selectedStage ?? "new",
    }
    if (aiEmployee) payload.aiEmployee = aiEmployee
    if (notifications) payload.notifications = notifications

    dispatch({ type: "hydrate", payload })
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [auth, storage])

  // Load the real data once preferences are hydrated.
  React.useEffect(() => {
    if (!state.hydrated) return
    let cancelled = false

    async function load() {
      setLoadingData(true)
      setLoadError(null)
      try {
        await refresh()
      } catch (error) {
        if (cancelled) return
        // Only a message we wrote reaches the user, never a raw API error.
        setLoadError(
          error instanceof BackendError
            ? error.message
            : "We couldn't load your data right now. Please try again."
        )
      } finally {
        if (!cancelled) setLoadingData(false)
      }
    }

    void load()
    return () => {
      cancelled = true
    }
  }, [state.hydrated, refresh])

  React.useEffect(() => {
    if (!state.hydrated) return
    storage.write(STORAGE_KEYS.onboarding, state.onboardingComplete)
    storage.write(STORAGE_KEYS.business, state.business)
    storage.write(STORAGE_KEYS.selectedStage, state.selectedStage)
    storage.write(STORAGE_KEYS.ai, state.aiEmployee)
    storage.write(STORAGE_KEYS.notifications, state.notifications)
  }, [state.hydrated, state.onboardingComplete, state.business, state.selectedStage, state.aiEmployee, state.notifications, storage])

  React.useEffect(() => {
    if (!state.toast) return
    const timer = window.setTimeout(() => dispatch({ type: "setToast", message: null }), 2400)
    return () => window.clearTimeout(timer)
  }, [state.toast])

  const derived = React.useMemo(() => selectDerived(state), [state])

  const value = React.useMemo<AppContextValue>(
    () => ({
      state,
      dispatch,
      derived,
      storage,
      repositories,
      auth,
      whatsapp,
      refresh,
      loadingData,
      loadError,
    }),
    [state, derived, storage, repositories, auth, whatsapp, refresh, loadingData, loadError]
  )

  return <AppContext.Provider value={value}>{children}</AppContext.Provider>
}

export function useApp() {
  const context = React.useContext(AppContext)
  if (!context) {
    throw new Error(`useApp must be used inside AppStoreProvider (${BRAND.productName})`)
  }
  return context
}

export function useAppState() {
  return useApp().state
}

export function useDerived() {
  return useApp().derived
}

export function useDispatch() {
  return useApp().dispatch
}
