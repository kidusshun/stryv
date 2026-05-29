import {
  Activity,
  BarChart3,
  Check,
  ChevronDown,
  Clock,
  Database,
  Flame,
  ListTree,
  Maximize2,
  Menu,
  Minus,
  Monitor,
  Moon,
  Play,
  Settings,
  Square,
  X,
  ShieldCheck,
  Timer,
} from 'lucide-react';
import { useEffect, useMemo, useState } from 'react';

type DatabaseStatus = {
  path: string;
  schemaVersion: number;
};

type TrackerStatus = Awaited<ReturnType<NonNullable<Window['stryv']>['getTrackerStatus']>>;
type TodayDashboard = Awaited<ReturnType<NonNullable<Window['stryv']>['getTodayDashboard']>>;
type Category = Awaited<ReturnType<NonNullable<Window['stryv']>['getCategories']>>[number];
type ClassificationRule = Awaited<ReturnType<NonNullable<Window['stryv']>['getClassificationRules']>>[number];

const previewDashboard: TodayDashboard = {
  day: new Date().toISOString().slice(0, 10),
  totalTrackedSeconds: 0,
  activeSeconds: 0,
  idleSeconds: 0,
  breakSeconds: 0,
  topApps: [],
  timeline: [],
  activeIntent: null,
  current: {
    sessionId: null,
    appName: 'Electron preview unavailable',
    windowTitle: null,
    executablePath: null,
    isIdle: false,
    startedAt: null,
    durationSeconds: 0,
    categoryName: null,
  },
};

type SelectOption = {
  label: string;
  value: string;
};

type AppPage = 'home' | 'config';

type CategorySummaryItem = {
  name: string;
  color: string;
  durationSeconds: number;
};

type CalendarBlock = {
  id: string;
  title: string;
  startedAt: string;
  endedAt: string | null;
  topPercent: number;
  heightPercent: number;
  color: string;
};

export function App() {
  const [activePage, setActivePage] = useState<AppPage>('home');
  const [isSidebarCollapsed, setIsSidebarCollapsed] = useState(true);
  const [databaseStatus, setDatabaseStatus] = useState<DatabaseStatus | null>(null);
  const [trackerStatus, setTrackerStatus] = useState<TrackerStatus | null>(null);
  const [today, setToday] = useState<TodayDashboard>(previewDashboard);
  const [categories, setCategories] = useState<Category[]>([]);
  const [rules, setRules] = useState<ClassificationRule[]>([]);
  const [intentName, setIntentName] = useState('Content Research');
  const [intentDuration, setIntentDuration] = useState(45);
  const [intentCategoryId, setIntentCategoryId] = useState<number | null>(null);
  const [intentPatterns, setIntentPatterns] = useState('TikTok, Instagram, YouTube');
  const [categoryName, setCategoryName] = useState('');
  const [categoryColor, setCategoryColor] = useState('#e8581a');
  const [categoryFlags, setCategoryFlags] = useState({
    isFocus: false,
    isWork: true,
    isBreak: false,
    isIdle: false,
    isDistracting: false,
    idleDetectionExempt: false,
    distractionBlockerEnabled: false,
  });
  const [rulePattern, setRulePattern] = useState('');
  const [ruleMatchType, setRuleMatchType] = useState<'app_name' | 'executable_path' | 'window_title'>('window_title');
  const [ruleCategoryId, setRuleCategoryId] = useState<number | null>(null);

  useEffect(() => {
    if (!window.stryv) {
      setDatabaseStatus({ path: 'Electron preload unavailable in browser preview', schemaVersion: 1 });
      return;
    }

    const refreshDashboard = () => {
      void window.stryv?.getTodayDashboard().then(setToday);
    };

    void window.stryv.getDatabaseStatus().then(setDatabaseStatus);
    void window.stryv.getTrackerStatus().then(setTrackerStatus);
    void window.stryv.getCategories().then((nextCategories) => {
      setCategories(nextCategories);
      const fallbackCategory = nextCategories.find((category) => category.name === 'Creative') ?? nextCategories[0];
      setIntentCategoryId((currentCategoryId) => currentCategoryId ?? fallbackCategory?.id ?? null);
      setRuleCategoryId((currentCategoryId) => currentCategoryId ?? fallbackCategory?.id ?? null);
    });
    void window.stryv.getClassificationRules().then(setRules);
    refreshDashboard();

    return window.stryv.onTrackerStatusChanged((status) => {
      setTrackerStatus(status);
      refreshDashboard();
    });
  }, []);

  const topDuration = useMemo(
    () => Math.max(...today.topApps.map((app) => app.durationSeconds), 1),
    [today.topApps],
  );
  const intentCategories = categories.filter(
    (category) => Boolean(category.is_work) || Boolean(category.is_focus),
  );
  const categorySummary = useMemo(() => getCategorySummary(today), [today]);
  const calendarBlocks = useMemo(() => getCalendarBlocks(today), [today]);

  const startIntent = async () => {
    if (!window.stryv || !intentCategoryId) {
      return;
    }

    const patterns = intentPatterns
      .split(',')
      .map((pattern) => pattern.trim())
      .filter(Boolean);

    await window.stryv.startIntentSession({
      name: intentName,
      durationMinutes: intentDuration,
      categoryId: intentCategoryId,
      rules: patterns.flatMap((pattern) => [
        { matchType: 'app_name', pattern } as const,
        { matchType: 'window_title', pattern } as const,
      ]),
    });

    setToday(await window.stryv.getTodayDashboard());
  };

  const stopIntent = async () => {
    if (!window.stryv) {
      return;
    }

    await window.stryv.stopActiveIntentSession();
    setToday(await window.stryv.getTodayDashboard());
  };

  const createNewCategory = async () => {
    if (!window.stryv || !categoryName.trim()) {
      return;
    }

    const createdCategory = await window.stryv.createCategory({
      name: categoryName,
      color: categoryColor,
      ...categoryFlags,
    });

    const nextCategories = await window.stryv.getCategories();
    setCategories(nextCategories);
    setCategoryName('');
    setIntentCategoryId((currentCategoryId) => currentCategoryId ?? createdCategory.id);
    setRuleCategoryId((currentCategoryId) => currentCategoryId ?? createdCategory.id);
  };

  const createNewRule = async () => {
    if (!window.stryv || !rulePattern.trim() || !ruleCategoryId) {
      return;
    }

    await window.stryv.createClassificationRule({
      name: rulePattern,
      matchType: ruleMatchType,
      pattern: rulePattern,
      categoryId: ruleCategoryId,
      priority: 100,
    });

    setRules(await window.stryv.getClassificationRules());
    setRulePattern('');
  };

  const toggleRule = async (rule: ClassificationRule) => {
    if (!window.stryv) {
      return;
    }

    await window.stryv.setClassificationRuleEnabled(rule.id, !rule.is_enabled);
    setRules(await window.stryv.getClassificationRules());
  };

  return (
    <main className="min-h-screen overflow-hidden bg-stryv-bg text-stryv-text">
      <WindowControls />
      <div
        className={`grid min-h-screen transition-[grid-template-columns] duration-200 ${
          isSidebarCollapsed ? 'lg:grid-cols-[72px_minmax(0,1fr)]' : 'lg:grid-cols-[224px_minmax(0,1fr)]'
        }`}
      >
        <AppSidebar
          activePage={activePage}
          isCollapsed={isSidebarCollapsed}
          onNavigate={setActivePage}
          onToggle={() => setIsSidebarCollapsed((current) => !current)}
        />

        <section className="min-h-screen min-w-0 overflow-auto px-5 pb-6 pt-12 sm:px-7 lg:px-9">
          <header className="flex flex-col gap-4 border-b border-stryv-line pb-6 sm:flex-row sm:items-center sm:justify-between">
            <div>
              <p className="bg-gradient-to-r from-stryv-amber via-stryv-orange to-stryv-ember bg-clip-text text-xs font-bold uppercase text-transparent">
                {activePage === 'home' ? 'Daily activity' : 'Stryv settings'}
              </p>
              <h2 className="mt-1 text-3xl font-bold tracking-normal text-white">
                {activePage === 'home' ? 'Today' : 'Configuration'}
              </h2>
            </div>
            <div className="flex flex-wrap items-center gap-2">
              <StatusPill icon={<ShieldCheck size={16} />} label="Local-first" />
              <StatusPill
                icon={<Monitor size={16} />}
                label={trackerStatus?.isRunning ? 'Tracking live' : 'Tracker unavailable'}
                active={Boolean(trackerStatus?.isRunning)}
              />
            </div>
          </header>

          {activePage === 'home' ? (
            <HomePage
              calendarBlocks={calendarBlocks}
              categorySummary={categorySummary}
              databaseStatus={databaseStatus}
              today={today}
              topDuration={topDuration}
            />
          ) : (
            <section className="mt-6 grid gap-5">
              <Panel title="Intent Session" icon={<Play size={18} />}>
                {today.activeIntent ? (
                  <div className="flex flex-col gap-4 sm:flex-row sm:items-center sm:justify-between">
                    <div className="min-w-0">
                      <p className="truncate text-xl font-bold text-white">{today.activeIntent.name}</p>
                      <p className="mt-1 text-sm text-stryv-muted">
                        Treating matches as {today.activeIntent.category_name} until{' '}
                        {formatTime(today.activeIntent.ends_at)}
                      </p>
                    </div>
                    <button
                      className="inline-flex h-10 items-center justify-center gap-2 rounded-lg border border-stryv-line px-4 text-sm font-bold text-stryv-muted hover:border-stryv-orange/50 hover:text-white"
                      onClick={stopIntent}
                      type="button"
                    >
                      <Square size={15} />
                      Stop
                    </button>
                  </div>
                ) : (
                  <div className="grid gap-4 xl:grid-cols-[minmax(0,1fr)_120px_180px_auto] xl:items-end">
                    <label className="grid gap-2">
                      <span className="text-xs font-bold uppercase text-stryv-muted">Intent</span>
                      <input
                        className="h-10 rounded-lg border border-stryv-line bg-black/40 px-3 text-sm text-white outline-none focus:border-stryv-orange/60"
                        onChange={(event) => setIntentName(event.target.value)}
                        value={intentName}
                      />
                    </label>
                    <label className="grid gap-2">
                      <span className="text-xs font-bold uppercase text-stryv-muted">Minutes</span>
                      <input
                        className="h-10 rounded-lg border border-stryv-line bg-black/40 px-3 text-sm text-white outline-none focus:border-stryv-orange/60"
                        min={1}
                        onChange={(event) => setIntentDuration(Number(event.target.value))}
                        type="number"
                        value={intentDuration}
                      />
                    </label>
                    <label className="grid gap-2">
                      <span className="text-xs font-bold uppercase text-stryv-muted">Category</span>
                      <ThemeSelect
                        onChange={(value) => setIntentCategoryId(Number(value))}
                        options={intentCategories.map((category) => ({
                          label: category.name,
                          value: String(category.id),
                        }))}
                        value={intentCategoryId ? String(intentCategoryId) : ''}
                      />
                    </label>
                    <button
                      className="inline-flex h-10 items-center justify-center gap-2 rounded-lg border border-stryv-orange/40 bg-gradient-to-r from-stryv-ember/30 to-stryv-orange/20 px-4 text-sm font-bold text-stryv-orange hover:border-stryv-orange/70"
                      onClick={startIntent}
                      type="button"
                    >
                      <Play size={15} />
                      Start
                    </button>
                    <label className="grid gap-2 xl:col-span-4">
                      <span className="text-xs font-bold uppercase text-stryv-muted">Allowed apps/sites</span>
                      <input
                        className="h-10 rounded-lg border border-stryv-line bg-black/40 px-3 text-sm text-white outline-none focus:border-stryv-orange/60"
                        onChange={(event) => setIntentPatterns(event.target.value)}
                        placeholder="TikTok, Instagram, YouTube"
                        value={intentPatterns}
                      />
                    </label>
                  </div>
                )}
              </Panel>
              <section className="grid gap-5 xl:grid-cols-2">
            <Panel title="Categories" icon={<Database size={18} />}>
              <div className="grid gap-3">
                <div className="grid gap-3 sm:grid-cols-[minmax(0,1fr)_112px_auto]">
                  <input
                    className="h-10 rounded-lg border border-stryv-line bg-black/40 px-3 text-sm text-white outline-none focus:border-stryv-orange/60"
                    onChange={(event) => setCategoryName(event.target.value)}
                    placeholder="Custom category"
                    value={categoryName}
                  />
                  <input
                    className="h-10 rounded-lg border border-stryv-line bg-black/40 px-2"
                    onChange={(event) => setCategoryColor(event.target.value)}
                    type="color"
                    value={categoryColor}
                  />
                  <button
                    className="h-10 rounded-lg border border-stryv-orange/40 px-4 text-sm font-bold text-stryv-orange hover:border-stryv-orange/70"
                    onClick={createNewCategory}
                    type="button"
                  >
                    Add
                  </button>
                </div>
                <div className="flex flex-wrap gap-2">
                  {(['isFocus', 'isWork', 'isBreak', 'isDistracting'] as const).map((flag) => (
                    <label
                      className="inline-flex items-center gap-2 rounded-full border border-stryv-line px-3 py-2 text-xs font-bold text-stryv-muted"
                      key={flag}
                    >
                      <input
                        checked={categoryFlags[flag]}
                        onChange={(event) =>
                          setCategoryFlags((currentFlags) => ({ ...currentFlags, [flag]: event.target.checked }))
                        }
                        type="checkbox"
                      />
                      {flag.replace('is', '')}
                    </label>
                  ))}
                </div>
                <div className="grid max-h-64 gap-2 overflow-auto pr-1">
                  {categories.map((category) => (
                    <div
                      className="flex items-center justify-between gap-3 rounded-lg border border-stryv-line bg-black/30 px-3 py-2 text-sm"
                      key={category.id}
                    >
                      <div className="flex min-w-0 items-center gap-2">
                        <span className="h-2.5 w-2.5 shrink-0 rounded-full" style={{ background: category.color }} />
                        <span className="truncate font-semibold text-white">{category.name}</span>
                      </div>
                      <span className="text-xs font-bold uppercase text-stryv-muted">
                        {category.is_work ? 'Work' : category.is_distracting ? 'Distract' : category.is_break ? 'Break' : 'Other'}
                      </span>
                    </div>
                  ))}
                </div>
              </div>
            </Panel>

            <Panel title="Rules" icon={<ListTree size={18} />}>
              <div className="grid gap-3">
                <div className="grid gap-3 sm:grid-cols-[140px_minmax(0,1fr)]">
                  <ThemeSelect
                    onChange={(value) =>
                      setRuleMatchType(value as 'app_name' | 'executable_path' | 'window_title')
                    }
                    options={[
                      { label: 'Window title', value: 'window_title' },
                      { label: 'App name', value: 'app_name' },
                      { label: 'Executable', value: 'executable_path' },
                    ]}
                    value={ruleMatchType}
                  />
                  <input
                    className="h-10 rounded-lg border border-stryv-line bg-black/40 px-3 text-sm text-white outline-none focus:border-stryv-orange/60"
                    onChange={(event) => setRulePattern(event.target.value)}
                    placeholder="youtube.com, TikTok, Slack"
                    value={rulePattern}
                  />
                </div>
                <div className="grid gap-3 sm:grid-cols-[minmax(0,1fr)_auto]">
                  <ThemeSelect
                    onChange={(value) => setRuleCategoryId(Number(value))}
                    options={categories.map((category) => ({
                      label: category.name,
                      value: String(category.id),
                    }))}
                    value={ruleCategoryId ? String(ruleCategoryId) : ''}
                  />
                  <button
                    className="h-10 rounded-lg border border-stryv-orange/40 px-4 text-sm font-bold text-stryv-orange hover:border-stryv-orange/70"
                    onClick={createNewRule}
                    type="button"
                  >
                    Add Rule
                  </button>
                </div>
                <div className="grid max-h-64 gap-2 overflow-auto pr-1">
                  {rules.length > 0 ? (
                    rules.map((rule) => (
                      <button
                        className="grid rounded-lg border border-stryv-line bg-black/30 px-3 py-2 text-left text-sm hover:border-stryv-orange/40"
                        key={rule.id}
                        onClick={() => {
                          void toggleRule(rule);
                        }}
                        type="button"
                      >
                        <span className="font-semibold text-white">{rule.pattern}</span>
                        <span className="mt-1 text-xs text-stryv-muted">
                          {rule.match_type} {'->'} {rule.category_name} · {rule.is_enabled ? 'enabled' : 'disabled'}
                        </span>
                      </button>
                    ))
                  ) : (
                    <EmptyState text="No classification rules yet." />
                  )}
                </div>
              </div>
            </Panel>
              </section>
              <section className="rounded-lg border border-stryv-line bg-stryv-panel p-5">
                <h3 className="text-base font-bold text-white">Local Data</h3>
                <dl className="mt-4 grid gap-3 text-sm">
                  <InfoRow label="Database file" value={databaseStatus?.path ?? 'Preparing local database...'} />
                  <InfoRow label="Poll interval" value={trackerStatus ? `${trackerStatus.pollIntervalSeconds}s` : '5s'} />
                  <InfoRow label="Idle threshold" value={trackerStatus ? `${trackerStatus.idleThresholdSeconds}s` : '300s'} />
                </dl>
              </section>
            </section>
          )}
        </section>
      </div>
    </main>
  );
}

function AppSidebar({
  activePage,
  isCollapsed,
  onNavigate,
  onToggle,
}: {
  activePage: AppPage;
  isCollapsed: boolean;
  onNavigate: (page: AppPage) => void;
  onToggle: () => void;
}) {
  return (
    <aside className="border-b border-stryv-line bg-black/95 px-3 pb-4 pt-12 lg:min-h-screen lg:border-b-0 lg:border-r">
      <div className="flex items-center justify-between">
        {!isCollapsed ? (
          <span className="px-2 text-xs font-bold uppercase tracking-normal text-stryv-muted">Navigation</span>
        ) : null}
        <button
          aria-label={isCollapsed ? 'Expand sidebar' : 'Collapse sidebar'}
          className="grid h-10 w-10 place-items-center rounded-lg border border-stryv-line text-stryv-muted hover:border-stryv-orange/45 hover:text-white"
          onClick={onToggle}
          type="button"
        >
          <Menu size={18} />
        </button>
      </div>
      <nav className="mt-4 grid gap-2" aria-label="Primary">
        <SidebarButton
          icon={<Activity size={18} />}
          isActive={activePage === 'home'}
          isCollapsed={isCollapsed}
          label="Today"
          onClick={() => onNavigate('home')}
        />
        <SidebarButton
          icon={<Settings size={18} />}
          isActive={activePage === 'config'}
          isCollapsed={isCollapsed}
          label="Config"
          onClick={() => onNavigate('config')}
        />
      </nav>
    </aside>
  );
}

function SidebarButton({
  icon,
  isActive,
  isCollapsed,
  label,
  onClick,
}: {
  icon: React.ReactNode;
  isActive: boolean;
  isCollapsed: boolean;
  label: string;
  onClick: () => void;
}) {
  return (
    <button
      className={`flex h-11 items-center gap-3 rounded-lg border px-3 text-sm font-bold transition ${
        isActive
          ? 'border-stryv-orange/35 bg-gradient-to-r from-stryv-ember/25 via-stryv-orange/10 to-transparent text-stryv-orange'
          : 'border-transparent text-stryv-muted hover:bg-stryv-elevated hover:text-white'
      } ${isCollapsed ? 'justify-center' : 'justify-start'}`}
      onClick={onClick}
      title={isCollapsed ? label : undefined}
      type="button"
    >
      <span className="shrink-0">{icon}</span>
      {!isCollapsed ? <span className="truncate">{label}</span> : null}
    </button>
  );
}

function HomePage({
  calendarBlocks,
  categorySummary,
  databaseStatus,
  today,
  topDuration,
}: {
  calendarBlocks: CalendarBlock[];
  categorySummary: CategorySummaryItem[];
  databaseStatus: DatabaseStatus | null;
  today: TodayDashboard;
  topDuration: number;
}) {
  return (
    <>
      <section className="mt-6 grid gap-4 md:grid-cols-2 xl:grid-cols-4" aria-label="Daily metrics">
        <MetricCard icon={<Timer size={20} />} label="Tracked Today" value={formatDuration(today.totalTrackedSeconds)} />
        <MetricCard icon={<Activity size={20} />} label="Active Time" value={formatDuration(today.activeSeconds)} />
        <MetricCard icon={<Moon size={20} />} label="Idle Time" value={formatDuration(today.idleSeconds)} />
        <MetricCard icon={<Clock size={20} />} label="Break Time" value={formatDuration(today.breakSeconds)} />
      </section>

      <section className="mt-6 grid min-w-0 gap-5 xl:grid-cols-[minmax(0,1fr)_330px]">
        <Panel title="Day Calendar" icon={<CalendarIcon />}>
          <DayCalendar blocks={calendarBlocks} />
        </Panel>
        <div className="grid content-start gap-5">
          <DailySummary categorySummary={categorySummary} today={today} />
          <Panel title="Current Session" icon={<Flame size={18} />}>
            <div className="min-w-0">
              <p className="truncate text-2xl font-bold text-white">{today.current.appName}</p>
              <p className="mt-2 line-clamp-2 text-sm leading-6 text-stryv-muted">
                {today.current.windowTitle ?? 'Waiting for the next active window sample.'}
              </p>
            </div>
            <div className="mt-5 grid gap-3 text-sm">
              <InfoRow label="Duration" value={formatDuration(today.current.durationSeconds)} />
              <InfoRow label="Category" value={today.current.categoryName ?? 'Uncategorized'} />
              <InfoRow label="Database" value={databaseStatus ? `Schema v${databaseStatus.schemaVersion}` : 'Preparing'} />
            </div>
          </Panel>
          <Panel title="Top Apps" icon={<BarChart3 size={18} />}>
            <div className="grid gap-3">
              {today.topApps.length > 0 ? (
                today.topApps.map((app) => (
                  <div key={app.appName} className="grid gap-2">
                    <div className="flex items-center justify-between gap-3 text-sm">
                      <span className="min-w-0 truncate font-semibold text-white">{app.appName}</span>
                      <span className="whitespace-nowrap text-stryv-muted">{formatDuration(app.durationSeconds)}</span>
                    </div>
                    <div className="h-2 overflow-hidden rounded-full bg-stryv-elevated">
                      <div
                        className="h-full rounded-full bg-gradient-to-r from-stryv-ember via-stryv-orange to-stryv-amber shadow-neon"
                        style={{ width: `${Math.max(6, (app.durationSeconds / topDuration) * 100)}%` }}
                      />
                    </div>
                  </div>
                ))
              ) : (
                <EmptyState text="No app usage recorded today yet." />
              )}
            </div>
          </Panel>
        </div>
      </section>
    </>
  );
}

function CalendarIcon() {
  return <Clock size={18} />;
}

function DayCalendar({ blocks }: { blocks: CalendarBlock[] }) {
  const hours = Array.from({ length: 24 }, (_, index) => index);

  return (
    <div className="relative h-[1440px] overflow-hidden rounded-lg border border-stryv-line bg-black/35">
      <div className="absolute inset-0 grid" style={{ gridTemplateRows: 'repeat(24, minmax(0, 1fr))' }}>
        {hours.map((hour) => (
          <div className="border-t border-stryv-line/70" key={hour}>
            <span className="ml-3 -translate-y-2 bg-black/60 px-2 text-[11px] font-bold text-stryv-muted">
              {formatHour(hour)}
            </span>
          </div>
        ))}
      </div>
      <div className="absolute bottom-0 left-20 right-4 top-0">
        {blocks.map((block) => (
          <article
            className="absolute left-0 right-0 overflow-hidden rounded-md border border-stryv-orange/35 bg-stryv-elevated px-3 py-2"
            key={block.id}
            style={{
              borderLeft: `4px solid ${block.color}`,
              top: `${block.topPercent}%`,
              height: `${block.heightPercent}%`,
            }}
          >
            <div className="absolute inset-0 opacity-20" style={{ background: block.color }} />
            <div className="relative min-w-0">
              <p className="truncate text-xs font-bold text-white">{block.title}</p>
              <p className="mt-1 truncate text-[11px] font-semibold text-stryv-text/80">
                {formatTime(block.startedAt)} - {block.endedAt ? formatTime(block.endedAt) : 'Now'}
              </p>
            </div>
          </article>
        ))}
      </div>
      {blocks.length === 0 ? (
        <div className="absolute inset-0 grid place-items-center px-6 text-center text-sm text-stryv-muted">
          No activity blocks recorded for today yet.
        </div>
      ) : null}
    </div>
  );
}

function DailySummary({
  categorySummary,
  today,
}: {
  categorySummary: CategorySummaryItem[];
  today: TodayDashboard;
}) {
  const total = Math.max(today.activeSeconds + today.idleSeconds, 1);

  return (
    <Panel title="Daily Summary" icon={<BarChart3 size={18} />}>
      <div className="grid gap-4">
        <div className="grid grid-cols-2 gap-3">
          <SummaryStat label="Tracked" value={formatDuration(today.totalTrackedSeconds)} />
          <SummaryStat label="Active" value={formatDuration(today.activeSeconds)} />
        </div>
        <div className="grid gap-3">
          {categorySummary.length > 0 ? (
            categorySummary.map((item) => (
              <div className="grid gap-2" key={item.name}>
                <div className="flex items-center justify-between gap-3 text-sm">
                  <span className="flex min-w-0 items-center gap-2">
                    <span className="h-2.5 w-2.5 shrink-0 rounded-full" style={{ background: item.color }} />
                    <span className="truncate font-semibold text-white">{item.name}</span>
                  </span>
                  <span className="whitespace-nowrap text-stryv-muted">{formatDuration(item.durationSeconds)}</span>
                </div>
                <div className="h-2 overflow-hidden rounded-full bg-stryv-elevated">
                  <div
                    className="h-full rounded-full"
                    style={{ background: item.color, width: `${Math.max(5, (item.durationSeconds / total) * 100)}%` }}
                  />
                </div>
              </div>
            ))
          ) : (
            <EmptyState text="No category summary yet." />
          )}
        </div>
      </div>
    </Panel>
  );
}

function SummaryStat({ label, value }: { label: string; value: string }) {
  return (
    <div className="rounded-lg border border-stryv-line bg-black/30 p-3">
      <p className="text-[11px] font-bold uppercase text-stryv-muted">{label}</p>
      <p className="mt-1 text-lg font-bold text-white">{value}</p>
    </div>
  );
}

function MetricCard({ icon, label, value }: { icon: React.ReactNode; label: string; value: string }) {
  return (
    <article className="rounded-lg border border-stryv-line bg-stryv-panel p-5 shadow-[0_18px_40px_rgba(0,0,0,0.28)]">
      <div className="flex items-center justify-between gap-3 text-stryv-orange">
        {icon}
        <span className="h-2 w-2 rounded-full bg-gradient-to-br from-stryv-amber to-stryv-ember shadow-neon" />
      </div>
      <p className="mt-5 text-xs font-bold uppercase text-stryv-muted">{label}</p>
      <strong className="mt-2 block text-2xl font-bold tracking-normal text-white">{value}</strong>
    </article>
  );
}

function WindowControls() {
  const [isVisible, setIsVisible] = useState(false);

  useEffect(() => {
    return window.stryv?.onWindowChromeHoverChanged(setIsVisible);
  }, []);

  const minimize = () => {
    void window.stryv?.minimizeWindow();
  };

  const toggleMaximize = () => {
    void window.stryv?.toggleMaximizeWindow();
  };

  const closeToTray = () => {
    void window.stryv?.closeWindowToTray();
  };

  return (
    <div
      className={`fixed inset-x-0 top-0 z-50 h-12 bg-gradient-to-b to-transparent transition-colors duration-150 [-webkit-app-region:drag] ${
        isVisible ? 'from-stryv-elevated/75' : 'from-stryv-elevated/0'
      }`}
    >
      <div
        className={`absolute right-3 top-2 flex gap-1 transition-all duration-150 [-webkit-app-region:no-drag] ${
          isVisible ? 'translate-y-0 opacity-100' : 'translate-y-[-2px] opacity-0'
        }`}
      >
        <button
          aria-label="Minimize"
          className="grid h-7 w-9 place-items-center rounded-md text-stryv-muted/80 hover:bg-white/10 hover:text-white"
          onClick={minimize}
          type="button"
        >
          <Minus size={14} />
        </button>
        <button
          aria-label="Maximize"
          className="grid h-7 w-9 place-items-center rounded-md text-stryv-muted/80 hover:bg-white/10 hover:text-white"
          onClick={toggleMaximize}
          type="button"
        >
          <Maximize2 size={13} />
        </button>
        <button
          aria-label="Close to tray"
          className="grid h-7 w-9 place-items-center rounded-md text-stryv-muted/80 hover:bg-stryv-ember/70 hover:text-white"
          onClick={closeToTray}
          type="button"
        >
          <X size={14} />
        </button>
      </div>
    </div>
  );
}

function Panel({
  children,
  className = '',
  icon,
  id,
  title,
}: {
  children: React.ReactNode;
  className?: string;
  icon: React.ReactNode;
  id?: string;
  title: string;
}) {
  return (
    <section className={`min-w-0 rounded-lg border border-stryv-line bg-stryv-panel p-5 ${className}`} id={id}>
      <div className="mb-5 flex items-center gap-2 text-white">
        <span className="text-stryv-orange">{icon}</span>
        <h3 className="text-base font-bold">{title}</h3>
      </div>
      {children}
    </section>
  );
}

function StatusPill({ active = false, icon, label }: { active?: boolean; icon: React.ReactNode; label: string }) {
  return (
    <div
      className={`inline-flex h-9 items-center gap-2 rounded-full border px-3 text-sm font-bold ${
        active
          ? 'border-stryv-orange/50 bg-stryv-orange/10 text-stryv-orange'
          : 'border-stryv-line bg-stryv-panel text-stryv-muted'
      }`}
    >
      {icon}
      {label}
    </div>
  );
}

function ThemeSelect({
  onChange,
  options,
  value,
}: {
  onChange: (value: string) => void;
  options: SelectOption[];
  value: string;
}) {
  const [isOpen, setIsOpen] = useState(false);
  const selectedOption = options.find((option) => option.value === value);

  return (
    <div
      className="relative min-w-0"
      onBlur={(event) => {
        if (!event.currentTarget.contains(event.relatedTarget)) {
          setIsOpen(false);
        }
      }}
    >
      <button
        aria-expanded={isOpen}
        className={`flex h-10 w-full min-w-0 items-center justify-between gap-3 rounded-lg border bg-black/45 px-3 text-left text-sm text-white outline-none transition ${
          isOpen
            ? 'border-stryv-orange/65 shadow-[0_0_0_3px_rgba(232,88,26,0.14)]'
            : 'border-stryv-line hover:border-stryv-orange/35'
        }`}
        onClick={() => setIsOpen((current) => !current)}
        type="button"
      >
        <span className={selectedOption ? 'truncate' : 'truncate text-stryv-muted'}>
          {selectedOption?.label ?? 'Select'}
        </span>
        <ChevronDown
          className={`shrink-0 text-stryv-orange transition-transform ${isOpen ? 'rotate-180' : ''}`}
          size={16}
        />
      </button>

      {isOpen ? (
        <div className="absolute left-0 right-0 top-[calc(100%+8px)] z-40 overflow-hidden rounded-lg border border-stryv-orange/35 bg-[#090909] shadow-[0_18px_42px_rgba(0,0,0,0.58),0_0_28px_rgba(232,88,26,0.12)]">
          <div className="max-h-60 overflow-auto p-1">
            {options.map((option) => {
              const isSelected = option.value === value;

              return (
                <button
                  className={`flex h-9 w-full items-center justify-between gap-3 rounded-md px-3 text-left text-sm transition ${
                    isSelected
                      ? 'bg-gradient-to-r from-stryv-ember/45 via-stryv-orange/25 to-transparent text-white'
                      : 'text-stryv-text hover:bg-stryv-elevated hover:text-white'
                  }`}
                  key={option.value}
                  onClick={() => {
                    onChange(option.value);
                    setIsOpen(false);
                  }}
                  type="button"
                >
                  <span className="min-w-0 truncate">{option.label}</span>
                  {isSelected ? <Check className="shrink-0 text-stryv-orange" size={15} /> : null}
                </button>
              );
            })}
          </div>
        </div>
      ) : null}
    </div>
  );
}

function InfoRow({ label, value }: { label: string; value: string }) {
  return (
    <div className="grid gap-1 border-t border-stryv-line pt-3 sm:grid-cols-[132px_minmax(0,1fr)] sm:gap-4">
      <dt className="text-xs font-bold uppercase text-stryv-muted">{label}</dt>
      <dd className="min-w-0 overflow-wrap-anywhere text-stryv-text [overflow-wrap:anywhere]">{value}</dd>
    </div>
  );
}

function EmptyState({ text }: { text: string }) {
  return (
    <div className="rounded-lg border border-dashed border-stryv-line bg-black/30 p-5 text-sm text-stryv-muted">
      {text}
    </div>
  );
}

function getCategorySummary(today: TodayDashboard): CategorySummaryItem[] {
  const durations = new Map<string, CategorySummaryItem>();

  const sessions = [...today.timeline].sort((a, b) => Date.parse(a.startedAt) - Date.parse(b.startedAt));

  for (const session of sessions) {
    const name = session.categoryName ?? (session.isIdle ? 'Idle' : 'Uncategorized');
    const color = session.categoryColor ?? (session.isIdle ? '#737373' : '#a3a3a3');
    const current = durations.get(name);

    durations.set(name, {
      name,
      color,
      durationSeconds: (current?.durationSeconds ?? 0) + session.durationSeconds,
    });
  }

  return [...durations.values()].sort((a, b) => b.durationSeconds - a.durationSeconds);
}

function getCalendarBlocks(today: TodayDashboard): CalendarBlock[] {
  const dayStart = new Date(`${today.day}T00:00:00`);
  const dayEnd = new Date(dayStart);
  dayEnd.setDate(dayEnd.getDate() + 1);
  const totalDayMs = dayEnd.getTime() - dayStart.getTime();
  const blocks: CalendarBlock[] = [];
  let currentSpan: {
    categories: Set<string>;
    endedAt: string | null;
    startedAt: string;
  } | null = null;

  const flushSpan = () => {
    if (!currentSpan) {
      return;
    }

    const startedAt = Math.max(Date.parse(currentSpan.startedAt), dayStart.getTime());
    const endedAt = Math.min(Date.parse(currentSpan.endedAt ?? new Date().toISOString()), dayEnd.getTime());
    const durationMs = Math.max(60 * 1000, endedAt - startedAt);
    const categories = [...currentSpan.categories];

    blocks.push({
      id: `${currentSpan.startedAt}-${currentSpan.endedAt ?? 'now'}`,
      title: categories.length > 0 ? categories.join(', ') : 'Uncategorized',
      startedAt: currentSpan.startedAt,
      endedAt: currentSpan.endedAt,
      color: '#e8581a',
      topPercent: ((startedAt - dayStart.getTime()) / totalDayMs) * 100,
      heightPercent: Math.min(100, (durationMs / totalDayMs) * 100),
    });

    currentSpan = null;
  };

  const sessions = [...today.timeline].sort((a, b) => Date.parse(a.startedAt) - Date.parse(b.startedAt));

  for (const session of sessions) {
    if (session.isIdle) {
      flushSpan();
      continue;
    }

    if (!currentSpan) {
      currentSpan = {
        categories: new Set(),
        endedAt: session.endedAt,
        startedAt: session.startedAt,
      };
    }

    currentSpan.categories.add(session.categoryName ?? 'Uncategorized');
    currentSpan.endedAt = session.endedAt;
  }

  flushSpan();

  return blocks;
}

function formatDuration(totalSeconds: number): string {
  const seconds = Math.max(0, Math.floor(totalSeconds));
  const hours = Math.floor(seconds / 3600);
  const minutes = Math.floor((seconds % 3600) / 60);

  if (hours > 0) {
    return `${hours}h ${String(minutes).padStart(2, '0')}m`;
  }

  return `${minutes}m`;
}

function formatHour(hour: number): string {
  if (hour === 0) {
    return '12 AM';
  }

  if (hour < 12) {
    return `${hour} AM`;
  }

  if (hour === 12) {
    return '12 PM';
  }

  return `${hour - 12} PM`;
}

function formatTime(iso: string): string {
  return new Intl.DateTimeFormat(undefined, {
    hour: '2-digit',
    minute: '2-digit',
  }).format(new Date(iso));
}
