import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

/// 密码圆点指示器
class PinDots extends StatelessWidget {
  const PinDots({
    super.key,
    required this.filled,
    this.length = 6,
    this.error = false,
    this.dense = false,
  });

  final int filled;
  final int length;
  final bool error;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final size = dense ? 11.0 : 13.0;
    final activeColor = error ? scheme.error : AppColors.seed;

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(length, (i) {
        final on = i < filled;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          curve: Curves.easeOut,
          margin: EdgeInsets.symmetric(horizontal: dense ? 6 : 8),
          width: on ? size : size,
          height: on ? size : size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: on ? activeColor : Colors.transparent,
            border: Border.all(
              color: on ? activeColor : scheme.outlineVariant,
              width: 1.6,
            ),
          ),
        );
      }),
    );
  }
}

/// 数字键盘：1-9 0 + 可选指纹键 + 退格
class PinPad extends StatelessWidget {
  const PinPad({
    super.key,
    required this.onDigit,
    required this.onBackspace,
    this.onBiometric,
    this.biometricBusy = false,
    this.enabled = true,
  });

  final ValueChanged<String> onDigit;
  final VoidCallback onBackspace;
  final VoidCallback? onBiometric;
  final bool biometricBusy;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final row in const [
          ['1', '2', '3'],
          ['4', '5', '6'],
          ['7', '8', '9'],
        ])
          _row(context, row.map((d) => _key(context, d)).toList()),
        _row(context, [
          if (onBiometric != null)
            _actionKey(
              context,
              icon: Icons.fingerprint_rounded,
              onTap: enabled && !biometricBusy ? onBiometric : null,
              highlighted: true,
              busy: biometricBusy,
            )
          else
            const SizedBox(width: _KeySize.box, height: _KeySize.box),
          _key(context, '0'),
          _actionKey(
            context,
            icon: Icons.backspace_outlined,
            onTap: enabled ? onBackspace : null,
          ),
        ]),
      ],
    );
  }

  Widget _row(BuildContext context, List<Widget> children) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) const SizedBox(width: 26),
            children[i],
          ],
        ],
      ),
    );
  }

  Widget _key(BuildContext context, String digit) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      width: _KeySize.box,
      height: _KeySize.box,
      child: Material(
        color: enabled
            ? scheme.surfaceContainerHighest.withValues(alpha: 0.6)
            : scheme.surfaceContainerHighest.withValues(alpha: 0.25),
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: enabled ? () => onDigit(digit) : null,
          child: Center(
            child: Text(
              digit,
              style: TextStyle(
                fontSize: 25,
                fontWeight: FontWeight.w600,
                color: enabled
                    ? scheme.onSurface
                    : scheme.onSurface.withValues(alpha: 0.35),
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _actionKey(
    BuildContext context, {
    required IconData icon,
    required VoidCallback? onTap,
    bool highlighted = false,
    bool busy = false,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final color = highlighted ? AppColors.seed : scheme.onSurfaceVariant;
    return SizedBox(
      width: _KeySize.box,
      height: _KeySize.box,
      child: Material(
        color: highlighted
            ? AppColors.seed.withValues(alpha: 0.12)
            : Colors.transparent,
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Center(
            child: busy
                ? SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.2,
                      valueColor: AlwaysStoppedAnimation(color),
                    ),
                  )
                : Icon(icon, size: 26, color: color),
          ),
        ),
      ),
    );
  }
}

class _KeySize {
  static const double box = 68;
}
