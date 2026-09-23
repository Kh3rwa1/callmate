import * as React from "react"

import { isPrimaryPath } from "@/app/routes"

type NavigateOptions = { replace?: boolean }

type RouterValue = {
  pathname: string
  navigate: (to: string, options?: NavigateOptions) => void
  back: () => void
  canGoBack: boolean
  showBottomNav: boolean
}

const RouterContext = React.createContext<RouterValue | null>(null)

const HISTORY_KEY = "__callmateDepth"
const MAX_DEPTH = 40

function currentPath() {
  const path = window.location.pathname
  return path === "/" ? "/" : path.replace(/\/+$/, "") || "/"
}

/**
 * Minimal history-based router. Keeps the app on real URLs (so browser back
 * works and deep links resolve) without pulling in a routing dependency.
 */
export function AppRouterProvider({
  children,
  initialPath = "/welcome",
}: {
  children: React.ReactNode
  initialPath?: string
}) {
  const [pathname, setPathname] = React.useState(() =>
    window.location.pathname === "/" || window.location.pathname === ""
      ? initialPath
      : currentPath()
  )

  React.useEffect(() => {
    // Seed history depth so `canGoBack` is accurate on a cold start.
    const depth = Number(window.sessionStorage.getItem(HISTORY_KEY) ?? "0")
    window.sessionStorage.setItem(HISTORY_KEY, String(Math.max(depth, 1)))

    if (window.location.pathname === "/" || window.location.pathname === "") {
      window.history.replaceState({ depth: 1 }, "", initialPath)
    }

    const onPopState = () => setPathname(currentPath())
    window.addEventListener("popstate", onPopState)
    return () => window.removeEventListener("popstate", onPopState)
  }, [initialPath])

  const navigate = React.useCallback((to: string, options?: NavigateOptions) => {
    if (to === currentPath()) return
    const depth = Number(window.sessionStorage.getItem(HISTORY_KEY) ?? "1")
    const nextDepth = options?.replace ? depth : Math.min(depth + 1, MAX_DEPTH)
    window.sessionStorage.setItem(HISTORY_KEY, String(nextDepth))
    if (options?.replace) {
      window.history.replaceState({ depth: nextDepth }, "", to)
    } else {
      window.history.pushState({ depth: nextDepth }, "", to)
    }
    setPathname(currentPath())
    window.scrollTo({ top: 0, behavior: "auto" })
  }, [])

  const back = React.useCallback(() => {
    const depth = Number(window.sessionStorage.getItem(HISTORY_KEY) ?? "1")
    if (window.history.length > 1 && depth > 1) {
      window.history.back()
      window.sessionStorage.setItem(HISTORY_KEY, String(depth - 1))
    } else {
      navigate("/home", { replace: true })
    }
  }, [navigate])

  const value = React.useMemo<RouterValue>(
    () => ({
      pathname,
      navigate,
      back,
      canGoBack: true,
      showBottomNav: isPrimaryPath(pathname),
    }),
    [pathname, navigate, back]
  )

  return <RouterContext.Provider value={value}>{children}</RouterContext.Provider>
}

export function useRouter() {
  const context = React.useContext(RouterContext)
  if (!context) throw new Error("useRouter must be used inside AppRouterProvider")
  return context
}
