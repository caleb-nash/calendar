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
    eventRepeatWeeks: null,
    multiDayPicking: false,
    multiDayTime: null,
    multiDaySelectedDates: new Set(),
    miniCalYear: today.getFullYear(),
    miniCalMonth: today.getMonth(),
    viewMode: "day",
    sidebarCalYear: today.getFullYear(),
    sidebarCalMonth: today.getMonth(),
  };

  // ---------- Elements ----------
  const monthTitleEl = document.getElementById("monthTitle");
  const daysGridEl = document.getElementById("daysGrid");
  const weekdaysRowEl = document.getElementById("weekdaysRow");
  const prevBtn = document.getElementById("prevBtn");
  const nextBtn = document.getElementById("nextBtn");
  const todayBtn = document.getElementById("todayBtn");
  const addEventBtn = document.getElementById("addEventBtn");
  const exportDataBtn = document.getElementById("exportDataBtn");
  const importDataBtn = document.getElementById("importDataBtn");
  const importFileInput = document.getElementById("importFileInput");
  const viewToggleBtn = document.getElementById("viewToggleBtn");
  const monthView = document.getElementById("monthView");
  const dayView = document.getElementById("dayView");
  const dayPrevBtn = document.getElementById("dayPrevBtn");
  const dayNextBtn = document.getElementById("dayNextBtn");
  const dayTodayBtn = document.getElementById("dayTodayBtn");
  const dayViewTitle = document.getElementById("dayViewTitle");
  const dayViewAllDay = document.getElementById("dayViewAllDay");
  const dayViewTimeline = document.getElementById("dayViewTimeline");

  const todayPanel = document.getElementById("todayPanel");
  const toggleTodayPanelBtn = document.getElementById("toggleTodayPanelBtn");
  const closeTodayPanelBtn = document.getElementById("closeTodayPanelBtn");
  const todayPanelAddBtn = document.getElementById("todayPanelAddBtn");
  const todayPanelLabel = document.getElementById("todayPanelLabel");
  const todayPanelDate = document.getElementById("todayPanelDate");
  const todayEventListEl = document.getElementById("todayEventList");
  const todayEmptyStateEl = document.getElementById("todayEmptyState");
  const sidebarCalPrev = document.getElementById("sidebarCalPrev");
  const sidebarCalNext = document.getElementById("sidebarCalNext");
  const sidebarCalTitle = document.getElementById("sidebarCalTitle");
  const sidebarCalGrid = document.getElementById("sidebarCalGrid");
  const TODAY_PANEL_KEY = "calendar_today_panel_hidden";

  const modalBackdrop = document.getElementById("modalBackdrop");
  const addModal = document.getElementById("addModal");
  const closeModalBtn = document.getElementById("closeModalBtn");
  const addForm = document.getElementById("addForm");
  const formDate = document.getElementById("formDate");
  const miniCalToggle = document.getElementById("miniCalToggle");
  const miniCalendar = document.getElementById("miniCalendar");
  const miniCalTitle = document.getElementById("miniCalTitle");
  const miniCalGrid = document.getElementById("miniCalGrid");
  const miniCalPrev = document.getElementById("miniCalPrev");
  const miniCalNext = document.getElementById("miniCalNext");
  const typePicker = document.getElementById("typePicker");
  const repeatModeGroup = document.getElementById("repeatModeGroup");
  const repeatModeEl = document.getElementById("repeatMode");
  const repeatHint = document.getElementById("repeatHint");
  const eventRepeatGroup = document.getElementById("eventRepeatGroup");
  const eventWeekdayPicker = document.getElementById("eventWeekdayPicker");
  const eventForeverBtn = document.getElementById("eventForeverBtn");
  const eventWeeksInput = document.getElementById("eventWeeksInput");
  const timeFieldWrap = document.getElementById("timeFieldWrap");
  const formTime = document.getElementById("formTime");
  const goalRepeatGroup = document.getElementById("goalRepeatGroup");
  const goalFreqMode = document.getElementById("goalFreqMode");
  const goalFreqHint = document.getElementById("goalFreqHint");
  const singleTextWrap = document.getElementById("singleTextWrap");
  const singleTextLabel = document.getElementById("singleTextLabel");
  const formText = document.getElementById("formText");
  const cycleFieldWrap = document.getElementById("cycleFieldWrap");
  const cycleItemsEl = document.getElementById("cycleItems");
  const addCycleItemBtn = document.getElementById("addCycleItemBtn");
  const saveBtn = document.getElementById("saveBtn");

  const multiDayBtn = document.getElementById("multiDayBtn");
  const multiDayBar = document.getElementById("multiDayBar");
  const multiDayTextInput = document.getElementById("multiDayTextInput");
  const multiDayCount = document.getElementById("multiDayCount");
  const multiDayCancelBtn = document.getElementById("multiDayCancelBtn");
  const multiDaySaveBtn = document.getElementById("multiDaySaveBtn");

  const REPEAT_HINTS = {
    daily: "Repeats every single day starting from the date above.",
    weekly: `Repeats every week on the same weekday as the date above.`,
    cycle: "Add the sequence in order (e.g. Push, Pull, Legs). It repeats forever, one step per day, starting from the date above.",
  };

  const GOAL_FREQ_HINTS = {
    daily: "Stays through the rest of the day, starting from the date above.",
    weekly: "Stays through the rest of that week (until Saturday), starting from the date above.",
    monthly: "Stays through the rest of that month, starting from the date above.",
    yearly: "Stays through the rest of that year, starting from the date above.",
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

  function exportData() {
    const blob = new Blob([JSON.stringify(state.data, null, 2)], { type: "application/json" });
    const url = URL.createObjectURL(blob);
    const a = document.createElement("a");
    a.href = url;
    a.download = `calendar-backup-${todayKey()}.json`;
    document.body.appendChild(a);
    a.click();
    a.remove();
    URL.revokeObjectURL(url);
  }

  function importData(file) {
    const reader = new FileReader();
    reader.onload = () => {
      let parsed;
      try {
        parsed = JSON.parse(reader.result);
      } catch (e) {
        window.alert("That file isn't valid JSON.");
        return;
      }
      if (!parsed || typeof parsed !== "object" || !parsed.singleEvents || !Array.isArray(parsed.routines)) {
        window.alert("That doesn't look like a calendar backup file.");
        return;
      }
      state.data = {
        singleEvents: parsed.singleEvents,
        routines: parsed.routines,
      };
      saveData();
      resetToToday();
      window.alert("Calendar restored from backup.");
    };
    reader.readAsText(file);
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
  function getGoalOccurrence(routine, target, start) {
    let endDate;
    if (routine.repeat === "daily") {
      endDate = start;
    } else if (routine.repeat === "weekly") {
      endDate = new Date(start.getFullYear(), start.getMonth(), start.getDate() + (6 - start.getDay()));
    } else if (routine.repeat === "monthly") {
      endDate = new Date(start.getFullYear(), start.getMonth() + 1, 0);
    } else if (routine.repeat === "yearly") {
      endDate = new Date(start.getFullYear(), 11, 31);
    } else {
      return null;
    }
    if (target > endDate) return null;
    return { text: routine.text, time: routine.time };
  }

  function getRoutineOccurrence(routine, key) {
    const target = parseDateKey(key);
    const start = parseDateKey(routine.startDate);
    if (target < start) return null;

    if (routine.type === "goal") {
      return getGoalOccurrence(routine, target, start);
    }

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
      if (routine.weeks && dayDiff >= routine.weeks * 7) return null;
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
      if (state.multiDayPicking && state.multiDaySelectedDates.has(key)) classes.push("multi-picked");

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

  function todayKey() {
    return dateKey(today.getFullYear(), today.getMonth(), today.getDate());
  }

  function currentPanelKey() {
    return state.selectedDate || todayKey();
  }

  function selectDate(key) {
    state.selectedDate = key;
    const d = parseDateKey(key);
    state.viewYear = d.getFullYear();
    state.viewMonth = d.getMonth();
    state.sidebarCalYear = d.getFullYear();
    state.sidebarCalMonth = d.getMonth();
    renderMonth();
    renderTodayPanel();
    renderSidebarCalendar();
    renderDayView();
  }

  function resetToToday() {
    state.selectedDate = null;
    state.viewYear = today.getFullYear();
    state.viewMonth = today.getMonth();
    state.sidebarCalYear = today.getFullYear();
    state.sidebarCalMonth = today.getMonth();
    renderMonth();
    renderTodayPanel();
    renderSidebarCalendar();
    renderDayView();
  }

  // ---------- Info panel ----------
  function itemInnerHtml(it) {
    return `
      <div class="event-main">
        <span class="event-badge">${TYPE_LABELS[it.type]}</span>
        <span class="event-text">${escapeHtml(it.text)}</span>
      </div>
      ${it.time ? `<span class="event-time">${formatTime(it.time)}</span>` : ""}
      ${
        it.type === "goal"
          ? `<button type="button" class="complete-btn" data-id="${it.id}" data-source="${it.source}" aria-label="Mark goal complete"><svg class="check-icon" viewBox="0 0 24 24" width="14" height="14" aria-hidden="true"><path d="M5 13l4 4L19 7" fill="none" stroke="currentColor" stroke-width="3" stroke-linecap="round" stroke-linejoin="round"/></svg></button>`
          : `<button type="button" class="delete-btn" data-id="${it.id}" data-source="${it.source}" aria-label="Delete">&times;</button>`
      }
    `;
  }

  function renderItemsList(listEl, emptyEl, items) {
    if (items.length === 0) {
      listEl.innerHTML = "";
      emptyEl.style.display = "block";
      return;
    }
    emptyEl.style.display = "none";
    listEl.innerHTML = items
      .map((it) => `<li class="event-item type-${it.type}" data-id="${it.id}" data-source="${it.source}">${itemInnerHtml(it)}</li>`)
      .join("");
  }

  function renderTodayPanel() {
    const key = currentPanelKey();
    const [y, m, d] = key.split("-").map(Number);
    const dt = new Date(y, m - 1, d);
    todayPanelLabel.textContent = key === todayKey() ? "Today" : WEEKDAYS_LONG[dt.getDay()];
    todayPanelDate.textContent = `${MONTHS[m - 1]} ${d}, ${y}`;
    renderItemsList(todayEventListEl, todayEmptyStateEl, getItemsForDate(key));
  }

  // ---------- Day view ----------
  function formatHourLabel(hour) {
    const period = hour >= 12 ? "PM" : "AM";
    const h12 = hour % 12 === 0 ? 12 : hour % 12;
    return `${h12} ${period}`;
  }

  function dayItemHtml(it) {
    return `<div class="event-item compact type-${it.type}" data-id="${it.id}" data-source="${it.source}">${itemInnerHtml(it)}</div>`;
  }

  function renderDayView() {
    const key = currentPanelKey();
    const [y, m, d] = key.split("-").map(Number);
    const dt = new Date(y, m - 1, d);
    dayViewTitle.textContent = `${WEEKDAYS_LONG[dt.getDay()]}, ${MONTHS[m - 1]} ${d}`;

    const items = getItemsForDate(key);
    const allDayItems = items.filter((it) => !it.time);
    const timedItems = items.filter((it) => it.time);

    dayViewAllDay.innerHTML = allDayItems.map((it) => dayItemHtml(it)).join("");

    const hourBuckets = Array.from({ length: 24 }, () => []);
    timedItems.forEach((it) => {
      const hour = parseInt(it.time.split(":")[0], 10);
      hourBuckets[hour].push(it);
    });

    dayViewTimeline.innerHTML = hourBuckets
      .map(
        (bucketItems, hour) => `
      <div class="day-hour-row">
        <div class="day-hour-label">${formatHourLabel(hour)}</div>
        <div class="day-hour-content">${bucketItems.map((it) => dayItemHtml(it)).join("")}</div>
      </div>
    `
      )
      .join("");
  }

  function setViewMode(mode) {
    state.viewMode = mode;
    monthView.hidden = mode !== "month";
    dayView.hidden = mode !== "day";
    viewToggleBtn.textContent = mode === "day" ? "Month view" : "Day view";
    renderMonth();
    renderDayView();
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

  // ---------- Mini calendar (date picker) ----------
  function buildMiniCalCells(y, m, selectedKey) {
    const firstOfMonth = new Date(y, m, 1);
    const startOffset = firstOfMonth.getDay();
    const daysInMonth = new Date(y, m + 1, 0).getDate();
    const daysInPrevMonth = new Date(y, m, 0).getDate();
    const totalCells = Math.ceil((startOffset + daysInMonth) / 7) * 7;

    const cells = [];
    for (let i = 0; i < totalCells; i++) {
      const dayOffset = i - startOffset + 1;
      let year = y;
      let month = m;
      let day = dayOffset;
      let otherMonth = false;

      if (dayOffset < 1) {
        month = m - 1;
        year = month < 0 ? y - 1 : y;
        month = (month + 12) % 12;
        day = daysInPrevMonth + dayOffset;
        otherMonth = true;
      } else if (dayOffset > daysInMonth) {
        day = dayOffset - daysInMonth;
        month = m + 1;
        year = month > 11 ? y + 1 : y;
        month = month % 12;
        otherMonth = true;
      }

      const key = dateKey(year, month, day);
      const cellDate = new Date(year, month, day);
      cellDate.setHours(0, 0, 0, 0);
      const isToday = cellDate.getTime() === today.getTime();
      const isSelected = selectedKey === key;

      const classes = ["mini-cal-cell"];
      if (otherMonth) classes.push("other-month");
      if (isToday) classes.push("today");
      if (isSelected) classes.push("selected");

      cells.push(`<button type="button" class="${classes.join(" ")}" data-key="${key}">${day}</button>`);
    }

    return cells.join("");
  }

  function renderMiniCalendar() {
    miniCalTitle.textContent = `${MONTHS[state.miniCalMonth]} ${state.miniCalYear}`;
    miniCalGrid.innerHTML = buildMiniCalCells(state.miniCalYear, state.miniCalMonth, formDate.value);
  }

  function renderSidebarCalendar() {
    sidebarCalTitle.textContent = `${MONTHS[state.sidebarCalMonth]} ${state.sidebarCalYear}`;
    sidebarCalGrid.innerHTML = buildMiniCalCells(state.sidebarCalYear, state.sidebarCalMonth, currentPanelKey());
  }

  function openMiniCalendar() {
    const base = formDate.value ? parseDateKey(formDate.value) : new Date(today);
    state.miniCalYear = base.getFullYear();
    state.miniCalMonth = base.getMonth();
    renderMiniCalendar();
    miniCalendar.classList.add("open");
    miniCalToggle.classList.add("active");
  }

  function closeMiniCalendar() {
    miniCalendar.classList.remove("open");
    miniCalToggle.classList.remove("active");
  }

  // ---------- Add-event modal ----------
  function resetAddForm(presetKey) {
    state.selectedType = null;
    state.selectedRepeat = null;
    state.goalFrequency = "daily";
    goalFreqHint.textContent = GOAL_FREQ_HINTS.daily;
    state.eventRepeatDays = new Set();
    state.eventForever = false;
    state.eventRepeatWeeks = null;
    formDate.value = presetKey || currentPanelKey();
    formTime.value = "";
    formText.value = "";
    eventWeeksInput.value = "";
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
    multiDayBtn.disabled = true;
    closeMiniCalendar();
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
    multiDayBtn.disabled = type !== "event";

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

  // ---------- Multi-day picking ----------
  function updateMultiDayBar() {
    const n = state.multiDaySelectedDates.size;
    multiDayCount.textContent = `${n} day${n === 1 ? "" : "s"} selected`;
    multiDaySaveBtn.disabled = n === 0 || multiDayTextInput.value.trim().length === 0;
  }

  function enterMultiDayPicking() {
    state.multiDayTime = formTime.value || null;
    state.multiDaySelectedDates = new Set();
    state.multiDayPicking = true;
    multiDayTextInput.value = formText.value.trim();
    closeAddModal();
    updateMultiDayBar();
    multiDayBar.classList.add("visible");
    renderMonth();
    multiDayTextInput.focus();
  }

  function exitMultiDayPicking() {
    state.multiDayPicking = false;
    multiDayBar.classList.remove("visible");
    renderMonth();
  }

  function saveMultiDayEvents() {
    const text = multiDayTextInput.value.trim();
    if (!text) return;
    state.multiDaySelectedDates.forEach((key) => {
      if (!state.data.singleEvents[key]) state.data.singleEvents[key] = [];
      state.data.singleEvents[key].push({
        id: uid(),
        type: "event",
        time: state.multiDayTime,
        text,
      });
    });
    saveData();
    exitMultiDayPicking();
    renderMonth();
    renderTodayPanel();
    renderDayView();
  }

  function submitAddForm(e) {
    e.preventDefault();
    const type = state.selectedType;
    const key = formDate.value;
    if (!type || !key) return;

    if (type === "event") {
      const text = formText.value.trim();
      if (!text) return;
      if ((state.eventForever || state.eventRepeatWeeks) && state.eventRepeatDays.size > 0) {
        state.data.routines.push({
          id: uid(),
          type: "event",
          repeat: "weekdays",
          days: Array.from(state.eventRepeatDays).sort(),
          startDate: key,
          time: formTime.value || null,
          weeks: state.eventForever ? null : state.eventRepeatWeeks,
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
    renderTodayPanel();
    renderDayView();
  }

  // ---------- Event listeners ----------
  prevBtn.addEventListener("click", () => changeMonth(-1));
  nextBtn.addEventListener("click", () => changeMonth(1));
  todayBtn.addEventListener("click", resetToToday);
  dayTodayBtn.addEventListener("click", resetToToday);

  dayPrevBtn.addEventListener("click", () => {
    const d = parseDateKey(currentPanelKey());
    d.setDate(d.getDate() - 1);
    selectDate(dateKey(d.getFullYear(), d.getMonth(), d.getDate()));
  });

  dayNextBtn.addEventListener("click", () => {
    const d = parseDateKey(currentPanelKey());
    d.setDate(d.getDate() + 1);
    selectDate(dateKey(d.getFullYear(), d.getMonth(), d.getDate()));
  });

  viewToggleBtn.addEventListener("click", () => {
    setViewMode(state.viewMode === "day" ? "month" : "day");
  });

  sidebarCalPrev.addEventListener("click", () => {
    state.sidebarCalMonth -= 1;
    if (state.sidebarCalMonth < 0) {
      state.sidebarCalMonth = 11;
      state.sidebarCalYear -= 1;
    }
    renderSidebarCalendar();
  });

  sidebarCalNext.addEventListener("click", () => {
    state.sidebarCalMonth += 1;
    if (state.sidebarCalMonth > 11) {
      state.sidebarCalMonth = 0;
      state.sidebarCalYear += 1;
    }
    renderSidebarCalendar();
  });

  sidebarCalGrid.addEventListener("click", (e) => {
    const cell = e.target.closest(".mini-cal-cell");
    if (!cell) return;
    selectDate(cell.dataset.key);
    if (todayPanel.classList.contains("collapsed")) setTodayPanelHidden(false);
  });

  daysGridEl.addEventListener("click", (e) => {
    const cell = e.target.closest(".day-cell");
    if (!cell) return;
    const { year, month, day } = cell.dataset;
    const key = dateKey(Number(year), Number(month), Number(day));

    if (state.multiDayPicking) {
      if (state.multiDaySelectedDates.has(key)) {
        state.multiDaySelectedDates.delete(key);
        cell.classList.remove("multi-picked");
      } else {
        state.multiDaySelectedDates.add(key);
        cell.classList.add("multi-picked");
      }
      updateMultiDayBar();
      return;
    }

    selectDate(key);
    if (todayPanel.classList.contains("collapsed")) setTodayPanelHidden(false);
  });

  todayPanelAddBtn.addEventListener("click", () => {
    if (state.multiDayPicking) return;
    openAddModal(currentPanelKey());
  });
  addEventBtn.addEventListener("click", () => {
    if (state.multiDayPicking) return;
    openAddModal(currentPanelKey());
  });

  exportDataBtn.addEventListener("click", exportData);
  importDataBtn.addEventListener("click", () => importFileInput.click());
  importFileInput.addEventListener("change", () => {
    const file = importFileInput.files[0];
    importFileInput.value = "";
    if (!file) return;
    const ok = window.confirm("This replaces everything currently on your calendar with the contents of this backup file. Continue?");
    if (!ok) return;
    importData(file);
  });

  closeModalBtn.addEventListener("click", closeAddModal);
  modalBackdrop.addEventListener("click", closeAddModal);

  miniCalToggle.addEventListener("click", (e) => {
    e.stopPropagation();
    if (miniCalendar.classList.contains("open")) {
      closeMiniCalendar();
    } else {
      openMiniCalendar();
    }
  });

  miniCalPrev.addEventListener("click", () => {
    state.miniCalMonth -= 1;
    if (state.miniCalMonth < 0) {
      state.miniCalMonth = 11;
      state.miniCalYear -= 1;
    }
    renderMiniCalendar();
  });

  miniCalNext.addEventListener("click", () => {
    state.miniCalMonth += 1;
    if (state.miniCalMonth > 11) {
      state.miniCalMonth = 0;
      state.miniCalYear += 1;
    }
    renderMiniCalendar();
  });

  miniCalGrid.addEventListener("click", (e) => {
    const cell = e.target.closest(".mini-cal-cell");
    if (!cell) return;
    formDate.value = cell.dataset.key;
    closeMiniCalendar();
    updateSaveEnabled();
  });

  document.addEventListener("click", (e) => {
    if (!miniCalendar.classList.contains("open")) return;
    if (miniCalendar.contains(e.target) || e.target === miniCalToggle) return;
    closeMiniCalendar();
  });

  multiDayBtn.addEventListener("click", enterMultiDayPicking);
  multiDayCancelBtn.addEventListener("click", exitMultiDayPicking);
  multiDaySaveBtn.addEventListener("click", saveMultiDayEvents);

  function handleItemListClick(e) {
    const completeBtn = e.target.closest(".complete-btn");
    if (completeBtn) {
      if (completeBtn.classList.contains("checked")) return;
      const { id, source } = completeBtn.dataset;
      completeBtn.classList.add("checked");
      const item = completeBtn.closest(".event-item");
      setTimeout(() => {
        item.classList.add("removing");
        setTimeout(() => {
          if (source === "routine") {
            deleteRoutine(id);
          } else {
            deleteSingleEvent(currentPanelKey(), id);
          }
          renderTodayPanel();
          renderMonth();
          renderDayView();
        }, 250);
      }, 450);
      return;
    }

    const btn = e.target.closest(".delete-btn");
    if (!btn) return;
    const { id, source } = btn.dataset;
    if (source === "routine") {
      const ok = window.confirm("This removes the routine from every day it repeats on, not just this one. Continue?");
      if (!ok) return;
      deleteRoutine(id);
    } else {
      deleteSingleEvent(currentPanelKey(), id);
    }
    renderTodayPanel();
    renderMonth();
    renderDayView();
  }

  todayEventListEl.addEventListener("click", handleItemListClick);
  dayViewAllDay.addEventListener("click", handleItemListClick);
  dayViewTimeline.addEventListener("click", handleItemListClick);

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
    goalFreqHint.textContent = GOAL_FREQ_HINTS[state.goalFrequency];
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
    if (state.eventForever) {
      state.eventRepeatWeeks = null;
      eventWeeksInput.value = "";
    }
    if (state.eventForever && state.eventRepeatDays.size === 0 && formDate.value) {
      const day = parseDateKey(formDate.value).getDay();
      state.eventRepeatDays.add(day);
      const btn = eventWeekdayPicker.querySelector(`.weekday-btn[data-day="${day}"]`);
      if (btn) btn.classList.add("active");
    }
  });

  eventWeeksInput.addEventListener("input", () => {
    const n = parseInt(eventWeeksInput.value, 10);
    if (n > 0) {
      state.eventRepeatWeeks = n;
      state.eventForever = false;
      eventForeverBtn.classList.remove("active");
      if (state.eventRepeatDays.size === 0 && formDate.value) {
        const day = parseDateKey(formDate.value).getDay();
        state.eventRepeatDays.add(day);
        const btn = eventWeekdayPicker.querySelector(`.weekday-btn[data-day="${day}"]`);
        if (btn) btn.classList.add("active");
      }
    } else {
      state.eventRepeatWeeks = null;
    }
  });

  multiDayTextInput.addEventListener("input", updateMultiDayBar);

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
      if (miniCalendar.classList.contains("open")) {
        closeMiniCalendar();
      } else if (addModal.classList.contains("open")) {
        closeAddModal();
      } else if (state.multiDayPicking) {
        exitMultiDayPicking();
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
  renderTodayPanel();
  renderSidebarCalendar();
  setViewMode("day");
})();
