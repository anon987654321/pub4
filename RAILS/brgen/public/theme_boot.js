/* FOUC guard: apply saved light theme before .theme-root paints. */
(function () {
  try {
    if (localStorage.getItem("brgen-theme") === "light") {
      const el = document.getElementById("dark-toggle")
      if (el) el.checked = true
    }
  } catch (e) {}
})()
