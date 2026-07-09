import 'app_builder.dart';

/// A class-based, explicit unit of feature registration.
///
/// A plugin groups the components, systems, resources and events that make up
/// one feature. Plugins are registered on the app and their [build] runs once,
/// receiving an [AppBuilder] to register everything they own. The `@GamePlugin`
/// annotation (Phase 2) adds a stable id, duplicate detection and dependency
/// validation, but the plugin still registers its systems explicitly here.
abstract base class Plugin {
  const Plugin();

  /// Other plugin types this plugin requires to have been added. Validated at
  /// build time. Defaults to none.
  List<Type> get dependencies => const <Type>[];

  /// Registers this plugin's systems, events and resources on [app].
  void build(AppBuilder app);
}
