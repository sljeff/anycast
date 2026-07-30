import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

void main() => runApp(const SentryDashboardApp());

class SentryDashboardApp extends StatelessWidget {
  const SentryDashboardApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Anycast Development Feedback',
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: _Colors.background,
        colorScheme: ColorScheme.fromSeed(
          seedColor: _Colors.accent,
          brightness: Brightness.dark,
          surface: _Colors.surface,
        ),
      ),
      home: const SentryDashboardPage(),
    );
  }
}

class SentryDashboardPage extends StatefulWidget {
  const SentryDashboardPage({super.key});

  @override
  State<SentryDashboardPage> createState() => _SentryDashboardPageState();
}

class _SentryDashboardPageState extends State<SentryDashboardPage> {
  var _periodIndex = 0;
  var _issueView = _IssueView.impact;

  static const _periods = [
    _PeriodData(
      label: '24H',
      events: 8,
      users: 1,
      issues: 3,
      chart: [0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 2, 5],
      axisLabels: ['00', '06', '12', '18', 'NOW'],
    ),
    _PeriodData(
      label: '7D',
      events: 27,
      users: 9,
      issues: 9,
      chart: [6, 2, 3, 5, 2, 1, 8],
      axisLabels: ['JUL 23', '25', '27', '29', 'NOW'],
    ),
    _PeriodData(
      label: '30D',
      events: 92,
      users: 17,
      issues: 15,
      chart: [4, 7, 6, 9, 8, 11, 15, 32],
      axisLabels: ['JUL 01', '08', '15', '22', 'NOW'],
    ),
  ];

  static const _issues = [
    _IssueData(
      id: 'ANYCAST-NM',
      title: 'FormatException: Unexpected character in search response',
      culprit: 'podcasts.dart · searchEpisodes',
      events: 44,
      users: 4,
      lastSeen: '2026-07-24T12:58:32Z',
      lastSeenLabel: 'Jul 24 · 12:58 UTC',
      state: 'ONGOING',
      url: 'https://kindjeff.sentry.io/issues/7513518762/',
    ),
    _IssueData(
      id: 'ANYCAST-NY',
      title: 'StateError: Bad state — Too many elements',
      culprit: 'player.dart · PageTabButton.build',
      events: 11,
      users: 1,
      lastSeen: '2026-07-08T21:21:25Z',
      lastSeenLabel: 'Jul 08 · 21:21 UTC',
      state: 'ONGOING',
      url: 'https://kindjeff.sentry.io/issues/7566250062/',
    ),
    _IssueData(
      id: 'ANYCAST-K2',
      title: 'TypeError: Null check operator used on a null value',
      culprit: 'QueryResultSet · root',
      events: 8,
      users: 3,
      lastSeen: '2026-07-27T17:14:09Z',
      lastSeenLabel: 'Jul 27 · 17:14 UTC',
      state: 'ONGOING',
      url: 'https://kindjeff.sentry.io/issues/6191874568/',
    ),
    _IssueData(
      id: 'ANYCAST-K3',
      title: 'CachedNetworkImage timed out loading artwork',
      culprit: 'PlatformDispatcher._dispatchError',
      events: 6,
      users: 5,
      lastSeen: '2026-07-28T02:26:06Z',
      lastSeenLabel: 'Jul 28 · 02:26 UTC',
      state: 'ONGOING',
      url: 'https://kindjeff.sentry.io/issues/6193352446/',
    ),
    _IssueData(
      id: 'ANYCAST-NS',
      title: 'App Hanging: main thread blocked for at least 2000 ms',
      culprit: 'iOS · timer callback',
      events: 4,
      users: 1,
      lastSeen: '2026-07-09T17:13:07Z',
      lastSeenLabel: 'Jul 09 · 17:13 UTC',
      state: 'ONGOING',
      url: 'https://kindjeff.sentry.io/issues/7563454975/',
    ),
    _IssueData(
      id: 'ANYCAST-Q1',
      title: 'WatchdogTermination: possible excessive RAM usage',
      culprit: 'iOS watchdog',
      events: 3,
      users: 1,
      lastSeen: '2026-07-30T01:49:08Z',
      lastSeenLabel: 'Jul 30 · 01:49 UTC',
      state: 'NEW',
      url: 'https://kindjeff.sentry.io/issues/7641393080/',
    ),
    _IssueData(
      id: 'ANYCAST-NK',
      title: 'Google Fonts failed because fonts.gstatic.com was unreachable',
      culprit: 'google_fonts_base.dart · _httpFetchFontAndSaveToDevice',
      events: 3,
      users: 1,
      lastSeen: '2026-07-30T01:32:22Z',
      lastSeenLabel: 'Jul 30 · 01:32 UTC',
      state: 'ONGOING',
      url: 'https://kindjeff.sentry.io/issues/7513514284/',
    ),
    _IssueData(
      id: 'ANYCAST-NH',
      title: 'pthread_exit',
      culprit: 'iOS runtime',
      events: 3,
      users: 2,
      lastSeen: '2026-07-24T06:22:27Z',
      lastSeenLabel: 'Jul 24 · 06:22 UTC',
      state: 'ONGOING',
      url: 'https://kindjeff.sentry.io/issues/7470198744/',
    ),
    _IssueData(
      id: 'ANYCAST-Q0',
      title: 'Share sheet origin must be non-zero and within source view',
      culprit: 'method_channel_share.dart · MethodChannelShare.share',
      events: 2,
      users: 1,
      lastSeen: '2026-07-30T01:33:34Z',
      lastSeenLabel: 'Jul 30 · 01:33 UTC',
      state: 'NEW',
      url: 'https://kindjeff.sentry.io/issues/7641382815/',
    ),
    _IssueData(
      id: 'ANYCAST-PV',
      title: 'Audio source returned HTTP 404',
      culprit: 'PlatformDispatcher._dispatchError',
      events: 2,
      users: 1,
      lastSeen: '2026-07-09T17:08:52Z',
      lastSeenLabel: 'Jul 09 · 17:08 UTC',
      state: 'ONGOING',
      url: 'https://kindjeff.sentry.io/issues/7602313364/',
    ),
    _IssueData(
      id: 'ANYCAST-PZ',
      title: 'CardListController was not registered in GetX',
      culprit: 'get_instance.dart · GetInstance.find',
      events: 1,
      users: 1,
      lastSeen: '2026-07-27T17:14:22Z',
      lastSeenLabel: 'Jul 27 · 17:14 UTC',
      state: 'NEW',
      url: 'https://kindjeff.sentry.io/issues/7636270649/',
    ),
    _IssueData(
      id: 'ANYCAST-PY',
      title: 'RevenueCat logout failed while device was offline',
      culprit: 'purchases_flutter.dart · Purchases.logOut',
      events: 1,
      users: 1,
      lastSeen: '2026-07-24T02:22:35Z',
      lastSeenLabel: 'Jul 24 · 02:22 UTC',
      state: 'NEW',
      url: 'https://kindjeff.sentry.io/issues/7630130060/',
    ),
  ];

  List<_IssueData> get _visibleIssues {
    final issues = [..._issues];
    switch (_issueView) {
      case _IssueView.impact:
        issues.sort((a, b) => b.events.compareTo(a.events));
      case _IssueView.recent:
        issues.sort(
          (a, b) =>
              DateTime.parse(b.lastSeen).compareTo(DateTime.parse(a.lastSeen)),
        );
      case _IssueView.newIssues:
        issues.removeWhere((issue) => issue.state != 'NEW');
    }
    return issues;
  }

  @override
  Widget build(BuildContext context) {
    final period = _periods[_periodIndex];

    return Scaffold(
      body: LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= 1080;
          return Row(
            children: [
              if (wide) const _SideRail(),
              Expanded(
                child: SingleChildScrollView(
                  padding: EdgeInsets.fromLTRB(
                    wide ? 40 : 20,
                    30,
                    wide ? 40 : 20,
                    52,
                  ),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 1180),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _TopBar(
                            periodIndex: _periodIndex,
                            onPeriodChanged: (value) {
                              setState(() => _periodIndex = value);
                            },
                          ),
                          const SizedBox(height: 30),
                          _MetricGrid(period: period),
                          const SizedBox(height: 18),
                          if (constraints.maxWidth >= 850)
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  flex: 2,
                                  child: _TrendPanel(period: period),
                                ),
                                const SizedBox(width: 18),
                                const Expanded(child: _CoveragePanel()),
                              ],
                            )
                          else
                            Column(
                              children: [
                                _TrendPanel(period: period),
                                const SizedBox(height: 18),
                                const _CoveragePanel(),
                              ],
                            ),
                          const SizedBox(height: 30),
                          _IssueHeader(
                            view: _issueView,
                            onChanged: (view) {
                              setState(() => _issueView = view);
                            },
                          ),
                          const SizedBox(height: 12),
                          _IssueList(issues: _visibleIssues),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _SideRail extends StatelessWidget {
  const _SideRail();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 224,
      padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
      decoration: const BoxDecoration(
        color: _Colors.rail,
        border: Border(right: BorderSide(color: _Colors.line)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              _LogoMark(),
              SizedBox(width: 12),
              Text(
                'ANYCAST',
                style: TextStyle(
                  color: _Colors.text,
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.8,
                ),
              ),
            ],
          ),
          const SizedBox(height: 44),
          const _RailItem(
            icon: Icons.monitor_heart_outlined,
            label: 'Development',
            selected: true,
          ),
          const _RailItem(icon: Icons.bug_report_outlined, label: 'Issues'),
          const _RailItem(icon: Icons.speed_outlined, label: 'Performance'),
          const _RailItem(icon: Icons.forum_outlined, label: 'User feedback'),
          const Spacer(),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: _Colors.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: _Colors.line),
            ),
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'DATA SOURCE',
                  style: TextStyle(
                    color: _Colors.muted,
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.4,
                  ),
                ),
                SizedBox(height: 8),
                Row(
                  children: [
                    _StatusDot(color: _Colors.good),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Sentry connected',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: _Colors.text, fontSize: 12),
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 6),
                Text(
                  'kindjeff / anycast',
                  style: TextStyle(color: _Colors.muted, fontSize: 11),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _LogoMark extends StatelessWidget {
  const _LogoMark();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 34,
      height: 34,
      decoration: BoxDecoration(
        color: _Colors.accent,
        borderRadius: BorderRadius.circular(11),
      ),
      child:
          const Icon(Icons.graphic_eq_rounded, color: Colors.black, size: 20),
    );
  }
}

class _RailItem extends StatelessWidget {
  const _RailItem({
    required this.icon,
    required this.label,
    this.selected = false,
  });

  final IconData icon;
  final String label;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      decoration: BoxDecoration(
        color: selected ? _Colors.accentSoft : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(icon,
              size: 19, color: selected ? _Colors.accent : _Colors.muted),
          const SizedBox(width: 11),
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: selected ? _Colors.text : _Colors.muted,
                fontSize: 13,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.periodIndex,
    required this.onPeriodChanged,
  });

  final int periodIndex;
  final ValueChanged<int> onPeriodChanged;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 24,
      runSpacing: 20,
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.end,
      children: [
        const SizedBox(
          width: 600,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    'APP DEVELOPMENT FEEDBACK',
                    style: TextStyle(
                      color: _Colors.accent,
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 2,
                    ),
                  ),
                  SizedBox(width: 10),
                  _LiveBadge(),
                ],
              ),
              SizedBox(height: 11),
              Text(
                'What is the app\ntrying to tell us?',
                style: TextStyle(
                  color: _Colors.text,
                  fontSize: 42,
                  height: 1.02,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -1.8,
                ),
              ),
              SizedBox(height: 12),
              Text(
                'Sentry snapshot · synced Jul 29, 2026 at 20:37 PDT',
                style: TextStyle(color: _Colors.muted, fontSize: 12),
              ),
            ],
          ),
        ),
        SegmentedButton<int>(
          segments: const [
            ButtonSegment(value: 0, label: Text('24H')),
            ButtonSegment(value: 1, label: Text('7D')),
            ButtonSegment(value: 2, label: Text('30D')),
          ],
          selected: {periodIndex},
          showSelectedIcon: false,
          onSelectionChanged: (selection) => onPeriodChanged(selection.first),
          style: ButtonStyle(
            foregroundColor: WidgetStateProperty.resolveWith(
              (states) => states.contains(WidgetState.selected)
                  ? Colors.black
                  : _Colors.muted,
            ),
            backgroundColor: WidgetStateProperty.resolveWith(
              (states) => states.contains(WidgetState.selected)
                  ? _Colors.text
                  : _Colors.surface,
            ),
            side: const WidgetStatePropertyAll(
              BorderSide(color: _Colors.line),
            ),
          ),
        ),
      ],
    );
  }
}

class _LiveBadge extends StatelessWidget {
  const _LiveBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: _Colors.goodSoft,
        borderRadius: BorderRadius.circular(999),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _StatusDot(color: _Colors.good),
          SizedBox(width: 6),
          Text(
            'CONNECTED',
            style: TextStyle(
              color: _Colors.good,
              fontSize: 9,
              fontWeight: FontWeight.w800,
              letterSpacing: 1,
            ),
          ),
        ],
      ),
    );
  }
}

class _MetricGrid extends StatelessWidget {
  const _MetricGrid({required this.period});

  final _PeriodData period;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 900 ? 4 : 2;
        final width = (constraints.maxWidth - (columns - 1) * 12) / columns;
        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            _MetricCard(
              width: width,
              label: 'ERROR EVENTS',
              value: '${period.events}',
              note: period.label == '24H'
                  ? 'Latest window'
                  : '${period.label} total',
              accent: _Colors.danger,
            ),
            _MetricCard(
              width: width,
              label: 'AFFECTED USERS',
              value: '${period.users}',
              note: 'Unique Sentry users',
              accent: _Colors.warning,
            ),
            _MetricCard(
              width: width,
              label: 'ACTIVE ISSUES',
              value: '${period.issues}',
              note: 'Seen in this period',
              accent: _Colors.accent,
            ),
            _MetricCard(
              width: width,
              label: 'USER FEEDBACK',
              value: '0',
              note: 'Capture not configured',
              accent: _Colors.muted,
            ),
          ],
        );
      },
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.width,
    required this.label,
    required this.value,
    required this.note,
    required this.accent,
  });

  final double width;
  final String label;
  final String value;
  final String note;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      padding: const EdgeInsets.all(18),
      decoration: _panelDecoration,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _StatusDot(color: accent),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(
                    color: _Colors.muted,
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.35,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            value,
            style: const TextStyle(
              color: _Colors.text,
              fontSize: 34,
              height: 1,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          Text(note,
              style: const TextStyle(color: _Colors.muted, fontSize: 11)),
        ],
      ),
    );
  }
}

class _TrendPanel extends StatelessWidget {
  const _TrendPanel({required this.period});

  final _PeriodData period;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 280,
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
      decoration: _panelDecoration,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text(
                'EVENT ACTIVITY',
                style: _sectionLabelStyle,
              ),
              const Spacer(),
              Text(
                '${period.events} total / ${period.label}',
                style: const TextStyle(color: _Colors.muted, fontSize: 11),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Expanded(
            child: CustomPaint(
              painter: _ActivityPainter(values: period.chart),
              child: const SizedBox.expand(),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              for (final label in period.axisLabels)
                Text(
                  label,
                  style: const TextStyle(
                    color: _Colors.muted,
                    fontSize: 9,
                    letterSpacing: 0.8,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ActivityPainter extends CustomPainter {
  const _ActivityPainter({required this.values});

  final List<int> values;

  @override
  void paint(Canvas canvas, Size size) {
    final grid = Paint()
      ..color = _Colors.line
      ..strokeWidth = 1;
    for (var row = 0; row < 4; row++) {
      final y = size.height * row / 3;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }

    final maxValue = math.max(1, values.reduce(math.max));
    final slot = size.width / values.length;
    final barWidth = math.max(4.0, slot * 0.52);
    final paint = Paint();
    for (var index = 0; index < values.length; index++) {
      final ratio = values[index] / maxValue;
      final height = math.max(3.0, size.height * ratio);
      paint.color = index == values.length - 1
          ? _Colors.accent
          : _Colors.accent.withValues(alpha: 0.28 + ratio * 0.42);
      final left = slot * index + (slot - barWidth) / 2;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(left, size.height - height, barWidth, height),
          const Radius.circular(5),
        ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _ActivityPainter oldDelegate) {
    return oldDelegate.values != values;
  }
}

class _CoveragePanel extends StatelessWidget {
  const _CoveragePanel();

  @override
  Widget build(BuildContext context) {
    const signals = [
      ('Sessions', 'ON', _Colors.good),
      ('Profiles', 'ON', _Colors.good),
      ('Replays', 'OFF', _Colors.muted),
      ('User feedback', 'OFF', _Colors.warning),
    ];
    return Container(
      height: 280,
      padding: const EdgeInsets.all(20),
      decoration: _panelDecoration,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('SIGNAL COVERAGE', style: _sectionLabelStyle),
          const SizedBox(height: 8),
          const Text(
            'What Sentry can currently see',
            style: TextStyle(color: _Colors.muted, fontSize: 11),
          ),
          const SizedBox(height: 14),
          for (final signal in signals) ...[
            Expanded(
              child: Row(
                children: [
                  _StatusDot(color: signal.$3),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      signal.$1,
                      style: const TextStyle(color: _Colors.text, fontSize: 12),
                    ),
                  ),
                  Text(
                    signal.$2,
                    style: TextStyle(
                      color: signal.$3,
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.1,
                    ),
                  ),
                ],
              ),
            ),
            if (signal != signals.last)
              const Divider(color: _Colors.line, height: 1),
          ],
        ],
      ),
    );
  }
}

class _IssueHeader extends StatelessWidget {
  const _IssueHeader({required this.view, required this.onChanged});

  final _IssueView view;
  final ValueChanged<_IssueView> onChanged;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 18,
      runSpacing: 14,
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('PRIORITY QUEUE', style: _sectionLabelStyle),
            SizedBox(height: 6),
            Text(
              '15 unresolved issues · 4 marked new',
              style: TextStyle(color: _Colors.muted, fontSize: 11),
            ),
          ],
        ),
        SegmentedButton<_IssueView>(
          segments: const [
            ButtonSegment(value: _IssueView.impact, label: Text('Impact')),
            ButtonSegment(value: _IssueView.recent, label: Text('Recent')),
            ButtonSegment(value: _IssueView.newIssues, label: Text('New')),
          ],
          selected: {view},
          showSelectedIcon: false,
          onSelectionChanged: (selection) => onChanged(selection.first),
          style: ButtonStyle(
            visualDensity: VisualDensity.compact,
            foregroundColor: WidgetStateProperty.resolveWith(
              (states) => states.contains(WidgetState.selected)
                  ? _Colors.text
                  : _Colors.muted,
            ),
            backgroundColor: WidgetStateProperty.resolveWith(
              (states) => states.contains(WidgetState.selected)
                  ? _Colors.surfaceStrong
                  : _Colors.surface,
            ),
            side: const WidgetStatePropertyAll(
              BorderSide(color: _Colors.line),
            ),
          ),
        ),
      ],
    );
  }
}

class _IssueList extends StatelessWidget {
  const _IssueList({required this.issues});

  final List<_IssueData> issues;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: _panelDecoration,
      child: Column(
        children: [
          for (var index = 0; index < issues.length; index++) ...[
            _IssueRow(issue: issues[index]),
            if (index != issues.length - 1)
              const Divider(color: _Colors.line, height: 1),
          ],
        ],
      ),
    );
  }
}

class _IssueRow extends StatelessWidget {
  const _IssueRow({required this.issue});

  final _IssueData issue;

  Future<void> _openIssue() async {
    await launchUrl(Uri.parse(issue.url), webOnlyWindowName: '_blank');
  }

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 760;
    return InkWell(
      onTap: _openIssue,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 15),
        child: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: issue.state == 'NEW'
                    ? _Colors.accentSoft
                    : _Colors.surfaceStrong,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                issue.state == 'NEW'
                    ? Icons.new_releases_outlined
                    : Icons.error_outline_rounded,
                color: issue.state == 'NEW' ? _Colors.accent : _Colors.danger,
                size: 18,
              ),
            ),
            const SizedBox(width: 13),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        issue.id,
                        style: const TextStyle(
                          color: _Colors.accent,
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.8,
                        ),
                      ),
                      const SizedBox(width: 8),
                      _IssueState(state: issue.state),
                    ],
                  ),
                  const SizedBox(height: 5),
                  Text(
                    issue.title,
                    maxLines: compact ? 2 : 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: _Colors.text,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    issue.culprit,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: _Colors.muted, fontSize: 10),
                  ),
                ],
              ),
            ),
            if (!compact) ...[
              const SizedBox(width: 16),
              _IssueStat(value: '${issue.events}', label: 'EVENTS'),
              const SizedBox(width: 24),
              _IssueStat(value: '${issue.users}', label: 'USERS'),
              const SizedBox(width: 24),
              SizedBox(
                width: 118,
                child: Text(
                  issue.lastSeenLabel,
                  textAlign: TextAlign.right,
                  style: const TextStyle(color: _Colors.muted, fontSize: 10),
                ),
              ),
            ],
            const SizedBox(width: 12),
            const Icon(Icons.arrow_outward_rounded,
                color: _Colors.muted, size: 17),
          ],
        ),
      ),
    );
  }
}

class _IssueState extends StatelessWidget {
  const _IssueState({required this.state});

  final String state;

  @override
  Widget build(BuildContext context) {
    final isNew = state == 'NEW';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: isNew ? _Colors.accentSoft : _Colors.surfaceStrong,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        state,
        style: TextStyle(
          color: isNew ? _Colors.accent : _Colors.muted,
          fontSize: 8,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.7,
        ),
      ),
    );
  }
}

class _IssueStat extends StatelessWidget {
  const _IssueStat({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 45,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            value,
            style: const TextStyle(
              color: _Colors.text,
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
          Text(
            label,
            style: const TextStyle(
              color: _Colors.muted,
              fontSize: 8,
              letterSpacing: 0.8,
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusDot extends StatelessWidget {
  const _StatusDot({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 7,
      height: 7,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }
}

const _sectionLabelStyle = TextStyle(
  color: _Colors.text,
  fontSize: 10,
  fontWeight: FontWeight.w800,
  letterSpacing: 1.5,
);

final _panelDecoration = BoxDecoration(
  color: _Colors.surface,
  borderRadius: BorderRadius.circular(18),
  border: Border.all(color: _Colors.line),
);

enum _IssueView { impact, recent, newIssues }

class _PeriodData {
  const _PeriodData({
    required this.label,
    required this.events,
    required this.users,
    required this.issues,
    required this.chart,
    required this.axisLabels,
  });

  final String label;
  final int events;
  final int users;
  final int issues;
  final List<int> chart;
  final List<String> axisLabels;
}

class _IssueData {
  const _IssueData({
    required this.id,
    required this.title,
    required this.culprit,
    required this.events,
    required this.users,
    required this.lastSeen,
    required this.lastSeenLabel,
    required this.state,
    required this.url,
  });

  final String id;
  final String title;
  final String culprit;
  final int events;
  final int users;
  final String lastSeen;
  final String lastSeenLabel;
  final String state;
  final String url;
}

abstract final class _Colors {
  static const background = Color(0xFF0B0C0E);
  static const rail = Color(0xFF0E1013);
  static const surface = Color(0xFF14161A);
  static const surfaceStrong = Color(0xFF1D2025);
  static const line = Color(0xFF292D33);
  static const text = Color(0xFFF2EFE8);
  static const muted = Color(0xFF89909A);
  static const accent = Color(0xFFFF7A45);
  static const accentSoft = Color(0x24FF7A45);
  static const danger = Color(0xFFFF6B68);
  static const warning = Color(0xFFE5B65B);
  static const good = Color(0xFF63D69E);
  static const goodSoft = Color(0x1C63D69E);
}
