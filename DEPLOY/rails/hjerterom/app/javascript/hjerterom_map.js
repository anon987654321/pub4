function escapeHtml(value) {
  return String(value || "")
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;");
}

function parsePoints(raw) {
  try {
    const points = JSON.parse(raw || "[]");
    return Array.isArray(points) ? points : [];
  } catch (_error) {
    return [];
  }
}

function logoClone(className) {
  const template = document.getElementById("hjerterom-logo-template");
  const wrap = document.createElement("span");
  wrap.className = className;

  if (!template) return wrap;

  const logo = template.content.firstElementChild?.cloneNode(true);
  if (logo) wrap.appendChild(logo);
  return wrap;
}

function heartMarker(point) {
  const wrap = document.createElement("a");
  wrap.href = point.url || "#";
  wrap.className = `hjerterom-heart-marker hjerterom-heart-marker--${point.type || "resource"}`;
  wrap.setAttribute("aria-label", point.title || "Hjerterom punkt");
  wrap.appendChild(logoClone("hjerterom-heart-marker__logo"));
  return wrap;
}

function popupHtml(point) {
  return `
    <div class="map-popup">
      <strong>${escapeHtml(point.title)}</strong>
      <p>${escapeHtml(point.subtitle || "Åsane")}</p>
      <a href="${escapeHtml(point.url)}">Åpne</a>
    </div>
  `;
}

function fallbackMap(root, points) {
  const canvas = root.querySelector("#hjerterom-map");
  if (!canvas) return;
  canvas.innerHTML = "";
  canvas.classList.add("map-home__fallback");

  const logo = logoClone("hjerterom-heart-logo");

  const list = document.createElement("div");
  list.className = "map-home__fallback-list";
  list.innerHTML = points.map(point => `
    <a class="map-home__pin-card" href="${escapeHtml(point.url)}">
      <span>${point.type === "food" ? "Mat" : "Ressurs"}</span>
      <strong>${escapeHtml(point.title)}</strong>
      <small>${escapeHtml(point.subtitle || "Åsane")}</small>
    </a>
  `).join("") || "<p>Ingen kartpunkter ennå.</p>";

  canvas.append(logo, list);
}

function initMapbox(root, points, token) {
  const canvas = root.querySelector("#hjerterom-map");
  if (!canvas || !window.mapboxgl || !token) return false;

  window.mapboxgl.accessToken = token;
  const map = new window.mapboxgl.Map({
    container: canvas,
    style: "mapbox://styles/mapbox/standard",
    center: [5.3256, 60.4669],
    zoom: 11.7,
    pitch: 56,
    bearing: -18,
    antialias: true
  });

  map.addControl(new window.mapboxgl.NavigationControl({ visualizePitch: true }), "bottom-right");
  map.addControl(new window.mapboxgl.GeolocateControl({
    positionOptions: { enableHighAccuracy: true },
    trackUserLocation: true,
    showUserHeading: true
  }), "bottom-right");

  points.forEach(point => {
    const marker = heartMarker(point);
    new window.mapboxgl.Marker({ element: marker, anchor: "bottom" })
      .setLngLat([Number(point.lng), Number(point.lat)])
      .setPopup(new window.mapboxgl.Popup({ offset: 28 }).setHTML(popupHtml(point)))
      .addTo(map);
  });

  return true;
}

function bootHjerteromMap() {
  const root = document.querySelector(".map-home");
  if (!root) return;

  const points = parsePoints(root.dataset.mapPoints);
  const token = root.dataset.mapboxToken;
  if (!initMapbox(root, points, token)) fallbackMap(root, points);
}

document.addEventListener("turbo:load", bootHjerteromMap);
document.addEventListener("DOMContentLoaded", bootHjerteromMap);
