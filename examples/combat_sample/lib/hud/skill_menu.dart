/// The pause screen: spend what the run has earned. The world is frozen
/// behind it (the menu is a [GameStatus], not an overlay with a flag).
/// A light "shop" panel with its own warm-cream palette: it is the one
/// screen you sit and read, so it gets to feel like a workbench.
library;

import 'package:flutter/foundation.dart' show immutable, listEquals;
import 'package:flutter/material.dart';
import 'package:scene_dash_v2/scene_dash_v2.dart';

import '../game/game_state.dart';
import '../game/score.dart';
import '../skills/skills.dart';
import '../world/data/config.dart' show qualityPresets;
import '../world/data/resources.dart' show GraphicsQuality, QualityRequested;
import 'leaves.dart';

// --- The shop's palette (light; local to this screen) ---
const _cream = Color(0xFFF4EFE4);
const _card = Color(0xFFFEFCF7);
const _ink = Color(0xFF4A4034);
const _inkSoft = Color(0xFF9C9080);
const _hair = Color(0xFFE4DCCC);
const _gold = Color(0xFFF2C14E);
const _goldDeep = Color(0xFFDBA43A);
const _green = Color(0xFF84C24E);
const _greenDeep = Color(0xFF6FB03E);

/// Points, vitality level and what is already owned: everything the menu
/// needs to decide what is affordable. A value type, so `WorldBuilder`
/// rebuilds only on real change.
@immutable
final class _MenuState {
  const _MenuState(this.points, this.vitality, this.levels, this.quality);

  final int points;
  final int vitality;

  /// Level per skill, in `Skill.values` order. 0 = not bought.
  final List<int> levels;

  /// Live quality preset index, so the active chip reads as selected.
  final int quality;

  @override
  bool operator ==(Object other) =>
      other is _MenuState &&
      points == other.points &&
      vitality == other.vitality &&
      quality == other.quality &&
      listEquals(levels, other.levels);

  @override
  int get hashCode =>
      Object.hash(points, vitality, quality, Object.hashAll(levels));
}

_MenuState _selectMenu(World world) {
  final book = world.resource<SkillBook>();
  return _MenuState(world.resource<Score>().points, book.vitalityLevel, [
    for (final skill in Skill.values) book.levelOf(skill),
  ], world.resource<GraphicsQuality>().level);
}

/// One thing you can buy (a skill or vitality), flattened so the node grid
/// and the detail card read the same source.
@immutable
class _Item {
  const _Item({
    required this.name,
    required this.tag,
    required this.blurb,
    required this.color,
    required this.icon,
    required this.level,
    required this.maxLevel,
    required this.cost,
    required this.onBuy,
  });

  final String name;

  /// A short flavour word for the detail card's tag pill (GUARD, BLAZE…).
  final String tag;
  final String blurb;
  final Color color;
  final IconData icon;
  final int level;
  final int maxLevel;
  final int cost;
  final VoidCallback onBuy;

  bool get owned => level > 0;
  bool get maxed => level >= maxLevel;
}

class SkillMenu extends StatefulWidget {
  const SkillMenu({super.key});

  @override
  State<SkillMenu> createState() => _SkillMenuState();
}

class _SkillMenuState extends State<SkillMenu> {
  /// Which item the detail card shows. Local UI state; the world only
  /// cares what you buy, not what you are looking at.
  int _selected = 0;

  List<_Item> _items(BuildContext context, _MenuState state) {
    _Item forSkill(
      Skill skill, {
      required String tag,
      required Color color,
      required IconData icon,
    }) {
      final level = state.levels[skill.index];
      return _Item(
        name: skill.label,
        tag: tag,
        blurb: skill.blurb,
        color: color,
        icon: icon,
        level: level,
        maxLevel: maxSkillLevel,
        cost: skill.costAt(level),
        onBuy: () => GameScope.of(context).emit(SkillUpgradeRequested(skill)),
      );
    }

    return [
      forSkill(
        Skill.fireGush,
        tag: 'BLAZE',
        color: const Color(0xFFFF7A2B),
        icon: Icons.local_fire_department,
      ),
      forSkill(
        Skill.lavaPit,
        tag: 'MOLTEN',
        color: const Color(0xFFE24A28),
        icon: Icons.volcano,
      ),
      forSkill(
        Skill.windBlast,
        tag: 'GALE',
        color: const Color(0xFF2FB6C4),
        icon: Icons.cyclone,
      ),
      forSkill(
        Skill.shield,
        tag: 'GUARD',
        color: const Color(0xFF5B8DEF),
        icon: Icons.shield,
      ),
      _Item(
        name: 'VITALITY',
        tag: 'VIGOR',
        blurb:
            'Raises your health by '
            '${vitalityHealthPerLevel.toStringAsFixed(0)} '
            'and heals you for it now.',
        color: const Color(0xFFEB6A6A),
        icon: Icons.favorite,
        level: state.vitality,
        maxLevel: maxVitalityLevel,
        cost: vitalityCost(state.vitality),
        onBuy: () => GameScope.of(context).emit(const VitalityRequested()),
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return WorldBuilder<_MenuState>(
      select: _selectMenu,
      builder: (context, state) {
        final items = _items(context, state);
        final selected = items[_selected.clamp(0, items.length - 1)];
        // A phone in landscape has little height to spare, so a short
        // screen gets a tighter panel (smaller header, nodes and card)
        // that fits the grid and detail side by side without scrolling.
        final compact = MediaQuery.sizeOf(context).height < 560;
        return Stack(
          fit: StackFit.expand,
          children: [
            ColoredBox(
              color: const Color(0x55201A12),
              child: SafeArea(
                child: Center(
                  child: Padding(
                    padding: EdgeInsets.all(compact ? 8 : 14),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 1000),
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: _cream,
                          borderRadius: BorderRadius.circular(28),
                          boxShadow: const [
                            BoxShadow(
                              color: Color(0x33000000),
                              blurRadius: 40,
                              offset: Offset(0, 18),
                            ),
                          ],
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _Header(points: state.points, compact: compact),
                            const _Dashed(),
                            Flexible(
                              child: SingleChildScrollView(
                                padding: EdgeInsets.fromLTRB(
                                  compact ? 18 : 26,
                                  compact ? 14 : 22,
                                  compact ? 18 : 26,
                                  compact ? 14 : 22,
                                ),
                                child: LayoutBuilder(
                                  builder: (context, c) => _Body(
                                    wide: c.maxWidth >= 640,
                                    compact: compact,
                                    items: items,
                                    selectedIndex: _selected,
                                    selected: selected,
                                    points: state.points,
                                    quality: state.quality,
                                    onPick: (i) =>
                                        setState(() => _selected = i),
                                  ),
                                ),
                              ),
                            ),
                            const _Dashed(),
                            const _Footer(),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const Positioned.fill(child: IgnorePointer(child: Leaves())),
          ],
        );
      },
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({
    required this.wide,
    required this.compact,
    required this.items,
    required this.selectedIndex,
    required this.selected,
    required this.points,
    required this.quality,
    required this.onPick,
  });

  final bool wide;
  final bool compact;
  final List<_Item> items;
  final int selectedIndex;
  final _Item selected;
  final int points;
  final int quality;
  final ValueChanged<int> onPick;

  @override
  Widget build(BuildContext context) {
    final grid = Wrap(
      spacing: compact ? 12 : 20,
      runSpacing: compact ? 12 : 18,
      children: [
        for (var i = 0; i < items.length; i++)
          _Node(
            item: items[i],
            selected: i == selectedIndex,
            compact: compact,
            onTap: () => onPick(i),
          ),
      ],
    );
    final qualityStrip = _QualityStrip(level: quality);
    final card = _DetailCard(item: selected, points: points, compact: compact);
    final gap = compact ? 14.0 : 20.0;

    if (!wide) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(child: grid),
          SizedBox(height: gap),
          card,
          SizedBox(height: gap),
          qualityStrip,
        ],
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              grid,
              SizedBox(height: gap),
              qualityStrip,
            ],
          ),
        ),
        SizedBox(width: compact ? 16 : 24),
        SizedBox(width: compact ? 248 : 288, child: card),
      ],
    );
  }
}

/// "Skills" on the left, the coin purse on the right.
class _Header extends StatelessWidget {
  const _Header({required this.points, required this.compact});

  final int points;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        compact ? 22 : 30,
        compact ? 16 : 24,
        compact ? 16 : 22,
        compact ? 12 : 18,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Text(
              'Skills',
              style: TextStyle(
                color: _ink,
                fontSize: compact ? 26 : 34,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.5,
                height: 1,
              ),
            ),
          ),
          _PointsBadge(points: points),
        ],
      ),
    );
  }
}

class _PointsBadge extends StatelessWidget {
  const _PointsBadge({required this.points});

  final int points;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 8, 18, 8),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(30),
        boxShadow: const [
          BoxShadow(
            color: Color(0x14000000),
            blurRadius: 10,
            offset: Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const _Coin(size: 30, letter: 'P'),
          const SizedBox(width: 10),
          Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '$points',
                style: const TextStyle(
                  color: _ink,
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  height: 1,
                ),
              ),
              const Text(
                'POINTS',
                style: TextStyle(
                  color: _inkSoft,
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.5,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// A ringed skill token: the icon in its element colour, the name and price
/// under it, a corner badge with the level once you own one.
class _Node extends StatelessWidget {
  const _Node({
    required this.item,
    required this.selected,
    required this.compact,
    required this.onTap,
  });

  final _Item item;
  final bool selected;
  final bool compact;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = item.color;
    final ring = compact ? 56.0 : 70.0;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: compact ? 78 : 92,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  width: ring,
                  height: ring,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: selected ? c.withValues(alpha: 0.12) : _card,
                    border: Border.all(color: c, width: selected ? 4 : 3),
                    boxShadow: [
                      if (selected)
                        BoxShadow(
                          color: c.withValues(alpha: 0.38),
                          blurRadius: 16,
                          spreadRadius: 1,
                        )
                      else
                        const BoxShadow(
                          color: Color(0x14000000),
                          blurRadius: 8,
                          offset: Offset(0, 3),
                        ),
                    ],
                  ),
                  child: Icon(item.icon, color: c, size: compact ? 26 : 32),
                ),
                if (item.owned)
                  Positioned(
                    top: -3,
                    right: -3,
                    child: _LevelBadge(item: item),
                  ),
              ],
            ),
            SizedBox(height: compact ? 6 : 9),
            Text(
              item.name,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: _ink,
                fontSize: 13,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.2,
                height: 1.1,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              item.maxed ? 'MAX' : '${item.cost} PTS',
              style: TextStyle(
                color: item.maxed ? _greenDeep : _inkSoft,
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The little corner coin on an owned node: its level, or a tick at max.
class _LevelBadge extends StatelessWidget {
  const _LevelBadge({required this.item});

  final _Item item;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 22,
      height: 22,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: item.maxed ? _greenDeep : item.color,
        border: Border.all(color: _cream, width: 2),
      ),
      child: item.maxed
          ? const Icon(Icons.check, size: 11, color: Colors.white)
          : Text(
              '${item.level}',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.w800,
                height: 1,
              ),
            ),
    );
  }
}

/// The selected item, laid out to be read: tag, a big token, the name and
/// what it does, then the price and the one button that spends points.
class _DetailCard extends StatelessWidget {
  const _DetailCard({
    required this.item,
    required this.points,
    required this.compact,
  });

  final _Item item;
  final int points;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final c = item.color;
    final affordable = !item.maxed && points >= item.cost;
    return Container(
      padding: EdgeInsets.fromLTRB(
        compact ? 18 : 22,
        compact ? 14 : 20,
        compact ? 18 : 22,
        compact ? 14 : 20,
      ),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(22),
        boxShadow: const [
          BoxShadow(
            color: Color(0x1A000000),
            blurRadius: 22,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          _Tag(text: item.tag, color: c, icon: item.icon),
          SizedBox(height: compact ? 12 : 18),
          Container(
            width: compact ? 74 : 96,
            height: compact ? 74 : 96,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: c.withValues(alpha: 0.14),
              border: Border.all(color: c, width: 3),
            ),
            child: Icon(item.icon, color: c, size: compact ? 36 : 46),
          ),
          SizedBox(height: compact ? 10 : 16),
          Text(
            item.name,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: _ink,
              fontSize: compact ? 19 : 22,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            item.blurb,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: _inkSoft,
              fontSize: 13,
              height: 1.4,
              fontWeight: FontWeight.w500,
            ),
          ),
          SizedBox(height: compact ? 12 : 18),
          if (item.maxed)
            const Text(
              'FULLY UPGRADED',
              style: TextStyle(
                color: _greenDeep,
                fontSize: 12,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.5,
              ),
            )
          else
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const _Coin(size: 22),
                const SizedBox(width: 8),
                Text(
                  '${item.cost}',
                  style: const TextStyle(
                    color: _ink,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(width: 6),
                const Text(
                  'POINTS',
                  style: TextStyle(
                    color: _inkSoft,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.5,
                  ),
                ),
              ],
            ),
          SizedBox(height: compact ? 10 : 14),
          _BuyButton(
            color: c,
            label: item.maxed ? 'MAXED' : (item.owned ? 'UPGRADE' : 'UNLOCK'),
            enabled: affordable,
            onTap: item.onBuy,
          ),
        ],
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag({required this.text, required this.color, required this.icon});

  final String text;
  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 6),
          Text(
            text,
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}

class _BuyButton extends StatelessWidget {
  const _BuyButton({
    required this.color,
    required this.label,
    required this.enabled,
    required this.onTap,
  });

  final Color color;
  final String label;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: GestureDetector(
        onTap: enabled ? onTap : null,
        behavior: HitTestBehavior.opaque,
        child: Container(
          height: 46,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: enabled ? color : const Color(0xFFE7E0D2),
            borderRadius: BorderRadius.circular(23),
            boxShadow: enabled
                ? [
                    BoxShadow(
                      color: color.withValues(alpha: 0.4),
                      blurRadius: 14,
                      offset: const Offset(0, 6),
                    ),
                  ]
                : null,
          ),
          child: Text(
            label,
            style: TextStyle(
              color: enabled ? Colors.white : _inkSoft,
              fontSize: 14,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.5,
            ),
          ),
        ),
      ),
    );
  }
}

/// The graphics dial: a quiet chip row under the grid.
class _QualityStrip extends StatelessWidget {
  const _QualityStrip({required this.level});

  final int level;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        const Padding(
          padding: EdgeInsets.only(right: 4),
          child: Text(
            'GRAPHICS',
            style: TextStyle(
              color: _inkSoft,
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.5,
            ),
          ),
        ),
        for (var i = 0; i < qualityPresets.length; i++)
          _QualityChip(
            label: qualityPresets[i].label,
            selected: i == level,
            onTap: () => GameScope.of(context).emit(QualityRequested(i)),
          ),
      ],
    );
  }
}

class _QualityChip extends StatelessWidget {
  const _QualityChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? _ink : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: selected ? _ink : _hair, width: 1.5),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? _cream : _inkSoft,
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 1,
          ),
        ),
      ),
    );
  }
}

class _Footer extends StatelessWidget {
  const _Footer();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(26, 14, 20, 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          _EscHint(onTap: () => _close(context)),
          _Cta(onTap: () => _close(context)),
        ],
      ),
    );
  }

  void _close(BuildContext context) =>
      GameScope.of(context).emit(const SkillMenuToggled());
}

class _EscHint extends StatelessWidget {
  const _EscHint({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: _card,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: _hair, width: 1.5),
        ),
        child: RichText(
          text: const TextSpan(
            children: [
              TextSpan(
                text: 'ESC',
                style: TextStyle(
                  color: _ink,
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1,
                ),
              ),
              TextSpan(
                text: '  to close',
                style: TextStyle(
                  color: _inkSoft,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Cta extends StatelessWidget {
  const _Cta({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 13),
        decoration: BoxDecoration(
          gradient: const LinearGradient(colors: [_green, _greenDeep]),
          borderRadius: BorderRadius.circular(24),
          boxShadow: const [
            BoxShadow(
              color: Color(0x556FB03E),
              blurRadius: 16,
              offset: Offset(0, 6),
            ),
          ],
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Back to the Fight',
              style: TextStyle(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.w800,
              ),
            ),
            SizedBox(width: 8),
            Icon(Icons.arrow_forward_rounded, color: Colors.white, size: 20),
          ],
        ),
      ),
    );
  }
}

/// A gold coin, the purse's and the price's shared unit. Optional [letter]
/// stamps it (the header's "P").
class _Coin extends StatelessWidget {
  const _Coin({required this.size, this.letter});

  final double size;
  final String? letter;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [_gold, _goldDeep],
        ),
      ),
      child: letter == null
          ? null
          : Text(
              letter!,
              style: TextStyle(
                color: Colors.white,
                fontSize: size * 0.5,
                fontWeight: FontWeight.w800,
                height: 1,
              ),
            ),
    );
  }
}

/// A thin dashed rule in the panel's own hairline colour.
class _Dashed extends StatelessWidget {
  const _Dashed();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 22),
      child: CustomPaint(
        size: const Size(double.infinity, 1.4),
        painter: _DashPainter(),
      ),
    );
  }
}

class _DashPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = _hair
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round;
    const dash = 5.0;
    const gap = 5.0;
    for (var x = 0.0; x < size.width; x += dash + gap) {
      canvas.drawLine(Offset(x, 0), Offset(x + dash, 0), paint);
    }
  }

  @override
  bool shouldRepaint(_DashPainter oldDelegate) => false;
}
