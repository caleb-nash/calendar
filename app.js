(() => {
  "use strict";

  const STORAGE_KEY = "calendar_events_v1";
  const WEEKDAYS_SHORT = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"];
  const WEEKDAYS_LONG = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"];
  const MONTHS = ["January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December"];

  const today = new Date();
  today.setHours(0, 0, 0, 0);

  const state = {
    viewYear: today.getFullYear(),
    viewMonth: today.getMonth(),
    selectedDate: null,
    events: loadEvents(),
  };

  const monthTitleEl = document.getElementById("monthTitle");
  const daysGridEl = document.getElementById("daysGrid");
  const weekdaysRowEl = document.getElementById("weekdaysRow");
  const prevBtn = document.getElementById("prevBtn");
  const nextBtn = document.getElementById("nextBtn");
  const todayBtn = document.getElementById("todayBtn");

  const dayPanel = document.getElementById("dayPanel");
  const panelBackdrop = document.getElementById("panelBackdrop");
  const closePanelBtn = document.getElementById("closePanelBtn");
  const panelWeekday = document.getElementById("panelWeekday");
  const panelDate = document.getElementById("panelDate");
  const eventListEl = document.getElementById("eventList");
  const emptyStateEl = document.getElementById("emptyState");
  const addEventForm = document.getElementById("addEventForm");
  const eventTimeInput = document.getElementById("eventTime");
  const eventTextInput = document.getElementById("eventText");

  function loadEvents() {
    try {
      const raw = localStorage.getItem(STORAGE_KEY);
      return raw ? JSON.parse(raw) : {};
    } catch (e) {
      return {};
    }
  }

  function saveEvents() {
    localStorage.setItem(STORAGE_KEY, JSON.stringify(state.events));
  }

  function pad(n) {
    return String(n).padStart(2, "0");
  }

  function dateKey(year, month, day) {
    return `${year}-${pad(month + 1)}-${pad(day)}`;
  }

  function renderWeekdaysRow() {
    weekdaysRowEl.innerHTML = WEEKDAYS_SHORT.map((d) => `<span>${d}</span>`).join("");
  }

  function renderMonth() {
    monthTitleEl.textContent = `${MONTHS[state.viewMonth]} ${state.viewYear}`;

    const firstOfMonth = new Date(state.viewYear, state.viewMonth, 1);
    const startOffset = firstOfMonth.getDay();
    const daysInMonth = new Date(state.viewYear, state.viewMonth + 1, 0).getDate();
    const daysInPrevMonth = new Date(state.viewYear, state.viewMonth, 0).getDate();

    const totalCells = Math.ceil((startOffset + daysInMonth) / 7) * 7;

    const cells = [];
    for (let i = 0; i < totalCells; i++) {
      const dayOffset = i - startOffset + 1;
      let year = state.viewYear;
      let month = state.viewMonth;
      let day = dayOffset;
      let otherMonth = false;

      if (dayOffset < 1) {
        month = state.viewMonth - 1;
        year = month < 0 ? state.viewYear - 1 : state.viewYear;
        month = (month + 12) % 12;
        day = daysInPrevMonth + dayOffset;
        otherMonth = true;
      } else if (dayOffset > daysInMonth) {
        day = dayOffset - daysInMonth;
        month = state.viewMonth + 1;
        year = month > 11 ? state.viewYear + 1 : state.viewYear;
        month = month % 12;
        otherMonth = true;
      }

      const key = dateKey(year, month, day);
      const cellDate = new Date(year, month, day);
      cellDate.setHours(0, 0, 0, 0);
      const isToday = cellDate.getTime() === today.getTime();
      const isSelected = state.selectedDate === key;
      const eventCount = (state.events[key] || []).length;

      const classes = ["day-cell"];
      if (otherMonth) classes.push("other-month");
      if (isToday) classes.push("today");
      if (isSelected) classes.push("selected");

      const dots = Array.from({ length: Math.min(eventCount, 3) })
        .map(() => "<span></span>")
        .join("");

      cells.push(`
        <button type="button" class="${classes.join(" ")}" data-key="${key}" data-year="${year}" data-month="${month}" data-day="${day}">
          <span class="day-num">${day}</span>
          <span class="event-dots">${dots}</span>
        </button>
      `);
    }

    daysGridEl.innerHTML = cells.join("");
  }

  function changeMonth(delta) {
    state.viewMonth += delta;
    if (state.viewMonth < 0) {
      state.viewMonth = 11;
      state.viewYear -= 1;
    } else if (state.viewMonth > 11) {
      state.viewMonth = 0;
      state.viewYear += 1;
    }
    renderMonth();
  }

  function goToToday() {
    state.viewYear = today.getFullYear();
    state.viewMonth = today.getMonth();
    renderMonth();
  }

  function openPanel(year, month, day) {
    const key = dateKey(year, month, day);
    state.selectedDate = key;
    renderMonth();
    renderPanel(year, month, day);
    dayPanel.classList.add("open");
    dayPanel.setAttribute("aria-hidden", "false");
    panelBackdrop.classList.add("visible");
  }

  function closePanel() {
    dayPanel.classList.remove("open");
    dayPanel.setAttribute("aria-hidden", "true");
    panelBackdrop.classList.remove("visible");
    state.selectedDate = null;
    renderMonth();
  }

  function renderPanel(year, month, day) {
    const key = dateKey(year, month, day);
    const d = new Date(year, month, day);
    panelWeekday.textContent = WEEKDAYS_LONG[d.getDay()];
    panelDate.textContent = `${MONTHS[month]} ${day}, ${year}`;

    const events = (state.events[key] || []).slice().sort((a, b) => {
      if (!a.time) return 1;
      if (!b.time) return -1;
      return a.time.localeCompare(b.time);
    });

    if (events.length === 0) {
      eventListEl.innerHTML = "";
      emptyStateEl.style.display = "block";
    } else {
      emptyStateEl.style.display = "none";
      eventListEl.innerHTML = events
        .map(
          (ev) => `
        <li class="event-item" data-id="${ev.id}">
          ${ev.time ? `<span class="event-time">${formatTime(ev.time)}</span>` : ""}
          <span class="event-text">${escapeHtml(ev.text)}</span>
          <button type="button" class="delete-btn" data-id="${ev.id}" aria-label="Delete event">&times;</button>
        </li>
      `
        )
        .join("");
    }
  }

  function formatTime(time24) {
    const [h, m] = time24.split(":").map(Number);
    const period = h >= 12 ? "PM" : "AM";
    const h12 = h % 12 === 0 ? 12 : h % 12;
    return `${h12}:${pad(m)} ${period}`;
  }

  function escapeHtml(str) {
    const div = document.createElement("div");
    div.textContent = str;
    return div.innerHTML;
  }

  function addEvent(key, time, text) {
    if (!state.events[key]) state.events[key] = [];
    state.events[key].push({
      id: `${Date.now()}-${Math.random().toString(36).slice(2, 8)}`,
      time: time || null,
      text,
    });
    saveEvents();
  }

  function deleteEvent(key, id) {
    if (!state.events[key]) return;
    state.events[key] = state.events[key].filter((ev) => ev.id !== id);
    if (state.events[key].length === 0) delete state.events[key];
    saveEvents();
  }

  // ---------- Event listeners ----------
  prevBtn.addEventListener("click", () => changeMonth(-1));
  nextBtn.addEventListener("click", () => changeMonth(1));
  todayBtn.addEventListener("click", goToToday);

  daysGridEl.addEventListener("click", (e) => {
    const cell = e.target.closest(".day-cell");
    if (!cell) return;
    const { year, month, day } = cell.dataset;
    openPanel(Number(year), Number(month), Number(day));
  });

  closePanelBtn.addEventListener("click", closePanel);
  panelBackdrop.addEventListener("click", closePanel);

  addEventForm.addEventListener("submit", (e) => {
    e.preventDefault();
    const text = eventTextInput.value.trim();
    if (!text || !state.selectedDate) return;
    addEvent(state.selectedDate, eventTimeInput.value, text);
    eventTextInput.value = "";
    eventTimeInput.value = "";
    eventTextInput.focus();
    const [y, m, d] = state.selectedDate.split("-").map(Number);
    renderPanel(y, m - 1, d);
    renderMonth();
  });

  eventListEl.addEventListener("click", (e) => {
    const btn = e.target.closest(".delete-btn");
    if (!btn || !state.selectedDate) return;
    deleteEvent(state.selectedDate, btn.dataset.id);
    const [y, m, d] = state.selectedDate.split("-").map(Number);
    renderPanel(y, m - 1, d);
    renderMonth();
  });

  document.addEventListener("keydown", (e) => {
    const tag = document.activeElement && document.activeElement.tagName;
    const typing = tag === "INPUT" || tag === "TEXTAREA";

    if (e.key === "Escape" && dayPanel.classList.contains("open")) {
      closePanel();
      return;
    }
    if (typing) return;

    if (e.key === "ArrowLeft") changeMonth(-1);
    if (e.key === "ArrowRight") changeMonth(1);
  });

  // ---------- Init ----------
  renderWeekdaysRow();
  renderMonth();
})();
