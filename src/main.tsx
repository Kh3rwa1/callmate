import { StrictMode } from "react"
import { createRoot } from "react-dom/client"

import "./index.css"
import App from "./App.tsx"

// Bright mode only: the app never applies the `dark` class, and this guards
// against a stale preference left by an earlier build.
document.documentElement.classList.remove("dark")
document.documentElement.classList.add("light")

createRoot(document.getElementById("root")!).render(
  <StrictMode>
    <App />
  </StrictMode>
)
