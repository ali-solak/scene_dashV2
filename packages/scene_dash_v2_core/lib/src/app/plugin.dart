import 'app_builder.dart';

/// Registers one app feature.
abstract base class Plugin {
  const Plugin();

  /// Plugins that must be added first.
  List<Type> get dependencies => const <Type>[];

  /// Registers this plugin's systems, events and resources on [app].
  void build(AppBuilder app);
}
