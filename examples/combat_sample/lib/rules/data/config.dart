part of '../rules.dart';

/// Melee reach and frontal arcs. On this flat arena an overlap is just a
/// distance + arc check, so resolution stays pure Dart and runs headless.
/// The player's generous reach and wide half-arc (a hair past a right
/// angle) give one cleave its crowd-clearing sweep; the barbarians keep a
/// tighter arc so being flanked still matters.
const double playerReach = 3.4;
const double playerStrikeHalfArc = 1.7;

const double brawlerReach = 3.0;
const double brawlerStrikeHalfArc = 1.1;

/// How hard a barbarian's swing shoves the player.
const double brawlerKnockback = 5.0;

/// Poise: a hit only interrupts the player's action once it lands this
/// hard. An ordinary barbarian swing sits under it (you get hurt and
/// shoved, not cancelled) while a giant's blow breaks through.
const double playerPoiseThreshold = 24;

/// Chest height: where the spark burst blooms on a connect.
const double impactBurstHeight = 1.5;

/// Player connects punch the camera (consumed by the rig with decay). The
/// light gets a small one so a quick slice still lands with a bit of weight
/// now that there is no hitstop; the heavy hits harder.
const double lightCameraKick = 0.3;
const double heavyCameraKick = 0.75;

/// Player death drops the whole world into slow motion behind the
/// restart prompt (the clock's whole-world guarantee; the HUD, on wall
/// time, stays crisp).
const double loseSlowMoTimeScale = 0.32;
