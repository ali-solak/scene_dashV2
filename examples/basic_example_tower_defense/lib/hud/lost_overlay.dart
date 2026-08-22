part of 'hud.dart';

class _LostOverlay extends StatelessWidget {
  const _LostOverlay();

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: const Color(0xCC05070B),
    child: Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'they got through',
            style: TextStyle(fontSize: 30, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: () => context.world.setState(GameStatus.playing),
            child: const Text('play again'),
          ),
        ],
      ),
    ),
  );
}
