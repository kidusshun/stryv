# Stryv Product Requirements Document

## 1. Product Summary

Stryv is a private Windows desktop app for tracking how time is spent throughout the day. It records active applications, websites, window titles, idle time, focus blocks, distractions, and daily work patterns so the user can build disciplined, high-output work habits.

The app is personal-first. It should feel like an honest operating dashboard for one person, not a manager tool, employee tracker, or team analytics product.

## 2. Product Goals

1. Show exactly where time goes during the day.
2. Make long work days measurable without glorifying low-quality hours.
3. Identify focus time, distraction time, context switching, idle time, and breaks.
4. Help the user improve consistency across days and weeks.
5. Keep all tracking data private and locally controlled by default.

## 3. Non-Goals

1. Team monitoring or employee productivity scoring.
2. Screenshots, webcam capture, keylogging, or invasive surveillance.
3. Billing, invoicing, payroll, or agency profitability features.
4. Cloud sync in the first implementation.
5. Mobile apps.
6. Browser extension dependency for the first version, unless website-level tracking cannot be achieved reliably from window titles.

## 4. Target Platform

- Primary platform: Windows.
- Framework: Electron.
- Local database: SQLite.
- Background tracking: Electron main process plus native active-window detection.
- UI: Electron renderer using a web frontend.

## 5. Priority Levels

- P0: Required for the app to function.
- P1: Important for making the app genuinely useful day to day.
- P2: Quality-of-life and deeper insight features.
- P3: Later polish or optional expansion.

## 6. Feature Roadmap

### Phase 1: App Foundation ✅

#### P0. Electron App Shell

Requirements:
- Create a Windows Electron desktop app named Stryv.
- App opens to a dashboard window.
- App has a persistent background process while running.
- App supports minimize-to-tray.
- App can be restored from the tray.
- App stores user data locally.

Acceptance Criteria:
- Launching Stryv opens the main window.
- Closing or minimizing can keep tracking active in the background.
- The tray icon can reopen the dashboard.

#### P0. Local Data Store

Requirements:
- Use SQLite for local storage.
- Store activity sessions, raw tracking samples, categories, settings, and daily summaries.
- Database should be created automatically on first launch.
- Data should remain available after app restart.

Core Tables:
- `activity_samples`
- `activity_sessions`
- `apps`
- `categories`
- `rules`
- `daily_summaries`
- `settings`

Acceptance Criteria:
- Activity data persists across restarts.
- Database migrations can be applied safely as schema changes.

### Phase 2: Automatic Activity Tracking ✅

#### P0. Active App and Window Tracking

Requirements:
- Detect the currently focused Windows application.
- Capture app name, executable path when available, window title, and timestamp.
- Poll at a configurable interval, defaulting to 5 seconds.
- Do not store duplicate data unnecessarily when nothing changes.

Acceptance Criteria:
- Switching from one app to another creates distinct tracked activity.
- Remaining in the same app continues the same activity session.
- App usage can be reconstructed into a timeline.

#### P0. Session Merging

Requirements:
- Convert raw samples into readable sessions.
- A session starts when the active app/window changes.
- A session ends when another app/window becomes active, the machine goes idle, or tracking stops.
- Very short interruptions should be mergeable using a configurable grace period.

Acceptance Criteria:
- The dashboard shows clean sessions rather than noisy 5-second samples.
- App totals are calculated from session durations.

#### P0. Idle Detection

Requirements:
- Detect when the user is away from the computer.
- Default idle threshold: 5 minutes.
- Mark idle time separately from active app usage.
- Resume normal tracking when the user becomes active again.

Acceptance Criteria:
- Leaving the computer does not inflate app usage totals.
- Idle blocks are visible in the daily timeline.

### Phase 3: Daily Dashboard ✅

#### P0. Today View

Requirements:
- Show total tracked time for the current day.
- Show active time, idle time, and break time.
- Show top apps by duration.
- Show a chronological timeline of the day.
- Show current active app/session.

Acceptance Criteria:
- User can open Stryv and immediately see where today's time has gone.
- Totals update while the app is running.

#### P1. App Detail View

Requirements:
- Selecting an app shows all sessions for that app.
- Show total duration, first used, last used, and associated window titles.
- Allow app category assignment.

Acceptance Criteria:
- User can understand not only which app consumed time, but when and why.

### Phase 4: Categories and Rules

#### P1. Activity Categories

Requirements:
- Support built-in categories:
  - Deep Work
  - Work
  - Learning
  - Communication
  - Planning
  - Admin
  - Entertainment
  - Social
  - Distraction
  - Neutral
  - Idle
- Allow category colors.
- Allow custom categories.

Acceptance Criteria:
- App totals can be grouped by category.
- Categories can be changed without losing historical sessions.

#### P1. Automatic Classification Rules

Requirements:
- User can define rules based on app name, executable path, website text in title, or window title keywords.
- Rules assign categories automatically.
- Rules can optionally mark activity as focus-eligible or distracting.

Acceptance Criteria:
- Repeated apps/sites are categorized automatically after a rule is created.
- Rule changes can be applied to future activity and optionally historical activity.

### Phase 5: Focus and Distraction Analysis

#### P1. Focus Time Detection

Requirements:
- Count uninterrupted sessions in focus-eligible categories as focus time.
- Default minimum focus block: 25 minutes.
- Context switches below a grace period should not always break focus.
- Show total focus time for the day.

Acceptance Criteria:
- User can see how much of the day was meaningful focused work.
- Focus time is separate from raw active computer time.

#### P1. Distraction Tracking

Requirements:
- Track time spent in categories marked as distracting.
- Show number of distraction sessions.
- Show when distractions occurred.
- Show top distracting apps/sites.

Acceptance Criteria:
- User can identify the biggest sources and times of distraction.

#### P1. Context Switching

Requirements:
- Count app/category switches during active work.
- Show context switches per hour.
- Highlight fragmented periods of work.

Acceptance Criteria:
- User can distinguish steady work from scattered work.

### Phase 6: Reports and Trends

#### P1. Daily Report

Requirements:
- Generate a daily summary containing:
  - Total active time
  - Focus time
  - Idle time
  - Break time
  - Distraction time
  - Top apps
  - Top categories
  - First active time
  - Last active time
  - Longest focus block
  - Context switch count

Acceptance Criteria:
- User can review a completed day in under one minute.

#### P2. Weekly Report

Requirements:
- Show trends across the last 7 days.
- Include daily active time, focus time, distraction time, and start/end times.
- Show best day, weakest day, and average focus per day.

Acceptance Criteria:
- User can see whether discipline is improving over time.

#### P2. Historical Search and Filtering

Requirements:
- Filter by date range, app, category, and title keyword.
- Search past sessions.
- Compare two days.

Acceptance Criteria:
- User can answer questions like "How much time did I spend in VS Code last week?"

### Phase 7: Goals and Workday Structure

#### P2. Daily Goals

Requirements:
- Allow daily targets for:
  - Active time
  - Focus time
  - Maximum distraction time
  - Latest acceptable start time
  - Minimum number of deep work blocks
- Show progress toward goals on the dashboard.

Acceptance Criteria:
- User can measure the day against personally defined discipline targets.

#### P2. Break Awareness

Requirements:
- Detect long continuous work periods.
- Notify user after configurable work duration.
- Track breaks separately from idle time when possible.
- Warn when the day contains too few breaks.

Acceptance Criteria:
- Stryv helps sustain long work days without confusing exhaustion for productivity.

#### P2. Workday Boundaries

Requirements:
- Detect first activity and last activity each day.
- Show work span separately from active work time.
- Support user-defined planned work windows.

Acceptance Criteria:
- User can see both "time at computer" and "real active work."

### Phase 8: Privacy and Control

#### P1. Privacy Exclusions

Requirements:
- Allow excluding specific apps from title tracking.
- Allow excluding apps entirely from tracking.
- Allow masking window titles for selected apps.
- Provide a pause tracking button.

Acceptance Criteria:
- Sensitive activity can be hidden or ignored without disabling the whole app.

#### P2. Data Management

Requirements:
- Export data as CSV or JSON.
- Delete all data.
- Delete a specific day.
- Rebuild summaries from raw sessions.

Acceptance Criteria:
- User owns the data and can inspect, export, or remove it.

### Phase 9: Desktop Integration

#### P1. Autostart on Login

Requirements:
- Option to start Stryv when Windows starts.
- Option to start minimized to tray.

Acceptance Criteria:
- Tracking can begin automatically each day.

#### P2. Notifications

Requirements:
- Notify when the user enters a distraction category for too long.
- Notify when focus goal is reached.
- Notify when break reminder triggers.
- Notifications can be disabled individually.

Acceptance Criteria:
- Notifications are useful, configurable, and not noisy.

#### P3. Global Shortcuts

Requirements:
- Shortcut to pause/resume tracking.
- Shortcut to open dashboard.
- Shortcut to start a focus block.

Acceptance Criteria:
- Common actions are accessible without opening the full app manually.

### Phase 10: Advanced Personal Features

#### P2. Manual Corrections

Requirements:
- Edit session category.
- Split a session.
- Merge adjacent sessions.
- Delete a session.
- Add a manual note to a session.

Acceptance Criteria:
- User can fix tracking mistakes without editing the database directly.

#### P2. Notes and Intent

Requirements:
- Allow optional daily note.
- Allow optional session note.
- Allow marking a session as intentional or accidental.

Acceptance Criteria:
- Reports can distinguish deliberate work from drift.

#### P3. Calendar Integration

Requirements:
- Optional calendar import.
- Show meetings on timeline.
- Compare planned events against actual tracked activity.

Acceptance Criteria:
- User can see whether planned work matched reality.

#### P3. Website-Level Tracking

Requirements:
- Improve website detection beyond browser window titles if needed.
- Consider a browser extension only if Electron/window-title tracking is insufficient.

Acceptance Criteria:
- Web usage can be categorized accurately enough for personal productivity analysis.

## 7. Suggested Implementation Order

1. Electron shell, tray behavior, and SQLite setup.
2. Active app/window polling.
3. Session merging and idle detection.
4. Today dashboard with timeline and app totals.
5. Category system.
6. Rule-based automatic classification.
7. Focus time, distraction time, and context switch metrics.
8. Daily report.
9. Privacy exclusions and pause tracking.
10. Autostart on login.
11. Weekly report and historical filtering.
12. Daily goals and break awareness.
13. Manual corrections.
14. Export/delete data controls.
15. Notifications and global shortcuts.
16. Calendar integration and enhanced website tracking.

## 8. Recommended First Technical Stack

- Electron for the desktop runtime.
- Vite for frontend development.
- React for dashboard UI.
- TypeScript for maintainability.
- SQLite for local data.
- `better-sqlite3` or equivalent for database access.
- `active-win` or equivalent for active window detection.
- Electron Builder for packaging.

## 9. Key Product Principles

1. Local-first: data should stay on the machine unless the user explicitly adds sync later.
2. Transparent: the user should always know what is being tracked.
3. Correct before pretty: inaccurate time tracking ruins trust.
4. Focus over vanity: raw 18-hour spans matter less than real focused output.
5. Low friction: the app should run quietly without constant manual input.
