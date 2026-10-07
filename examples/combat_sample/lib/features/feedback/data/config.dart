part of '../feedback.dart';

const double hitFlashSeconds = 0.1;
const double lightHitPauseSeconds = 0.035;
const double hitPauseSeconds = 0.07;

const double recoilSettleSeconds = 0.45;
const double lightRecoil = 0.6;
const double finisherRecoil = 1.0;
const double heavyRecoil = 0.8;
const double killRecoil = 1.3;

double recoilFor(DamageDealt hit) {
  if (hit.killed) return killRecoil;
  return switch (hit.weight) {
    HitWeight.light => lightRecoil,
    HitWeight.finisher => finisherRecoil,
    HitWeight.heavy => heavyRecoil,
  };
}

const double comboTimeoutSeconds = 2.2;

const int shockwaveDustPuffs = 6;
const double shockwaveTrauma = 0.2;

const double damageNumberSeconds = 0.8;
const double damageNumberHeight = 2.3;
const double damageNumberRise = 1.1;
const double damageNumberSpread = 0.5;
const double damageNumberPopSeconds = 0.12;
const double damageNumberPop = 0.6;
const Size damageNumberCanvas = Size(220, 110);
const double damageNumberWorldHeight = 0.6;
