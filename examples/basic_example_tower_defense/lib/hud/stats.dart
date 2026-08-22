part of 'hud.dart';

class _StatBar extends StatelessWidget {
  const _StatBar();

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: const Color(0xCC0B1017),
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: Colors.white12),
    ),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          WorldBuilder<int>(
            select: (world) => world.resource<Lives>().value,
            builder: (context, lives) =>
                _Stat('lives', '$lives', const Color(0xFFE86A64)),
          ),
          const _Divider(),
          WorldBuilder<int>(
            select: (world) => world.resource<Gold>().value,
            builder: (context, gold) =>
                _Stat('gold', '$gold', const Color(0xFFE8C46A)),
          ),
          const _Divider(),
          WorldBuilder<int>(
            select: (world) =>
                world.query<Health>(require: const [Creep]).count(),
            builder: (context, alive) =>
                _Stat('creeps', '$alive', const Color(0xFF7FC6F2)),
          ),
        ],
      ),
    ),
  );
}

class const _Stat(final String label, final String value, final Color color)
    extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        label,
        style: const TextStyle(
          color: Colors.white38,
          fontSize: 11,
          letterSpacing: 1.6,
        ),
      ),
      Text(
        value,
        style: TextStyle(
          color: color,
          fontSize: 24,
          fontWeight: FontWeight.w600,
          height: 1.1,
        ),
      ),
    ],
  );
}

class _Divider extends StatelessWidget {
  const _Divider();

  @override
  Widget build(BuildContext context) => Container(
    width: 1,
    height: 34,
    margin: const EdgeInsets.symmetric(horizontal: 20),
    color: Colors.white12,
  );
}

class _Hint extends StatelessWidget {
  const _Hint();

  @override
  Widget build(BuildContext context) => Text(
    'tap the ground beside the lane to build a tower  ·  $towerCost gold',
    style: TextStyle(color: Colors.white.withValues(alpha: 0.45), fontSize: 13),
  );
}
