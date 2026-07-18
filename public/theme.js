// Apply saved theme before paint to avoid light/dark flash.
(() => {
  const storageKey = "theme"
  const root = document.documentElement
  const stored = localStorage.getItem(storageKey)
  const prefersDark = window.matchMedia("(prefers-color-scheme: dark)").matches
  const useDark = stored === "dark" || (stored !== "light" && prefersDark)

  root.classList.toggle("dark", useDark)
  root.classList.remove("light")
})()
