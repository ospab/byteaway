import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../app/di.dart';
import '../../core/constants.dart';
import '../theme/app_theme.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final PageController _pageController = PageController();
  int _index = 0;
  bool _saving = false;

  static const List<_SlideData> _slides = [
    _SlideData(
      icon: Icons.wifi_tethering_rounded,
      title: 'Как работает сервис',
      description:
          'ByteAway использует только ту часть интернета, которой вы не пользуетесь в данный момент.',
    ),
    _SlideData(
      icon: Icons.touch_app_rounded,
      title: 'Что делаете вы',
      description:
          'Вы включаете режим узла в приложении, а мы автоматически следим за условиями и безопасной работой.',
    ),
    _SlideData(
      icon: Icons.workspace_premium_rounded,
      title: 'Что вы получаете',
      description:
          'За активность узла вы получаете доступ к VPN-трафику и используете сервис без сложной настройки.',
    ),
  ];

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _finish() async {
    if (_saving) return;
    setState(() => _saving = true);
    final prefs = sl<SharedPreferences>();
    await prefs.setBool(AppConstants.onboardingDoneKey, true);
    if (!mounted) return;
    context.go('/login');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final isTabletLike = constraints.maxWidth >= 900;
            final horizontalPadding = isTabletLike ? 56.0 : 20.0;
            final cardWidth = isTabletLike ? 760.0 : 600.0;

            return Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: cardWidth),
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                    horizontalPadding,
                    18,
                    horizontalPadding,
                    16,
                  ),
                  child: Column(
                    children: [
                      Expanded(
                        child: PageView.builder(
                          controller: _pageController,
                          itemCount: _slides.length,
                          onPageChanged: (value) {
                            setState(() => _index = value);
                          },
                          itemBuilder: (context, i) {
                            final slide = _slides[i];
                            return _SlideCard(data: slide);
                          },
                        ),
                      ),
                      const SizedBox(height: 20),
                      Row(
                        children: [
                          Expanded(
                            child: Wrap(
                              spacing: 8,
                              children: List.generate(
                                _slides.length,
                                (i) => AnimatedContainer(
                                  duration: const Duration(milliseconds: 220),
                                  width: i == _index ? 28 : 10,
                                  height: 10,
                                  decoration: BoxDecoration(
                                    color: i == _index
                                        ? AppTheme.primary
                                        : Colors.white24,
                                    borderRadius: BorderRadius.circular(999),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          TextButton(
                            onPressed: _saving ? null : _finish,
                            child: const Text('Пропустить'),
                          ),
                          const SizedBox(width: 8),
                          SizedBox(
                            height: 48,
                            child: ElevatedButton(
                              onPressed: _saving
                                  ? null
                                  : () {
                                      if (_index == _slides.length - 1) {
                                        _finish();
                                      } else {
                                        _pageController.nextPage(
                                          duration:
                                              const Duration(milliseconds: 260),
                                          curve: Curves.easeOut,
                                        );
                                      }
                                    },
                              child: Text(
                                _index == _slides.length - 1
                                    ? 'Перейти к входу'
                                    : 'Далее',
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _SlideCard extends StatelessWidget {
  final _SlideData data;

  const _SlideCard({required this.data});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0x2018B2A1), Color(0x144D5C9A)],
        ),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: AppTheme.primary.withOpacity(0.18),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Icon(data.icon, color: AppTheme.primary, size: 34),
          ),
          const Spacer(),
          Text(
            data.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  color: AppTheme.textPrimary,
                  fontWeight: FontWeight.w800,
                ),
          ),
          const SizedBox(height: 12),
          Text(
            data.description,
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: AppTheme.textSecondary,
                  height: 1.45,
                ),
          ),
        ],
      ),
    );
  }
}

class _SlideData {
  final IconData icon;
  final String title;
  final String description;

  const _SlideData({
    required this.icon,
    required this.title,
    required this.description,
  });
}
