import 'package:flutter_test/flutter_test.dart';
import 'package:scene_game/collectables/data/config.dart';
import 'package:scene_game/player/data/config.dart';
import 'package:scene_game/projectiles/data/config.dart';

/// Pure-function coverage for the charge -> projectile/impact scaling helpers.
void main() {
  test('a burst pellet (charge 0) keeps the unscaled values', () {
    expect(projectileHitRadiusForCharge(0), projectileHitRadius);
    expect(projectileKnockbackForCharge(0), projectileKnockback);
    expect(projectileLiftForCharge(0), projectileLift);
    expect(projectileSpinForCharge(0), projectileBaseSpin);
  });

  test('projectile scale grows from min to max with charge', () {
    expect(chargedProjectileScale(0), chargedProjectileMinScale);
    expect(chargedProjectileScale(1), chargedProjectileMaxScale);
    expect(
      chargedProjectileScale(0.5),
      closeTo(
        (chargedProjectileMinScale + chargedProjectileMaxScale) / 2,
        1e-9,
      ),
    );
  });

  test('hit radius scales between the charged min and max', () {
    expect(
      projectileHitRadiusForCharge(0.0001),
      greaterThan(projectileHitRadius),
    );
    expect(
      projectileHitRadiusForCharge(1),
      closeTo(chargedProjectileMaxHitRadius, 1e-9),
    );
  });

  test('knockback, lift and spin rise with charge and are bounded', () {
    expect(projectileKnockbackForCharge(1), chargedProjectileMaxKnockback);
    expect(projectileLiftForCharge(1), chargedProjectileMaxLift);
    expect(projectileSpinForCharge(1), chargedProjectileMaxSpin);
    // Over-range charge clamps rather than extrapolating.
    expect(projectileKnockbackForCharge(2), chargedProjectileMaxKnockback);
  });

  test('charged values exceed burst values', () {
    expect(
      projectileKnockbackForCharge(1),
      greaterThan(projectileKnockbackForCharge(0)),
    );
    expect(projectileLiftForCharge(1), greaterThan(projectileLiftForCharge(0)));
    expect(projectileSpinForCharge(1), greaterThan(projectileSpinForCharge(0)));
  });

  test('shield collection distance covers the player + pickup radii', () {
    // The squared collect distance must be at least the touching distance.
    final touching = (playerCollisionRadius + collectableRadius);
    expect(shieldCollectDistanceSq, greaterThan(touching * touching));
  });
}
