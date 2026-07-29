(() => {
  "use strict";

  const STORAGE_KEY = "calendar_data_v2";
  const WEEKDAYS_SHORT = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"];
  const WEEKDAYS_LONG = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"];
  const MONTHS = ["January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December"];
  const TYPE_LABELS = { event: "Event", goal: "Goal", routine: "Routine" };

  const today = new Date();
  today.setHours(0, 0, 0, 0);

  const state = {
    viewYear: today.getFullYear(),
    viewMonth: today.getMonth(),
    selectedDate: null,
    data: loadData(),
    selectedType: null,
    selectedRepeat: null,
    goalFrequency: "daily",
    eventRepeatDays: new Set(),
    eventForever: false,
  };

  // ---------- Elements ----------
  const monthTitleEl = document.getElementById("monthTitle");
  const daysGridEl = document.getElementById("daysGrid");
  const weekdaysRowEl = document.getElementById("weekdaysRow");
  const prevBtn = document.getElementById("prevBtn");
  const nextBtn = document.getElementById("nextBtn");
  const todayBtn = document.getElementById("todayBtn");
  const addEventBtn = document.getElementById("addEventBtn");

  const dayPanel = document.getElementById("dayPanel");
  const panelBackdrop = document.getElementById("panelBackdrop");
  const closePanelBtn = document.getElementById("closePanelBtn");
  const panelAddBtn = document.getElementById("panelAddBtn");
  const panelWeekday = document.getElementById("panelWeekday");
  const panelDate = document.getElementById("panelDate");
  const eventListEl = document.getElementById("eventList");
  const emptyStateEl = document.getElementById("emptyState");

  const todayPanel = document.getElementById("todayPanel");
  const toggleTodayPanelBtn = document.getElementById("toggleTodayPanelBtn");
  const closeTodayPanelBtn = document.getElementById("closeTodayPanelBtn");
  const todayPanelDate = document.getElementById("todayPanelDate");
  const todayEventListEl = document.getElementById("todayEventList");
  const todayEmptyStateEl = document.getElementById("todayEmptyState");
  const TODAY_PANEL_KEY = "calendar_today_panel_hidden";

  const modalBackdrop = document.getElementById("modalBackdrop");
  const addModal = document.getElementById("addModal");
  const closeModalBtn = document.getElementById("closeModalBtn");
  const addForm = document.getElementById("addForm");
  const formDate = document.getElementById("formDate");
  const typePicker = document.getElementById("typePicker");
  const repeatModeGroup = document.getElementById("repeatModeGroup");
  const repeatModeEl = document.getElementById("repeatMode");
  const repeatHint = document.getElementById("repeatHint");
  const eventRepeatGroup = document.getElementById("eventRepeatGroup");
  const eventWeekdayPicker = document.getElementById("eventWeekdayPicker");
  const eventForeverBtn = document.getElementById("eventForeverBtn");
  const timeFieldWrap = document.getElementById("timeFieldWrap");
  const formTime = document.getElementById("formTime");
  const goalRepeatGroup = document.getElementById("goalRepeatGroup");
  const goalFreqMode = document.getElementById("goalFreqMode");
  const singleTextWrap = document.getElementById("singleTextWrap");
  const singleTextLabel = document.getElementById("singleTextLabel");
  const formText = document.getElementById("formText");
  const cycleFieldWrap = document.getElementById("cycleFieldWrap");
  const cycleItemsEl = document.getElementById("cycleItems");
  const addCycleItemBtn = document.getElementById("addCycleItemBtn");
  const saveBtn = document.getElementById("saveBtn");

  const REPEAT_HINTS = {
    daily: "Repeats every single day starting from the date above.",
    weekly: `Repeats every week on the same weekday as the date above.`,
    cycle: "Add the sequence in order (e.g. Push, Pull, Legs). It repeats forever, one step per day, starting from the date above.",
  };

  // ---------- Storage ----------
  function loadData() {
    try {
      const raw = localStorage.getItem(STORAGE_KEY);
      const parsed = raw ? JSON.parse(raw) : null;
      return {
        singleEvents: (parsed && parsed.singleEvents) || {},
        routines: (parsed && parsed.routines) || [],
      };
    } catch (e) {
      return { singleEvents: {}, routines: [] };
    }
  }

  function saveData() {
    localStorage.setItem(STORAGE_KEY, JSON.stringify(state.data));
  }

  function uid() {
    return `${Date.now()}-${Math.random().toString(36).slice(2, 8)}`;
  }

  function pad(n) {
    return String(n).padStart(2, "0");
  }

  function dateKey(year, month, day) {
    return `${year}-${pad(month + 1)}-${pad(day)}`;
  }

  function parseDateKey(key) {
    const [y, m, d] = key.split("-").map(Number);
    const dt = new Date(y, m - 1, d);
    dt.setHours(0, 0, 0, 0);
    return dt;
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

  // ---------- Routine occurrence math ----------
  function getRoutineOccurrence(routine, key) {
    const target = parseDateKey(key);
    const start = parseDateKey(routine.startDate);
    if (target < start) return null;
    const dayDiff = Math.round((target - start) / 86400000);

    if (routine.repeat === "daily") {
      return { text: routine.text, time: routine.time };
    }
    if (routine.repeat === "weekly") {
      if (dayDiff % 7 !== 0) return null;
      return { text: routine.text, time: routine.time };
    }
    if (routine.repeat === "cycle") {
      const n = routine.items.length;
      if (n === 0) return null;
      const idx = ((dayDiff % n) + n) % n;
      return { text: routine.items[idx], time: routine.time };
    }
    if (routine.repeat === "monthly") {
      if (target.getDate() !== start.getDate()) return null;
      return { text: routine.text, time: routine.time };
    }
    if (routine.repeat === "yearly") {
      if (target.getDate() !== start.getDate() || target.getMonth() !== start.getMonth()) return null;
      return { text: routine.text, time: routine.time };
    }
    if (routine.repeat === "weekdays") {
      if (!routine.days.includes(target.getDay())) return null;
      return { text: routine.text, time: routine.time };
    }
    return null;
  }

  function getItemsForDate(key) {
    const items = [];
    (state.data.singleEvents[key] || []).forEach((ev) => {
      items.push({ id: ev.id, type: ev.type, time: ev.time, text: ev.text, source: "single" });
    });
    state.data.routines.forEach((r) => {
      const occ = getRoutineOccurrence(r, key);
      if (occ) {
        items.push({ id: r.id, type: r.type || "routine", time: occ.time, text: occ.text, source: "routine", repeat: r.repeat });
      }
    });
    items.sort((a, b) => {
      if (!a.time && !b.time) return 0;
      if (!a.time) return 1;
      if (!b.time) return -1;
      return a.time.localeCompare(b.time);
    });
    return items;
  }

  // ---------- Calendar rendering ----------
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
      const dayItems = getItemsForDate(key);

      const classes = ["day-cell"];
      if (otherMonth) classes.push("other-month");
      if (isToday) classes.push("today");
      if (isSelected) classes.push("selected");

      const dots = dayItems
        .slice(0, 3)
        .map((it) => `<span class="dot-${it.type}"></span>`)
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

  function todayKey() {
    return dateKey(today.getFullYear(), today.getMonth(), today.getDate());
  }

  // ---------- Day panel ----------
  function openPanel(year, month, day) {
    const key = dateKey(year, month, day);
    state.selectedDate = key;
    renderMonth();
    renderPanel(key);
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

  function renderItemsList(listEl, emptyEl, items) {
    if (items.length === 0) {
      listEl.innerHTML = "";
      emptyEl.style.display = "block";
      return;
    }
    emptyEl.style.display = "none";
    listEl.innerHTML = items
      .map(
        (it) => `
      <li class="event-item type-${it.type}" data-id="${it.id}" data-source="${it.source}">
        <div class="event-main">
          <span class="event-badge">${TYPE_LABELS[it.type]}</span>
          <span class="event-text">${escapeHtml(it.text)}</span>
        </div>
        ${it.time ? `<span class="event-time">${formatTime(it.time)}</span>` : ""}
        <button type="button" class="delete-btn" data-id="${it.id}" data-source="${it.source}" aria-label="Delete">&times;</button>
      </li>
    `
      )
      .join("");
  }

  function renderPanel(key) {
    const [y, m, d] = key.split("-").map(Number);
    const dt = new Date(y, m - 1, d);
    panelWeekday.textContent = WEEKDAYS_LONG[dt.getDay()];
    panelDate.textContent = `${MONTHS[m - 1]} ${d}, ${y}`;
    renderItemsList(eventListEl, emptyStateEl, getItemsForDate(key));
  }

  function refreshPanelIfOpen() {
    if (state.selectedDate) renderPanel(state.selectedDate);
  }

  function renderTodayPanel() {
    const key = todayKey();
    todayPanelDate.textContent = `${MONTHS[today.getMonth()]} ${today.getDate()}, ${today.getFullYear()}`;
    renderItemsList(todayEventListEl, todayEmptyStateEl, getItemsForDate(key));
  }

  function setTodayPanelHidden(hidden) {
    todayPanel.classList.toggle("collapsed", hidden);
    toggleTodayPanelBtn.setAttribute("aria-pressed", String(!hidden));
    localStorage.setItem(TODAY_PANEL_KEY, hidden ? "1" : "0");
  }

  function deleteSingleEvent(key, id) {
    if (!state.data.singleEvents[key]) return;
    state.data.singleEvents[key] = state.data.singleEvents[key].filter((ev) => ev.id !== id);
    if (state.data.singleEvents[key].length === 0) delete state.data.singleEvents[key];
    saveData();
  }

  function deleteRoutine(id) {
    state.data.routines = state.data.routines.filter((r) => r.id !== id);
    saveData();
  }

  // ---------- Add-event modal ----------
  function resetAddForm(presetKey) {
    state.selectedType = null;
    state.selectedRepeat = null;
    state.goalFrequency = "daily";
    state.eventRepeatDays = new Set();
    state.eventForever = false;
    formDate.value = presetKey || state.selectedDate || todayKey();
    formTime.value = "";
    formText.value = "";
    cycleItemsEl.innerHTML = "";
    addCycleRow();
    addCycleRow();
    addCycleRow();

    goalFreqMode.querySelectorAll(".seg-btn[data-freq]").forEach((b) => {
      b.classList.toggle("active", b.dataset.freq === "daily");
    });
    eventWeekdayPicker.querySelectorAll(".weekday-btn").forEach((b) => b.classList.remove("active"));
    eventForeverBtn.classList.remove("active");

    typePicker.querySelectorAll(".type-btn").forEach((b) => b.classList.remove("active"));
    repeatModeEl.querySelectorAll(".seg-btn").forEach((b) => b.classList.remove("active"));
    repeatModeGroup.hidden = true;
    repeatHint.textContent = "";
    eventRepeatGroup.hidden = true;
    timeFieldWrap.hidden = true;
    goalRepeatGroup.hidden = true;
    singleTextWrap.hidden = true;
    cycleFieldWrap.hidden = true;
    saveBtn.disabled = true;
  }

  function addCycleRow(value) {
    const row = document.createElement("div");
    row.className = "cycle-row";
    row.innerHTML = `
      <span class="cycle-index"></span>
      <input type="text" class="cycle-input" placeholder="e.g. Push" maxlength="60" />
      <button type="button" class="remove-cycle-btn" aria-label="Remove">&times;</button>
    `;
    row.querySelector(".cycle-input").value = value || "";
    cycleItemsEl.appendChild(row);
    renumberCycleRows();
  }

  function renumberCycleRows() {
    cycleItemsEl.querySelectorAll(".cycle-row").forEach((row, i) => {
      row.querySelector(".cycle-index").textContent = i + 1;
    });
  }

  function updateFieldsForType() {
    const type = state.selectedType;
    repeatModeGroup.hidden = type !== "routine";
    goalRepeatGroup.hidden = type !== "goal";
    eventRepeatGroup.hidden = type !== "event";

    if (type === "routine") {
      const repeat = state.selectedRepeat;
      timeFieldWrap.hidden = !repeat;
      singleTextWrap.hidden = !(repeat === "daily" || repeat === "weekly");
      cycleFieldWrap.hidden = repeat !== "cycle";
      singleTextLabel.textContent = "Routine name";
      formText.placeholder = "e.g. Morning run";
      repeatHint.textContent = repeat ? REPEAT_HINTS[repeat] : "";
    } else if (type === "event") {
      timeFieldWrap.hidden = false;
      singleTextWrap.hidden = false;
      cycleFieldWrap.hidden = true;
      singleTextLabel.textContent = "Description";
      formText.placeholder = "What's this for?";
    } else if (type === "goal") {
      timeFieldWrap.hidden = true;
      singleTextWrap.hidden = false;
      cycleFieldWrap.hidden = true;
      singleTextLabel.textContent = "Goal";
      formText.placeholder = "What's the goal?";
    } else {
      timeFieldWrap.hidden = true;
      singleTextWrap.hidden = true;
      cycleFieldWrap.hidden = true;
    }

    updateSaveEnabled();
  }

  function updateSaveEnabled() {
    const type = state.selectedType;
    if (!type || !formDate.value) {
      saveBtn.disabled = true;
      return;
    }
    if (type === "event" || type === "goal") {
      saveBtn.disabled = formText.value.trim().length === 0;
      return;
    }
    if (type === "routine") {
      if (!state.selectedRepeat) {
        saveBtn.disabled = true;
        return;
      }
      if (state.selectedRepeat === "cycle") {
        const values = Array.from(cycleItemsEl.querySelectorAll(".cycle-input"))
          .map((i) => i.value.trim())
          .filter(Boolean);
        saveBtn.disabled = values.length === 0;
      } else {
        saveBtn.disabled = formText.value.trim().length === 0;
      }
    }
  }

  function openAddModal(presetKey) {
    resetAddForm(presetKey);
    addModal.classList.add("open");
    addModal.setAttribute("aria-hidden", "false");
    modalBackdrop.classList.add("visible");
  }

  function closeAddModal() {
    addModal.classList.remove("open");
    addModal.setAttribute("aria-hidden", "true");
    modalBackdrop.classList.remove("visible");
  }

  function submitAddForm(e) {
    e.preventDefault();
    const type = state.selectedType;
    const key = formDate.value;
    if (!type || !key) return;

    if (type === "event") {
      const text = formText.value.trim();
      if (!text) return;
      if (state.eventForever && state.eventRepeatDays.size > 0) {
        state.data.routines.push({
          id: uid(),
          type: "event",
          repeat: "weekdays",
          days: Array.from(state.eventRepeatDays).sort(),
          startDate: key,
          time: formTime.value || null,
          text,
        });
      } else {
        if (!state.data.singleEvents[key]) state.data.singleEvents[key] = [];
        state.data.singleEvents[key].push({
          id: uid(),
          type,
          time: formTime.value || null,
          text,
        });
      }
    } else if (type === "goal") {
      const text = formText.value.trim();
      if (!text) return;
      state.data.routines.push({
        id: uid(),
        type: "goal",
        repeat: state.goalFrequency,
        startDate: key,
        time: null,
        text,
      });
    } else if (type === "routine") {
      const repeat = state.selectedRepeat;
      if (!repeat) return;
      if (repeat === "cycle") {
        const items = Array.from(cycleItemsEl.querySelectorAll(".cycle-input"))
          .map((i) => i.value.trim())
          .filter(Boolean);
        if (items.length === 0) return;
        state.data.routines.push({
          id: uid(),
          type: "routine",
          repeat: "cycle",
          startDate: key,
          time: formTime.value || null,
          items,
        });
      } else {
        const text = formText.value.trim();
        if (!text) return;
        state.data.routines.push({
          id: uid(),
          type: "routine",
          repeat,
          startDate: key,
          time: formTime.value || null,
          text,
        });
      }
    }

    saveData();
    closeAddModal();
    renderMonth();
    refreshPanelIfOpen();
    renderTodayPanel();
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
  panelBackdrop.addEventListener("click", () => {
    if (addModal.classList.contains("open")) {
      closeAddModal();
    } else {
      closePanel();
    }
  });

  panelAddBtn.addEventListener("click", () => openAddModal(state.selectedDate));
  addEventBtn.addEventListener("click", () => openAddModal(state.selectedDate || todayKey()));
  closeModalBtn.addEventListener("click", closeAddModal);
  modalBackdrop.addEventListener("click", closeAddModal);

  eventListEl.addEventListener("click", (e) => {
    const btn = e.target.closest(".delete-btn");
    if (!btn || !state.selectedDate) return;
    const { id, source } = btn.dataset;
    if (source === "routine") {
      const ok = window.confirm("This removes the routine from every day it repeats on, not just this one. Continue?");
      if (!ok) return;
      deleteRoutine(id);
    } else {
      deleteSingleEvent(state.selectedDate, id);
    }
    renderPanel(state.selectedDate);
    renderMonth();
    renderTodayPanel();
  });

  todayEventListEl.addEventListener("click", (e) => {
    const btn = e.target.closest(".delete-btn");
    if (!btn) return;
    const { id, source } = btn.dataset;
    if (source === "routine") {
      const ok = window.confirm("This removes the routine from every day it repeats on, not just this one. Continue?");
      if (!ok) return;
      deleteRoutine(id);
    } else {
      deleteSingleEvent(todayKey(), id);
    }
    renderTodayPanel();
    renderMonth();
    refreshPanelIfOpen();
  });

  toggleTodayPanelBtn.addEventListener("click", () => {
    setTodayPanelHidden(!todayPanel.classList.contains("collapsed"));
  });

  closeTodayPanelBtn.addEventListener("click", () => setTodayPanelHidden(true));

  typePicker.addEventListener("click", (e) => {
    const btn = e.target.closest(".type-btn");
    if (!btn) return;
    typePicker.querySelectorAll(".type-btn").forEach((b) => b.classList.remove("active"));
    btn.classList.add("active");
    state.selectedType = btn.dataset.type;
    state.selectedRepeat = null;
    repeatModeEl.querySelectorAll(".seg-btn").forEach((b) => b.classList.remove("active"));
    updateFieldsForType();
  });

  goalFreqMode.addEventListener("click", (e) => {
    const btn = e.target.closest(".seg-btn");
    if (!btn) return;
    goalFreqMode.querySelectorAll(".seg-btn[data-freq]").forEach((b) => b.classList.remove("active"));
    btn.classList.add("active");
    state.goalFrequency = btn.dataset.freq;
  });

  eventWeekdayPicker.addEventListener("click", (e) => {
    const btn = e.target.closest(".weekday-btn");
    if (!btn) return;
    const day = Number(btn.dataset.day);
    if (state.eventRepeatDays.has(day)) {
      state.eventRepeatDays.delete(day);
      btn.classList.remove("active");
    } else {
      state.eventRepeatDays.add(day);
      btn.classList.add("active");
    }
  });

  eventForeverBtn.addEventListener("click", () => {
    state.eventForever = !state.eventForever;
    eventForeverBtn.classList.toggle("active", state.eventForever);
    if (state.eventForever && state.eventRepeatDays.size === 0 && formDate.value) {
      const day = parseDateKey(formDate.value).getDay();
      state.eventRepeatDays.add(day);
      const btn = eventWeekdayPicker.querySelector(`.weekday-btn[data-day="${day}"]`);
      if (btn) btn.classList.add("active");
    }
  });

  repeatModeEl.addEventListener("click", (e) => {
    const btn = e.target.closest(".seg-btn");
    if (!btn) return;
    repeatModeEl.querySelectorAll(".seg-btn").forEach((b) => b.classList.remove("active"));
    btn.classList.add("active");
    state.selectedRepeat = btn.dataset.repeat;
    updateFieldsForType();
  });

  addCycleItemBtn.addEventListener("click", () => {
    addCycleRow();
    updateSaveEnabled();
  });

  cycleItemsEl.addEventListener("click", (e) => {
    const btn = e.target.closest(".remove-cycle-btn");
    if (!btn) return;
    btn.closest(".cycle-row").remove();
    renumberCycleRows();
    updateSaveEnabled();
  });

  cycleItemsEl.addEventListener("input", updateSaveEnabled);
  formText.addEventListener("input", updateSaveEnabled);
  formDate.addEventListener("input", updateSaveEnabled);

  addForm.addEventListener("submit", submitAddForm);

  document.addEventListener("keydown", (e) => {
    const tag = document.activeElement && document.activeElement.tagName;
    const typing = tag === "INPUT" || tag === "TEXTAREA";

    if (e.key === "Escape") {
      if (addModal.classList.contains("open")) {
        closeAddModal();
      } else if (dayPanel.classList.contains("open")) {
        closePanel();
      }
      return;
    }
    if (typing) return;

    if (e.key === "ArrowLeft") changeMonth(-1);
    if (e.key === "ArrowRight") changeMonth(1);
  });

  // ---------- Init ----------
  setTodayPanelHidden(localStorage.getItem(TODAY_PANEL_KEY) === "1");
  renderWeekdaysRow();
  renderMonth();
  renderTodayPanel();
})();
