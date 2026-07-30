(function () {
  const STORAGE_KEY = 'touchgrass-state';

  const STAGES = [
    { level: 1, emoji: '🌰', name: 'Tiny Seed' },
    { level: 2, emoji: '🌱', name: 'Sprout' },
    { level: 3, emoji: '🌿', name: 'Sapling' },
    { level: 4, emoji: '🪴', name: 'Young Plant' },
    { level: 5, emoji: '🌳', name: 'Tree' },
    { level: 6, emoji: '🌸', name: 'Blooming Tree' },
    { level: 7, emoji: '🍎', name: 'Fruit Bearer' },
    { level: 8, emoji: '🌲', name: 'Mighty Oak' },
  ];
  const XP_PER_LEVEL = 100;
  const MAX_LEVEL = STAGES.length;

  const BADGES = [
    { id: 'first_log', name: 'First Step', desc: 'Log your first day', emoji: '🥾', test: s => s.sessions.length >= 1 },
    { id: 'goal_setter', name: 'Goal Setter', desc: 'Set a daily goal', emoji: '🎯', test: s => s.goalSet },
    { id: 'streak_3', name: 'Bronze Streak', desc: '3-day streak', emoji: '🥉', test: s => s.bestStreak >= 3 },
    { id: 'streak_7', name: 'Silver Streak', desc: '7-day streak', emoji: '🥈', test: s => s.bestStreak >= 7 },
    { id: 'streak_14', name: 'Gold Streak', desc: '14-day streak', emoji: '🥇', test: s => s.bestStreak >= 14 },
    { id: 'streak_30', name: 'Diamond Streak', desc: '30-day streak', emoji: '💎', test: s => s.bestStreak >= 30 },
  ];

  function defaultState() {
    return {
      goal: 3,
      goalSet: false,
      xp: 0,
      streak: 0,
      bestStreak: 0,
      sessions: [], // { hours }
    };
  }

  function loadState() {
    try {
      const raw = localStorage.getItem(STORAGE_KEY);
      if (!raw) return defaultState();
      return Object.assign(defaultState(), JSON.parse(raw));
    } catch (e) {
      return defaultState();
    }
  }

  function saveState() {
    localStorage.setItem(STORAGE_KEY, JSON.stringify(state));
  }

  let state = loadState();

  function levelFromXp(xp) {
    return Math.min(MAX_LEVEL, Math.floor(xp / XP_PER_LEVEL) + 1);
  }

  function stageForLevel(level) {
    return STAGES[Math.min(level, MAX_LEVEL) - 1];
  }

  // ---------- Rendering ----------
  function render() {
    const level = levelFromXp(state.xp);
    const stage = stageForLevel(level);
    const xpIntoLevel = state.xp % XP_PER_LEVEL;
    const isMaxLevel = level >= MAX_LEVEL;

    $('#levelNum').textContent = level;
    $('#avatarStage').textContent = stage.emoji;
    $('#avatarTitle').textContent = stage.name;
    $('#xpFill').style.width = isMaxLevel ? '100%' : (xpIntoLevel / XP_PER_LEVEL * 100) + '%';
    $('#xpNum').textContent = isMaxLevel ? state.xp : xpIntoLevel;
    $('#xpNeeded').textContent = isMaxLevel ? state.xp : XP_PER_LEVEL;

    $('#navStreakCount').textContent = state.streak;
    $('#statStreak').textContent = state.streak;
    $('#statBest').textContent = state.bestStreak;

    if (state.sessions.length) {
      const last = state.sessions[state.sessions.length - 1];
      $('#statToday').textContent = last.hours + 'h';
      const recent = state.sessions.slice(-7);
      const avg = recent.reduce((sum, s) => sum + s.hours, 0) / recent.length;
      $('#statAvg').textContent = avg.toFixed(1) + 'h';
    } else {
      $('#statToday').textContent = '–';
      $('#statAvg').textContent = '–';
    }

    $('#goalSub').textContent = state.goalSet
      ? `Goal: ${state.goal}h / day`
      : 'Choose your daily limit';

    renderPath(level);
    renderBadges();
  }

  function renderPath(currentLevel) {
    const path = $('#questPath');
    path.innerHTML = '';
    STAGES.forEach(stage => {
      const node = document.createElement('div');
      node.className = 'path-node';
      if (stage.level < currentLevel) node.classList.add('is-done');
      if (stage.level === currentLevel) node.classList.add('is-active');
      node.innerHTML = `
        <div class="path-node__emoji">${stage.emoji}</div>
        <div class="path-node__level">LV ${stage.level}</div>
        <div class="path-node__name">${stage.name}</div>
      `;
      path.appendChild(node);
    });
  }

  function renderBadges() {
    const grid = $('#badgeGrid');
    grid.innerHTML = '';
    let unlockedCount = 0;
    BADGES.forEach(b => {
      const unlocked = b.test(state);
      if (unlocked) unlockedCount++;
      const el = document.createElement('div');
      el.className = 'badge' + (unlocked ? ' is-unlocked' : '');
      el.innerHTML = `
        <div class="badge__emoji">${unlocked ? b.emoji : '🔒'}</div>
        <div class="badge__name">${b.name}</div>
        <div class="badge__desc">${b.desc}</div>
      `;
      grid.appendChild(el);
    });
    $('#badgeSub').textContent = `${unlockedCount} / ${BADGES.length} unlocked`;
  }

  // ---------- Actions ----------
  function logScreenTime(hours) {
    const beforeLevel = levelFromXp(state.xp);
    const underGoal = state.goalSet ? hours <= state.goal : hours <= 3;

    state.sessions.push({ hours });
    if (underGoal) {
      state.streak += 1;
      state.xp += 20;
    } else {
      state.streak = 0;
      state.xp += 5;
    }
    state.bestStreak = Math.max(state.bestStreak, state.streak);

    const afterLevel = levelFromXp(state.xp);
    saveState();
    render();

    if (afterLevel > beforeLevel) {
      showLevelUp(afterLevel);
    }
  }

  function showLevelUp(level) {
    const stage = stageForLevel(level);
    $('#toastEmoji').textContent = stage.emoji;
    $('#toastSub').textContent = `You grew into a ${stage.name}`;
    const toast = $('#levelToast');
    toast.classList.add('is-shown');
    setTimeout(() => toast.classList.remove('is-shown'), 3200);
  }

  // ---------- Helpers ----------
  function $(sel) { return document.querySelector(sel); }
  function openModal(id) { $(id).classList.add('is-open'); }
  function closeModal(id) { $(id).classList.remove('is-open'); }

  // ---------- Wiring ----------
  function init() {
    render();

    // Goal modal
    const goalSlider = $('#goalSlider');
    goalSlider.value = state.goal;
    $('#goalSliderVal').textContent = state.goal;
    goalSlider.addEventListener('input', () => {
      $('#goalSliderVal').textContent = goalSlider.value;
    });
    $('#btnSetGoal').addEventListener('click', () => openModal('#goalModal'));
    $('#btnSetGoal2').addEventListener('click', () => openModal('#goalModal'));
    $('#goalCancel').addEventListener('click', () => closeModal('#goalModal'));
    $('#goalSave').addEventListener('click', () => {
      state.goal = parseFloat(goalSlider.value);
      state.goalSet = true;
      saveState();
      render();
      closeModal('#goalModal');
    });

    // Log modal
    const logSlider = $('#logSlider');
    $('#logSliderVal').textContent = logSlider.value;
    logSlider.addEventListener('input', () => {
      $('#logSliderVal').textContent = logSlider.value;
    });
    $('#btnLogTime').addEventListener('click', () => openModal('#logModal'));
    $('#btnLogTime2').addEventListener('click', () => openModal('#logModal'));
    $('#logCancel').addEventListener('click', () => closeModal('#logModal'));
    $('#logSave').addEventListener('click', () => {
      logScreenTime(parseFloat(logSlider.value));
      closeModal('#logModal');
    });

    // Achievements shortcut scrolls to badges
    $('#btnAchievements').addEventListener('click', () => {
      $('#badgesSection').scrollIntoView({ behavior: 'smooth', block: 'start' });
    });

    // Reset
    $('#btnReset').addEventListener('click', () => {
      if (confirm('Reset all progress? This cannot be undone.')) {
        state = defaultState();
        saveState();
        render();
      }
    });

    // Close modals on backdrop click
    document.querySelectorAll('.modal-backdrop').forEach(backdrop => {
      backdrop.addEventListener('click', (e) => {
        if (e.target === backdrop) backdrop.classList.remove('is-open');
      });
    });
  }

  document.addEventListener('DOMContentLoaded', init);
})();
