part of 'hud.dart';

class _Picker extends StatelessWidget {
  const _Picker();

  @override
  Widget build(BuildContext context) => WorldBuilder<(TowerKind, int)>(
    select: (world) =>
        (world.resource<BuildChoice>().kind, world.resource<Gold>().value),
    builder: (context, state) {
      final (chosen, gold) = state;
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final kind in TowerKind.values)
            _PickerButton(
              kind: kind,
              chosen: kind == chosen,
              affordable: gold >= kind.cost,
            ),
        ],
      );
    },
  );
}

class const _PickerButton({
  required final TowerKind kind,
  required final bool chosen,
  required final bool affordable,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 6),
    child: Opacity(
      opacity: affordable ? 1 : 0.4,
      child: ChoiceChip(
        selected: chosen,
        onSelected: (_) => context.world.resource<BuildChoice>().kind = kind,
        label: Text('${kind.label}  ${kind.cost}'),
      ),
    ),
  );
}
